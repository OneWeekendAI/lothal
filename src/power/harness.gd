class_name Harness
extends RefCounted
## The build's current path, as data — plans/2026-09-10-power-room-design.md §4.2, slice PW2.
##
## Six values: which connector the pack plugs into, which capacitor sits across the ESC's pads,
## and a gauge and a length for each of the two wire runs (the main lead from the connector to the
## stack, and the four motor leads out to the arms). Nothing here is a part you buy except the two
## ids; wire is a gauge and a length, which is WireGauge's whole argument for not being a parts
## file.
##
## ---------------------------------------------------------------------------
## DERIVED DEFAULT, AUTHORED OVERRIDE — THE SHAPE `AssemblyTweaks` ALREADY USES
## ---------------------------------------------------------------------------
##
## Every one of the six has a default that comes OFF THE BUILD, and every one is overridable. The
## mechanism is `AssemblyTweaks.value_mm`'s exactly: a sparse override dictionary, a derived
## default table, and one reader that prefers the first and falls back to the second. Sparse is
## the load-bearing half — an absent key means "whatever the parts imply", not zero, which is what
## lets a default follow the frame you chose instead of freezing at the value the frame happened
## to have when the harness was first touched.
##
## `defaults()` is public for the same reason `AssemblyTweaks.limits()` is: PW4's inspector has to
## show a builder what the default WOULD be beside what they typed, and a panel that recomputed it
## itself would be a second opinion about the aircraft.
##
## ---------------------------------------------------------------------------
## WHAT IS ROUGH HERE, SAID OUT LOUD (design §0)
## ---------------------------------------------------------------------------
##
## Lead lengths are not published by anybody, for any frame, ever. Neither is the gauge a builder
## chose. So the tables below are CLASS-TYPICAL and say so on each line: a 5" freestyle harness is
## 14 AWG to the stack and 20 AWG out to the motors because that is what the 5" freestyle world
## solders, not because a number was measured. Design §0's relaxation is exactly this case — a
## labelled default with an editable field beside it is a starting point with its provenance on
## its face, and it is NOT an invented spec presented as measured.
##
## What that relaxation does NOT cover is where a mass lands, and see `Build.mass_parts()` for the
## axis trap that governs the four motor leads.

# ---------------------------------------------------------------------------
# The six keys
# ---------------------------------------------------------------------------

## Which connector pair the pack plugs into. A part id from connectors.json.
const CONNECTOR := "connector_id"
## The low-ESR electrolytic across the ESC's input pads. A part id from capacitors.json.
const CAPACITOR := "capacitor_id"
## The run from the connector to the ESC's pads. Two conductors — positive and negative — and
## `main_lead_mass_g` is what knows that, not the length.
const MAIN_LEAD_AWG := "main_lead_awg"
const MAIN_LEAD_LENGTH_MM := "main_lead_length_mm"
## The run from the ESC's pads out to ONE motor. Three conductors, because a brushless motor has
## three phases and all three run the length of the arm.
const MOTOR_LEAD_AWG := "motor_lead_awg"
const MOTOR_LEAD_LENGTH_MM := "motor_lead_length_mm"

## The part ids, held apart from the numbers because they are resolved through the catalog and
## clamped by nothing, where a gauge is checked against WireGauge's table.
const ID_KEYS := [CONNECTOR, CAPACITOR]
const NUMBER_KEYS := [MAIN_LEAD_AWG, MAIN_LEAD_LENGTH_MM, MOTOR_LEAD_AWG, MOTOR_LEAD_LENGTH_MM]

## Conductors in each run. NOT authored per build and not a field: a DC supply is two wires and a
## three-phase motor is three, on every aircraft that has ever been built. Putting them in the
## override table would invite a build with two-phase motors.
const MAIN_LEAD_CONDUCTORS := 2
const MOTOR_LEAD_CONDUCTORS := 3

# ---------------------------------------------------------------------------
# The class-typical tables
# ---------------------------------------------------------------------------

## Main lead gauge and length, and the motor lead's gauge, by the frame's `max_prop_inches`.
##
## Keyed on `max_prop_inches` rather than on `catalog.size_class`, and that is not a preference.
## `size_class` is a browsing STRING that the shipped catalog spells inconsistently by hand —
## "65mm" for a 1.6" whoop, "3\"" for one 3.5" frame and "3.5\"" for another (CustomFrames.
## size_class_for spends a paragraph on why no formula reproduces it). A band table keyed on a
## string nobody normalises is a band table with a hole in it the day somebody adds a frame.
## `max_prop_inches` is a number, is in `specs`, and every frame in the catalog carries one.
##
## Rows are `[max_prop_inches ceiling, main lead AWG, main lead mm, motor lead AWG, the lead length
## the MOTOR ships with]`, ascending, and the LAST row is the catch-all — a 15" frame gets the
## cinelifter's harness rather than nothing. See MOTOR_SUPPLIED_LEAD_MM for what the fifth column
## is for and why it is a column rather than one constant.
##
## EVERY NUMBER IN THIS TABLE IS CLASS-TYPICAL AND NONE OF IT IS MEASURED. The gauges are what
## each class actually solders; the main lead lengths are what a pack sitting on the plate needs
## to reach the stack with enough slack to plug in, which grows with the frame and is not
## proportional to anything in particular.
const CLASS_ROWS := [
	# Whoops. 26 AWG to the stack on a 1S, 28 AWG phases: an 0802 ships with hair, and about
	# 25 mm of it.
	[2.0, 26, 60.0, 28, 25.0],
	# 2.5-3" micros on 2-4S.
	[3.0, 22, 70.0, 26, 40.0],
	# Toothpicks and 3.5" freestyle.
	[4.0, 20, 90.0, 24, 70.0],
	# THE REFERENCE CLASS. 14 AWG main lead is what an XT60 pigtail is made of, 20 AWG is what a
	# 2207 ships with, and it ships with about 100 mm of it.
	[5.5, 14, 120.0, 20, 100.0],
	# 6-7" long range.
	[7.5, 14, 150.0, 18, 150.0],
	# Cinelifters and 10" cruisers on 6S.
	[999.0, 12, 180.0, 16, 200.0],
]

## How much wire a motor lead needs BEYOND the arm it runs along: out of the ESC's pads, around
## the standoffs, along the arm and up into the motor's own leads. 30 mm, ROUGH, and flat rather
## than a fraction of the arm because the awkward part of that route is the middle of the
## aircraft, which does not get bigger as fast as the arm does.
const MOTOR_LEAD_ROUTING_ALLOWANCE_MM := 30.0

## THE STRETCH OF MOTOR LEAD THE MOTOR ALREADY CARRIES — the fifth column of CLASS_ROWS, read
## through `motor_supplied_lead_mm` below. The reason it exists is a double-count, not a refinement.
##
## `motors.json` masses are the motor AS SOLD, and a motor is sold with its phase wires attached —
## the XING2 2207 row says "included wire" in its own source string, and every other row is a
## vendor figure of the same kind. `Build.mass_parts()` puts that whole mass at the arm tip. So a
## harness that then weighed the FULL ESC-to-motor run would count the motor's own leads twice, on
## every build in the catalog, invisibly — the same defect `connectors.json`'s `pigtail_mass_g`
## note exists to prevent, arriving from the other direction.
##
## The resolution is the one that note prescribes: count it once. `motor_lead_length_mm` is the
## WHOLE run, because that is the length PW3's voltage drop and ampacity checks need and the length
## a builder would measure; `motor_lead_mass_g` weighs only the part of it the motor did not bring,
## which is that length less this stub.
##
## A COLUMN RATHER THAN ONE CONSTANT, and that was measured rather than assumed. It was a flat
## 100 mm, and a flat stub is a claim that a 2808 on a 215 mm arm ships with the same pigtail as an
## 0802 on a 32 mm one. It does not, and the flat version put FORTY-THREE GRAMS of "added" motor
## lead on the 10" long-range build — more than a third of its frame — because the run grew with the
## arm while the stub did not. Every figure in the column is ROUGH and class-typical, like every
## other number in this table; what it fixes is not the precision of any one of them but a shape
## that was wrong at both ends of the catalog.
##
## It is deliberately NOT a per-motor spec: no motor publishes its lead length, and adding a
## `lead_length_mm` column to motors.json would be seventeen invented numbers where one labelled
## band table does the same work and is visible in one place.
static func motor_supplied_lead_mm(build: Build) -> float:
	return float(_class_row(build)[4])

## Straps, tape, solder and heat-shrink: what is left of the harness once the connector, the two
## wire runs and the capacitor are real objects with real positions.
##
## FLAT, and flat for the reason `Build.wiring_mass_g()` used to give for the 14 g lump it
## replaces: harness sundries scale with something — how many things are soldered to how many
## other things — and Lothal has measured that on exactly zero aircraft. A flat remainder is wrong
## in a way that is stated and bounded. 5 g is a battery strap and a few centimetres of shrink on
## a 5"; it is ROUGH, and unlike its predecessor it is AUTHORED rather than being whatever a budget
## had left, which is the honest difference PW2 bought.
const REMAINDER_MASS_G := 5.0

## What of a connector pair the AIRCRAFT carries: one half of it. See `connector_mass_g` for the
## double-count this prevents. Exactly a half rather than a measured split — the two halves of an
## XT60 are near enough the same object, and no vendor publishes them separately.
const AIRCRAFT_SIDE_SHARE := 0.5

## The capacitor's default, by pack cell count — the §3.4 rule's own variable, since the one thing
## that actually decides a capacitor is whether its voltage rating survives a full pack. A 6S rests
## at 22.2 V and charges to 25.2, so nothing below 35 V is admissible there; a 1S whoop cannot fit
## a 35 V can under the AIO. Rows are `[cell ceiling, capacitor id]`, ascending, last row catch-all.
const CAPACITOR_ROWS := [
	[2, "cap_220uf_16v"],
	[4, "cap_470uf_35v"],
	[99, "cap_1000uf_35v"],
]

## Only the values the builder has actually set. Sparse — see the header.
var _overrides: Dictionary = {}


## What the parts imply, for every one of the six. Nothing here is authored per build: the two
## wire rows come off the frame's own `max_prop_inches`, the motor lead length off the arm, the
## connector off the PACK'S OWN `catalog.connector` — which is the join connectors.json's schema
## block exists to keep spelled one way — and the capacitor off the pack's cell count.
static func defaults(build: Build) -> Dictionary:
	var row := _class_row(build)
	return {
		CONNECTOR: _connector_for_pack(build),
		CAPACITOR: _capacitor_for_pack(build),
		MAIN_LEAD_AWG: int(row[1]),
		MAIN_LEAD_LENGTH_MM: float(row[2]),
		MOTOR_LEAD_AWG: int(row[3]),
		# The arm the lead runs along, plus what the route costs beyond it. The one default here
		# that is derived from a MEASURED number — the frame publishes its arm — rather than from a
		# class band.
		MOTOR_LEAD_LENGTH_MM: build.arm_m * 1000.0 + MOTOR_LEAD_ROUTING_ALLOWANCE_MM,
	}


## Records a value. Stored UNCLAMPED, on AssemblyTweaks.set_mm's precedent and for its reason: a
## 12 AWG main lead authored for a cinelifter has to still be 12 AWG when the cinelifter goes back
## on, and silently rewriting the builder's number because a toothpick is currently fitted is the
## same mistake in a different place. A gauge the table does not carry is caught where it is READ
## (WireGauge refuses rather than interpolating), not here.
func set_value(key: String, authored: Variant) -> void:
	if not ID_KEYS.has(key) and not NUMBER_KEYS.has(key):
		push_error("unknown harness value: %s" % key)
		return
	_overrides[key] = authored


func has_override(key: String) -> bool:
	return _overrides.has(key)


## Back to what the parts imply, for one value or for all of them.
func clear(key: String) -> void:
	_overrides.erase(key)


func reset() -> void:
	_overrides.clear()


## The value in force: what was set, or the derived default. THE ONE READER, so a caller cannot
## invent a different default for a key it happens to know about.
func value(key: String, build: Build) -> Variant:
	if _overrides.has(key):
		return _overrides[key]
	return defaults(build)[key]


## Every value in force, in one dictionary — the shape `AssemblyTweaks.resolved_m` hands the
## geometry, and for the same reason: one crossing point rather than six.
func resolved(build: Build) -> Dictionary:
	var out := defaults(build)
	for key in _overrides:
		out[key] = _overrides[key]
	return out


## The overrides alone, for persistence and for `Build.at_air`'s twin. Sparse, so a saved harness
## carries only what was authored and picks up new defaults when the parts under it move.
func overrides() -> Dictionary:
	return _overrides.duplicate()


static func from_overrides(stored: Dictionary) -> Harness:
	var harness := Harness.new()
	for key in stored:
		if ID_KEYS.has(key) or NUMBER_KEYS.has(key):
			harness._overrides[key] = stored[key]
	return harness


# ---------------------------------------------------------------------------
# Masses
# ---------------------------------------------------------------------------

## The main lead: both conductors, at the authored length and gauge.
func main_lead_mass_g(build: Build) -> float:
	return MAIN_LEAD_CONDUCTORS * WireGauge.mass_g(
		int(value(MAIN_LEAD_AWG, build)),
		float(value(MAIN_LEAD_LENGTH_MM, build)) / 1000.0)


## ONE motor lead: three conductors, over the part of the run the motor did not bring with it.
## See MOTOR_SUPPLIED_LEAD_MM for why that subtraction is here and not a fudge.
##
## Floored at zero rather than going negative: a run shorter than the leads the motor came with
## means those leads reach the board and the harness adds no wire, which is a real build and not an
## error. A builder in that position trims, and trimmings do not fly.
func motor_lead_mass_g(build: Build) -> float:
	var added_mm := maxf(
		float(value(MOTOR_LEAD_LENGTH_MM, build)) - motor_supplied_lead_mm(build), 0.0)
	return MOTOR_LEAD_CONDUCTORS * WireGauge.mass_g(
		int(value(MOTOR_LEAD_AWG, build)), added_mm / 1000.0)


## The connector pair, off its catalog row. Zero for a build whose connector id resolves to
## nothing, which is a pack-side family with no row rather than a build with no plug.
##
## HALF THE PAIR, AND THAT IS THE THIRD DOUBLE-COUNT THIS SLICE HAD TO SETTLE. connectors.json's
## `mass_g` is the mass of the PAIR, male and female together, and its schema block says that is
## "what a build actually carries". Wiring it up showed that it is not: the female half is soldered
## to the PACK, and `batteries.json`'s masses are published pack weights, which a manufacturer
## measures with the lead and the plug already on it. Counting the pair here puts the pack's own
## plug on the aircraft twice. So the aircraft carries its half — see AIRCRAFT_SIDE_SHARE — and the
## other half stays where it was already being weighed.
##
## `pigtail_mass_g` IS DELIBERATELY NOT READ HERE, and connectors.json's schema block names this
## as the choice PW2 had to make. A housed XT60H ships pre-soldered to a short lead pair, and that
## stretch of wire is ALREADY modelled — by `main_lead_mass_g` above, at the builder's own gauge
## and the builder's own length. Adding the row's figure to it would weigh the same copper twice.
## The modelled lead wins because it is the one the builder can change: counting the pigtail
## instead would make part of the length field inert, and a slider that moves a number less than it
## says it does is worse than one that does not exist.
func connector_mass_g(build: Build) -> float:
	return float(_row_for(build, CONNECTOR).get("mass_g", 0.0)) * AIRCRAFT_SIDE_SHARE


func capacitor_mass_g(build: Build) -> float:
	return float(_row_for(build, CAPACITOR).get("mass_g", 0.0))


## Everything the harness weighs. Four motor leads, not one — the count lives here so that
## `Build.mass_parts()` appending four `PartMass` entries and this function are the same claim,
## which is what makes the "mass equals the sum of its parts" check able to fail.
func total_mass_g(build: Build) -> float:
	return connector_mass_g(build) + main_lead_mass_g(build) \
		+ MotorLayout.MOTOR_NAMES.size() * motor_lead_mass_g(build) \
		+ capacitor_mass_g(build) + REMAINDER_MASS_G


## The capacitor's can as a box in body axes: the diameter across X and Z, the height up Y, because
## an electrolytic stands on the ESC's pads. Falls back to a 10 mm cube for a row with no published
## dimensions, on `Build.component_size_of`'s precedent and for its reason.
func capacitor_size_m(build: Build) -> Vector3:
	var specs: Dictionary = _row_for(build, CAPACITOR).get("specs", {})
	var diameter := float(specs.get("diameter_mm", 0.0))
	var height := float(specs.get("height_mm", 0.0))
	if diameter > 0.0 and height > 0.0:
		return Vector3(diameter, height, diameter) / 1000.0
	return Vector3.ONE * 0.010


## A thin rod's own inertia about its own centre, as an axis-aligned diagonal.
##
##     I = m L^2 / 12 * (E - d (x) d)
##
## which for a unit axis `d` has diagonal entries `m L^2 / 12 * (1 - d_i^2)` — so a lead running
## along Z contributes nothing about Z and a lead running out along an arm at 45 degrees splits its
## transverse term between X and Z. The off-diagonal terms of that outer product are dropped, which
## is the same diagonal-only convention `InertiaPrimitives` states for every other primitive in the
## project; on a 40 mm lead the whole local tensor is three orders below the parallel-axis term
## that carries it out to the arm.
##
## THE CONDUCTOR'S OWN RADIUS IS IGNORED — a thin rod, not a cylinder. A 20 AWG bundle is under a
## millimetre across and its radial term is quadratic in that, which is smaller than the roughness
## already in the length.
static func rod_diag_kg_m2(mass_kg: float, length_m: float, axis: Vector3) -> Vector3:
	if mass_kg <= 0.0 or length_m <= 0.0 or axis.length_squared() <= 0.0:
		return Vector3.ZERO
	var d := axis.normalized()
	var scale := mass_kg * length_m * length_m / 12.0
	return Vector3(
		scale * (1.0 - d.x * d.x),
		scale * (1.0 - d.y * d.y),
		scale * (1.0 - d.z * d.z))


# ---------------------------------------------------------------------------
# Derivation internals
# ---------------------------------------------------------------------------

static func _class_row(build: Build) -> Array:
	var inches := 0.0
	if not build.frame.is_empty():
		inches = float((build.frame.get("specs", {}) as Dictionary).get("max_prop_inches", 0.0))
	for row in CLASS_ROWS:
		if inches <= float(row[0]):
			return row
	return CLASS_ROWS[CLASS_ROWS.size() - 1]


## The connector row whose family is the one the PACK terminates in. This is the join in the
## direction that matters for a default: a builder who chooses a 6S pack with an XT60 on it wants
## an XT60 on the aircraft, and nothing else is a sensible starting point.
##
## Empty when nothing matches — a pack in a family with no row, which `test_power_parts.gd` already
## makes impossible for the shipped catalog and which a custom pack could still produce. Empty
## means no connector fitted and therefore no connector mass, which is honest: the alternative is
## planting a default plug the builder never chose and charging them six grams for it.
static func _connector_for_pack(build: Build) -> String:
	if build.catalog == null or build.battery.is_empty():
		return ""
	var family := String((build.battery.get("catalog", {}) as Dictionary).get("connector", ""))
	if family == "":
		return ""
	for row in build.catalog.list_category("connector"):
		if String((row.get("catalog", {}) as Dictionary).get("family", "")) == family:
			return String(row.get("part_id", ""))
	return ""


static func _capacitor_for_pack(build: Build) -> String:
	var cells := 0
	if not build.battery.is_empty():
		cells = int(float((build.battery.get("specs", {}) as Dictionary).get("cells", 0)))
	for row in CAPACITOR_ROWS:
		if cells <= int(row[0]):
			return String(row[1])
	return String(CAPACITOR_ROWS[CAPACITOR_ROWS.size() - 1][1])


## The catalog rows the two fitted ids resolve to. Public because PW3's checks read the connector's
## rating, its family and its contact resistance, and PW5's inspector shows all three: a caller that
## did its own `catalog.get_part(harness.value(...))` would be a second place the override table is
## consulted, which is the one thing `value()` exists to prevent.
##
## Empty for nothing fitted, which is a real state and not an error — see `_connector_for_pack`.
func connector_row(build: Build) -> Dictionary:
	return _row_for(build, CONNECTOR)


func capacitor_row(build: Build) -> Dictionary:
	return _row_for(build, CAPACITOR)


func _row_for(build: Build, key: String) -> Dictionary:
	if build.catalog == null:
		return {}
	var part_id := String(value(key, build))
	if part_id == "":
		return {}
	return build.catalog.get_part(part_id)
