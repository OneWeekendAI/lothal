class_name TestLicenceCheck
extends RefCounted
## The activation gate — the one piece of Lothal that stands between a user and the app.
##
## The failure modes here are asymmetric, and this file is shaped around that asymmetry.
##
## ---------------------------------------------------------------------------
## 1. THE BUG THAT LOOKS LIKE WORKING CODE
## ---------------------------------------------------------------------------
##
## A verifier that rejects everything is discovered within a minute: nobody can open the app.
## A verifier that ACCEPTS everything is invisible. It ships, it activates, every tester says
## it works, and the gate has simply never existed. That is the bug this file is built to catch,
## and almost every assertion below is a negative one — which creates its own trap, because a
## `verify()` that returned `Result.none()` unconditionally would satisfy all of them.
##
## So the suite is anchored by a positive check built from the SAME fixture builder that the
## negative cases mutate. Every rejection below is one field away from an accepted licence. If
## the accept path breaks, the anchor fails loudly instead of the negatives quietly passing for
## a reason that has nothing to do with what they claim to test.
##
## ---------------------------------------------------------------------------
## 2. "VERIFIED" WHERE NOTHING WAS VERIFIED
## ---------------------------------------------------------------------------
##
## The tamper cases use a REAL key pair and a REAL signature, and mutate the payload by a single
## character AFTER signing. A verifier doing nothing accepts that document and this suite fails.
## One fixture is signed with a DIFFERENT key than the one it is verified against, which catches
## the subtler variant: code that checks a signature's structure without ever binding it to a
## particular key.
##
## ---------------------------------------------------------------------------
## 3. THE KEY ID THAT IS READ BEFORE ANYTHING IS TRUSTED
## ---------------------------------------------------------------------------
##
## `key_id` is parsed out of an unverified payload, because it selects the key that does the
## verifying. The safety of that rests entirely on unknown ids being refused — if an unrecognised
## id fell through to a default key, or worse to "no key, so skip", the field would be an open
## door rather than a rotation mechanism. It is pinned here, and pinned specifically while a
## valid override key is being injected, so the check cannot pass merely because verification
## failed for some unrelated reason afterwards.
##
## ---------------------------------------------------------------------------
## 4. MISSING AND TAMPERED MUST BE THE SAME ANSWER
## ---------------------------------------------------------------------------
##
## Every rejection is asserted to produce `valid == false` AND an empty `email`. A result that
## said invalid but still carried an address would be one careless caller away from an app that
## shows "Activated — someone@example.com" on a forged document.

const KEY_BITS := 2048


static func run() -> Array:
	var results: Array = []

	results.append_array(_test_a_good_licence_activates())
	results.append_array(_test_a_tampered_payload_is_refused())
	results.append_array(_test_a_tampered_signature_is_refused())
	results.append_array(_test_another_key_is_refused())
	results.append_array(_test_an_unknown_key_id_is_refused())
	results.append_array(_test_a_future_schema_is_refused())
	results.append_array(_test_missing_fields_are_refused())
	results.append_array(_test_junk_never_crashes_and_never_activates())
	results.append_array(_test_a_malformed_email_is_refused())
	results.append_array(_test_real_addresses_are_not_rejected())
	results.append_array(_test_the_key_seam_defaults_to_the_real_key())

	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The licence payload that SHOULD be accepted. Every negative test starts here and breaks
## exactly one thing, which is what makes those tests evidence rather than decoration.
static func _payload_dict(email := "someone@example.com") -> Dictionary:
	return {
		"schema": LicenceCheck.SCHEMA,
		"email": email,
		"issued": "2026-08-09",
		"key_id": 1,
	}


static func _payload(email := "someone@example.com") -> String:
	return JSON.stringify(_payload_dict(email))


static func _sign(payload: String, key: CryptoKey) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(payload.to_utf8_buffer())
	return Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, hashing.finish(), key))


static func _envelope(payload: String, key: CryptoKey) -> PackedByteArray:
	return JSON.stringify({"payload": payload, "signature": _sign(payload, key)}).to_utf8_buffer()


## A rejection is only a rejection if it carries no address with it. Used by every negative case
## so that "invalid but here is the email anyway" cannot slip through as a pass.
static func _refused(label: String, result: LicenceCheck.Result) -> TestResult:
	return TestResult.new(label, not result.valid and result.email.is_empty(),
		"valid=%s email=%s reason=%s" % [result.valid, result.email, result.reason])


# ---------------------------------------------------------------------------
# The anchor: a real licence actually opens the app
# ---------------------------------------------------------------------------

static func _test_a_good_licence_activates() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var result := LicenceCheck.verify(_envelope(_payload(), key), key)

	return [
		TestResult.new("a signed licence is accepted", result.valid,
			"valid=%s reason=%s" % [result.valid, result.reason]),
		TestResult.new("the signed address is reported", result.email == "someone@example.com", result.email),
	]


# ---------------------------------------------------------------------------
# Tamper resistance — the checks a do-nothing verifier fails
# ---------------------------------------------------------------------------

static func _test_a_tampered_payload_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload()
	var signature := _sign(payload, key)

	# Signed honestly, then edited. This is the attack the signature exists to stop: someone
	# swaps in their own address and everything else about the document still looks right.
	var swapped := payload.replace("someone@example.com", "someoneelse@example.com")
	var swapped_result := LicenceCheck.verify(
		JSON.stringify({"payload": swapped, "signature": signature}).to_utf8_buffer(), key)

	# A flipped character somewhere harmless must fail too, otherwise the verifier is checking a
	# prefix or a length rather than the content. Built by editing the Dictionary and
	# re-stringifying rather than by a string replace over the serialised form: JSON.stringify
	# emits `"key":"value"` with no space, so a replace written with a space matches nothing,
	# leaves the payload pristine, and the test then asserts that an UNMODIFIED licence is
	# refused — which fails for the right reason only by accident.
	var nudged_dict := _payload_dict()
	nudged_dict["issued"] = "2026-08-10"
	var nudged_result := LicenceCheck.verify(
		JSON.stringify({"payload": JSON.stringify(nudged_dict), "signature": signature}).to_utf8_buffer(), key)

	return [
		_refused("a swapped email is refused", swapped_result),
		_refused("any edit after signing is refused", nudged_result),
	]


static func _test_a_tampered_signature_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload()
	var signature := _sign(payload, key)

	# One base64 character changed. Picking a replacement that differs from the original matters:
	# substituting a character for itself would leave the signature intact and the test would
	# assert that a VALID licence is refused, passing only while the verifier was broken.
	var first: String = signature.substr(0, 1)
	var mutated: String = ("B" if first != "B" else "C") + signature.substr(1)

	var edited := LicenceCheck.verify(
		JSON.stringify({"payload": payload, "signature": mutated}).to_utf8_buffer(), key)

	var empty := LicenceCheck.verify(
		JSON.stringify({"payload": payload, "signature": ""}).to_utf8_buffer(), key)

	var not_base64 := LicenceCheck.verify(
		JSON.stringify({"payload": payload, "signature": "!!!not base64!!!"}).to_utf8_buffer(), key)

	return [
		TestResult.new("the mutated signature really differs", mutated != signature, mutated.substr(0, 8)),
		_refused("an edited signature is refused", edited),
		_refused("an empty signature is refused", empty),
		_refused("a non-base64 signature is refused", not_base64),
	]


static func _test_another_key_is_refused() -> Array:
	var crypto := Crypto.new()
	var ours := crypto.generate_rsa(KEY_BITS)
	var theirs := crypto.generate_rsa(KEY_BITS)

	# A structurally perfect signature over the exact payload — made by the wrong person. This is
	# what someone gets by standing up their own issuing service and signing themselves a key.
	var result := LicenceCheck.verify(_envelope(_payload(), theirs), ours)

	return [_refused("a signature from another key is refused", result)]


static func _test_an_unknown_key_id_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# Each of these is signed correctly by the key it is verified against, so the ONLY thing that
	# can refuse them is the key_id check itself. Without that, a forger who compromised any key
	# Lothal has ever shipped — or who simply named a key that does not exist — would be relying
	# on whatever the lookup did by default.
	var bad_ids := {"an unlisted key_id": 99, "key_id zero": 0, "a negative key_id": -1}
	for label in bad_ids:
		var doc := _payload_dict()
		doc["key_id"] = bad_ids[label]
		var result := LicenceCheck.verify(_envelope(JSON.stringify(doc), key), key)
		results.append(_refused("%s is refused" % label, result))

	# And the field cannot simply be left out.
	var missing := _payload_dict()
	missing.erase("key_id")
	results.append(_refused("a missing key_id is refused",
		LicenceCheck.verify(_envelope(JSON.stringify(missing), key), key)))

	return results


static func _test_a_future_schema_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# Signed by the real key — a licence from a LATER Lothal, not an attack. It must still be
	# refused rather than read for the fields this build happens to recognise, because a future
	# schema is exactly where a field like "expires" or "seats" would arrive, and silently
	# ignoring it would honour a licence on terms it does not actually grant.
	var versions := {"a future schema": LicenceCheck.SCHEMA + 1, "schema zero": 0}
	for label in versions:
		var doc := _payload_dict()
		doc["schema"] = versions[label]
		results.append(_refused("%s is refused" % label,
			LicenceCheck.verify(_envelope(JSON.stringify(doc), key), key)))

	var missing := _payload_dict()
	missing.erase("schema")
	results.append(_refused("a missing schema is refused",
		LicenceCheck.verify(_envelope(JSON.stringify(missing), key), key)))

	return results


static func _test_missing_fields_are_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload()
	var results: Array = []

	# Envelopes that are missing a half, or carry the right keys with the wrong types. The typed
	# cases matter because `doc["payload"]` on a Dictionary value would not be a String, and code
	# that cast rather than checked would sign-verify a stringified Dictionary and could, in
	# principle, be made to agree with itself.
	var envelopes := {
		"an envelope with no payload": {"signature": _sign(payload, key)},
		"an envelope with no signature": {"payload": payload},
		"a numeric payload": {"payload": 42, "signature": _sign(payload, key)},
		"a dictionary payload": {"payload": {"schema": 1}, "signature": _sign(payload, key)},
		"a numeric signature": {"payload": payload, "signature": 42},
		"an empty envelope": {},
	}
	for label in envelopes:
		results.append(_refused("%s is refused" % label,
			LicenceCheck.verify(JSON.stringify(envelopes[label]).to_utf8_buffer(), key)))

	# A payload that is signed correctly but is not itself an object.
	var scalar := JSON.stringify("just a string")
	results.append(_refused("a non-object payload is refused",
		LicenceCheck.verify(_envelope(scalar, key), key)))

	return results


static func _test_junk_never_crashes_and_never_activates() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# What a user actually pastes into the box when something has gone wrong: a fragment, an
	# error page, the whole of an email, nothing at all. None of it may crash the launch path,
	# because a crash here is an app that will not start and cannot be recovered without finding
	# a file whose location the user does not know.
	var junk := {
		"an empty body": PackedByteArray(),
		"whitespace only": "   \n\t ".to_utf8_buffer(),
		"an html error page": "<!doctype html><title>404</title>".to_utf8_buffer(),
		"a truncated document": "{\"payload\": \"{\\\"sche".to_utf8_buffer(),
		"a json array": "[1,2,3]".to_utf8_buffer(),
		"a bare number": "42".to_utf8_buffer(),
		"undecodable bytes": PackedByteArray([0xff, 0xfe, 0x00, 0x01, 0x80]),
		"the payload without its envelope": _payload().to_utf8_buffer(),
	}

	for label in junk:
		var result := LicenceCheck.verify(junk[label], key)
		results.append(_refused("%s activates nothing" % label, result))

	return results


static func _test_a_malformed_email_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# All signed by the real key: these represent an ISSUING bug, not an attack. The empty case is
	# the one that matters — a function that signed "" would otherwise produce a licence that
	# activates the app and displays "Activated — ", which silently removes the only thing
	# discouraging people from passing their licence around.
	var bad := {
		"an empty address": "",
		"an address with no @": "someone.example.com",
		"an address with two @": "some@one@example.com",
		"an address with no local part": "@example.com",
		"an address with no domain dot": "someone@example",
		"an address with a trailing dot": "someone@example.",
		"an address with a space": "some one@example.com",
		"an address with a newline": "someone@example.com\nBcc: everyone",
	}
	for label in bad:
		var doc := _payload_dict()
		doc["email"] = bad[label]
		results.append(_refused("%s is refused" % label,
			LicenceCheck.verify(_envelope(JSON.stringify(doc), key), key)))

	var missing := _payload_dict()
	missing.erase("email")
	results.append(_refused("a missing email is refused",
		LicenceCheck.verify(_envelope(JSON.stringify(missing), key), key)))

	return results


static func _test_real_addresses_are_not_rejected() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# The other half of the email check, and the more important half. Every address here belongs
	# to somebody, and a validator that tightened its way into rejecting one of them would lock a
	# real, verified user out of a paid app with no way to diagnose it. Plus-addressing and
	# multi-label domains are the two that hand-rolled validators break first.
	var real := [
		"someone@example.com",
		"some.one@example.com",
		"some+lothal@example.com",
		"some_one@example.co.uk",
		"s@example.io",
		"someone@mail.students.example.ac.in",
		"SomeOne@Example.COM",
		"some-one@example-domain.com",
	]
	for address in real:
		var result := LicenceCheck.verify(_envelope(_payload(address), key), key)
		results.append(TestResult.new("%s activates" % address, result.valid and result.email == address,
			"valid=%s reason=%s" % [result.valid, result.reason]))

	return results


static func _test_the_key_seam_defaults_to_the_real_key() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)

	# `key = null` sends verification down the production path, which loads the shipped public
	# key. A valid envelope signed by a throwaway key must not verify against it — and if the key
	# file is absent from the build, nothing verifies at all. Either way this pins the
	# default-secure behaviour of the seam: forgetting to pass a key never means "skip the check".
	var result := LicenceCheck.verify(_envelope(_payload(), key))

	# And the shipped key must actually be present, or the whole gate is inert in the export. This
	# is asserted separately so the case above cannot pass for the wrong reason.
	var shipped_key_exists := FileAccess.file_exists(LicenceCheck.PUBLIC_KEYS[1])

	return [
		_refused("the injectable key seam defaults to the real key", result),
		TestResult.new("the activation public key is present in the project", shipped_key_exists,
			LicenceCheck.PUBLIC_KEYS[1]),
	]
