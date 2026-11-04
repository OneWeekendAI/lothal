class_name TestResult
extends RefCounted
## A single PASS/FAIL line: what was checked, whether it held, and the actual value
## for context when it didn't.

var name: String
var passed: bool
var detail: String

func _init(p_name: String, p_passed: bool, p_detail: String) -> void:
	name = p_name
	passed = p_passed
	detail = p_detail


## A claim the model is KNOWN not to meet yet, recorded instead of loosened. `claim_holds` is the
## real, unwidened check. While it is false the result passes and says KNOWN GAP with the reason;
## the moment it becomes true the result FAILS ("gap closed"), so the marker cannot outlive the
## gap and the band can never be quietly widened underneath it.
static func known_gap(p_name: String, claim_holds: bool, p_detail: String, reason: String) -> TestResult:
	if claim_holds:
		return TestResult.new(p_name, false,
			"KNOWN-GAP MARKER IS STALE: the claim now holds, remove the marker (%s). %s" % [reason, p_detail])
	return TestResult.new(p_name + " [KNOWN GAP]", true, "KNOWN GAP (%s): %s" % [reason, p_detail])
