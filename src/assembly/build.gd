class_name Build
extends RefCounted
## A chosen set of parts turned into physics and into the five numbers the user reads.
## This is the layer that makes Lothal a design workbench rather than a flight sim: every
## selectable spec in data/parts/ reaches the dynamics through here, and nothing reaches
## the dynamics any other way.
##
## The five derived stats (parts.md) recompute on every part change:
##   all-up weight · thrust-to-weight · hover throttle % · est. flight time · top speed

const INCH_M := 0.0254
const GRAVITY_MPS2 := 9.81
## Standard sea-level air, and no longer "the air". It is the DEFAULT and the ORACLE's value —
## what a Build is flown in when nobody says where they fly, which is what keeps ReferenceBuild
## at 496.0 g / 11.69:1 / 29.6% for ever. Derived through AirDensity rather than written as 1.225
## so the two cannot drift; the Rust copy is pinned to this one by tests/test_rust_constants.gd.
const AIR_DENSITY_KGM3 := 1.225

## How far the reachable thrust may fall below the bench figure before warnings() names the pack.
##
## A PICKED CONSTANT, and flagged as one deliberately. It is not a boundary in the physics — sag is
## a continuum, and every pack is somewhere on it. What it marks is the point at which the bench
## figure stops being a useful prediction of the aircraft, which is a judgement about a reader
## rather than about a battery. It survives as a threshold only because what it gates is a
## LIMITING statement that names the binding part, and the two figures either side of it are both
## printed in the sentence — so a builder reading it can see the continuum the constant sits on.
const SAG_WORTH_NAMING := 0.75

## The same kind of constant, for the same kind of statement: the fraction of static thrust a prop
## must still be making at the build's own top speed before Lothal stops to mention the pitch.
##
## A PICKED CONSTANT, and a round one. Unloading is a continuum too — every prop is somewhere on it
## the moment the aircraft moves — and half is a reader's threshold, not a boundary in the physics.
## It is also the level at which the answer to "why is this thing slow?" changes: below it, the
## limit is the propeller rather than the airframe, and that is a different part to go and swap.
## Stated for the record because it is the sort of number that gets fitted after the fact: the
## reference build sits at 0.60 and therefore does not warn, and that is where it landed rather
## than where it was aimed.
const UNLOADING_WORTH_NAMING := 0.50

## THE 55 g ELECTRONICS BUDGET, AND WHAT PW2 DID TO IT.
##
## It was: a flat fixed electronics package — FC+ESC stack, camera, VTX, antenna, receiver, wiring
## — 55 g of real mass carried as a constant, with each component that grew a physical form taking
## its share OUT of it rather than being added beside it. That is what CARVED_SHARES below records,
## and the REMAINDER was `wiring_mass_g()`: 14 g standing for wiring, connector, capacitor, solder
## and straps, lumped at the origin.
##
## THE REMAINDER MECHANISM IS RETIRED (plans/2026-09-10-power-room-design.md §4.4). The harness is
## now real objects with real masses in real places — see `Harness` and `mass_parts()` — so there
## is nothing left for a budget to be the leftover of, and this aircraft's electronics no longer
## sum to 55 g. That is why this constant is no longer called ELECTRONICS_MASS_G: it stopped being
## the mass of anything, and a constant that keeps its name while changing its meaning is the
## quietest kind of wrong.
##
## WHAT IT STILL IS: the budget the six shares in CARVED_SHARES were cut from, which is exactly
## what makes "does the budget still balance" an arithmetic question rather than an inspection —
## a seventh share that grew past what the budget has left is still an error worth catching. It is
## also the figure FramePlausibility quotes at the builder when it says how much of a small
## aircraft is electronics; replacing that sentence with the build's own electronics mass is PW4's,
## not this slice's.
##
## WHAT IT IS NOT, ANY MORE: a bound on the aircraft. The reference build's all-up weight moved
## when the harness became real, and the whole point of PW2 being its own slice is that the figure
## follows the model rather than the other way round. See docs/lothal/parts.md for the new number.
const ELECTRONICS_BUDGET_G := 55.0
## The box the SURVIVING REMAINDER is carried in: straps, tape, solder and heat-shrink, at the
## origin, which is where a thing that genuinely is everywhere belongs. Its SIZE stayed as it was
## rather than shrinking with the mass — an inertia box is linear in mass, and every entry that has
## since come out of the lump carries the difference honestly in its own box.
##
## It used to hold camera, VTX, antenna, receiver and wiring; LTHL-11 took the first four out and
## PW2 took the wiring, the connector and the capacitor. What is left is `Harness.REMAINDER_MASS_G`.
const ELECTRONICS_SIZE_M := Vector3(0.030, 0.015, 0.030)

## The FC/ESC stack's share of that budget, straight off parts.md's published breakdown of the
## fixed electronics package rather than re-estimated here. Taken OUT of ELECTRONICS_BUDGET_G, not
## added to it, which leaves 35 g of camera, VTX, antenna, receiver and wiring lumped at the origin.
## (This line read 43 g until build-level validation went looking for the number: 43 was the remainder
## when only the ESC had been carved out, and nothing updated it when the FC's 8 g followed. The code
## below has always computed 55 - 8 - 12; only the prose was stale.)
## The FLIGHT CONTROLLER's BUDGETED share, which is what the lump gives up rather than what any
## particular board weighs — the same shape ESC_BUDGET_MASS_G has, and for the same reason. Was
## 12 g of "FC/ESC stack" while the two were one lumped constant; unbundling the ESC into a
## catalog part forced honest figures for both, and a real F4 board is about 8 g against a real
## 45 A 4-in-1's 12 g.
##
## The reference board weighs exactly this, so the reference build's 496 g is unchanged to the
## gram; fit the H743 instead and the aircraft gets 4 g heavier, which is the right answer and the
## whole reason the flight controller stopped being a constant.
const FC_BUDGET_MASS_G := 8.0

## The ESC's BUDGETED share, which is what the lump gives up rather than what any particular board
## weighs. The reference build's 45 A 4-in-1 weighs exactly this, so its 496 g is unchanged to the
## gram; fit the 80 A board instead and the aircraft gets 6 g heavier, which is the right answer and
## the whole reason the ESC stopped being a constant.
const ESC_BUDGET_MASS_G := 12.0

## Kept as the sum of the two, because several places still speak of "the stack" as one object —
## it is still one object on the aircraft, bolted through one pattern.
const STACK_MASS_G := FC_BUDGET_MASS_G + ESC_BUDGET_MASS_G

## The CAMERA's budgeted share, and the three that follow it: the same shape FC_BUDGET_MASS_G and
## ESC_BUDGET_MASS_G have, for the same reason, and taken OUT of ELECTRONICS_BUDGET_G rather than
## added beside it. The default part in each category weighs exactly its share, so the reference
## build is unchanged at 496.0 g to the gram; fit a heavier one and the aircraft gains exactly the
## excess, which is the pattern the H743's 4 g overage already established.
##
## The four numbers are a breakdown of the 35 g that was left after the stack came out, and they
## are the class-typical masses of the parts a 5" freestyle actually carries: an 8 g micro camera,
## a 6 g 400 mW transmitter, a 5 g u.FL antenna and a 2 g receiver. Each has a default entry in its
## own category file that weighs it, and each of those entries states its provenance.
const CAMERA_BUDGET_MASS_G := 8.0
const VTX_BUDGET_MASS_G := 6.0
const ANTENNA_BUDGET_MASS_G := 5.0
const RECEIVER_BUDGET_MASS_G := 2.0

## Every share carved out of the budget, by the category that carved it. ONE TABLE RATHER THAN SIX
## CONSTANTS READ SIX PLACES, so "does the budget still balance" is a question with an arithmetic
## answer instead of an inspection: budget_remainder_g() is the remainder, and a share that grew past
## what the budget has left makes it negative rather than making the aircraft heavier.
const CARVED_SHARES := {
	"flight_controller": FC_BUDGET_MASS_G,
	"esc": ESC_BUDGET_MASS_G,
	"camera": CAMERA_BUDGET_MASS_G,
	"vtx": VTX_BUDGET_MASS_G,
	"antenna": ANTENNA_BUDGET_MASS_G,
	"receiver": RECEIVER_BUDGET_MASS_G,
}

## The components that come out of the lump and MAY BE OMITTED, in the order they are weighed.
## The stack's two are not here: a quad without a flight controller is not a build with something
## missing, it is not an aircraft.
##
## SIX SINCE C2, AND THE LAST TWO ARE A DIFFERENT KIND OF MEMBER. Camera, VTX, antenna and receiver
## were CARVED out of ELECTRONICS_BUDGET_G — the 55 g lump stood for them, so unbundling them cost
## the aircraft nothing. GPS and buzzer are ADDED: the lump was never their mass, the reference
## build carries neither, and there is nothing to carve them out of. Fitting one therefore makes
## the aircraft heavier, which — with navigation unmodelled — is the single most useful thing
## Lothal can say about a GPS. `CARVED_SHARES` is what tells the two kinds apart, and
## `added_components()` below derives the second list from it rather than restating it.
const OPTIONAL_COMPONENTS := ["camera", "vtx", "antenna", "receiver", "gps", "buzzer"]

## Which mount each optional component sits on. The ids are MountLayout's, and this table is the
## only place a component is associated with a place — no component carries an offset of its own,
## and nothing here is a coordinate. A masted GPS is not an exception to that: the mast is the
## MODULE's own published dimension, read the same way its box is, and it reaches the seat through
## MountLayout.seated_centre_m's `rise_m`. See component_rise_m().
const COMPONENT_MOUNTS := {
	"camera": "camera_bay",
	"vtx": "vtx_bay",
	"antenna": "antenna_mount",
	"receiver": "rx_bay",
	"gps": "gps_mount",
	"buzzer": "buzzer_mount",
}

## Which SYSTEM owns each optional component — the single source for which rail a component is
## picked on, which panel describes it, and which system lights it on the model.
##
## THE TABLE EXISTS BECAUSE THE ALTERNATIVE IS TWO HAND-WRITTEN LISTS. Until C3, one
## `ElectronicsPicker` iterated OPTIONAL_COMPONENTS directly and rendered all of it on Video's
## rail, which is why `gps` and `buzzer` arrived there in C2 without anybody choosing that. The
## split could have been done with a list of three names per picker; that is exactly the shape
## P10f found — *the two lists were never the same list* — so the pickers are built by FILTERING
## OPTIONAL_COMPONENTS through this table instead, and a seventh component that is not named here
## does not land quietly on one rail or the other.
##
## The system names are `GlassShell.SYSTEMS`' own, and C4 asserts that rather than trusting it.
const COMPONENT_SYSTEM := {
	"camera": "Video",
	"vtx": "Video",
	"antenna": "Video",
	"receiver": "Control",
	"gps": "Control",
	"buzzer": "Control",
}

## The part each category gets when a selection does not name one. Every Build call site written
## before these categories existed still means what it meant, and the reference build still weighs
## 496 g — each of these weighs exactly its share above. An EMPTY string means "not fitted", which
## is what a whoop passes.
##
## GPS AND BUZZER ARE DELIBERATELY ABSENT, and the absence is the feature. A category with no entry
## here resolves to "" — not fitted — through the `.get(category, "")` the two readers below use,
## so every Build call site written before C2 builds the same aircraft it always did and every
## oracle in the project is bit-identical. Giving either one a default would retrofit a few grams
## and a centre-of-mass shift onto every build in the app, which is the same mistake
## `project_schema.gd:43` uses a GPS as its worked example of.
const DEFAULT_COMPONENT_IDS := {
	"camera": "cam_micro_analog",
	"vtx": "vtx_analog_400mw",
	"antenna": "antenna_rhcp_ufl",
	"receiver": "rx_elrs_2400",
}

## WHAT THE BUDGET HAS LEFT once every share above has been taken out of it: 14 g, and it is a
## FIGURE RATHER THAN A MASS NOW.
##
## It used to be `wiring_mass_g()` — the mass of the wiring, connectors, capacitor, solder,
## heat-shrink and straps, lumped at the origin because a harness is everywhere on the aircraft by
## definition. PW2 replaced every one of those with a real object at a real place (`Harness`,
## `harness_mass_g()`), so nothing reads this as a mass any more. It survives as the arithmetic
## that keeps CARVED_SHARES honest: a seventh share that grew past what the budget has left makes
## this negative rather than making the aircraft heavier, and the check that watches it is the
## reason the table exists.
##
## The 14 g it returns is NOT what the reference build's harness weighs. That number is on the
## harness now, and it is bigger — see the re-baseline in docs/lothal/parts.md.
static func budget_remainder_g() -> float:
	return ELECTRONICS_BUDGET_G - carved_total_g()


## Every optional component omitted, in the shape from_ids takes. What a whoop on an AIO passes,
## and what a fixture passes when it needs an aircraft that is FORE/AFT SYMMETRIC.
##
## That second use is not a test convenience and it is worth stating where the mechanism lives.
## The fitted components sit at real places, so a fitted build's centre of mass is 0.18 mm behind the
## origin — small, correct, and enough to tip an aircraft over in three seconds if it is flown with
## four equal motor commands and no flight controller, because a constant torque integrates twice.
## Two suites do exactly that on purpose, to ask a question about the PACK with no controller in
## the path to answer it for them, and one asks whether RateTune's scaling law equalises the
## response across frames. All three need the confound gone rather than compensated, and a build
## with nothing fitted is the honest way to say so: it is a real aircraft, it is symmetric by
## construction, and it needs no new machinery to express.
static func no_components() -> Dictionary:
	var out := {}
	for category in OPTIONAL_COMPONENTS:
		out[category] = ""
	return out


## The sum of every carved share. Computed rather than written down, which is the whole reason
## CARVED_SHARES is a table: a seventh component added to it cannot fail to appear here.
static func carved_total_g() -> float:
	var total := 0.0
	for category in CARVED_SHARES:
		total += float(CARVED_SHARES[category])
	return total


## The optional components the budget never stood for: everything in OPTIONAL_COMPONENTS that
## CARVED_SHARES does not name. GPS and buzzer today.
##
## DERIVED, NOT WRITTEN DOWN, and that is the whole point of it — P10f's finding was that the two
## lists were never the same list. A seventh component added to OPTIONAL_COMPONENTS and given a
## carved share appears here automatically as carved; one added without a share appears as added.
## There is no second table to forget to edit, and `electronics_mass_g()` splitting into carved and
## added terms means the identity `electronics = carved + harness + added` holds by construction
## rather than by two authors agreeing.
static func added_components() -> Array[String]:
	var out: Array[String] = []
	for category in OPTIONAL_COMPONENTS:
		if not CARVED_SHARES.has(category):
			out.append(String(category))
	return out


## The other half of the same partition: the optional components the 55 g lump DID stand for.
## Camera, VTX, antenna and receiver — CARVED_SHARES' other two entries are the stack's boards,
## which are not optional at all.
##
## Its existence is what lets a caller say "the carved four" without writing them down, which
## several checks needed the moment OPTIONAL_COMPONENTS stopped being four names: a loop that
## indexes CARVED_SHARES or DEFAULT_COMPONENT_IDS by category is asking about THIS list, and
## before C2 the two were accidentally the same.
static func carved_components() -> Array[String]:
	var out: Array[String] = []
	for category in OPTIONAL_COMPONENTS:
		if CARVED_SHARES.has(category):
			out.append(String(category))
	return out


## The optional components one system owns, in the order the mass model weighs them — what each
## payload rail is built from.
##
## **IT REFUSES RATHER THAN SHRUGS**, and that is the whole of why this is a function and not a
## dictionary comprehension at the call site. The failure mode of two lists is SILENCE: a category
## in OPTIONAL_COMPONENTS with no entry in COMPONENT_SYSTEM belongs to no system, so a filter that
## skipped it would leave it weighed by the mass model, saved by the schema, drawn on the aircraft
## — and pickable on no rail in the app. Nothing would be broken enough to notice. So an unclaimed
## category is not skipped: this answers NOTHING for anybody until the table is fixed, pushes an
## error naming the category, and leaves the rail that asked with no rows in it, which is the one
## thing a builder cannot miss. A blank rail with an error in the log is a bug report; a component
## that silently cannot be fitted is a mystery six months later.
##
## The two tables are parameters with the constants as defaults so the refusal itself can be
## tested: `COMPONENT_SYSTEM` is a const Dictionary and therefore read-only at runtime, so a test
## that could not pass its own seventh category in could only assert the happy path.
static func components_for_system(system: String, p_categories: Array = OPTIONAL_COMPONENTS,
		p_owner: Dictionary = COMPONENT_SYSTEM) -> Array[String]:
	var unclaimed := unclaimed_components(p_categories, p_owner)
	if not unclaimed.is_empty():
		push_error(("Build.COMPONENT_SYSTEM claims no system for %s; "
			+ "no component rail can be built until it does") % ", ".join(unclaimed))
		return [] as Array[String]

	var out: Array[String] = []
	for category in p_categories:
		if String(p_owner[category]) == system:
			out.append(String(category))
	return out


## Every optional component no system owns. Empty is the only correct answer; it is returned as a
## list rather than a bool so the error above can name what is missing, and so C4's coverage check
## can report the category rather than just the fact.
static func unclaimed_components(p_categories: Array = OPTIONAL_COMPONENTS,
		p_owner: Dictionary = COMPONENT_SYSTEM) -> Array[String]:
	var out: Array[String] = []
	for category in p_categories:
		if not p_owner.has(category):
			out.append(String(category))
	return out


## How many grams the fitted ADDED components put on this aircraft, and therefore how much heavier
## it is than the same build without them. Zero on every build that fits neither, which is every
## build the project had before C2.
func added_components_mass_g() -> float:
	var total := 0.0
	for category in added_components():
		if components.has(category):
			total += float((components[category] as Dictionary).get("mass_g", 0.0))
	return total


## How far a component's own centre stands off the face it mounts to, beyond half its own box: the
## mast. Read from `specs.mast_height_mm`, in metres, zero for a part that publishes none.
##
## GENERIC RATHER THAN A GPS BRANCH. Nothing here asks what category the part is, so a future
## masted antenna or a standoff-mounted receiver needs a spec field and no code. The one component
## that publishes the field today is the GPS, and design §2.3 is why it is worth a mechanism: a
## masted module puts several grams 45-70 mm above the top plate, which is the highest mass on the
## aircraft and the one that moves the centre of mass vertically more than anything else fitted.
##
## The HEIGHT is a labelled default with a field beside it (design §0). WHERE THE MASS GOES is not
## a default — it is wiring, and it is asserted.
static func component_rise_m(part: Dictionary) -> float:
	return float((part.get("specs", {}) as Dictionary).get("mast_height_mm", 0.0)) / 1000.0


## The same height with the BUILDER'S value preferred, which is what the mass model and the drawing
## both read. C6: the mast is a builder's choice — design §9 is explicit that nothing would sharpen
## the catalog's figure, because the stalk you actually fitted is the answer — so the field beside
## the row is the source and the catalog entry is only where it starts.
##
## GENERIC, and deliberately not keyed on "gps": the override applies to any part whose specs
## DECLARE a mast, so a masted antenna arriving later needs a spec field and no code here. Keying
## it on the category name would put a seventh hand-written list in a wave whose whole subject is
## that two were already one too many.
func rise_m_for(part: Dictionary) -> float:
	var override := float(assembly_value("mast_height_m"))
	if override >= 0.0 and (part.get("specs", {}) as Dictionary).has("mast_height_mm"):
		return override
	return component_rise_m(part)

## The FC/ESC stack's own bolt pattern. 30.5x30.5 is the full-size standard, and it is a property
## of the STACK rather than of the frame — which is the whole reason a fit check is worth having.
## Buy the wrong one and it does not bolt to your frame; frames.json drills the 3.5" freestyle
## 20x20 and the whoops 25.5x25.5, and none of those take this board.
##
## The flight controller is still not selectable; the ESC now is, and carries its own pattern in
## data/parts/escs.json. Both bolt through the same holes on a real stack, and warnings() checks
## the ESC's against the frame the same way it checks the motors'.
const STACK_MOUNT_PATTERN := "30.5x30.5"

## The board a selection that does not name one gets. Every Build call site written before ESCs
## existed still means what it meant, and the reference build still weighs 496 g.
const DEFAULT_ESC_ID := "esc_4in1_45a_30x30"

## The board a selection that does not name one gets. Every Build call site written before
## flight controllers existed still means what it meant, and the reference build still
## weighs 496 g — this board weighs exactly FC_BUDGET_MASS_G.
const DEFAULT_FC_ID := "fc_f405_30x30"

## Mirrors battery.rs DEFAULT_CHEMISTRY. Rust cannot export constants to GDScript, so an
## unrecognised chemistry name falls back to this; the value must agree with the Rust source
## of truth, which the golden cross-check enforces.
const BATTERY_DEFAULT_CHEMISTRY := "LiPo"


## How the FC/ESC stack attaches, in the same shape MountPoint.mounting_of() returns for a catalog
## part. Here rather than in the catalog because the stack is not a catalog part yet — and stating
## it in the one place the mesh and the mass both read keeps it from becoming two opinions the day
## it becomes one.
static func stack_mounting() -> Dictionary:
	return {"attachment": MountPoint.BOLT, "pattern": STACK_MOUNT_PATTERN}

## The frame's centre plate, as a box, derived from arm length rather than authored — a
## body dimension is not in parts.md's spec-field table, so it does not belong in the JSON.
const FRAME_PLATE_TO_ARM_RATIO := 1.364   # 110 mm arm -> 150 mm plate
const FRAME_PLATE_THICKNESS_M := 0.010

## Drag area (Cd*A) of the reference 5" build, scaled by frame size. Calibrated so the
## reference build's top speed lands inside physics.md §8's real-world 100-130 km/h band;
## the previous hard-coded lumped coefficient capped it at ~56 km/h.
const REFERENCE_DRAG_AREA_M2 := 0.009
const REFERENCE_ARM_M := 0.110

## Top speed is quoted at a sustained 45-degree lean: the lean a speed run actually sits at.
##
## This constant's ORIGINAL justification has expired and is worth recording, because the obvious
## reading of the new physics is the wrong one. It used to say that the geometric maximum lean was
## about 85 degrees and that a model with no prop unloading would badly over-predict there — the
## implication being that once unloading existed the lean could be computed rather than assumed.
##
## It can be, and it was, and the answer is 66.6 degrees at 163 km/h for the reference build
## (2026-08-14): full throttle, lean free, limited by the airspeed at which the prop can no longer
## make the thrust that lean needs. That is ABOVE physics.md §8's 100-130 km/h band, while the
## fixed 45 degrees gives 107 km/h inside it.
##
## So 45 degrees was never standing in for missing propeller physics. It is a statement about what a
## PILOT holds, which is a different kind of claim and one the propeller model has nothing to say
## about. It stays. What the model adds is a ceiling it can now be checked against, and an honest
## thrust cap below.
const TOP_SPEED_LEAN_RAD := 0.7853982

## Passed as `open_circuit_v` to mean "at the pack's NOMINAL voltage" — the datum every figure on
## the stats panel is quoted at, and the one the 11.7:1 and 29% oracles are defined at
## (physics.md §5). It is the default everywhere, so the analytic layer answers the spec-sheet
## question unless a caller explicitly asks a different one.
##
## A sentinel rather than an overload because the alternative is two near-identical solvers, and
## the project has already paid for one number having two expressions. Negative because no pack
## rests at a negative voltage, so it cannot collide with a real reading.
const AT_NOMINAL := -1.0

## How a freestyle pilot actually spends a pack, as fractions of flying time. Every current figure
## the app quotes for a FLIGHT rather than a hover is the model's own answer at each of these
## points, time-weighted — see average_flight_current_a().
##
## THIS REPLACED A SCALAR, AND IT IS STILL A GUESS. Until 2026-08-14 this was
## `FLIGHT_CURRENT_TO_HOVER_RATIO := 1.6`, a multiplier over hover current with no mechanism under
## it, which battery_plausibility.gd told builders to their face could only be settled with a
## stopwatch. It could not be validated because there was nothing to validate.
##
## What changed is not that the guessing stopped. It is WHERE the guess sits. The current at each
## row below is computed — trimmed by the forward-flight propeller model at that airspeed and load
## factor, through the same sag and the same current law the hover figure uses. What is assumed is
## only the MIX: how much of an evening is spent cruising versus punching. That is a claim about a
## pilot, stated in units a pilot can disagree with, and a builder who flies gentle cruise lines
## and one who flies bandos disagree about it out loud. The scalar could not express that
## disagreement, which is exactly why it could never be checked.
##
## Named FREESTYLE deliberately. A racer and a long-range cruiser fly different profiles, and the
## day either is offered this constant is the thing that grows a sibling rather than a fudge.
##
## Steady cruise ALONE was considered and rejected: it is cheaper than hovering (translational lift
## is real), so averaging over it predicts about eight minutes for the reference build and busts the
## 4-6 min band in physics.md §8. A model that is honest per-term and dishonest overall is worse
## than the scalar it replaced.
const FREESTYLE_FLIGHT_PROFILE: Array[Dictionary] = [
	{"name": "hover / slow", "fraction": 0.15, "airspeed_mps": 2.0, "load_factor": 1.0},
	{"name": "cruise", "fraction": 0.40, "airspeed_mps": 12.0, "load_factor": 1.0},
	{"name": "fast", "fraction": 0.25, "airspeed_mps": 22.0, "load_factor": 1.0},
	{"name": "manoeuvre", "fraction": 0.15, "airspeed_mps": 15.0, "load_factor": 2.0},
	{"name": "punch", "fraction": 0.05, "airspeed_mps": 10.0, "load_factor": 3.0},
]
const USABLE_CAPACITY_FRACTION := 0.80

var frame: Dictionary
var motor: Dictionary
var propeller: Dictionary
var battery: Dictionary
var esc: Dictionary
var fc: Dictionary
## The optional components, by category — camera, VTX, antenna, receiver, GPS, buzzer. A category
## ABSENT from this dictionary is a component not fitted, which is a real build rather than an
## incomplete one, and it costs the aircraft nothing. Held as one dictionary rather than a field
## each because everything that reads them reads them all the same way (mass_parts,
## electronics_mass_g), and near-identical fields are places a seventh component would have to be
## added — a prediction C2 collected on, twice.
var components: Dictionary = {}
## The prop guard, applied to every motor (v1: one guard for the whole build). Empty when nothing
## is fitted — the reference build's default, so its 496 g / 11.69:1 / 29.6% oracles are unmoved
## bit-identically. See guard_id below for the id that resolved to this dictionary.
##
## LANDED IN P10b (plans/2026-08-26-propulsion-room-design.md §3.4), which is the wiring P10a's
## `PropGuard.as_part_mass` was written for but the slice did not carry across. Without this
## field the closure the BEMT solve reads through `forward_ratios()` would have nothing to close
## against — a duct fitted on paper and forgotten in flight.
var guard: Dictionary = {}
## THE CURRENT PATH, as data — plans/2026-09-10-power-room-design.md §4.2, slice PW2. Connector,
## capacitor, and a gauge and length for each of the two wire runs, every one of them a default
## DERIVED from this build with an authored override on top.
##
## An object rather than six fields, and a HARNESS rather than a resolved dictionary — which is the
## opposite of the call `assembly` makes above, so it is worth saying why they differ. `assembly`
## is resolved because AssemblyTweaks reads a user file and clamps against limits computed FROM a
## Build, so a Build holding one would be a cycle. `Harness` clamps against nothing and reads no
## file: it holds a sparse override table and asks the build for the rest, which means a Build can
## hold one without the cycle and without a second copy of the defaults living anywhere.
##
## Never null. A Build assembled field by field — several fixtures still do — gets the derived
## harness for the parts it was given, which is the same answer `from_ids` would have produced.
var harness := Harness.new()
var catalog: PartsCatalog

## THE IDS THIS BUILD IS AN AIRCRAFT MADE OF, kept beside the resolved dictionaries so the build can
## be re-resolved when the catalog under it moves — see `refit_from`, which is §4 of
## plans/2026-09-01-authored-blade-design.md. Written once by `from_ids` and never edited: a Build
## assembled field by field, which several fixtures still do, carries an empty table here and
## therefore has nothing to refit from, which is honest rather than wrong.
var _part_ids: Dictionary = {}

## THE AIR THIS BUILD IS FLOWN IN, and the line that makes a Build an aircraft AT A PLACE rather
## than an aircraft.
##
## That is a real change in what this object means, and it is the honest one. Thrust-to-weight was
## never a property of a parts list; it was a property of a parts list in air, and the old code got
## away with the elision only because there was exactly one atmosphere. Two identical parts lists
## at two different fields are now two different objects with different TWR, which is correct.
##
## Standard by DEFAULT, and that default is load-bearing rather than convenient: ReferenceBuild
## calls the defaulted constructor and therefore cannot see user state BY CONSTRUCTION rather than
## by remembering to. It is the same discipline as PartsCatalog's two constructors — there, a
## boolean defaulting to "no custom parts" would have put one forgettable flag between the oracle
## and a file in the user's writable directory; here the forgettable thing is an omitted argument,
## and omitting it lands on standard air, which is where the oracle must be.
var air := AirDensity.standard()

var arm_m: float
var mass_properties: MassProperties
## Lazily built by forward_ratios(). Never read directly. Cleared in _recompute so a Build that
## is reconfigured — different guard, different prop — pays the ~150 ms BEMT solve once for its
## new surface rather than flying the previous fit's, which would be a silent regression the
## Rust-side cache key alone cannot save.
var _forward_ratios: BemtRatios = null
## The tip-loss suppression the fitted guard earns (§4.0). 0.0 when no guard is fitted, positive
## when a duct's `tip_gap_mm` is small compared with the blade's tip chord. Derived once in
## `_recompute` from `PropellerDocument.chord_at(1.0)` — the physics's own length scale, per
## `PropGuard.tip_loss_closure`'s own refusal to keep the chord as a constant.
var guard_closure: float = 0.0
## What the closure does to STATIC thrust and to STATIC torque, from `BemtModel.
## static_closure_factors()`. Both are 1.0 when no guard is fitted.
##
## TWO NUMBERS, NOT ONE, AND THAT IS THE POINT. `k_q` is fit from `k_t` by a fixed multiple
## (`PropellerModel.fit_k_q`), so scaling `k_t` by the thrust factor and then fitting `k_q`
## from the scaled value would move torque the same way thrust moved. The solve says the
## opposite: closing the tip leak enlarges the momentum sink, the induced velocity drops, and
## induced drag drops with it. Measured on the reference 5x4.5x3 at the cinewhoop duct's
## closure of 0.5615 — thrust x1.0017, torque x0.9829. Fitting k_q from the scaled k_t would
## have reported a duct costing 0.17% MORE current where the model says it saves 1.71%, and
## `effective_max_amps` (which is a ratio of two k_q values) would have carried that the same
## wrong way. `tests/test_prop_guard.gd`'s `_a_duct_saves_current_rather_than_costing_it`
## asserts the direction so the shortcut cannot come back.
var _static_closure_factor: float = 1.0
var _static_closure_torque_factor: float = 1.0
var k_t: float
var k_q: float
## Motor max_amps adjusted for the selected prop: current tracks shaft torque, so a prop
## that demands more torque at a given RPM also draws more current than the one the
## motor's amp figure was measured with.
var effective_max_amps: float
var drag_coefficient: float

## How this builder assembled the aircraft, in the same resolved form AssemblyTweaks hands the
## geometry (AssemblyTweaks.resolved_m) and AirframeModel draws from. Empty means "whatever the
## parts imply", which is what DEFAULT_ASSEMBLY below spells out.
##
## THIS IS THE LINE THAT MADE ASSEMBLY PHYSICS-BEARING, and it is a reversal of a decision this
## project made deliberately and wrote down at length (assembly_tweaks.gd). That decision was
## right for what it covered — a 2 mm prop shim genuinely changes clearance and nothing else — and
## it named this exact door: "when the mass model grows a real centre-of-gravity term, these values
## are already the single source for it; nothing has to be re-decided, a consumer is added." This
## is that consumer. What did NOT happen is the thing it forbade: there is no second copy of a
## mount position inside the physics. Build reads the same MountLayout table Lab draws from.
##
## A resolved DICTIONARY rather than an AssemblyTweaks object, deliberately: AssemblyTweaks reads
## a user file and clamps against limits that are themselves derived from a Build, so a Build
## holding one would be a cycle. Build takes the answer, not the thing that computes it.
var assembly: Dictionary = {}

## What the parts imply when nobody has tweaked anything: pack centred on the top plate, standoffs
## at whatever the frame implies. Here rather than in AirframeModel because BOTH the drawing and
## the mass model need the same fallbacks, and two lists of defaults is two things to get out of
## step.
## `prop_imbalance_g` is in GRAMS rather than metres, which is why this dictionary can no longer be
## described as "the tweaks in SI". It is here rather than as a spec on the propeller because
## residual imbalance is a property of the BUILD, not of the part: the same prop out of the same
## bag is balanced or not depending on what has happened to it since, and a catalog entry claiming
## a figure would be asserting something about an object nobody has weighed. See VibrationModel.
const DEFAULT_ASSEMBLY := {
	"prop_spacer_m": 0.0, "soft_mount_m": 0.0, "plate_gap_m": -1.0,
	"battery_mount": "strap_top", "battery_offset_m": 0.0,
	"prop_imbalance_g": VibrationModel.DEFAULT_IMBALANCE_KG * 1000.0,
	# The GPS mast, and -1.0 means "whatever the fitted module publishes" — the same sentinel
	# plate_gap_m uses, and for the same reason: zero is a LEGITIMATE mast height (a flat module),
	# so absence cannot be spelled 0.0 without making "flat" and "unset" the same answer.
	"mast_height_m": -1.0,
	# Camera uptilt in DEGREES (video-room design §2). A labelled guess: 25 is what most builds fly,
	# and at 0 Sim makes you pitch hard to see the gate. No sentinel is needed, unlike the mast —
	# nothing in the catalog publishes an angle for this to fall back to, so the default IS the
	# answer. Touches no physics: the reference oracles do not read it, and that is asserted.
	"camera_tilt_deg": 25.0,
}

## `component_ids` names the optional components — camera, VTX, antenna, receiver — and anything it
## leaves out gets DEFAULT_COMPONENT_IDS, so every call site written before these categories
## existed builds exactly the aircraft it used to. AN EMPTY STRING MEANS NOT FITTED, and it is the
## only way to say so: a whoop passes {"camera": "", "vtx": "", "receiver": ""} and gets an
## aircraft that is lighter by the whole of those three shares.
##
## A DICTIONARY rather than four more positional parameters, and the reason is the omission case:
## four trailing defaults would make "" and "left out" look identical at a call site, and the
## difference between them is 21 g.
static func from_ids(p_catalog: PartsCatalog, frame_id: String, motor_id: String, prop_id: String,
		battery_id: String, esc_id: String = DEFAULT_ESC_ID,
		fc_id: String = DEFAULT_FC_ID, component_ids: Dictionary = {},
		p_air: AirDensity = null, guard_id: String = "",
		harness_overrides: Dictionary = {}) -> Build:
	var b := Build.new()
	# `null` rather than AirDensity.standard() as the default value, because a GDScript default
	# argument is evaluated once and shared: a literal object default would hand every Build in the
	# process the SAME AirDensity instance, and one caller mutating its elevation would move the
	# oracle. The null is the language's shape, not an admission that air is optional.
	b.air = p_air if p_air != null else AirDensity.standard()
	b._part_ids = {
		"frame": frame_id,
		"motor": motor_id,
		"propeller": prop_id,
		"battery": battery_id,
		"esc": esc_id,
		"fc": fc_id,
		"guard": guard_id,
	}
	# The harness grows here the way the guard did in P10b — one more trailing argument, defaulting
	# to what the parts imply, so every call site written before Power existed builds exactly the
	# aircraft it used to except for the harness it was always carrying. SPARSE: only what the
	# caller authored is stored, and everything else follows the frame and the pack.
	b.harness = Harness.from_overrides(harness_overrides)
	for category in OPTIONAL_COMPONENTS:
		b._part_ids[category] = String(component_ids.get(category, DEFAULT_COMPONENT_IDS.get(category, "")))
	b.refit_from(p_catalog)
	return b


## Re-resolves every part from `p_catalog` by the id it was fitted under, and recomputes.
##
## THE RULE (plans/2026-09-01-authored-blade-design.md §4): a Build is rebuilt from its parts when
## the parts store changes. Publishing an edited blade re-writes a record a build may already be
## flying, and P10b's finding applies unchanged — `_forward_ratios` caches the ratio surface, and a
## build holding one solved from the old planform keeps flying the old planform. The stale set is
## larger than the surface: `_static_closure_factor` read the old tip chord, `k_t` was scaled
## against the old blade, and the spin-up τ was fitted to the old blade's inertia. Every one of
## them is derived in `_recompute`, so re-resolving the dictionaries and recomputing clears all
## four at once rather than clearing four handles by name and forgetting the fifth.
##
## IN PLACE rather than returning a twin, and that is the load-bearing half. A caller that rebuilt
## a fresh Build would trivially get a fresh `_forward_ratios` object whether or not the planform
## under it had moved — which is exactly why §4's assertion is a PAIR, and why the object-identity
## half of it only means something against a build that was asked to refit itself.
##
## `from_ids` is this function's first caller, so there is one resolution path rather than two: the
## constructor records the ids and then refits, and a category added to one is added to both by
## construction.
func refit_from(p_catalog: PartsCatalog) -> void:
	catalog = p_catalog
	frame = p_catalog.get_part(String(_part_ids.get("frame", "")))
	motor = p_catalog.get_part(String(_part_ids.get("motor", "")))
	propeller = p_catalog.get_part(String(_part_ids.get("propeller", "")))
	battery = p_catalog.get_part(String(_part_ids.get("battery", "")))
	esc = p_catalog.get_part(String(_part_ids.get("esc", "")))
	fc = p_catalog.get_part(String(_part_ids.get("fc", "")))
	# Rebuilt rather than patched, so a component whose id no longer resolves is UNFITTED after a
	# refit instead of left behind as the part it used to be. A builder who deletes a custom camera
	# and finds the aircraft still 8 g heavier would be reading a part that is gone.
	components = {}
	for category in OPTIONAL_COMPONENTS:
		var part_id := String(_part_ids.get(category, DEFAULT_COMPONENT_IDS.get(category, "")))
		if part_id == "":
			continue
		var part: Dictionary = p_catalog.get_part(part_id)
		# An id that resolves to nothing is a typo or a part removed from the catalog. It is left
		# UNFITTED rather than fitted as a massless ghost, which is the same answer the mass model
		# would have given and is at least visible in the details panel as a missing component.
		if part.is_empty():
			continue
		components[category] = part
	# The guard, one for the whole build. Same treatment as an optional component: an id that
	# resolves to nothing leaves the guard slot empty rather than filled with a massless ghost,
	# which is what keeps the reference build's 496 g oracle bit-identical at guard_id = "".
	guard = {}
	var fitted_guard_id := String(_part_ids.get("guard", ""))
	if fitted_guard_id != "":
		var guard_part: Dictionary = p_catalog.get_part(fitted_guard_id)
		if not guard_part.is_empty():
			guard = guard_part
	_recompute()

## The same aircraft, at a different field.
##
## This exists because "it cannot hover HERE" is a very different statement from "it cannot hover",
## and telling them apart needs the build's own sea-level twin to compare against. Rebuilt from the
## catalog rather than copied and rescaled: the density ratio moves k_t exactly, but it also moves
## k_q and therefore the current the pack is asked for, so the throttle a current limit binds at
## does NOT follow a clean ratio. Recomputing is the only way to get that right, and the warning
## path is the only caller — this is not on the per-frame road.
##
## The assembly comes with it. A twin that forgot where the pack was strapped would answer a
## question about a different aircraft.
func at_air(p_air: AirDensity) -> Build:
	var ids := {}
	for category in OPTIONAL_COMPONENTS:
		if components.has(category):
			ids[category] = str((components[category] as Dictionary)["part_id"])
		else:
			ids[category] = ""
	# A twin at a different air must carry the same guard — otherwise "would this fly at sea
	# level" answers about a different aircraft. Fits the guard by its id, same as every other
	# component, so the twin re-runs the closure derivation at the new density rather than
	# copying the old scalar (the closure IS density-invariant, but stating that here would
	# duplicate the property BemtRatios asserts and drift is exactly the failure mode).
	var g_id := str(guard.get("part_id", "")) if not guard.is_empty() else ""
	var twin := Build.from_ids(catalog, str(frame["part_id"]), str(motor["part_id"]),
		str(propeller["part_id"]), str(battery["part_id"]), str(esc["part_id"]),
		str(fc["part_id"]), ids, p_air, g_id)
	# The harness comes with it, for the assembly's reason: a twin that forgot the builder's lead
	# lengths would answer a question about a different aircraft. The OVERRIDES travel, not the
	# resolved values — the twin re-derives its defaults from its own parts, which is the whole
	# point of a sparse table.
	twin.harness = Harness.from_overrides(harness.overrides())
	twin.set_assembly(assembly)
	return twin


## Adopts an assembly configuration and recomputes. The mass properties are the only thing that
## changes: nothing here touches thrust, current or any collective figure, which is why the
## project's three fixed points survive a pack slid to the end of its travel.
##
## Partial dictionaries are fine — anything absent falls back to DEFAULT_ASSEMBLY, which is the
## same "an absent key means whatever the parts imply" rule the tweak FILE already follows.
func set_assembly(resolved: Dictionary) -> void:
	assembly = resolved
	_recompute()


## This drone's printing decisions (`Project.printing`) — printed-room PR1. Read by `mass_parts` for
## the printed parts a builder has FITTED, and by AirframeModel to draw them. Empty is every build
## written before the Printed room, and fits nothing: the reference build's 507.48 g is unmoved.
var printing: Dictionary = {}


## This drone's configuration decisions (`Project.config`) — Config room C1/C2. Only one key of it
## reaches the physics today, `motor_spin`, and it does so through `MotorLayout.spin_map()` alone.
## Empty is every build written before the Config room, and is today's constants exactly.
var config: Dictionary = {}


## No `_recompute()`: nothing in the config block changes a mass, a coefficient or a geometry, so
## the 507.48 g / 11.43:1 / 29.9 % oracles cannot move by setting it. It is read where it is used.
func set_config(p_config: Dictionary) -> void:
	config = p_config


func set_printing(p_printing: Dictionary) -> void:
	printing = p_printing
	_recompute()


## Where the pack sits: `{"mount": MountPoint or null, "position": Vector3}`. THE ONE SEAT — `mass_parts`
## weighs the pack here and the printed battery pad (PR11) hangs beneath it, so the two cannot disagree.
##
## A fitted, readable pad lifts the pack off its mount by the pad's thickness (PR17, `battery_rise_m`): the
## pad sits on the plate and the pack on the pad. Before PR17 the pack stayed on the plate and the pad was
## weighed inside it — found by drawing the pad where it is weighed.
##
## A frame that does not offer the saved mount — a whoop whose bottom plate has no room for strap slots —
## falls back to the top plate rather than dropping the pack at the origin. Same rule as AirframeModel's
## drawing: the pack is somewhere on every real aircraft.
func battery_seat() -> Dictionary:
	var battery_mount := MountLayout.by_id(mount_points(), String(assembly_value("battery_mount")))
	if battery_mount == null:
		battery_mount = MountLayout.by_id(mount_points(), "strap_top")
	return {"mount": battery_mount, "position": MountLayout.seated_centre_m(battery_mount, battery_size_m(),
		float(assembly_value("battery_offset_m")), battery_rise_m())}


## How far the pack stands off its mount, metres: a fitted, readable battery pad's thickness, else zero.
## AirframeModel seats the drawn pack with the same number.
func battery_rise_m() -> float:
	if not BatteryPad.is_fitted(printing):
		return 0.0
	var dims := BatteryPad.dimensions(battery, printing)
	return float(dims["thickness_mm"]) / 1000.0 if bool(dims["ok"]) else 0.0


## One assembly value, with the parts-implied fallback applied. The single reader, so a caller
## cannot accidentally invent a different default for a key it happens to know about.
func assembly_value(key: String) -> Variant:
	return assembly.get(key, DEFAULT_ASSEMBLY[key])


## The frame's mount table at the standoff height currently fitted. Both the mass model below and
## Lab's drawing resolve mounts through MountLayout; this is Build's way in.
func mount_points() -> Array[MountPoint]:
	return MountLayout.for_frame(frame, float(assembly_value("plate_gap_m")))


func _recompute() -> void:
	arm_m = float(frame["specs"]["arm_mm"]) / 1000.0

	# The guard's tip-loss closure and static thrust boost — computed first, before k_t, because
	# k_t scales by the static factor and everything downstream (peak thrust, hover throttle,
	# TWR) reads that scaled k_t. Zero-closure short-circuit is not an optimisation: it keeps
	# the reference build's 496 g / 11.69:1 / 29.6% oracles bit-identical at guard_id = "",
	# because `PropGuard.tip_loss_closure` returns 0.0 for a bumper AND for an unfitted guard,
	# and `BemtRatios.static_closure_factor` returns 1.0 at closure = 0.0. See P10a's row for
	# why the oracle-preservation check that guards this is a positive assertion.
	guard_closure = 0.0
	_static_closure_factor = 1.0
	_static_closure_torque_factor = 1.0
	if not guard.is_empty():
		# The blade's tip chord IS the length scale §0's rule names, and PropellerDocument's
		# `chord_at(1.0)` is the ONE place it lives — a constant here would be a second copy
		# `tip_loss_closure`'s own refusal exists to prevent. The three plumbing links §4.0
		# names run through here: this one (the length scale), the k_t scaling below (the
		# static path), and _forward_ratios clearance (the surface cache).
		#
		# READABLE FIRST, THEN THE CLAIM. `tip_loss_closure` asks only about `kind` and
		# `tip_gap_mm` — it never calls `compute()`, because P9 wrote it as a pure statement
		# about a gap and a length scale. `mass_parts()` DOES call `compute()`, through
		# `as_part_mass`, and drops a guard whose geometry is refused. Without this check the
		# two disagree: a duct with a mistyped `wall_mm` fits no mass, appears on no inspector
		# row, and still hands the aircraft its tip-loss suppression. One unreadable part, two
		# answers. So the closure is claimed only for a guard the geometry can read, which is
		# the same "an unreadable part models as no part" posture the refusal exists for.
		var guard_specs: Dictionary = guard.get("specs", {})
		if String(PropGuard.compute(guard_specs).get("tier", "")) == "computed":
			var guarded_prop_doc := PropellerDocument.from_catalog_prop(propeller)
			var chord_at_tip_mm := guarded_prop_doc.chord_at(1.0)
			guard_closure = PropGuard.tip_loss_closure(guard_specs, chord_at_tip_mm)
	# _forward_ratios cleared here even when nothing changed, so the check does not have to know
	# what changed — a stale surface is what §4.0's third bullet warns against.
	_forward_ratios = null

	# --- Thrust coefficient, fit from the manufacturer table, then moved to this prop ---
	# physics.md §4 is explicit that C_T must be fit from published thrust tables rather
	# than guessed. A motor's headline thrust figure is only meaningful together with the
	# prop and pack it was measured on, so motors.json names both. Fit k_t for that exact
	# pairing, then rescale it to whatever prop is actually fitted.
	#
	# THE MOVE IS NOW THE BEMT GEOMETRY RATIO (§0, P5): blade count and twist enter the
	# integral where they act, at the RPM the motor's k_t was fitted at, instead of the old
	# D⁴·blades^0.8·pitch^0.5 rules of thumb. When the fitted prop IS the motor's test prop
	# (the reference build), the ratio short-circuits to 1.0 bit-exact — the anchor the
	# 496 g / 11.69:1 / 29.6% oracles hang on.
	var test_prop: Dictionary = catalog.get_part(motor["thrust_test"]["prop_id"])
	var test_voltage: float = float(motor["thrust_test"]["voltage_v"])
	var test_max_rpm: float = float(motor["specs"]["kv"]) * test_voltage
	var k_t_at_test_prop := PropellerModel.fit_k_t(float(motor["specs"]["max_thrust_g"]), test_max_rpm)

	var test_doc := PropellerDocument.from_catalog_prop(test_prop)
	var prop_doc := PropellerDocument.from_catalog_prop(propeller)
	k_t = BemtModel.scale_k_t_to_prop(
		k_t_at_test_prop,
		test_doc.diameter_mm * 0.001, test_doc.pitch_mm * 0.001, float(test_doc.blades), test_doc.chord,
		prop_doc.diameter_mm * 0.001, prop_doc.pitch_mm * 0.001, float(prop_doc.blades), prop_doc.chord,
		test_max_rpm)
	# --- And then moved to the AIR THIS BUILD IS FLOWN IN ---
	# T = C_T * rho * n^2 * D^4, so k_t is linear in density. Without this line the whole air slice
	# is decoration: thrust_n is k_t * omega^2 with no rho in it, and fit_k_t has none either, so
	# density would reach flight time and top speed through drag and induced power and leave
	# thrust-to-weight at 11.69:1 in Leh. Lothal would ask a builder where they fly, appear to
	# account for it, and still tell a marginal cinelifter it was fine.
	#
	# THE DENOMINATOR IS AN ASSUMPTION, and it is stated rather than hidden: that the manufacturer's
	# thrust table was measured in standard air. It almost certainly was not — manufacturers publish
	# thrust and current at a stand and state no conditions, not the elevation, not the temperature,
	# not the day. A table measured at 300 m on a warm afternoon puts perhaps 5% into k_t.
	#
	# That is real, and it is worth sizing against the error it sits inside rather than worrying at
	# on its own: labs-and-sim.md §1 records that fifteen manufacturers' tables disagree with each
	# other by 1.79x on one shared prop. A 5% uncertainty about the air a published figure was
	# measured in is roughly a twentieth of the spread the catalog already concedes. It does not
	# make this ratio wrong; it makes it a correction applied to a number that was never precise.
	#
	# The alternative — leaving k_t alone and letting only power respond to air — is worse, and not
	# by a little. It would be a SILENT assumption that thrust does not depend on air density, which
	# is false as physics rather than merely uncertain as data.
	k_t *= air.kgm3() / AirDensity.standard_kgm3()

	# The guard's static thrust boost, from §4.0's "the closure reaches both". `k_t` reaches
	# `PropellerModel.thrust_n` at hover — the panel's own hover-throttle bisection — and the
	# forward-flight tick reads through `forward_ratios()`, whose closure-aware surface takes
	# the same closure into both numerator and denominator so the ratio is nearly closure-
	# invariant. Which means: without this line, a fitted duct would raise the flight-tick
	# thrust and NOT the hover-throttle the panel quotes, and a builder would see two answers.
	#
	# Solved once when the guard is fitted, cached on the build so hover_throttle's ~60 bisect
	# iterations do not each pay a fresh solve. Follows the k_t scaling for air density above
	# for the same reason: the panel quotes k_t already scaled by the field, and the closure
	# is another multiplicative correction to the same number.
	#
	# The torque half of the same pair is applied to k_q below rather than here, because k_q is
	# fit FROM k_t and the closure moves the two in opposite directions — see this file's
	# `_static_closure_torque_factor` for the measured numbers.
	var k_t_open_rotor := k_t
	if guard_closure > 0.0:
		var prop_g := prop_geometry()
		var closure_factors := BemtModel.static_closure_factors(
			prop_g.diameter_m, prop_g.pitch_m, prop_g.blades, blade_chord(), guard_closure)
		_static_closure_factor = closure_factors[0]
		_static_closure_torque_factor = closure_factors[1]
		k_t *= _static_closure_factor

	# k_q is fit from the OPEN-ROTOR k_t and then carries the closure's own torque factor. Both
	# steps are needed: fitting from the closed k_t would double the closure into torque with
	# the wrong sign, and skipping the torque factor would leave a duct's current draw — the
	# number a duct is actually fitted for — untouched by the duct.
	k_q = PropellerModel.fit_k_q(k_t_open_rotor, _prop_geometry(propeller).diameter_m) \
		* _static_closure_torque_factor

	var k_q_at_test_prop := PropellerModel.fit_k_q(k_t_at_test_prop, _prop_geometry(test_prop).diameter_m)
	effective_max_amps = float(motor["specs"]["max_amps"]) * (k_q / k_q_at_test_prop)

	var drag_area_m2: float = REFERENCE_DRAG_AREA_M2 * pow(arm_m / REFERENCE_ARM_M, 2.0)
	drag_coefficient = 0.5 * air.kgm3() * drag_area_m2

	mass_properties = MassProperties.compute(mass_parts())


## The FITTED prop's geometry in SI. Public because anything assembling a powertrain needs
## the blade count and radius the audio and the rotor mesh are driven from, and recovering
## them from the raw catalog dictionary at each call site would be a second copy of the
## inch-to-metre conversion.
func prop_geometry() -> Dictionary:
	return _prop_geometry(propeller)


## The fitted propeller's planform, flat as `PropellerDocument.chord` stores it: r/R and chord in
## millimetres, alternating. The blade's own geometry, which §0's rule says must be the SAME
## geometry the mesh draws and the integral reads — this is the accessor that carries it out of the
## document and into the powertrain.
func blade_chord() -> PackedFloat64Array:
	return PropellerDocument.from_catalog_prop(propeller).chord


## The forward-flight ratio surface for the fitted prop (P6's closure). Cached on the build,
## because `BemtRatios.for_prop` costs ~150 ms of BEMT solves the first time a given planform is
## asked for and every panel refresh reconstructs a Build.
##
## This is the ONE place forward flight is decided for this aircraft. Both the flight tick (through
## `Powertrain`) and the panel figures below read the same surface, so the current the pack sees
## and the current the stats page quotes cannot disagree about what the rotor is doing — the same
## property `current_in_flight_at_rpm`'s "one factor rather than two" comment defends.
func forward_ratios() -> BemtRatios:
	if _forward_ratios == null:
		var geometry := prop_geometry()
		# `for_prop_with_guard` at closure = 0.0 reaches the SAME cache entry `for_prop` used
		# to, since the Rust key bit-encodes 0.0 verbatim — so a build with no guard fitted
		# pays no extra solve. A fitted guard keys a different table, which is the point of
		# threading the closure at all: two builds that differ only in their guard get two
		# different surfaces, one solve each, cached forever after.
		_forward_ratios = BemtRatios.for_prop_with_guard(
			geometry.diameter_m, geometry.pitch_m, geometry.blades, blade_chord(),
			guard_closure)
	return _forward_ratios


## Per-prop geometry in SI, since the catalog quotes props in inches like the real world.
func _prop_geometry(prop: Dictionary) -> Dictionary:
	return {
		"diameter_m": float(prop["specs"]["diameter_inches"]) * INCH_M,
		"pitch_m": float(prop["specs"]["pitch_inches"]) * INCH_M,
		"blades": float(prop["specs"]["blades"]),
	}


func mass_parts() -> Array:
	var parts: Array = []

	# Motor + prop are lumped at the arm tip. Their own local tensors are a rounding error
	# next to the m*d^2 parallel-axis term at a 110 mm arm (roughly 200x smaller), but they
	# cost nothing to carry and stay correct if someone authors a very short-armed frame.
	var motor_prop_mass_kg := (float(motor["mass_g"]) + float(propeller["mass_g"])) / 1000.0
	var motor_inertia := InertiaPrimitives.cylinder_y_axis(
		motor_prop_mass_kg,
		float(motor["specs"]["stator_diameter_mm"]) / 2000.0,
		float(motor["specs"]["stator_height_mm"]) / 1000.0
	)
	for name in MotorLayout.MOTOR_NAMES:
		parts.append(PartMass.new(motor_prop_mass_kg, MotorLayout.motor_position(name, arm_m),
			motor_inertia, "Motor + prop %s" % name))

	# THE FRAME STAYS ONE LUMPED BOX AT THE ORIGIN, and that is a decision rather than the
	# leftover it looks like next to the four entries below that just gained positions.
	#
	# A frame's mass is genuinely distributed — arms, plates and standoffs are in different places —
	# and modelling that is more honest than this. But this box was AUTHORED as a stand-in for the
	# distribution of the whole airframe, arms included: FRAME_PLATE_TO_ARM_RATIO makes it 150 mm
	# across on a 110 mm arm, wider than the arms reach, precisely so its m*r^2 stands for carbon
	# that is out at the tips (frame_model.gd says the same thing from the other side, explaining
	# why the DRAWN centre plate must not reuse this ratio). Splitting it into plates plus four arms
	# therefore means shrinking this box to the real 60 mm plate at the same time — a second and
	# larger inertia re-baseline, landing in the same commit as the one this slice is actually
	# about, with no way to attribute the two apart afterwards.
	#
	# It also costs nothing HERE: the frame is symmetric about the origin either way, so it
	# contributes exactly zero to the centre of mass, which is what this slice moves. What it would
	# sharpen is the arm-length exponent in the roll-inertia comparison — which is a question about
	# arms, and belongs in the slice whose subject is arms.
	var frame_mass_kg := float(frame["mass_g"]) / 1000.0
	var plate := arm_m * FRAME_PLATE_TO_ARM_RATIO
	var frame_size := Vector3(plate, FRAME_PLATE_THICKNESS_M, plate)
	parts.append(PartMass.new(frame_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(frame_mass_kg, frame_size), "Frame"))

	# The pack, where the builder actually strapped it. This is the entry the whole slice is for:
	# it is the one mass the user can move, so it is the one that proves the offset reached the
	# physics rather than only the picture.
	#
	# Nothing here decides where that is. MountLayout resolves the seat from the frame's own specs
	# and the standoffs currently fitted, and seats the pack on it — the SAME call AirframeModel
	# makes to draw it, which is what makes labs-and-sim.md §2.2's "the fit check and the picture
	# are the same geometry" true of mass and not just of clearance.
	var battery_mass_kg := float(battery["mass_g"]) / 1000.0
	var battery_size := battery_size_m()
	var battery_position: Vector3 = battery_seat()["position"]
	parts.append(PartMass.new(battery_mass_kg, battery_position,
		InertiaPrimitives.box(battery_mass_kg, battery_size), "Pack"))

	# The electronics: the two stack boards, at their carved shares. They summed with the old lump
	# to ELECTRONICS_BUDGET_G exactly, and PW2 ended that — the harness below is weighed rather than
	# left over, so this aircraft's electronics no longer add to 55 g. The stack is separate from
	# the lump for the reason it always was: it is a real object with a real footprint, and its
	# 36.5 mm board has a different tensor from the 30 mm cube the remainder stands on.
	#
	# BOTH BOARDS NOW SIT WHERE THEY ARE DRAWN: on the standoff stack's seat — the bottom plate's
	# upper face — each raised by its own offset within the stack, ESC below and FC above it. Both
	# terms come from the parts: the seat is MountLayout's, and the two heights are StackMesh's own,
	# the same numbers it draws the boards at. So the standoff tweak now moves the stack's mass
	# along with its picture (labs-and-sim.md §2.5), and neither height is written twice.
	#
	# This is the term assembly_tweaks.gd said the mass model would grow one day: "when the mass
	# model grows a real centre-of-gravity term, these values are already the single source for it."
	# A consumer was added; nothing was re-decided.
	var stack_seat := MountLayout.by_id(mount_points(), "stack")
	var stack_position := stack_seat.position if stack_seat != null else Vector3.ZERO

	# The FC at its OWN catalog mass, on its own footprint — the line that makes fitting a
	# bigger board cost something. The budget below gives up FC_BUDGET_MASS_G, and whatever
	# this board actually weighs is what the aircraft carries.
	var fc_mass_kg := fc_mass_g() / 1000.0
	parts.append(PartMass.new(fc_mass_kg,
		stack_position + Vector3(0.0, StackMesh.fc_centre_height_m(), 0.0),
		InertiaPrimitives.box(fc_mass_kg, StackMesh.size_m(fc_mount_pattern())), "Flight controller"))

	# The ESC at its OWN catalog mass, on its own footprint. This is the line that makes fitting a
	# bigger board cost something: the budget below gave up ESC_BUDGET_MASS_G, and whatever this
	# board actually weighs is what the aircraft carries.
	var esc_mass_kg := esc_mass_g() / 1000.0
	parts.append(PartMass.new(esc_mass_kg,
		stack_position + Vector3(0.0, StackMesh.esc_centre_height_m(), 0.0),
		InertiaPrimitives.box(esc_mass_kg, StackMesh.size_m(esc_mount_pattern())), "ESC"))

	# The optional components, each at its OWN catalog mass, in its OWN bay, and each omittable:
	# the four LTHL-11 took out of the lump (camera, VTX, antenna, receiver) and the two C2 ADDED
	# beside it (GPS, buzzer). The loop does not know which kind it is holding, and it should not —
	# the difference is in the budget's bookkeeping, not in how a part is weighed or placed.
	#
	# THIS IS THE LOOP THAT MOVES THE CENTRE OF MASS, and it is the reason the previous comment
	# here refused to do it. What changed is not the appetite for precision but where the positions
	# come from: every one of them is MountLayout's, resolved through the same seated_centre_m()
	# call the pack goes through, from the frame's own plate geometry. Nothing below carries an
	# offset of its own, and COMPONENT_MOUNTS is the whole of what this file knows about where a
	# camera lives — the name of a place, not a coordinate.
	#
	# A component not fitted contributes nothing and costs nothing. That is the entire point at the
	# small end: a whoop's AIO board has the camera and the receiver on it and carries no separate
	# transmitter, so the aircraft must be lighter by their whole share of the budget rather than
	# quietly keeping a default.
	var mounts := mount_points()
	for category in OPTIONAL_COMPONENTS:
		if not components.has(category):
			continue
		var component: Dictionary = components[category]
		var component_mass_kg := float(component.get("mass_g", 0.0)) / 1000.0
		var component_size := component_size_of(component)
		var bay := MountLayout.by_id(mounts, String(COMPONENT_MOUNTS[category]))
		# The mast, and it is the part's own published dimension rather than an offset this file
		# carries — the same kind of read as component_size_of() on the line above. A part with no
		# mast rises zero, which is every component in the app but a masted GPS.
		parts.append(PartMass.new(component_mass_kg,
			MountLayout.seated_centre_m(bay, component_size, 0.0, rise_m_for(component)),
			InertiaPrimitives.box(component_mass_kg, component_size),
			str(component.get("name", category))))

	# THE HARNESS, and this is the block PW2 exists for. It was ONE 14 g lump at the origin — the
	# budget's remainder, standing for wiring, connector, capacitor, solder, heat-shrink and straps,
	# put at the origin because a harness is everywhere on the aircraft by definition. That was
	# honest about the mass and silent about the distribution, and the distribution is the half that
	# is actually knowable: the connector is at the pack, the trunk runs down the spine, four leads
	# run out to the motors, and the cap stands on the ESC.
	#
	# So it is now five entries and a remainder, each weighed off `Harness` (which is where the
	# gauges, lengths and part ids live) and each placed by the same geometry everything else on
	# this aircraft is placed by. What is left at the origin is straps, tape, solder and shrink,
	# which genuinely is everywhere.
	#
	# ---------------------------------------------------------------------------
	# THE TRAP, AND THIS CODEBASE HAS PAID FOR IT ONCE
	# ---------------------------------------------------------------------------
	#
	# Every entry below goes in as a `PartMass` at a position with a LOCAL DIAGONAL — the part's own
	# tensor about its own centre — so that `MassProperties.compute`'s parallel-axis step supplies
	# the m·d² term EXACTLY ONCE. Handing a local diagonal a term that already contains the offset
	# (a pre-shifted scalar, the way P10a's guard row nearly did) counts it twice, and the four
	# motor leads are precisely the geometry where that would happen and not be noticed.
	#
	# And the sharper half of P10b's review finding applies unchanged: ROLL IS I_ZZ. A double-count
	# wired into the X entry of a local diagonal lands in PITCH, and a roll check looks straight
	# past it. That is why tests/test_harness.gd asserts the zero-offset property and the tensor
	# term as a PAIR — neither is sufficient alone, and the pair is what makes the mutation visible
	# whichever axis it is misfiled under.
	var harness_connector_kg := harness.connector_mass_g(self) / 1000.0
	var harness_main_kg := harness.main_lead_mass_g(self) / 1000.0
	var harness_motor_lead_kg := harness.motor_lead_mass_g(self) / 1000.0
	var harness_cap_kg := harness.capacitor_mass_g(self) / 1000.0

	# The connector, at the pack's own position. A plug is bolted to nothing and hangs off the end
	# of the lead, so the pack is the only place on the aircraft it is definitely near. Point mass:
	# an XT60 pair is 16 mm long and its own tensor is four orders under the parallel-axis term.
	if harness_connector_kg > 0.0:
		parts.append(PartMass.new(harness_connector_kg, battery_position, Vector3.ZERO,
			"Connector"))

	# The main lead, as a ROD and not a point. It is dressed ALONG THE FRAME between the ESC's pads
	# and the connector at the pack: mid-way between the two in plan, and at the STACK'S OWN HEIGHT
	# rather than anywhere between the plates and the pack.
	#
	# THE HEIGHT IS THE PART THAT WAS GOT WRONG TWICE BEFORE IT WAS GOT RIGHT, so it is written down.
	# Running the rod out by half its own length towards the pack pointed it nearly straight up — a
	# lead is 120 mm and the pack sits about 20 mm above the plate — and put eight grams of copper
	# sixty millimetres in the air. Putting its centroid at the geometric midpoint of the stack and
	# the pack was better and still wrong in the same direction: it lifted the modelled centre of
	# mass and pushed the airframe's perpendicular-axis relation (I_yaw ≈ I_roll + I_pitch, which
	# tests/test_frame_bench.gd holds to the parts' own thickness) from 11.5% out to 12.0%.
	#
	# A battery lead does not fly through the air to meet the pack. It comes off the pads, lies on
	# the plate, and the slack is coiled there — so its mass is in the PLANE OF THE FRAME, which is
	# what the model now says. Length is mass and slack, not reach.
	#
	# Three properties this project asserts elsewhere survive because of that, and would each have
	# broken silently otherwise: a build with no components fitted is still FORE/AFT SYMMETRIC,
	# sliding the pack does not change how HIGH the centre of mass sits, and sliding it fore and aft
	# still leaves ROLL inertia alone.
	var main_length_m := float(harness.value(Harness.MAIN_LEAD_LENGTH_MM, self)) / 1000.0
	var run := battery_position - stack_position
	var main_position := Vector3(
		stack_position.x + run.x * 0.5, stack_position.y, stack_position.z + run.z * 0.5)
	# The rod lies along the spine: a lead is dressed fore and aft, never across the airframe.
	if harness_main_kg > 0.0:
		parts.append(PartMass.new(harness_main_kg, main_position,
			Harness.rod_diag_kg_m2(harness_main_kg, main_length_m, Vector3(0.0, 0.0, 1.0)),
			"Main lead"))

	# FOUR MOTOR LEADS, one at each motor's plan position. This is the previously absent
	# contribution to roll and pitch inertia the re-baseline was expected to surface: four masses at
	# the arm ends, each carrying its own rod tensor about its own centre and NOTHING ELSE. The R²
	# bite is `MassProperties`'s to add.
	#
	# `motor_lead_mass_g` is the wire the HARNESS adds, not the whole run — see
	# `Harness.MOTOR_SUPPLIED_LEAD_MM` for why, and it is the same double-count argument that
	# governs `pigtail_mass_g`. Zero on a build whose arms are shorter than a motor's own leads,
	# which appends nothing rather than four zero-mass entries.
	if harness_motor_lead_kg > 0.0:
		var motor_lead_length_m := float(
			harness.value(Harness.MOTOR_LEAD_LENGTH_MM, self)) / 1000.0
		for motor_name in MotorLayout.MOTOR_NAMES:
			var lead_position := MotorLayout.motor_position(motor_name, arm_m)
			parts.append(PartMass.new(harness_motor_lead_kg, lead_position,
				Harness.rod_diag_kg_m2(harness_motor_lead_kg, motor_lead_length_m,
					lead_position),
				"Motor lead %s" % motor_name))

	# The capacitor, standing on the ESC's pads — the same seat and the same height StackMesh draws
	# the board at, so the can is where the picture puts it. A real object with published body
	# dimensions, so it gets a real box rather than a point.
	if harness_cap_kg > 0.0:
		var cap_size := harness.capacitor_size_m(self)
		parts.append(PartMass.new(harness_cap_kg,
			stack_position + Vector3(0.0, StackMesh.esc_centre_height_m(), 0.0),
			InertiaPrimitives.box(harness_cap_kg, cap_size), "Capacitor"))

	# What is genuinely everywhere: straps, tape, solder and heat-shrink, at the origin. The
	# honest remainder rather than the entry that got forgotten, and — unlike the 14 g it replaces —
	# AUTHORED at what those things weigh instead of being whatever a budget had left over.
	var remainder_kg := Harness.REMAINDER_MASS_G / 1000.0
	parts.append(PartMass.new(remainder_kg, Vector3.ZERO,
		InertiaPrimitives.box(remainder_kg, ELECTRONICS_SIZE_M), "Harness remainder"))

	# Prop guards, one ring at each motor — the P10a `as_part_mass` finally has a caller
	# (§3.4 shipped in P10b). PartMass carries the guard's mass at the motor's plan position
	# with `Vector3.ZERO` local diagonal, so `AirframeProperties.compute`'s parallel-axis shift
	# adds the R² roll-inertia bite exactly ONCE — the double-count trap this file's guard row
	# would fall into if anyone handed the local diagonal the scalar
	# `roll_inertia_contribution_kg_m2` instead. The `null` return from `as_part_mass` on an
	# unreadable guard is what stops a class-typical default masquerading as a real fit, so
	# nothing is appended when the guard's spec is one `compute()` refuses.
	#
	# One guard applied to every motor (v1: whole-build guard_id in from_ids). A per-motor
	# per-guard authoring is future work; the physics already accepts a heterogeneous fit
	# because `as_part_mass` takes the motor position as a separate arg.
	if not guard.is_empty():
		var guard_specs: Dictionary = guard.get("specs", {})
		for motor_name in MotorLayout.MOTOR_NAMES:
			var pm := PropGuard.as_part_mass(guard_specs,
				MotorLayout.motor_position(motor_name, arm_m))
			if pm != null:
				parts.append(pm)

	# Printed parts the builder FITTED in this drone's Printed room (printed-room PR1). Added on top,
	# not carved from a budget — nothing ever budgeted for them — and absent unless fitted, which is
	# what keeps the reference build at 507.48 g. The seats are ArmGuard's, the same ones ArmGuardMesh
	# is drawn at.
	parts.append_array(ArmGuard.part_masses(self, printing))
	# PR10: the printed GPS mast, on the same terms — only when fitted, over the GPS bay.
	parts.append_array(GpsMast.part_masses(self, printing))
	# PR11: the printed battery pad, only when fitted, beneath the pack's own seat.
	parts.append_array(BatteryPad.part_masses(self, printing))

	return parts


## A component's box in BODY axes: width across X, height up Y, length along Z — the same
## reordering Build.battery_size_of does, and for the same reason, because these category files
## publish dimensions in the part's own frame the way batteries.json does.
##
## The fallback is a 10 mm cube, for an entry whose contributor has not published dimensions yet.
## It is wrong in a small way rather than absent in a large one: an inertia box is linear in mass
## and quadratic in size, so a 15 g antenna with no dimensions is placed correctly and spun
## slightly wrong, where a zero size would make it a point mass and a mass-scaled guess would be a
## dimension this project computed instead of read. Every shipped entry carries real dimensions.
static func component_size_of(part: Dictionary) -> Vector3:
	var specs: Dictionary = part.get("specs", {})
	var length: float = float(specs.get("length_mm", 0.0))
	var width: float = float(specs.get("width_mm", 0.0))
	var height: float = float(specs.get("height_mm", 0.0))
	if length > 0.0 and width > 0.0 and height > 0.0:
		return Vector3(width, height, length) / 1000.0
	return Vector3.ONE * 0.010


## The camera's uptilt as a rotation about the camera's own centre: a positive rotation about +X,
## so forward (-Z) goes to (0, sin θ, -cos θ) and the lens looks above the horizon (video-room
## design §2). THE ONE PLACE THIS ROTATION IS WRITTEN — ComponentMesh tips the drawn camera with it
## and VideoPlausibility measures the published box with it, so the picture and the clearance
## warning cannot come to disagree about which way up is.
static func camera_tilt_transform(tilt_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt_deg)), Vector3.ZERO)


## How tall a camera stands when tipped up by `tilt_deg`, in metres: the vertical extent of its
## PUBLISHED box under `camera_tilt_transform`, which works out to l·sin θ + h·cos θ.
##
## Not written as that formula, and not read off the drawn mesh. Godot's AABB transform does the
## trigonometry, so there is no second copy of the rotation to drift; and the published box rather
## than the drawing, because the published box is what a builder can check against the part in
## their hand. The drawn silhouette is a little shorter — the lens barrel is narrower than the body
## — so a warning quoting this figure errs towards speaking, by 2.7 mm on a micro camera at 40°.
static func camera_standing_height_m(part: Dictionary, tilt_deg: float) -> float:
	var size := component_size_of(part)
	return (camera_tilt_transform(tilt_deg) * AABB(-size * 0.5, size)).size.y


## What this build's electronics actually weigh: the two stack boards at their own masses, every
## optional component that is fitted at its own mass, and the wiring remainder.
##
## What this build's harness weighs, all of it: connector, main lead, four motor leads, capacitor
## and the straps-and-tape remainder. THE SAME CLAIM `mass_parts()` MAKES, computed the same way —
## `Harness.total_mass_g` is the one place the five terms are added up, so an entry appended above
## and not counted here (or the reverse) is a discrepancy a check can see rather than a number two
## functions quietly disagree about.
func harness_mass_g() -> float:
	return harness.total_mass_g(self)


## NO LONGER PINNED TO THE BUDGET, and that is PW2's doing rather than a drift. It used to come out
## at exactly ELECTRONICS_BUDGET_G with the default part in every category, because the harness term
## in it was the budget's own remainder; the harness is weighed now, so this is the sum of what the
## build actually carries and the 55 g is a figure it happens to be near. It is still LOWER when
## something is omitted and HIGHER when a heavier-than-budget part is fitted, which was always the
## point — this is the number that replaced a flat 55 g in the one place that was quoting it at the
## builder (FramePlausibility._electronics_lump).
##
## It counts CARVED AND ADDED components alike, because it is the mass of the electronics this
## aircraft carries and a GPS is electronics. What tells the two apart is the identity test_esc.gd
## asserts — `electronics = carved shares + harness + added` — where the added term is what makes
## the two ways of accounting for the aircraft agree on a build that fits a GPS.
func electronics_mass_g() -> float:
	var total := fc_mass_g() + esc_mass_g() + harness_mass_g()
	for category in OPTIONAL_COMPONENTS:
		if components.has(category):
			total += float(components[category].get("mass_g", 0.0))
	return total


## The fitted pack as a box in BODY axes: width across X, height up Y, length along Z — because
## nose is -Z (physics.md §1) and a pack is strapped down fore-and-aft. The catalog publishes it in
## its own frame (length, width, height), so the reordering happens here, once.
##
## This is the ONE answer to "how big is the pack". BatteryMesh draws these same three numbers, and
## the overhang measured on screen is measured off that drawing. The project already learned what
## two answers to one object's size costs — main.tscn hardcoding 0.0778 while the physics read
## MotorLayout — and the pack was the last component still carrying a private estimate.
func battery_size_m() -> Vector3:
	return battery_size_of(battery)


## How wide the assembled aircraft is, tip to tip across the propeller discs.
##
## Two motors face each other across the airframe at `arm_m` from the centre, and each carries a
## prop reaching another radius past its own hub — so the widest thing that has to fit through a
## gate is 2 * (arm + prop radius). Derived rather than measured off AirframeModel, because this is
## the same arithmetic LabScreen._camera_distance_m() uses to frame the catalog's biggest build,
## and it needs no meshes to exist: a course warning is asked at a point where nothing has been
## drawn yet.
##
## Used by CourseWarnings to say whether a ring is smaller than the aircraft that has to fly
## through it, which is a comparison of two known dimensions and therefore needs no threshold.
func airframe_span_m() -> float:
	return (arm_m + float(prop_geometry()["diameter_m"]) * 0.5) * 2.0


## Static so anything holding a catalog entry can ask its size without assembling a Build. The
## fallback is for an entry whose contributor has not published dimensions yet: the old estimate
## from mass at LiPo pack density, which is wrong in a small way rather than absent in a large one.
## Every entry in data/parts/batteries.json carries real dimensions, so nothing in the shipped
## catalog reaches it — it exists so a half-finished contribution renders and flies instead of
## collapsing to a point mass.
static func battery_size_of(pack: Dictionary) -> Vector3:
	var specs: Dictionary = pack.get("specs", {})
	var mass_kg: float = float(pack.get("mass_g", 0.0)) / 1000.0
	var length: float = float(specs.get("length_mm", 0.0))
	var width: float = float(specs.get("width_mm", 0.0))
	var height: float = float(specs.get("height_mm", 0.0))
	if length > 0.0 and width > 0.0 and height > 0.0:
		return Vector3(width, height, length) / 1000.0
	# A 70 x 35 x 30 mm pack at the reference build's mass, scaled by the cube root of this one's —
	# stated in BODY axes like the branch above, so an undimensioned entry is at least mounted the
	# right way round. (The estimate it replaces returned this in the catalog's own order, which
	# laid the pack ACROSS the airframe; no shipped entry reaches this line, so nothing moved.)
	return Vector3(0.035, 0.030, 0.070) * pow(maxf(mass_kg, 0.001) / 0.185, 1.0 / 3.0)


## How much of the RPM ceiling this motor can reach before its current limit stops it,
## given the prop fitted. Current tracks shaft torque, which climbs as D^5, so an
## oversized prop is current-limited long before it is voltage-limited. Exactly 1.0 when
## the fitted prop is the one the motor's amp rating was measured with.
## The throttle ceiling the aircraft is ACTUALLY flown at: whichever limit binds first. Everything
## dynamic goes through here — the motor model's ceiling, peak thrust, hover, top speed — so a
## build cannot be commanded past what its weakest link will pass.
##
## Deliberately NOT what max_total_thrust_n() is quoted at; see that function.
func max_throttle_fraction() -> float:
	return minf(motor_throttle_limit(), minf(pack_throttle_limit(), esc_throttle_limit()))


## How much of the RPM ceiling the MOTORS can reach before their own current limit stops them,
## given the prop fitted. Exactly 1.0 when the fitted prop is the one the motor's amp rating was
## measured with. This is the limit the project had before packs had a rating.
func motor_throttle_limit() -> float:
	return throttle_limit_for(4.0 * float(motor["specs"]["max_amps"]))


## The pack's maximum continuous discharge: capacity in amp-hours times its C-rating. The number
## on the wrapper, meaning what the wrapper means by it.
##
## This is why c_rating is a `specs` field rather than browsing metadata. Left in `catalog` and
## read by nothing, a 300 mAh 30C whoop pack would deliver 100 A on demand, and pack choice would
## be a question of capacity and mass alone — which is exactly the half of the lesson a battery
## bench exists to teach the other half of.
func pack_max_amps() -> float:
	return float(battery["specs"]["mah"]) / 1000.0 * float(battery["specs"].get("c_rating", 0.0))


func pack_throttle_limit() -> float:
	return throttle_limit_for(pack_max_amps())


## The throttle at which the four motors together draw `total_amps`. Current tracks shaft torque
## and torque goes as RPM^2, so the current at a throttle is quadratic in it — which is why this
## is a square root and not a ratio, and why an oversized prop or an undersized pack bites much
## harder than the headline numbers suggest.
##
## One expression, used by both limits, so the pack limit cannot end up meaning something subtly
## different from the motor limit that has been in the project since day one.
func throttle_limit_for(total_amps: float) -> float:
	# The arithmetic lives in Rust (rust/src/fitting.rs) — the current-limit expression, one
	# copy in the codebase, and the part of the fitting pipeline the compiled core exists for.
	return Fitting.throttle_limit_for(total_amps, 4.0 * effective_max_amps)


## WHICH component is holding this build back, by name, with the ceiling it imposes.
##
## The point of modelling two limits is not that a build is limited — it is that a builder can see
## which part to spend money on. "You are capped at 62% throttle" sends nobody anywhere; "your
## pack is capped at 62% and your motors would take 100%" sells a battery.
##
## Ties go to the motors, which is the pre-existing behaviour and the right default: an unrated
## pack (a contribution missing c_rating) yields a zero limit that throttle_limit_for reads as
## "no limit stated", so it must not be reported as the binding one.
func limiting_component() -> Dictionary:
	# Ordered so that ties go to the motors, then the pack, then the ESC. That is the pre-existing
	# behaviour extended rather than reshuffled, and it matters for an unrated part: a contribution
	# missing continuous_a yields a zero limit that throttle_limit_for() reads as "no limit
	# stated", and it must not then be reported as the thing holding the build back.
	var candidates := [
		{
			"name": "motors",
			"label": str(motor["name"]),
			"amps": 4.0 * float(motor["specs"]["max_amps"]),
			"throttle": motor_throttle_limit(),
		},
		{
			"name": "battery",
			"label": str(battery["name"]),
			"amps": pack_max_amps(),
			"throttle": pack_throttle_limit(),
		},
		{
			"name": "esc",
			"label": str(esc.get("name", "ESC")),
			"amps": esc_max_amps(),
			"throttle": esc_throttle_limit(),
		},
	]
	# The tie-break decision lives in Rust (rust/src/fitting.rs): strict minimum wins and ties
	# keep the earlier candidate, so an unrated part's zero limit is never reported as binding.
	return candidates[Fitting.limiting_index(
		candidates[0]["throttle"], candidates[1]["throttle"], candidates[2]["throttle"])]

func motor_model() -> MotorModel:
	# P7 (propulsion.md §3.4): tau is per-motor now, computed from J_rotor + J_blade and
	# the motor/prop torque slopes at the linearisation point. No caller path may hand out a
	# MotorModel without this — the pre-P7 shared 0.03 s constant is gone; MotorModel's own
	# fallback matches it identically so a probe that skips the derivation reproduces the
	# old numbers rather than a silent zero.
	return MotorModel.create_with_tau(float(motor["specs"]["kv"]), max_throttle_fraction(),
		_tau_s())


## The τ this build hands to MotorModel. Derived at the hover operating point when the build
## can hover — the case throttle-response feel is written about — and at rated_rpm otherwise,
## so an unflyable configuration still gets a meaningful spin-up rather than a zero. Public
## so the panel and the ESC bench can render every intermediate through
## `MotorSpinUp.compute()` without recomputing k_q or rebuilding the prop document.
func spin_up() -> Dictionary:
	var prop_doc := PropellerDocument.from_catalog_prop(propeller)
	var test_prop: Dictionary = catalog.get_part(motor["thrust_test"]["prop_id"])
	var k_t_at_test_prop := PropellerModel.fit_k_t(float(motor["specs"]["max_thrust_g"]),
		float(motor["specs"]["kv"]) * float(motor["thrust_test"]["voltage_v"]))
	var k_q_at_test_prop := PropellerModel.fit_k_q(k_t_at_test_prop,
		_prop_geometry(test_prop).diameter_m)
	var omega_ref: float = _omega_hover_rad_s()
	return MotorSpinUp.compute(motor, prop_doc, _spin_up_materials(), k_q, k_q_at_test_prop,
		omega_ref)


func _tau_s() -> float:
	var s := spin_up()
	var value: float = float(s.get("tau_s", 0.0))
	return value if value > 0.0 else MotorSpinUp.FALLBACK_TAU_S


func _omega_hover_rad_s() -> float:
	return PropellerModel.rpm_to_rad_s(operating_rpm())


## The RPM this aircraft is judged at: hover if it hovers, rated if it does not.
##
## rated_rpm() is the RPM at max throttle at the test voltage. Multiply by hover_throttle when the
## build actually hovers so the linearisation lands where a stick input actually operates; fall
## back to rated_rpm otherwise, since 0.5 · rated is the wrong number when the aircraft cannot
## hover at all.
##
## Public and named because P10e's thrust-distribution overlay needs the SAME operating point the
## spin-up linearisation uses. Two definitions of "the RPM this drone sits at" would let the
## overlay draw a blade loading the τ nobody flies, and the disagreement would be invisible —
## both numbers are plausible and neither is labelled.
func operating_rpm() -> float:
	var rated := rated_rpm()
	if not can_hover():
		return rated
	return rated * hover_throttle()


## The static thrust the fitted blade makes at each annulus of the solve, at `operating_rpm()`.
##
## `[r_m, dT_N]` interleaved, straight out of `BemtModel.thrust_distribution` — which taps the
## per-annulus addends of the very sum `solve()` returns. There is deliberately NO arithmetic here
## beyond assembling the call: the moment this method starts adjusting what Rust handed back, the
## overlay is drawing something the aircraft does not fly.
##
## Empty for a rotor the solve declines (P10e §3): a refusal and a blade that makes no thrust are
## different answers and must not render the same.
func thrust_distribution() -> PackedFloat64Array:
	var geometry := prop_geometry()
	return BemtModel.thrust_distribution(
		air.kgm3(), geometry.diameter_m, geometry.pitch_m, geometry.blades,
		operating_rpm(), blade_chord(), guard_closure)


## The per-rev orders the airframe is excited at, name → multiples of one revolution.
##
## Three, and they are three different physical mechanisms rather than three harmonics of one:
## an out-of-balance blade forces once per revolution, the blades force once each per revolution,
## and the motor's electrical drive forces once per POLE PAIR per revolution. P10e's Campbell
## overlay turns each into a line at `order · rpm / 60`.
##
## Assembled here rather than in the overlay for the reason `thrust_distribution` is: the
## multipliers are properties of the aircraft, and an overlay that recomputed one of them from
## `specs.poles` would be a second definition of a number that already has one — the P10d defect
## in a new file. `pole_pairs()` is that one definition, halving included.
##
## BLADE PASSING IS `blades × rpm/60` ONLY FOR EVENLY SPACED BLADES. That is every propeller
## Lothal can express today — blade count is a scalar on the record and the authored planform
## carries one chord table for all blades. If a future slice ever lets a builder space blades
## unequally, the forcing splits into a set of lines around this one and this method is where it
## stops being true; nothing downstream would notice on its own.
func excitation_orders() -> Dictionary:
	return {
		"1x rotation": 1.0,
		"blade passing": float(prop_geometry().blades),
		"motor electrical": pole_pairs(),
	}


## The highest RPM this aircraft can actually turn: full throttle as the weakest of the motor,
## pack and ESC limits allows it, sag included.
##
## A composition of two methods that already exist, named because P10e's Campbell diagram has to
## draw the difference between "an RPM on the axis" and "an RPM this build can reach". Marking a
## resonance crossing the aircraft cannot get to is the overlay telling a builder to avoid a
## throttle setting that does not exist.
func reachable_rpm() -> float:
	return rpm_at_throttle(max_throttle_fraction())


## FrameMaterials for the blade-density fallback in MotorSpinUp — used only when a
## propeller has no `published_mass_g` and the density-integral form has to be used instead.
## Loaded once and cached because there is exactly one materials table and this method may
## be called every UI refresh of the propulsion panel.
static var _spin_up_materials_cached: FrameMaterials


static func _spin_up_materials() -> FrameMaterials:
	if _spin_up_materials_cached == null:
		_spin_up_materials_cached = FrameMaterials.load_default()
	return _spin_up_materials_cached

func battery_model() -> BatteryModel:
	return BatteryModel.create(
		float(battery["specs"]["nominal_v"]),
		float(battery["specs"]["internal_r_ohm"]),
		float(battery["specs"]["mah"]),
		int(battery["specs"].get("cells", 0)),
		str(battery["specs"].get("chemistry", BATTERY_DEFAULT_CHEMISTRY))
	)

func build_drone_core() -> DroneCore:
	var geometry := _prop_geometry(propeller)
	var core := DroneCore.new(mass_properties, motor_model(), arm_m, k_t, k_q, battery_model(),
		effective_max_amps, rated_rpm(), drag_coefficient,
		pole_pairs(), geometry.blades, geometry.diameter_m * 0.5, gyro(), geometry.pitch_m,
		air.kgm3(), blade_chord(), guard_closure)
	# The aircraft the sim flies is the aircraft the builder configured, including a spin map
	# Lothal has warned about: design §5.3 — fly it badly, do not refuse it.
	core.config = config
	return core

## Electrical frequency is per POLE PAIR, not per pole — a 14-pole motor turns through
## seven electrical cycles per revolution, not fourteen. Getting this wrong is a factor of
## two on the whine, which sounds like a different motor rather than like a bug.
func pole_pairs() -> float:
	return float(motor["specs"]["poles"]) * 0.5


# ---------------------------------------------------------------------------
# The five derived stats (parts.md). This feedback loop is the product.
# ---------------------------------------------------------------------------

func all_up_weight_g() -> float:
	return mass_properties.total_mass_kg * 1000.0

func weight_n() -> float:
	return mass_properties.total_mass_kg * GRAVITY_MPS2

## Quoted at NOMINAL pack voltage, deliberately. This is the bench figure — the same
## convention every manufacturer thrust table and every spec sheet uses, and the one
## physics.md §8 and parts.md's reference build state as the 11.7:1 oracle. Evaluating it
## at the sagged full-throttle voltage instead would read ~8.9:1 for the reference build
## and quietly move the project's own smoke-test number.
##
## Sag is not being ignored — it is fully modelled where it is actually felt, in flight
## and in hover throttle. A spec sheet number and a flying number are different things.
## Quoted at the MOTOR's current limit as well, for the same reason and by the same line of
## argument. A pack's C-rating is a property of the battery strapped on today, not of the
## airframe: swap the pack and this number would move, and the figure two builders compare would
## stop being about the aircraft. So the bench figure asks what these motors and props can make at
## this voltage, and the pack's limit binds everywhere the machine is actually flown —
## max_throttle_fraction(), and therefore peak thrust, hover, top speed and the sim's own ceiling.
##
## warnings() says out loud when the reachable thrust is far below this, which is where a
## builder finds out that the bench figure is not the flying figure. Naming the gap is worth more
## than hiding it inside a single number that then explains nothing.
func max_total_thrust_n() -> float:
	return 4.0 * PropellerModel.thrust_n(k_t, max_rpm_at_nominal())


## The RPM behind the bench figure above: KV at nominal volts, capped by what the motors' own
## current limit lets them reach. Factored out because top_speed_kmh() asks the same question at a
## non-zero airspeed, and two spellings of one RPM ceiling is one edit away from two answers.
func max_rpm_at_nominal() -> float:
	return float(motor["specs"]["kv"]) * float(battery["specs"]["nominal_v"]) * motor_throttle_limit()

func thrust_to_weight() -> float:
	return max_total_thrust_n() / weight_n()

## Steady-state total thrust at a given throttle, with the pack sagging under the current
## that throttle draws. This is deliberately NOT monotonic: on a high-resistance pack,
## past some throttle the extra current costs more voltage than the extra command buys,
## and thrust peaks and then falls. That is the Li-ion entry's whole reason to exist, and
## it is why hover is solved by bracketing rather than by iterating a fixed point — the
## fixed point diverges on exactly the packs the catalog includes to be interesting.
func thrust_at_throttle_n(throttle: float, open_circuit_v: float = AT_NOMINAL) -> float:
	return 4.0 * PropellerModel.thrust_n(k_t, rpm_at_throttle(throttle, open_circuit_v))

## Steady-state RPM at a throttle command. RPM and pack sag depend on each other, but the
## loop converges quickly: more sag means less RPM means less current means less sag.
## Turns the AT_NOMINAL sentinel into a voltage. Anything non-negative is taken at face value: a
## caller that has a real pack in hand passes what that pack is actually resting at.
func resolve_open_circuit_v(open_circuit_v: float) -> float:
	if open_circuit_v < 0.0:
		return float(battery["specs"]["nominal_v"])
	return open_circuit_v


func rpm_at_throttle(throttle: float, open_circuit_v: float = AT_NOMINAL) -> float:
	# The 12-iteration sag fixed point lives in Rust (rust/src/fitting.rs) — it is the same
	# convergence Powertrain reaches dynamically by integrating the lag.
	var kv: float = float(motor["specs"]["kv"])
	var rest_v := resolve_open_circuit_v(open_circuit_v)
	var internal_r: float = float(battery["specs"]["internal_r_ohm"])
	return Fitting.rpm_at_throttle(throttle, max_throttle_fraction(), kv, rest_v,
		internal_r, effective_max_amps, rated_rpm())

## Current drawn by one motor at a given RPM — see DroneCore.current_at_rpm, which this
## must agree with exactly, or the HUD's numbers and the flight model's numbers diverge.
func current_at_rpm(rpm: float) -> float:
	return Fitting.current_at_rpm(rpm, effective_max_amps, rated_rpm())

## The RPM at which this motor draws its rated amps with the prop actually fitted: KV times
## the pack voltage the manufacturer's amp figure was measured at.
func rated_rpm() -> float:
	return Fitting.rated_rpm(float(motor["specs"]["kv"]), float(motor["thrust_test"]["voltage_v"]))

## Throttle at which sagged thrust peaks, and that peak. Everything above this throttle is
## the pack losing the argument with the motors.
func peak_thrust(open_circuit_v: float = AT_NOMINAL) -> Dictionary:
	var best_throttle := 0.0
	var best_thrust := 0.0
	var cap := max_throttle_fraction()
	var samples := 400
	for i in range(samples + 1):
		var t := cap * float(i) / float(samples)
		var thrust := thrust_at_throttle_n(t, open_circuit_v)
		if thrust > best_thrust:
			best_thrust = thrust
			best_throttle = t
	return {"throttle": best_throttle, "thrust_n": best_thrust}

## True when the build can actually generate its own weight in thrust, sag included.
func can_hover(open_circuit_v: float = AT_NOMINAL) -> bool:
	return peak_thrust(open_circuit_v)["thrust_n"] > weight_n()

## Steady-state hover throttle AT THE NOMINAL VOLTAGE DATUM by default (physics.md §5) — the
## project's 29% oracle, and the figure the stats panel quotes. Pass a resting voltage, or use
## hover_throttle_for(), to ask what a pack in a particular state of charge actually needs.
##
## Bisected on the rising branch of thrust_at_throttle_n,
## so it is the LOWER of the two throttles that produce hover thrust — the stable one.
## Returns the peak-thrust throttle for a build that cannot hold itself up, which reads as
## "flat out and still sinking" rather than as a number that was quietly clamped.
func hover_throttle(open_circuit_v: float = AT_NOMINAL) -> float:
	var peak := peak_thrust(open_circuit_v)
	var target_n := weight_n()
	if peak["thrust_n"] <= target_n:
		return peak["throttle"]

	var low := 0.0
	var high: float = peak["throttle"]
	for _i in 60:
		var mid := (low + high) * 0.5
		if thrust_at_throttle_n(mid, open_circuit_v) < target_n:
			low = mid
		else:
			high = mid
	return high

## This board's mass, or the budgeted share if a selection reached here without one.
## The sensor this aircraft flies, from the fitted board. The ONE answer to "what gyro is on
## this build" — the details panel and the flying aircraft read the same call, so they cannot
## come to describe different sensors.
## The six part ids that make this build, joined — a stable name for THIS combination of parts.
##
## Used to key the builder's saved PID tunes, and it is all six rather than the frame alone because
## the plant a tune is derived against is the whole aircraft: a 5" freestyle with 2807s on it is a
## different thing to fly than the same frame with 2207s, and a tune that followed one to the other
## would recreate the bug RateTune exists to fix. The ids rather than an index or a hash, so the
## saved file stays readable and a part that is renamed in the catalog fails to match instead of
## silently matching something else.
func fingerprint() -> String:
	var ids: Array[String] = []
	for part in [frame, motor, propeller, battery, esc, fc]:
		ids.append(String(part.get("part_id", "?")))
	return "/".join(ids)


## The fitted board's sensor, ON THIS AIRFRAME. Two different aircraft carrying the same board get
## the same sensor and a different shake, which is the point: the noise a gyro reads stopped being
## a property of the board when frame resonance arrived, and became a property of the board plus
## the thing it is bolted to.
func gyro() -> Gyro:
	var g := Gyro.from_part(fc)
	g.vibration = VibrationModel.for_build(self)
	return g


## This board's mass, or the budgeted share if a selection reached here without one.
func fc_mass_g() -> float:
	return float(fc.get("mass_g", FC_BUDGET_MASS_G))


func fc_mount_pattern() -> String:
	return str(fc.get("mounting", {}).get("pattern", STACK_MOUNT_PATTERN))


func esc_mass_g() -> float:
	return float(esc.get("mass_g", ESC_BUDGET_MASS_G))


func esc_mount_pattern() -> String:
	return str(esc.get("mounting", {}).get("pattern", STACK_MOUNT_PATTERN))


## What the ESC will pass in TOTAL: its per-channel continuous rating times its channel count.
##
## Reading a "45A 4-in-1" as 45 A for the whole aircraft is the mistake this function exists to
## make impossible — it is four 45 A channels, so 180 A, and the other reading would make every
## board in the catalog the binding constraint on every build. Burst is carried in the catalog and
## deliberately not used: applying a burst rating as though it were continuous is just a larger
## continuous rating wearing a misleading name, and doing it properly needs a thermal state.
func esc_max_amps() -> float:
	var specs: Dictionary = esc.get("specs", {})
	return float(specs.get("continuous_a", 0.0)) * float(specs.get("channels", 4.0))


func esc_throttle_limit() -> float:
	return throttle_limit_for(esc_max_amps())


## The board's continuous rating for ONE CHANNEL, which is the number printed on the product and
## the number the hardware actually enforces. esc_max_amps() above is this times the channel count;
## the two are a factor of four apart on every board in the catalog, and confusing them in either
## direction is the single most expensive mistake available here.
func esc_continuous_a() -> float:
	return float(esc.get("specs", {}).get("continuous_a", 0.0))


func esc_channels() -> int:
	return int(esc.get("specs", {}).get("channels", 4))


## The board's BURST rating per channel, carried and deliberately not used as a limit anywhere.
## Exposed only so a readout can show it while saying it is not modelled — a builder comparing two
## boards compares both numbers, and leaving it off the screen entirely would be its own kind of
## dishonesty. Modelling it properly needs a thermal state (how long the burst has lasted, how hot
## the board already was); applied as though it were continuous it is simply a larger continuous
## rating wearing a misleading name.
func esc_burst_a() -> float:
	return float(esc.get("specs", {}).get("burst_a", 0.0))


## What ONE motor pulls at the highest throttle the MOTORS themselves can reach — the demand one
## channel of the board has to pass.
##
## Quoted at motor_throttle_limit() and NOT at max_throttle_fraction(), which is the whole trick.
## max_throttle_fraction() is already clamped by the ESC, so asking what the motors draw there
## would ask what they draw once the board has stopped them — and every board in the catalog would
## report exactly enough headroom for itself. A bench that cannot fail is not a bench.
##
## The pack is left out for a different reason: a weak pack would make a weak board look adequate,
## and the moment you fit a better battery the board is the thing that lets the smoke out. What the
## pack does to this build is reported by name through limiting_component(), which is where a
## builder finds out that the money is better spent there.
##
## Equal to the motor's rated max_amps whenever the fitted prop is heavy enough to reach that
## rating, and less on a prop too small to load the motor that far — which is why this bench, like
## the thrust stand, is testing a PAIRING and not a board against a datasheet.
func motor_demand_per_channel_a() -> float:
	var ceiling := motor_throttle_limit()
	return effective_max_amps * ceiling * ceiling


## Continuous amps available on one channel, less what one motor will ask of it. Negative means the
## board is undersized for these motors and would be the thing that fails.
func esc_channel_headroom_a() -> float:
	# Both sides PER CHANNEL. Putting esc_max_amps() on the left — the board's total against one
	# motor's draw — is the reading escs.json's schema warns about, and it reports 208 A of headroom
	# where there are 28: every board in the catalog looks ample, which is a failure that resembles
	# a working feature.
	return esc_continuous_a() - motor_demand_per_channel_a()


func esc_has_channel_headroom() -> bool:
	return esc_channel_headroom_a() >= 0.0


## Total pack current at a throttle command, via the RPM that throttle actually reaches.
func hover_current_a(throttle: float, open_circuit_v: float = AT_NOMINAL) -> float:
	return 4.0 * current_at_rpm(rpm_at_throttle(throttle, open_circuit_v))


## The hover throttle for a pack in the state it is ACTUALLY in, rather than at the nominal datum.
##
## This is what the field flies. scenes/main.gd rests the throttle stick here, so centring the
## stick hovers whatever pack came out of the bag — a fresh one, which rests above nominal and
## needs LESS than the quoted 29%, or a half-used one, which needs a little more. Solved once at
## spawn and then left alone: the pack keeps draining while you fly, and the aircraft settling
## slowly downward over four minutes is the consequence pack choice exists to teach, not a bug to
## servo out. What was a bug was the aircraft dropping out of the sky at half pack, which was the
## discharge datum and is fixed in BatteryModel.
##
## Deliberately NOT what the stats panel shows. That number is quoted at nominal voltage, it is
## the one two builders can compare, and it does not move.
func hover_throttle_for(pack: BatteryModel) -> float:
	return hover_throttle(pack.resting_voltage_v())

## Total pack current holding a trimmed flight at one airspeed and load factor.
##
## The aircraft leans until the horizontal component of thrust balances drag, so both the lean and
## the thrust needed fall out of the airspeed rather than being chosen: total thrust is the
## hypotenuse of the lift it must hold and the drag it must beat. The throttle that produces that
## thrust is then bisected on the RISING branch, capped at the peak-thrust throttle, for the same
## reason hover_throttle() is — on a high-resistance pack thrust is not monotonic in throttle, and
## a fixed point would diverge on exactly the packs the catalog carries to be interesting.
##
## The lean is what puts the freestream on the rotor axis, so it is also what decides how much of
## the airspeed unloads the prop and how much of it is the edgewise flow that makes the rotor
## cheaper. Both come out of the one angle; neither is a separate assumption.
func flight_current_at_a(airspeed_mps: float, load_factor: float, throttle_ceiling: float,
		open_circuit_v: float = AT_NOMINAL) -> float:
	var ratios := forward_ratios()

	var lift_n := load_factor * weight_n()
	var drag_n := drag_coefficient * airspeed_mps * airspeed_mps
	var lean_rad := atan2(drag_n, lift_n)
	var v_axial := airspeed_mps * sin(lean_rad)
	var v_edge := airspeed_mps * cos(lean_rad)
	var target_n := sqrt(lift_n * lift_n + drag_n * drag_n)

	var low := 0.0
	var high := throttle_ceiling
	for _i in 40:
		var mid := (low + high) * 0.5
		var mid_rpm := rpm_at_throttle(mid, open_circuit_v)
		var thrust_n := 4.0 * PropellerModel.thrust_n(k_t, mid_rpm) \
			* ratios.thrust_ratio(mid_rpm, v_axial, v_edge)
		if thrust_n < target_n:
			low = mid
		else:
			high = mid

	# `high` is the ceiling itself when this segment is unreachable, which reads as "flat out and
	# still not holding it" — the same convention hover_throttle() uses for a build that cannot
	# hold itself up, rather than a number quietly clamped into looking achievable.
	var rpm := rpm_at_throttle(high, open_circuit_v)
	return 4.0 * current_at_rpm(rpm) * ratios.power_ratio(rpm, v_axial, v_edge)


## The current a pack actually sees over a flight: the model's answer at each row of
## FREESTYLE_FLIGHT_PROFILE, weighted by how much of the time is spent there.
func average_flight_current_a(open_circuit_v: float = AT_NOMINAL) -> float:
	# One peak solve for all five segments. It is 400 thrust evaluations and it does not depend on
	# airspeed, so paying for it per segment would quintuple the cost of every stats-panel refresh
	# for an identical answer.
	var ceiling: float = peak_thrust(open_circuit_v)["throttle"]
	var total := 0.0
	for segment in FREESTYLE_FLIGHT_PROFILE:
		total += float(segment["fraction"]) * flight_current_at_a(
			float(segment["airspeed_mps"]), float(segment["load_factor"]), ceiling, open_circuit_v)
	return total


## Zero for a build that cannot hover — there is no flight to put a time on.
func flight_time_min() -> float:
	if not can_hover():
		return 0.0
	var average_current_a := average_flight_current_a()
	if average_current_a <= 0.0:
		return 0.0
	var usable_mah: float = float(battery["specs"]["mah"]) * USABLE_CAPACITY_FRACTION
	return (usable_mah / (average_current_a * 1000.0)) * 60.0

## How much flying is LEFT in a pack in the state it is actually in, in minutes.
##
## The same convention as flight_time_min() — average current is the model's own answer over
## FREESTYLE_FLIGHT_PROFILE, and only USABLE_CAPACITY_FRACTION of the pack is flown — so the
## HUD's countdown and the stats panel's estimate are the same claim about the same aircraft, and
## a pilot who reads 4.1 minutes in the garage and 4.1 minutes at spawn is not being told two
## different things by two different formulas.
##
## What differs is only the capacity remaining, and the voltage it is solved at: a half-empty pack
## rests lower, so the hover it has to hold costs a little more current. Zero for a build that
## cannot hover, and zero once the usable capacity is gone — the pack is not flat, it is past the
## reserve you would have landed on.
func remaining_flight_time_min(pack: BatteryModel) -> float:
	var rest_v := pack.resting_voltage_v()
	if not can_hover(rest_v):
		return 0.0
	var average_current_a := average_flight_current_a(rest_v)
	if average_current_a <= 0.0:
		return 0.0
	var usable_mah := pack.capacity_mah * USABLE_CAPACITY_FRACTION - pack.used_mah
	if usable_mah <= 0.0:
		return 0.0
	return (usable_mah / (average_current_a * 1000.0)) * 60.0


## Terminal speed at the reference lean: horizontal thrust balances aerodynamic drag.
##
## The thrust ceiling is evaluated AT THE SPEED BEING SOLVED FOR, which is why this bisects rather
## than evaluating one expression. A leaned rotor at speed has the freestream partly along its own
## axis and makes less thrust than the same rotor on a stand, so "can this aircraft hold 45 degrees
## at 40 m/s" is a question about 40 m/s and not about a bench.
##
## For the reference build this changes NOTHING — 107 km/h before and after — because at a fixed 45
## degrees the thrust required is weight over cos(45), 6.9 N against 34 N still available. That is
## the honest result and it is worth saying plainly rather than implying the correction earned its
## place here. It earns it on builds the reference build cannot exercise: a heavy or low-TWR
## aircraft, or a high-pitch prop whose thrust runs out early, is where the cap actually binds, and
## for those the previous figure was an over-estimate.
func top_speed_kmh() -> float:
	var lean_horizontal_n := weight_n() * tan(TOP_SPEED_LEAN_RAD)
	var max_rpm := max_rpm_at_nominal()
	var ratios := forward_ratios()

	# The drag-only answer, which is an upper bound: unloading can only ever take thrust away.
	var high := sqrt(lean_horizontal_n / drag_coefficient)
	var low := 0.0
	for _i in 40:
		var mid := (low + high) * 0.5
		var available_n := 4.0 * PropellerModel.thrust_n(k_t, max_rpm) \
			* ratios.thrust_ratio(max_rpm, mid * sin(TOP_SPEED_LEAN_RAD),
				mid * cos(TOP_SPEED_LEAN_RAD))
		var horizontal_n := minf(lean_horizontal_n, available_n * sin(TOP_SPEED_LEAN_RAD))
		if drag_coefficient * mid * mid < horizontal_n:
			low = mid
		else:
			high = mid
	return low * 3.6


# ---------------------------------------------------------------------------
# Compatibility: warn, never block (parts.md). "What happens if I put 7-inch props on a
# race frame" is exactly the curiosity that makes a builder sim worth using, and the sim
# answering "it barely lifts and the inertia is awful" teaches more than a greyed-out
# dropdown ever would.
# ---------------------------------------------------------------------------

func warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	var prop_inches: float = float(propeller["specs"]["diameter_inches"])
	var max_prop_inches: float = float(frame["specs"]["max_prop_inches"])
	if prop_inches > max_prop_inches:
		out.append(BuildWarning.impossible(&"prop_clearance",
			"%s props exceed the %s's %.1f\" clearance — they would strike the frame." % [
				propeller["name"], frame["name"], max_prop_inches],
			{"prop_inches": prop_inches, "max_prop_inches": max_prop_inches}))

	if motor.get("mount_pattern", "") != frame["specs"].get("motor_mount", ""):
		out.append(BuildWarning.impossible(&"motor_mount",
			"%s uses a %s mount; the %s is drilled %s." % [
				motor["name"], motor.get("mount_pattern", "?"),
				frame["name"], frame["specs"].get("motor_mount", "?")],
			{"motor_pattern": str(motor.get("mount_pattern", "?")),
				"frame_pattern": str(frame["specs"].get("motor_mount", "?"))}))

	# Named by the component that actually binds. Reporting "too much prop for the motor" when it
	# is the pack that runs out first would send a builder to buy the wrong part, which is the
	# whole reason the binding constraint is modelled separately rather than as one ceiling.
	var throttle_cap := max_throttle_fraction()
	if throttle_cap < 0.99:
		var limit := limiting_component()
		var limit_values := {
			"limited_by": str(limit["name"]), "limit_amps": float(limit["amps"]),
			"throttle_cap": throttle_cap,
		}
		match limit["name"]:
			"battery":
				out.append(BuildWarning.limiting(&"current_limit",
					"The %s runs out of current before the motors or the %s do — %.0f A continuous caps this build at %.0f%% throttle." % [
						limit["label"], esc.get("name", "ESC"), limit["amps"], throttle_cap * 100.0],
					limit_values))
			"esc":
				out.append(BuildWarning.limiting(&"current_limit",
					"The %s runs out of current first — %.0f A across four channels caps this build at %.0f%% throttle, where the %s would take %.0f%% and the %s would pass %.0f A." % [
						limit["label"], limit["amps"], throttle_cap * 100.0,
						motor["name"], motor_throttle_limit() * 100.0,
						battery["name"], pack_max_amps()],
					limit_values))
			_:
				out.append(BuildWarning.limiting(&"current_limit",
					"%s is too much prop for the %s — it hits its %.0f A limit at %.0f%% throttle." % [
						propeller["name"], motor["name"],
						float(motor["specs"]["max_amps"]), throttle_cap * 100.0],
					limit_values))

	# Both boards bolt to the frame through the same centre pattern, and either can be the wrong
	# one. This is the same check the motors already get, and the same mistake someone makes
	# exactly once: a 20x20 board and a 30.5x30.5 frame do not meet.
	out.append_array(_stack_fit_warning(esc, esc_mount_pattern(), &"stack_mount", "The ESC"))
	out.append_array(_stack_fit_warning(fc, fc_mount_pattern(), &"fc_stack_mount",
		"The flight controller"))

	# CHARACTERISTIC, and deliberately: labs-and-sim.md §2.1's rule is that where the physics has
	# a hard boundary you warn, and where it has a continuum you describe. Four grams over a
	# budgeted share is a position on a continuum. Nothing binds, nothing refuses — the aircraft is
	# simply heavier, and every number on the panel already says so. LIMITING would claim something
	# caps this build when nothing does, which is the failure the severity scale exists to prevent.
	if fc_mass_g() > FC_BUDGET_MASS_G:
		out.append(BuildWarning.characteristic(&"fc_mass_budget",
			"%s is %.0f g against the %.0f g the electronics budget allots — the aircraft carries the extra %.0f g." % [
				fc.get("name", "The flight controller"), fc_mass_g(), FC_BUDGET_MASS_G,
				fc_mass_g() - FC_BUDGET_MASS_G],
			{"board_mass_g": fc_mass_g(), "budget_mass_g": FC_BUDGET_MASS_G,
				"excess_g": fc_mass_g() - FC_BUDGET_MASS_G}))

	# Thrust-to-weight is a bench number at nominal voltage (see max_total_thrust_n). On a
	# high-resistance pack the thrust actually reachable is far below it, which would
	# otherwise surface as the baffling combination of a healthy TWR next to a drone that
	# will not fly. Say it out loud instead — this is the lesson the Li-ion is here to teach.
	var reachable_thrust_n: float = peak_thrust()["thrust_n"]
	var usable_fraction := reachable_thrust_n / max_total_thrust_n()
	if usable_fraction < SAG_WORTH_NAMING:
		out.append(BuildWarning.limiting(&"pack_sag",
			"The %s sags hard under load — only %.0f%% of that %.1f:1 bench figure is reachable, or %.1f:1 in the air." % [
				battery["name"], usable_fraction * 100.0, thrust_to_weight(),
				reachable_thrust_n / weight_n()],
			{"usable_fraction": usable_fraction, "bench_twr": thrust_to_weight(),
				"reachable_twr": reachable_thrust_n / weight_n()}))

	# The field comes FIRST of the three, deliberately. It is the frame every number below it is
	# quoted in, and a reader who meets "cannot hover" before they have been told they are at
	# 3500 m has been handed the conclusion before the premise.
	out.append_array(_field_air())
	out.append_array(_flight_quality())
	out.append_array(_prop_unloading())
	out.append_array(_vibration_character())

	# What this build's frame is, where its numbers came from, and the one place Lothal knows it is
	# wrong. Its own file because the bounds each need a paragraph of justification and this
	# function is already long — see FramePlausibility for every number in it.
	out.append_array(FramePlausibility.warnings_for(self))

	# And the same for the motor, which needs its own file for a reason the frame's does not: a
	# frame's surprising numbers are visible on screen, and a motor's are not. A thrust figure
	# with a digit wrong draws an aircraft that looks entirely normal.
	out.append_array(MotorPlausibility.warnings_for(self))

	# How far this build extrapolates from the manufacturer's own thrust-test row — fired for
	# catalog and custom builds alike, because whether the extrapolation is trustworthy is a
	# question about the k_t scaling law and not about who typed the numbers in.
	out.append_array(PropExtrapolation.warnings_for(self))

	# What this build's custom prop is, when it has one — analogous to MotorPlausibility, and
	# empty for a catalog prop.
	out.append_array(PropPlausibility.warnings_for(self))

	# And the same for the pack — empty for a catalog battery, and for a custom one it says the
	# two things a builder needs to know: the derived internal resistance is a self-consistency
	# assumption reproduced (not a measurement), and every flight-time figure is averaged over an
	# assumed mission profile named FREESTYLE_FLIGHT_PROFILE.
	out.append_array(BatteryPlausibility.warnings_for(self))

	# And the two halves of the stack. The ESC's file exists for one check above all others — the
	# per-board/per-channel confusion escs.json's schema puts in capitals — and the FC's exists to
	# keep two derived numbers from being read as the same kind of number: its noise floor is
	# datasheet-backed and its bias is illustrative.
	out.append_array(EscPlausibility.warnings_for(self))
	out.append_array(FcPlausibility.warnings_for(self))

	# And what the pilot's intent passes through on its way to the motors
	# (plans/2026-09-12-control-room-plan.md C6): an aircraft with no receiver at all, a buzzer that
	# goes silent with the pack, and a COUNT of the parts wanting a serial port — stated without a
	# port count, because no board in this catalog publishes one and a headroom figure derived from
	# a number nobody published is the one thing design §0 still refuses.
	out.append_array(ControlPlausibility.warnings_for(self))

	# And what the picture passes through (video-room design §3, slice V4): a camera the builder's
	# uptilt tips into the top plate, and a transmitter fitted with no antenna. Both read the build
	# alone — the tilt comes out of `assembly`, never off a drawn node.
	out.append_array(VideoPlausibility.warnings_for(self))

	# And the path the current takes to get there (plans/2026-09-10-power-room-plan.md PW3): wire
	# ampacity per segment, the harness's own voltage drop reported APART from the pack's sag, the
	# plug's rating and — the one hard refusal in the set — whether the plug on the aircraft mates
	# with the one on the pack. Last of the list because it is the only entry that reads a primed
	# powertrain, and a reader meeting "your leads lose 0.4 V" before they have been told what the
	# build draws has been handed a consequence with no premise.
	out.append_array(HarnessChecks.warnings_for(self))

	# And what the builder will type into a configurator (config-room design §5, slice C2): today,
	# a motor map that cannot fly. Registered here exactly as the eleven modules above are, because
	# a check the aggregate does not carry is a check nobody sees.
	out.append_array(ConfigPlausibility.warnings_for(self))
	return out


## The throttle command that settles at a given RPM — rpm_at_throttle inverted, by bisection.
##
## Bisection rather than the obvious `rpm / rpm_at_throttle(1.0)`, and the difference is not small:
## that ratio puts the reference build's 180 Hz crossing at 44% throttle, where it actually turns
## 207 Hz. The curve is not a line, because voltage sags with load and the motor's own current cap
## bites near the top, so a linear inversion is wrong by 15% in the middle of the range — exactly
## where a builder would be listening for the peak. rpm_at_throttle IS monotone, which is all
## bisection needs, and asking IT rather than modelling its shape here means this stays correct if
## the powertrain ever gains another nonlinearity.
##
## Returns above 1.0 for an rpm this build cannot reach, so a caller can tell "at 140% throttle"
## from "at full throttle" and say the honest thing about it.
func throttle_at_rpm(target_rpm: float) -> float:
	var full := rpm_at_throttle(1.0)
	if full <= 0.0:
		return INF
	if target_rpm >= full:
		return target_rpm / full   # unreachable: report how far out of reach, not a clamp
	var low := 0.0
	var high := 1.0
	# 40 halvings takes the bracket below one part in 10^12 — far past the precision of anything
	# that reads this, and cheap enough that there is no reason to stop earlier.
	for i in 40:
		var mid := (low + high) * 0.5
		if rpm_at_throttle(mid) < target_rpm:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


## Where this airframe rings, and where in the throttle range its own harmonics drive it.
##
## CHARACTERISTIC, and this is the purest case of the rule in the whole file. There is no throttle
## at which a resonance stops the aircraft working; there is one at which the gyro gets noisy, the
## D term starts spending itself on shake, and the motors get warm. That is a continuum from end to
## end — parts.md: where physics has a hard boundary, warn; where it has a continuum, describe. A
## build whose hover harmonic sits on its frame mode has not made a mistake. Half the 5" quads ever
## built are that build.
##
## WHAT THIS SENTENCE MAY AND MAY NOT SAY. VibrationModel's whole scale rests on one guessed
## constant and no manufacturer publishes a frame resonance for anything, so there is no held-out
## measurement to be right or wrong against. It may therefore quote FREQUENCIES and THROTTLES —
## those come from the cantilever scaling law and from this build's own rpm curve, both of which
## are derivations a reader can check — and it may NOT quote an amplitude, an error bar, or an
## accuracy. labs-and-sim.md §2.1 says a bench that will not quote its own error bar is
## decoration; the converse is that one quoting a fabricated error bar is worse than decoration,
## and a test in tests/test_build_warnings.gd holds this sentence to it.
func _vibration_character() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var model := VibrationModel.for_build(self)
	var full_rpm := rpm_at_throttle(1.0)
	if full_rpm <= 0.0 or model.resonance_hz <= 0.0:
		return out

	var blades: float = prop_geometry().blades
	var imbalance_throttle := throttle_at_rpm(model.resonance_hz * 60.0)
	var blade_throttle := throttle_at_rpm(model.resonance_hz * 60.0 / blades)
	var hover := hover_throttle()

	# The sentence changes when the crossing is out of reach, because "sweeps through it at 140%
	# throttle" is arithmetic rather than information — the same reason manoeuvre headroom has two
	# wordings for one figure.
	var where := "Prop imbalance sweeps through it at %.0f%% throttle and blade passage at %.0f%%" % [
		imbalance_throttle * 100.0, blade_throttle * 100.0]
	if imbalance_throttle > 1.0:
		where = "Blade passage sweeps through it at %.0f%% throttle; rotation itself never reaches it" % [
			blade_throttle * 100.0]
	if blade_throttle > 1.0:
		where = "Neither harmonic reaches it inside the throttle range — this airframe rings above anything its own props can drive"

	out.append(BuildWarning.characteristic(&"frame_resonance",
		"%s arms put the first bending mode near %.0f Hz. %s — that is where the gyro is noisiest and where the D term costs the most." % [
			frame["name"], model.resonance_hz, where],
		{"resonance_hz": model.resonance_hz,
			"imbalance_crossing_throttle": imbalance_throttle,
			"blade_crossing_throttle": blade_throttle,
			"hover_throttle": hover,
			"blades": blades}))

	# A separate id rather than a clause on the one above, because it is a separate fact and a
	# panel or a test must be able to ask about it alone. It is the fact a builder can act on:
	# hover is where the aircraft spends its life, and a harmonic parked on the mode there is a
	# permanently noisy gyro rather than a peak you fly through.
	var hover_hz := rpm_at_throttle(hover) / 60.0
	for harmonic in [{"hz": hover_hz, "what": "Prop imbalance"}, {"hz": hover_hz * blades, "what": "Blade passage"}]:
		if absf(float(harmonic["hz"]) - model.resonance_hz) < model.resonance_hz * 0.15:
			out.append(BuildWarning.characteristic(&"hover_on_resonance",
				"%s sits at %.0f Hz at hover, right on the %.0f Hz frame mode — this one will be shaking the gyro the whole flight rather than only on the way past." % [
					harmonic["what"], float(harmonic["hz"]), model.resonance_hz],
				{"harmonic_hz": float(harmonic["hz"]), "resonance_hz": model.resonance_hz,
					"hover_throttle": hover}))
			break

	return out


## One board's bolt pattern against the frame's, as a list so a caller can append it
## unconditionally.
##
## One helper rather than two copies of the comparison: the ESC and the flight controller bolt
## through the SAME holes, and two copies is how they come to disagree about what "fits" means.
##
## IMPOSSIBLE because there is a boundary in the geometry to point at — the holes either line up
## or they do not. But IT STILL MOUNTS: labs-and-sim.md §2.6 is explicit that zip-tying a
## mismatched board on is a thing real builders do on a Saturday afternoon, and the useful answer
## is a sentence you can act on rather than a dropdown that has greyed itself out. Severity
## changes how this is SAID, never whether the part can be chosen.
##
## Separate ids for the two boards rather than one shared id, because a build can get this wrong
## twice independently, and two warnings answering to one name cannot be told apart by a test or
## filtered by a panel.
func _stack_fit_warning(board: Dictionary, board_pattern: String, id: StringName,
		fallback_name: String) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var frame_stack: String = str(frame["specs"].get("stack_mount", ""))
	if frame_stack == "" or board_pattern == frame_stack:
		return out
	out.append(BuildWarning.impossible(id,
		"%s is a %s board; the %s is drilled %s for its stack." % [
			board.get("name", fallback_name), board_pattern, frame["name"], frame_stack],
		{"board_pattern": board_pattern, "frame_pattern": frame_stack}))
	return out


## What this aircraft DOES, in numbers with units — as opposed to whether it is any good.
##
## This block used to be three branches on one axis: cannot hover, else TWR < 2.0 "will barely
## leave the ground", else hover > 60% "almost no headroom". Four things were wrong with it, and
## they are worth naming because they are the failure modes this whole file now guards against.
##
##   1. 2.0:1 IS TASTE WEARING PHYSICS CLOTHING. It is not a boundary between flying and not
##      flying; it is roughly the boundary between sluggish and sporty. Cinelifters and camera
##      rigs fly at and below it deliberately, and one such build was told it would barely leave a
##      ground it had in fact left, climbed away from and flown laps around.
##   2. IT CUT ONE QUANTITY TWICE. Hover throttle is sqrt(1 / TWR) — thrust goes as RPM squared
##      and RPM as the command — so TWR 2.0 IS hover 70.7%. Two constants, one continuum, and
##      either could be edited into disagreeing with the other about the same aircraft.
##   3. `elif` HID THE USEFUL STATEMENT BEHIND THE ALARMING ONE. The reported build never saw the
##      headroom sentence, which was the accurate and actionable one, because the TWR branch
##      consumed it first. They are not mutually exclusive facts.
##   4. IT WAS ALL THE SAME SEVERITY as a pack that physically does not fit.
##
## What is left is one hard boundary and two descriptions. The boundary is real: peak thrust below
## weight means the aircraft cannot hold itself up, and no wording makes that a preference. The two
## descriptions are both reported, every time, because they are different facts — how hard it can
## climb, and how much of a stick input it can absorb without giving up altitude to do it.
##
## There is deliberately no derived "floor" between them. The only floor that could be computed
## honestly — the TWR at which climb margin no longer arrests a descent — depends on the descent
## rate being arrested, which is a pilot's choice and not a property of the parts. Rather than
## assert one, the margin itself is printed and the reader can do what they like with it.
## What the propeller's own pitch costs this build at speed.
##
## A prop stops making thrust at an advance ratio near its geometric pitch over its diameter, so a
## high-pitch prop on a low-revving motor runs out of blade before it runs out of drag: the aircraft
## is not slow because it is draggy, it is slow because the propeller has nothing left to push
## against. That is a genuinely different diagnosis from "too heavy" or "not enough thrust", it is
## invisible on any static figure the stats panel shows, and before the forward-flight model
## (2026-08-14) Lothal could not tell a builder about it at all.
##
## CHARACTERISTIC, and warn-never-block as always: a high-pitch prop is a legitimate choice with a
## consequence, which is exactly the case this severity exists for.
##
## Quotes no error bar and must not grow one. The model under it is characteristic
## (validation.md) — there is no published C_T(J) for any FPV propeller — so what is trustworthy
## here is the ranking and the mechanism, not the metre per second.
func _prop_unloading() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not can_hover():
		return out

	var geometry := prop_geometry()
	var top_mps := top_speed_kmh() / 3.6
	var v_axial := top_mps * sin(TOP_SPEED_LEAN_RAD)
	var max_rpm := max_rpm_at_nominal()
	var v_edge := top_mps * cos(TOP_SPEED_LEAN_RAD)
	var remaining := forward_ratios().thrust_ratio(max_rpm, v_axial, v_edge)

	if remaining >= UNLOADING_WORTH_NAMING:
		return out

	out.append(BuildWarning.characteristic(&"prop_unloading",
		"The %s is steep for these motors — at its own top speed this build's props are down to %.0f%% of the thrust they make on a stand, because the aircraft is flying at %.0f%% of the speed the blade would screw itself forward at. A lower-pitch prop, or more RPM, buys back the top end." % [
			propeller["name"], remaining * 100.0,
			PropellerModel.advance_ratio(max_rpm, geometry.diameter_m, v_axial)
				/ PropellerModel.j_zero(geometry.diameter_m, geometry.pitch_m) * 100.0],
		{"thrust_fraction_at_top_speed": remaining,
			"advance_ratio": PropellerModel.advance_ratio(max_rpm, geometry.diameter_m, v_axial),
			"j_zero": PropellerModel.j_zero(geometry.diameter_m, geometry.pitch_m),
			"top_speed_kmh": top_speed_kmh()}))
	return out


func _flight_quality() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	if not can_hover():
		# WHERE it cannot hover matters, and saying only "it will not leave the ground" to a builder
		# whose design is fine at sea level would be the cinelifter bug in a new place: a true
		# sentence that leads to the wrong action. They would go and buy different motors when what
		# they have is a perfectly good aircraft for a lower field.
		#
		# The twin is built ONLY on this branch and only when the air is non-standard, so the common
		# path costs nothing. It cannot recurse: the twin is at standard air, and this block is the
		# only caller of at_air().
		var ground := "This build cannot lift its own %.0f g — it will not leave the ground." % all_up_weight_g()
		var detail := {"all_up_weight_g": all_up_weight_g(), "twr": thrust_to_weight(),
			"reachable_twr": peak_thrust()["thrust_n"] / weight_n()}
		if not air.is_standard():
			var sea_level := at_air(AirDensity.standard())
			if sea_level.can_hover():
				ground = "This build cannot lift its own %.0f g AT THIS FIELD — %.0f m and %.0f °C is %.3f kg/m³, %.1f%% less air than sea level. The same aircraft hovers at %.0f%% throttle at sea level, %.1f:1. It is the field, not the parts." % [
					all_up_weight_g(), air.elevation_m, air.temperature_c, air.kgm3(),
					air.fraction_below_standard() * 100.0,
					sea_level.hover_throttle() * 100.0, sea_level.thrust_to_weight()]
				detail["twr_at_sea_level"] = sea_level.thrust_to_weight()
				detail["hover_throttle_at_sea_level"] = sea_level.hover_throttle()
		out.append(BuildWarning.impossible(&"cannot_hover", ground, detail))
		# Climb margin and headroom are statements about flight, and there is none. Printing
		# "climbs at -2 m/s^2" beneath "it will not leave the ground" would be arithmetic, not
		# information.
		return out

	var climb := climb_margin_mps2()
	out.append(BuildWarning.characteristic(&"climb_margin",
		"Thrust-to-weight %.1f:1 — %.1f m/s%s of climb available above hover, about %.1f g." % [
			thrust_to_weight(), climb, "²", climb / GRAVITY_MPS2],
		{"twr": thrust_to_weight(), "climb_accel_mps2": climb,
			"climb_g": climb / GRAVITY_MPS2}))

	# Two wordings for one figure, because "past that" is not a true clause when there is no past
	# that: a build with the whole range in hand should read as having it, rather than as having
	# 100% of something it is about to run out of.
	var demand := attitude_demand_at_hover()
	var headroom := "Hover sits at %.0f%% throttle and holds it through any input the mixer can ask for." % [
		hover_throttle() * 100.0]
	if demand < 1.0:
		headroom = "Hover sits at %.0f%% throttle, and holds it through %.0f%% of a full roll-pitch-yaw demand — past that the mixer keeps the attitude and gives up the collective." % [
			hover_throttle() * 100.0, demand * 100.0]
	out.append(BuildWarning.characteristic(&"manoeuvre_headroom", headroom,
		{"hover_throttle": hover_throttle(), "attitude_demand_fraction": demand}))

	return out


## What the air at this field is, and what it costs — with units, and no judgement.
##
## CHARACTERISTIC, and it could not honestly be anything else. There is no boundary in air density:
## 900 m is not a different kind of place from 800 m, and any elevation at which Lothal started
## calling a field a problem would be a picked constant describing the taste of whoever typed it
## rather than the aircraft — the 2.0:1 thrust-to-weight mistake relocated to geography. Everything
## that BINDS is already reported by the branches above, evaluated at this air: a build that cannot
## hover here says so, and one whose hover throttle has eaten its attitude headroom says that.
## This warning's whole job is to make the reason legible.
##
## Silent at standard air. A course at sea level saying "0.0% below sea level" is a line of text
## that reports nothing, and the warning list is not a status bar.
func _field_air() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if air.is_standard():
		return out

	var fraction := air.fraction_below_standard()
	# Thrust is linear in density (T = C_T·ρ·n²·D⁴), so the thrust statement is exactly the density
	# statement and is quoted as the same number rather than as a second calculation.
	out.append(BuildWarning.characteristic(&"field_air",
		"This course is at %.0f m and %.0f °C — %.3f kg/m³, %.1f%% %s sea-level air. Thrust is linear in air density, so every figure here is quoted %.1f%% %s than the same build at sea level." % [
			air.elevation_m, air.temperature_c, air.kgm3(),
			absf(fraction) * 100.0, "below" if fraction > 0.0 else "above",
			absf(fraction) * 100.0, "lower" if fraction > 0.0 else "higher"],
		{"elevation_m": air.elevation_m, "temperature_c": air.temperature_c,
			"air_density_kgm3": air.kgm3(), "fraction_below_standard": fraction}))
	return out


## Upward acceleration available above hover, in m/s^2. Whatever thrust is not holding the aircraft
## up is free to accelerate it, so this is exactly g(TWR - 1) — a physical statement with units,
## and one that needs no threshold to be worth printing.
func climb_margin_mps2() -> float:
	return GRAVITY_MPS2 * (thrust_to_weight() - 1.0)


## How much of a full simultaneous roll-pitch-yaw demand this build can absorb while still HOLDING
## its hover throttle, as a fraction of full command. 1.0 means the stick can go anywhere and the
## aircraft keeps its altitude authority.
##
## This is the honest reason a high hover throttle matters, and it is derived from the mixer rather
## than asserted. MotorMixer gives attitude priority over collective (airmode, see its header): it
## builds the per-motor attitude deltas first, then shifts the collective until they fit inside
## [0, 1]. So the throttle actually delivered is capped at 1 - hi, where hi is the largest delta,
## and a build hovering above that cap sinks whenever the pilot asks for that much attitude.
##
## Bisected against MotorMixer.mix() itself rather than solved from MIX_GAIN, so that if the mixing
## strategy changes — a different gain, a different airmode policy, renormalisation — this figure
## follows it instead of quietly describing a mixer that no longer exists.
func attitude_demand_at_hover() -> float:
	var hover := hover_throttle()
	if _holds_collective(hover, 1.0):
		return 1.0

	var low := 0.0
	var high := 1.0
	for _i in 40:
		var mid := (low + high) * 0.5
		if _holds_collective(hover, mid):
			low = mid
		else:
			high = mid
	return low


## Does the mixer still deliver the commanded collective at this demand? The three mix rows each
## sum to zero across the four motors, so the mean of the mixed commands IS the collective the
## mixer settled on — below the command means it has started trading throttle for attitude.
func _holds_collective(throttle: float, demand: float) -> bool:
	var mixed := MotorMixer.mix(throttle, demand, demand, demand)
	var total := 0.0
	for name in MotorLayout.MOTOR_NAMES:
		total += float(mixed[name])
	return total / 4.0 >= throttle - 1e-6
