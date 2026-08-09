// Tests for the trust boundary.
//
// Each rejection test must FAIL if its own check is deleted from firebase_token.ts. A test that
// passes because some earlier check rejected the token first proves nothing about the check it
// claims to cover, so every token below is well-formed in every respect except the one under test.

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { verifyFirebaseIdToken } from "./firebase_token.ts";

const PROJECT = "lothal-activation";
const ISS = `https://securetoken.google.com/${PROJECT}`;

function bytesToB64url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function jsonToB64url(value: unknown): string {
  return bytesToB64url(new TextEncoder().encode(JSON.stringify(value)));
}

/** A key pair standing in for Google's. Generated per run: nothing here is a real credential. */
async function makeSigner(kid: string) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid, alg: "RS256" };

  async function mint(
    claims: Record<string, unknown> = {},
    header: Record<string, unknown> = {},
  ): Promise<string> {
    const head = jsonToB64url({ alg: "RS256", kid, typ: "JWT", ...header });
    const body = jsonToB64url({
      aud: PROJECT,
      iss: ISS,
      sub: "uid-abc123",
      email: "Pilot@Example.com",
      email_verified: true,
      exp: Math.floor(Date.now() / 1000) + 3600,
      ...claims,
    });
    const sig = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      pair.privateKey,
      new TextEncoder().encode(`${head}.${body}`),
    );
    return `${head}.${body}.${bytesToB64url(new Uint8Array(sig))}`;
  }

  return { mint, keys: () => Promise.resolve([jwk as JsonWebKey]) };
}

Deno.test("accepts a genuine token and returns its uid and email", async () => {
  const g = await makeSigner("k1");
  const claims = await verifyFirebaseIdToken(await g.mint(), PROJECT, g.keys);
  assertEquals(claims.uid, "uid-abc123");
  // Lowercased so the same person cannot obtain two differently-cased licences, and so the
  // address in the signed payload is stable across sign-ins.
  assertEquals(claims.email, "pilot@example.com");
});

Deno.test("rejects a token signed by a key that is not Google's", async () => {
  const google = await makeSigner("k1");
  const attacker = await makeSigner("k1"); // same kid, different private key
  const token = await attacker.mint();
  await assertRejects(
    () => verifyFirebaseIdToken(token, PROJECT, google.keys),
    Error,
    "bad signature",
  );
});

Deno.test("rejects a token minted for a different Firebase project", async () => {
  // Google signed this one too. `aud` is the only thing that ties a token to this app.
  const g = await makeSigner("k1");
  const token = await g.mint({ aud: "someone-elses-app", iss: "https://securetoken.google.com/someone-elses-app" });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "not issued for this app");
});

Deno.test("rejects a token whose issuer is not Firebase's securetoken service", async () => {
  const g = await makeSigner("k1");
  const token = await g.mint({ iss: "https://accounts.google.com" });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "bad issuer");
});

Deno.test("rejects an expired token", async () => {
  const g = await makeSigner("k1");
  const token = await g.mint({ exp: Math.floor(Date.now() / 1000) - 1 });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "expired");
});

Deno.test("rejects a token with an unverified email", async () => {
  const g = await makeSigner("k1");
  const token = await g.mint({ email_verified: false });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "not verified");
});

Deno.test("rejects a token carrying no email", async () => {
  const g = await makeSigner("k1");
  const token = await g.mint({ email: undefined });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "no email");
});

Deno.test("rejects a token carrying no uid", async () => {
  const g = await makeSigner("k1");
  const token = await g.mint({ sub: undefined });
  await assertRejects(() => verifyFirebaseIdToken(token, PROJECT, g.keys), Error, "no uid");
});

Deno.test("rejects an unsigned token claiming alg none", async () => {
  // The classic JWT forgery: strip the signature and tell the verifier not to check one.
  const g = await makeSigner("k1");
  const head = jsonToB64url({ alg: "none", kid: "k1", typ: "JWT" });
  const body = jsonToB64url({
    aud: PROJECT, iss: ISS, sub: "uid-evil", email: "evil@example.com",
    email_verified: true, exp: Math.floor(Date.now() / 1000) + 3600,
  });
  await assertRejects(
    () => verifyFirebaseIdToken(`${head}.${body}.`, PROJECT, g.keys),
    Error,
    "unexpected alg",
  );
});

Deno.test("rejects a token signed by a key id Google does not publish", async () => {
  const google = await makeSigner("k1");
  const attacker = await makeSigner("attacker-kid");
  const token = await attacker.mint();
  await assertRejects(
    () => verifyFirebaseIdToken(token, PROJECT, google.keys),
    Error,
    "unknown signing key",
  );
});

Deno.test("rejects a bare uid, which is what the browser must not be trusted to send", async () => {
  const g = await makeSigner("k1");
  await assertRejects(() => verifyFirebaseIdToken("uid-abc123", PROJECT, g.keys), Error, "malformed token");
});
