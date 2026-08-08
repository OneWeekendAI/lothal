class_name TestUpdateCheck
extends RefCounted
## The update channel — the one piece of Lothal that can cause code to arrive on a stranger's
## machine, on a build that neither Apple nor Microsoft vouches for.
##
## Three of the checks here would pass while proving nothing if written the obvious way, and
## each is written specifically so it cannot.
##
## ---------------------------------------------------------------------------
## 1. A PARSER THAT REJECTS EVERYTHING PASSES EVERY NEGATIVE TEST
## ---------------------------------------------------------------------------
##
## Most of this file asserts that a bad manifest yields no update. All of those assertions hold
## for `parse_manifest()` returning `Result.none()` unconditionally — including for the good
## manifest, which is the one case that matters to a user. So the suite is anchored by a
## positive check built from the SAME fixture builder the negative cases mutate: every rejection
## below is one field away from an accepted manifest, and if the accept path breaks, the anchor
## fails loudly instead of the negatives quietly passing for the wrong reason.
##
## ---------------------------------------------------------------------------
## 2. "SIGNATURE VERIFIED" WHERE NOTHING WAS VERIFIED
## ---------------------------------------------------------------------------
##
## The dangerous bug is not a signature check that rejects valid releases — that is loud, and
## it is discovered the first time a release ships. It is a check that accepts anything: an
## early draft of this code hashed the payload and then compared the hash to itself, which
## verified every document ever written and looked exactly like working code.
##
## The defence is that the tamper tests use a REAL key pair and a REAL signature, and mutate the
## payload by a single character AFTER signing. A verifier that is doing nothing accepts that
## document, and this suite fails. It also signs one fixture with a DIFFERENT key than the one
## used to verify — that catches the subtler variant where the code checks a well-formed
## signature's structure without ever binding it to a specific key.
##
## ---------------------------------------------------------------------------
## 3. THE VERSION COMPARISON THAT WORKS FOR NINE RELEASES
## ---------------------------------------------------------------------------
##
## Comparing versions as strings is correct for 0.1.0 through 0.9.0 and wrong from 0.10.0
## onward, at which point updates silently stop reaching everybody and no error is ever logged.
## A test that only compares 0.1.0 against 0.2.0 passes on the broken implementation. The
## double-digit cases are therefore pinned explicitly, in both directions.

const KEY_BITS := 2048


static func run() -> Array:
	var results: Array = []

	results.append_array(_test_a_good_manifest_is_offered())
	results.append_array(_test_double_digit_versions_compare_numerically())
	results.append_array(_test_a_tampered_payload_is_refused())
	results.append_array(_test_another_key_is_refused())
	results.append_array(_test_an_unsigned_manifest_is_refused())
	results.append_array(_test_junk_never_crashes_and_never_offers())
	results.append_array(_test_the_same_or_older_version_is_not_offered())
	results.append_array(_test_a_plain_http_download_is_refused())
	results.append_array(_test_a_missing_digest_is_refused())
	results.append_array(_test_a_platform_without_a_build_is_not_offered())
	results.append_array(_test_a_missing_key_verifies_nothing())

	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A manifest payload that SHOULD be accepted. Every negative test below starts here and breaks
## exactly one thing, which is what makes those tests evidence rather than decoration.
static func _payload(version := "0.2.0") -> String:
	return JSON.stringify(_payload_dict(version))


## The same fixture as a mutable Dictionary.
##
## Tests that break one field edit THIS and re-stringify, rather than running string replaces
## over the serialised form. That is not tidiness: `JSON.stringify` emits `"key":"value"` with
## no space, so a replace written as `"key": "value"` matches nothing, leaves the payload
## pristine, and the test then asserts that an UNMODIFIED manifest is refused — which fails for
## the right reason only by accident, and would silently pass the day the assertion was
## inverted. Four checks in this file were written that way first and all four caught it.
static func _payload_dict(version := "0.2.0") -> Dictionary:
	return {
		"schema": UpdateCheck.SCHEMA,
		"version": version,
		"released": "2026-08-10",
		"min_version": "0.0.0",
		"notes_url": "https://lothal.example/releases/v%s" % version,
		"downloads": {
			"macos": {
				"url": "https://dl.lothal.example/v%s/Lothal-%s-macos-universal.zip" % [version, version],
				"size": 94371840,
				"sha256": "a" .repeat(64),
			},
			"windows": {
				"url": "https://dl.lothal.example/v%s/Lothal-%s-windows-x64.zip" % [version, version],
				"size": 73400320,
				"sha256": "b" .repeat(64),
			},
		},
	}


static func _sign(payload: String, key: CryptoKey) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(payload.to_utf8_buffer())
	return Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, hashing.finish(), key))


static func _envelope(payload: String, key: CryptoKey) -> PackedByteArray:
	return JSON.stringify({"payload": payload, "signature": _sign(payload, key)}).to_utf8_buffer()


# ---------------------------------------------------------------------------
# The anchor: a real release is actually offered
# ---------------------------------------------------------------------------

static func _test_a_good_manifest_is_offered() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var result := UpdateCheck.parse_manifest(_envelope(_payload("0.2.0"), key), "macos", "0.1.0", key)

	var url_is_the_mac_build: bool = result.download_url.ends_with("macos-universal.zip")

	return [
		TestResult.new("a signed newer manifest is offered", result.available,
			"available=%s reason=%s" % [result.available, result.reason]),
		TestResult.new("the offered version is the manifest's", result.version == "0.2.0", result.version),
		TestResult.new("the platform's own build is selected", url_is_the_mac_build, result.download_url),
		TestResult.new("the digest is carried through", result.sha256 == "a".repeat(64), result.sha256),
	]


# ---------------------------------------------------------------------------
# Version ordering past the ninth release
# ---------------------------------------------------------------------------

static func _test_double_digit_versions_compare_numerically() -> Array:
	# "0.10.0" < "0.9.0" as strings. This is the whole point of the function.
	var ten_beats_nine := LothalVersion.compare("0.10.0", "0.9.0") == 1
	var nine_loses_to_ten := LothalVersion.compare("0.9.0", "0.10.0") == -1
	var equal_is_equal := LothalVersion.compare("1.2.0", "1.2") == 0
	var patch_counts := LothalVersion.compare("1.2.10", "1.2.9") == 1

	# And the same bug seen through the door it would actually walk in by: a v0.10.0 release
	# offered to a v0.9.0 install. String comparison reports "not newer" and no one is told.
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var result := UpdateCheck.parse_manifest(_envelope(_payload("0.10.0"), key), "macos", "0.9.0", key)

	return [
		TestResult.new("0.10.0 is newer than 0.9.0", ten_beats_nine, "compare=%d" % LothalVersion.compare("0.10.0", "0.9.0")),
		TestResult.new("0.9.0 is older than 0.10.0", nine_loses_to_ten, "compare=%d" % LothalVersion.compare("0.9.0", "0.10.0")),
		TestResult.new("a missing patch component reads as zero", equal_is_equal, "1.2.0 vs 1.2"),
		TestResult.new("patch numbers compare numerically", patch_counts, "1.2.10 vs 1.2.9"),
		TestResult.new("v0.10.0 is offered to a v0.9.0 install", result.available, result.reason),
	]


# ---------------------------------------------------------------------------
# Tamper resistance — the checks that a do-nothing verifier fails
# ---------------------------------------------------------------------------

static func _test_a_tampered_payload_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload("0.2.0")
	var signature := _sign(payload, key)

	# Signed honestly, then edited. This is the attack the signature exists to stop: the
	# download is redirected and everything else about the document still looks right.
	var tampered := payload.replace("https://dl.lothal.example", "https://dl.evil.example")
	var forged := JSON.stringify({"payload": tampered, "signature": signature}).to_utf8_buffer()

	var result := UpdateCheck.parse_manifest(forged, "macos", "0.1.0", key)

	# A single flipped character somewhere harmless must fail too — otherwise the verifier is
	# checking a prefix or a length rather than the content.
	var nudged_dict := _payload_dict("0.2.0")
	nudged_dict["released"] = "2026-08-11"
	var nudged := JSON.stringify(nudged_dict)
	var nudged_result := UpdateCheck.parse_manifest(
		JSON.stringify({"payload": nudged, "signature": signature}).to_utf8_buffer(), "macos", "0.1.0", key)

	return [
		TestResult.new("a redirected download url is refused", not result.available, result.reason),
		TestResult.new("any edit after signing is refused", not nudged_result.available, nudged_result.reason),
	]


static func _test_another_key_is_refused() -> Array:
	var crypto := Crypto.new()
	var ours := crypto.generate_rsa(KEY_BITS)
	var theirs := crypto.generate_rsa(KEY_BITS)

	# A structurally perfect signature over the exact payload — made by the wrong person.
	var result := UpdateCheck.parse_manifest(_envelope(_payload("0.2.0"), theirs), "macos", "0.1.0", ours)

	return [TestResult.new("a signature from another key is refused", not result.available, result.reason)]


static func _test_an_unsigned_manifest_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload("0.2.0")

	# The shape a naive server might serve: the manifest itself, no envelope. It parses, every
	# field is valid, and it must still be refused — "looks like a manifest" is not authority.
	var bare := payload.to_utf8_buffer()
	var bare_result := UpdateCheck.parse_manifest(bare, "macos", "0.1.0", key)

	var empty_sig := JSON.stringify({"payload": payload, "signature": ""}).to_utf8_buffer()
	var empty_result := UpdateCheck.parse_manifest(empty_sig, "macos", "0.1.0", key)

	return [
		TestResult.new("a bare unsigned manifest is refused", not bare_result.available, bare_result.reason),
		TestResult.new("an empty signature is refused", not empty_result.available, empty_result.reason),
	]


# ---------------------------------------------------------------------------
# Everything else fails closed, and nothing crashes the launch path
# ---------------------------------------------------------------------------

static func _test_junk_never_crashes_and_never_offers() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# A 404 page, a truncated file, an empty body, a JSON array, raw bytes that are not UTF-8.
	# All five are things a real CDN has served to a real client at some point.
	var junk := {
		"an html error page": "<!doctype html><title>404</title>".to_utf8_buffer(),
		"a truncated document": "{\"payload\": \"{\\\"sche".to_utf8_buffer(),
		"an empty body": PackedByteArray(),
		"a json array": "[1,2,3]".to_utf8_buffer(),
		"undecodable bytes": PackedByteArray([0xff, 0xfe, 0x00, 0x01, 0x80]),
	}

	for label in junk:
		var result := UpdateCheck.parse_manifest(junk[label], "macos", "0.1.0", key)
		results.append(TestResult.new("%s offers nothing" % label, not result.available, result.reason))

	# A schema from a future Lothal must decline rather than read the fields it recognises.
	var future := JSON.stringify({
		"schema": UpdateCheck.SCHEMA + 1, "version": "0.2.0",
		"downloads": {"macos": {"url": "https://dl.lothal.example/x.zip", "sha256": "a".repeat(64)}},
	})
	var future_result := UpdateCheck.parse_manifest(_envelope(future, key), "macos", "0.1.0", key)
	results.append(TestResult.new("an unknown schema is declined", not future_result.available, future_result.reason))

	return results


static func _test_the_same_or_older_version_is_not_offered() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)

	var same := UpdateCheck.parse_manifest(_envelope(_payload("0.1.0"), key), "macos", "0.1.0", key)
	var older := UpdateCheck.parse_manifest(_envelope(_payload("0.0.9"), key), "macos", "0.1.0", key)

	return [
		TestResult.new("the installed version is not offered to itself", not same.available, same.reason),
		TestResult.new("an older release is not offered", not older.available, older.reason),
	]


static func _test_a_plain_http_download_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var payload := _payload("0.2.0").replace("https://dl.lothal.example", "http://dl.lothal.example")

	# Signed by the real key — the maintainer's own mistake rather than an attack. It must still
	# be refused, because the signature covers the document and not the wire it points at.
	var result := UpdateCheck.parse_manifest(_envelope(payload, key), "macos", "0.1.0", key)

	return [TestResult.new("an http download url is refused even when signed", not result.available, result.reason)]


static func _test_a_missing_digest_is_refused() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var results: Array = []

	# Blank, short, and non-hex. The blank case is the one that matters: it is what a broken
	# packaging script produces, and it must not read as "no digest, so nothing to check".
	var bad_digests := {"a blank digest": "", "a truncated digest": "abc123", "a non-hex digest": "z".repeat(64)}
	for label in bad_digests:
		var doc := _payload_dict("0.2.0")
		(doc["downloads"] as Dictionary)["macos"]["sha256"] = bad_digests[label]
		var result := UpdateCheck.parse_manifest(_envelope(JSON.stringify(doc), key), "macos", "0.1.0", key)
		results.append(TestResult.new("%s is refused" % label, not result.available, result.reason))

	return results


static func _test_a_platform_without_a_build_is_not_offered() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)
	var envelope := _envelope(_payload("0.2.0"), key)

	# Lothal ships macOS and Windows. Anything else gets no offer rather than the first entry
	# in the downloads block, which would hand a Linux user a .app bundle.
	var linux := UpdateCheck.parse_manifest(envelope, "", "0.1.0", key)
	var windows := UpdateCheck.parse_manifest(envelope, "windows", "0.1.0", key)

	return [
		TestResult.new("an unshipped platform is offered nothing", not linux.available, linux.reason),
		TestResult.new("windows is offered the windows build",
			windows.available and windows.download_url.ends_with("windows-x64.zip"), windows.download_url),
	]


static func _test_a_missing_key_verifies_nothing() -> Array:
	var key := Crypto.new().generate_rsa(KEY_BITS)

	# `key = null` sends verification down the production path, which loads the shipped public
	# key. Under the headless runner that file may or may not be present — either way a valid
	# envelope signed by a throwaway key must not verify against the real one. This pins the
	# default-secure behaviour of the seam: forgetting to pass a key never means "skip".
	var result := UpdateCheck.parse_manifest(_envelope(_payload("0.2.0"), key), "macos", "0.1.0")

	return [TestResult.new("the injectable key seam defaults to the real key", not result.available, result.reason)]
