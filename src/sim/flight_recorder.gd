class_name FlightRecorder
extends RefCounted
## A file that says what the aircraft actually did (LTHL-18).
##
## ===========================================================================
## THIS IS NOT A LAB/SIM VIOLATION, AND HERE IS WHY
## ===========================================================================
##
## labs-and-sim.md's governing rule is SIM AUTHORS NOTHING, and tests/test_pid_tunes.gd enforces
## the sharpest case of it: "only Lab writes a tune — nothing in the flight path does." This class
## writes a file from inside the flight path, so it will look like a breach to the next person who
## reads it. It is not one, and the distinction is worth stating precisely rather than assuming.
##
## The rule is about AUTHORING WHAT THE DRONE OR THE WORLD IS. A tune, a build, a course, a pack's
## remaining charge: those are all garage decisions, and a flight that quietly rewrote one would
## mean the builder's aircraft changed because they flew it. A LOG authors nothing. It records what
## happened, which makes it the purest instance there is of "only changes what is happening" — the
## flight is not different for having been watched, and tests/test_flight_recorder.gd asserts
## exactly that, to the bit, by flying the same aircraft twice with the recorder off.
##
## THE COROLLARY, AND IT IS LOAD-BEARING: reading a log back must never reconstruct a build. The
## header NAMES the aircraft; it does not DEFINE it. A reader that could turn a log into a flyable
## Build would be a second and much worse parts catalog — one written by a flight, drifting from
## the real one the day a part's mass is corrected. So there is no route from a header back to a
## Build anywhere in this project, read_header() returns a plain Dictionary, and the test suite
## checks the absence by reading this file's source.
##
## No existing test needed widening for this. test_pid_tunes.gd's writer check enumerates callers
## of pid_tunes.save/remember/forget specifically, not file writers in general, and this class
## calls none of them; it is left exactly as it was.
##
## ===========================================================================
## WHAT THIS IS FOR
## ===========================================================================
##
## VibrationModel.REFERENCE_RESONANCE_HZ is 180.0 and its own comment says "No source. There is no
## source." Every frame in the catalog rings at a ratio to that guess, and RateTune.kd_ceiling_for
## refuses to let the guess move the D gains precisely because it cannot be checked — which leaves
## six of fourteen frames on the wrong side of a noise budget.
##
## There IS data: FPV pilots post Betaflight blackbox logs, which are gyro traces at 1-8 kHz with
## the frame's resonance visible as a peak. What stood between Lothal and that comparison was that
## Lothal could not produce a comparable trace. This file is that trace. It does not make LTHL-18
## a measurement on its own — it makes the measurement possible, which is a smaller claim and the
## only honest one until a real log has been laid alongside one of these.
##
## ===========================================================================
## WHAT IS DELIBERATELY NOT HERE
## ===========================================================================
##
## No FFT, no spectrum view, no plotting, no analysis of any kind. This slice ends at a file. The
## comparison happens in Python where numpy.fft already exists and is better than anything a
## half-built spectrum viewer in Godot would be, and building that viewer would cost more than the
## whole recorder while answering nothing.

## Bumped when a column is REMOVED or its meaning changes. Appending a column does not bump it:
## a reader that selects by name, which the header's `columns` list exists to let it do, is
## unaffected by an addition.
const SCHEMA := 1

## ---------------------------------------------------------------------------
## The columns
## ---------------------------------------------------------------------------
##
## Every one of these is copied straight out of Observables. NOTHING here is computed a second
## time: the recorder is a consumer of the published layer like the HUD and the audio synthesiser,
## and a recorder that derived, say, reaction torque from k_q would be the second expression of a
## law that has exactly one, which is how a log and the flight it claims to describe come to
## disagree. The three quantities this file needed that were not published — elapsed time,
## per-motor torque, per-motor current — were added to Observables rather than reached around.
##
## OMEGA AND GYRO ARE SEPARATE COLUMNS AND THIS IS NOT NEGOTIABLE. physics.md §9 keeps ground
## truth and the sensor estimate side by side deliberately: omega_* is what the aircraft actually
## did, gyro_* is what the flight controller was told. A log that collapses them into one channel
## is a game replay. A log that keeps them apart is the only way to see what filtering, bias and
## vibration actually COST, and that gap is the entire reason this file is worth writing.
const COLUMNS := [
	"t_s",

	"m1_rpm", "m1_thrust_n", "m1_torque_n_m", "m1_current_a", "m1_blade_pass_hz",
	"m2_rpm", "m2_thrust_n", "m2_torque_n_m", "m2_current_a", "m2_blade_pass_hz",
	"m3_rpm", "m3_thrust_n", "m3_torque_n_m", "m3_current_a", "m3_blade_pass_hz",
	"m4_rpm", "m4_thrust_n", "m4_torque_n_m", "m4_current_a", "m4_blade_pass_hz",

	"total_thrust_n", "current_total_a", "voltage_live_v", "capacity_used_fraction",

	"pos_x_m", "pos_y_m", "pos_z_m",
	"vel_x_mps", "vel_y_mps", "vel_z_mps",
	"quat_x", "quat_y", "quat_z", "quat_w",

	"omega_x_rad_s", "omega_y_rad_s", "omega_z_rad_s",
	"gyro_x_rad_s", "gyro_y_rad_s", "gyro_z_rad_s",

	"accel_x_body_mps2", "accel_y_body_mps2", "accel_z_body_mps2",
	"airspeed_mps", "g_force",
]

## EVERY COLUMN STATES ITS UNIT, and the file carries this table so a reader never has to guess.
## Internally Lothal is rad/s throughout; Betaflight blackbox is deg/s. That factor of 57.3 is the
## single easiest way to ruin a comparison whose entire purpose is to line two spectra up, so
## NOTHING here is converted silently in either direction — the rates go out in the units the
## simulation holds them in, and this table says so. Converting to deg/s is one multiply in the
## Python that does the comparing, done where the reader can see it happen.
const UNITS := {
	"t_s": "s",
	"m1_rpm": "rpm", "m1_thrust_n": "N", "m1_torque_n_m": "N*m", "m1_current_a": "A", "m1_blade_pass_hz": "Hz",
	"m2_rpm": "rpm", "m2_thrust_n": "N", "m2_torque_n_m": "N*m", "m2_current_a": "A", "m2_blade_pass_hz": "Hz",
	"m3_rpm": "rpm", "m3_thrust_n": "N", "m3_torque_n_m": "N*m", "m3_current_a": "A", "m3_blade_pass_hz": "Hz",
	"m4_rpm": "rpm", "m4_thrust_n": "N", "m4_torque_n_m": "N*m", "m4_current_a": "A", "m4_blade_pass_hz": "Hz",
	"total_thrust_n": "N", "current_total_a": "A", "voltage_live_v": "V", "capacity_used_fraction": "fraction",
	"pos_x_m": "m", "pos_y_m": "m", "pos_z_m": "m",
	"vel_x_mps": "m/s", "vel_y_mps": "m/s", "vel_z_mps": "m/s",
	"quat_x": "unit", "quat_y": "unit", "quat_z": "unit", "quat_w": "unit",
	"omega_x_rad_s": "rad/s", "omega_y_rad_s": "rad/s", "omega_z_rad_s": "rad/s",
	"gyro_x_rad_s": "rad/s", "gyro_y_rad_s": "rad/s", "gyro_z_rad_s": "rad/s",
	"accel_x_body_mps2": "m/s^2", "accel_y_body_mps2": "m/s^2", "accel_z_body_mps2": "m/s^2",
	"airspeed_mps": "m/s", "g_force": "g",
}

## ---------------------------------------------------------------------------
## Rate, and the memory it costs
## ---------------------------------------------------------------------------
##
## THE DEFAULT IS EVERY SUBSTEP, i.e. the full 1 kHz the dynamics run at (physics.md §6, 8
## substeps of a 120 Hz frame). This is the right default for the work this file exists for:
## frequency content is the whole point, decimating destroys it, and a 500 Hz peak needs better
## than 1 kHz sampling to survive at all. A log decimated by default would quietly answer the one
## question it was built to answer with an alias.
##
## What that costs, measured rather than guessed: 46 columns x 8 bytes is 368 bytes per row, so
## 1 kHz buffers 22 MB per minute of flight. On disk it is 915 bytes per row measured on a real
## 3 s log — exact round-tripped decimals are verbose — so about 55 MB per minute written. A
## three-minute pack is roughly 66 MB held and 165 MB on disk: large, but well inside what a
## desktop running a 3D simulation already has, and a single flight is not a session. Past a few
## minutes, set
## decimation: it is exact (one row in N, no averaging, which would be a filter nobody asked for)
## and the header's measured sample rate falls with it so an FFT downstream cannot be misled.
var decimation: int

## ---------------------------------------------------------------------------
## Not stalling the flight
## ---------------------------------------------------------------------------
##
## capture() appends floats to a packed buffer and does nothing else — no formatting, no
## allocation per row, no file handle touched. All of the string work and the single write happen
## in save(), off the physics loop.
##
## A recorder that wrote to disk at 1 kHz from inside the physics loop would hitch, and the damage
## would be INVISIBLE from the log itself: the file would faithfully record the perturbed flight
## and look entirely correct. That is why the test for this is from outside — the same flight
## flown twice, once observed — and why it is exact rather than approximate.
var _rows := PackedFloat64Array()
var _tick := 0

var _build: Build
var _tune: RateTune
## The sensor that is actually flying, when the caller has one. Optional, and null falls back
## to a fresh Gyro off the build — see _gyro_block().
var _gyro: Gyro

func _init(p_build: Build, p_decimation: int = 1, p_tune: RateTune = null, p_gyro: Gyro = null) -> void:
	_build = p_build
	_tune = p_tune
	_gyro = p_gyro
	decimation = maxi(1, p_decimation)


## One row, from the published observables. Call it once per substep, after the step.
func capture(obs: Observables) -> void:
	var keep := _tick % decimation == 0
	_tick += 1
	if not keep:
		return

	_rows.append(obs.elapsed_s)

	for i in Observables.MOTOR_COUNT:
		_rows.append(obs.rpm[i])
		_rows.append(obs.thrust_n[i])
		_rows.append(obs.reaction_torque_n_m[i])
		_rows.append(obs.current_a[i])
		_rows.append(obs.blade_pass_hz[i])

	_rows.append(obs.total_thrust_n)
	_rows.append(obs.current_total_a)
	_rows.append(obs.voltage_live_v)
	_rows.append(obs.capacity_used_fraction)

	_rows.append(obs.position_m.x)
	_rows.append(obs.position_m.y)
	_rows.append(obs.position_m.z)
	_rows.append(obs.velocity_mps.x)
	_rows.append(obs.velocity_mps.y)
	_rows.append(obs.velocity_mps.z)
	_rows.append(obs.orientation.x)
	_rows.append(obs.orientation.y)
	_rows.append(obs.orientation.z)
	_rows.append(obs.orientation.w)

	# Ground truth, then the sensor. Two channels, never one — see COLUMNS.
	_rows.append(obs.angular_velocity_rad_s.x)
	_rows.append(obs.angular_velocity_rad_s.y)
	_rows.append(obs.angular_velocity_rad_s.z)
	_rows.append(obs.gyro_rad_s.x)
	_rows.append(obs.gyro_rad_s.y)
	_rows.append(obs.gyro_rad_s.z)

	_rows.append(obs.accel_body_mps2.x)
	_rows.append(obs.accel_body_mps2.y)
	_rows.append(obs.accel_body_mps2.z)
	_rows.append(obs.airspeed_mps)
	_rows.append(obs.g_force)


func row_count() -> int:
	return floori(float(_rows.size()) / float(COLUMNS.size()))


## Writes the log. One JSON header line commented with '#', then a CSV header row, then the rows.
##
## The format is a deliberate non-decision: it gets converted downstream and what actually matters
## is that the schema is explicit, self-describing and stable. What this shape buys is that both
## halves are trivial on the far side — `json.loads(first_line[1:])` and then a pandas read_csv
## that skips one line — while the file stays greppable and diffable, which a binary would not.
## The '#' prefix is what pandas and numpy both already treat as a comment.
##
## Values go through String.num_scientific, which ROUND-TRIPS EXACTLY: parsing a column back
## returns the same float64 the simulation held. Godot's "%.9g" is not available (GDScript's
## format has no %g and emits the literal), str() silently drops to about 8 significant digits on
## small values, and either would mean a log that had quietly rounded its own physics — which is a
## log you cannot check a residual against.
func save(path: String) -> bool:
	var stride := COLUMNS.size()
	if _rows.size() % stride != 0:
		push_error("flight log buffer is %d floats, not a multiple of %d columns" % [_rows.size(), stride])
		return false

	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		push_warning("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	handle.store_line("#" + JSON.stringify(_header()))
	handle.store_line(",".join(COLUMNS))

	var cells := PackedStringArray()
	cells.resize(stride)
	for r in row_count():
		var base := r * stride
		for c in stride:
			cells[c] = String.num_scientific(_rows[base + c])
		handle.store_line(",".join(cells))

	handle.close()
	return true


## The header block: the sample rate, and the aircraft.
##
## A TRACE WITHOUT ITS BUILD IS UNINTERPRETABLE. A peak at 180 Hz means nothing unless the arm
## length and the tip mass that produced it are known, which is the whole difficulty this file
## exists to remove. Build.fingerprint() already solves this exact shape of problem — it keys
## saved PID tunes, and it is deliberately readable part ids rather than a hash, so a human
## opening the log can see what flew.
func _header() -> Dictionary:
	var vibration := VibrationModel.for_build(_build)
	return {
		"schema": SCHEMA,
		"generator": "lothal.flight_recorder",

		# MEASURED from the timestamps actually written, not declared from the constructor: an FFT
		# of a trace whose rate you are guessing at is worthless, and a header that could claim a
		# rate the rows do not have is a guess wearing a number's clothes.
		"sample_rate_hz": _measured_sample_rate_hz(),
		"sample_rate_source": "measured from the recorded timestamps",
		"decimation": decimation,
		"rows": row_count(),
		"duration_s": _duration_s(),

		"aircraft": {
			"fingerprint": _build.fingerprint(),
			"arm_m": _build.arm_m,
			"mass_kg": _build.mass_properties.total_mass_kg,
			"blades": _build.prop_geometry().blades,
			"prop_diameter_m": _build.prop_geometry().diameter_m,
		},

		# The builder's assembly, in full. Prop imbalance especially: it is a builder-settable
		# value that directly changes the spectrum, so a log recording the shake without recording
		# what was set is a measurement with its independent variable missing.
		"assembly": _resolved_assembly(),

		# What the model was told to ring at. Recorded so that a comparison against a real blackbox
		# spectrum can state what it is disagreeing WITH — and flagged, here in the file, as the
		# unsourced guess it is, because a number travelling in a data file loses its caveats
		# faster than a number in a source comment.
		"vibration_model": {
			"resonance_hz": vibration.resonance_hz,
			"damping_ratio": vibration.damping_ratio,
			"imbalance_kg": vibration.imbalance_kg,
			"blade_pass_equivalent_kg": vibration.blade_pass_kg,
			"soft_mount_m": vibration.soft_mount_m,
			"caveat": "characteristic model, not predictive: resonance is anchored on one guessed"
				+ " frequency (VibrationModel.REFERENCE_RESONANCE_HZ) and the amplitude scale is a"
				+ " single free constant. Ratios are derived; absolute values are not sourced.",
		},

		# WHAT THE SENSOR DID TO THE SIGNAL BEFORE IT REACHED THE gyro_* COLUMNS. Added because
		# the first real comparison could not be made without it: the analysis in
		# tools/resonance_analysis.py refuses a Betaflight log whose gyro was recorded after the
		# lowpass, since that lowpass attenuates exactly the resonance peak being hunted — and it
		# could not apply the same refusal to a Lothal log, because a Lothal log did not say. A
		# trace that cannot state its own filtering can be held to a standard the other side of
		# the comparison is held to only by assumption, which is not a standard.
		#
		# Appending this does not bump SCHEMA: per the rule above, a reader selecting by name is
		# unaffected by an addition.
		#
		# THE GYRO THAT FLEW, not a fresh one built from the same parts. Build.gyro() constructs
		# a new Gyro on every call, so asking the BUILD would describe a sensor that was never in
		# the aircraft — identical today, and silently wrong the moment anything adjusts the
		# sensor on the way into a flight, which is exactly what tools/record_sweep.gd does when
		# it disables the lowpass to take a measurement. A header that quietly reported the
		# lowpass as still on would invalidate the one comparison this block was added for.
		"gyro": _gyro_block(),

		"tune": _tune_block(),

		"columns": COLUMNS,
		"units": UNITS,
		"frames": "position/velocity are WORLD; accel and gyro/omega are BODY. Betaflight blackbox"
			+ " is deg/s — these rates are rad/s and are NOT converted.",
	}


## What the sensor did to the signal before it reached the gyro_* columns.
##
## Falls back to the build's own gyro when the caller did not hand one over, which is right for
## a flight that never touched the sensor and is the only case where the two agree by
## construction. When they can differ, the one that flew wins.
func _gyro_block() -> Dictionary:
	var g := _gyro if _gyro != null else _build.gyro()
	return {
		"sample_rate_hz": g.sample_rate_hz,
		"lowpass_hz": g.cutoff_hz,
		"noise_rad_s": g.noise_rad_s,
		"source": "the gyro that flew" if _gyro != null else "rebuilt from the build",
	}


func _resolved_assembly() -> Dictionary:
	var out: Dictionary = {}
	for key in Build.DEFAULT_ASSEMBLY:
		out[key] = _build.assembly_value(key)
	return out


## The gains in force during the flight, or an explicit null. NOT derived here when absent: a
## recorder that filled in RateTune.derive() would be asserting which gains flew, and it does not
## know — the tune in force is the garage's, and overrides are exactly the case where a derived
## answer would be confidently wrong.
func _tune_block() -> Variant:
	if _tune == null:
		return null
	var out: Dictionary = {}
	for axis in RateTune.AXIS_NAMES.size():
		var gains := _tune.gains_for(axis)
		out[RateTune.AXIS_NAMES[axis]] = {
			"p": gains.x, "i": gains.y, "d": gains.z,
			"overridden": _tune.is_overridden(axis),
		}
	return out


func _duration_s() -> float:
	var rows := row_count()
	if rows < 2:
		return 0.0
	return _rows[(rows - 1) * COLUMNS.size()] - _rows[0]


func _measured_sample_rate_hz() -> float:
	var span := _duration_s()
	if span <= 0.0:
		return 0.0
	return float(row_count() - 1) / span


## Reads a log's header back. Returns a plain Dictionary and NOTHING ELSE — see the class header:
## a log names an aircraft, it does not define one, and there is deliberately no route from here
## to a Build. Follows json_store.gd's rule that a bad file is a warning and an empty result, not
## a crash.
static func read_header(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return {}
	var line := handle.get_line()
	handle.close()

	if not line.begins_with("#"):
		push_warning("%s has no flight-log header line" % path)
		return {}

	var reader := JSON.new()
	if reader.parse(line.substr(1)) != OK:
		push_warning("%s has a malformed header (line %d: %s)" % [
			path, reader.get_error_line(), reader.get_error_message()])
		return {}

	var parsed: Variant = reader.data
	return parsed if parsed is Dictionary else {}
