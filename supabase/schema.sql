-- Tempus cloud backup — the whole server side.
--
-- One row per member, holding the same `AppModel.Stored` JSON that already lives in
-- UserDefaults. Deliberately not a mirror of Stored's fields: every field there is optional so an
-- old save keeps decoding when a new one lands, and columns would trade that property for a
-- migration on every release. Postgres never reads inside the blob, because only the app ever will.
--
-- Run in the Supabase dashboard ▸ SQL Editor. Safe to re-run.

create table if not exists public.backups (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  blob       jsonb       not null,
  updated_at timestamptz not null default now()
);

-- Without this every balance and flight log in the database is readable *and writable* by anyone
-- holding the anon key — which ships inside the app binary, so that is everyone who installs it.
alter table public.backups enable row level security;

-- Three policies rather than one `for all`, because the app upserts: PostgREST's
-- `resolution=merge-duplicates` needs insert AND update to be permitted, and a select to read a
-- restore back. Each is scoped to the caller's own row by auth.uid(), so a member can never name
-- someone else's user_id — the WITH CHECK is what stops a write claiming another id.
drop policy if exists "members read their own backup"   on public.backups;
drop policy if exists "members insert their own backup" on public.backups;
drop policy if exists "members update their own backup" on public.backups;

create policy "members read their own backup"
  on public.backups for select
  using (auth.uid() = user_id);

create policy "members insert their own backup"
  on public.backups for insert
  with check (auth.uid() = user_id);

create policy "members update their own backup"
  on public.backups for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- The shared bank, part one: invites that can actually be delivered.
--
-- `LinkedScreen` sends a *pending* request and shows "waiting for them to accept"; Status Club
-- shows an incoming one with Accept/Decline. All of that is built and works — it just has nowhere
-- to post to and nowhere to read from. These two tables are that somewhere.
--
-- What this does NOT do is share a balance. `link_pairs.miles` exists and stays 0: earning and
-- spending are still local, and `AppModel.pool` still excludes a pending link. Moving the balance
-- onto the server is a separate decision with a real cost on the client — see the note at the
-- bottom of this file.
--
-- Run in the Supabase dashboard ▸ SQL Editor. Safe to re-run.

create table if not exists public.link_invites (
  id          uuid primary key default gen_random_uuid(),
  from_user   uuid not null references auth.users (id) on delete cascade,
  from_name   text not null,
  to_email    text not null,
  to_name     text not null,
  created_at  timestamptz not null default now(),
  accepted_by uuid references auth.users (id) on delete cascade,
  accepted_at timestamptz,
  declined_at timestamptz
);

-- One OPEN invite per pair of people, not one invite ever.
--
-- A plain `unique (from_user, to_email)` — which is what this started as — is a trap: the row
-- survives being declined and being accepted, so a decline would permanently bar the sender from
-- ever inviting that person again, and unlinking would bar them from linking a second time. The
-- constraint has to cover only invites that are still awaiting an answer.
create unique index if not exists link_invites_open_uniq
  on public.link_invites (from_user, lower(to_email))
  where accepted_by is null and declined_at is null;

-- An invite is addressed by email, so the recipient is found by matching the JWT's own email
-- claim. Lower-cased on both sides: a member who signs up as Ada@… must still receive an invite
-- sent to ada@….
create index if not exists link_invites_to_email_idx
  on public.link_invites (lower(to_email))
  where accepted_by is null and declined_at is null;

create table if not exists public.link_pairs (
  id        uuid primary key default gen_random_uuid(),
  a_user    uuid not null references auth.users (id) on delete cascade,
  b_user    uuid not null references auth.users (id) on delete cascade,
  miles     integer not null default 0,
  linked_at timestamptz not null default now(),
  -- What stops one pair existing twice with its ends swapped. Every writer must order the two
  -- ids before inserting; `accept_link_invite` below is the only writer, and it does.
  check (a_user < b_user),
  unique (a_user, b_user)
);

alter table public.link_invites enable row level security;
alter table public.link_pairs   enable row level security;

-- Invites. The sender may create and read their own; the recipient may read one addressed to
-- their own email. Nobody may read an invite that is neither from nor to them — without this,
-- anyone holding the anon key (which ships inside the app binary) could enumerate every member's
-- email address in the database.
drop policy if exists "senders create their own invites"  on public.link_invites;
drop policy if exists "both ends read an invite"          on public.link_invites;
drop policy if exists "senders withdraw their invites"    on public.link_invites;

create policy "senders create their own invites"
  on public.link_invites for insert
  with check (auth.uid() = from_user);

create policy "both ends read an invite"
  on public.link_invites for select
  using (
    auth.uid() = from_user
    or lower(to_email) = lower(auth.jwt() ->> 'email')
  );

-- Withdrawing is a delete by the sender. Accepting and declining are NOT updates — they go
-- through the function below, so there is no update policy at all and a recipient cannot edit
-- an invite's fields on their way to accepting it.
create policy "senders withdraw their invites"
  on public.link_invites for delete
  using (auth.uid() = from_user);

-- Pairs are readable by their two members and writable by nobody: the only thing that creates a
-- pair is `accept_link_invite`, which runs as definer.
drop policy if exists "members read their own pair" on public.link_pairs;

create policy "members read their own pair"
  on public.link_pairs for select
  using (auth.uid() = a_user or auth.uid() = b_user);

-- Accepting is two writes that must both happen or neither: stamp the invite, create the pair.
-- A function is what makes that one transaction, and `security definer` is what lets it write
-- `link_pairs` when no policy permits an insert. It re-checks the caller is the addressee, so
-- being definer does not hand anyone else the table.
create or replace function public.accept_link_invite(invite uuid)
returns public.link_pairs
language plpgsql
security definer
set search_path = public
as $$
declare
  inv  public.link_invites;
  pair public.link_pairs;
  lo   uuid;
  hi   uuid;
begin
  select * into inv from public.link_invites
   where id = invite
     and accepted_by is null
     and declined_at is null
   for update;

  if not found then
    raise exception 'invite not open' using errcode = 'no_data_found';
  end if;

  if lower(inv.to_email) is distinct from lower(auth.jwt() ->> 'email') then
    raise exception 'not your invite' using errcode = 'insufficient_privilege';
  end if;

  if inv.from_user = auth.uid() then
    raise exception 'cannot link with yourself' using errcode = 'check_violation';
  end if;

  -- One bank each. `AppModel.link` is a single optional, so a member in two pairs is a state the
  -- app cannot represent — and a pot that two different partners could both spend from is not a
  -- shared bank, it is a leak. Checked for BOTH ends, because either may have linked with someone
  -- else in the time this invite sat unanswered.
  if exists (select 1 from public.link_pairs
              where a_user in (inv.from_user, auth.uid())
                 or b_user in (inv.from_user, auth.uid())) then
    raise exception 'already linked' using errcode = 'unique_violation';
  end if;

  update public.link_invites
     set accepted_by = auth.uid(), accepted_at = now()
   where id = inv.id;

  -- The check constraint wants them ordered, so order them here rather than trusting a caller.
  lo := least(inv.from_user, auth.uid());
  hi := greatest(inv.from_user, auth.uid());

  insert into public.link_pairs (a_user, b_user)
  values (lo, hi)
  on conflict (a_user, b_user) do update set linked_at = public.link_pairs.linked_at
  returning * into pair;

  return pair;
end;
$$;

create or replace function public.decline_link_invite(invite uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.link_invites
     set declined_at = now()
   where id = invite
     and accepted_by is null
     and lower(to_email) = lower(auth.jwt() ->> 'email');
$$;

revoke all on function public.accept_link_invite(uuid)  from public;
revoke all on function public.decline_link_invite(uuid) from public;
grant execute on function public.accept_link_invite(uuid)  to authenticated;
grant execute on function public.decline_link_invite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Part two: the balance itself.
--
-- **How the two balances divide.** Accepting a link moves nothing across — that is what
-- `LinkedScreen` has always promised, and it stays true. Each member keeps the personal balance
-- they already had; the pair gets a *shared pot* that starts empty and fills as either of them
-- lands. `AppModel.pool` is personal + pot, which is what every surface already displays, so no
-- screen has to learn a new number.
--
-- **Spending takes personal first, then the pot.** Personal miles cannot be raced — nobody else
-- can reach them — so that part stays synchronous and offline-capable. Only the shortfall is a
-- round-trip, and only that part can fail.
--
-- **The pot is where the race lives, and it is settled here, not on the client.** A conditional
-- update is atomic under Postgres's row lock: the `where miles >= amount` and the subtraction are
-- one statement, so two members spending the same 40 mi at the same moment cannot both succeed
-- however the clients behave. The loser gets an empty result, which is a refusal Redeem already
-- knows how to draw.

-- Two people sharing a bank have to be able to see where the miles went, or a balance that moves
-- while you are not looking is indistinguishable from a bug. Every movement of the pot writes a
-- line here, and both members can read all of it.
create table if not exists public.link_ledger (
  id      uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.link_pairs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  amount  integer not null,          -- positive credit, negative debit
  label   text    not null,
  at      timestamptz not null default now()
);

create index if not exists link_ledger_pair_idx on public.link_ledger (pair_id, at desc);

alter table public.link_ledger enable row level security;

drop policy if exists "members read their pair's ledger" on public.link_ledger;

create policy "members read their pair's ledger"
  on public.link_ledger for select
  using (exists (
    select 1 from public.link_pairs p
     where p.id = link_ledger.pair_id
       and (p.a_user = auth.uid() or p.b_user = auth.uid())
  ));

-- No insert policy: only the two functions below write the ledger, and they run as definer.

-- Spend from the pot. Returns the new balance, or NO ROW when there was not enough — which is the
-- refusal, not an error. `miles >= amount` inside the UPDATE is the whole concurrency story.
create or replace function public.spend_from_pair(pair uuid, amount integer, label text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining integer;
begin
  if amount <= 0 then
    raise exception 'amount must be positive' using errcode = 'check_violation';
  end if;

  update public.link_pairs
     set miles = miles - amount
   where id = pair
     and miles >= amount
     and (a_user = auth.uid() or b_user = auth.uid())
  returning miles into remaining;

  if not found then
    return null;                      -- not enough, and nothing moved
  end if;

  insert into public.link_ledger (pair_id, user_id, amount, label)
  values (pair, auth.uid(), -amount, label);

  return remaining;
end;
$$;

-- Credit the pot. A landing is the only caller, so this never fails on balance — but it is still
-- a single atomic statement, because two phones can land at the same moment.
create or replace function public.earn_to_pair(pair uuid, amount integer, label text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining integer;
begin
  if amount <= 0 then
    raise exception 'amount must be positive' using errcode = 'check_violation';
  end if;

  update public.link_pairs
     set miles = miles + amount
   where id = pair
     and (a_user = auth.uid() or b_user = auth.uid())
  returning miles into remaining;

  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  insert into public.link_ledger (pair_id, user_id, amount, label)
  values (pair, auth.uid(), amount, label);

  return remaining;
end;
$$;

-- Unlinking. Either member may, at any time — that is what the screen has always said. The pot is
-- split evenly rather than forfeited or handed to one side; the odd mile goes to whoever is still
-- holding the row's `a_user` slot, which is arbitrary and half a mile is not worth a rule.
-- The caller gets their share back to spend locally.
create or replace function public.unlink_pair(pair uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  p     public.link_pairs;
  share integer;
begin
  select * into p from public.link_pairs
   where id = pair and (a_user = auth.uid() or b_user = auth.uid())
   for update;

  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  share := p.miles / 2;
  if p.a_user = auth.uid() then
    share := p.miles - share;         -- the odd mile stays with a_user
  end if;

  delete from public.link_pairs where id = pair;
  return share;
end;
$$;

revoke all on function public.spend_from_pair(uuid, integer, text) from public;
revoke all on function public.earn_to_pair(uuid, integer, text)    from public;
revoke all on function public.unlink_pair(uuid)                    from public;
grant execute on function public.spend_from_pair(uuid, integer, text) to authenticated;
grant execute on function public.earn_to_pair(uuid, integer, text)    to authenticated;
grant execute on function public.unlink_pair(uuid)                    to authenticated;

-- ---------------------------------------------------------------------------
-- Part three: hardening, and deleting an account for real.
--
-- Everything the client can post is bounded here rather than trusted. None of these limits is a
-- feature — they are the ceilings a caller with the anon key and a curl command runs into, so
-- that "hacking" the shared bank amounts to nothing more than a rejected row.

-- A name shown to another member, an email an invite is addressed to, a label on the ledger:
-- each is display text with a sane maximum. `to_email` also has to look like an address, or
-- the recipient lookup (`lower(auth.jwt() ->> 'email')`) can never match it and the row is junk.
alter table public.link_invites drop constraint if exists link_invites_from_name_len;
alter table public.link_invites drop constraint if exists link_invites_to_name_len;
alter table public.link_invites drop constraint if exists link_invites_to_email_shape;
alter table public.link_invites
  add constraint link_invites_from_name_len  check (char_length(from_name) between 1 and 80),
  add constraint link_invites_to_name_len    check (char_length(to_name)   between 1 and 80),
  add constraint link_invites_to_email_shape check (
    char_length(to_email) <= 254 and to_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  );

alter table public.link_ledger drop constraint if exists link_ledger_label_len;
alter table public.link_ledger
  add constraint link_ledger_label_len check (char_length(label) between 1 and 80);

-- The backup is one member's save file — a few hundred KB at the very most. A megabyte is
-- already several times the largest real one; anything past it is not a backup.
alter table public.backups drop constraint if exists backups_blob_size;
alter table public.backups
  add constraint backups_blob_size check (pg_column_size(blob) <= 1048576);

-- A landing pays at most a few hundred miles (300 minutes at the top multiplier is well under
-- a thousand). A single credit past that is not a landing, whatever the client says.
create or replace function public.earn_to_pair(pair uuid, amount integer, label text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining integer;
begin
  if amount <= 0 or amount > 2000 then
    raise exception 'amount out of range' using errcode = 'check_violation';
  end if;

  update public.link_pairs
     set miles = miles + amount
   where id = pair
     and (a_user = auth.uid() or b_user = auth.uid())
  returning miles into remaining;

  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  insert into public.link_ledger (pair_id, user_id, amount, label)
  values (pair, auth.uid(), amount, label);

  return remaining;
end;
$$;

-- A member may erase their own backup row directly as well as through the function below. This
-- policy was missing: `Backend.deleteBackup` issued the DELETE, RLS matched no row it was allowed
-- to remove, PostgREST answered 204, and the app told the member their data was gone while the
-- row sat there. Under RLS a delete that is not permitted is not an error — it is a no-op.
drop policy if exists "members delete their own backup" on public.backups;
create policy "members delete their own backup"
  on public.backups for delete
  using (auth.uid() = user_id);

-- Deleting the account. App Store Review 5.1.1(v) wants the account and its data gone, from
-- inside the app, and the anon key cannot delete an auth user — that needs the service role,
-- which cannot ship in a client. A definer function owned by the project's `postgres` role can,
-- and it can only ever delete the caller: `auth.uid()` is the one id it touches.
--
-- Order matters. A shared pot is split first — `unlink_pair` writes both halves to
-- `link_payouts`, so the partner collects theirs on their next refresh and the caller's own row
-- goes with the account — then every row this member wrote is
-- removed explicitly — the cascades on auth.users would take them anyway, but a cascade that
-- silently fails on a future foreign key is not something to lean on for a legal requirement.
-- Deleting the auth user last invalidates every refresh token the member ever held; an access
-- token already issued stays valid until it expires (an hour at most), which is why the client
-- drops its own session in the same breath.
create or replace function public.delete_my_account()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  me    uuid := auth.uid();
  share integer := 0;
  p     public.link_pairs;
begin
  if me is null then
    raise exception 'not signed in' using errcode = 'insufficient_privilege';
  end if;

  for p in select * from public.link_pairs where a_user = me or b_user = me for update loop
    share := share + public.unlink_pair(p.id);
  end loop;

  delete from public.link_invites
   where from_user = me
      or accepted_by = me
      or lower(to_email) = lower(auth.jwt() ->> 'email');
  delete from public.backups where user_id = me;
  delete from auth.users where id = me;

  return share;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Part four: the shared bank's invariants, after an outside audit (18 Sep 2026).
--
-- Three things the first cut got wrong, each one a way for a member to lose or mint miles:
-- unlinking deleted the pair and with it the *other* member's half of the pot; two invites
-- accepted at the same moment could put one member in two banks; and a landing's credit was
-- whatever the client said it was, as many times as it cared to say it.

-- 1. A settlement the other member can collect. `unlink_pair` used to hand the caller their share
--    and drop the row, and the partner's half went with it. Now both halves are written here and
--    each member collects their own through `claim_payouts()` — which is what the caller does too,
--    so a reply lost on the wire is not a share lost for good.
create table if not exists public.link_payouts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  amount     integer not null check (amount >= 0),
  label      text not null default 'Shared bank unlinked',
  at         timestamptz not null default now(),
  claimed_at timestamptz
);

create index if not exists link_payouts_open_idx
  on public.link_payouts (user_id) where claimed_at is null;

alter table public.link_payouts enable row level security;

drop policy if exists "members read their own payouts" on public.link_payouts;
create policy "members read their own payouts"
  on public.link_payouts for select
  using (auth.uid() = user_id);
-- No insert/update/delete policies: only the functions below write here.

create or replace function public.unlink_pair(pair uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  p     public.link_pairs;
  half  integer;
  other uuid;
begin
  select * into p from public.link_pairs
   where id = pair and (a_user = auth.uid() or b_user = auth.uid())
   for update;

  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  half  := p.miles / 2;
  other := case when p.a_user = auth.uid() then p.b_user else p.a_user end;

  -- The odd mile stays with a_user, as before. Both shares are written, neither is handed back
  -- in the reply: each member claims their own, which survives a dropped connection.
  insert into public.link_payouts (user_id, amount)
  values (p.a_user, p.miles - half), (p.b_user, half);

  delete from public.link_pairs where id = pair;
  return 0;
end;
$$;

-- Everything waiting for the caller, claimed in one statement. Concurrent claims cannot double
-- pay: the UPDATE's `claimed_at is null` is the lock.
create or replace function public.claim_payouts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  total integer;
begin
  with claimed as (
    update public.link_payouts
       set claimed_at = now()
     where user_id = auth.uid() and claimed_at is null
    returning amount
  )
  select coalesce(sum(amount), 0) into total from claimed;
  return total;
end;
$$;

-- 2. One bank each, even under a race. Two invites from the same sender accepted at the same
--    instant each locked their own invite row, each saw no pair, and each inserted one. An
--    advisory lock on both member ids, taken in a fixed order before the membership check, makes
--    the second transaction wait and then see the first one's pair.
create or replace function public.accept_link_invite(invite uuid)
returns public.link_pairs
language plpgsql
security definer
set search_path = public
as $$
declare
  inv  public.link_invites;
  pair public.link_pairs;
  lo   uuid;
  hi   uuid;
begin
  select * into inv from public.link_invites
   where id = invite
     and accepted_by is null
     and declined_at is null
   for update;

  if not found then
    raise exception 'invite not open' using errcode = 'no_data_found';
  end if;

  if lower(inv.to_email) is distinct from lower(auth.jwt() ->> 'email') then
    raise exception 'not your invite' using errcode = 'insufficient_privilege';
  end if;

  if inv.from_user = auth.uid() then
    raise exception 'cannot link with yourself' using errcode = 'check_violation';
  end if;

  lo := least(inv.from_user, auth.uid());
  hi := greatest(inv.from_user, auth.uid());
  perform pg_advisory_xact_lock(hashtext(lo::text));
  perform pg_advisory_xact_lock(hashtext(hi::text));

  if exists (select 1 from public.link_pairs
              where a_user in (inv.from_user, auth.uid())
                 or b_user in (inv.from_user, auth.uid())) then
    raise exception 'already linked' using errcode = 'unique_violation';
  end if;

  update public.link_invites
     set accepted_by = auth.uid(), accepted_at = now()
   where id = inv.id;

  insert into public.link_pairs (a_user, b_user)
  values (lo, hi)
  on conflict (a_user, b_user) do update set linked_at = public.link_pairs.linked_at
  returning * into pair;

  return pair;
end;
$$;

-- 3. A credit is one landing, once. The client names each landing with an `op` id it minted when
--    the flight landed; the ledger keeps it unique, so a retry (or a replay) of the same landing
--    returns the balance and moves nothing. And a member can credit at most 3,000 mi to a pot in
--    any rolling day — far above what real flying pays, low enough that a script achieves little.
alter table public.link_ledger add column if not exists op uuid;
create unique index if not exists link_ledger_op_uniq on public.link_ledger (op) where op is not null;

drop function if exists public.earn_to_pair(uuid, integer, text);

create or replace function public.earn_to_pair(pair uuid, amount integer, label text, op uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining integer;
  today     integer;
begin
  if amount <= 0 or amount > 2000 then
    raise exception 'amount out of range' using errcode = 'check_violation';
  end if;

  -- Already credited: answer with the balance, move nothing.
  if exists (select 1 from public.link_ledger where link_ledger.op = earn_to_pair.op) then
    select miles into remaining from public.link_pairs
     where id = pair and (a_user = auth.uid() or b_user = auth.uid());
    if not found then
      raise exception 'not your pair' using errcode = 'insufficient_privilege';
    end if;
    return remaining;
  end if;

  select coalesce(sum(l.amount), 0) into today
    from public.link_ledger l
   where l.user_id = auth.uid() and l.amount > 0 and l.at > now() - interval '1 day';
  if today + amount > 3000 then
    raise exception 'daily credit limit' using errcode = 'check_violation';
  end if;

  update public.link_pairs
     set miles = miles + amount
   where id = pair
     and (a_user = auth.uid() or b_user = auth.uid())
  returning miles into remaining;

  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  insert into public.link_ledger (pair_id, user_id, amount, label, op)
  values (pair, auth.uid(), amount, label, op);

  return remaining;
end;
$$;

-- Grants, restated for every function in this file: nothing for anon, execute for members.
-- `revoke ... from public` alone is what the first cut did; anon is revoked by name as well so
-- the grant a future dashboard default might hand it is undone here too.
revoke all on function public.accept_link_invite(uuid)                     from public, anon;
revoke all on function public.decline_link_invite(uuid)                    from public, anon;
revoke all on function public.spend_from_pair(uuid, integer, text)         from public, anon;
revoke all on function public.earn_to_pair(uuid, integer, text, uuid)      from public, anon;
revoke all on function public.unlink_pair(uuid)                            from public, anon;
revoke all on function public.claim_payouts()                              from public, anon;
revoke all on function public.delete_my_account()                          from public, anon;
grant execute on function public.accept_link_invite(uuid)                  to authenticated;
grant execute on function public.decline_link_invite(uuid)                 to authenticated;
grant execute on function public.spend_from_pair(uuid, integer, text)      to authenticated;
grant execute on function public.earn_to_pair(uuid, integer, text, uuid)   to authenticated;
grant execute on function public.unlink_pair(uuid)                         to authenticated;
grant execute on function public.claim_payouts()                           to authenticated;
grant execute on function public.delete_my_account()                       to authenticated;

-- ---------------------------------------------------------------------------
-- Part five: gift cards, for real.
--
-- The Concourse's gift flow always spent real miles and told the sender "it is in their wallet
-- now" — and nothing delivered it: no server row, no recipient lookup, no accept or decline.
-- `ConcourseScreen` archived the category on 18 Sep 2026 rather than keep selling that. This is
-- the same shape as `link_invites` above: a row addressed by email, read by both ends, and
-- answered through a definer function rather than an update anyone could forge.
--
-- **Who debits what.** The sender's miles leave on the client, at send time, through the same
-- `payOrder` path every other Concourse purchase already uses — a gift is priced and paid for
-- exactly like a face or a header. This table and its functions only carry the credit to the
-- *recipient*; nothing here ever touches the sender's balance, which is why there is no "refund
-- the sender" case anywhere below — a declined or ignored gift already cost what it cost, the
-- same way a paid-for card that is never opened stays paid for.
create table if not exists public.gifts (
  id          uuid primary key default gen_random_uuid(),
  from_user   uuid not null references auth.users (id) on delete cascade,
  from_name   text not null,
  to_email    text not null,
  to_name     text not null,
  -- Capped, not just positive: the dial that sends a gift tops out at 1,000 mi, and a caller with
  -- the anon key posting straight to this table is bounded here rather than trusted to stay under
  -- what the UI would have asked for.
  amount      integer not null check (amount > 0 and amount <= 2000),
  face        text,
  created_at  timestamptz not null default now(),
  accepted_by uuid references auth.users (id) on delete cascade,
  accepted_at timestamptz,
  declined_at timestamptz,
  -- Same bounds as `link_invites`: display text has a sane maximum, and an address that cannot
  -- look like one can never match `lower(auth.jwt() ->> 'email')` on the way back out.
  constraint gifts_from_name_len  check (char_length(from_name) between 1 and 80),
  constraint gifts_to_name_len    check (char_length(to_name)   between 1 and 80),
  constraint gifts_to_email_shape check (
    char_length(to_email) <= 254 and to_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  )
);

create index if not exists gifts_to_email_idx
  on public.gifts (lower(to_email)) where accepted_by is null and declined_at is null;

alter table public.gifts enable row level security;

drop policy if exists "senders create their own gifts" on public.gifts;
drop policy if exists "both ends read a gift"           on public.gifts;

create policy "senders create their own gifts"
  on public.gifts for insert
  with check (auth.uid() = from_user);

create policy "both ends read a gift"
  on public.gifts for select
  using (
    auth.uid() = from_user
    or lower(to_email) = lower(auth.jwt() ->> 'email')
  );

-- No update policy at all, on purpose: accepting and declining go through the two functions
-- below, so a recipient can never edit a gift's amount on the way to taking it.

-- The recipient's credit, matched by JWT email exactly like `accept_link_invite`. Returns the
-- amount actually credited: 0 for a replay (already accepted — a retried tap must never double
-- the miles), and an exception for anything that was never this member's to take.
create or replace function public.accept_gift(gift uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.gifts;
begin
  select * into g from public.gifts
   where id = gift
     and accepted_by is null
     and declined_at is null
   for update;

  if not found then
    if exists (select 1 from public.gifts where id = gift and accepted_by is not null) then
      return 0;
    end if;
    -- Declined, or never existed — either way there is nothing left here to accept.
    raise exception 'gift not open' using errcode = 'no_data_found';
  end if;

  if lower(g.to_email) is distinct from lower(auth.jwt() ->> 'email') then
    raise exception 'not your gift' using errcode = 'insufficient_privilege';
  end if;

  update public.gifts set accepted_by = auth.uid(), accepted_at = now() where id = g.id;
  return g.amount;
end;
$$;

create or replace function public.decline_gift(gift uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.gifts
     set declined_at = now()
   where id = gift
     and accepted_by is null
     and declined_at is null
     and lower(to_email) = lower(auth.jwt() ->> 'email');
$$;

revoke all on function public.accept_gift(uuid)  from public, anon;
revoke all on function public.decline_gift(uuid) from public, anon;
grant execute on function public.accept_gift(uuid)  to authenticated;
grant execute on function public.decline_gift(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Part six: offline personal miles, online transfers.
-- The phone keeps earning/spending without a connection. An ordered outbox is
-- reconciled before a transfer; it is NEVER an upsert of a caller's balance.
-- ponytail: offline activity and the one-time legacy import are self-reported.
-- Bounds and a server-clock gift cap limit abuse; App Attest is the next step if
-- hostile modified clients become material. This does not prove physical study.
create table if not exists public.miles_wallets (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  balance bigint not null default 0 check (balance between 0 and 2147483647),
  sequence bigint not null default 0
);
create table if not exists public.miles_events (
  wallet_id uuid not null references public.miles_wallets(id) on delete cascade,
  seq bigint not null,
  id uuid not null,
  delta bigint not null,
  at timestamptz not null,
  payload jsonb not null,
  primary key (wallet_id, seq),
  unique (wallet_id, id)
);
create table if not exists public.gift_operations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  result jsonb not null,
  at timestamptz not null default now()
);
-- Independent of gifts: deleting a sender must not erase an accepted recipient's
-- receipt between server commit and the phone receiving the response.
create table if not exists public.gift_receipts (
  gift uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  wallet_id uuid not null references public.miles_wallets(id) on delete cascade,
  amount integer not null check (amount > 0)
);
create index if not exists gift_operations_user_at on public.gift_operations(user_id, at);
create index if not exists miles_events_credit_day on public.miles_events(wallet_id, at) where delta > 0;

alter table public.miles_wallets enable row level security;
alter table public.miles_events enable row level security;
alter table public.gift_operations enable row level security;
alter table public.gift_receipts enable row level security;
-- These tables are RPC-only, including reads. No client table policies.
revoke all on public.miles_wallets, public.miles_events, public.gift_operations, public.gift_receipts
  from anon, authenticated;
drop policy if exists "senders create their own gifts" on public.gifts;
-- Old clients must not consume a gift without its durable wallet credit.
revoke all on function public.accept_gift(uuid) from public, anon, authenticated;

create or replace function public.reconcile_miles(wallet uuid, events jsonb, expected bigint)
returns public.miles_wallets
language plpgsql security definer set search_path = '' as $$
declare
  w public.miles_wallets;
  e jsonb;
  prior jsonb;
  n bigint;
  d bigint;
  event_id uuid;
  happened timestamptz;
  day_start timestamptz;
  credited bigint;
begin
  if auth.uid() is null then raise exception 'Sign in to sync miles.' using errcode = '42501'; end if;
  if wallet is null or expected is null or expected < 1 or events is null
     or jsonb_typeof(events) <> 'array' or jsonb_array_length(events) > 128
     or octet_length(events::text) > 131072 then
    raise exception 'Invalid miles batch.' using errcode = '23514';
  end if;
  -- One history per account. Clones/restores share the stream id and must agree on
  -- every sequence; another installation cannot import the same starting miles.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 617));
  if exists (select 1 from public.miles_wallets m where m.user_id = auth.uid() and m.id <> wallet) then
    raise exception 'Restore the latest account backup before transferring miles.' using errcode = '23514';
  end if;
  insert into public.miles_wallets(id, user_id) values (wallet, auth.uid()) on conflict (id) do nothing;
  select * into w from public.miles_wallets m where m.id = wallet and m.user_id = auth.uid() for update;
  if not found then raise exception 'Not your miles history.' using errcode = '42501'; end if;
  for e in select value from jsonb_array_elements(events) loop
    n := (e->>'seq')::bigint;
    d := (e->>'delta')::bigint;
    event_id := (e->>'id')::uuid;
    if n is null or d is null or event_id is null or (e->>'at') is null
       or (e->>'at')::numeric not between 1577836800 and extract(epoch from now()) + 300 then
      raise exception 'Invalid miles event.' using errcode = '23514';
    end if;
    happened := to_timestamp((e->>'at')::double precision);
    if n <= w.sequence then
      select m.payload into prior from public.miles_events m where m.wallet_id = wallet and m.seq = n;
      if not found or prior <> e then
        raise exception 'Conflicting offline history. Restore the latest account backup before transferring miles.' using errcode = '23514';
      end if;
      continue;
    end if;
    if n <> w.sequence + 1 or d < -1000000 or d > (case when n = 1 then 1000000 else 3000 end)
       or (n = 1 and d < 0) or w.balance + d < 0 then
      raise exception 'The offline miles history could not be reconciled.' using errcode = '23514';
    end if;
    if d > 0 and n > 1 then
      day_start := date_trunc('day', happened at time zone 'UTC') at time zone 'UTC';
      select coalesce(sum(m.delta), 0) into credited from public.miles_events m
        where m.wallet_id = wallet and m.seq > 1 and m.delta > 0
          and m.at >= day_start and m.at < day_start + interval '1 day';
      if credited + d > 3000 then
        raise exception 'The offline credit limit was exceeded. Your local miles are unchanged.' using errcode = '23514';
      end if;
    end if;
    insert into public.miles_events(wallet_id, seq, id, delta, at, payload)
      values (wallet, n, event_id, d, happened, e);
    w.balance := w.balance + d;
    w.sequence := n;
  end loop;
  if w.sequence <> expected then
    raise exception 'This miles history is out of date. Restore the latest account backup before transferring miles.' using errcode = '23514';
  end if;
  update public.miles_wallets m set balance = w.balance, sequence = w.sequence where m.id = wallet;
  return w;
end;
$$;
revoke all on function public.reconcile_miles(uuid, jsonb, bigint) from public, anon, authenticated;

create or replace function public.sync_miles(wallet uuid, events jsonb, expected bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare w public.miles_wallets;
begin
  w := public.reconcile_miles(wallet, events, expected);
  return jsonb_build_object('sequence', w.sequence);
end;
$$;

create or replace function public.send_gift(operation uuid, wallet uuid, events jsonb, expected bigint,
  personal integer, pair uuid, amount integer, cost integer, from_name text, to_name text, to_email text, face text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w public.miles_wallets;
  previous public.gift_operations;
  payload jsonb;
  result jsonb;
  reason text;
  today bigint;
  remaining integer;
begin
  if auth.uid() is null then raise exception 'Sign in to send a gift.' using errcode = '42501'; end if;
  if operation is null then raise exception 'A gift needs an operation id.' using errcode = '23514'; end if;
  payload := jsonb_build_object('wallet', wallet, 'events', events, 'expected', expected,
    'personal', personal, 'pair', pair, 'amount', amount, 'cost', cost,
    'from_name', from_name, 'to_name', to_name, 'to_email', to_email, 'face', face);
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 617));
  select * into previous from public.gift_operations g where g.id = operation;
  if found then
    if previous.user_id <> auth.uid() or previous.payload <> payload then
      raise exception 'Gift operation does not match.' using errcode = '42501';
    end if;
    return previous.result;
  end if;
  -- The nested block rolls back BOTH reconciliation and any debit on refusal.
  begin
    if amount is null or amount not between 1 and 2000 or cost is null or cost < amount or cost > amount + 1000
       or personal is null or personal < 0 or personal > cost
       or from_name is null or char_length(from_name) not between 1 and 80
       or to_name is null or char_length(to_name) not between 1 and 80
       or to_email is null or char_length(to_email) > 254
       or to_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
       or (face is not null and char_length(face) > 80) then
      raise exception 'Check the gift amount and recipient.' using errcode = '23514';
    end if;
    if lower(to_email) = lower(auth.jwt()->>'email') then
      raise exception 'Choose another member to receive the gift.' using errcode = '23514';
    end if;
    w := public.reconcile_miles(wallet, events, expected);
    -- Server time, immutable operation history, serialized per sender. Neither
    -- client backdating, concurrent requests nor unlink/relink reset this cap.
    select coalesce(sum((g.payload->>'amount')::integer), 0) into today
      from public.gift_operations g where g.user_id = auth.uid()
        and g.result->>'state' = 'sent' and g.at > now() - interval '24 hours';
    if today + amount > 2000 then
      raise exception 'You can send up to 2,000 mi in 24 hours. Try again later.' using errcode = '23514';
    end if;
    if w.balance < personal then
      raise exception 'Those miles have already been spent.' using errcode = '23514';
    end if;
    if cost > personal then
      remaining := public.spend_from_pair(pair, cost - personal, 'Gift');
      if remaining is null then
        raise exception 'Those shared miles have already been spent.' using errcode = '23514';
      end if;
    end if;
    update public.miles_wallets m set balance = balance - personal where m.id = wallet;
    insert into public.gifts(id, from_user, from_name, to_email, to_name, amount, face)
      values (operation, auth.uid(), from_name, lower(to_email), to_name, amount, face);
    result := jsonb_build_object('state', 'sent', 'sequence', w.sequence, 'pot', remaining);
  exception when check_violation then
    get stacked diagnostics reason = message_text;
    result := jsonb_build_object('state', 'refused', 'reason', reason, 'sequence', 0);
  end;
  insert into public.gift_operations(id, user_id, payload, result) values (operation, auth.uid(), payload, result);
  return result;
end;
$$;

create or replace function public.receive_gift(gift uuid, wallet uuid, events jsonb, expected bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w public.miles_wallets;
  g public.gifts;
  receipt public.gift_receipts;
begin
  w := public.reconcile_miles(wallet, events, expected);
  select * into receipt from public.gift_receipts r where r.gift = receive_gift.gift;
  if found then
    if receipt.user_id <> auth.uid() or receipt.wallet_id <> wallet then
      raise exception 'Not your gift receipt.' using errcode = '42501';
    end if;
    return jsonb_build_object('amount', receipt.amount, 'sequence', w.sequence);
  end if;
  select * into g from public.gifts where id = gift for update;
  if not found or lower(g.to_email) is distinct from lower(auth.jwt()->>'email') then
    raise exception 'Not your gift.' using errcode = '42501';
  end if;
  if g.accepted_by is not null or g.declined_at is not null then
    return jsonb_build_object('amount', 0, 'sequence', w.sequence);
  end if;
  update public.gifts set accepted_by = auth.uid(), accepted_at = now() where id = gift;
  update public.miles_wallets m set balance = balance + g.amount where m.id = wallet;
  insert into public.gift_receipts(gift, user_id, wallet_id, amount) values (gift, auth.uid(), wallet, g.amount);
  return jsonb_build_object('amount', g.amount, 'sequence', w.sequence);
end;
$$;

revoke all on function public.sync_miles(uuid, jsonb, bigint) from public, anon;
revoke all on function public.send_gift(uuid, uuid, jsonb, bigint, integer, uuid, integer, integer, text, text, text, text) from public, anon;
revoke all on function public.receive_gift(uuid, uuid, jsonb, bigint) from public, anon;
grant execute on function public.sync_miles(uuid, jsonb, bigint) to authenticated;
grant execute on function public.send_gift(uuid, uuid, jsonb, bigint, integer, uuid, integer, integer, text, text, text, text) to authenticated;
grant execute on function public.receive_gift(uuid, uuid, jsonb, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Part seven: Sign in with Apple's refresh tokens, for revocation on deletion (19 Sep 2026).
--
-- Written and read only by the `apple-token` Edge Function through the service role. Row level
-- security is on with no policies, so no client key — anon or a signed-in member's — can read a
-- token back. The row goes with the user (`on delete cascade`) if deletion runs before revocation
-- for any reason, so nothing lingers.
create table if not exists public.apple_tokens (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  created_at    timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;
revoke all on table public.apple_tokens from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Part eight: naming the account's own wallet, so a reinstall is not a dead end (22 Sep 2026).
--
-- `reconcile_miles` allows exactly one miles stream per account and refuses every other one with
-- "Restore the latest account backup before transferring miles." That is the right rule — it is
-- what stops a cloned install importing its balance a second time — but the client had no way to
-- obey it. A phone that mints a fresh `MilesJournal` (a reinstall, an erased install, a second
-- device) can no longer send or accept a gift, and the instruction in the message is not one a
-- member can carry out: signing in after onboarding pushes that phone's state *over* the cloud
-- backup, so the old journal is already gone by the time the refusal arrives.
--
-- This names the stream instead, so the client can adopt it (`AppModel.repairMilesWallet`) rather
-- than guess. It is read-only and tells the caller nothing about anybody else: the row is looked
-- up by `auth.uid()` and nothing else is selectable from these tables at all.
create or replace function public.my_wallet()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare w public.miles_wallets;
begin
  if auth.uid() is null then raise exception 'Sign in to sync miles.' using errcode = '42501'; end if;
  select * into w from public.miles_wallets m where m.user_id = auth.uid();
  if not found then return null; end if;
  return jsonb_build_object('wallet', w.id, 'sequence', w.sequence, 'balance', w.balance);
end;
$$;
revoke all on function public.my_wallet() from public, anon;
grant execute on function public.my_wallet() to authenticated;

-- ---------------------------------------------------------------------------
-- Part nine: linking merges the two banks, at once (22 Sep 2026).
--
-- Linking used to merge nothing: each member kept their personal balance and the pot started
-- empty and filled from the next landing on. Asked for the other way round — the moment two
-- members link, what they already hold is one bank — so each phone deposits its own personal
-- balance into the pot the first time it sees the pair live. `earn_to_pair` is the wrong door for
-- that: it is capped at 2,000 a call and 3,000 a rolling day, which is right for minting a
-- landing's credit and would swallow a member's whole balance.
--
-- **Once per member per pair, and that is the idempotency key.** There is no `op` id here because
-- the ledger line itself is one: a second call finds the member's own deposit row, moves nothing
-- and answers with the balance — so a reply lost on the wire is safe to retry, and the client can
-- zero its personal balance on any successful answer. The ceiling is a sanity bound, not a rate
-- limit; a deposit moves miles the member already had, and once only.
-- **The deposit is paid out of the member's reconciled wallet** (25 Sep 2026 audit). The first
-- version took `amount` on the client's word, bounded only by a 1,000,000 sanity ceiling: any
-- signed-in member could link with a second account of their own and mint a million miles into a
-- spendable pot, then unlink, relink and do it again. Now it reconciles the caller's journal the way
-- `send_gift` does, refuses more than the wallet holds, and debits the wallet in the same
-- transaction — so a deposit moves miles that exist, and relinking moves them, not copies them.
drop function if exists public.deposit_to_pair(uuid, integer);
create or replace function public.deposit_to_pair(pair uuid, wallet uuid, events jsonb,
  expected bigint, amount integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.miles_wallets;
  remaining integer;
begin
  if auth.uid() is null then raise exception 'Sign in to share a bank.' using errcode = '42501'; end if;
  if amount is null or amount < 0 then
    raise exception 'amount out of range' using errcode = 'check_violation';
  end if;
  -- The same per-member lock `send_gift` takes, so a deposit and a gift cannot both spend one balance.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 617));

  select p.miles into remaining from public.link_pairs p
   where p.id = pair and (p.a_user = auth.uid() or p.b_user = auth.uid());
  if not found then
    raise exception 'not your pair' using errcode = 'insufficient_privilege';
  end if;

  w := public.reconcile_miles(wallet, events, expected);

  if exists (select 1 from public.link_ledger l
              where l.pair_id = pair
                and l.user_id = auth.uid()
                and l.label = 'Merged on linking') then
    return jsonb_build_object('pot', remaining, 'sequence', w.sequence);
  end if;

  if w.balance < amount then
    raise exception 'Those miles have already been spent.' using errcode = 'check_violation';
  end if;

  update public.miles_wallets m set balance = balance - amount where m.id = wallet;
  update public.link_pairs p set miles = p.miles + amount where p.id = pair
  returning p.miles into remaining;

  insert into public.link_ledger (pair_id, user_id, amount, label)
  values (pair, auth.uid(), amount, 'Merged on linking');

  return jsonb_build_object('pot', remaining, 'sequence', w.sequence);
end;
$$;
revoke all on function public.deposit_to_pair(uuid, uuid, jsonb, bigint, integer) from public, anon;
grant execute on function public.deposit_to_pair(uuid, uuid, jsonb, bigint, integer) to authenticated;
