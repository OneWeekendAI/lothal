#!/usr/bin/env bash
# Generate the update-signing key pair. RUN THIS ONCE, EVER.
#
# The private key signs every release manifest Lothal will ever trust. The public half is
# compiled into the binary, which is what makes this key impossible to rotate quietly: every
# copy of Lothal already installed verifies against the key that was baked in when it was
# built. Replacing the key means those installs stop seeing updates — permanently, silently —
# and the only route back is telling people to download a new build by hand.
#
# So the private key does not go in the repo, does not go in the bucket, and does not go in a
# CI secret. It lives in the macOS keychain-protected directory below and in one offline backup
# you make yourself. If it leaks, whoever has it can hand every Lothal install any payload they
# like; if it is lost, the update channel is dead for everyone already running Lothal.

set -euo pipefail
cd "$(dirname "$0")/.."

PRIVATE_DIR="$HOME/.lothal"
PRIVATE_KEY="$PRIVATE_DIR/update_private.pem"
PUBLIC_KEY="keys/update_public.pem"

if [ -f "$PRIVATE_KEY" ]; then
  echo "error: a signing key already exists at $PRIVATE_KEY" >&2
  echo "       Refusing to overwrite it. Generating a new pair strands every installed copy" >&2
  echo "       of Lothal on the old public key — they would never see another update." >&2
  exit 1
fi

mkdir -p "$PRIVATE_DIR" keys
chmod 700 "$PRIVATE_DIR"

# 4096-bit RSA. Godot's Crypto verifies PKCS#1 v1.5 over SHA-256 natively, so this needs no
# GDExtension and no Apple Developer ID — the trust here is entirely Lothal's own, which is the
# point: it works exactly as well on an unsigned build as on a notarised one.
openssl genrsa -out "$PRIVATE_KEY" 4096
chmod 600 "$PRIVATE_KEY"
openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"

echo
echo "private key: $PRIVATE_KEY   (BACK THIS UP OFFLINE. NEVER COMMIT IT.)"
echo "public key:  $PUBLIC_KEY    (commit this — it ships inside the binary)"
echo
echo "Verify the pair matches before you ship anything:"
echo "  openssl rsa -in $PRIVATE_KEY -pubout | diff - $PUBLIC_KEY && echo MATCHED"
