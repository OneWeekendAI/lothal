class_name FrameBench
extends RefCounted
## The frame bench (labs-and-sim.md §2.1) — what a frame does to the aircraft's ROTATION, which is
## the one major design lever Lothal computed on every part change and showed nobody.
##
## ---------------------------------------------------------------------------
## WHAT IS UNDER TEST
## ---------------------------------------------------------------------------
##
## The frame CARRYING ITS BUILD, never a bare frame. An empty frame has no interesting inertia: on
## a 5" freestyle the four motor/prop assemblies and the pack account for most of the roll figure
## and the 110 g plate itself contributes a minority of it. So the unit under test is the assembled
## aircraft attributed to its frame, exactly as the thrust stand tests a pairing rather than a motor.
##
## ---------------------------------------------------------------------------
## THE RESULT THIS EXISTS TO MAKE VISIBLE
## ---------------------------------------------------------------------------
##
## Motor torque about the roll axis scales with arm LENGTH — the motors are further out, so they
## have more leverage. Roll inertia scales with arm length SQUARED, because the parallel axis
## theorem squares the offset. So angular acceleration
##
##     alpha = tau / I  ~  arm / arm^2  =  1 / arm
##
## and a longer-armed aircraft rolls SLOWER despite having more leverage. Inertia wins the exponent.
## frames.json's own schema has said arm_mm "is the sleeper spec" since the catalog was written;
## this is the bench that lets a builder feel it.
##
## BOTH TERMS ARE DERIVED, and that is load-bearing. The torque comes from the four real motors at
## their real positions, through MotorMixer and MotorLayout, against the real thrust the powertrain
## is producing. Driving the step with a constant test torque would make every frame's response
## differ only by inertia — which would still show the right direction, and would hide the half of
## the lesson where the long arm has more leverage and loses anyway.
##
## ---------------------------------------------------------------------------
## WHAT THE STEP RESPONSE IS, EXACTLY
## ---------------------------------------------------------------------------
##
## Inertia cannot be felt statically, only as how hard it is to START rotating. So the bench trims
## the four motors at a hover collective, throws full stick on one axis, and reports what the
## aircraft does about it.
##
## It is a RIG WITH ONE AXIS FREE — the software equivalent of the bifilar pendulum a builder hangs
## an airframe from to measure its moment of inertia. There is no rigid body here, no translation,
## no gravity, no flight controller and no DroneCore: the aircraft cannot go anywhere, it can only
## turn. §6's "Lab does not fly" is intact, and tests/test_frame_bench.gd holds the bench to the
## simulator's own answer so the absence costs no accuracy.
##
## Nothing in here is a new physics model. The inertia is MassProperties'. The torque is
## MotorLayout's. The thrust is Powertrain's. The only arithmetic this file owns is alpha = tau / I
## and the accumulation of a rate from it, which is the MEASUREMENT the bench takes — the same
## thing timing a pendulum's swing is.
##
## ---------------------------------------------------------------------------
## THE MOTORS REALLY TURN, SO THE RUN REALLY COSTS
## ---------------------------------------------------------------------------
##
## A step response asks four motors for four different throttles and they answer with real RPM,
## real thrust and real current out of a real pack (labs-and-sim.md §5). The pack drains, the rotors
## turn on the rate the powertrain hands them, and the bench is audible through the existing
## Observables path with no change to any file under src/audio/.

const AXIS_ROLL := 0
const AXIS_PITCH := 1
const AXIS_YAW := 2
const AXIS_NAMES := ["roll", "pitch", "yaw"]

## The rate the step runs to. 500 deg/s is the same step tests/test_rate_step_response.gd grades the
## rate loop against, so "how long to reach it" is a number that already means something in this
## project rather than one chosen for this screen.
const TARGET_RATE_DEG_S := 500.0

## THE RUN ENDS WHEN THE TARGET RATE IS REACHED. This is a cap on the measurement, not on the
## physics: full stick held open-loop really does keep accelerating, and a real quad flicked into a
## flip really does keep speeding up until something stops it. But past a few hundred deg/s the
## number stops meaning anything to a pilot — no airframe in this catalog is flown there, and a
## gyro clips around 2000 deg/s — so a run held for a fixed duration produces five figures of
## deg/s, an axis rescaled to fit them, and every frame's curve flattened into the same shape.
##
## Stopping at the rate is also what makes the chart the comparison it is meant to be: every line
## climbs to the same 500 deg/s, and the only thing that differs between two frames is HOW LONG it
## took them — which is exactly the quantity a pilot feels and the one the panel headlines.
##
## RUN_SECONDS is the backstop for an airframe that never gets there, not the normal end of a run.
const RUN_SECONDS := 0.8

## Physics at 1 kHz, the same substep the flight loop and the other three benches use.
const PHYSICS_HZ := 1000.0
const MAX_SUBSTEPS := 300

## How long the motors are given to finish spooling when the SETTLED figure is taken. Comfortably
## past the ~30 ms electrical lag; torque climbs monotonically to its steady state, so this is the
## peak rather than a point on the way to it.
const SETTLE_SECONDS := 0.4

var build: Build
var powertrain: Powertrain
## The DRAWN airframe this bench is reporting on, or null to measure a throwaway one. Handed in by
## the screen so the clearance quoted on the panel is the clearance of the aircraft on screen —
## airframe_model.gd:193 is explicit that the geometry has one source and this is how it stays one.
var airframe: AirframeModel = null

var axis := AXIS_ROLL
var collective := 0.0
var running := false

## Accumulated state of the single free axis. Angle is carried so the screen can turn the airframe
## by exactly the amount the measurement says it turned, rather than by an animation.
var rate_rad_s := 0.0
var angle_rad := 0.0
var elapsed_s := 0.0

## THE AIRFRAME'S OWN NUMBERS, and deliberately not "the largest value seen during the last run".
##
## A peak read off the visible run would depend on how long that run happened to last, and the run
## stops the moment the target rate is reached — so a light airframe that got there in 25 ms would
## report a peak taken before its motors had finished spooling, and would look WEAKER than a heavy
## one that had time to settle. That is the exact inversion this bench exists to prevent.
##
## So these are taken once, at begin(), by spooling a scratch powertrain to steady state at the same
## full-stick commands. They are a property of the aircraft; the trace is what it did today.
var peak_alpha_rad_s2 := 0.0
var peak_torque_n_m := 0.0

## Every substep of the visible run, as [elapsed_s, rate_deg_s]. Held here rather than sampled by
## whoever is drawing, because a roll step is over in tens of milliseconds and a screen sampling it
## once a frame at 60 Hz would draw the whole response as three points.
var history: Array = []
## Seconds to reach TARGET_RATE_DEG_S, or -1 while it has not been reached.
var time_to_rate_s := -1.0
var _alpha_rad_s2 := 0.0


static func for_build(p_build: Build, p_airframe: AirframeModel = null) -> FrameBench:
	var bench := FrameBench.new()
	bench.build = p_build
	bench.airframe = p_airframe
	bench.powertrain = _powertrain_for(p_build)
	return bench


## The powertrain the step is run on — the build's own, exactly as the thrust stand and the battery
## bench assemble theirs. Its ceiling is Build.max_throttle_fraction(), unlike the ESC bench's:
## nothing here is measuring a current limit, so a motor that cannot be commanded past 62% in flight
## must not be commanded past it on this bench either, or the roll rate reported would be one the
## aircraft cannot reach.
static func _powertrain_for(p_build: Build) -> Powertrain:
	var geometry := p_build.prop_geometry()
	return Powertrain.new(
		p_build.motor_model(), p_build.k_t, p_build.k_q, p_build.battery_model(),
		p_build.effective_max_amps, p_build.rated_rpm(),
		p_build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5)


# ---------------------------------------------------------------------------
# The static half: what this aircraft's mass distribution IS, before anything is run.
# ---------------------------------------------------------------------------

## Roll, pitch and yaw inertia in kg*m^2, in the coordinate contract's own axes (physics.md §1:
## +Roll about -Z, +Pitch about +X, +Yaw about -Y). The tensor MassProperties builds is in body
## axes, so this is a re-labelling and never a recomputation — the mapping lives here once, for the
## same reason Gyro.contract_rates() lives in one place.
##
## All three, deliberately. On an X quad roll and pitch differ by less than most builders expect —
## the pack lying fore-and-aft is nearly the whole of the difference — while yaw is in a different
## regime entirely, at roughly the sum of the other two.
func inertia_kg_m2() -> Vector3:
	var tensor := build.mass_properties.inertia
	return Vector3(tensor.z.z, tensor.x.x, tensor.y.y)


## Where the mass actually sits, as an offset from the frame's geometric centre.
##
## For every build in the catalog this is exactly zero, and that is a REPORT rather than a bug: the
## mass model lumps the pack, the stack, the ESC and the loose electronics at the origin, and no
## mount position reaches it (build.gd's own comment on mass_parts() says so). Sliding the pack
## forward moves the picture and the fit warnings and not this. The bench states it rather than
## omitting it, because a builder who can see the pack hanging off the nose is entitled to know
## whether the physics has heard about it.
func com_offset_m() -> Vector3:
	return build.mass_properties.com_m


## Each part's share of ROLL inertia, largest first: its own local term plus the parallel-axis term
## m*d^2 about the roll axis, which is body Z.
##
## This is the row that answers "why is my build slow", and the answer is usually not the frame.
## The arithmetic is the same parallel-axis shift MassProperties applies, restricted to one axis —
## there is no second source for the shift itself, because there is nothing here to diverge FROM:
## the total is asserted against MassProperties' own tensor in the tests.
func roll_inertia_contributions() -> Array:
	var com := build.mass_properties.com_m
	var total := inertia_kg_m2().x
	var out: Array = []
	for part in build.mass_parts():
		var d: Vector3 = part.position_m - com
		var share: float = part.local_inertia_diag.z + part.mass_kg * (d.x * d.x + d.y * d.y)
		out.append({
			"label": part.label,
			"mass_g": part.mass_kg * 1000.0,
			"kg_m2": share,
			"fraction": share / total if total > 0.0 else 0.0,
		})
	out.sort_custom(func(a, b): return a["kg_m2"] > b["kg_m2"])
	return out


## Clearance between two adjacent propeller discs. Read off the DRAWN airframe — the one on screen
## if this bench has been handed it, a throwaway one built from the same Build if not. Never
## re-derived from arm_mm and a diameter: airframe_model.gd:193 names that as the divergence to
## avoid, and a second opinion here would agree for a long time and then stop.
func prop_gap_m() -> float:
	if airframe != null:
		return airframe.adjacent_prop_gap_m()
	var drawn := AirframeModel.new()
	drawn.rebuild(build)
	var gap := drawn.adjacent_prop_gap_m()
	drawn.free()
	return gap


## The collective the step is trimmed at: what this aircraft's throttle actually sits at, hands off,
## on the pack currently in it. A step response from idle would be measuring a machine that is
## falling out of the sky, and one from full throttle would have no headroom to add differential to.
func hover_collective() -> float:
	return build.hover_throttle_for(powertrain.battery)


# ---------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------

## Trims the four motors at `p_collective` and arms a step on `p_axis`. The motors are PRIMED rather
## than spun up from rest, because a hover trim is where a stick input is actually given, and the
## spool-up from zero would put a second, much larger transient in front of the one being measured.
func begin(p_axis: int, p_collective: float) -> void:
	axis = p_axis
	collective = clampf(p_collective, 0.0, 1.0)
	powertrain.prime(collective)
	_take_settled_figures()
	rate_rad_s = 0.0
	angle_rad = 0.0
	elapsed_s = 0.0
	history = []
	time_to_rate_s = -1.0
	_alpha_rad_s2 = 0.0
	running = true


## The settled torque and acceleration for the armed axis, on a SCRATCH powertrain at the
## nominal-voltage datum (physics.md §5).
##
## Scratch, so taking the figure costs the user's pack nothing — the visible run is what costs. At
## the datum, so two frames are comparable: measured on whatever charge each happened to have, a 7"
## on a fresh pack could out-accelerate a 3" on a flat one and the arm-length result would disappear
## into the batteries. It is the same convention Build.max_total_thrust_n() is quoted at, and for
## the same reason — this is the spec-sheet figure, and the trace beside it is the flying one.
func _take_settled_figures() -> void:
	var scratch := _powertrain_for(build)
	scratch.battery.set_to_nominal_datum()
	scratch.prime(collective)
	var cmds := commands()
	var dt := 1.0 / PHYSICS_HZ
	for _i in int(SETTLE_SECONDS * PHYSICS_HZ):
		scratch.step(cmds, dt)

	var inertia: float = inertia_kg_m2()[axis]
	peak_torque_n_m = absf(torque_n_m(scratch)[axis])
	peak_alpha_rad_s2 = peak_torque_n_m / inertia if inertia > 0.0 else 0.0


## Full deflection on the armed axis and neutral on the other two, through the mixer that is
## actually installed. Not a hand-written motor pattern: MotorMixer is where airmode decides what to
## sacrifice when the deltas do not fit, and a bench that mixed its own commands would be reporting
## the authority of an aircraft with a different mixer in it.
func commands() -> Dictionary:
	return MotorMixer.mix(collective,
		1.0 if axis == AXIS_ROLL else 0.0,
		1.0 if axis == AXIS_PITCH else 0.0,
		1.0 if axis == AXIS_YAW else 0.0)


## The torque the four motors are producing RIGHT NOW about roll, pitch and yaw, from the thrust the
## powertrain has published and the reaction torque their RPM implies. MotorLayout does the
## resolving; this only sums.
func torque_n_m(source: Powertrain = null) -> Vector3:
	var from := source if source != null else powertrain
	var total := Vector3.ZERO
	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var rpm: float = from.motor_rpm[name]
		var contribution := MotorLayout.torque_from_motor(
			name,
			from.observables.thrust_n[i],
			PropellerModel.reaction_torque_n_m(from.k_q, rpm),
			build.arm_m)
		total += Vector3(contribution["roll"], contribution["pitch"], contribution["yaw"])
	return total


## One frame of bench. Separate from any _process for the same reason the other three benches'
## advance() is: a headless test and the screenshot tool drive it by hand, and the two must never
## drive it at once.
func advance(delta: float) -> void:
	if not running:
		return

	var substeps := clampi(int(ceil(delta * PHYSICS_HZ)), 1, MAX_SUBSTEPS)
	var dt := delta / float(substeps)
	var cmds := commands()
	var inertia: float = inertia_kg_m2()[axis]

	for _i in substeps:
		powertrain.step(cmds, dt)

		var tau: float = torque_n_m()[axis]
		_alpha_rad_s2 = tau / inertia if inertia > 0.0 else 0.0
		rate_rad_s += _alpha_rad_s2 * dt
		angle_rad += rate_rad_s * dt

		history.append([elapsed_s + (_i + 1) * dt, rad_to_deg(rate_rad_s)])

		if rate_rad_s >= deg_to_rad(TARGET_RATE_DEG_S):
			time_to_rate_s = elapsed_s + (_i + 1) * dt
			elapsed_s = time_to_rate_s
			running = false
			return

	elapsed_s += delta
	if elapsed_s >= RUN_SECONDS:
		running = false


## Runs a whole step to completion and returns what it measured, with the pack held AT THE NOMINAL
## VOLTAGE DATUM (physics.md §5). That datum is what makes two frames comparable: measured on
## whatever charge each happened to have, a 7" on a fresh pack could out-accelerate a 3" on a flat
## one and the arm-length result would disappear into the batteries.
static func measure(p_build: Build, p_axis: int) -> Dictionary:
	var bench := FrameBench.for_build(p_build)
	bench.powertrain.battery.set_to_nominal_datum()
	bench.begin(p_axis, p_build.hover_throttle())
	var dt := 1.0 / PHYSICS_HZ
	while bench.running:
		bench.advance(dt)
	return bench.readings()


# ---------------------------------------------------------------------------
# What the bench is reading, as numbers. One dictionary, so a test and the panel cannot disagree
# about what the bench says.
# ---------------------------------------------------------------------------

func readings() -> Dictionary:
	var inertia := inertia_kg_m2()
	return {
		"axis": axis,
		"axis_name": AXIS_NAMES[axis],
		"inertia_kg_m2": inertia[axis],
		"inertia_roll_kg_m2": inertia.x,
		"inertia_pitch_kg_m2": inertia.y,
		"inertia_yaw_kg_m2": inertia.z,
		"peak_torque_n_m": peak_torque_n_m,
		"peak_alpha_rad_s2": peak_alpha_rad_s2,
		"alpha_rad_s2": _alpha_rad_s2,
		"rate_deg_s": rad_to_deg(rate_rad_s),
		"target_rate_deg_s": TARGET_RATE_DEG_S,
		"time_to_rate_s": time_to_rate_s,
		"angle_deg": rad_to_deg(angle_rad),
		"elapsed_s": elapsed_s,
		"collective": collective,
		"arm_mm": build.arm_m * 1000.0,
		"all_up_weight_g": build.all_up_weight_g(),
		"prop_gap_mm": prop_gap_m() * 1000.0,
		"com_offset_mm": com_offset_m().length() * 1000.0,
		"current_a": powertrain.observables.current_total_a,
		"voltage_v": powertrain.observables.voltage_live_v,
	}
