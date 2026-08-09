// Verification of Firebase ID tokens.
//
// This is the whole of the trust boundary. Everything downstream — the address that goes into the
// signed licence, and therefore the name on every licence Lothal will ever verify — rests on this
// file returning claims only for tokens Google actually signed.
//
// WHY A TOKEN AND NOT A UID
// A Firebase uid is not a secret and proves nothing: it is a string a browser puts in a request
// body, and looking it up in Firebase only establishes that the account exists, never that the
// caller owns it. Anyone who learns a uid could mint that person's licence. An ID token cannot be
// produced without Google's private key, so checking its signature IS the proof of ownership, and
// it needs no lookup, no service-account credential, and no network call to Firebase.

/** Firebase's token-signing keys in JWK form.
 *
 *  Firebase also publishes these as X.509 certificates at a robot/v1 URL. Prefer this endpoint:
 *  the cert form has to be parsed down to a SubjectPublicKeyInfo before WebCrypto will import it,
 *  which is hand-rolled DER walking in the one place where a parsing slip means accepting a token
 *  that was never verified. */
const FIREBASE_JWKS =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

export type FirebaseClaims = {
  uid: string;
  email: string;
};

export type KeyFetcher = () => Promise<JsonWebKey[]>;

function b64urlToBytes(input: string): Uint8Array<ArrayBuffer> {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(input.length + ((4 - (input.length % 4)) % 4), "=");
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/** Google's keys, cached for an hour. Fetching per activation would put a second network round
 *  trip in front of every user to re-learn an answer that changes a few times a year. */
let cache: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

export async function fetchFirebaseKeys(): Promise<JsonWebKey[]> {
  const HOUR = 60 * 60 * 1000;
  if (cache && Date.now() - cache.fetchedAt < HOUR) return cache.keys;
  const res = await fetch(FIREBASE_JWKS);
  if (!res.ok) throw new Error(`firebase jwks ${res.status}`);
  const body = await res.json();
  // The endpoint returns { keys: [...] }; older mirrors return a bare kid->jwk map. Accept both
  // rather than silently ending up with an empty key set, which would present as "unknown signing
  // key" on every legitimate token.
  const keys: JsonWebKey[] = Array.isArray(body?.keys) ? body.keys : Object.values(body ?? {});
  cache = { keys, fetchedAt: Date.now() };
  return keys;
}

/** Verifies a Firebase ID token end to end and returns the uid and verified email, or throws.
 *
 *  Every failure path throws. There is deliberately no "partially verified" return shape for a
 *  caller to misread as success.
 *
 *  @param projectId The Firebase project this app is. Both `aud` and the tail of `iss` must equal
 *                   it — without that comparison a token minted by ANY other Firebase project
 *                   would verify here, because Google signed that one too.
 *  @param fetchKeys Injected so tests can supply a key pair they control. */
export async function verifyFirebaseIdToken(
  token: string,
  projectId: string,
  fetchKeys: KeyFetcher = fetchFirebaseKeys,
): Promise<FirebaseClaims> {
  if (!token) throw new Error("empty token");

  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");

  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
  // Pinning the algorithm is what stops a token whose header says {"alg":"none"} — or a symmetric
  // alg keyed on the public key — from taking the verification path at all.
  if (header.alg !== "RS256") throw new Error("unexpected alg");
  if (!header.kid) throw new Error("token carries no key id");

  const jwk = (await fetchKeys()).find((k) => (k as { kid?: string }).kid === header.kid);
  if (!jwk) throw new Error("unknown signing key");

  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("bad signature");

  const claims = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));

  if (claims.aud !== projectId) throw new Error("token was not issued for this app");
  if (claims.iss !== `https://securetoken.google.com/${projectId}`) throw new Error("bad issuer");
  if (!claims.exp || claims.exp * 1000 <= Date.now()) throw new Error("token expired");
  if (!claims.sub) throw new Error("token carries no uid");
  if (!claims.email) throw new Error("token carries no email");
  // A Google account can carry an address nobody has demonstrated control of. Issuing against one
  // would put a stranger's address in a signed licence.
  if (claims.email_verified !== true) {
    throw new Error("email is not verified on this Google account");
  }

  return { uid: String(claims.sub), email: String(claims.email).toLowerCase() };
}
