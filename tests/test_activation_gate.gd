class_name TestActivationGate
extends RefCounted
## The gate as the user meets it: a screen, a paste box, and an app that does or does not appear.
##
## test_licence_check.gd proves the verifier. This file proves the thing built on top of it, which
## is a separate question and the one with the embarrassing failure modes — a verifier that is
## correct and a screen that opens the app anyway is exactly as broken as no verifier at all.
##
## The three things asserted here that a plausible implementation gets wrong:
##
## 1. **A refused key leaves the app closed.** Not "shows a message" — the assertion is on the
##    stored licence and on what the screen reports, so a screen that displayed an error and
##    proceeded would fail.
##
## 2. **A refused key writes nothing.** An implementation that stored first and verified second
##    would pass every "was it refused?" check and still leave a forged licence on disk, which
##    the NEXT launch would then re-verify — and reject, giving a user who typed one wrong
##    character an app that is now permanently unactivatable until they find a file they do not
##    know the name of.
##
## 3. **The accepted bytes are stored verbatim.** Round-tripping the licence through Godot's JSON
##    writer produces a document that verifies now and fails on the next launch, because the
##    signature covers the payload string exactly as issued. That bug is invisible in any test
##    that only checks the first activation, so this file re-verifies from disk afterwards.
##
## These run against `user://` and clean up after themselves, because a licence left behind by the
## suite would silently activate the developer's own build and hide the gate from the person most
## likely to notice something wrong with it.

const KEY_BITS := 2048


static func run() -> Array:
	var results: Array = []

	results.append_array(_test_a_valid_key_activates_and_persists())
	results.append_array(_test_the_licence_is_stored_verbatim())
	results.append_array(_test_a_reserialised_payload_no_longer_verifies())
	results.append_array(_test_a_refused_key_stores_nothing())
	results.append_array(_test_the_stored_licence_survives_a_relaunch())
	results.append_array(_test_a_tampered_stored_licence_is_refused())
	results.append_array(_test_a_missing_licence_reads_as_not_activated())

	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A licence signed by a throwaway key. Note these fixtures CANNOT activate a real build: the
## screen and the gate both verify through the production path, against the shipped public key.
## That is deliberate and it shapes this file — the tests below assert on `LicenceCheck.store()`
## and `verify_stored()` with an injected key rather than driving the screen's own accept path,
## because a test that could make the real gate open would be a test proving the gate does not
## work.
static func _envelope(email: String, key: CryptoKey) -> PackedByteArray:
	var payload := JSON.stringify({
		"schema": LicenceCheck.SCHEMA, "email": email, "issued": "2026-08-09", "key_id": 1,
	})
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(payload.to_utf8_buffer())
	var signature := Marshalls.raw_to_base64(
		Crypto.new().sign(HashingContext.HASH_SHA256, hashing.finish(), key))
	return JSON.stringify({"payload": payload, "signature": signature}).to_utf8_buffer()


static func _clear() -> void:
	LicenceCheck.clear()


# ---------------------------------------------------------------------------
# Storing and reading back
# ---------------------------------------------------------------------------

static func _test_a_valid_key_activates_and_persists() -> Array:
	_clear()
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var body := _envelope("someone@example.com", key)

	var stored := LicenceCheck.store(body)
	var read_back := LicenceCheck.verify_stored(key)

	_clear()
	return [
		TestResult.new("a valid licence is written", stored, "store()=%s" % stored),
		TestResult.new("the stored licence verifies on read-back", read_back.valid, read_back.reason),
		TestResult.new("the reported address is the signed one",
			read_back.email == "someone@example.com", read_back.email),
	]


## The byte-exactness of `store()`, pinned with a document Godot's own JSON writer would NOT
## reproduce.
##
## The compact envelope above is useless for this: Godot's writer emits exactly the same bytes it
## parsed, so a `store()` that round-tripped its input would pass a byte-comparison against it and
## the check would be decoration. An indented envelope is a valid licence — the signature covers
## the inner payload string, which whitespace between the envelope's keys does not touch — and it
## is one that a re-serialising `store()` provably mangles.
static func _test_the_licence_is_stored_verbatim() -> Array:
	_clear()
	var key := Crypto.new().generate_rsa(KEY_BITS)

	var compact := _envelope("someone@example.com", key)
	var parsed: Dictionary = JSON.parse_string(compact.get_string_from_utf8())
	var indented := JSON.stringify(parsed, "  ").to_utf8_buffer()

	LicenceCheck.store(indented)
	var on_disk := FileAccess.open(LicenceCheck.LICENCE_PATH, FileAccess.READ)
	var identical := on_disk != null and on_disk.get_buffer(on_disk.get_length()) == indented

	# It must also still verify from disk: storing verbatim is worthless if the bytes preserved
	# are ones the verifier then rejects.
	var read_back := LicenceCheck.verify_stored(key)

	_clear()
	return [
		TestResult.new("the fixture is one a re-serialising store() would change",
			indented != compact, "%d bytes indented vs %d compact" % [indented.size(), compact.size()]),
		TestResult.new("the licence is stored byte-for-byte as issued", identical,
			"%d bytes in, %d bytes on disk" % [indented.size(),
				on_disk.get_length() if on_disk != null else -1]),
		TestResult.new("and the verbatim bytes still verify", read_back.valid, read_back.reason),
	]


## The mutation that actually destroys a licence: re-serialising the inner PAYLOAD rather than the
## envelope. Nothing in the app does this, and this test exists so that nothing ever starts to —
## it is the one rewrite that produces a document which looks entirely well-formed and verifies
## nowhere, and its natural discovery point is a stranger's second launch.
static func _test_a_reserialised_payload_no_longer_verifies() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var envelope: Dictionary = JSON.parse_string(_envelope("someone@example.com", key).get_string_from_utf8())

	# Parse the payload and write it back out. Semantically identical, byte-wise not.
	var payload: Dictionary = JSON.parse_string(envelope["payload"])
	var rewritten := JSON.stringify(payload, "  ")

	var result := LicenceCheck.verify(
		JSON.stringify({"payload": rewritten, "signature": envelope["signature"]}).to_utf8_buffer(), key)

	return [
		TestResult.new("the rewrite really changed the bytes", rewritten != envelope["payload"],
			"%d vs %d chars" % [rewritten.length(), (envelope["payload"] as String).length()]),
		TestResult.new("a re-serialised payload no longer verifies",
			not result.valid and result.email.is_empty(), result.reason),
	]


static func _test_a_refused_key_stores_nothing() -> Array:
	_clear()
	var crypto := Crypto.new()
	var ours := crypto.generate_rsa(KEY_BITS)
	var theirs := crypto.generate_rsa(KEY_BITS)
	var results: Array = []

	# The screen drives the real verifier. Everything here must be refused, and — the part that
	# matters — must leave no file behind for the next launch to trip over.
	var screen := ActivationScreen.new(LothalVersion.ACTIVATION_URL)
	# _ready() builds the widgets the screen writes its message into; without it, submit() would
	# fault on a null label rather than exercising the path under test.
	screen._ready()

	var bad := {
		"a licence from another key": _envelope("someone@example.com", theirs),
		"an empty paste": PackedByteArray(),
		"a half-copied key": _envelope("someone@example.com", ours).slice(0, 200),
		"an html error page": "<!doctype html><title>404</title>".to_utf8_buffer(),
	}
	for label in bad:
		var accepted: bool = screen.submit(bad[label])
		var left_behind := FileAccess.file_exists(LicenceCheck.LICENCE_PATH)
		results.append(TestResult.new("%s is refused and stores nothing" % label,
			not accepted and not left_behind,
			"accepted=%s file_on_disk=%s" % [accepted, left_behind]))

	screen.free()
	_clear()
	return results


static func _test_the_stored_licence_survives_a_relaunch() -> Array:
	_clear()
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var body := _envelope("pilot@example.com", key)
	LicenceCheck.store(body)

	# "A relaunch" is exactly this: nothing in memory, read the file, verify it again. The bug
	# this catches — a licence mutated by the act of saving it — cannot be seen any other way,
	# because the first verification happens on the bytes that arrived rather than on the file.
	var first := LicenceCheck.verify_stored(key)
	var second := LicenceCheck.verify_stored(key)

	_clear()
	return [
		TestResult.new("the licence verifies from disk", first.valid, first.reason),
		TestResult.new("and again on the launch after that",
			second.valid and second.email == "pilot@example.com", second.reason),
	]


static func _test_a_tampered_stored_licence_is_refused() -> Array:
	_clear()
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var body := _envelope("someone@example.com", key)

	# One character changed in the file, the way an editor or a careless hand would do it. This is
	# the "a licence with one character changed is rejected" case from the release checklist.
	var text := body.get_string_from_utf8().replace("someone@example.com", "someoneelse@example.com")
	var file := FileAccess.open(LicenceCheck.LICENCE_PATH, FileAccess.WRITE)
	file.store_buffer(text.to_utf8_buffer())
	file.close()

	var result := LicenceCheck.verify_stored(key)
	_clear()

	return [
		TestResult.new("an edited licence file is refused", not result.valid and result.email.is_empty(),
			"valid=%s email=%s reason=%s" % [result.valid, result.email, result.reason]),
	]


static func _test_a_missing_licence_reads_as_not_activated() -> Array:
	_clear()
	var result := LicenceCheck.verify_stored()

	# Missing and tampered must be the same answer. Asserted explicitly because the tempting
	# implementation returns a distinguishable "not found" that a caller then treats as a
	# different, softer case.
	return [
		TestResult.new("no licence file reads as not activated",
			not result.valid and result.email.is_empty(), result.reason),
	]
