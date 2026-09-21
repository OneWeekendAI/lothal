class_name TestConfigMotors
extends RefCounted
## Config room slice C2 — motor spin direction comes from the BUILD rather than from a `const`,
## through ONE accessor, with today's constants pinned as the default.
## Design: plans/2026-09-20-config-room-design.md §5, whose three constraints this file is written
## against one by one.
##
## §5.1 — `MotorLayout.SPIN` was read in two places, `MotorMixer.mix()` and
##        `MotorLayout.torque_from_motor()`, and they must not be allowed to disagree. Both now go
##        through `MotorLayout.spin_map(config)`, and `_test_both_callers_read_the_same_map` is the
##        check that would catch one of them being left behind.
## §5.2 — every oracle in the project is defined at today's configuration. The default must
##        reproduce the old constants BIT FOR BIT, and `_test_the_default_is_todays_constants`
##        pins that against LITERALS rather than against `SPIN` itself: an assertion written in
##        terms of the table it is guarding cannot tell a changed table from a correct one.
## §5.3 — a wrong map must FLY BADLY, NOT BE BLOCKED. `_test_a_wrong_map_flies_badly_and_is_not_blocked`
##        asserts all three halves of that: the warning fires, nothing refuses the build, and the
##        aircraft the sim flies really is the wrong one.

## An authored map that cannot fly: M2 flipped, so three motors turn one way and one the other and
## the reaction torques no longer cancel. Adjacent-same AND net-nonzero in one fixture.
const UNFLYABLE := {"M1": 1.0, "M2": 1.0, "M3": -1.0, "M4": 1.0}


static func run() -> Array:
	var results: Array = []

	results.append_array(_test_the_default_is_todays_constants())
	results.append_array(_test_props_in_flips_every_motor())
	results.append_array(_test_both_callers_read_the_same_map())
	results.append_array(_test_an_authored_map_is_taken_verbatim())
	results.append_array(_test_the_map_reaches_the_physics_from_the_build())
	results.append_array(_test_a_wrong_map_flies_badly_and_is_not_blocked())

	return results


## §5.2, and the reason for the literals. The expected numbers below are written out by hand from
## motor_layout.gd as it stood before C2 — M1/M4 +1, M2/M3 -1 — and the mixer's expected output is
## hand-computed from MIX_GAIN = 0.2 at a yaw-only demand. Comparing against `MotorLayout.SPIN`
## instead would pass for a table that had been edited, which is precisely the failure this pins.
static func _test_the_default_is_todays_constants() -> Array:
	var results: Array = []

	var expected := {"M1": 1.0, "M2": -1.0, "M3": -1.0, "M4": 1.0}
	var default_map := MotorLayout.spin_map({})

	var exact := default_map.size() == expected.size()
	for name in expected:
		exact = exact and default_map.has(name) and typeof(default_map[name]) == TYPE_FLOAT \
			and float(default_map[name]) == float(expected[name])
	results.append(TestResult.new(
		"the default spin map is today's constants bit for bit: M1/M4 +1, M2/M3 -1",
		exact, "spin_map({}) = %s" % str(default_map)))

	# An absent `config` and an explicit props-out are the same aircraft — a build saved before the
	# Config room existed must not fly differently from one that opened it and changed nothing.
	var props_out := MotorLayout.spin_map({"motor_spin": "props_out"})
	results.append(TestResult.new(
		"an absent config and an explicit props_out are the same map",
		props_out == default_map, "props_out = %s" % str(props_out)))

	# The pin that protects the CONTROL oracles: the mixer's own output at a yaw-only demand, from
	# literals. throttle 0.5, yaw +1, MIX_GAIN 0.2 -> delta = 0.2 * spin, collective unshifted.
	var mixed := MotorMixer.mix(0.5, 0.0, 0.0, 1.0)
	var mix_expected := {"M1": 0.7, "M2": 0.3, "M3": 0.3, "M4": 0.7}
	var mix_ok := true
	var mix_detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var got := float(mixed[name])
		mix_ok = mix_ok and absf(got - float(mix_expected[name])) < 1e-12
		mix_detail.append("%s=%.6f" % [name, got])
	results.append(TestResult.new(
		"the default mixer output at a yaw-only demand is unchanged from the constant table",
		mix_ok, "%s (expected %s)" % [", ".join(mix_detail), str(mix_expected)]))

	# And the same pin on the other caller: the yaw reaction's sign per motor, from literals.
	var torque_ok := true
	var torque_detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var yaw := float(MotorLayout.torque_from_motor(name, 0.0, 1.0, 0.1)["yaw"])
		torque_ok = torque_ok and yaw == float(expected[name])
		torque_detail.append("%s=%+.1f" % [name, yaw])
	results.append(TestResult.new(
		"the default yaw reaction per motor is unchanged from the constant table",
		torque_ok, ", ".join(torque_detail)))

	return results


## §4.3's real choice. Props-in is every motor reversed, and it is the whole point of the value
## being authored that the yaw reaction genuinely changes sign.
static func _test_props_in_flips_every_motor() -> Array:
	var results: Array = []

	var flipped := MotorLayout.spin_map({"motor_spin": "props_in"})
	var ok := flipped.size() == 4
	for name in MotorLayout.MOTOR_NAMES:
		ok = ok and float(flipped[name]) == -float(MotorLayout.spin_map({})[name])
	results.append(TestResult.new(
		"props_in reverses every motor relative to the default",
		ok, "props_in = %s" % str(flipped)))

	var yaw := float(MotorLayout.torque_from_motor("M1", 0.0, 1.0, 0.1,
		Vector3.ZERO, {"motor_spin": "props_in"})["yaw"])
	results.append(TestResult.new(
		"a props_in build's yaw reaction on M1 is the opposite sign",
		yaw == -1.0, "yaw=%+.1f" % yaw))

	return results


## §5.1 — the two readers of the old constant, held against each other on a map that is neither
## the default nor its exact negation, so a caller that ignored `config` entirely and a caller
## that flipped everything are both caught.
static func _test_both_callers_read_the_same_map() -> Array:
	var results: Array = []

	var config := {"motor_spin": UNFLYABLE}
	var mixed := MotorMixer.mix(0.5, 0.0, 0.0, 1.0, config)

	var agree := true
	var detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		# The mixer's yaw response: above the collective means this motor is pushed up by +yaw.
		var mixer_sign := signf(float(mixed[name]) - 0.5)
		var torque_sign := signf(float(MotorLayout.torque_from_motor(
			name, 0.0, 1.0, 0.1, Vector3.ZERO, config)["yaw"]))
		var authored := signf(float(UNFLYABLE[name]))
		agree = agree and mixer_sign == authored and torque_sign == authored
		detail.append("%s mixer %+.0f / torque %+.0f / authored %+.0f" % [
			name, mixer_sign, torque_sign, authored])
	results.append(TestResult.new(
		"MotorMixer.mix and MotorLayout.torque_from_motor read the same authored map",
		agree, " · ".join(detail)))

	return results


## The accessor does not sanitise. §5.3 turns on this: a map Lothal thinks is wrong is still the
## map it flies, and a "helpful" correction here would make the warning a lie.
static func _test_an_authored_map_is_taken_verbatim() -> Array:
	var results: Array = []

	var got := MotorLayout.spin_map({"motor_spin": UNFLYABLE})
	var verbatim := true
	for name in MotorLayout.MOTOR_NAMES:
		verbatim = verbatim and float(got[name]) == float(UNFLYABLE[name])
	results.append(TestResult.new(
		"an unflyable authored map is returned verbatim, not corrected",
		verbatim, "spin_map = %s" % str(got))	)

	# A partial map keeps the default for every motor it does not mention, and a nonsense value is
	# not allowed to become a third spin direction.
	var partial := MotorLayout.spin_map({"motor_spin": {"M2": 1.0, "M3": "sideways"}})
	results.append(TestResult.new(
		"an unnamed motor keeps its default, and a non-numeric entry does not become a new direction",
		float(partial["M1"]) == 1.0 and float(partial["M2"]) == 1.0
			and float(partial["M3"]) == -1.0 and float(partial["M4"]) == 1.0,
		"partial = %s" % str(partial))	)

	return results


## The path §5 actually asks for: the persisted `config` block -> Build -> the sim's two readers.
static func _test_the_map_reaches_the_physics_from_the_build() -> Array:
	var results: Array = []

	var catalog := PartsCatalog.load_default()
	var project := Project.create("config C2")
	project.parts = {
		"frame": ReferenceBuild.FRAME_ID, "motor": ReferenceBuild.MOTOR_ID,
		"propeller": ReferenceBuild.PROPELLER_ID, "battery": ReferenceBuild.BATTERY_ID,
		"esc": ReferenceBuild.ESC_ID, "flight_controller": ReferenceBuild.FC_ID,
	}
	project.config["motor_spin"] = "props_in"
	var build := project.to_build(catalog)

	results.append(TestResult.new(
		"Project.to_build carries the config block onto the Build",
		build != null and String(build.config.get("motor_spin", "")) == "props_in",
		"build config = %s" % ("(no build)" if build == null else str(build.config))))

	var core_map: Dictionary = {} if build == null else MotorLayout.spin_map(build.build_drone_core().config)
	results.append(TestResult.new(
		"the drone core the build hands the sim flies the authored map",
		not core_map.is_empty() and float(core_map.get("M1", 0.0)) == -1.0,
		"core map = %s" % str(core_map)))

	# And the inner loop, which is the other half of the aircraft: a controller given the config
	# mixes yaw the authored way.
	var controller := RateModeController.new()
	controller.config = {"motor_spin": "props_in"}
	var cmds := controller.update(Vector3(0, 0, 1), Vector3.ZERO, 0.5, 0.01)
	var default_cmds := RateModeController.new().update(Vector3(0, 0, 1), Vector3.ZERO, 0.5, 0.01)
	results.append(TestResult.new(
		"RateModeController mixes through the config it was given",
		signf(float(cmds["M1"]) - 0.5) == -signf(float(default_cmds["M1"]) - 0.5)
			and float(default_cmds["M1"]) != 0.5,
		"M1 %.4f vs default %.4f" % [float(cmds["M1"]), float(default_cmds["M1"])]))

	return results


## §5.3, in three parts: the warning fires, NOTHING is blocked, and the aircraft really is wrong.
static func _test_a_wrong_map_flies_badly_and_is_not_blocked() -> Array:
	var results: Array = []

	# Fore-aft symmetric, so the only asymmetry in the flight check below is the spin map: a real
	# centre-of-mass offset tips an untrimmed quad and would muddy the yaw reading.
	var build := ReferenceBuild.fore_aft_symmetric()
	build.set_config({"motor_spin": UNFLYABLE})

	var fired: BuildWarning = null
	for w in ConfigPlausibility.warnings_for(build):
		if w.id == &"motor_spin_unflyable":
			fired = w
	results.append(TestResult.new(
		"an adjacent-pair spin map raises motor_spin_unflyable at impossible severity",
		fired != null and fired.severity == BuildWarning.Severity.IMPOSSIBLE,
		"fired = %s" % ("(none)" if fired == null else "%s / %s" % [
			BuildWarning.severity_name(fired.severity), fired.message])))

	# Registered where every other module is, or it is a check nothing shows.
	var ids: Array[StringName] = []
	for w in build.warnings():
		ids.append(w.id)
	results.append(TestResult.new(
		"Build.warnings() carries the config check, like the eleven modules beside it",
		ids.has(&"motor_spin_unflyable"), "ids = %s" % str(ids))	)

	# A correct map says nothing — a warning that fires on every build is not a check.
	var good := ReferenceBuild.fore_aft_symmetric()
	var quiet := true
	for w in ConfigPlausibility.warnings_for(good):
		quiet = quiet and w.id != &"motor_spin_unflyable"
	results.append(TestResult.new(
		"the default build is not accused of an unflyable spin map",
		quiet, "quiet = %s" % quiet))

	# NOT BLOCKED, and flown as authored: four equal throttles on a map whose reactions no longer
	# cancel spins the aircraft up about yaw, where the same commands on the default map do not.
	var bad_yaw := _yaw_rate_after_a_second(build)
	var good_yaw := _yaw_rate_after_a_second(good)
	results.append(TestResult.new(
		"the wrong map is flown, not refused: the aircraft spins up about yaw where the default does not",
		absf(bad_yaw) > 1.0 and absf(good_yaw) < 1e-6,
		"wrong %.4f rad/s vs default %.9f rad/s" % [bad_yaw, good_yaw]))

	return results


## Four equal throttles, one second, and the body-yaw rate that results. Equal commands so the
## ONLY asymmetry available is the spin map.
static func _yaw_rate_after_a_second(build: Build) -> float:
	var core := build.build_drone_core()
	core.prime_motors(0.5)
	var cmds := {}
	for name in MotorLayout.MOTOR_NAMES:
		cmds[name] = 0.5
	for i in 500:
		core.step(cmds, 1.0 / 500.0)
	return core.rigid_body.angular_velocity_rad_s.y
