class_name LicenceCheck
extends RefCounted
## Verifies an activation licence, offline, against a public key baked into the binary.
##
## Lothal asks for a verified email address before it opens. The verifying happens on the web —
## a page that can sit behind a CAPTCHA and Google sign-in — and what comes back here is a
## signed statement of the outcome. This file is the whole of the app's side of that: it reads
## a document, decides whether the maintainer really wrote it, and reports the email inside.
##
## ---------------------------------------------------------------------------
## WHY THIS MAKES NO NETWORK REQUEST
## ---------------------------------------------------------------------------
##
## The obvious design phones the issuing service at launch and asks "is this licence good?".
## That design is worse in every direction that matters. It makes an offline machine a broken
## machine, on a tool whose users are quite reasonably at a flying field with no signal. It
## makes the issuing service a launch-time dependency, so an outage or a shut-down project
## bricks every install at once. And it buys nothing: the answer would be checked by the same
## client that could be patched to ignore it.
##
## So the licence is self-contained and verified here, with arithmetic, from bytes on disk. The
## backend is a one-time issuing service that the app never speaks to — not at activation, not
## at launch, not ever. Activation is a copy-paste, which is why the web page exists.
##
## The cost of that choice is that a licence can be shared, because anything self-contained can
## be copied. That is answered socially rather than cryptographically — see WHAT THIS DOES NOT
## DEFEND AGAINST below.
##
## ---------------------------------------------------------------------------
## WHY THERE IS NO EXPIRY
## ---------------------------------------------------------------------------
##
## An expiring licence needs a renewal path, and this app has no network, so there isn't one. A
## licence that lapsed would stop a working install for a reason its owner could not diagnose
## and could not fix from the field. Worse, the clock it would be judged against is the user's
## own: a machine with a wrong date would revoke itself by accident. `issued` is recorded
## because it is useful in a support conversation, and it is deliberately never enforced.
##
## ---------------------------------------------------------------------------
## WHY THE KEY IS NUMBERED
## ---------------------------------------------------------------------------
##
## The update-signing key cannot be rotated — its public half is baked into copies of Lothal
## already on disk, and a compromise there is permanent (see update_check.gd). This key is
## different: it lives in a cloud secret store, reachable by anyone who gains project access,
## so the odds of it leaking are higher and the consequence of that being unfixable is
## unacceptable. `key_id` exists from the first release so a future build can ship a second
## public key and issue against it, rather than the leak being a dead end.
##
## The map is `key_id` -> path, and an id not in it is refused. That is what makes the field a
## rotation mechanism rather than a decoration: an attacker cannot name a key of their own.
##
## ---------------------------------------------------------------------------
## FAILING CLOSED
## ---------------------------------------------------------------------------
##
## Every path returns `valid = false` except the one where a real signature over a well-formed
## payload verified against a key we shipped. Missing file, empty file, junk, a tampered byte,
## an unknown key id, a schema from the future: all the same answer, which is the activation
## screen. Missing and tampered MUST land in the same place — if a corrupt licence produced a
## different outcome from an absent one, the difference would eventually be an escape hatch.
##
## Tests assert the absence of validity for each malformed input, and every check here has been
## mutation-tested: commented out, the suite fails. A verifier that returned false for
## everything would pass a happy-path-only suite, which is precisely the shape of the bug that
## matters here — an activation gate nobody can get through is loud and gets fixed on day one,
## and one that accepts anything looks exactly like working code.
##
## ---------------------------------------------------------------------------
## WHAT THIS DOES NOT DEFEND AGAINST
## ---------------------------------------------------------------------------
##
## Lothal is a Godot export, and a Godot export decompiles in about ten minutes with gdsdecomp
## (release.md §2). Anyone willing to do that can delete the call to this function. Nothing in
## this file pretends otherwise, and no amount of cleverness here would change it — the check
## and the code that honours it live on the attacker's machine.
##
## That is accepted, because the goal is not to defeat a determined attacker. It is to make the
## ordinary, honest path go through a verified email, so there is a way to tell people that a
## new version exists. Someone who decompiles the binary to skip a free sign-in was never going
## to be on the mailing list anyway.
##
## Sharing is answered the same way. The email is inside the signed payload and the app shows
## it, permanently, so a shared licence advertises whose it is. Making a licence unshareable
## would mean binding it to hardware, which means a machine id, which means an unbind request
## when someone buys a new laptop, which means a support inbox and a network call — and it
## would cost the offline property above, which is worth more than the leak it would prevent.

## Bumped when the licence's shape changes incompatibly. A build that meets a schema it does not
## understand refuses rather than reading the fields it happens to recognise.
const SCHEMA := 1

## The `key_id` -> public key table lives in rust/src/licence.rs, baked in at compile time, and
## is reached through `Licence.knows_key_id()`. It used to be a map to `res://keys/*.pem` here;
## that made the trust anchor a swappable file in the pck, so it moved into the binary. Keeping
## a second copy of the id list in GDScript would only create something to drift.

## Where the licence lives once accepted. Written byte-for-byte as it arrived — see `store()`.
const LICENCE_PATH := "user://licence.json"


## The outcome of verifying a licence. `valid` is the only field a caller may branch on, and it
## is false on every error, so a caller that forgets to check the others cannot open the app on
## a document that did not verify.
class Result extends RefCounted:
	var valid := false
	## The address inside the signed payload. Empty unless `valid`. Displayed to the user, which
	## is the entire anti-sharing mechanism.
	var email := ""
	## Why verification produced nothing. For logs and tests only — never shown to the user, who
	## learns nothing actionable from "signature did not verify" and would only learn from it
	## which mutation to try next.
	var reason := ""

	static func none(why: String) -> Result:
		var r := Result.new()
		r.reason = why
		return r


## Verifies a licence document and reports the address inside it.
##
## `body` is the raw bytes exactly as they were read from disk or pasted — bytes rather than
## String because the signature covers an exact byte sequence, and a round trip through String
## normalisation is precisely the kind of invisible mutation that turns a valid licence into a
## rejected one on somebody else's machine.
##
## `key` overrides the shipped public key and exists so the suite can sign fixtures with a
## throwaway pair. It accepts a CryptoKey (exported to PKCS#8 PEM here) or a PEM string; it
## defaults to null, which loads the real key. The injectable seam must never be the path
## production takes by accident, and it is not a bypass — it selects WHICH key verifies, never
## whether one does. The verification arithmetic itself is compiled (rust/src/licence.rs).
static func verify(body: PackedByteArray, key: Variant = null) -> Result:
	if body.is_empty():
		return Result.none("empty body")

	var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(envelope) != TYPE_DICTIONARY:
		return Result.none("body is not a JSON object")

	var doc: Dictionary = envelope
	if not doc.has("payload") or typeof(doc["payload"]) != TYPE_STRING:
		return Result.none("no payload")
	if not doc.has("signature") or typeof(doc["signature"]) != TYPE_STRING:
		return Result.none("no signature")

	var payload_text: String = doc["payload"]

	var inner: Variant = JSON.parse_string(payload_text)
	if typeof(inner) != TYPE_DICTIONARY:
		return Result.none("payload is not a JSON object")
	var licence: Dictionary = inner

	# `key_id` is read here, BEFORE anything has been verified, because it selects the key the
	# verification will use — a chicken-and-egg that is safe only for this one narrow purpose.
	#
	# An attacker controls this number, and all it lets them do is choose which of OUR public
	# keys their forgery is checked against. Every one of those requires a private half they do
	# not have, and an id naming no key at all is refused outright. The field is also inside the
	# signed payload, so on the success path it could not have been altered after issuing.
	#
	# What must never happen is any OTHER field being trusted from this parse. Everything below
	# the signature check is read from the same dictionary only because the bytes it came from
	# are the bytes that verified — the parse is of `payload_text`, which is the exact string
	# the signature covers, so re-parsing it afterwards would return an identical dictionary.
	if not licence.has("key_id"):
		return Result.none("no key_id")
	var key_id := int(licence["key_id"])
	if not Licence.knows_key_id(key_id):
		return Result.none("unknown key_id %d" % key_id)

	# The signed unit is the payload STRING, exactly as it sits in the envelope — never a
	# re-serialisation of the dictionary above. Signing a round-tripped dictionary instead makes
	# verification depend on key ordering and float formatting agreeing between the issuing
	# service and Godot's JSON writer, which they do not reliably do. The failure mode of that
	# mistake is a signature that verifies on the maintainer's machine and rejects every licence
	# in the field. This rule is already load-bearing in update_check.gd for the same reason.
	if not _verify_signature(payload_text, doc["signature"] as String, key_id,
			_resolve_key_pem(key)):
		return Result.none("signature did not verify")

	if int(licence.get("schema", 0)) != SCHEMA:
		return Result.none("unsupported schema")

	var email := str(licence.get("email", ""))
	# A signed licence should never carry a malformed address, so this check is about the case
	# where something upstream went wrong rather than about hostile input — an issuing bug that
	# signed an empty string would otherwise activate the app and show "Activated — ", which
	# quietly removes the only thing discouraging licence sharing.
	if not is_plausible_email(email):
		return Result.none("malformed email")

	var result := Result.new()
	result.valid = true
	result.email = email
	return result


## Reads and verifies the stored licence, if there is one.
##
## A missing file returns the same shape of failure as a corrupt one, deliberately: the app's
## two states are "verified" and "not verified", and any third state is a door.
static func verify_stored(key: Variant = null) -> Result:
	if not FileAccess.file_exists(LICENCE_PATH):
		return Result.none("no licence stored")

	var file := FileAccess.open(LICENCE_PATH, FileAccess.READ)
	if file == null:
		return Result.none("licence file unreadable")

	return verify(file.get_buffer(file.get_length()), key)


## Writes an accepted licence to disk, byte for byte as it was received.
##
## Worth being precise about what this does and does not protect against, because the obvious
## statement of it is wrong and the wrong version invites the wrong fix.
##
## Re-serialising the ENVELOPE is survivable. Parsing and re-writing it changes whitespace and key
## order, but the `payload` string is carried across as a string value and comes back identical,
## so the signature still covers what it covered. A test that only checks the envelope round trip
## therefore proves very little — Godot's writer happens to reproduce this shape byte for byte,
## and the check passes whether or not the code is doing the right thing.
##
## Re-serialising the PAYLOAD is fatal, and silently so. Parsing the inner document and writing it
## back out reorders keys, reformats numbers, and re-escapes strings, and the signature covers the
## exact bytes that were signed rather than the meaning behind them. The failure appears on the
## user's machine on the SECOND launch — activation works, then the app asks again for ever — and
## it cannot be reproduced by anyone who has not stored a licence and then read it back.
##
## So: the whole document goes down verbatim. Not because every alternative corrupts it, but
## because verbatim is the only rule with no cases to get right, and the cost of following it is
## one `store_buffer` instead of one `store_string`.
static func store(body: PackedByteArray) -> bool:
	var file := FileAccess.open(LICENCE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(body)
	file.close()
	return true


## Removes the stored licence. Used by the "not me" path on the activation screen; also the
## thing to call when a support conversation needs a clean slate.
static func clear() -> void:
	if FileAccess.file_exists(LICENCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LICENCE_PATH))


## A deliberately loose sanity check: one `@`, something either side, a dot in the domain, and
## no whitespace anywhere.
##
## It is not an RFC 5322 validator and must not become one. The real validation happened when
## Google authenticated the address; anything stricter here can only reject addresses that
## genuinely exist, and the failure it would cause — a paying, verified user who cannot open the
## app and cannot see why — is far worse than the one it would prevent.
static func is_plausible_email(email: String) -> bool:
	if email.is_empty() or email.length() > 254:
		return false
	if email.contains(" ") or email.contains("\t") or email.contains("\n") or email.contains("\r"):
		return false

	var parts := email.split("@", false)
	if parts.size() != 2:
		return false
	if (parts[0] as String).is_empty():
		return false

	var domain: String = parts[1]
	return domain.contains(".") and not domain.begins_with(".") and not domain.ends_with(".")


## The public key PEM the verification runs against: an injected CryptoKey exported to PKCS#8
## (the test suite's throwaway pairs), an injected PEM string, or empty to load the real shipped
## key. Godot's CryptoKey.save writes the public half as PKCS#8, the same format as the shipped
## activation_public.pem, so the Rust verifier parses both identically.
static func _resolve_key_pem(key: Variant) -> String:
	if typeof(key) == TYPE_STRING:
		return key
	if key is CryptoKey:
		var path := "user://licence_verify_key.pub"
		if key.save(path, true) != OK:
			return ""
		var pem := FileAccess.get_file_as_string(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return pem
	return ""


## RSA-PKCS#1 v1.5 over SHA-256 of the payload, against the public key `key_id` names.
##
## Both the arithmetic AND the key are compiled (rust/src/licence.rs). With no injected key
## this calls `Licence.verify`, which reaches a PEM baked into the binary at compile time and
## cannot be pointed anywhere else — no file is read, so there is no file to swap. That is the
## whole change: the trust anchor used to be `res://keys/activation_public.pem` inside the pck,
## and repacking the archive with a different PEM took over verification with no decompiler and
## no code edit.
##
## `key_pem` is non-empty only when the suite injects a throwaway pair, and that path calls the
## PEM-taking entry point instead. It is not reachable from any production call site — but be
## clear-eyed about what it is: verifying against a caller-supplied key is not verification.
## It survives because the alternative is a test suite that cannot sign its own fixtures, and
## because anyone able to pass an argument here can already edit the GDScript that calls it.
static func _verify_signature(payload: String, signature_b64: String, key_id: int,
		key_pem: String) -> bool:
	if key_pem == "":
		return Licence.verify(payload, signature_b64, key_id)
	return Licence.verify_signature(payload, signature_b64, key_pem)
