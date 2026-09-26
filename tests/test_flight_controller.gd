class_name TestFlightController
extends RefCounted
## The flight controller as a PART. Every check here is about a board the builder chose
## rather than a constant the project picked.
##
## The gyro model has existed since the control path was rebuilt, and it has always been
## correct — sample rate, PT1 cutoff, noise floor, bias, each with a comment explaining what
## it costs. What it was not, was CHOSEN. Those four quantities are properties of the IMU on
## the board you buy, and this suite is what holds them to that.

const EXPECTED_IDS := ["fc_f411_25x25_whoop", "fc_f405_20x20", "fc_f405_30x30",
	"fc_f722_30x30", "fc_h743_30x30", "fc_f405_30x30_budget"]

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var boards := catalog.list_category("flight_controller")

	results.append(TestResult.new(
		"the catalog loads six flight controllers, in file order",
		boards.size() == 6,
		"loaded %d entries" % boards.size()
	))

	var ids: Array = []
	for board in boards:
		ids.append(str(board["part_id"]))
	results.append(TestResult.new(
		"every expected board id is present",
		ids == EXPECTED_IDS,
		"got %s" % str(ids)
	))

	# Schema conformance. Every physics-bearing spec must be present and in a range that
	# could describe a real sensor — a zero cutoff is a divide-by-zero and a zero sample
	# rate is an infinite loop in Gyro.update().
	var malformed: Array = []
	for board in boards:
		var id: String = str(board.get("part_id", "?"))
		var specs: Dictionary = board.get("specs", {})
		var pattern: String = str(board.get("mounting", {}).get("pattern", ""))
		if float(board.get("mass_g", 0.0)) <= 0.0:
			malformed.append("%s: mass_g" % id)
		if str(board.get("category", "")) != "flight_controller":
			malformed.append("%s: category" % id)
		if MountPoint.parse_pattern_m(pattern) == Vector2.ZERO:
			malformed.append("%s: mounting.pattern" % id)
		if float(specs.get("gyro_sample_rate_hz", 0.0)) <= 0.0:
			malformed.append("%s: gyro_sample_rate_hz" % id)
		if float(specs.get("gyro_cutoff_hz", 0.0)) <= 0.0:
			malformed.append("%s: gyro_cutoff_hz" % id)
		if float(specs.get("gyro_noise_rad_s", -1.0)) < 0.0:
			malformed.append("%s: gyro_noise_rad_s" % id)
		if float(specs.get("gyro_bias_rad_s", -1.0)) < 0.0:
			malformed.append("%s: gyro_bias_rad_s" % id)
		if str(board.get("source", "")).strip_edges() == "":
			malformed.append("%s: source" % id)
	results.append(TestResult.new(
		"every board declares its physics-bearing specs, its mount and its source",
		malformed.is_empty(),
		"malformed fields: %s" % ("none" if malformed.is_empty() else str(malformed))
	))

	# The schema prose exists and states the two rules a contributor most needs.
	var schema := PartsCatalog.schema_for("flight_controller")
	results.append(TestResult.new(
		"the _schema states the two-tier rule and the mass-budget rule",
		schema.length() > 200 and schema.contains("specs") and schema.contains("catalog")
			and schema.to_lower().contains("budget"),
		"schema is %d chars" % schema.length()
	))

	# Loop rate is carried and INERT. If a future slice wires it in, this check is the one
	# that should be deleted deliberately rather than a claim quietly becoming true.
	var reads_loop_rate := false
	for path in ["res://src/sim/gyro.gd", "res://src/assembly/build.gd",
			"res://src/sim/drone_core.gd", "res://src/fc/flight_controller.gd"]:
		if FileAccess.get_file_as_string(path).contains("loop_rate_hz"):
			reads_loop_rate = true
	results.append(TestResult.new(
		"loop_rate_hz is catalog metadata: nothing in the physics reads it",
		not reads_loop_rate,
		"physics files naming loop_rate_hz: %s" % ("none" if not reads_loop_rate else "SOME")
	))

	# --- The gyro is configured FROM THE PART ---
	# One owner: Gyro.from_part is the only place catalog keys become gyro fields.
	var quiet := Gyro.from_part(catalog.get_part("fc_h743_30x30"))
	var loud := Gyro.from_part(catalog.get_part("fc_f405_30x30_budget"))
	results.append(TestResult.new(
		"from_part reads the board's own four specs, not the defaults",
		quiet.noise_rad_s == 0.0044 and quiet.sample_rate_hz == 8000.0
			and loud.noise_rad_s == 0.0069 and loud.sample_rate_hz == 3200.0,
		"H743 %.4f rad/s @ %.0f Hz, budget %.4f rad/s @ %.0f Hz"
			% [quiet.noise_rad_s, quiet.sample_rate_hz, loud.noise_rad_s, loud.sample_rate_hz]
	))

	# A partial entry degrades to the stock sensor rather than to zero. A zero cutoff is a
	# divide-by-zero and a zero sample rate is an infinite loop in update().
	var partial := Gyro.from_part({"specs": {"gyro_noise_rad_s": 0.01}})
	results.append(TestResult.new(
		"a board that omits a spec falls back to that field's default, not to zero",
		partial.noise_rad_s == 0.01 and partial.sample_rate_hz == Gyro.DEFAULT_SAMPLE_RATE_HZ
			and partial.cutoff_hz == Gyro.DEFAULT_CUTOFF_HZ
			and partial.bias_rad_s == Gyro.DEFAULT_BIAS_RAD_S,
		"noise %.4f, rate %.0f, cutoff %.0f, bias %s"
			% [partial.noise_rad_s, partial.sample_rate_hz, partial.cutoff_hz, partial.bias_rad_s]
	))

	# THE PIN. The reference board's JSON figures and Gyro's DEFAULT_* are two copies of the
	# same four numbers. The day one moves without the other, this says so by name.
	var stock := Gyro.from_part(catalog.get_part("fc_f405_30x30"))
	results.append(TestResult.new(
		"the reference board's specs ARE Gyro's stock defaults, to the digit",
		stock.sample_rate_hz == Gyro.DEFAULT_SAMPLE_RATE_HZ
			and stock.cutoff_hz == Gyro.DEFAULT_CUTOFF_HZ
			and stock.noise_rad_s == Gyro.DEFAULT_NOISE_RAD_S
			and stock.bias_rad_s == Gyro.DEFAULT_BIAS_RAD_S,
		"board %.0f Hz / %.0f Hz / %.4f / %s vs defaults %.0f / %.0f / %.4f / %s"
			% [stock.sample_rate_hz, stock.cutoff_hz, stock.noise_rad_s,
				stock.bias_rad_s, Gyro.DEFAULT_SAMPLE_RATE_HZ, Gyro.DEFAULT_CUTOFF_HZ,
				Gyro.DEFAULT_NOISE_RAD_S, Gyro.DEFAULT_BIAS_RAD_S]
	))

	# --- Choosing a different board changes what the FC actually SEES ---
	# Two aircraft, identical in every part but the board, stepped identically from rest.
	# The noisier board must deliver a measurably noisier signal — not merely store a
	# different number. That distinction is the whole slice: a check that compared
	# build.gyro().noise_rad_s would pass on a Gyro that was never wired in.
	var dt := 0.001
	var rms: Dictionary = {}
	for board_id in ["fc_h743_30x30", "fc_f405_30x30_budget"]:
		var core := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			board_id).build_drone_core()
		# Settle first, so what is measured is the noise floor and not the filter's
		# start-up transient from zero.
		for _i in 500:
			core.step(MotorMixer.mix(0.0, 0.0, 0.0, 0.0), dt)
		var sum_sq := 0.0
		var n := 4000
		for _i in n:
			core.step(MotorMixer.mix(0.0, 0.0, 0.0, 0.0), dt)
			var reading: Vector3 = core.observables.gyro_rad_s - core.rigid_body.angular_velocity_rad_s
			sum_sq += reading.length_squared()
		rms[board_id] = sqrt(sum_sq / float(n))

	var quiet_rms: float = rms["fc_h743_30x30"]
	var loud_rms: float = rms["fc_f405_30x30_budget"]
	results.append(TestResult.new(
		"a noisier board delivers a measurably noisier signal to the FC",
		loud_rms > quiet_rms * 1.3,
		"ICM-42688 board %.5f rad/s RMS error, BMI270 board %.5f — ratio %.2fx"
			% [quiet_rms, loud_rms, loud_rms / maxf(quiet_rms, 1e-9)]
	))

	# ONE gyro, and only one. That nothing in src/fc/ reaches around it to ground truth is
	# already checked, properly and with a comment stripper, by test_control_path.gd — this
	# is the half that check cannot make: that the sensor the aircraft flies is the one it
	# was HANDED, rather than a second one it built for itself. Two constructions here would
	# be two opinions about what board is fitted, and both would produce plausible numbers.
	var core_src := FileAccess.get_file_as_string("res://src/sim/drone_core.gd")
	var built: int = core_src.count("Gyro.new") + core_src.count("Gyro.from_part")
	results.append(TestResult.new(
		"DroneCore does not build itself a second gyro behind the one it was given",
		built <= 1,
		"drone_core.gd constructs %d gyros" % built
	))

	# And Build is the single source for the configuration the aircraft is flying.
	var wired := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		"fc_f405_30x30_budget")
	results.append(TestResult.new(
		"the aircraft flies the board Build says it does",
		wired.build_drone_core().gyro.noise_rad_s == wired.gyro().noise_rad_s
			and wired.gyro().noise_rad_s == 0.0069,
		"Build.gyro() %.4f, DroneCore's gyro %.4f"
			% [wired.gyro().noise_rad_s, wired.build_drone_core().gyro.noise_rad_s]
	))

	# --- THE MASS-BUDGET GUARD ---
	# The three fixed points, with the default board selected. If these move, mass was ADDED
	# to the 55 g electronics budget instead of taken OUT of it — which is the mistake this
	# whole slice is most likely to make, and the one that would silently move two of the
	# project's three oracles for what was meant to be a change to the catalog.
	# Hover is held to the project's OWN oracle tolerance (test_hover.gd: +/-0.02 of 0.29)
	# rather than a tighter one invented here. The solver returns 29.9% since PW2 re-baselined the
	# harness (29.6% before it); asserting a bound the project does not itself hold would
	# be this test disagreeing with the oracle it claims to be guarding.
	var ref := ReferenceBuild.build()
	results.append(TestResult.new(
		"the reference build is unchanged: 507.5 g, 11.43:1, 29.9% hover",
		absf(ref.all_up_weight_g() - 507.48) < 0.5
			and absf(ref.thrust_to_weight() - 11.43) < 0.05
			and absf(ref.hover_throttle() - 0.299) < 0.02,
		"%.1f g, %.2f:1, %.1f%% hover"
			% [ref.all_up_weight_g(), ref.thrust_to_weight(), ref.hover_throttle() * 100.0]
	))

	# A heavier board is carried honestly: the aircraft gains exactly the excess over the
	# budgeted share, and the lump does not move.
	var heavy := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		"fc_h743_30x30")
	var gained := heavy.all_up_weight_g() - ref.all_up_weight_g()
	results.append(TestResult.new(
		"a 12 g board makes the aircraft exactly 4 g heavier, not 12 g heavier",
		absf(gained - 4.0) < 0.01,
		"all-up went %.1f g -> %.1f g, a gain of %.2f g against a %.0f g budgeted share"
			% [ref.all_up_weight_g(), heavy.all_up_weight_g(), gained, Build.FC_BUDGET_MASS_G]
	))

	# And it says so, as a DESCRIPTION. Being 4 g heavier is a position on a continuum, not
	# a boundary in the physics (labs-and-sim.md §2.1), so it describes rather than warns —
	# and it certainly does not block.
	var budget_warning: BuildWarning = null
	for w in heavy.warnings():
		if w.id == &"fc_mass_budget":
			budget_warning = w
	results.append(TestResult.new(
		"an over-budget board is described, not scolded, and still builds",
		budget_warning != null
			and budget_warning.severity == BuildWarning.Severity.CHARACTERISTIC
			and heavy.mass_properties.total_mass_kg > 0.0,
		"warning: %s" % ("absent" if budget_warning == null else budget_warning.message)
	))

	# The reference board is exactly the budgeted share, so it says nothing at all.
	var quiet_on_budget := true
	for w in ref.warnings():
		if w.id == &"fc_mass_budget":
			quiet_on_budget = false
	results.append(TestResult.new(
		"a board that weighs its budgeted share says nothing about mass",
		quiet_on_budget,
		"reference board is %.0f g against a %.0f g share" % [ref.fc_mass_g(), Build.FC_BUDGET_MASS_G]
	))

	# --- Fit ---
	# A 20x20 board does not bolt to a 30.5x30.5 frame. §2.6's worked example: it still
	# MOUNTS, because zip-tying a mismatched board on is a thing real builders do on a
	# Saturday afternoon, and the useful answer is a sentence you can act on rather than a
	# dropdown that has greyed itself out.
	var mismatched := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		"fc_f405_20x20")
	var fit: BuildWarning = null
	var esc_fit_still_fine := true
	for w in mismatched.warnings():
		if w.id == &"fc_stack_mount":
			fit = w
		if w.id == &"stack_mount":
			esc_fit_still_fine = false
	results.append(TestResult.new(
		"a 20x20 board on a 30.5x30.5 frame is impossible to bolt, and still mounts",
		fit != null and fit.severity == BuildWarning.Severity.IMPOSSIBLE
			and mismatched.mass_properties.total_mass_kg > 0.0
			and mismatched.all_up_weight_g() > 0.0,
		"warning: %s" % ("absent" if fit == null else fit.message)
	))
	results.append(TestResult.new(
		"the FC's fit check is its own, and does not disturb the ESC's",
		esc_fit_still_fine,
		"the correctly-fitted ESC %s a mount warning"
			% ("did not raise" if esc_fit_still_fine else "RAISED")
	))
	results.append(TestResult.new(
		"the fit warning names both patterns, so it can be acted on",
		fit != null and fit.values.get("board_pattern", "") == "20x20"
			and fit.values.get("frame_pattern", "") == "30.5x30.5",
		"values: %s" % ("none" if fit == null else str(fit.values))
	))

	# And the reference board on the reference frame says nothing.
	var silent := true
	for w in ref.warnings():
		if w.id == &"fc_stack_mount":
			silent = false
	results.append(TestResult.new(
		"a board that bolts down is not mentioned",
		silent,
		"reference board is %s on a %s frame"
			% [ref.fc_mount_pattern(), ref.frame["specs"].get("stack_mount", "?")]
	))

	# --- The panel says what the sensor COSTS, not what it is ---
	# "Noise floor 0.0028 rad/s" means nothing. What it costs you in usable D does.
	var panel := FcDetails.new()
	panel.render(ref.fc, ref)
	var text := panel.rendered_text()
	panel.free()
	results.append(TestResult.new(
		"the details panel states filter lag in ms and noise in deg/s, not raw units",
		text.contains("ms") and text.contains("°/s") and not text.contains("rad/s"),
		"panel text: %s" % text.replace("\n", " | ")
	))

	# The D-term row is the one that turns a spec sheet into a decision, and it must be derived
	# from the filter the model ACTUALLY HAS. PIDController has no D-term lowpass, so the
	# derivative acts on whatever the gyro hands it — but what the gyro hands it has been through
	# the PT1, so successive readings are correlated and the step between them is much smaller
	# than two independent samples would give.
	#
	# This expectation is written out longhand rather than calling the panel's own helper,
	# because a test that asked the code for the answer it is checking would pass on any
	# formula at all. Treating the samples as independent reports six times this figure.
	var t := 1.0 / Gyro.DEFAULT_SAMPLE_RATE_HZ
	var rc := 1.0 / (TAU * Gyro.DEFAULT_CUTOFF_HZ)
	var a := t / (rc + t)
	var expected_d := RateModeController.ROLL_PITCH_KD \
		* Gyro.DEFAULT_NOISE_RAD_S * sqrt(2.0 * a * a / (2.0 - a)) \
		/ (t * RateModeController.MAX_RATE_RAD_S)
	results.append(TestResult.new(
		"the panel quotes what the noise floor costs at the installed D gain",
		text.contains("%.1f%%" % (expected_d * 100.0)),
		"expected %.2f%% of motor command from noise alone; panel says: %s"
			% [expected_d * 100.0, text.replace("\n", " | ")]
	))

	# A noisier board must read as costing more. If both boards printed the same figure the
	# row would be decoration.
	var loud_panel := FcDetails.new()
	var loud_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		"fc_f405_30x30_budget")
	loud_panel.render(loud_build.fc, loud_build)
	var loud_text := loud_panel.rendered_text()
	loud_panel.free()
	results.append(TestResult.new(
		"a noisier board reads as costing more at the motors",
		loud_text != text,
		"budget board panel differs from the reference board's: %s" % (loud_text != text)
	))

	# Loop rate appears, labelled as carried-and-unmodelled, exactly as the ESC's burst
	# rating is. Leaving it off the screen entirely would be its own kind of dishonesty.
	results.append(TestResult.new(
		"loop rate is shown and labelled as not modelled",
		text.contains("not modelled"),
		"panel text: %s" % text.replace("\n", " | ")
	))

	# The rail browses the three axes a builder actually decides along.
	var rail := FcPicker.new(catalog)
	rail.select_id("fc_h743_30x30")
	var picked: Dictionary = rail.selected_part()
	rail.free()
	results.append(TestResult.new(
		"the FC rail lists boards and selects by id",
		str(picked.get("part_id", "")) == "fc_h743_30x30",
		"selected %s" % str(picked.get("part_id", "none"))
	))

	# --- The field flies the board Lab shows ---
	# The selection dictionary is what crosses the door out of the garage (labs-and-sim.md §4).
	# A board that appeared on the rail but not in that dictionary would leave Lab describing
	# one aircraft while the field flew another — the precise divergence §2.2 exists to forbid,
	# and it would be invisible because both halves would produce plausible numbers.
	var panel_ids := {"flight_controller": "fc_f405_30x30_budget"}
	var field_panel := BuildPanel.new(catalog, panel_ids)
	# _rebuild() directly rather than parenting into the tree, as test_build_panel.gd does:
	# the panel is pure Control wiring and a headless SceneTree has no reason to be involved.
	field_panel._rebuild()
	var flown: Build = field_panel.build
	field_panel.free()
	results.append(TestResult.new(
		"a board chosen in Lab is the board the field builds",
		flown.fc.get("part_id", "") == "fc_f405_30x30_budget"
			and flown.gyro().noise_rad_s == 0.0069,
		"field built %s, flying a %.4f rad/s sensor"
			% [str(flown.fc.get("part_id", "none")), flown.gyro().noise_rad_s]
	))

	# And a selection that predates the category still loads, rather than failing on a missing
	# key deep inside Build. Saved configurations exist on disk from before this slice.
	var legacy := BuildPanel.new(catalog, {"frame": ReferenceBuild.FRAME_ID})
	legacy._rebuild()
	var legacy_build: Build = legacy.build
	legacy.free()
	results.append(TestResult.new(
		"a saved selection from before flight controllers existed still loads",
		legacy_build.fc.get("part_id", "") == Build.DEFAULT_FC_ID,
		"fell back to %s" % str(legacy_build.fc.get("part_id", "none"))
	))

	return results
