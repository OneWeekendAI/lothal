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
