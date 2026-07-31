extends SceneTree
## Dev tool, not a test: runs the real physics headlessly, feeds the published observables
## to the real synthesiser, and writes a WAV. This is the audio equivalent of
## capture_frame.gd — the way to actually LISTEN to a change without booting the game and
## flying it.
##
##   godot --headless --script res://tests/capture_audio.gd -- <out.wav> [sweep|flypast|bench]
##
## Everything here is driven by a genuine simulation: the flight controller is running, the
## pack is sagging, and the four motors are at four different RPM because the PID is
## correcting. Nothing about the sound is scripted — the throttle is, and the sound is
## whatever the physics does with it.
##
## The propagation (distance gain, air absorption) is reimplemented here rather than shared
## with DroneAudio, because in the game that work is done inside AudioStreamPlayer3D, which
## needs a scene and an audio device. This is an offline stand-in for it, so the two can
## differ in detail; the SOURCE, which is the part with all the interesting behaviour, is
## the same RotorSynth in both.

const SAMPLE_RATE := 44100.0
const BLOCK := 256
const PHYSICS_SUBSTEPS := 6

## Where the listener stands, and how close the drone gets on the flypast.
const LISTENER := Vector3(0.0, 1.6, 0.0)
const REFERENCE_DISTANCE_M := 3.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://lothal.wav"
	var mode: String = args[1] if args.size() > 1 else "sweep"

	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	var synth := RotorSynth.new(SAMPLE_RATE)

	var samples := PackedFloat32Array()
	match mode:
		"flypast": samples = _render_flypast(build, core, synth)
		"bench": samples = _render_bench(build, synth)
		_: samples = _render_sweep(build, core, synth)

	_write_wav(samples, out_path)
	print("wrote %s (%.1f s, %s)" % [out_path, float(samples.size()) / SAMPLE_RATE, mode])
	quit()


## Throttle sweep at a fixed 5 m, hovering under the flight controller the whole time.
## Idle -> hover -> full -> hover -> idle. This is the source model on display: the pitch
## rise, the broadband taking over at speed, the beating, and the warble of the PID working.
func _render_sweep(build: Build, core: DroneCore, synth: RotorSynth) -> PackedFloat32Array:
	var hover: float = build.hover_throttle()
	var full: float = build.max_throttle_fraction()
	core.prime_motors(0.0)
	core.rigid_body.position_m = LISTENER + Vector3(0, 3.4, 5.0)

	var out := PackedFloat32Array()
	var duration := 9.0
	var elapsed := 0.0

	while elapsed < duration:
		var throttle := _sweep_throttle(elapsed / duration, hover, full)
		# The attitude controller runs for real, which is what keeps the four motors from
		# ever sitting at the same RPM — the beating in the result is its doing, not an
		# effect applied afterwards.
		var block_dt := float(BLOCK) / SAMPLE_RATE
		var substep := block_dt / float(PHYSICS_SUBSTEPS)
		for _i in PHYSICS_SUBSTEPS:
			var cmds := AngleModeController.update(core.rigid_body.orientation,
				core.gyro.rate_rad_s,
				{"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle})
			core.step(cmds, substep)

		# The airframe is pinned in place for this take: the point is to hear the throttle,
		# and a drone left to its own devices at full throttle leaves the map in two seconds.
		core.rigid_body.position_m = LISTENER + Vector3(0, 3.4, 5.0)
		core.rigid_body.velocity_mps = Vector3.ZERO

		out.append_array(_propagate(synth.render_block(core.observables, 1.0, BLOCK),
			core.observables.position_m, Vector3.ZERO))
		elapsed += block_dt

	return out


## A pass: the drone crosses in front of the listener at speed, under hover throttle, with
## real drag. Doppler, the distance curve and air absorption are the whole content here —
## the source barely changes across the take.
func _render_flypast(build: Build, core: DroneCore, synth: RotorSynth) -> PackedFloat32Array:
	var hover: float = build.hover_throttle()
	core.prime_motors(hover)
	core.rigid_body.position_m = Vector3(-70.0, 4.0, 6.0)
	core.rigid_body.velocity_mps = Vector3(26.0, 0.0, 0.0)

	var out := PackedFloat32Array()
	var elapsed := 0.0
	var block_dt := float(BLOCK) / SAMPLE_RATE

	while elapsed < 6.0:
		var substep := block_dt / float(PHYSICS_SUBSTEPS)
		for _i in PHYSICS_SUBSTEPS:
			var cmds := AngleModeController.update(core.rigid_body.orientation,
				core.gyro.rate_rad_s,
				{"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover})
			core.step(cmds, substep)
		# Held at altitude — there is no altitude hold in the sim, and a drone that sinks
		# into the ground mid-take ends the demonstration early.
		core.rigid_body.position_m.y = 4.0
		core.rigid_body.velocity_mps.y = 0.0

		var obs := core.observables
		var doppler := RotorSynth.doppler_scale(obs.position_m, obs.velocity_mps, LISTENER)
		out.append_array(_propagate(synth.render_block(obs, doppler, BLOCK),
			obs.position_m, obs.velocity_mps))
		elapsed += block_dt

	return out


## A motor on the stand: idle, then ramp to 60% across the first half of the take and hold.
## No DroneCore, no rigid body, no flight controller — the sound of the garage.
##
## This is the demonstration that Lothal Labs gets audio for nothing. RotorSynth reads only
## Observables, and a Powertrain fills every field it reads, so the bench is audible without
## a single line of audio code changing. Note the signature: no DroneCore parameter, which
## is the entire claim in one line.
const BENCH_DURATION_S := 6.0
const BENCH_PEAK_THROTTLE := 0.6
const BENCH_DISTANCE_M := 3.0

func _render_bench(build: Build, synth: RotorSynth) -> PackedFloat32Array:
	var geometry := build.prop_geometry()
	var pt := Powertrain.new(
		build.motor_model(), build.k_t, build.k_q, build.battery_model(),
		build.effective_max_amps, build.rated_rpm(),
		build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5
	)

	var out := PackedFloat32Array()
	var block_dt := float(BLOCK) / SAMPLE_RATE
	var substep := block_dt / float(PHYSICS_SUBSTEPS)
	var elapsed := 0.0
	# The bench stands at a fixed distance in front of the listener; nothing moves, so
	# there is no doppler and the propagation filter is constant across the take.
	var bench_position := LISTENER + Vector3(0, 0, BENCH_DISTANCE_M)

	while elapsed < BENCH_DURATION_S:
		var ramp := clampf(elapsed / (BENCH_DURATION_S * 0.5), 0.0, 1.0)
		var throttle := BENCH_PEAK_THROTTLE * ramp
		var cmds := {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}
		for _i in PHYSICS_SUBSTEPS:
			pt.step(cmds, substep)

		out.append_array(_propagate(synth.render_block(pt.observables, 1.0, BLOCK),
			bench_position, Vector3.ZERO))
		elapsed += block_dt

	print("bench: final %.0f RPM, %.2f V live, %.1f A, %.3f%% of pack used" % [
		pt.observables.rpm[0], pt.observables.voltage_live_v,
		pt.observables.current_total_a, pt.observables.capacity_used_fraction * 100.0])
	return out


## Idle -> hover -> full -> hover -> idle across the take.
func _sweep_throttle(t: float, hover: float, full: float) -> float:
	if t < 0.12:
		return 0.0
	if t < 0.30:
		return hover * ((t - 0.12) / 0.18)
	if t < 0.45:
		return hover
	if t < 0.62:
		return hover + (full - hover) * ((t - 0.45) / 0.17)
	if t < 0.78:
		return full
	if t < 0.92:
		return full - (full - hover) * ((t - 0.78) / 0.14)
	return hover


## Distance gain and air absorption — the offline stand-in for what AudioStreamPlayer3D
## does in the game.
##
## The low-pass is the part that matters perceptually. Plain 1/r attenuation alone makes a
## distant drone sound like a near one played quietly, which is not what distance sounds
## like: air absorbs high frequencies far faster than low, so a drone at 70 m is a buzz and
## the same drone at 5 m is a scream, and the difference is spectral rather than only loud.
var _lowpass_state := 0.0

func _propagate(block: PackedFloat32Array, source: Vector3, _velocity: Vector3) -> PackedFloat32Array:
	var distance := maxf(source.distance_to(LISTENER), 0.5)
	var gain := clampf(REFERENCE_DISTANCE_M / distance, 0.0, 1.0)

	# Corner frequency falls with distance. 18 kHz right on top of it, down past 2 kHz by
	# 70 m — the same shape as real air absorption without pretending to be a fit to it.
	var cutoff := clampf(18000.0 * pow(REFERENCE_DISTANCE_M / distance, 0.45), 700.0, 18000.0)
	var alpha := 1.0 - exp(-TAU * cutoff / SAMPLE_RATE)

	var out := PackedFloat32Array()
	out.resize(block.size())
	for i in block.size():
		_lowpass_state += alpha * (block[i] - _lowpass_state)
		out[i] = clampf(_lowpass_state * gain, -1.0, 1.0)
	return out


## 16-bit mono PCM.
func _write_wav(samples: PackedFloat32Array, path: String) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.stereo = false
	stream.data = pcm
	stream.save_to_wav(path)
