class_name TestHud
extends RefCounted
## The HUD is a renderer of the observables layer, so everything except the pixels is
## testable headlessly — and the pixels were checked separately with tests/capture_frame.gd.
##
## The check with teeth is the throttle bar. It would be much easier to draw the stick
## position, and it would look right in every hover screenshot while being wrong exactly
## when it matters: in angle mode the controller moves the motors away from the commanded
## throttle constantly, and a pack that is sagging reaches less RPM for the same command.
## The bar has to follow the motors, not the stick.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)

	var hud := Hud.new()
	var course := GateCourse.new()
	var timer := LapTimer.new("user://test_hud_lap.json")

	var core := build.build_drone_core()
	core.prime_motors(build.hover_throttle())
	hud.render(core, build, course, timer, false)

	var hover_reading: float = hud._throttle_bar.value
	results.append(TestResult.new(
		"throttle bar reads a sane fraction at hover, not 0 or pinned",
		hover_reading > 5.0 and hover_reading < 80.0,
		"bar = %.0f %% at hover" % hover_reading
	))

	# Same drone, motors spun up much harder: the bar must move even though nothing about
	# the "stick" was touched here at all.
	core.prime_motors(build.max_throttle_fraction())
	hud.render(core, build, course, timer, false)
	var full_reading: float = hud._throttle_bar.value
	results.append(TestResult.new(
		"throttle bar follows actual motor RPM, not the stick",
		full_reading > hover_reading + 20.0,
		"hover %.0f %% -> full %.0f %%" % [hover_reading, full_reading]
	))

	results.append(TestResult.new(
		"voltage readout shows live pack voltage and current",
		hud._voltage_label.text.contains("V") and hud._voltage_label.text.contains("A")
			and core.last_voltage_v > 0.0,
		"reads \"%s\" (V_live = %.2f V)" % [hud._voltage_label.text, core.last_voltage_v]
	))

	# A pack under heavy sag must be shown as such rather than in the calm colour.
	var nominal: float = float(build.battery["specs"]["nominal_v"])
	core.last_voltage_v = nominal * 0.70
	hud.render(core, build, course, timer, false)
	var sagging_color: Color = hud._voltage_label.get_theme_color("font_color")
	core.last_voltage_v = nominal
	hud.render(core, build, course, timer, false)
	var healthy_color: Color = hud._voltage_label.get_theme_color("font_color")

	results.append(TestResult.new(
		"a hard-sagging pack turns the voltage readout red, a healthy one does not",
		sagging_color.is_equal_approx(Hud.COLOR_CRITICAL) and healthy_color.is_equal_approx(Hud.COLOR_OK),
		"70%% of nominal -> %s, nominal -> %s" % [sagging_color, healthy_color]
	))

	results.append(TestResult.new(
		"speed readout is in km/h and tracks the rigid body",
		_speed_text_for(hud, build, core, course, timer, Vector3(0, 0, -10.0)) == "36 km/h",
		"10 m/s reads \"%s\"" % _speed_text_for(hud, build, core, course, timer, Vector3(0, 0, -10.0))
	))

	results.append(TestResult.new(
		"gate counter names the gate that is actually due",
		hud._gate_label.text == "GATE 1 / 8",
		"reads \"%s\" with next_gate_index = %d" % [hud._gate_label.text, course.next_gate_index]
	))

	var gate: Dictionary = course.gates[0]
	course.advance(gate["position"] - gate["normal"] * 0.5, gate["position"] + gate["normal"] * 0.5)
	hud.render(core, build, course, timer, true)
	results.append(TestResult.new(
		"the gate counter advances, and the mode readout follows the flight mode",
		hud._gate_label.text == "GATE 2 / 8" and hud._mode_label.text == "ACRO",
		"reads \"%s\" / \"%s\"" % [hud._gate_label.text, hud._mode_label.text]
	))

	# Nodes built outside the scene tree are not reference-counted, and leaving them behind
	# makes the runner exit with leaked-RID ERRORs that read exactly like a failing suite.
	hud.free()

	return results

static func _speed_text_for(hud: Hud, build: Build, core: DroneCore, course: GateCourse,
		timer: LapTimer, velocity: Vector3) -> String:
	core.rigid_body.velocity_mps = velocity
	hud.render(core, build, course, timer, false)
	return hud._speed_label.text
