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

	var hud := DsHud.new()
	var course := GateCourse.new()
	var timer := LapTimer.new(course.fingerprint(), "user://test_hud_lap.json")

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
			and core.observables.voltage_live_v > 0.0,
		"reads \"%s\" (V_live = %.2f V)" % [hud._voltage_label.text, core.observables.voltage_live_v]
	))

	# A pack under heavy sag must be shown as such rather than in the calm colour.
	#
	# These drive core.observables rather than DroneCore's internals, because observables
	# is what the HUD actually consumes — a test that writes a field the renderer no longer
	# reads passes or fails for reasons unrelated to the renderer. That physics fills those
	# observables correctly in the first place is a separate claim, checked against a real
	# stepped simulation in test_observables.gd.
	var nominal: float = float(build.battery["specs"]["nominal_v"])
	core.observables.voltage_live_v = nominal * 0.70
	hud.render(core, build, course, timer, false)
	var sagging_color: Color = hud._voltage_label.get_theme_color("font_color")
	core.observables.voltage_live_v = nominal
	hud.render(core, build, course, timer, false)
	var healthy_color: Color = hud._voltage_label.get_theme_color("font_color")

	results.append(TestResult.new(
		"a hard-sagging pack turns the voltage readout red, a healthy one does not",
		sagging_color.is_equal_approx(DsHud.COLOR_CRITICAL) and healthy_color.is_equal_approx(DsHud.COLOR_OK),
		"70%% of nominal -> %s, nominal -> %s" % [sagging_color, healthy_color]
	))

	results.append(TestResult.new(
		"speed readout converts m/s to km/h",
		_speed_text_for(hud, build, core, course, timer, 10.0) == "36 km/h",
		"10 m/s reads \"%s\"" % _speed_text_for(hud, build, core, course, timer, 10.0)
	))

	results.append(TestResult.new(
		"gate counter names the gate that is actually due",
		hud._gate_label.text == "Gate 1 of 8",
		"reads \"%s\" with next_gate_index = %d" % [hud._gate_label.text, course.next_gate_index]
	))

	var gate: Dictionary = course.gates[0]
	course.advance(gate["position"] - gate["normal"] * 0.5, gate["position"] + gate["normal"] * 0.5)
	hud.render(core, build, course, timer, true)
	results.append(TestResult.new(
		"the gate counter advances, and the mode readout follows the flight mode",
		hud._gate_label.text == "Gate 2 of 8" and hud._mode_label.text == "Full manual (acro)",
		"reads \"%s\" / \"%s\"" % [hud._gate_label.text, hud._mode_label.text]
	))

	# S3: every other value text, the mode in plain words, banner, REC, warnings, and the walk.
	hud.render(core, build, course, timer, false)
	results.append(TestResult.new("flight mode reads in plain words, never ANGLE or ACRO alone",
		hud._mode_label.text == "Self-levelling" and not hud._mode_label.text.contains("ANGLE"),
		"reads \"%s\"" % hud._mode_label.text))
	timer.best_lap_s = 61.5
	timer.running = true
	timer.current_lap_s = 12.34
	hud.render(core, build, course, timer, false)
	results.append(TestResult.new("lap and best read as clock times",
		hud._current_lap_label.text == "Lap  %s" % LapTimer.format(12.34)
			and hud._best_lap_label.text == "Best  %s" % LapTimer.format(61.5),
		"\"%s\" / \"%s\"" % [hud._current_lap_label.text, hud._best_lap_label.text]))
	results.append(TestResult.new("pack line reads percent and time left",
		hud._pack_label.text.contains("%") and hud._pack_label.text.contains("left"),
		"reads \"%s\"" % hud._pack_label.text))
	hud.show_banner("NEW BEST", 1.0)
	results.append(TestResult.new("banner shows its text, then clears after its time",
		hud._banner_label.text == "NEW BEST" and hud._banner_panel.visible
			and _cleared_after(hud, 1.5),
		"text \"%s\"" % hud._banner_label.text))
	hud.set_recording(true, 75.0, 1200)
	results.append(TestResult.new("REC line shows elapsed clock and rows, and hides when stopped",
		hud._record_label.visible and hud._record_label.text.contains("1:15")
			and hud._record_label.text.contains("1200"),
		"reads \"%s\"" % hud._record_label.text))
	hud.set_recording(false)
	results.append(TestResult.new("REC line hides when recording stops", not hud._record_label.visible, ""))

	# Warnings: none on the reference build's HUD panel when it has none; named when it has some.
	var catalog2 := PartsCatalog.load_default()
	var bad := Build.from_ids(catalog2, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		"prop_7x4x3", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID)
	hud.show_warnings(bad)
	results.append(TestResult.new("the HUD lists the build's warnings (props over the frame clearance)",
		hud._warnings_panel.visible and hud._warnings_label.text.contains("props exceed"),
		"reads \"%s\"" % hud._warnings_label.text))
	var quiet := ReferenceBuild.build()
	var quiet_n := quiet.warnings().size()
	hud.show_warnings(quiet)
	results.append(TestResult.new("the warnings panel matches Build.warnings() for a quieter build",
		hud._warnings_panel.visible == (quiet_n > 0), "%d warnings" % quiet_n))

	var banned: Array = []
	_walk_variations(hud, banned)
	results.append(TestResult.new("no node carries ReadoutLabel, TitleLabel or MutedLabel",
		banned.is_empty(), str(banned)))
	results.append(TestResult.new("the scene walk is not vacuous", _count(hud) > 20, "%d nodes" % _count(hud)))

	# Nodes built outside the scene tree are not reference-counted, and leaving them behind
	# makes the runner exit with leaked-RID ERRORs that read exactly like a failing suite.
	hud.free()

	return results

static func _speed_text_for(hud: DsHud, build: Build, core: DroneCore, course: GateCourse,
		timer: LapTimer, airspeed_mps: float) -> String:
	core.observables.airspeed_mps = airspeed_mps
	hud.render(core, build, course, timer, false)
	return hud._speed_label.text


static func _cleared_after(hud: DsHud, seconds: float) -> bool:
	hud.tick_banner(seconds)
	return not hud._banner_panel.visible


static func _walk_variations(n: Node, out: Array) -> void:
	if n is Control and String((n as Control).theme_type_variation) in ["ReadoutLabel", "TitleLabel", "MutedLabel"]:
		out.append("%s:%s" % [n.name, (n as Control).theme_type_variation])
	for c in n.get_children():
		_walk_variations(c, out)


static func _count(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count(c)
	return k
