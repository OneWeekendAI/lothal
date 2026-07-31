class_name ReferenceBuild
extends RefCounted
## The canonical 5" freestyle quad from docs/lothal/parts.md — the fixture every
## mass-properties and motor/propeller test is checked against. Hand-verified on paper
## before any code was written: 496 g all-up, 11.7:1 thrust-to-weight, 29% hover throttle.
##
## Since day 5 this is no longer a hard-coded parts list: it is a named SELECTION from the
## JSON catalog, so the fixture and the thing the user assembles in the UI are the same
## code path. If loading the catalog or the parts pipeline breaks, the day 2 oracle tests
## fail — which is exactly the coupling worth having.

const FRAME_ID := "frame_5in_freestyle"
const MOTOR_ID := "motor_2207_1960kv"
const PROPELLER_ID := "prop_5x43x3"
const BATTERY_ID := "battery_4s_1500"

## Values the day 2-4 tests refer to directly. Kept as named constants rather than JSON
## lookups so a test failure points at the physics, not at a dictionary key.
const MOTOR_KV := 1960.0
const BATTERY_NOMINAL_V := 14.8
const MOTOR_MAX_AMPS := 32.0

static func build() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), FRAME_ID, MOTOR_ID, PROPELLER_ID, BATTERY_ID)

static func arm_m() -> float:
	return build().arm_m

static func mass_parts() -> Array:
	return build().mass_parts()

static func motor_model() -> MotorModel:
	return build().motor_model()

static func battery_model() -> BatteryModel:
	return build().battery_model()

static func propeller_k_t() -> float:
	return build().k_t

static func propeller_k_q() -> float:
	return build().k_q

static func build_drone_core() -> DroneCore:
	return build().build_drone_core()

## Steady-state hover throttle command (0..1) — the value each motor should sit at, hands-off,
## once RPM has settled, ON A FRESH PACK. Solved against the sagged voltage of a full battery,
## which is what scenes/main.gd rests the throttle stick at when you spawn with one.
##
## NOT the 29% oracle, and the difference is the point of the nominal-voltage datum
## (physics.md §5). The oracle is Build.hover_throttle(), quoted at nominal voltage the way a
## spec sheet is; a full 4S rests at 16.8 V rather than 14.8, so it needs about three points less
## throttle than the sheet says. Every flight test in tests/ takes its throttle from here, and
## they are all asking the flying question — what does the stick sit at — rather than the
## spec-sheet one.
static func hover_throttle() -> float:
	var b := build()
	return b.hover_throttle_for(b.battery_model())
