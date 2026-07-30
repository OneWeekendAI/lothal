class_name RotorSynth
extends RefCounted
## Turns the observables layer into sound. Pure DSP: no Node, no AudioServer, no scene
## tree, so the whole thing runs and is asserted on headlessly, exactly like src/sim.
## DroneAudio is the thin engine-facing wrapper around this.
##
## Three mechanisms, because a real rotor has three and they scale differently. Modelling
## them as one "engine noise that gets louder with throttle" is what makes synthesised
## drones sound like a hair dryer:
##
##   1. TONAL — harmonics of blade-pass frequency. The periodic pressure field of a loaded
##      blade sweeping past you. Tracks THRUST, not RPM: a prop spinning freely and a prop
##      actually holding the aircraft up are different sounds, and thrust is already
##      published per motor so this costs nothing.
##
##   2. BROADBAND — turbulent boundary-layer and tip-vortex noise. The air, rather than the
##      blade. Scales very steeply with tip speed (acoustic power roughly as the sixth
##      power, so pressure as the cube), and its centre frequency RISES with tip speed
##      rather than sitting still. This is the component that makes it sound like moving
##      air instead of a played tone.
##
##   3. ELECTRICAL — commutation whine at pole-pair frequency. Thin and high. Kept quiet
##      deliberately: architecture.md's warning that "a physically correct 3.4 kHz whine is
##      a dentist drill" is about exactly this component.
##
## The signature quad sound is not synthesised anywhere in here. Beating between the four
## rotors emerges because each rotor's phase is integrated from its OWN published
## frequency, and the flight controller never lets four motors sit at the same RPM. The
## warble on top emerges because per-motor thrust ripples as the PID corrects. Both are
## consequences of summing four honest sources; neither is an effect that was added.

const DEFAULT_SAMPLE_RATE_HZ := 44100.0
const MOTOR_COUNT := 4

## Loudness of one rotor's tonal component at a thrust equal to the whole aircraft's
## weight. Four rotors at hover each carry a quarter of that, so the tonal sum at hover
## sits near a quarter of full scale, leaving headroom for a full-throttle punch out.
const TONAL_GAIN := 0.55
const BROADBAND_GAIN := 0.42
const ELECTRICAL_GAIN := 0.07

## The reference build's blade tip at full throttle: a 5" prop at ~29,000 RPM. Broadband
## level is expressed relative to this rather than in absolute terms, so a 3" build is
## quieter and a 7" build louder without any per-build tuning.
const REFERENCE_TIP_SPEED_MPS := 193.0
const REFERENCE_RPM := 29000.0

## Broadband noise peaks at a roughly constant Strouhal number, which is why its centre
## frequency climbs with tip speed instead of staying put. Chord is estimated from prop
## diameter — blade chord is not a spec in the parts catalog, and a fixed fraction of
## diameter is how props actually scale.
const BROADBAND_STROUHAL := 0.2
const BROADBAND_CHORD_TO_DIAMETER := 0.1
const BROADBAND_MIN_HZ := 150.0
## Bandwidth of the broadband component. Low Q on purpose: this is meant to be a wide
## rushing band, and a high Q turns it into a whistle, which is a different mechanism.
const BROADBAND_Q := 0.9

## The Chamberlin state-variable filter below is only stable while its frequency
## coefficient 2*sin(pi*fc/fs) stays below 1, which caps fc at a SIXTH of the sample rate,
## not the half that Nyquist would suggest. Above it the filter does not degrade
## gracefully — it diverges to infinity within a few samples and every subsequent sample is
## NaN, which reaches the audio device as a click and then silence.
##
## This bit: a fast 5" prop pushes the Strouhal-scaled centre frequency well past fs/6, so
## the limit is reached in normal flight, not only in pathological cases.
const MAX_FILTER_FRACTION := 0.15

## Soft-clip threshold. Mild saturation, standing in for the fact that neither air nor a
## microphone responds linearly to a loud close source. Also the thing that stops a
## four-rotor punch-out from hard-clipping into a crackle.
const SATURATION_KNEE := 0.7

var sample_rate_hz: float

# --- Oscillator state. Phase is INTEGRATED, never recomputed from frequency each block:
# recomputing it restarts each block at the same phase, which destroys the interference
# between rotors that produces beating, and clicks at every block boundary.
var _blade_phase := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _elec_phase := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

# --- Previous block's targets, so every parameter ramps across a block instead of
# stepping at the boundary. A step in amplitude or frequency is an audible tick.
var _prev_blade_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_elec_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_tonal_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_elec_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_noise_amp: float = 0.0
var _prev_noise_f: float = 0.0
var _primed := false

# --- Broadband filter and noise state ---
var _svf_low: float = 0.0
var _svf_band: float = 0.0
var _rng_state: int = 0x2545F491

func _init(p_sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ) -> void:
	sample_rate_hz = p_sample_rate_hz

## Renders `frame_count` mono samples from the published observables.
##
## `doppler_scale` multiplies every frequency: 1.0 for a stationary source, above 1.0 when
## approaching the listener. It is applied here rather than by pitch-shifting the finished
## buffer because we are generating the waveform anyway, and scaling the phase increment is
## both exact and free, where resampling a rendered block is neither.
func render_block(obs: Observables, p_doppler_scale: float, frame_count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frame_count)
	if frame_count <= 0:
		return out

	var nyquist := sample_rate_hz * 0.5
	var weight_n := maxf(obs.weight_n, 0.001)

	# --- This block's targets ---
	var blade_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var elec_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var tonal_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var elec_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var highest_blade_hz := 0.0
	var mean_tip := 0.0

	for i in MOTOR_COUNT:
		# Read the PUBLISHED frequencies. Deriving them from obs.rpm here would work today
		# and would be the bug the observables layer exists to prevent.
		var blade_hz: float = obs.blade_pass_hz[i] * p_doppler_scale
		var elec_hz: float = obs.electrical_hz[i] * p_doppler_scale

		# A fundamental above Nyquist cannot be represented at all; rendering it anyway
		# folds it back down as a descending phantom tone. Silence is the honest answer.
		if blade_hz > 0.0 and blade_hz < nyquist:
			blade_inc[i] = blade_hz / sample_rate_hz
			tonal_amp[i] = TONAL_GAIN * (obs.thrust_n[i] / weight_n)
			highest_blade_hz = maxf(highest_blade_hz, blade_hz)

		if elec_hz > 0.0 and elec_hz < nyquist:
			elec_inc[i] = elec_hz / sample_rate_hz
			# Commutation whine follows motor torque, which goes as RPM squared just as
			# thrust does.
			var rpm_fraction: float = obs.rpm[i] / REFERENCE_RPM
			elec_amp[i] = ELECTRICAL_GAIN * rpm_fraction * rpm_fraction

		mean_tip += obs.tip_speed_mps[i]

	mean_tip /= float(MOTOR_COUNT)

	# --- Broadband target ---
	# The four rotors' broadband contributions are turbulent and mutually incoherent, so
	# they sum as POWER rather than as pressure. Four separate noise generators and filters
	# would cost four times as much and be indistinguishable from one at the summed level,
	# so this is one band whose level carries all four.
	var chord_m := maxf(BROADBAND_CHORD_TO_DIAMETER * obs.prop_radius_m * 2.0, 0.001)
	var noise_f := clampf(BROADBAND_STROUHAL * mean_tip / chord_m,
		BROADBAND_MIN_HZ, sample_rate_hz * MAX_FILTER_FRACTION)
	var tip_ratio := mean_tip / REFERENCE_TIP_SPEED_MPS
	var noise_amp := BROADBAND_GAIN * tip_ratio * tip_ratio * tip_ratio

	# The very first block has no previous target to ramp from. Ramping up from silence
	# instead would put a fade-in on the first few milliseconds of every respawn.
	if not _primed:
		_prev_blade_inc = blade_inc.duplicate()
		_prev_elec_inc = elec_inc.duplicate()
		_prev_tonal_amp = tonal_amp.duplicate()
		_prev_elec_amp = elec_amp.duplicate()
		_prev_noise_amp = noise_amp
		_prev_noise_f = noise_f
		_primed = true

	# --- Per-sample ramp steps ---
	var inv := 1.0 / float(frame_count)
	var d_blade_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var d_elec_inc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var d_tonal_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var d_elec_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in MOTOR_COUNT:
		d_blade_inc[i] = (blade_inc[i] - _prev_blade_inc[i]) * inv
		d_elec_inc[i] = (elec_inc[i] - _prev_elec_inc[i]) * inv
		d_tonal_amp[i] = (tonal_amp[i] - _prev_tonal_amp[i]) * inv
		d_elec_amp[i] = (elec_amp[i] - _prev_elec_amp[i]) * inv
	var d_noise_amp := (noise_amp - _prev_noise_amp) * inv
	var d_noise_f := (noise_f - _prev_noise_f) * inv

	var table := RotorWavetable.get_table(
		RotorWavetable.harmonics_below_nyquist(highest_blade_hz, sample_rate_hz))
	var sine := RotorWavetable.get_table(1)
	var table_size := float(RotorWavetable.TABLE_SIZE)

	# Locals, because a member lookup per sample in GDScript is a real cost at 44,100 of
	# them a second.
	var blade_phase := _blade_phase
	var elec_phase := _elec_phase
	var cur_blade_inc := _prev_blade_inc
	var cur_elec_inc := _prev_elec_inc
	var cur_tonal_amp := _prev_tonal_amp
	var cur_elec_amp := _prev_elec_amp
	var cur_noise_amp := _prev_noise_amp
	var cur_noise_f := _prev_noise_f
	var svf_low := _svf_low
	var svf_band := _svf_band
	var rng := _rng_state

	for n in frame_count:
		var sample := 0.0

		for i in MOTOR_COUNT:
			var p: float = blade_phase[i] + cur_blade_inc[i]
			if p >= 1.0:
				p -= 1.0
			blade_phase[i] = p
			var x := p * table_size
			var idx := int(x)
			sample += cur_tonal_amp[i] * (table[idx] + (table[idx + 1] - table[idx]) * (x - float(idx)))

			var q: float = elec_phase[i] + cur_elec_inc[i]
			if q >= 1.0:
				q -= 1.0
			elec_phase[i] = q
			var y := q * table_size
			var jdx := int(y)
			sample += cur_elec_amp[i] * (sine[jdx] + (sine[jdx + 1] - sine[jdx]) * (y - float(jdx)))

			cur_blade_inc[i] += d_blade_inc[i]
			cur_elec_inc[i] += d_elec_inc[i]
			cur_tonal_amp[i] += d_tonal_amp[i]
			cur_elec_amp[i] += d_elec_amp[i]

		# White noise from an inline LCG. randf() would be a scripting-engine call per
		# sample, which at this rate is the single most expensive line in the loop.
		rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
		var white := float(rng) * 9.3132257e-10 - 1.0

		# Chamberlin state-variable filter, band-pass output. Two multiplies and three adds
		# for a resonant band whose centre frequency can be swept per sample, which is what
		# the Strouhal scaling needs.
		var f := 2.0 * sin(PI * cur_noise_f / sample_rate_hz)
		svf_low += f * svf_band
		var band_in := white - svf_low - BROADBAND_Q * svf_band
		svf_band += f * band_in
		sample += cur_noise_amp * svf_band

		cur_noise_amp += d_noise_amp
		cur_noise_f += d_noise_f

		out[n] = _soft_clip(sample)

	_blade_phase = blade_phase
	_elec_phase = elec_phase
	_prev_blade_inc = blade_inc
	_prev_elec_inc = elec_inc
	_prev_tonal_amp = tonal_amp
	_prev_elec_amp = elec_amp
	_prev_noise_amp = noise_amp
	_prev_noise_f = noise_f
	_svf_low = svf_low
	_svf_band = svf_band
	_rng_state = rng

	return out

## Mono rendered into the interleaved stereo frames AudioStreamGeneratorPlayback expects.
## Deliberately identical in both channels: the source is a point in space, and where it
## sits in the stereo field is the 3D player's business, not the synthesiser's.
func render_stereo(obs: Observables, p_doppler_scale: float, frame_count: int) -> PackedVector2Array:
	var mono := render_block(obs, p_doppler_scale, frame_count)
	var frames := PackedVector2Array()
	frames.resize(frame_count)
	for n in frame_count:
		var s: float = mono[n]
		frames[n] = Vector2(s, s)
	return frames

## Cubic soft clip. Linear below the knee, compressing above it, hard-limited at 1.0 so a
## buffer can never be sent to the audio device with samples outside its range.
static func _soft_clip(x: float) -> float:
	if x > SATURATION_KNEE:
		var over := minf(x - SATURATION_KNEE, 1.0 - SATURATION_KNEE)
		var t := over / (1.0 - SATURATION_KNEE)
		return SATURATION_KNEE + (1.0 - SATURATION_KNEE) * (t - t * t * t / 3.0) * 1.5
	if x < -SATURATION_KNEE:
		return -_soft_clip(-x)
	return x

## Doppler factor for a source moving at `source_velocity` relative to a listener at
## `listener_position`. Above 1.0 while closing, below while receding — the frequency rise
## and the drop as it goes past, which is most of what makes a fast pass read as fast.
##
## Only the component of velocity ALONG the line to the listener matters: a drone flying a
## circle around you at constant radius has a large speed and no doppler shift at all.
static func doppler_scale(source_position: Vector3, source_velocity: Vector3, listener_position: Vector3) -> float:
	var to_listener := listener_position - source_position
	var distance := to_listener.length()
	if distance < 0.001:
		return 1.0
	var closing_speed := source_velocity.dot(to_listener / distance)
	# Clamped short of the speed of sound: at Mach 1 the exact expression divides by zero,
	# and nothing in this simulation should be able to produce an infinite frequency.
	closing_speed = clampf(closing_speed, -0.7 * Observables.SPEED_OF_SOUND_MPS, 0.7 * Observables.SPEED_OF_SOUND_MPS)
	return Observables.SPEED_OF_SOUND_MPS / (Observables.SPEED_OF_SOUND_MPS - closing_speed)

## Energy at a single frequency, by the Goertzel algorithm — one bin of a DFT for the cost
## of a loop. Used by the tests to assert what was actually rendered rather than trusting
## that the parameter went in correctly.
static func goertzel_energy(samples: PackedFloat32Array, hz: float, p_sample_rate_hz: float) -> float:
	var count := samples.size()
	if count == 0 or hz <= 0.0:
		return 0.0
	var coeff := 2.0 * cos(TAU * hz / p_sample_rate_hz)
	var s1 := 0.0
	var s2 := 0.0
	for i in count:
		var s0: float = samples[i] + coeff * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coeff * s1 * s2
