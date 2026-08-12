/**
 * dl.meetdev.in — the download edge in front of the GCS bucket.
 *
 * This exists instead of pointing a CNAME straight at Google's storage host, and the reason is
 * worth knowing before you change it. GCS's CNAME path requires the bucket to be NAMED for the
 * domain ("dl.meetdev.in"), requires proving domain ownership in Google Search Console, and —
 * the part that actually rules it out — does not serve HTTPS on that leg. Cloudflare would then
 * be terminating TLS for the visitor and talking to the origin in the clear, which is precisely
 * the wire an attacker would want for a binary download.
 *
 * A Worker fetches the object over HTTPS from storage.googleapis.com, so the whole path is
 * encrypted, the bucket can be called anything, nothing needs verifying, and there is somewhere
 * to count downloads — which the bucket on its own cannot do.
 */

const BUCKET = "lothal-releases";
const ORIGIN = `https://storage.googleapis.com/${BUCKET}`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Only GET and HEAD reach the bucket. The Worker is public and unauthenticated, so anything
    // that could write must not be proxied — a stray PUT arriving at a bucket that later gets a
    // permissive IAM binding is the kind of mistake that is invisible until it isn't.
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    let path = url.pathname.replace(/^\/+/, "");

    // Stable aliases the README and landing page can link to without knowing the version.
    // /latest/macos, /latest/windows and /latest/linux resolve through the manifest, so a
    // published release updates every download link on the internet at once.
    if (path === "latest/macos" || path === "latest/windows" || path === "latest/linux") {
      const platform = path.split("/")[1];
      const manifest = await fetch(`${ORIGIN}/latest.json`, { cf: { cacheTtl: 300 } });
      if (!manifest.ok) return new Response("No current release", { status: 503 });

      const envelope = await manifest.json();
      // The signature is NOT verified here and must not be relied on here — this is a
      // convenience redirect, and the authority for "is this really our build" lives in the
      // client that checks the signature against a key baked into its own binary. A check
      // performed by the same server that serves the file proves nothing about that server.
      const payload = JSON.parse(envelope.payload);
      const target = payload?.downloads?.[platform]?.url;
      if (!target) return new Response("No build for that platform", { status: 404 });

      ctx.waitUntil(count(env, platform, payload.version));
      return Response.redirect(target, 302);
    }

    // Directory traversal has no meaning against an object store, but a path that walks out of
    // the prefix would still let someone address objects this Worker was never meant to expose.
    if (path.includes("..") || path === "") {
      return new Response("Not found", { status: 404 });
    }

    const response = await fetch(`${ORIGIN}/${path}`, {
      cf: {
        // Versioned artifacts never change, so they cache hard. latest.json must not — a stale
        // manifest is a release nobody is told about.
        cacheTtl: path === "latest.json" ? 300 : 31536000,
        cacheEverything: true,
      },
    });

    const headers = new Headers(response.headers);

    // Cache-Control is SET here, not inherited from the bucket. Cloudflare's zone-level Browser
    // Cache TTL overrides whatever the origin sent — the bucket serves latest.json with
    // max-age=300 and the edge was rewriting it to max-age=14400. Four hours is a long time to
    // be unable to withdraw a bad manifest, and it delays every release announcement by up to
    // the same. Setting the header on the response we return wins over the zone default.
    headers.set(
      "Cache-Control",
      path === "latest.json"
        ? "public, max-age=300, must-revalidate"
        : "public, max-age=31536000, immutable"
    );
    // The landing page reads latest.json from a different origin, so it needs CORS. Only this
    // one file: the zips are fetched by navigation, not by script, and a blanket wildcard would
    // be a permission granted for no reason.
    if (path === "latest.json") {
      headers.set("Access-Control-Allow-Origin", "*");
    }
    headers.set("X-Content-Type-Options", "nosniff");

    // Named platforms only. A two-way ternary here silently filed every Linux download under
    // "windows" the moment a third platform existed, and a counter that lies is worse than one
    // that abstains — so an unrecognised zip counts as "unknown" rather than as the last branch.
    if (response.ok && path.endsWith(".zip")) {
      const platform =
        ["macos", "windows", "linux"].find((p) => path.includes(p)) ?? "unknown";
      ctx.waitUntil(count(env, platform, "direct"));
    }

    return new Response(response.body, { status: response.status, headers });
  },
};

/**
 * Download counting, in whatever KV namespace is bound as COUNTERS.
 *
 * Deliberately fire-and-forget through ctx.waitUntil: a counter that could fail a download is
 * a worse thing than a counter that occasionally misses one. Unbound KV is not an error — the
 * Worker runs fine without it and simply counts nothing.
 */
async function count(env, platform, version) {
  if (!env.COUNTERS) return;
  const key = `dl:${version}:${platform}`;
  try {
    const current = parseInt((await env.COUNTERS.get(key)) || "0", 10);
    await env.COUNTERS.put(key, String(current + 1));
  } catch (_) {
    // Ignored on purpose. See above.
  }
}
