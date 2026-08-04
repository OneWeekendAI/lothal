class_name BuildWarning
extends RefCounted
## One thing worth saying about a build: how serious it is, what it is, what it says, and the
## numbers it was derived from.
##
## ## Why this is data and not a sentence
##
## Warnings used to be plain strings, and a UI handed a string can only do one thing with it. So
## every statement about every build arrived in the same amber, which meant a pack that physically
## will not fit and a build that is merely heavy read identically. Those are categorically
## different claims, and flattening them is how a cinelifter builder came to be told they had made
## a mistake for correctly building a cinelifter.
##
## The sentence still gets written down here in the physics, because only the physics knows the
## numbers. What travels with it is everything the UI needs to present it without re-deriving
## anything: a severity to colour and order by, a stable id to test and filter against, and the
## computed values behind the wording.
##
## ## The severities, and where the line between them is
##
## The rule is stated in labs-and-sim.md §2.1, and it is the whole point of this file:
## WHERE THE PHYSICS HAS A HARD BOUNDARY, WARN. WHERE IT HAS A CONTINUUM, DESCRIBE.
##
##   IMPOSSIBLE     — the geometry or the physics refuses. Props strike the frame; the board does
##                    not bolt to the plate; the build cannot lift itself. These are facts, and
##                    there is a boundary in the physics to point at.
##   LIMITING       — it works, but something binds, and the builder should be told WHICH PART.
##                    The current-limit warnings are the standard here: they compute a throttle
##                    cap from the parts and name the component that actually caps it.
##   CHARACTERISTIC — a description of what this build IS. Heavy and slow to climb. Little
##                    manoeuvre headroom. THESE ARE NOT ERRORS. A cinelifter is supposed to read
##                    like a cinelifter, and telling a builder what they have built is
##                    information, not a scolding.
##
## Warn, never block, in all three cases (parts.md). Severity changes how something is SAID, never
## whether the part can be chosen.
##
## Every warning source speaks this vocabulary — Build.warnings(), AirframeModel.mount_warnings()
## and AirframeModel.battery_fit_warnings(). They stay three separate lists, for the reasons their
## own comments give, but they share one severity scale so the UI has one rule rather than three.

## Ordered most severe first, so the enum's own ordinal is the sort key and there is no second
## table anywhere that could disagree with this one about which of two warnings matters more.
enum Severity { IMPOSSIBLE, LIMITING, CHARACTERISTIC }

var severity: Severity
## Stable and machine-readable — what a test names, and what a UI filters on. Wording changes
## freely; this does not.
var id: StringName
var message: String
## What the message was computed from, so a consumer can present or re-format the figures without
## a second derivation that could drift from the sentence beside it.
var values: Dictionary


func _init(p_severity: Severity, p_id: StringName, p_message: String, p_values: Dictionary = {}) -> void:
	severity = p_severity
	id = p_id
	message = p_message
	values = p_values


static func impossible(p_id: StringName, p_message: String, p_values: Dictionary = {}) -> BuildWarning:
	return BuildWarning.new(Severity.IMPOSSIBLE, p_id, p_message, p_values)


static func limiting(p_id: StringName, p_message: String, p_values: Dictionary = {}) -> BuildWarning:
	return BuildWarning.new(Severity.LIMITING, p_id, p_message, p_values)


static func characteristic(p_id: StringName, p_message: String, p_values: Dictionary = {}) -> BuildWarning:
	return BuildWarning.new(Severity.CHARACTERISTIC, p_id, p_message, p_values)


## The list, most severe first, STABLE within a severity — bucketed rather than sorted, because
## Array.sort_custom is not a stable sort and the order the physics emitted its findings in is
## itself information worth keeping.
static func by_severity(list: Array[BuildWarning]) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	for level in [Severity.IMPOSSIBLE, Severity.LIMITING, Severity.CHARACTERISTIC]:
		for entry in list:
			if entry.severity == level:
				out.append(entry)
	return out


## Just the sentences. For tests, logs and anywhere a single block of text is genuinely what is
## wanted — the panels use the severities instead.
static func messages(list: Array[BuildWarning]) -> Array[String]:
	var out: Array[String] = []
	for entry in list:
		out.append(entry.message)
	return out


static func severity_name(level: Severity) -> String:
	match level:
		Severity.IMPOSSIBLE: return "impossible"
		Severity.LIMITING: return "limiting"
		_: return "characteristic"
