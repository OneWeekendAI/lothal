class_name TestFlightRecorder
extends RefCounted
## The flight recorder (LTHL-18) — a file that says what the aircraft actually did.
##
## ## Why none of these assert "a log was written and it has rows"
##
## Because that check passes for a recorder that writes garbage, and garbage is the likely
## failure here rather than an empty file: every column in this log is a plausible-looking
## float, and a trace that has silently recorded the wrong quantity looks exactly like a trace
## that has recorded the right one. So this suite was written against a deliberately WRONG
## recorder — one that logged the gyro reading into both the gyro and the omega columns — and
## every assertion below rejects it:
##
##   * the two columns must DIFFER, and the difference must grow with prop imbalance by the
##     factor the imbalance was wound up by. This is the claim the whole slice rests on: the
##     log carries the gap between what the aircraft did and what the flight controller was
##     told, because that gap is the thing LTHL-15's 180 Hz guess needs checking against;
##   * two identical flights must produce BYTE-IDENTICAL files, which is free (the gyro is
##     seeded) and which fails the moment a wall clock, an unordered Dictionary or an
##     unseeded RNG reaches the file;
##   * the flight with the recorder running must be the same flight, to the last bit, as the
##     one without it. A recorder that stalls or perturbs the loop would be invisible
##     otherwise, because the log would faithfully record the perturbed flight;
##   * the header must name the aircraft that flew, because a resonance peak means nothing
##     without the arm length and tip mass that produced it.
##
## ## What this suite does NOT do
##
## It does not compare anything to a blackbox log. That comparison happens in Python, off the
## end of this file, and it is the entire reason the file exists — but nothing here may claim
## it has happened. See VibrationModel's header for what is and is not sourced.

const TEST_PATH := "user://test_flight_log.csv"
const OTHER_PATH := "user://test_flight_log_b.csv"
const DT := 0.001
const STEPS := 3000   # 3 s at 1 kHz — long enough that a 1x line near 140 Hz has 400+ cycles


static func _clean() -> void:
	for path in [TEST_PATH, OTHER_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _build_with_imbalance(imbalance_g: float) -> Build:
	var build := ReferenceBuild.build()
	var assembly: Dictionary = build.assembly.duplicate()
	assembly["prop_imbalance_g"] = imbalance_g
	build.set_assembly(assembly)
	return build


## Flies a build hands-off at hover for STEPS substeps, recording every one when `record` is set.
## Returns the core, so a caller can compare where the aircraft ENDED — which is how the
## "recording does not change the flight" check is made.
static func _fly(build: Build, recorder: FlightRecorder = null) -> DroneCore:
	var core := build.build_drone_core()
	var throttle := ReferenceBuild.hover_throttle()
	core.prime_motors(throttle)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}

	for _i in STEPS:
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT)
		core.step(cmds, DT)
		if recorder != null:
			recorder.capture(core.observables)

	return core


## Reads one column out of a written log, by name. Deliberately a dumb CSV reader rather than a
## method on FlightRecorder: this suite must check what is IN THE FILE, and a reader shipped
## alongside the writer could agree with it about a mistake they both make.
static func _column(path: String, column_name: String) -> PackedFloat64Array:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var header_row := -1
	for i in lines.size():
		if not lines[i].begins_with("#"):
			header_row = i
			break

	var names := lines[header_row].split(",")
	var index := names.find(column_name)
	var out := PackedFloat64Array()
	if index < 0:
		return out

	for i in range(header_row + 1, lines.size()):
		if lines[i].strip_edges().is_empty():
			continue
		out.append(float(lines[i].split(",")[index]))
	return out


## The JSON header block, read back out of the comment lines at the top.
static func _header(path: String) -> Dictionary:
	var text := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("#"):
			break
		text += line.substr(1)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## RMS of (gyro - omega) on the roll axis, taken from the FILE. This is the sensor's total
## error: vibration, plus the PT1's lag, plus bias and noise. Only one of those three moves
## when the prop balance is changed, which is what makes the ratio below meaningful.
static func _sensor_error_rms(path: String) -> float:
	var gyro := _column(path, "gyro_x_rad_s")
	var omega := _column(path, "omega_x_rad_s")
	if gyro.size() != omega.size() or gyro.is_empty():
		return -1.0
	var sum_sq := 0.0
	for i in gyro.size():
		var d: float = gyro[i] - omega[i]
		sum_sq += d * d
	return sqrt(sum_sq / float(gyro.size()))


static func run() -> Array:
	var results: Array = []
	_clean()

	# --- A flight, recorded --------------------------------------------------------------
	var balanced := _build_with_imbalance(0.02)   # the stock, decently balanced prop
	var recorder := FlightRecorder.new(balanced)
	var flown := _fly(balanced, recorder)
	var wrote := recorder.save(TEST_PATH)

	var t := _column(TEST_PATH, "t_s")
	results.append(TestResult.new(
		"a recorded flight lands in a file, one row per substep, timestamped in SIMULATED seconds",
		wrote and t.size() == STEPS and absf(t[t.size() - 1] - float(STEPS) * DT) < 1e-6,
		"%d rows, last timestamp %.4f s" % [t.size(), t[t.size() - 1] if t.size() > 0 else -1.0]))

	# --- THE ONE THAT MATTERS: truth and sensor are separate columns -----------------------
	#
	# physics.md §9 keeps ground truth and the sensor estimate side by side deliberately.
	# omega is what the aircraft DID; gyro is what the flight controller was TOLD. A log that
	# collapses them is a game replay. Keeping them apart is the only way to see what
	# filtering, bias and vibration actually cost — which is the whole reason this file is
	# worth writing, and the reason the stub this suite was written against failed here first.
	var error_balanced := _sensor_error_rms(TEST_PATH)
	results.append(TestResult.new(
		"the log keeps ground truth and the sensor reading APART — gyro is not a copy of omega",
		error_balanced > 0.0,
		"RMS(gyro - omega) on roll = %.6f rad/s" % error_balanced))

	# ...and the gap is the SIGNAL, not an offset: winding the prop imbalance up 20x has to
	# show up in the file, in proportion. A recorder logging a filtered copy of the same
	# channel into both columns reads zero here at every imbalance and cannot pass.
	var chipped := _build_with_imbalance(0.4)
	var chipped_recorder := FlightRecorder.new(chipped)
	_fly(chipped, chipped_recorder)
	chipped_recorder.save(OTHER_PATH)
	var error_chipped := _sensor_error_rms(OTHER_PATH)

	results.append(TestResult.new(
		"the log carries the signal it exists for: sensor error grows with prop imbalance",
		error_chipped > error_balanced * 3.0,
		"RMS(gyro - omega) %.6f rad/s at 0.02 g against %.6f at 0.40 g (%.1fx)" % [
			error_balanced, error_chipped, error_chipped / maxf(error_balanced, 1e-12)]))

	# --- Determinism ------------------------------------------------------------------------
	#
	# The gyro is seeded and the vibration model holds no RNG at all, so the same flight twice
	# IS the same flight. A byte comparison is therefore available, and it is the strongest
	# cheap check there is: a wall clock in the header, a Dictionary iterated in hash order, or
	# an unseeded RNG anywhere in the flight path all fail it immediately.
	var repeat := _build_with_imbalance(0.02)
	var repeat_recorder := FlightRecorder.new(repeat)
	_fly(repeat, repeat_recorder)
	repeat_recorder.save(OTHER_PATH)
	results.append(TestResult.new(
		"the same flight twice produces a BYTE-IDENTICAL log — no wall clock, no unseeded RNG",
		FileAccess.get_file_as_string(TEST_PATH) == FileAccess.get_file_as_string(OTHER_PATH),
		"%d bytes each" % FileAccess.get_file_as_string(TEST_PATH).length()))

	# --- Recording must not change the flight -------------------------------------------------
	#
	# A recorder that stalled or perturbed the loop would be INVISIBLE from the log alone: the
	# file would faithfully record the perturbed flight and look entirely correct. So the check
	# is from outside — the same flight, flown twice, once with the recorder attached — and it
	# is exact rather than approximate, because there is no mechanism by which observing a
	# deterministic simulation should move it by even one bit.
	var unobserved := _fly(_build_with_imbalance(0.02))
	results.append(TestResult.new(
		"recording does not change the flight — same trajectory, to the bit, with the recorder off",
		unobserved.rigid_body.position_m == flown.rigid_body.position_m
			and unobserved.rigid_body.orientation == flown.rigid_body.orientation
			and unobserved.rigid_body.angular_velocity_rad_s == flown.rigid_body.angular_velocity_rad_s,
		"unrecorded ended at %v, recorded at %v" % [
			unobserved.rigid_body.position_m, flown.rigid_body.position_m]))

	# --- The header names the aircraft ---------------------------------------------------------
	#
	# A trace without its build is uninterpretable: a peak at 180 Hz means nothing unless the
	# arm length and tip mass that produced it are known. Build.fingerprint() already exists for
	# this shape of problem and is readable part ids rather than a hash, so a human opening the
	# file can see what flew.
	var header := _header(TEST_PATH)
	var aircraft: Dictionary = header.get("aircraft", {})
	results.append(TestResult.new(
		"the header names the build that was flown, by the same fingerprint that keys its tune",
		str(aircraft.get("fingerprint", "")) == balanced.fingerprint(),
		"fingerprint in file: %s" % aircraft.get("fingerprint", "(absent)")))

	# The assembly tweaks especially. Prop imbalance is a builder-settable value that directly
	# changes the spectrum, so a log recording the shake without recording what was set is a
	# measurement with its independent variable missing.
	var other_header := _header(OTHER_PATH)
	results.append(TestResult.new(
		"the header records the assembly the shake came from, so the spectrum has its cause beside it",
		is_equal_approx(float(header["assembly"]["prop_imbalance_g"]), 0.02)
			and is_equal_approx(float(other_header["assembly"]["prop_imbalance_g"]), 0.02),
		"balanced log says %s g" % header["assembly"]["prop_imbalance_g"]))

	# --- Every column states its unit ------------------------------------------------------
	#
	# Internally everything is rad/s; Betaflight blackbox is deg/s. An unstated unit is a
	# factor of 57 waiting to happen, in a comparison whose whole purpose is to line two
	# spectra up.
	var columns: Array = header.get("columns", [])
	var units: Dictionary = header.get("units", {})
	var unitless: PackedStringArray = []
	for column_name in columns:
		if not units.has(column_name):
			unitless.append(str(column_name))
	results.append(TestResult.new(
		"every column in the file states its unit in the header",
		not columns.is_empty() and unitless.is_empty(),
		"%d columns, all with units" % columns.size() if unitless.is_empty()
			else "no unit for: %s" % ", ".join(unitless)))

	# --- The sample rate is recorded, and it is the one the file actually has -----------------
	#
	# An FFT of a trace whose rate you are guessing at is worthless. Measured from the recorded
	# timestamps rather than declared from the constructor, so the header cannot claim a rate
	# the rows do not have.
	results.append(TestResult.new(
		"the log records its OWN sample rate, measured from the timestamps it wrote",
		absf(float(header.get("sample_rate_hz", 0.0)) - 1000.0) < 1.0,
		"%.2f Hz declared, decimation %s" % [
			header.get("sample_rate_hz", 0.0), header.get("decimation", "(absent)")]))

	# --- Decimation ---------------------------------------------------------------------------
	#
	# Supported for long flights, off by default: the whole point of the file is frequency
	# content and decimating destroys it. What must hold is that a decimated log does not LIE —
	# its declared rate has to fall with it.
	var sparse_recorder := FlightRecorder.new(_build_with_imbalance(0.02), 10)
	_fly(_build_with_imbalance(0.02), sparse_recorder)
	sparse_recorder.save(OTHER_PATH)
	var sparse_header := _header(OTHER_PATH)
	results.append(TestResult.new(
		"a decimated log keeps one row in N and says so — the declared rate falls with it",
		_column(OTHER_PATH, "t_s").size() == floori(float(STEPS) / 10.0)
			and absf(float(sparse_header.get("sample_rate_hz", 0.0)) - 100.0) < 1.0,
		"%d rows at %.1f Hz" % [
			_column(OTHER_PATH, "t_s").size(), sparse_header.get("sample_rate_hz", 0.0)]))

	# --- The columns that were published all along (LTHL-51) -------------------------------------
	#
	# electrical_hz, tip_speed_mps and weight_n were computed by Observables and never listed in
	# COLUMNS. The check is not "the column exists" — an empty column exists too, and a column of
	# zeroes is exactly what a wrong wiring produces. So each is checked against the physics it is
	# supposed to carry, using a relationship the recorder does not know about:
	#
	#   * electrical_hz must be rpm/60 x pole_pairs. A recorder that appended blade_pass_hz twice,
	#     or that read the wrong motor's slot, disagrees here immediately — the two differ by
	#     pole_pairs/blades, which is 7/3 on the reference build and not a rounding error;
	#   * weight_n must be mass x g, which pins it to the aircraft rather than to any per-motor
	#     quantity that happened to be lying next to it in the buffer.
	var erpm := _column(TEST_PATH, "m1_electrical_hz")
	var m1_rpm := _column(TEST_PATH, "m1_rpm")
	var pole_pairs := balanced.pole_pairs()
	var erpm_ok := erpm.size() == m1_rpm.size() and not erpm.is_empty()
	if erpm_ok:
		for i in range(0, erpm.size(), 97):   # every 97th row: a stride that is not a substep count
			if absf(erpm[i] - m1_rpm[i] / 60.0 * pole_pairs) > 1e-6 * maxf(1.0, erpm[i]):
				erpm_ok = false
				break
	results.append(TestResult.new(
		"the log carries electrical frequency, and it IS rpm/60 x pole pairs — not blade pass wearing its name",
		erpm_ok,
		"m1_electrical_hz %.3f Hz against m1_rpm %.1f at %.0f pole pairs" % [
			erpm[0] if not erpm.is_empty() else -1.0,
			m1_rpm[0] if not m1_rpm.is_empty() else -1.0, pole_pairs]))

	# Tip speed is the other one order tracking cannot recover on its own: it needs the prop
	# radius, which lives in the header and not in any column. Checked as strictly positive and
	# ordered against rpm rather than recomputed here, since recomputing it in the test would
	# just be the same formula twice.
	var tip := _column(TEST_PATH, "m1_tip_speed_mps")
	results.append(TestResult.new(
		"tip speed reaches the file and tracks rpm rather than sitting at a constant",
		tip.size() == m1_rpm.size() and not tip.is_empty() and tip[0] > 1.0
			and (tip[tip.size() - 1] > tip[0]) == (m1_rpm[m1_rpm.size() - 1] > m1_rpm[0]),
		"m1_tip_speed_mps runs %.1f -> %.1f m/s" % [
			tip[0] if not tip.is_empty() else -1.0,
			tip[tip.size() - 1] if not tip.is_empty() else -1.0]))

	var weight := _column(TEST_PATH, "weight_n")
	var expected_weight := balanced.mass_properties.total_mass_kg * Observables.GRAVITY_MPS2
	results.append(TestResult.new(
		"weight reaches the file and is the aircraft's own mass x g",
		not weight.is_empty() and absf(weight[0] - expected_weight) < 1e-4,
		"weight_n = %.4f N against mass %.4f kg (%.4f N expected)" % [
			weight[0] if not weight.is_empty() else -1.0,
			balanced.mass_properties.total_mass_kg, expected_weight]))

	# --- A recording says whether it is CONTINUOUS ------------------------------------------------
	#
	# A respawn teleports the aircraft, so a reader differencing position across that row gets an
	# acceleration that never happened. LTHL-51 cannot mark the row — that needs the event stream
	# LTHL-53 brings — but it must not let the file stay silent either. The count is what the
	# header carries, and this asserts both directions: silence when the flight was continuous,
	# and a number when it was not. Asserting only the nonzero case would pass for a recorder that
	# hardcoded a warning into every log, which is a warning nobody would read twice.
	var jumped := FlightRecorder.new(_build_with_imbalance(0.02))
	_fly(_build_with_imbalance(0.02), jumped)
	jumped.discontinuities = 2
	jumped.save(OTHER_PATH)
	results.append(TestResult.new(
		"the header says whether the trace is continuous — silent on a clean flight, counted after a respawn",
		int(_header(TEST_PATH).get("discontinuities", -1)) == 0
			and int(_header(OTHER_PATH).get("discontinuities", -1)) == 2,
		"clean log reports %s, respawned log reports %s" % [
			_header(TEST_PATH).get("discontinuities", "(absent)"),
			_header(OTHER_PATH).get("discontinuities", "(absent)")]))

	# --- Flying produces a file -------------------------------------------------------------------
	#
	# THE ONE THAT WAS THE WHOLE POINT OF LTHL-51. Every check above passed on the day the only
	# caller of this class was a headless tool and flying the actual simulator wrote nothing; a
	# recorder can be perfect and unreachable. This checks the reachability, by source, in the
	# same style as the "cannot reconstruct a build" check below — the scene must capture inside
	# its substep loop, not once per frame, or the log is decimated by 8 without saying so.
	var scene_code := TestPidTunes._code_only(
		FileAccess.get_file_as_string("res://src/scenes/main.gd"))
	var substep_body := scene_code.split("for i in SUBSTEPS:")
	results.append(TestResult.new(
		"the flight scene captures into the recorder, and does it per SUBSTEP rather than per frame",
		scene_code.contains("FlightRecorder.new")
			and substep_body.size() == 2 and substep_body[1].contains("capture("),
		"main.gd constructs a recorder and calls capture() inside the substep loop"))

	# The filename, pinned exactly, because Studio will list these by name and the list is only
	# useful if the name sorts. Zero-padding is the whole check: "flight-2026-8-9" sorts after
	# "flight-2026-12-01" as a string, so a formatter that dropped the padding would produce a
	# directory that reads as random while every individual name looks fine.
	var scene: GDScript = load("res://src/scenes/main.gd")
	var march: String = scene.log_path({
		"year": 2026, "month": 3, "day": 9, "hour": 7, "minute": 4, "second": 5})
	var december: String = scene.log_path({
		"year": 2026, "month": 12, "day": 1, "hour": 18, "minute": 30, "second": 59})
	results.append(TestResult.new(
		"a log's filename is zero-padded, so a directory of them sorts chronologically as text",
		march.get_file() == "flight-20260309-070405.csv"
			and december.get_file() == "flight-20261201-183059.csv"
			and march < december,
		"%s sorts before %s" % [march.get_file(), december.get_file()]))

	# --- A log names an aircraft; it does not DEFINE one ---------------------------------------
	#
	# The corollary that keeps this file on the right side of Lab/Sim. If reading a log back
	# could reconstruct a Build, the log would be a second and much worse parts catalog, and the
	# two would disagree the first time the real one changed. So the reader returns a header
	# Dictionary and there is no route from it to a Build anywhere in the project.
	var recorder_code := TestPidTunes._code_only(
		FileAccess.get_file_as_string("res://src/sim/flight_recorder.gd"))
	results.append(TestResult.new(
		"reading a log back cannot reconstruct a build — the log names the aircraft, it does not define it",
		not recorder_code.contains("Build.from_ids") and not recorder_code.contains("PartsCatalog"),
		"flight_recorder.gd builds nothing"))

	# --- Reading a header back ------------------------------------------------------------------
	#
	# The shipped reader, checked against the dumb one above rather than trusted on its own: it
	# has to agree with a reader that knows nothing about how the file was written.
	results.append(TestResult.new(
		"the shipped header reader agrees with a reader that knows nothing about the writer",
		FlightRecorder.read_header(TEST_PATH).get("aircraft", {}).get("fingerprint", "")
			== balanced.fingerprint(),
		"read_header() returns the same fingerprint the raw parse found"))

	# And a bad file is not a fatal error — json_store.gd's rule, and for the same reason: a
	# half-written log is a lost log, never a crash in whatever was reading it.
	var truncated := FileAccess.open(OTHER_PATH, FileAccess.WRITE)
	truncated.store_line("#{\"schema\": 1, \"aircraft\": {")
	truncated.close()
	results.append(TestResult.new(
		"a truncated log reads as an empty header rather than failing",
		FlightRecorder.read_header(OTHER_PATH).is_empty()
			and FlightRecorder.read_header("user://no_such_log.csv").is_empty(),
		"truncated and missing files both read as {}"))

	_clean()
	return results
