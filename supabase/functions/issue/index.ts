// Lothal's licence issuer.
//
// Takes a Firebase ID token from the activation page, proves it is genuine, and returns a licence
// signed with the RSA key whose public half is compiled into every Lothal binary
// (rust/src/licence.rs, ACTIVATION_PUBLIC_KEYS). The app verifies that signature offline and
// never calls this function — or anything else — again. This is a one-time issuing service, not
// a launch-time dependency: it can vanish and every existing install keeps working.
//
// THE FLOW
//   [Continue with Google] → Firebase popup → Firebase Auth records the user (email, uid)
//                          → page gets an ID token → POST here → licence printed on screen
//
// WHAT IS TRUSTED, AND WHERE
// The browser proves nothing. A page can claim any address or uid it likes, so the address that
// ends up in the signed payload is read out of Firebase's own token AFTER its signature has been
// checked (firebase_token.ts), never out of the request body. There is deliberately no lookup
// against Firebase: the signature IS the proof, so no service-account credential lives here and
// no outage of Firebase's API can block an activation.
//
// WHERE THE EMAIL LIST LIVES
// In Firebase Auth. Its user records hold email and uid as a side effect of signing in, so there
// is nothing to write here — an earlier design carried a Postgres table that was written on every
// issue and read by nothing, and it was removed rather than kept as a second copy of a list
// Firebase already keeps.

import { verifyFirebaseIdToken } from "./firebase_token.ts";

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

function b64urlToBytes(input: string): Uint8Array<ArrayBuffer> {
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

  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const privateKey = Deno.env.get("ACTIVATION_PRIVATE_KEY");
  if (!projectId || !privateKey) {
    // Refuse loudly rather than issuing something unverifiable. A misconfigured deploy that
    // signed with a missing key would produce licences that verify nowhere, and the only symptom
    // would be users reporting that a key they were just given does not work.
    return json({ error: "issuer is not configured" }, 500, origin);
  }

  let idToken = "";
  try {
    const body = await req.json();
    idToken = String(body.id_token ?? "");
    if (!idToken) throw new Error("no token");
  } catch {
    return json({ error: 'expected {"id_token": "..."}' }, 400, origin);
  }

  let claims;
  try {
    claims = await verifyFirebaseIdToken(idToken, projectId);
  } catch (e) {
    return json({ error: `sign-in could not be verified: ${(e as Error).message}` }, 401, origin);
  }

  const issued = new Date().toISOString().slice(0, 10);

  // The payload is signed AS THIS EXACT STRING and returned as this exact string. The app stores
  // it verbatim and verifies over the bytes it received — it never re-serialises the dictionary,
  // because key order and number formatting do not survive a round trip through two different
  // JSON writers, and a signature that depended on them would verify here and fail in the field.
  const payload = JSON.stringify({ schema: SCHEMA, email: claims.email, issued, key_id: KEY_ID });
  const signature = await signPayload(payload, privateKey);

  // The envelope is composed HERE and handed over as one finished string, rather than returning
  // the two halves for the page to assemble. The payload must reach the app byte-identical, and
  // a browser that rebuilt the envelope would be a second JSON writer in the path — the exact
  // shape of mistake that produces a licence which verifies on the maintainer's machine and
  // fails in the field. Indented because a human pastes it; only the payload string is signed,
  // so envelope formatting is free.
  const licence = JSON.stringify({ payload, signature }, null, 2);

  return json({ licence, email: claims.email }, 200, origin);
});
