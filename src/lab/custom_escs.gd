class_name CustomEscs
extends CustomParts
## The ESCs a builder entered themselves. Read CustomParts first for the id space, the shared
## document and the refusals that are not about ESCs.
##
## This is the simplest of the six categories and it is deliberately kept that way: three numbers, a
## mass and a bolt pattern, every one of them printed on the product page. Nothing here is derived,
## because nothing here has to be worked out.
##
## ---------------------------------------------------------------------------
## THE ONE FIELD THAT WILL BE ENTERED WRONG
## ---------------------------------------------------------------------------
##
## escs.json's `_schema` puts it in capitals and so does this file: RATINGS ARE PER MOTOR, NOT PER
## BOARD. A "45A 4-in-1" is four 45 A channels — 180 A across the board — and the number the
## hardware enforces, the number the product page prints, and the number `continuous_a` holds are
## all the per-channel one.
##
## Both directions of the mistake are silent. Enter 180 where 45 belongs and the ESC becomes four
## times too strong, which does not produce an error: it produces a board that simply stops being
## the limiting component, so the aircraft gets faster and nothing on screen says why. Enter 45
## where a per-board figure was meant and the board becomes the binding constraint on every build.
##
## Neither is a refusal, because both are perfectly well-formed boards — a 240 A per-channel ESC is
## absurd rather than impossible, and labs-and-sim.md §2 warns and never blocks. The check lives in
## EscPlausibility, next to the build that carries it, and it names the mistake rather than merely
## observing that a number is large.
##
## ---------------------------------------------------------------------------
## burst_a IS CARRIED AND IS NOT A LIMIT
## ---------------------------------------------------------------------------
##
## Accepted, stored, shown, and read by nothing that decides anything — see Build.esc_burst_a for
## the full argument. Modelling it honestly needs a thermal state (how long the burst has lasted,
## how hot the board already was); applied as though it were continuous it is a larger continuous
## rating wearing a misleading name. It is on the form because it is printed next to the continuous
## figure and builders compare both, and leaving it off the screen would be its own dishonesty.

const ESCS_KEY := "escs"

## Every board in the shipped catalog bolts, through the stack's own centre pattern. Nothing reads
## anything else off an ESC's mounting block, and a board that arrived without one would fall
## through Build's fit check silently.
const BOLT_ATTACHMENT := "bolt"

## The channel count of a 4-in-1, which is what a quad ESC is. Not fixed — a builder running four
## single ESCs enters 4 all the same, and the field exists because `esc_max_amps` multiplies by it.
const DEFAULT_CHANNELS := 4


func array_key() -> String:
	return ESCS_KEY


func category() -> String:
	return "esc"


func escs() -> Array:
	return records()


func get_esc(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomEscs:
	var document := CustomEscs.new()
	document.read_from(path)
	return document


# ---------------------------------------------------------------------------
# Building a record
# ---------------------------------------------------------------------------

## A catalog-shaped record from what a builder reads off the product page. Static, and the ONE place
## a record's shape is written down.
##
## `continuous_a` and `burst_a` are PER CHANNEL. The parameter is named for it, the schema says so,
## and EscPlausibility checks it afterwards, because three statements of the same thing is what this
## particular mistake is worth.
static func make_record(name: String, continuous_a: float, burst_a: float, channels: int,
		mass_g: float, pattern: String, cell_range: String, protocol: String,
		source: String) -> Dictionary:
	return {
		"part_id": id_for(name),
		"name": name,
		"category": "esc",
		"mass_g": mass_g,
		"mounting": {
			"attachment": BOLT_ATTACHMENT,
			"pattern": pattern,
		},
		"specs": {
			"continuous_a": continuous_a,
			"burst_a": burst_a,
			"channels": channels,
		},
		"catalog": {
			"board_class": board_class_for(channels),
			"cell_range": cell_range,
			"protocol": protocol,
		},
		"source": source,
	}


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "esc")


## The picker's board bucket, spelled the way escs.json spells it. A custom board lands in the
## shipped catalog's own filter bucket rather than in a bucket of one — the same reasoning
## CustomBatteries.cell_class_for carries.
static func board_class_for(channels: int) -> String:
	return "4-in-1" if channels == DEFAULT_CHANNELS else "%d-channel" % channels


# ---------------------------------------------------------------------------
# The ESC-specific refusals
# ---------------------------------------------------------------------------

## Each of these is a case where the sim would produce a number rather than a complaint.
##
## Nothing here is about whether a board is SENSIBLE. A 240 A per-channel claim is accepted, flown,
## and warned about by EscPlausibility — including by name, as the whole-board mistake it almost
## certainly is.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: continuous_a and burst_a PER CHANNEL, and the channel count")
		return problems
	var specs := raw_specs as Dictionary

	# A missing or zero continuous rating is not an unrated board, it is an UNLIMITED one:
	# throttle_limit_for() reads a zero limit as "no limit stated" and the ESC drops out of
	# limiting_component() entirely. Silence, and in the direction that flatters the build.
	if not specs.has("continuous_a") or float(specs["continuous_a"]) <= 0.0:
		problems.append("specs.continuous_a must be present and positive, PER CHANNEL — a board with no rating is read as a board with no limit")

	# Zero channels makes esc_max_amps() zero, which is the same silence by another route.
	if not specs.has("channels") or int(specs["channels"]) < 1:
		problems.append("specs.channels must be present and at least 1 — a quad's 4-in-1 is 4")

	# Carried rather than used, but a burst rating of zero would show as a board that cannot burst
	# at all, which is a claim no product makes.
	if not specs.has("burst_a") or float(specs["burst_a"]) <= 0.0:
		problems.append("specs.burst_a must be present and positive, PER CHANNEL — it is printed next to the continuous figure")

	# The board bolts through the frame's stack pattern, and the fit check is the only thing that
	# stops a builder buying a 20x20 board for a 30.5x30.5 frame. A board with no pattern would pass
	# that check by having nothing to compare.
	var mounting: Variant = record.get("mounting", null)
	if not (mounting is Dictionary):
		problems.append("mounting is required: the board bolts, through a pattern like \"30.5x30.5\"")
	else:
		var block := mounting as Dictionary
		if str(block.get("attachment", "")) != BOLT_ATTACHMENT:
			problems.append("mounting.attachment must be \"%s\" — stacks bolt, and every reader assumes it" % BOLT_ATTACHMENT)
		if str(block.get("pattern", "")).strip_edges() == "":
			problems.append("mounting.pattern is required — without it nothing can tell you the board does not fit your frame")

	return problems
