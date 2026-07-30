class_name TestBench
extends RefCounted
## The thrust stand (labs-and-sim.md §2.1) — a motor and propeller pairing on a bench, spun
## up and judged, with no flight simulation running anywhere.
##
## The tests that matter here are the ones that would still pass if the bench were a lie.
## A bench that drew a spinning prop and printed plausible numbers is easy; the checks below
## are chosen so that a decorative one fails:
##
##   - the rotor turns at the RPM the powertrain PUBLISHED, not at a rate the screen picked
##   - the instruments settle on the numbers Build predicts ANALYTICALLY, by a different route
##   - the pack sags under load and RECOVERS when the throttle backs off
##   - nothing anywhere in the bench integrates a rigid body
##
## Every Control built here is freed, or the runner emits leaked-RID ERROR lines that read
## like failures.

const DT := 1.0 / 120.0
const SETTLE_SECONDS := 2.0
const TEST_THROTTLE := 0.5

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_it_does_not_fly(catalog))
	results.append_array(_test_settles_where_the_analytic_model_says(catalog))
	results.append_array(_test_the_rotor_turns_at_published_rpm(catalog))
	results.append_array(_test_sag_and_recovery(catalog))
	results.append_array(_test_instruments(catalog))
	results.append_array(_test_sweep(catalog))
	results.append_array(_test_it_is_a_room_of_its_own(catalog))
	results.append_array(_test_the_camera_is_looking_at_the_pairing(catalog))
	results.append_array(_test_the_bench_can_be_heard(catalog))

	return results


# ---------------------------------------------------------------------------
# The bench is audible
# ---------------------------------------------------------------------------

## "It works for free because the synthesiser reads only Observables" is true, and it was still
## not enough. The bench renders into a SubViewport, and a SubViewport does not route 3D audio
## unless audio_listener_enable_3d is set — it defaults to false. Sim never needed it because
## main.tscn sits on the root viewport, where it is already on.
##
## So the failure mode was: every audio assertion in the project passing, no audio file
## changed, the wiring visibly correct, and the bench making no sound at all. Nothing that
## reads like a bug anywhere. Hence a test about the one property that decides it.
static func _test_the_bench_can_be_heard(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)

	results.append(TestResult.new(
		"the bench's viewport actually routes 3D audio, so the stand can be heard at all",
		bench.audio_viewport().audio_listener_enable_3d,
		"audio_listener_enable_3d = %s" % bench.audio_viewport().audio_listener_enable_3d
	))

	# The synthesiser is present and reading the same published layer everything else reads.
	# If this ever has to become a DIFFERENT synthesiser, the Powertrain split has failed.
	results.append(TestResult.new(
		"the bench drives the flight sim's own synthesiser, not a copy of it",
		bench.drone_audio is DroneAudio,
		"attached %s" % bench.drone_audio
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The camera is pointed at the thing under test
# ---------------------------------------------------------------------------

## Written because the first version of this bench got it wrong in a way no other test could
## see: the camera aimed at the stand's ORIGIN, but the motor hangs off the end of a boom
## whose length is set by the prop's radius, so the pairing sat over 100 mm outside the frame.
## Every physics assertion above passed on that build. Only the screenshot showed it.
##
## Checked as an angle rather than by eye, and across the whole span of the catalog, because
## the boom length changes with the prop and a framing that works for a 5" can miss a 10".
static func _test_the_camera_is_looking_at_the_pairing(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var worst_rotor := 0.0
	var worst_rotor_prop := "—"
	var worst_base := 0.0
	var worst_base_prop := "—"
	# The VERTICAL half-field, less a margin. Vertical rather than horizontal because the camera
	# is KEEP_WIDTH on a landscape viewport, so the vertical field is the narrower of the two and
	# therefore the one that actually clips things. Measuring against the horizontal field would
	# pass a shot with the rotor out of the top of the frame — which is exactly the bug this test
	# was written after finding.
	var aspect := float(BenchScreen.VIEWPORT_SIZE.x) / float(BenchScreen.VIEWPORT_SIZE.y)
	var half_field := rad_to_deg(atan(tan(deg_to_rad(BenchScreen.CAMERA_FOV) * 0.5) / aspect)) * 0.85

	for prop in catalog.list_category("propeller"):
		var bench := BenchScreen.new(catalog, ReferenceBuild.MOTOR_ID, prop["part_id"])
		var camera := bench.camera_transform()

		# Both ends of the composition: the rotor, which is the subject, and the foot of the
		# column, which is what makes the picture read as a stand rather than as a propeller
		# floating in the dark. Both have to be in shot at every prop size in the catalog,
		# because the boom length — and therefore the whole framing — is set by the prop.
		var rotor: Vector3 = bench.stand.position + bench.stand.mount_position_m
		var base: Vector3 = bench.stand.position

		var rotor_off := _off_axis_deg(camera, rotor)
		var base_off := _off_axis_deg(camera, base)
		if rotor_off > worst_rotor:
			worst_rotor = rotor_off
			worst_rotor_prop = String(prop["name"])
		if base_off > worst_base:
			worst_base = base_off
			worst_base_prop = String(prop["name"])

		bench.free()

	results.append(TestResult.new(
		"the rotor is inside the frame for every prop in the catalog",
		worst_rotor < half_field,
		"worst rotor offset over %d props = %.1f deg (%s), half-field %.1f deg" % [
			catalog.list_category("propeller").size(), worst_rotor, worst_rotor_prop, half_field]
	))
	results.append(TestResult.new(
		"the stand it is mounted on is in shot too, so the bench reads as a bench",
		worst_base < half_field,
		"worst base offset = %.1f deg (%s), half-field %.1f deg" % [
			worst_base, worst_base_prop, half_field]
	))

	return results


## How far a point sits off the camera's own axis, in degrees. A camera looks down its own -Z.
static func _off_axis_deg(camera: Transform3D, point: Vector3) -> float:
	var to_point := (point - camera.origin).normalized()
	var facing := -camera.basis.z.normalized()
	return rad_to_deg(acos(clampf(to_point.dot(facing), -1.0, 1.0)))


## A file's executable lines, with comments stripped. The absence check below is about what the
## bench REFERS TO, not about what it is allowed to talk about — and these files talk about
## DroneCore constantly, because explaining which half lives where is most of why their headers
## exist. A check that forbade the prose would quietly pressure the next person to delete the
## explanation rather than to keep the separation.
static func _code_only(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		var hash_index := line.find("#")
		lines.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(lines)


static func _settle(bench: BenchScreen, throttle: float, seconds: float = SETTLE_SECONDS) -> void:
	bench.set_throttle(throttle)
	for _i in int(seconds / DT):
		bench.advance(DT)


# ---------------------------------------------------------------------------
# Nothing flies
# ---------------------------------------------------------------------------

## labs-and-sim.md §6: "Lab does not fly." The bench is the one part of Lab that runs a
## physics loop, so it is the one place that rule could be broken by accident — and a bench
## that quietly grew an integrator would look completely normal on screen.
static func _test_it_does_not_fly(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)
	_settle(bench, TEST_THROTTLE)

	var obs := bench.powertrain.observables
	results.append(TestResult.new(
		"the bench runs a powertrain and no rigid body: it never acquires a position",
		obs.position_m == Vector3.ZERO and obs.velocity_mps == Vector3.ZERO and obs.airspeed_mps == 0.0,
		"position %s, airspeed %.3f m/s after %.0f s at %.0f%% throttle" % [
			obs.position_m, obs.airspeed_mps, SETTLE_SECONDS, TEST_THROTTLE * 100.0]
	))

	bench.free()

	# The absence, stated as an absence — read out of the source the way test_prop_rotation.gd
	# checks PropellerMesh declares no speed of its own. Asserting it at runtime is not
	# available: `powertrain is DroneCore` is a static contradiction the compiler rejects
	# outright, which is a stronger guarantee but not one that leaves a green line behind.
	#
	# So the check is that the bench's own files never NAME the flight half. A DroneCore here
	# would drag in mass properties, drag and an integrator, and every number above would
	# still look exactly right — which is why the test has to be about the text.
	var forbidden := ["DroneCore", "RigidBodyState", "MassProperties",
		"AngleModeController", "RateModeController"]
	var offences: PackedStringArray = []
	for path in ["res://src/lab/bench_screen.gd", "res://src/lab/bench_stand.gd",
			"res://src/lab/bench_instruments.gd", "res://src/sim/powertrain.gd"]:
		var code := _code_only(FileAccess.get_file_as_string(path))
		for name in forbidden:
			if code.contains(name):
				offences.append("%s names %s" % [path.get_file(), name])

	results.append(TestResult.new(
		"nothing in the bench or the powertrain so much as names the flight half",
		offences.is_empty(),
		"checked %d files for %s%s" % [4, ", ".join(forbidden),
			"" if offences.is_empty() else " — " + "; ".join(offences)]
	))

	return results


# ---------------------------------------------------------------------------
# The cross-check: two independent routes to one number
# ---------------------------------------------------------------------------

## Build solves steady state ANALYTICALLY by iterating a fixed point. The bench reaches it
## DYNAMICALLY by integrating a first-order lag against a sagging pack, at the frame rate a
## screen actually runs at rather than the 1 kHz the flight loop uses. Agreement is evidence.
static func _test_settles_where_the_analytic_model_says(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)
	var build := bench.current_build()
	_settle(bench, TEST_THROTTLE)

	var expected_rpm := build.rpm_at_throttle(TEST_THROTTLE)
	var actual_rpm := bench.rpm()
	results.append(TestResult.new(
		"the bench settles at the RPM Build predicts analytically for the same throttle",
		absf(actual_rpm - expected_rpm) / expected_rpm < 0.01,
		"bench %.0f RPM vs analytic %.0f RPM" % [actual_rpm, expected_rpm]
	))

	# thrust_at_throttle_n is the total across four motors; the bench reports ONE.
	var expected_thrust_g := (build.thrust_at_throttle_n(TEST_THROTTLE) / 4.0) / 9.81 * 1000.0
	var actual_thrust_g := bench.thrust_g()
	results.append(TestResult.new(
		"the bench settles at the thrust Build predicts analytically for the same throttle",
		absf(actual_thrust_g - expected_thrust_g) / expected_thrust_g < 0.02,
		"bench %.0f g vs analytic %.0f g" % [actual_thrust_g, expected_thrust_g]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The rotor turns on the rate it is GIVEN, and the giver is the powertrain
# ---------------------------------------------------------------------------

## PropellerMesh renders a rate it is handed and derives none. Until now Lab handed it a
## 150 RPM hand-spin; this is the first time it sees a real one. The check is that the two
## agree exactly, because "the prop spins convincingly, agreeing with nothing" is precisely
## the failure the observables layer exists to prevent.
static func _test_the_rotor_turns_at_published_rpm(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)
	_settle(bench, TEST_THROTTLE)

	var published_rpm: float = bench.powertrain.observables.rpm[0]
	var prop: PropellerMesh = bench.stand.propeller_mesh
	var drawn_rpm := absf(prop.rate_rad_s()) / TAU * 60.0

	results.append(TestResult.new(
		"the rotor turns at exactly the RPM the powertrain published, not a rate the screen chose",
		absf(drawn_rpm - published_rpm) < 1.0,
		"drawn %.1f RPM vs published %.1f RPM" % [drawn_rpm, published_rpm]
	))

	# Direction comes from the same table the yaw torque does. The bench shows M1.
	results.append(TestResult.new(
		"spin direction comes from MotorLayout.SPIN rather than being chosen by the bench",
		signf(prop.rate_rad_s()) == signf(MotorLayout.SPIN[BenchStand.BENCH_MOTOR]),
		"rate %.1f rad/s against SPIN[%s] = %.0f" % [
			prop.rate_rad_s(), BenchStand.BENCH_MOTOR, MotorLayout.SPIN[BenchStand.BENCH_MOTOR]]
	))

	# Above the aliasing bound the blades are replaced by the disc they sweep. A real bench
	# RPM is far above that bound, so this is the first slice where the switch actually fires
	# in anger — and a rotor drawn as discrete blades at 14,000 RPM would strobe or appear to
	# run backwards, which is a correctness problem rather than a polish one.
	results.append(TestResult.new(
		"at real bench RPM the rotor is drawn as a swept disc rather than strobing blades",
		prop.blur_drawn() and not prop.blades_drawn(),
		"at %.0f RPM (discrete bound is %.0f RPM): blur=%s blades=%s" % [
			drawn_rpm, PropellerMesh.max_discrete_rpm(prop.blade_count, PropellerMesh.DESIGN_FPS),
			prop.blur_drawn(), prop.blades_drawn()]
	))

	# ...and at a hand-spin idle it is still blades, or the bench would never show the twist
	# the previous slice went to the trouble of generating.
	_settle(bench, 0.0, 1.0)
	results.append(TestResult.new(
		"backed off to a stop the rotor is discrete blades again, not a permanent disc",
		bench.stand.propeller_mesh.blades_drawn(),
		"at %.0f RPM: blades=%s" % [bench.rpm(), bench.stand.propeller_mesh.blades_drawn()]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The pack sags, and comes back
# ---------------------------------------------------------------------------

## BatteryModel doing its job, visible in the instruments. Sag alone is not enough of a
## check — a model that simply subtracted a constant would show sag too. Recovery on
## backing off is what proves the voltage is a function of the current actually being drawn.
static func _test_sag_and_recovery(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)
	var nominal: float = bench.current_build().battery_model().nominal_v

	_settle(bench, 0.0, 0.5)
	var idle_v := bench.voltage_v()

	_settle(bench, bench.current_build().max_throttle_fraction())
	var loaded_v := bench.voltage_v()
	var loaded_a := bench.current_a()

	_settle(bench, 0.0, 1.0)
	var recovered_v := bench.voltage_v()

	results.append(TestResult.new(
		"the pack sags under bench load rather than sitting at its nominal voltage",
		loaded_v < nominal - 0.2 and loaded_v > 0.0,
		"%.2f V under %.1f A per motor, nominal %.2f V" % [loaded_v, loaded_a, nominal]
	))
	results.append(TestResult.new(
		"backing the throttle off lets the pack recover, so voltage tracks current draw",
		recovered_v > loaded_v + 0.2 and recovered_v <= idle_v + 0.001,
		"idle %.2f V -> loaded %.2f V -> recovered %.2f V" % [idle_v, loaded_v, recovered_v]
	))

	# A bench run costs charge (labs-and-sim.md §5), which is what makes owning two packs mean
	# something. Recovery must not be a free reset back to a full battery.
	results.append(TestResult.new(
		"a bench run consumes real pack charge, and recovering voltage does not refill it",
		bench.powertrain.observables.capacity_used_fraction > 0.0
			and recovered_v < nominal + 0.001,
		"%.3f%% of the pack used" % (bench.powertrain.observables.capacity_used_fraction * 100.0)
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The instruments
# ---------------------------------------------------------------------------

static func _test_instruments(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)
	var build := bench.current_build()
	_settle(bench, TEST_THROTTLE)

	var text := bench.instruments.readout_text()
	var live_fields_present := (
		text.has("thrust") and text.has("current") and text.has("rpm")
		and text.has("voltage") and text.has("efficiency")
	)
	results.append(TestResult.new(
		"the bench reads out thrust, current, RPM, live pack voltage and efficiency",
		live_fields_present,
		"keys present: %s" % ", ".join(PackedStringArray(text.keys()))
	))

	# Efficiency is grams of thrust per watt at the wall — the number labs-and-sim.md §2.1
	# says most builders never look at and that decides flight time. Checked against its own
	# definition rather than against a remembered value, so it cannot drift into being
	# grams-per-amp (which would look identical at a glance and be wrong by a factor of 15).
	var expected_gpw := bench.thrust_g() / (bench.voltage_v() * bench.current_a())
	results.append(TestResult.new(
		"efficiency is grams per WATT, not grams per amp",
		absf(bench.efficiency_g_per_w() - expected_gpw) < 0.01
			and absf(bench.efficiency_g_per_w() - bench.thrust_g() / bench.current_a()) > 0.5,
		"%.2f g/W (grams-per-amp would read %.2f)" % [
			bench.efficiency_g_per_w(), bench.thrust_g() / bench.current_a()]
	))

	# Build already computes the throttle at which the motor hits its current limit, so the
	# bench surfaces it rather than deriving a second opinion.
	results.append(TestResult.new(
		"the throttle at which this pairing hits its current limit is surfaced from Build",
		absf(bench.instruments.current_limit_throttle - build.max_throttle_fraction()) < 1e-6,
		"limit at %.1f%% throttle" % (bench.instruments.current_limit_throttle * 100.0)
	))

	# Idle must read zero rather than a floor, or the panel is decorative.
	_settle(bench, 0.0, 1.0)
	results.append(TestResult.new(
		"a stopped bench reads zero thrust and zero current, not a resting glow",
		bench.thrust_g() < 1.0 and bench.current_a() < 0.1,
		"%.2f g, %.3f A at zero throttle" % [bench.thrust_g(), bench.current_a()]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The swept ramp
# ---------------------------------------------------------------------------

## Throttle by hand is one way to run a stand; a swept ramp is the other, and it is the one
## that shows you the whole curve rather than the one point you happened to stop at.
static func _test_sweep(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := BenchScreen.new(catalog)

	bench.start_sweep()
	var peak_rpm := 0.0
	var started_sweeping := bench.sweeping
	var elapsed := 0.0
	while bench.sweeping and elapsed < BenchScreen.SWEEP_SECONDS * 2.0:
		bench.advance(DT)
		peak_rpm = maxf(peak_rpm, bench.rpm())
		elapsed += DT

	results.append(TestResult.new(
		"a swept ramp runs idle to full and back to idle, then stops on its own",
		started_sweeping and not bench.sweeping and elapsed < BenchScreen.SWEEP_SECONDS * 2.0,
		"swept for %.1f s of a %.1f s ramp" % [elapsed, BenchScreen.SWEEP_SECONDS]
	))

	var full_rpm := bench.current_build().rpm_at_throttle(bench.current_build().max_throttle_fraction())
	results.append(TestResult.new(
		"the sweep actually reaches full throttle rather than stopping short",
		peak_rpm > full_rpm * 0.97,
		"peaked at %.0f RPM against a full-throttle %.0f RPM" % [peak_rpm, full_rpm]
	))
	results.append(TestResult.new(
		"the sweep returns to idle rather than leaving the motor running",
		bench.throttle < 0.01,
		"ended at %.1f%% throttle" % (bench.throttle * 100.0)
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The bench is a room, and it is not there when you are not in it
# ---------------------------------------------------------------------------

## Same argument AppShell already makes for Sim: a bench holds a running powertrain and an
## audio bus, so "it costs nothing while you are in Lab" has to be an absence rather than a
## flag. A paused bench is something that can rot; a freed one cannot.
static func _test_it_is_a_room_of_its_own(_catalog: PartsCatalog) -> Array:
	var results: Array = []
	var shell := AppShell.new()

	results.append(TestResult.new(
		"the app still opens on Lab, with no bench and no sim instantiated",
		shell.showing_lab() and shell.bench == null and shell.sim == null,
		"showing_lab=%s bench=%s sim=%s" % [shell.showing_lab(), shell.bench, shell.sim]
	))

	shell.show_bench()
	results.append(TestResult.new(
		"opening the bench instantiates it and leaves the flight sim absent",
		shell.bench != null and shell.sim == null and not shell.showing_lab(),
		"bench=%s sim=%s" % [shell.bench, shell.sim]
	))

	# The pairing under test is the one chosen on Lab's rails — the bench judges the build
	# being assembled, not a fixture of its own.
	shell.show_lab()
	shell.lab.motor_picker.select_id("motor_2807_1300kv")
	shell.lab.propeller_picker.select_id("prop_7x4x3")
	shell.show_bench()
	var benched := shell.bench.current_build()
	results.append(TestResult.new(
		"the bench tests the pairing chosen on Lab's rails, not a fixture of its own",
		benched.motor["part_id"] == "motor_2807_1300kv" and benched.propeller["part_id"] == "prop_7x4x3",
		"benching %s + %s" % [benched.motor["name"], benched.propeller["name"]]
	))

	shell.show_lab()
	results.append(TestResult.new(
		"leaving the bench frees it, so a powertrain never runs behind Lab",
		shell.bench == null and shell.showing_lab(),
		"bench=%s" % shell.bench
	))

	shell.free()
	return results
