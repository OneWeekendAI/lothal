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

	return results
