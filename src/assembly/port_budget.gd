class_name PortBudget
extends RefCounted
## HOW MANY SERIAL PORTS THE BOARD HAS — the supply side of the port budget, config-room design
## §2.2 and §4.2, slice C5. The sibling of `ControlPlausibility`'s demand side, and the one place in
## the project that answers this question, on `MotorLayout.spin_map`'s rule: one accessor, so the
## warning row, the panel and anything downstream cannot come to say it three different ways.
##
## ---------------------------------------------------------------------------
## THE NUMBER IS A GUESS AND IT SAYS SO IN THE SAME BREATH AS SAYING THE NUMBER
## ---------------------------------------------------------------------------
##
## No board in `flight_controllers.json` publishes a port count, because every entry is class-typical
## rather than a product, and the count VARIES ACROSS THE CLASS it is typical of. Control-room design
## §9 called sourcing the real numbers the fix; config-room §0.1 declines that route — it is a
## sourcing task, and sourcing tasks sit in `track.md` for months — and ships the number as a
## **class-typical range with an editable field beside it**, in the voice `gyro_bias_rad_s` already
## uses.
##
## The bar that was relaxed is accuracy. THE BAR THAT WAS NOT IS PROVENANCE: a guess may never be
## presented as measured. So every answer here carries where it came from, and the three are really
## three different kinds of claim rather than three confidence levels:
##
##   CLASS_TYPICAL — the catalog's range. Lothal's guess about a class of board.
##   TYPED         — a number the builder read off their own board's product page in thirty seconds
##                   and typed. Not a better guess: a DIFFERENT KIND OF FACT, and it is theirs.
##   UNPUBLISHED   — the entry carries no range. C4's honest silence, unchanged and still reachable,
##                   because a custom board authored without one is a real build.
##
## A range rather than a single number because a range is what is genuinely known — and, per §4.2,
## the VERDICT USUALLY SURVIVES IT: four peripherals do not fit a 1–2 port whoop at either end, and
## that answers the question the builder actually asked.

## Where the range lives on a catalog entry. In `catalog`, not `specs`: it is browsing metadata and
## a checkable property of the real product, and it bears on no physics at all.
const CATALOG_KEY := "uart_range"

## Where the builder's own figure lives in the drone's `config` block (C1's decision block).
const CONFIG_KEY := "uart_count"

## The three provenances, as they are written into `values` and compared against. Constants rather
## than literals so a reader of a warning and a writer of a panel cannot disagree by a spelling.
const CLASS_TYPICAL := "class_typical"
const TYPED := "typed"
const UNPUBLISHED := "unpublished"

## What an entry with no range reads as, everywhere it is shown. `ControlPlausibility` re-exports
## this as `PORTS_UNPUBLISHED`, which is the name it shipped under in C4 and the name its test uses.
const UNPUBLISHED_TEXT := "not published in this catalog"


## This build's port supply: `{low, high, provenance, sentence}`.
##
## `low` and `high` are 0 when nothing is known, and the caller is expected to check `provenance`
## rather than to read 0 as a count — which is why the sentence is returned with them.
static func for_build(build: Build) -> Dictionary:
	var typed := typed_count(build.config)
	if typed > 0:
		return {
			"low": typed, "high": typed, "provenance": TYPED,
			"sentence": ("You have told Lothal this board has %d serial %s — your figure for this "
				+ "build, read off the board rather than guessed by the catalog.") % [
					typed, "port" if typed == 1 else "ports"],
		}

	var published: Array = _published_range(build.fc)
	if published.is_empty():
		return {
			"low": 0, "high": 0, "provenance": UNPUBLISHED,
			"sentence": ("How many this board has is %s, so Lothal cannot tell you whether they "
				+ "fit — check your board's own documentation.") % [UNPUBLISHED_TEXT],
		}

	var low := int(published[0])
	var high := int(published[1])
	var figure := str(low) if low == high else "%d–%d" % [low, high]
	return {
		"low": low, "high": high, "provenance": CLASS_TYPICAL,
		"sentence": ("A %s board typically has %s — a class-typical figure for boards of its kind, "
			+ "not your board's, and you can set yours here.") % [
				str(build.fc.get("name", "board of this kind")), figure],
	}


## Does a demand of `demand` ports fit this supply, said in the words the builder acts on?
##
## THE VERDICT IS THE REASON A GUESS IS ADMISSIBLE AT ALL, so it is careful about the case where the
## guess does not decide it: a demand between the two ends is reported as UNDECIDED rather than
## resolved to the end that flatters the build, and the field is how the builder settles it.
## Returns "" when nothing is known, because a verdict with no figure behind it is the confident
## sentence this whole file exists to avoid.
static func verdict(demand: int, budget: Dictionary) -> String:
	var provenance := String(budget.get("provenance", UNPUBLISHED))
	if provenance == UNPUBLISHED:
		return ""

	var low := int(budget.get("low", 0))
	var high := int(budget.get("high", 0))
	var either := low != high
	if demand <= low:
		return ("On either figure, %d fits." % demand) if either else ("%d fits." % demand)
	if demand > high:
		return ("On either figure, %d does not fit." % demand) if either \
			else ("%d does not fit." % demand)
	return ("Whether %d fits depends on which end of that range your board is — read the real "
		+ "number off its product page and set it here.") % demand


## Writes the builder's own figure into a drone's config block, or clears it.
##
## Zero and negative CLEAR rather than assert a board with no ports: a spin box being dragged past
## its floor is not a claim, and the class-typical range coming back is the honest response to it.
static func set_count(config: Dictionary, count: int) -> void:
	if count <= 0:
		config.erase(CONFIG_KEY)
		return
	config[CONFIG_KEY] = count


## The override as an int, or 0 for none — tolerant of the float a JSON round trip leaves behind.
## Public because the panel's field has to show what is stored without inferring it from a range.
static func typed_count(config: Dictionary) -> int:
	var raw: Variant = config.get(CONFIG_KEY, null)
	if raw is int or raw is float:
		return int(raw)
	return 0


## The entry's range, or `[]` if it publishes none or publishes nonsense. A malformed range is
## treated as no range, on the standing rule: warn, never block, and never invent.
static func _published_range(fc: Dictionary) -> Array:
	var raw: Variant = (fc.get("catalog", {}) as Dictionary).get(CATALOG_KEY, null)
	if not (raw is Array) or (raw as Array).size() != 2:
		return []
	var low := int((raw as Array)[0])
	var high := int((raw as Array)[1])
	if low < 1 or high < low:
		return []
	return [low, high]
