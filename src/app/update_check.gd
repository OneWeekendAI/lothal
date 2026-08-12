class_name UpdateCheck
extends RefCounted
## Reads the release manifest and decides whether to offer an update.
##
## Lothal ships unsigned by Apple and Microsoft, which means the usual chain of trust — you
## downloaded this from a publisher the OS recognises — does not exist here. That raises the
## stakes on this file rather than lowering them: an update channel is a path from a server to
## code on someone's machine, and if the only thing guarding it is HTTPS then whoever controls
## the bucket controls every Lothal install.
##
## ---------------------------------------------------------------------------
## WHY THE SHA256 IN THE MANIFEST IS NOT ENOUGH ON ITS OWN
## ---------------------------------------------------------------------------
##
## The obvious design publishes a hash next to the zip and checks the download against it. It
## reads like security and is worth almost nothing, because the hash is served from the SAME
## bucket as the payload. Anyone who can replace the zip can replace the hash in the same
## breath. It defends against a corrupted download and against nothing else.
##
## So the manifest carries an RSA signature over its own contents, made with a key that lives
## on the maintainer's machine and never touches the bucket or the repo. The public half is
## baked into the binary at `res://keys/update_public.pem`. A bucket compromise then yields an
## attacker who can delete releases or serve stale ones, but not one who can point Lothal at a
## payload of their choosing — that requires the private key, which is not there to steal.
##
## Verification is implemented and enforced from v0.1.0, on a build that offers no in-app
## download at all. That ordering is deliberate. If the field were merely reserved and checked
## later, every v0.1.0 client in the wild would be a client that accepts unsigned manifests
## forever, and the install base most in need of the protection is the one that predates it.
##
## ---------------------------------------------------------------------------
## FAILING CLOSED
## ---------------------------------------------------------------------------
##
## Every rejection path here returns "no update available", never "proceed anyway". The failure
## that matters is not a missed notification — the user loses nothing and finds the release on
## the site — it is an update banner shown on the strength of a document that did not verify.
## Tests assert the *absence* of an offer for each malformed input, because a parser that
## returns empty on everything would pass a test that only checked the happy path.

## Bumped when the manifest's shape changes incompatibly. A client that meets a schema it does
## not understand declines rather than guessing at the fields it recognises.
const SCHEMA := 1

const PUBLIC_KEY_PATH := "res://keys/update_public.pem"

## Platform keys used in the manifest's `downloads` block. All three are shipped as of 0.2.0.
const PLATFORM_MACOS := "macos"
const PLATFORM_WINDOWS := "windows"
const PLATFORM_LINUX := "linux"


## What a completed check found. `available` is the only field a caller needs to branch on,
## and it is false on every error, so a caller that forgets to check the others cannot show a
## banner for a manifest that failed to verify.
class Result extends RefCounted:
	var available := false
	var version := ""
	var notes_url := ""
	var download_url := ""
	var sha256 := ""
	## Human-readable reason the check produced nothing. For logs and tests only — never shown
	## to the user, who does not benefit from "signature verification failed" in a toast.
	var reason := ""

	static func none(why: String) -> Result:
		var r := Result.new()
		r.reason = why
		return r


## The platform string for the machine this is running on, or "" where Lothal does not ship.
static func current_platform() -> String:
	return platform_for_os_name(OS.get_name())


## The manifest key for an `OS.get_name()` value, or "" where Lothal does not ship.
##
## Split out from `current_platform` so the mapping is testable: read straight from OS, it can
## only ever be exercised for the machine running the suite, so the Linux arm would have been
## asserted by nothing until a Linux user reported that updates said "unsupported platform" —
## which is exactly how it was missing from 0.2.0's release despite a Linux build existing.
static func platform_for_os_name(os_name: String) -> String:
	match os_name:
		"macOS":
			return PLATFORM_MACOS
		"Windows":
			return PLATFORM_WINDOWS
		"Linux":
			return PLATFORM_LINUX
		_:
			return ""


## Parses and verifies a manifest, returning what should be offered to the user.
##
## `body` is the raw bytes as fetched — bytes rather than String because the signature is over
## the exact byte sequence that was signed, and a round trip through String normalisation is
## precisely the kind of invisible mutation that makes a valid signature fail.
##
## `platform` is injected rather than read from OS so the suite can exercise both platforms on
## whichever machine happens to be running the tests.
##
## `key` overrides the shipped public key and exists so the suite can sign fixtures with a
## throwaway pair. It defaults to null, which loads the real key — the injectable seam must
## never be the path production takes by accident.
static func parse_manifest(body: PackedByteArray, platform: String, installed_version: String,
		key: CryptoKey = null) -> Result:
	if body.is_empty():
		return Result.none("empty body")

	var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(envelope) != TYPE_DICTIONARY:
		return Result.none("body is not a JSON object")

	var doc: Dictionary = envelope
	if not doc.has("signature") or typeof(doc["signature"]) != TYPE_STRING:
		return Result.none("no signature")
	if not doc.has("payload") or typeof(doc["payload"]) != TYPE_STRING:
		return Result.none("no payload")

	# The signed unit is the payload STRING, exactly as it sits in the envelope. Signing a
	# re-serialised dictionary instead would make verification depend on key ordering and
	# float formatting matching between openssl and Godot's JSON writer, which they do not
	# reliably do — and the failure mode of that mistake is a signature that verifies on the
	# maintainer's machine and rejects every real release in the field.
	if not _verify(doc["payload"] as String, doc["signature"] as String, key):
		return Result.none("signature did not verify")

	var inner: Variant = JSON.parse_string(doc["payload"] as String)
	if typeof(inner) != TYPE_DICTIONARY:
		return Result.none("payload is not a JSON object")

	var manifest: Dictionary = inner
	if int(manifest.get("schema", 0)) != SCHEMA:
		return Result.none("unsupported schema")

	var offered := str(manifest.get("version", ""))
	if not LothalVersion.is_well_formed(offered):
		return Result.none("malformed version")

	if LothalVersion.compare(offered, installed_version) <= 0:
		return Result.none("not newer")

	if platform.is_empty():
		return Result.none("unsupported platform")

	var downloads: Variant = manifest.get("downloads", null)
	if typeof(downloads) != TYPE_DICTIONARY:
		return Result.none("no downloads block")

	var entry: Variant = (downloads as Dictionary).get(platform, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return Result.none("no build for this platform")

	var build: Dictionary = entry
	var url := str(build.get("url", ""))
	var digest := str(build.get("sha256", ""))

	# An https:// URL is required rather than preferred. The signature proves the maintainer
	# wrote this manifest; it says nothing about the transport that fetches what it points at,
	# and a signed manifest naming an http:// payload would hand a network attacker the very
	# substitution the signature exists to prevent.
	if not url.begins_with("https://"):
		return Result.none("download url is not https")

	# 64 hex characters or nothing. A blank or truncated digest must not read as "skip the
	# check" further down the line — that is how a verification step becomes decorative.
	if digest.length() != 64 or not digest.is_valid_hex_number():
		return Result.none("malformed sha256")

	var result := Result.new()
	result.available = true
	result.version = offered
	result.download_url = url
	result.sha256 = digest.to_lower()
	result.notes_url = str(manifest.get("notes_url", ""))
	return result


## RSA-PKCS#1 v1.5 over SHA-256 of the payload, against the public key shipped in the binary.
##
## Returns false on every failure including a missing or unreadable key file. A build whose key
## did not export cannot verify anything, and the correct behaviour there is to offer no
## updates at all rather than to fall back to trusting the document.
static func _verify(payload: String, signature_b64: String, key: CryptoKey = null) -> bool:
	if key == null:
		if not FileAccess.file_exists(PUBLIC_KEY_PATH):
			return false
		key = CryptoKey.new()
		if key.load(PUBLIC_KEY_PATH, true) != OK:
			return false

	var signature := Marshalls.base64_to_raw(signature_b64)
	if signature.is_empty():
		return false

	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return false
	hashing.update(payload.to_utf8_buffer())

	return Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), signature, key)
