// apple-token: the server half of Sign in with Apple's revocation.
//
// Apple asks an app that offers Sign in with Apple to revoke the member's grant when their account
// is deleted. Revoking needs a refresh token, and the only thing that buys one is the authorization
// code from sign-in, within five minutes of it being issued. So the app posts that code here right
// after it links the session ({action:"store"}), this exchanges it and keeps the refresh token in
// public.apple_tokens (service role only), and account deletion posts {action:"revoke"} before it
// deletes the user.
//
// Secrets (supabase secrets set …): APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8, PEM),
// optionally APPLE_CLIENT_ID (defaults to the app's bundle id). SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.crescerestudios.tempus";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Apple's client_secret is a short-lived ES256 JWT signed with the Sign in with Apple key.
async function clientSecret(): Promise<string> {
  const team = Deno.env.get("APPLE_TEAM_ID");
  const kid = Deno.env.get("APPLE_KEY_ID");
  const pem = Deno.env.get("APPLE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (!team || !kid || !pem) throw new Error("Apple secrets are not set");
  const key = await importPKCS8(pem, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid })
    .setIssuer(team)
    .setSubject(CLIENT_ID)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(key);
}

async function apple(endpoint: "token" | "revoke", form: Record<string, string>) {
  return await fetch(`https://appleid.apple.com/auth/${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user }, error } = await asUser.auth.getUser();
  if (error || !user) return json({ error: "not signed in" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const body = await req.json().catch(() => ({}));
  const secret = await clientSecret();

  if (body.action === "store" && typeof body.code === "string") {
    const r = await apple("token", {
      grant_type: "authorization_code",
      code: body.code,
      client_id: CLIENT_ID,
      client_secret: secret,
    });
    if (!r.ok) return json({ error: `apple ${r.status}: ${await r.text()}` }, 502);
    const { refresh_token } = await r.json();
    const { error: dbError } = await admin
      .from("apple_tokens")
      .upsert({ user_id: user.id, refresh_token });
    if (dbError) return json({ error: dbError.message }, 500);
    return json({ stored: true });
  }

  if (body.action === "revoke") {
    const { data } = await admin
      .from("apple_tokens")
      .select("refresh_token")
      .eq("user_id", user.id)
      .maybeSingle();
    if (!data) return json({ revoked: false, reason: "no token on file" });
    const r = await apple("revoke", {
      token: data.refresh_token,
      token_type_hint: "refresh_token",
      client_id: CLIENT_ID,
      client_secret: secret,
    });
    await admin.from("apple_tokens").delete().eq("user_id", user.id);
    return json({ revoked: r.ok });
  }

  return json({ error: "unknown action" }, 400);
});
