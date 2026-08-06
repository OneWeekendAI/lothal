extends SceneTree
## Flies a slow throttle sweep and writes a FlightRecorder log, for LTHL-18.
##
##   godot --headless --script res://tools/record_sweep.gd -- --out=/tmp/sweep.csv
##
## WHY A SLOW SWEEP RATHER THAN A REPRESENTATIVE FLIGHT, and this is the whole point of the
## file. tools/resonance_analysis.py finds a frame mode by ORDER TRACKING: it follows each
## motor's harmonics using logged rpm and reads off where they got loud as they swept through
## the mode. That works only if a harmonic is a LINE within one analysis frame.
##
## Four real Betaflight logs were measured against exactly this requirement and all four
## failed it. In freestyle flight the 1x line moves by a median of 155-235 Hz WITHIN a single
## 1.024 s frame — 160 to 240 FFT bins of smear — so the harmonic is not a line, it is a
## broad blur across half the band, and no amount of analysis recovers a peak from it. The
## flight profile is not a detail of the method; it is a precondition of it.
##
## So this sweeps SWEEP_SECONDS from idle to full and back, slowly enough that the 1x line
## drifts a small fraction of a bin per frame. That is not how anyone flies. It is how a
## swept-sine test is run, and this is a swept-sine test.
##
## THIS AUTHORS NOTHING. It flies a catalog build with a scripted stick input and writes a log,
## which is what flight_recorder.gd's header explains at length is not a Lab/Sim breach: no
## tune, build, course or pack is written back. The build it flies is ReferenceBuild's, read
## and not modified.

const OUT_DEFAULT := "user://sweep.csv"
const DT := 0.001

## Long enough that the 1x line drifts well under one FFT bin per 1.024 s analysis frame. The
## reference build's 1x runs to roughly 400 Hz, so a 120 s up-and-down sweep moves it about
## 7 Hz/s, or 7 bins per frame — against 240 in the real logs. Slower would be better and
## costs only wall time; this is the point where the peak is already sharp.
const SWEEP_SECONDS := 120.0

## Idle to full. Below IDLE the motors are not turning fast enough for the 1x line to be
## inside the analysis band at all, so sweeping from zero would only add frames with nothing
## in them.
const IDLE_THROTTLE := 0.15
const FULL_THROTTLE := 1.0

## Far enough above the analysis band that the gyro's PT1 is effectively pass-through. Matches
## the value tests/test_vibration.gd uses for the same purpose.
const UNFILTERED_CUTOFF_HZ := 2000.0


func _init() -> void:
	var out_path := OUT_DEFAULT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)

	var build := ReferenceBuild.build()
	var core := build.build_drone_core()

	# THE GYRO LOWPASS IS TURNED OFF FOR THE MEASUREMENT, and this is the same act as setting
	# debug_mode = GYRO_SCALED on a real quad before a filter-tuning flight — it is what makes
	# the two traces comparable rather than what makes Lothal look good.
	#
	# It is not optional. The fitted board's PT1 sits at 150 Hz and the modelled mode is at 180,
	# so the sensor attenuates the peak this whole exercise exists to locate; a Lothal log flown
	# normally is refused by tools/resonance_analysis.py for exactly the reason a default
	# Betaflight log is. Worth noticing on its own: on the reference build, the resonance is
	# above the gyro's own cutoff, so the flight controller never sees most of it.
	# 2000 Hz rather than 0, and the difference is not cosmetic. Gyro's PT1 has no "off" branch:
	# alpha = dt/(RC+dt) with RC = 1/(2*pi*fc), so a cutoff of ZERO gives RC = infinity, alpha =
	# 0, and a sensor whose output never moves off zero at all. The first run of this script did
	# exactly that and wrote 120 000 rows of zeroes, which the analysis correctly reported as
	# "no detection" rather than as a resonance — the failure was loud, but it was a failure.
	# Pushing the cutoff far above the band instead is how tests/test_vibration.gd already
	# disables the filter, and at 2000 Hz the PT1's gain across 60-500 Hz is within a fraction
	# of a percent of unity.
	core.gyro.cutoff_hz = UNFILTERED_CUTOFF_HZ

	var recorder := FlightRecorder.new(build, 1, null, core.gyro)
	core.prime_motors(IDLE_THROTTLE)
	var fc := FlightController.new()

	var steps := int(SWEEP_SECONDS / DT)
	for i in steps:
		# Triangle: up over the first half, back down over the second. Sweeping BOTH WAYS is
		# free and it is a control — a mode is at the same frequency going up as coming down,
		# while anything that tracks elapsed time rather than rpm is not.
		var phase := float(i) / float(steps)
		var ramp := phase * 2.0 if phase < 0.5 else (1.0 - phase) * 2.0
		var throttle: float = IDLE_THROTTLE + (FULL_THROTTLE - IDLE_THROTTLE) * ramp

		# Sticks centred throughout. The aircraft is not being asked to go anywhere; the props
		# are the shaker and the airframe is the specimen.
		var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT)
		core.step(cmds, DT)
		recorder.capture(core.observables)

	if not recorder.save(out_path):
		push_error("could not write %s" % out_path)
		quit(1)
		return

	print("wrote %s: %d rows, %.1f s" % [out_path, recorder.row_count(), SWEEP_SECONDS])
	quit(0)
