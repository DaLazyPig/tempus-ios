// Run with Node and @electric-sql/pglite, optionally passing its module path.
// Uses an isolated in-memory PostgreSQL; never contacts Supabase.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
process.on('uncaughtException', e => { console.error(e.message, e.where ?? '', e.position ?? ''); process.exit(1); });
const { PGlite } = await import(process.argv[2] ?? '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth;
  create table auth.users(id uuid primary key, email text);
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select (auth.jwt()->>'sub')::uuid $$;
  grant usage on schema auth, public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
`);
const schema = await readFile(new URL('../schema.sql', import.meta.url), 'utf8');
await db.exec(schema);
await db.exec(schema); // Dashboard reruns must leave the final policy/grants intact.
const users = Array.from({ length: 6 }, (_, i) => ({ id: randomUUID(), email: `member${i}@example.com`, wallet: randomUUID() }));
for (const u of users) await db.query('insert into auth.users values ($1,$2)', [u.id, u.email]);
async function login(u, role = 'authenticated') {
  await db.exec(`reset role; set role ${role}`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify(u ? { sub: u.id, email: u.email } : {})]);
}
async function admin(sql, args = []) { await db.exec('reset role'); return (await db.query(sql, args)).rows; }
const event = (seq, delta) => ({ id: randomUUID(), seq, delta, at: Math.floor(Date.now() / 1000) });
async function sync(u, events, expected = events.at(-1)?.seq ?? 1) {
  return (await db.query('select public.sync_miles($1,$2,$3) as result', [u.wallet, JSON.stringify(events), expected])).rows[0].result;
}
const [a,b,c,d,e,f] = users;
const history = [event(1, 0), event(2, 100), event(3, -20)];
await login(a);
assert.equal((await sync(a, history)).sequence, 3);
assert.equal((await sync(a, history)).sequence, 3); // Exact replay.
await assert.rejects(sync(a, [event(3, -20)], 3), /Conflicting offline history/);
await assert.rejects(sync(a, [event(5, 10)], 5), /could not be reconciled/);
await assert.rejects(sync({ ...a, wallet: randomUUID() }, [event(1, 100)]), /latest account backup/);
await assert.rejects(db.query('select public.reconcile_miles($1,$2,$3)', [a.wallet, '[]', 3]), /permission denied/);
await assert.rejects(db.query('update public.miles_wallets set balance = 99999'), /permission denied/);
await assert.rejects(db.query(`insert into public.gifts(from_user,from_name,to_email,to_name,amount)
  values ($1,'A',$2,'B',2000)`, [a.id,b.email]), /row-level security|permission denied/);
async function send(u, recipient, amount, { id = randomUUID(), personal = amount, pair = null, sequence = 1, cost = amount } = {}) {
  const args = [id,u.wallet,'[]',sequence,personal,pair,amount,cost,'Sender','Recipient',recipient.email,'G01'];
  const execute = async () => (await db.query('select public.send_gift($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) as result', args)).rows[0].result;
  return { id, result: await execute(), retry: execute };
}
const sent = await send(a,b,30,{ sequence: 3 });
assert.equal(sent.result.state, 'sent');
assert.deepEqual(await sent.retry(), sent.result); // Ignore first response, then retry.
assert.equal(Number((await admin('select balance from miles_wallets where id=$1',[a.wallet]))[0].balance),50);
assert.equal(Number((await admin('select count(*) as n from gifts'))[0].n),1);
await login(b);
await sync(b,[event(1,50)]);
async function receive(u, id, seq = 1) {
  return (await db.query('select public.receive_gift($1,$2,$3,$4) as result',[id,u.wallet,'[]',seq])).rows[0].result;
}
assert.equal((await receive(b,sent.id)).amount,30);
assert.equal((await receive(b,sent.id)).amount,30); // Receipt can be recovered; local id dedupes it.
assert.equal(Number((await admin('select balance from miles_wallets where id=$1',[b.wallet]))[0].balance),80);
await login(c);
await sync(c,[event(1,50)]);
await assert.rejects(receive(c,sent.id), /Not your gift receipt/);
await assert.rejects(db.query('select public.accept_gift($1)',[sent.id]), /permission denied/);
await login(null,'anon');
await assert.rejects(sync(c,[],1), /permission denied/);
await login(a);
const first = await send(a,b,40,{sequence:3});
const second = await send(a,b,40,{sequence:3});
assert.equal(first.result.state,'sent');
assert.equal(second.result.state,'refused');
assert.deepEqual(await second.retry(),second.result); // Refusal is terminal for this id.
assert.equal(Number((await admin('select balance from miles_wallets where id=$1',[a.wallet]))[0].balance),10);
// Daily limit is computed using server time and counts an operation only once.
await login(d); await sync(d,[event(1,5000)]);
const large = await send(d,b,1200);
assert.equal(large.result.state,'sent');
assert.deepEqual(await large.retry(),large.result);
assert.equal((await send(d,b,1000)).result.state,'refused');
// Shared shortfall and personal debit are part of the same gift transaction.
const pair = randomUUID();
const ends = [e.id,f.id].sort();
await admin('insert into link_pairs(id,a_user,b_user,miles) values($1,$2,$3,60)',[pair,...ends]);
await login(e); await sync(e,[event(1,10)]);
assert.equal((await send(e,b,50,{personal:10,pair})).result.state,'sent');
assert.equal(Number((await admin('select miles from link_pairs where id=$1',[pair]))[0].miles),20);
await login(e);
assert.equal((await send(e,b,30,{personal:0,pair})).result.state,'refused');
assert.equal(Number((await admin('select miles from link_pairs where id=$1',[pair]))[0].miles),20);
// The recipient can recover a receipt even if the sender deletes their account.
await admin('delete from auth.users where id=$1',[a.id]);
await login(b);
assert.equal((await receive(b,sent.id)).amount,30);
await db.close();
console.log('PASS: offline replay/conflicts, permissions, atomic gifts, lost-response receipts, balance checks, daily limit, shared shortfall, schema rerun');
