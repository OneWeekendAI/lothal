class_name TestWarningRows
extends RefCounted
## Lab dock design §3/§5.1: every warning also carries {item, severity, short, long}.
##
## `item` is the Lab-list row that owns it, `short` is that row's third line (<= 38 characters, so
## "⚠ " + short stays inside §3's ~40), and `long` is the sentence the warning always had. The long
## text is asserted unchanged by the existing suites (test_build_warnings and friends), which is why
## this file only asserts that `long` IS `message`.
##
## ONE RESULT PER CASE, never a loop that fails once (feedback: loop tests hide coverage) — the id
## coverage emits one line per id found in the source, and the length check one line per warning.

const CINELIFTER := ["frame_7in_cinelifter", "motor_2808_1300kv", "prop_5x43x2",
	"battery_4s_650", "esc_4in1_80a_30x30"]
const CANNOT_FLY := ["frame_3in_toothpick", "motor_1103_8000kv", "prop_3x3x3",
	"battery_6s_4000_liion", "esc_aio_5a_whoop"]
const FIELD_VEHICLE := ["frame_5in_deadcat", "motor_f60proii_2207_1750kv", "prop_35x28x3",
	"battery_4s_650", "esc_4in1_45a_30x30"]


static func run() -> Array:
	var results: Array = []
	results.append_array(_every_source_id_has_a_row())
	results.append(_pack_current_limit_goes_on_battery())
	results.append(_esc_current_limit_goes_on_esc())
	results.append(_motor_current_limit_goes_on_motors())
	results.append(_the_short_is_computed_from_the_values())
	results.append(_long_is_the_message())
	results.append(_severity_is_carried())
	results.append(_an_unknown_id_has_no_item())
	results.append(_a_long_short_is_clipped())
	var catalog := PartsCatalog.load_default()
	for fixture in [CINELIFTER, CANNOT_FLY, FIELD_VEHICLE]:
		results.append_array(_every_real_warning_has_a_short_row(catalog, fixture))
	return results


## Every id a BuildWarning is constructed with anywhere in src/ — the literal `&"id"` form and the
## constant form (`NAME`, `GATE_BELOW_GROUND` …) — has an entry in the table.
static func _every_source_id_has_a_row() -> Array:
	var out: Array = []
	var ids := {}
	var files: Array[String] = []
	_scan("res://src", files)
	var literal := RegEx.create_from_string(
		"BuildWarning\\.(impossible|limiting|characteristic)\\(\\s*&\"([a-z_0-9]+)\"")
	# The long form FrameWarnings uses — `BuildWarning.new(Severity.X,\n &"id", …)` — which the
	# literal pattern above cannot see; before it was scanned, eight frame ids had no row at all.
	var long_form := RegEx.create_from_string(
		"BuildWarning\\.new\\(\\s*BuildWarning\\.Severity\\.[A-Z]+,\\s*&\"([a-z_0-9]+)\"")
	var constant := RegEx.create_from_string("const [A-Z_]+ := &\"([a-z_0-9]+)\"")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in literal.search_all(text):
			ids[m.get_string(2)] = path
		for m in long_form.search_all(text):
			ids[m.get_string(1)] = path
		# Constants are only warning ids in the files that build warnings from them.
		if text.contains("BuildWarning.") and (path.ends_with("course_warnings.gd")
				or path.ends_with("prop_extrapolation.gd")):
			for m in constant.search_all(text):
				ids[m.get_string(1)] = path
	# The stack-fit helper takes its id as an argument; both callers name it in build.gd.
	ids["stack_mount"] = "res://src/assembly/build.gd"
	ids["fc_stack_mount"] = "res://src/assembly/build.gd"
	if ids.size() < 60:
		out.append(TestResult.new("warning rows: the source scan found the warning ids", false,
			"only %d ids found — the scan is broken, so the per-id checks below mean nothing" % ids.size()))
	for id in ids:
		out.append(TestResult.new("warning rows: '%s' has a row" % id,
			WarningRows.has(StringName(id)), "declared in %s" % ids[id]))
	return out


static func _scan(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), into)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			into.append(dir_path.path_join(file))


static func _current_limit(limited_by: String) -> BuildWarning:
	return BuildWarning.limiting(&"current_limit", "sentence",
		{"limited_by": limited_by, "limit_amps": 60.0, "throttle_cap": 0.78})


static func _pack_current_limit_goes_on_battery() -> TestResult:
	var w := _current_limit("battery")
	return TestResult.new("warning rows: a pack current limit is Battery's, not Motors'",
		w.item == WarningRows.BATTERY and w.short == "pack limits you to 78% throttle",
		"item=%s short='%s'" % [w.item, w.short])


static func _esc_current_limit_goes_on_esc() -> TestResult:
	var w := _current_limit("esc")
	return TestResult.new("warning rows: an ESC current limit is the ESC's",
		w.item == WarningRows.ESC and w.short == "ESC limits you to 78% throttle",
		"item=%s short='%s'" % [w.item, w.short])


static func _motor_current_limit_goes_on_motors() -> TestResult:
	var w := _current_limit("motor")
	return TestResult.new("warning rows: a motor current limit is the Motors'",
		w.item == WarningRows.MOTORS and w.short == "motor limits you to 78% throttle",
		"item=%s short='%s'" % [w.item, w.short])


static func _the_short_is_computed_from_the_values() -> TestResult:
	var w := BuildWarning.limiting(&"pack_sag", "x", {"usable_fraction": 0.614})
	return TestResult.new("warning rows: a short quotes the warning's own number",
		w.short == "sag: 61% of bench thrust", "short='%s'" % w.short)


static func _long_is_the_message() -> TestResult:
	var w := BuildWarning.impossible(&"prop_clearance", "The whole sentence, unchanged.",
		{"max_prop_inches": 5.0})
	return TestResult.new("warning rows: long is the message, word for word",
		w.long() == "The whole sentence, unchanged." and w.message == w.long(),
		"long='%s'" % w.long())


static func _severity_is_carried() -> TestResult:
	var w := BuildWarning.characteristic(&"custom_motor", "x")
	return TestResult.new("warning rows: severity travels with the row fields",
		w.severity == BuildWarning.Severity.CHARACTERISTIC and w.item == WarningRows.MOTORS,
		"severity=%d item=%s" % [w.severity, w.item])


static func _an_unknown_id_has_no_item() -> TestResult:
	var w := BuildWarning.limiting(&"no_such_warning_id", "x")
	return TestResult.new("warning rows: an unknown id has no row rather than a guessed one",
		w.item == &"" and w.short == "", "item=%s short='%s'" % [w.item, w.short])


static func _a_long_short_is_clipped() -> TestResult:
	var w := BuildWarning.impossible(&"motor_mount", "x",
		{"motor_pattern": "16x16 M3 and some very long text", "frame_pattern": "19x19 M3"})
	return TestResult.new("warning rows: a short never exceeds %d characters" % WarningRows.SHORT_MAX,
		w.short.length() <= WarningRows.SHORT_MAX and w.short.ends_with("…"),
		"%d chars: '%s'" % [w.short.length(), w.short])


static func _every_real_warning_has_a_short_row(catalog: PartsCatalog, ids: Array) -> Array:
	var out: Array = []
	var build := Build.from_ids(catalog, ids[0], ids[1], ids[2], ids[3], ids[4])
	var list := build.warnings()
	if list.is_empty():
		out.append(TestResult.new("warning rows: %s produces warnings to check" % ids[0], false,
			"no warnings — this fixture checks nothing"))
	for w in list:
		out.append(TestResult.new("warning rows: %s '%s' has an item and a short <= %d" % [
				ids[0], w.id, WarningRows.SHORT_MAX],
			w.item != &"" and w.short != "" and w.short.length() <= WarningRows.SHORT_MAX,
			"item=%s short='%s' (%d)" % [w.item, w.short, w.short.length()]))
	return out
