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

	return results
