#!/usr/bin/env bash
# Publish a packaged release to the GCS bucket, then prune to the newest three.
#
#   ./release/upload.sh 0.1.0 --dry-run     # show every action, change nothing
#   ./release/upload.sh 0.1.0
#
# Ordering matters and is not arbitrary. The zips go up FIRST and latest.json LAST, because
# latest.json is what tells every installed Lothal that a release exists — publishing it before
# its payloads means a window where clients are pointed at URLs that 404.
#
# ---------------------------------------------------------------------------
# WHY THE PRUNE IS HERE AND NOT A LIFECYCLE RULE
# ---------------------------------------------------------------------------
#
# GCS lifecycle can delete by age, by storage class, or by numNewerVersions. None of those is
# "keep the newest three releases". numNewerVersions counts versions of ONE object key, and
# every release here lives under its own v<version>/ prefix, so those are unrelated objects and
# the rule would never fire. An age rule does fire — on the calendar, which means a quiet
# quarter deletes the current release along with the old ones.
#
# So the prune is explicit, it runs after a successful upload, and it never touches the release
# it just published. --dry-run prints the deletions instead of making them; run it that way the
# first time, because the failure mode of getting this wrong is deleting the download every
# link on the internet points at.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: release/upload.sh <version> [--dry-run]" >&2; exit 1; }
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

BUCKET="${LOTHAL_BUCKET:-gs://lothal-releases}"
KEEP="${LOTHAL_KEEP_RELEASES:-3}"
SRC="build/release/v$VERSION"

[ -d "$SRC" ] || { echo "error: nothing packaged at $SRC — run release/package.sh $VERSION" >&2; exit 1; }
[ -f "$SRC/latest.json" ] || { echo "error: no manifest at $SRC/latest.json" >&2; exit 1; }

command -v gsutil >/dev/null 2>&1 || { echo "error: gsutil not on PATH (install the gcloud SDK)" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  would run: $*"
  else
    "$@"
  fi
}

echo "==> uploading payloads to $BUCKET/v$VERSION/"
for file in "$SRC"/*.zip "$SRC/SHA256SUMS.txt"; do
  # Long cache lifetime: a versioned URL's contents never change, so every re-download after
  # the first should be served by Cloudflare's edge rather than billed as GCS egress.
  run gsutil -h "Cache-Control:public, max-age=31536000, immutable" \
    cp "$file" "$BUCKET/v$VERSION/$(basename "$file")"
done

echo "==> uploading manifest last"
# The opposite cache policy, for the opposite reason: this file MUST change, and a stale copy
# at the edge is a release nobody is told about. Five minutes is short enough that a bad
# manifest can be replaced quickly and long enough that launches do not each cost an origin hit.
run gsutil -h "Cache-Control:public, max-age=300" cp "$SRC/latest.json" "$BUCKET/latest.json"

echo "==> pruning to the newest $KEEP releases"
# Sorted by version number, not by upload time or lexically: "v0.10.0" sorts before "v0.9.0" as
# text, which would delete the newest release and keep the oldest — the same double-digit bug
# the in-app version comparison guards against, in the one place where it destroys data.
EXISTING=$(gsutil ls -d "$BUCKET/v*/" 2>/dev/null | sed 's#.*/v\([^/]*\)/#\1#' | sort -t. -k1,1n -k2,2n -k3,3n || true)

if [ -z "$EXISTING" ]; then
  echo "  no release prefixes found; nothing to prune"
else
  TOTAL=$(echo "$EXISTING" | wc -l | tr -d ' ')
  echo "  $TOTAL release(s) in the bucket: $(echo "$EXISTING" | tr '\n' ' ')"
  if [ "$TOTAL" -gt "$KEEP" ]; then
    DOOMED=$(echo "$EXISTING" | head -n "$((TOTAL - KEEP))")
    for old in $DOOMED; do
      # The release just published is never a candidate, whatever the sort says. This is belt
      # and braces against a version string that sorts oddly, because the cost of the sort
      # being wrong once is the live download disappearing.
      if [ "$old" = "$VERSION" ]; then
        echo "  refusing to prune v$old — it is the release being published"
        continue
      fi
      echo "  deleting v$old"
      run gsutil -m rm -r "$BUCKET/v$old/"
    done
  else
    echo "  nothing to prune"
  fi
fi

echo
if [ "$DRY_RUN" = "1" ]; then
  echo "dry run — nothing was uploaded or deleted."
else
  echo "published: $BUCKET/v$VERSION/"
  echo "manifest:  $BUCKET/latest.json"
  echo
  echo "Verify the live manifest before announcing:"
  echo "  curl -s https://dl.meetdev.in/latest.json | python3 -m json.tool | head"
fi
