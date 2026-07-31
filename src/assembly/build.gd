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
const AIR_DENSITY_KGM3 := 1.225

## Fixed electronics package (parts.md): FC+ESC stack, camera, VTX, antenna, receiver,
## wiring. Not selectable in v1, but it is 55 g of real mass, so it stays in the
## mass-properties calculation. A constant, not an omission.
const ELECTRONICS_MASS_G := 55.0
const ELECTRONICS_SIZE_M := Vector3(0.030, 0.015, 0.030)

## The FC/ESC stack's own bolt pattern. 30.5x30.5 is the full-size standard, and it is a property
## of the STACK rather than of the frame — which is the whole reason a fit check is worth having.
## Buy the wrong one and it does not bolt to your frame; frames.json drills the 3.5" freestyle
## 20x20 and the whoops 25.5x25.5, and none of those take this board.
##
## Not selectable yet. Unbundling the electronics into separately choosable parts needs an ESC
## bench and current-headroom checking, and that is its own slice.
const STACK_MOUNT_PATTERN := "30.5x30.5"


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

## Top speed is quoted at a sustained 45-degree lean. Not the geometric maximum — at an
## 11:1 thrust-to-weight the geometric maximum is an 85-degree lean, which no pilot holds
## and which this model (no prop unloading at speed) would badly over-predict. 45 degrees
## is the lean a speed run actually sits at.
const TOP_SPEED_LEAN_RAD := 0.7853982

## Hover is the cheapest thing a quad ever does. Real flying averages well above it, and
## packs are landed with reserve rather than run flat.
const FLIGHT_CURRENT_TO_HOVER_RATIO := 1.6
const USABLE_CAPACITY_FRACTION := 0.80

var frame: Dictionary
var motor: Dictionary
var propeller: Dictionary
var battery: Dictionary
var catalog: PartsCatalog

var arm_m: float
var mass_properties: MassProperties
var k_t: float
var k_q: float
## Motor max_amps adjusted for the selected prop: current tracks shaft torque, so a prop
## that demands more torque at a given RPM also draws more current than the one the
## motor's amp figure was measured with.
var effective_max_amps: float
var drag_coefficient: float

static func from_ids(p_catalog: PartsCatalog, frame_id: String, motor_id: String, prop_id: String, battery_id: String) -> Build:
	var b := Build.new()
	b.catalog = p_catalog
	b.frame = p_catalog.get_part(frame_id)
	b.motor = p_catalog.get_part(motor_id)
	b.propeller = p_catalog.get_part(prop_id)
	b.battery = p_catalog.get_part(battery_id)
	b._recompute()
	return b

func _recompute() -> void:
	arm_m = float(frame["specs"]["arm_mm"]) / 1000.0

	# --- Thrust coefficient, fit from the manufacturer table, then moved to this prop ---
	# physics.md §4 is explicit that C_T must be fit from published thrust tables rather
	# than guessed. A motor's headline thrust figure is only meaningful together with the
	# prop and pack it was measured on, so motors.json names both. Fit k_t for that exact
	# pairing, then rescale it to whatever prop is actually fitted.
	var test_prop: Dictionary = catalog.get_part(motor["thrust_test"]["prop_id"])
	var test_voltage: float = float(motor["thrust_test"]["voltage_v"])
	var test_max_rpm: float = float(motor["specs"]["kv"]) * test_voltage
	var k_t_at_test_prop := PropellerModel.fit_k_t(float(motor["specs"]["max_thrust_g"]), test_max_rpm)

	k_t = PropellerModel.scale_k_t_to_prop(k_t_at_test_prop, _prop_geometry(test_prop), _prop_geometry(propeller))
	k_q = PropellerModel.fit_k_q(k_t, _prop_geometry(propeller).diameter_m)

	var k_q_at_test_prop := PropellerModel.fit_k_q(k_t_at_test_prop, _prop_geometry(test_prop).diameter_m)
	effective_max_amps = float(motor["specs"]["max_amps"]) * (k_q / k_q_at_test_prop)

	var drag_area_m2: float = REFERENCE_DRAG_AREA_M2 * pow(arm_m / REFERENCE_ARM_M, 2.0)
	drag_coefficient = 0.5 * AIR_DENSITY_KGM3 * drag_area_m2

	mass_properties = MassProperties.compute(mass_parts())


## The FITTED prop's geometry in SI. Public because anything assembling a powertrain needs
## the blade count and radius the audio and the rotor mesh are driven from, and recovering
## them from the raw catalog dictionary at each call site would be a second copy of the
## inch-to-metre conversion.
func prop_geometry() -> Dictionary:
	return _prop_geometry(propeller)


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
		parts.append(PartMass.new(motor_prop_mass_kg, MotorLayout.motor_position(name, arm_m), motor_inertia))

	var frame_mass_kg := float(frame["mass_g"]) / 1000.0
	var plate := arm_m * FRAME_PLATE_TO_ARM_RATIO
	var frame_size := Vector3(plate, FRAME_PLATE_THICKNESS_M, plate)
	parts.append(PartMass.new(frame_mass_kg, Vector3.ZERO, InertiaPrimitives.box(frame_mass_kg, frame_size)))

	var battery_mass_kg := float(battery["mass_g"]) / 1000.0
	parts.append(PartMass.new(battery_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(battery_mass_kg, battery_size_m())))

	var electronics_mass_kg := ELECTRONICS_MASS_G / 1000.0
	parts.append(PartMass.new(electronics_mass_kg, Vector3.ZERO, InertiaPrimitives.box(electronics_mass_kg, ELECTRONICS_SIZE_M)))

	return parts


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
func max_throttle_fraction() -> float:
	var rated_amps: float = float(motor["specs"]["max_amps"])
	var full_throttle_amps := 4.0 * effective_max_amps
	if full_throttle_amps <= 0.0:
		return 1.0
	return clampf(sqrt((4.0 * rated_amps) / full_throttle_amps), 0.0, 1.0)

func motor_model() -> MotorModel:
	return MotorModel.new(float(motor["specs"]["kv"]), max_throttle_fraction())

func battery_model() -> BatteryModel:
	return BatteryModel.new(
		float(battery["specs"]["nominal_v"]),
		float(battery["specs"]["internal_r_ohm"]),
		float(battery["specs"]["mah"]),
		int(battery["specs"].get("cells", 0)),
		str(battery["specs"].get("chemistry", BatteryModel.DEFAULT_CHEMISTRY))
	)

func build_drone_core() -> DroneCore:
	var geometry := _prop_geometry(propeller)
	return DroneCore.new(mass_properties, motor_model(), arm_m, k_t, k_q, battery_model(),
		effective_max_amps, rated_rpm(), drag_coefficient,
		pole_pairs(), geometry.blades, geometry.diameter_m * 0.5)

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
func max_total_thrust_n() -> float:
	var max_rpm: float = float(motor["specs"]["kv"]) * float(battery["specs"]["nominal_v"]) * max_throttle_fraction()
	return 4.0 * PropellerModel.thrust_n(k_t, max_rpm)

func thrust_to_weight() -> float:
	return max_total_thrust_n() / weight_n()

## Steady-state total thrust at a given throttle, with the pack sagging under the current
## that throttle draws. This is deliberately NOT monotonic: on a high-resistance pack,
## past some throttle the extra current costs more voltage than the extra command buys,
## and thrust peaks and then falls. That is the Li-ion entry's whole reason to exist, and
## it is why hover is solved by bracketing rather than by iterating a fixed point — the
## fixed point diverges on exactly the packs the catalog includes to be interesting.
func thrust_at_throttle_n(throttle: float) -> float:
	return 4.0 * PropellerModel.thrust_n(k_t, rpm_at_throttle(throttle))

## Steady-state RPM at a throttle command. RPM and pack sag depend on each other, but the
## loop converges quickly: more sag means less RPM means less current means less sag.
func rpm_at_throttle(throttle: float) -> float:
	var t := clampf(throttle, 0.0, max_throttle_fraction())
	var kv: float = float(motor["specs"]["kv"])
	var nominal_v: float = float(battery["specs"]["nominal_v"])
	var internal_r: float = float(battery["specs"]["internal_r_ohm"])

	var voltage_v := nominal_v
	var rpm := 0.0
	for _i in 12:
		rpm = t * kv * voltage_v
		voltage_v = maxf(nominal_v - current_at_rpm(rpm) * 4.0 * internal_r, 0.0)
	return rpm

## Current drawn by one motor at a given RPM — see DroneCore.current_at_rpm, which this
## must agree with exactly, or the HUD's numbers and the flight model's numbers diverge.
func current_at_rpm(rpm: float) -> float:
	var fraction := rpm / rated_rpm()
	return effective_max_amps * fraction * fraction

## The RPM at which this motor draws its rated amps with the prop actually fitted: KV times
## the pack voltage the manufacturer's amp figure was measured at.
func rated_rpm() -> float:
	return float(motor["specs"]["kv"]) * float(motor["thrust_test"]["voltage_v"])

## Throttle at which sagged thrust peaks, and that peak. Everything above this throttle is
## the pack losing the argument with the motors.
func peak_thrust() -> Dictionary:
	var best_throttle := 0.0
	var best_thrust := 0.0
	var cap := max_throttle_fraction()
	var samples := 400
	for i in range(samples + 1):
		var t := cap * float(i) / float(samples)
		var thrust := thrust_at_throttle_n(t)
		if thrust > best_thrust:
			best_thrust = thrust
			best_throttle = t
	return {"throttle": best_throttle, "thrust_n": best_thrust}

## True when the build can actually generate its own weight in thrust, sag included.
func can_hover() -> bool:
	return peak_thrust()["thrust_n"] > weight_n()

## Steady-state hover throttle: bisected on the rising branch of thrust_at_throttle_n,
## so it is the LOWER of the two throttles that produce hover thrust — the stable one.
## Returns the peak-thrust throttle for a build that cannot hold itself up, which reads as
## "flat out and still sinking" rather than as a number that was quietly clamped.
func hover_throttle() -> float:
	var peak := peak_thrust()
	var target_n := weight_n()
	if peak["thrust_n"] <= target_n:
		return peak["throttle"]

	var low := 0.0
	var high: float = peak["throttle"]
	for _i in 60:
		var mid := (low + high) * 0.5
		if thrust_at_throttle_n(mid) < target_n:
			low = mid
		else:
			high = mid
	return high

## Total pack current at a throttle command, via the RPM that throttle actually reaches.
func hover_current_a(throttle: float) -> float:
	return 4.0 * current_at_rpm(rpm_at_throttle(throttle))

## Zero for a build that cannot hover — there is no flight to put a time on.
func flight_time_min() -> float:
	if not can_hover():
		return 0.0
	var average_current_a := hover_current_a(hover_throttle()) * FLIGHT_CURRENT_TO_HOVER_RATIO
	if average_current_a <= 0.0:
		return 0.0
	var usable_mah: float = float(battery["specs"]["mah"]) * USABLE_CAPACITY_FRACTION
	return (usable_mah / (average_current_a * 1000.0)) * 60.0

## Terminal speed at the reference lean: horizontal thrust balances aerodynamic drag.
func top_speed_kmh() -> float:
	var horizontal_thrust_n := weight_n() * tan(TOP_SPEED_LEAN_RAD)
	horizontal_thrust_n = minf(horizontal_thrust_n, max_total_thrust_n() * sin(TOP_SPEED_LEAN_RAD))
	return sqrt(horizontal_thrust_n / drag_coefficient) * 3.6


# ---------------------------------------------------------------------------
# Compatibility: warn, never block (parts.md). "What happens if I put 7-inch props on a
# race frame" is exactly the curiosity that makes a builder sim worth using, and the sim
# answering "it barely lifts and the inertia is awful" teaches more than a greyed-out
# dropdown ever would.
# ---------------------------------------------------------------------------

func warnings() -> Array[String]:
	var out: Array[String] = []

	var prop_inches: float = float(propeller["specs"]["diameter_inches"])
	var max_prop_inches: float = float(frame["specs"]["max_prop_inches"])
	if prop_inches > max_prop_inches:
		out.append("%s props exceed the %s's %.1f\" clearance — they would strike the frame." % [
			propeller["name"], frame["name"], max_prop_inches])

	if motor.get("mount_pattern", "") != frame["specs"].get("motor_mount", ""):
		out.append("%s uses a %s mount; the %s is drilled %s." % [
			motor["name"], motor.get("mount_pattern", "?"), frame["name"], frame["specs"].get("motor_mount", "?")])

	var throttle_cap := max_throttle_fraction()
	if throttle_cap < 0.99:
		out.append("%s is too much prop for the %s — it hits its %.0f A limit at %.0f%% throttle." % [
			propeller["name"], motor["name"], float(motor["specs"]["max_amps"]), throttle_cap * 100.0])

	# Thrust-to-weight is a bench number at nominal voltage (see max_total_thrust_n). On a
	# high-resistance pack the thrust actually reachable is far below it, which would
	# otherwise surface as the baffling combination of a healthy TWR next to a drone that
	# will not fly. Say it out loud instead — this is the lesson the Li-ion is here to teach.
	var reachable_thrust_n: float = peak_thrust()["thrust_n"]
	var usable_fraction := reachable_thrust_n / max_total_thrust_n()
	if usable_fraction < 0.75:
		out.append("The %s sags hard under load — only %.0f%% of that %.1f:1 bench figure is reachable, or %.1f:1 in the air." % [
			battery["name"], usable_fraction * 100.0, thrust_to_weight(),
			reachable_thrust_n / weight_n()])

	if not can_hover():
		out.append("This build cannot lift its own %.0f g — it will not leave the ground." % all_up_weight_g())
	elif thrust_to_weight() < 2.0:
		out.append("Thrust-to-weight is only %.1f:1 — this will barely leave the ground." % thrust_to_weight())
	elif hover_throttle() > 0.6:
		out.append("Hover throttle is %.0f%% — almost no headroom left to manoeuvre." % (hover_throttle() * 100.0))

	return out
