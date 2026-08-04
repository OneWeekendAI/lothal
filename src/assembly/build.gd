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

## How far the reachable thrust may fall below the bench figure before warnings() names the pack.
##
## A PICKED CONSTANT, and flagged as one deliberately. It is not a boundary in the physics — sag is
## a continuum, and every pack is somewhere on it. What it marks is the point at which the bench
## figure stops being a useful prediction of the aircraft, which is a judgement about a reader
## rather than about a battery. It survives as a threshold only because what it gates is a
## LIMITING statement that names the binding part, and the two figures either side of it are both
## printed in the sentence — so a builder reading it can see the continuum the constant sits on.
const SAG_WORTH_NAMING := 0.75

## Fixed electronics package (parts.md): FC+ESC stack, camera, VTX, antenna, receiver,
## wiring. Not selectable in v1, but it is 55 g of real mass, so it stays in the
## mass-properties calculation. A constant, not an omission.
##
## THIS IS A BUDGET, AND IT DOES NOT GROW. As components come out of the lump and get physical
## form, they take their share OUT of this number rather than being added beside it — see
## STACK_MASS_G below and mass_parts(). The reference build's 496 g, 11.7:1 and 29% hover were
## computed with the whole 55 g included, so a component that gained mass on its way to becoming
## visible would silently move two of the project's three fixed points for what was meant to be a
## change to the picture.
const ELECTRONICS_MASS_G := 55.0
## The part of the lump still lumped: camera, VTX, antenna, receiver and wiring, as one box at the
## origin. Its SIZE stayed as it was rather than shrinking with the mass — an inertia box is linear
## in mass, and the stack's own box below carries the difference honestly.
const ELECTRONICS_SIZE_M := Vector3(0.030, 0.015, 0.030)

## The FC/ESC stack's share of that budget, straight off parts.md's published breakdown of the
## fixed electronics package rather than re-estimated here. Taken OUT of ELECTRONICS_MASS_G, not
## added to it, which leaves 43 g of camera, VTX, antenna, receiver and wiring lumped at the origin.
## The FLIGHT CONTROLLER's share of that budget. Was 12 g of "FC/ESC stack" while the two were one
## lumped constant; unbundling the ESC into a catalog part forced honest figures for both, and a
## real F4 board is about 8 g against a real 45 A 4-in-1's 12 g.
const FC_MASS_G := 8.0

## The ESC's BUDGETED share, which is what the lump gives up rather than what any particular board
## weighs. The reference build's 45 A 4-in-1 weighs exactly this, so its 496 g is unchanged to the
## gram; fit the 80 A board instead and the aircraft gets 6 g heavier, which is the right answer and
## the whole reason the ESC stopped being a constant.
const ESC_BUDGET_MASS_G := 12.0

## Kept as the sum of the two, because several places still speak of "the stack" as one object —
## it is still one object on the aircraft, bolted through one pattern.
const STACK_MASS_G := FC_MASS_G + ESC_BUDGET_MASS_G

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

## Passed as `open_circuit_v` to mean "at the pack's NOMINAL voltage" — the datum every figure on
## the stats panel is quoted at, and the one the 11.7:1 and 29% oracles are defined at
## (physics.md §5). It is the default everywhere, so the analytic layer answers the spec-sheet
## question unless a caller explicitly asks a different one.
##
## A sentinel rather than an overload because the alternative is two near-identical solvers, and
## the project has already paid for one number having two expressions. Negative because no pack
## rests at a negative voltage, so it cannot collide with a real reading.
const AT_NOMINAL := -1.0

## Hover is the cheapest thing a quad ever does. Real flying averages well above it, and
## packs are landed with reserve rather than run flat.
const FLIGHT_CURRENT_TO_HOVER_RATIO := 1.6
const USABLE_CAPACITY_FRACTION := 0.80

var frame: Dictionary
var motor: Dictionary
var propeller: Dictionary
var battery: Dictionary
var esc: Dictionary
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

static func from_ids(p_catalog: PartsCatalog, frame_id: String, motor_id: String, prop_id: String,
		battery_id: String, esc_id: String = DEFAULT_ESC_ID) -> Build:
	var b := Build.new()
	b.catalog = p_catalog
	b.frame = p_catalog.get_part(frame_id)
	b.motor = p_catalog.get_part(motor_id)
	b.propeller = p_catalog.get_part(prop_id)
	b.battery = p_catalog.get_part(battery_id)
	b.esc = p_catalog.get_part(esc_id)
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
		parts.append(PartMass.new(motor_prop_mass_kg, MotorLayout.motor_position(name, arm_m),
			motor_inertia, "Motor + prop %s" % name))

	var frame_mass_kg := float(frame["mass_g"]) / 1000.0
	var plate := arm_m * FRAME_PLATE_TO_ARM_RATIO
	var frame_size := Vector3(plate, FRAME_PLATE_THICKNESS_M, plate)
	parts.append(PartMass.new(frame_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(frame_mass_kg, frame_size), "Frame"))

	var battery_mass_kg := float(battery["mass_g"]) / 1000.0
	parts.append(PartMass.new(battery_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(battery_mass_kg, battery_size_m()), "Pack"))

	# The electronics, in two entries that sum to ELECTRONICS_MASS_G exactly. The stack is separate
	# because it is now a real object with a real footprint, and its 36.5 mm board has a different
	# tensor from the 30 mm cube the lump stands on; the two together weigh what the one did.
	#
	# BOTH ARE AT THE ORIGIN, and that is the point of labs-and-sim.md §2.5 rather than an
	# oversight. The stack is DRAWN between the plates, below the centreline, and the mass model
	# does not hear about that: it is a lumped centre box plus four point masses and has no term a
	# mount offset could enter. When it grows a real centre-of-gravity term, the mount point is
	# already the single source for where the stack is — a consumer gets added, nothing gets
	# re-decided.
	var fc_mass_kg := FC_MASS_G / 1000.0
	parts.append(PartMass.new(fc_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(fc_mass_kg, StackMesh.size_m(STACK_MOUNT_PATTERN)), "Flight controller"))

	# The ESC at its OWN catalog mass, on its own footprint. This is the line that makes fitting a
	# bigger board cost something: the budget below gave up ESC_BUDGET_MASS_G, and whatever this
	# board actually weighs is what the aircraft carries.
	var esc_mass_kg := esc_mass_g() / 1000.0
	parts.append(PartMass.new(esc_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(esc_mass_kg, StackMesh.size_m(esc_mount_pattern())), "ESC"))

	var loose_mass_kg := (ELECTRONICS_MASS_G - FC_MASS_G - ESC_BUDGET_MASS_G) / 1000.0
	parts.append(PartMass.new(loose_mass_kg, Vector3.ZERO,
		InertiaPrimitives.box(loose_mass_kg, ELECTRONICS_SIZE_M), "Wiring and electronics"))

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
	var full_throttle_amps := 4.0 * effective_max_amps
	if full_throttle_amps <= 0.0 or total_amps <= 0.0:
		return 1.0
	return clampf(sqrt(total_amps / full_throttle_amps), 0.0, 1.0)


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
	var binding: Dictionary = candidates[0]
	for candidate in candidates:
		if candidate["throttle"] < binding["throttle"]:
			binding = candidate
	return binding

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
	var max_rpm: float = float(motor["specs"]["kv"]) * float(battery["specs"]["nominal_v"]) * motor_throttle_limit()
	return 4.0 * PropellerModel.thrust_n(k_t, max_rpm)

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
	var t := clampf(throttle, 0.0, max_throttle_fraction())
	var kv: float = float(motor["specs"]["kv"])
	var rest_v := resolve_open_circuit_v(open_circuit_v)
	var internal_r: float = float(battery["specs"]["internal_r_ohm"])

	var voltage_v := rest_v
	var rpm := 0.0
	for _i in 12:
		rpm = t * kv * voltage_v
		voltage_v = maxf(rest_v - current_at_rpm(rpm) * 4.0 * internal_r, 0.0)
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

## Zero for a build that cannot hover — there is no flight to put a time on.
func flight_time_min() -> float:
	if not can_hover():
		return 0.0
	var average_current_a := hover_current_a(hover_throttle()) * FLIGHT_CURRENT_TO_HOVER_RATIO
	if average_current_a <= 0.0:
		return 0.0
	var usable_mah: float = float(battery["specs"]["mah"]) * USABLE_CAPACITY_FRACTION
	return (usable_mah / (average_current_a * 1000.0)) * 60.0

## How much flying is LEFT in a pack in the state it is actually in, in minutes.
##
## The same convention as flight_time_min() — average current is hover current times
## FLIGHT_CURRENT_TO_HOVER_RATIO, and only USABLE_CAPACITY_FRACTION of the pack is flown — so the
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
	var average_current_a := hover_current_a(hover_throttle(rest_v), rest_v) * FLIGHT_CURRENT_TO_HOVER_RATIO
	if average_current_a <= 0.0:
		return 0.0
	var usable_mah := pack.capacity_mah * USABLE_CAPACITY_FRACTION - pack.used_mah
	if usable_mah <= 0.0:
		return 0.0
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

	# The board has to bolt to the frame, which is the same check the motors already get and the
	# same mistake someone makes exactly once: a 20x20 board and a 30.5x30.5 frame do not meet.
	var frame_stack: String = str(frame["specs"].get("stack_mount", ""))
	if frame_stack != "" and esc_mount_pattern() != frame_stack:
		out.append(BuildWarning.impossible(&"stack_mount",
			"%s is a %s board; the %s is drilled %s for its stack." % [
				esc.get("name", "The ESC"), esc_mount_pattern(), frame["name"], frame_stack],
			{"board_pattern": esc_mount_pattern(), "frame_pattern": frame_stack}))

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

	out.append_array(_flight_quality())
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
func _flight_quality() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	if not can_hover():
		out.append(BuildWarning.impossible(&"cannot_hover",
			"This build cannot lift its own %.0f g — it will not leave the ground." % all_up_weight_g(),
			{"all_up_weight_g": all_up_weight_g(), "twr": thrust_to_weight(),
				"reachable_twr": peak_thrust()["thrust_n"] / weight_n()}))
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
