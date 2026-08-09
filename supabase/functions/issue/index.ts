// Lothal's licence issuer.
//
// Takes a Google ID token from the activation page, proves it is genuine, and returns a licence
// signed with the RSA key whose public half is compiled into every Lothal binary
// (rust/src/licence.rs, ACTIVATION_PUBLIC_KEYS). The app verifies that signature offline and
// never calls this function — or anything else — again. This is a one-time issuing service, not
// a launch-time dependency: it can vanish and every existing install keeps working.
//
// WHY NOT SUPABASE AUTH'S GOOGLE PROVIDER
// It would work, and it needs a Google OAuth client SECRET pasted into the project dashboard.
// Verifying the ID token here directly needs only the client ID, which is public and already
// sits in the page's config.js. Fewer secrets is the whole reason to prefer it; the security is
// identical, because in both cases the thing being trusted is Google's signature over the token.
//
// WHAT IS TRUSTED, AND WHERE
// The browser proves nothing. A page can claim any address it likes, so the address that ends up
// in the signed payload is read out of Google's own token AFTER its signature has been checked
// here, against Google's published keys. `email_verified` is required too: a Google account can
// carry an unverified address, and issuing against one would put an address in the signed licence
// that nobody has ever demonstrated control of.

import { createClient } from "jsr:@supabase/supabase-js@2";

const GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = ["accounts.google.com", "https://accounts.google.com"];

// The key that signs licences. key_id 1 is the only entry in the app's compiled table; when it
// rotates, the app must ship the NEW public key first and only then may this start issuing
// against it — reversing that order strands everyone whose install predates the new key.
const KEY_ID = 1;
const SCHEMA = 1;

const ALLOWED_ORIGINS = [
  "https://lothal.meetdev.in",
  "http://localhost:8788",
  "http://127.0.0.1:8788",
];

function corsHeaders(origin: string | null): Record<string, string> {
  // Echo the origin only when it is one we know. A wildcard would let any page on the internet
  // spend a user's token here; it would not leak the signing key, but it would let a phishing
  // page mint a real licence and present itself as Lothal.
  const allowed = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders(origin) },
  });
}

function b64urlToBytes(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(input.length + ((4 - (input.length % 4)) % 4), "=");
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function bytesToB64(bytes: ArrayBuffer): string {
  const view = new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < view.length; i++) binary += String.fromCharCode(view[i]);
  return btoa(binary);
}

/** Google's signing keys, cached for an hour. Fetching them per request would make every
 *  activation depend on a second network round trip that almost never changes its answer. */
let certsCache: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

async function googleKeys(): Promise<JsonWebKey[]> {
  const HOUR = 60 * 60 * 1000;
  if (certsCache && Date.now() - certsCache.fetchedAt < HOUR) return certsCache.keys;
  const res = await fetch(GOOGLE_CERTS);
  if (!res.ok) throw new Error(`google certs ${res.status}`);
  const body = await res.json();
  certsCache = { keys: body.keys ?? [], fetchedAt: Date.now() };
  return certsCache.keys;
}

type GoogleClaims = { email?: string; email_verified?: boolean; aud?: string; iss?: string; exp?: number };

/** Verifies a Google ID token end to end and returns its claims, or throws. Every failure path
 *  throws rather than returning a partial result, so there is no shape of "sort of verified"
 *  for a caller to mishandle. */
async function verifyGoogleIdToken(token: string, clientId: string): Promise<GoogleClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");

  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
  if (header.alg !== "RS256") throw new Error("unexpected alg");

  const jwk = (await googleKeys()).find((k) => (k as { kid?: string }).kid === header.kid);
  if (!jwk) throw new Error("unknown signing key");

  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlToBytes(parts[2]),
    signed,
  );
  if (!ok) throw new Error("bad signature");

  const claims: GoogleClaims = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));

  // Order matters only for the error messages; all four must hold.
  if (!claims.iss || !GOOGLE_ISSUERS.includes(claims.iss)) throw new Error("bad issuer");
  // Without this, a token minted for ANY other Google app would verify here — the signature is
  // Google's either way. `aud` is what ties the token to this application.
  if (claims.aud !== clientId) throw new Error("token was not issued for this app");
  if (!claims.exp || claims.exp * 1000 <= Date.now()) throw new Error("token expired");
  if (!claims.email) throw new Error("token carries no email");
  if (claims.email_verified !== true) throw new Error("email is not verified on this Google account");

  return claims;
}

async function signPayload(payload: string, pkcs8Pem: string): Promise<string> {
  const body = pkcs8Pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    b64urlToBytes(body),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  // PKCS#1 v1.5, never PSS. PSS deploys cleanly, passes every unit test, and rejects every
  // licence ever issued — the app verifies with pkcs1v15 in rust/src/licence.rs.
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(payload),
  );
  return bytesToB64(sig);
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "POST only" }, 405, origin);

  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const privateKey = Deno.env.get("ACTIVATION_PRIVATE_KEY");
  if (!clientId || !privateKey) {
    // Refuse loudly rather than issuing something unverifiable. A misconfigured deploy that
    // signed with a missing key would produce licences that verify nowhere, and the only symptom
    // would be users reporting that a key they were just given does not work.
    return json({ error: "issuer is not configured" }, 500, origin);
  }

  let idToken: string;
  try {
    const body = await req.json();
    idToken = String(body.id_token ?? "");
    if (!idToken) throw new Error("no id_token");
  } catch {
    return json({ error: "expected {\"id_token\": \"...\"}" }, 400, origin);
  }

  let claims: GoogleClaims;
  try {
    claims = await verifyGoogleIdToken(idToken, clientId);
  } catch (e) {
    return json({ error: `sign-in could not be verified: ${(e as Error).message}` }, 401, origin);
  }

  const email = claims.email!.toLowerCase();
  const issued = new Date().toISOString().slice(0, 10);

  // The payload is signed AS THIS EXACT STRING and returned as this exact string. The app stores
  // it verbatim and verifies over the bytes it received — it never re-serialises the dictionary,
  // because key order and number formatting do not survive a round trip through two different
  // JSON writers, and a signature that depended on them would verify here and fail in the field.
  const payload = JSON.stringify({ schema: SCHEMA, email, issued, key_id: KEY_ID });
  const signature = await signPayload(payload, privateKey);

  // The email list. Firebase Auth used to BE the list; on Supabase the equivalent is one table,
  // written here and read by nobody at runtime — the app never asks whether an address is still
  // present, so a failure to record must not deny a licence the user has already earned.
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    await supabase.from("activations")
      .upsert({ email, last_issued: new Date().toISOString() }, { onConflict: "email" });
  } catch (e) {
    console.error("activation not recorded", (e as Error).message);
  }

  // The envelope is composed HERE and handed over as one finished string, rather than returning
  // the two halves for the page to assemble. The payload must reach the app byte-identical, and
  // a browser that rebuilt the envelope would be a second JSON writer in the path — the exact
  // shape of mistake that produces a licence which verifies on the maintainer's machine and
  // fails in the field. Indented because a human pastes it; only the payload string is signed,
  // so envelope formatting is free.
  const licence = JSON.stringify({ payload, signature }, null, 2);

  return json({ licence, email }, 200, origin);
});
