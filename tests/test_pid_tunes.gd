class_name TestPidTunes
extends RefCounted
## The builder's own gains, and whether they survive the app closing.
##
## The one property worth being loud about: a tune is stored PER BUILD. A tune that followed the
## user from a 65 mm whoop to a 10" long-range would recreate exactly the bug RateTune exists to
## fix, with the builder's own numbers instead of the project's — which would be worse, because
## they would have every reason to trust it.

const TEST_PATH := "user://test_pid_tunes.json"

const WHOOP := "frame_65mm_whoop"
const LONG_RANGE := "frame_10in_long_range"


static func _build(frame_id: String) -> Build:
	return Build.from_ids(PartsCatalog.load_default(), frame_id, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)


## Source-reading helpers, borrowed in shape from tests/test_control_path.gd — comments stripped so
## that a file MENTIONING a call in prose does not read as making it.
static func _code_only(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		var hash_index := line.find("#")
		lines.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(lines)


static func _gd_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name in DirAccess.get_files_at(dir_path):
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	for name in DirAccess.get_directories_at(dir_path):
		out.append_array(_gd_files(dir_path.path_join(name)))
	return out


static func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


static func run() -> Array:
	var results: Array = []
	_clean()

	var whoop := _build(WHOOP)
	var long_range := _build(LONG_RANGE)

	# --- A build with nothing saved gets the derived tune, not zeros ------------------------
	var fresh := PidTunes.load_from(TEST_PATH)
	var derived := RateTune.derive(whoop)
	results.append(TestResult.new(
		"a build with nothing saved gets the derived tune",
		fresh.tune_for(whoop).kp == derived.kp and not fresh.tune_for(whoop).has_overrides(),
		"kp %s" % fresh.tune_for(whoop).kp))

	# --- Round trip -------------------------------------------------------------------------
	var edited := fresh.tune_for(whoop)
	edited.set_gains(0, Vector3(3.5, 0.22, 0.05))
	edited.set_gains(2, Vector3(1.1, 0.07, 0.0))
	fresh.remember(whoop, edited)
	results.append(TestResult.new(
		"the tune file is written",
		fresh.save(TEST_PATH) and FileAccess.file_exists(TEST_PATH),
		TEST_PATH))

	var reloaded := PidTunes.load_from(TEST_PATH)
	var back := reloaded.tune_for(whoop)
	results.append(TestResult.new(
		"hand-set gains round-trip through the file exactly",
		back.gains_for(0) == Vector3(3.5, 0.22, 0.05) and back.gains_for(2) == Vector3(1.1, 0.07, 0.0),
		"roll %s, yaw %s" % [back.gains_for(0), back.gains_for(2)]))
	results.append(TestResult.new(
		"an axis that was never set still comes back DERIVED, not stored",
		not back.is_overridden(1) and back.kp.y == derived.derived_kp.y,
		"pitch kp %.4f against the derived %.4f" % [back.kp.y, derived.derived_kp.y]))

	# --- THE ONE THAT MATTERS ---------------------------------------------------------------
	var other := reloaded.tune_for(long_range)
	results.append(TestResult.new(
		"a tune saved on the whoop does NOT follow the builder to the 10\" long-range",
		not other.has_overrides() and other.kp == RateTune.derive(long_range).kp,
		"10\" roll kp %.3f, which is its own derived %.3f and not the whoop's %.3f" % [
			other.kp.x, RateTune.derive(long_range).derived_kp.x, 3.5]))

	# --- Reset ------------------------------------------------------------------------------
	reloaded.forget(whoop)
	var reset := reloaded.tune_for(whoop)
	results.append(TestResult.new(
		"resetting returns the build to its derived baseline in one action",
		not reset.has_overrides() and reset.kp == derived.derived_kp,
		"back to kp %s" % reset.kp))

	# --- A bad file is not a fatal error ----------------------------------------------------
	# Same rule as AssemblyTweaks and PackCharge: missing, truncated, wrong shape and wrong type
	# all land on defaults, and Lab opens. A workbench that will not start because a preferences
	# file is half-written has made a preference more important than the product.
	var broken := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	broken.store_string("{\"schema\": 1, \"tunes\": {\"%s\": {\"roll\": {\"p\": \"fast\"}}}" % whoop.fingerprint())
	broken.close()
	var salvaged := PidTunes.load_from(TEST_PATH)
	results.append(TestResult.new(
		"a truncated or mistyped tune file loads as the derived tune rather than failing",
		salvaged.tune_for(whoop).kp == derived.derived_kp,
		"kp %s" % salvaged.tune_for(whoop).kp))

	# --- Unknown fields survive a round trip ------------------------------------------------
	# A file written by a later Lothal holds keys this one has never heard of. Opening an older
	# build must not silently destroy a newer one's settings.
	var forward := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	forward.store_string(JSON.stringify({
		"schema": 1, "feedforward": {"roll": 0.9},
		"tunes": {whoop.fingerprint(): {"roll": {"p": 4.0, "i": 0.2, "d": 0.03}, "tpa": 0.6}}}))
	forward.close()
	var carried := PidTunes.load_from(TEST_PATH)
	carried.save(TEST_PATH)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	results.append(TestResult.new(
		"fields a later version wrote are kept, not dropped",
		document.has("feedforward") and (document["tunes"][whoop.fingerprint()] as Dictionary).has("tpa"),
		"kept: %s" % ", ".join(document.keys())))

	# --- SIM AUTHORS NOTHING ------------------------------------------------------------------
	#
	# The corollary that settled where tuning lives, and it is an ABSENCE — so it is checked by
	# reading the source, the way test_control_path.gd checks that nothing in src/fc/ names the
	# body's true angular velocity. An absence cannot be caught at runtime: a Sim that quietly saved
	# a tune would produce entirely plausible numbers, right up until a flight rewrote a garage
	# decision.
	var writers: PackedStringArray = []
	for path in _gd_files("res://src"):
		if path == "res://src/lab/pid_tunes.gd":
			continue   # its own definition, not a call
		var code := _code_only(FileAccess.get_file_as_string(path))
		if not (code.contains("pid_tunes.save") or code.contains("pid_tunes.remember")
				or code.contains("pid_tunes.forget")):
			continue
		writers.append(path.get_file())
	results.append(TestResult.new(
		"only Lab writes a tune — nothing in the flight path does",
		writers.size() == 1 and writers[0] == "lab_screen.gd",
		"writers: %s" % ("none" if writers.is_empty() else ", ".join(writers))))

	# Checked positively too, because an empty file would satisfy the absence above: the field has
	# to actually READ the tune, or the derivation never reaches anything that flies.
	var sim_code := _code_only(FileAccess.get_file_as_string("res://src/scenes/main.gd"))
	results.append(TestResult.new(
		"the field flies the tune the garage set, adopted on the one path a part change lands on",
		sim_code.contains("fc.rate_loop.adopt_tune(pid_tunes.tune_for(build))"),
		"main.gd adopts the tune in _on_build_changed"))

	# --- THE PANEL --------------------------------------------------------------------------
	#
	# Driven through apply_axis(), which is the same path a mouse drives. Range.value_changed does
	# not fire for code-set values on 4.7.1, so a test that only set the field and waited would be
	# asserting on a signal that never arrives — and would pass for a panel wired to nothing.
	var panel := TunePanel.new()
	var panel_build := _build(LONG_RANGE)
	var panel_tune := RateTune.derive(panel_build)
	panel.render(panel_build, panel_tune)

	results.append(TestResult.new(
		"the panel opens on the derived tune and says the plant it came from",
		panel.rendered_text().contains("%.3f" % panel_tune.derived_kp.x)
			and panel.rendered_text().contains("rad/s"),
		panel.rendered_text().split("\n")[3]))

	panel.set_field(0, "p", 9.0)
	panel.apply_axis(0)
	results.append(TestResult.new(
		"editing a field changes the tune in force and keeps the derived baseline on screen",
		panel_tune.kp.x == 9.0 and panel_tune.derived_kp.x != 9.0
			and panel.rendered_text().contains("Derived  P %.3f" % panel_tune.derived_kp.x),
		"in force %.2f, still showing derived %.3f" % [panel_tune.kp.x, panel_tune.derived_kp.x]))

	panel.reset_axis(0)
	results.append(TestResult.new(
		"reverting one axis is one action and leaves the others alone",
		panel_tune.kp.x == panel_tune.derived_kp.x and not panel_tune.is_overridden(0),
		"roll back to %.3f" % panel_tune.kp.x))

	# Warn, never block: the widget must not be the thing that stops an absurd gain, or "warnings
	# not blocks" has been quietly reversed by a max_value.
	panel.set_field(2, "p", 380.0)
	panel.apply_axis(2)
	results.append(TestResult.new(
		"an absurd gain typed into the panel is accepted, not clamped away",
		panel_tune.kp.z == 380.0,
		"yaw P held at %.1f" % panel_tune.kp.z))

	# Created outside the tree, so it is freed rather than queue_freed.
	panel.free()

	_clean()
	return results
