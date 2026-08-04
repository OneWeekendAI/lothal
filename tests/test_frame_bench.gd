class_name TestFrameBench
extends RefCounted
## The frame bench: mass distribution made measurable.
##
## Every assertion here was chosen against one standard — CAN IT FAIL? Asserting that the roll
## inertia of a build assembled from m and r comes out as m*r^2 is arithmetic checking itself, and
## this bench is unusually exposed to that. So the checks below are all statements about the REAL
## catalog, or cross-checks against a second implementation that was written for another purpose:
##
##   - the ~4x claim frames.json's own schema makes about 3" vs 7", which nothing verified before;
##   - the counterintuitive result — a longer arm has MORE leverage and still rolls SLOWER —
##     asserted with the torque derived from the real motors, so both terms are free to move;
##   - the perpendicular-axis identity, which fails the moment the tensor's axes are mismapped;
##   - the bench's predicted roll acceleration against what DroneCore actually achieves, which is
##     the accountability that makes the bench answerable to the physics rather than to itself;
##   - prop clearance against the drawn geometry (the two-sources hazard airframe_model.gd:193
##     names by name);
##   - and the centre of mass under a slid pack, which is the one that reports a LIMITATION rather
##     than a capability. See _com_under_a_slid_pack below.

## The build carried by every frame under comparison. Same motors, same props, same pack — so the
## only thing that differs between two rows is the frame, which is the entire argument of the bench.
const CARRIED_MOTOR := ReferenceBuild.MOTOR_ID
const CARRIED_PROP := ReferenceBuild.PROPELLER_ID
const CARRIED_PACK := ReferenceBuild.BATTERY_ID

const SHORT_FRAME := "frame_3in_toothpick"     # 75 mm arm
const LONG_FRAME := "frame_7in_long_range"     # 150 mm arm

const DT := 0.001
const DURATION_S := 0.8


static func _build_on(frame_id: String) -> Build:
	return Build.from_ids(PartsCatalog.load_default(), frame_id, CARRIED_MOTOR, CARRIED_PROP,
		CARRIED_PACK, ReferenceBuild.ESC_ID)


static func run() -> Array:
	var results: Array = []

	var short_build := _build_on(SHORT_FRAME)
	var long_build := _build_on(LONG_FRAME)

	# --- 1. The sleeper spec, verified ---
	#
	# frames.json's _schema states that arm_mm "is squared in the parallel axis theorem, so a 7"
	# frame has roughly 4x the roll inertia of a 3" from geometry alone". Nothing in the project
	# checked that until now. The arms are 75 mm and 150 mm — exactly 2x, so the geometry term
	# alone contributes 4x, and the heavier frame plate adds on top of it.
	var short_inertia := FrameBench.for_build(short_build).inertia_kg_m2()
	var long_inertia := FrameBench.for_build(long_build).inertia_kg_m2()
	var inertia_ratio: float = long_inertia.x / short_inertia.x
	results.append(TestResult.new(
		"a 7\" carries roughly 4x the roll inertia of a 3\" on the same build (frames.json's schema)",
		inertia_ratio > 3.0 and inertia_ratio < 5.0,
		"%.1fx — %.0f vs %.0f g*cm^2 (arms 150 vs 75 mm)" % [
			inertia_ratio, long_inertia.x * 1.0e7, short_inertia.x * 1.0e7]
	))

	# --- 2. THE RESULT THE BENCH EXISTS FOR ---
	#
	# Motor torque about the roll axis scales with arm LENGTH. Roll inertia scales with arm length
	# SQUARED. So alpha = tau / I goes as 1/arm: the longer arm has more leverage and still rolls
	# slower, because inertia wins the exponent.
	#
	# Both terms are derived, neither is asserted. The torque comes from the four real motors at
	# their real positions through MotorMixer and MotorLayout, so a longer arm genuinely does
	# produce more of it — which is what stops this from being "bigger number divided by bigger
	# number". If the torque were a constant, this test would pass trivially and prove nothing.
	var short_roll := FrameBench.measure(short_build, FrameBench.AXIS_ROLL)
	var long_roll := FrameBench.measure(long_build, FrameBench.AXIS_ROLL)

	results.append(TestResult.new(
		"the LONGER arm does produce more roll torque — the leverage term is real, not held fixed",
		long_roll["peak_torque_n_m"] > short_roll["peak_torque_n_m"],
		"%.3f N*m at 150 mm vs %.3f N*m at 75 mm" % [
			long_roll["peak_torque_n_m"], short_roll["peak_torque_n_m"]]
	))

	var alpha_ratio: float = short_roll["peak_alpha_rad_s2"] / long_roll["peak_alpha_rad_s2"]
	results.append(TestResult.new(
		"and it STILL rolls slower: peak angular acceleration falls as roughly 1/arm",
		alpha_ratio > 1.4 and alpha_ratio < 3.0,
		"3\" accelerates %.2fx harder (%.0f vs %.0f rad/s^2) on a 2.00x arm ratio" % [
			alpha_ratio, short_roll["peak_alpha_rad_s2"], long_roll["peak_alpha_rad_s2"]]
	))

	# --- 3. The tensor's axes are mapped to the contract's axes, and mismapping shows ---
	#
	# A quad is very nearly planar in its mass distribution, so the perpendicular axis theorem
	# holds to within the parts' own thickness: I_yaw ~= I_roll + I_pitch. This fails immediately
	# if roll is read off the wrong element of the Basis, which is the single most likely mistake
	# in the whole model and the one an "inertia is positive" check would never see.
	var datum := FrameBench.for_build(ReferenceBuild.build()).inertia_kg_m2()
	var planar_error: float = absf(datum.z - (datum.x + datum.y)) / datum.z
	results.append(TestResult.new(
		"yaw inertia is roll plus pitch to within the airframe's own thickness (perpendicular axis)",
		planar_error < 0.12,
		"yaw %.0f vs roll+pitch %.0f g*cm^2 — %.1f%% apart" % [
			datum.z * 1.0e7, (datum.x + datum.y) * 1.0e7, planar_error * 100.0]
	))

	# --- 4. THE BENCH IS ACCOUNTABLE TO THE SIMULATOR ---
	#
	# The bench predicts a peak roll acceleration from MassProperties and MotorLayout. DroneCore
	# reaches one by integrating a rigid body under the same command. Nothing forces them to agree:
	# the bench reads the tensor's diagonal and the body integrates the full tensor with a
	# gyroscopic term, and they are two separate expressions of "what does full stick do".
	#
	# This is the same accountability that proved the hover-throttle readout honest, and it is what
	# makes the frame bench a measurement rather than a formula with a picture next to it.
	var cross := _bench_against_the_simulator()
	results.append(TestResult.new(
		"the bench's predicted peak roll acceleration is what the simulator actually achieves",
		cross["error_fraction"] < 0.05,
		"bench %.1f rad/s^2, sim %.1f rad/s^2 — %.2f%% apart" % [
			cross["bench"], cross["sim"], cross["error_fraction"] * 100.0]
	))

	# --- 5. Prop clearance comes from the drawn geometry, not from a second derivation ---
	results.append_array(_clearance_matches_the_drawing())

	# --- 6. The centre of mass under a slid pack ---
	results.append_array(_com_under_a_slid_pack())

	# --- 7. What the spread across the catalog is, since §7 needs it ---
	results.append_array(_catalog_spread())

	# --- 8. The room around the model ---
	results.append_array(screen_tests())

	return results


## Bench prediction vs. simulator truth, both at the nominal-voltage datum and both at the same
## collective, so the only thing that can differ is the rotational model itself.
static func _bench_against_the_simulator() -> Dictionary:
	var build := ReferenceBuild.build()
	var collective := build.hover_throttle()

	var bench := FrameBench.for_build(build)
	bench.powertrain.battery.set_to_nominal_datum()
	bench.begin(FrameBench.AXIS_ROLL, collective)
	for _i in int(DURATION_S / DT):
		bench.advance(DT)
	var predicted: float = bench.readings()["peak_alpha_rad_s2"]

	# The simulator, driven by the same mixer command with no controller in the path — the same
	# open-loop measurement tests/test_rate_step_response.gd takes its slew floor from.
	var core := build.build_drone_core()
	core.powertrain.battery.set_to_nominal_datum()
	core.prime_motors(collective)
	var cmds := MotorMixer.mix(collective, 1.0, 0.0, 0.0)
	var previous := 0.0
	var achieved := 0.0
	for _i in int(DURATION_S / DT):
		core.step(cmds, DT)
		var rate: float = Gyro.contract_rates(core.rigid_body.angular_velocity_rad_s).x
		achieved = maxf(achieved, (rate - previous) / DT)
		previous = rate

	return {
		"bench": predicted,
		"sim": achieved,
		"error_fraction": absf(predicted - achieved) / achieved if achieved > 0.0 else 1.0,
	}


## The clearance the bench reports must be the clearance of the airframe on screen. AirframeModel
## already measures it off the drawn props; a bench that recomputed it from arm_mm and a diameter
## would agree for a long time and then stop — which is the whole content of the comment at
## airframe_model.gd:193.
static func _clearance_matches_the_drawing() -> Array:
	var results: Array = []
	# A build whose props genuinely overlap, so the check is not made against a comfortable
	# positive number that any plausible formula would reproduce.
	for pair in [[ReferenceBuild.FRAME_ID, ReferenceBuild.PROPELLER_ID],
			["frame_3in_toothpick", ReferenceBuild.PROPELLER_ID]]:
		var build := Build.from_ids(PartsCatalog.load_default(), pair[0], CARRIED_MOTOR,
			pair[1], CARRIED_PACK, ReferenceBuild.ESC_ID)

		var drawn := AirframeModel.new()
		drawn.rebuild(build)
		var drawn_gap := drawn.adjacent_prop_gap_m()
		drawn.free()

		var reported := FrameBench.for_build(build).prop_gap_m()
		results.append(TestResult.new(
			"prop clearance on %s is read off the drawn airframe, to the millimetre" % pair[0],
			absf(reported - drawn_gap) < 1e-9,
			"bench %.2f mm, drawing %.2f mm" % [reported * 1000.0, drawn_gap * 1000.0]
		))
	return results


## SLIDING THE PACK MOVES THE PICTURE AND NOT THE MASS MODEL, and that gap is what this asserts.
##
## build.gd:216 says so in its own words: the electronics and the pack are lumped at the origin,
## "the mass model does not hear about" where anything is mounted, and when it grows a real
## centre-of-gravity term the mount point is already the single source for where the pack is.
##
## So the honest assertion is the divergence, not a capability. The drawn pack MUST move — that is
## the mount travel of §2.6 working — and the modelled centre of mass must be seen not to, because
## a bench that showed a COM shifting when nothing in the physics had shifted would be inventing a
## number. This test fails the day the offset is wired into mass_parts(), which is exactly when
## somebody should be made to come back and read this comment.
static func _com_under_a_slid_pack() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()

	var tweaks := AssemblyTweaks.new()
	var travel_mm := AssemblyTweaks.battery_travel_mm(build)
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, travel_mm)

	var drawn := AirframeModel.new()
	drawn.rebuild(build, tweaks)
	var slid_z: float = drawn.battery_mesh.position.z
	var slid_offset := drawn.battery_offset_m

	var centred := AirframeModel.new()
	centred.rebuild(build, AssemblyTweaks.new())
	var centred_z: float = centred.battery_mesh.position.z

	var bench_com := FrameBench.for_build(build, drawn).com_offset_m()
	drawn.free()
	centred.free()

	results.append(TestResult.new(
		"sliding the pack to the end of its travel moves the pack that is drawn",
		travel_mm > 1.0 and absf(slid_z - centred_z) > 0.001
			and is_equal_approx(slid_offset, travel_mm / 1000.0),
		"%.0f mm of travel moved the drawn pack %.1f mm forward" % [
			travel_mm, (centred_z - slid_z) * 1000.0]
	))

	# And the mass model does not hear about it — see the docstring. The bench must report the
	# centre of mass the physics is actually using, which for every build in the catalog is the
	# geometric centre, because every centre-mounted part is lumped at the origin.
	results.append(TestResult.new(
		"and the modelled centre of mass does NOT move: no mount position reaches mass_parts()",
		bench_com.length() < 1e-9,
		"COM offset %.4f mm from the geometric centre with the pack slid %.0f mm forward"
			% [bench_com.length() * 1000.0, travel_mm]
	))

	# The one thing that must be true whatever the pack is doing: the parts that dominate roll
	# inertia are the four motor/prop assemblies and the pack, not the frame. This is the reading
	# the panel exists to give, and it is falsifiable — on a 5" freestyle the 110 g frame is the
	# single heaviest part and contributes less than the four 41 g arm-tip lumps do.
	var contributions := FrameBench.for_build(build).roll_inertia_contributions()
	var frame_share := 0.0
	var motor_share := 0.0
	for entry in contributions:
		if String(entry["label"]).begins_with("Frame"):
			frame_share = entry["fraction"]
		elif String(entry["label"]).begins_with("Motor"):
			motor_share += entry["fraction"]
	results.append(TestResult.new(
		"the arm-tip motor/prop assemblies dominate roll inertia, and the frame does not",
		motor_share > frame_share and contributions.size() >= 7,
		"motors %.0f%% vs frame %.0f%% across %d parts" % [
			motor_share * 100.0, frame_share * 100.0, contributions.size()]
	))

	return results


## The spread the fixed PID gains have to cover, measured rather than assumed. This is the number
## labs-and-sim.md §7 needs and the reason the bench makes the problem visible; it fixes nothing.
static func _catalog_spread() -> Array:
	var lowest := INF
	var highest := 0.0
	var lowest_name := ""
	var highest_name := ""
	for frame in PartsCatalog.load_default().list_category("frame"):
		var build := _build_on(String(frame["part_id"]))
		var roll: float = FrameBench.for_build(build).inertia_kg_m2().x
		if roll < lowest:
			lowest = roll
			lowest_name = String(frame["name"])
		if roll > highest:
			highest = roll
			highest_name = String(frame["name"])

	# More than an order of magnitude, measured on ONE carried build so the frame is the only thing
	# that differs. Flown with class-appropriate parts the real spread is far wider still — a whoop
	# does not carry a 2207 and a 4S 1500 — so this is the CONSERVATIVE reading of the problem, and
	# rate_mode_controller.gd hands every one of these the same three gains.
	return [TestResult.new(
		"the catalog spans more than an order of magnitude of roll inertia on ONE set of fixed PID gains",
		highest / lowest > 10.0,
		"%.0fx — %s %.0f to %s %.0f g*cm^2 (input to labs-and-sim.md §7, not fixed here)" % [
			highest / lowest, lowest_name, lowest * 1.0e7, highest_name, highest * 1.0e7]
	)]


# ---------------------------------------------------------------------------
# The room around the model. Every Control built here is freed, or the runner emits leaked-RID
# ERROR lines that read like failures.
# ---------------------------------------------------------------------------

static func _screen(frame_id: String) -> FrameBenchScreen:
	return FrameBenchScreen.new(PartsCatalog.load_default(), frame_id, CARRIED_MOTOR,
		CARRIED_PROP, CARRIED_PACK, ReferenceBuild.ESC_ID, PackCharge.new())


## Runs a screen's step to completion the way the screenshot tool does — by hand, with _process
## off, so the bench is never advanced twice per frame.
static func _run_to_completion(screen: FrameBenchScreen) -> void:
	screen.set_process(false)
	screen.start_run()
	var guard := 0
	while screen.running and guard < 10000:
		screen.advance(1.0 / 60.0)
		guard += 1


static func screen_tests() -> Array:
	var results: Array = []

	# --- The chart carries the comparison, and the two lines actually differ ---
	#
	# A yardstick line that tracked the build's own line would look entirely correct and compare
	# nothing. So a 7" is run and the two series are required to separate — by a margin far larger
	# than any sampling artefact could produce.
	var screen := _screen(LONG_FRAME)
	_run_to_completion(screen)
	var reading := screen.readings()
	var mine := screen.trace.lower_series()
	var theirs := screen.trace.upper_series()
	var widest := screen.trace.widest_gap()
	results.append(TestResult.new(
		"the chart draws this build against the 5\" reference, and the two lines are not the same line",
		mine.size() > 20 and mine.size() == theirs.size() and widest > 50.0,
		"%d samples a series, widest separation %.0f deg/s" % [mine.size(), widest]
	))

	# The 7" must be the SLOWER of the two, which is the direction the whole bench argues for. A
	# check on separation alone would pass just as happily if the long frame were quicker.
	results.append(TestResult.new(
		"and the 7\" is the slower line: it reaches a lower rate than the 5\" reference throughout",
		reading["rate_deg_s"] < reading["yardstick_rate_deg_s"]
			and reading["inertia_kg_m2"] > reading["yardstick_inertia_kg_m2"],
		"7\" reached %.0f deg/s against the reference's %.0f, on %.1fx the roll inertia" % [
			reading["rate_deg_s"], reading["yardstick_rate_deg_s"],
			reading["inertia_kg_m2"] / reading["yardstick_inertia_kg_m2"]]
	))

	# --- The run costs charge, and the yardstick's pack is not the user's ---
	var store := screen.pack_charge
	screen.persist_pack_charge()
	var used: float = store.used_mah(CARRIED_PACK)
	results.append(TestResult.new(
		"a step response costs pack charge — four motors turning are four motors drawing (§5)",
		used > 0.0,
		"the run took %.2f mAh out of the pack" % used
	))
	# The yardstick is the SAME pack part as the build's, so a write-back that included it would
	# silently overwrite the user's charge with the reference run's. The yardstick starts at the
	# nominal datum — a long way down a 4S — so if its state ever reached the store the recorded draw
	# would be hundreds of mAh rather than the handful a forty-millisecond step actually costs.
	results.append(TestResult.new(
		"and the yardstick runs on its own pack, so comparing frames never drains the user's",
		screen.yardstick.powertrain.battery != screen.bench.powertrain.battery and used < 50.0,
		"%.2f mAh recorded against the pack; the yardstick alone sits %.0f%% down and is not in it" % [
			used, (1.0 - screen.yardstick.powertrain.battery.remaining_fraction()) * 100.0]
	))

	# --- The rotors turn on a rate they are handed (§2.1) ---
	var turning := 0
	for motor_name in MotorLayout.MOTOR_NAMES:
		var mesh: PropellerMesh = screen.airframe.propeller_meshes[motor_name]
		if absf(mesh.rate_rad_s()) > 0.0:
			turning += 1
	var m1: PropellerMesh = screen.airframe.propeller_meshes["M1"]
	var m1_rpm := absf(m1.rate_rad_s()) / TAU * 60.0
	results.append(TestResult.new(
		"the four rotors turn on the rate the powertrain published, and on no rate the room chose",
		turning == 4 and absf(m1_rpm - screen.bench.powertrain.observables.rpm[0]) < 0.5,
		"%d rotors turning; M1 at %.0f rpm against the published %.0f" % [
			turning, m1_rpm, screen.bench.powertrain.observables.rpm[0]]
	))

	# --- And the airframe turned by the angle that was MEASURED, not by an animation ---
	# Against the contract's roll axis (-Z), not against "it moved". A basis built about the wrong
	# axis, or by an animation curve that merely looked like rotation, fails here.
	var expected := Basis(Vector3(0, 0, -1), screen.bench.angle_rad)
	results.append(TestResult.new(
		"the airframe on screen turned by exactly the angle the measurement says it turned",
		screen.bench.angle_rad > 0.1
			and screen.airframe.transform.basis.is_equal_approx(expected),
		"rolled %.1f deg about the contract's roll axis (-Z)" % rad_to_deg(screen.bench.angle_rad)
	))

	# --- Audible through the existing path, or silently silent ---
	results.append(TestResult.new(
		"3D audio is routed out of the bench's own SubViewport, or the room is silent and says nothing",
		screen.audio_viewport().audio_listener_enable_3d,
		"audio_listener_enable_3d = true"
	))

	screen.free()

	# --- NOTHING HERE FLIES, checked by reading the source ---
	#
	# An absence cannot be asserted at runtime: a bench that quietly built a DroneCore would produce
	# numbers that still looked entirely plausible. The only way to see it is to look for the text,
	# which is the same argument test_bench.gd and test_control_path.gd make.
	var flight_words := ["DroneCore", "RigidBodyState", "RateModeController"]
	var named: PackedStringArray = []
	for path in ["res://src/lab/frame_bench.gd", "res://src/lab/frame_bench_screen.gd",
			"res://src/lab/frame_instruments.gd"]:
		var code := FileAccess.get_file_as_string(path)
		for line in code.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for word in flight_words:
				if line.contains(word):
					named.append("%s: %s" % [path.get_file(), word])
	results.append(TestResult.new(
		"the frame bench names no part of the flight half — one axis is free and nothing flies (§6)",
		named.is_empty(),
		"checked 3 files for %s%s" % [", ".join(flight_words),
			"" if named.is_empty() else " — found " + ", ".join(named)]
	))

	# --- It is a room of its own, and leaving it frees it ---
	var shell := AppShell.new()
	shell.lab.picker.select_id(LONG_FRAME)
	shell.show_frame_bench()
	results.append(TestResult.new(
		"the frame bench opens on the frame chosen on Lab's rail, with no other room running",
		shell.frame_bench != null and shell.bench == null and shell.battery_bench == null
			and shell.esc_bench == null and shell.sim == null
			and shell.frame_bench.current_build().frame["part_id"] == LONG_FRAME,
		"testing %s" % shell.frame_bench.current_build().frame["name"]
	))

	shell.show_lab()
	results.append(TestResult.new(
		"leaving frees it, so no pack drains behind Lab",
		shell.frame_bench == null and shell.showing_lab(),
		"frame_bench=%s" % shell.frame_bench
	))
	shell.free()

	return results
