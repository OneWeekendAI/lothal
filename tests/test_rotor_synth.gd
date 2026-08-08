class_name TestRotorSynth
extends RefCounted
## Sound is the one output nobody can assert by looking at it, so these tests measure the
## rendered waveform rather than checking that parameters were passed along.
##
## Three of these check claims that would otherwise only be caught by ear, late:
##   - beating exists when the four rotors differ and vanishes when they do not
##   - the tonal component follows THRUST, so a loaded prop and a free one differ
##   - the block rate cannot be heard, i.e. no click where two buffers meet
##
## And one is a gate rather than a claim: the CPU benchmark. Per-sample synthesis in an
## interpreted language is the part of this design most likely to simply not fit, and the
## honest way to find out is a number, not a guess.

const SAMPLE_RATE := 44100.0

## Timing runs for the CPU gate, and the budget the best of them must beat. The synth
## measures ~60-95 ms per second of audio on the reference machine; 150 ms leaves room for
## a slower runner while still catching anything that makes the synth structurally slower.
const BENCH_RUNS := 5
const BENCH_BUDGET_S := 0.15

static func run() -> Array:
	var results: Array = []

	# --- Silence when nothing is turning ---
	var idle := _observables(0.0, 0.0, 0.0)
	var idle_block := RotorSynth.new(SAMPLE_RATE).render_block(idle, 1.0, 2048)
	results.append(TestResult.new(
		"motors stopped is silence, not a floor of noise",
		_peak(idle_block) < 0.0001,
		"peak = %.6f" % _peak(idle_block)
	))

	# --- The rendered tone is the published blade-pass frequency ---
	# Checked against a detuned neighbour rather than in isolation: energy at 1450 Hz alone
	# proves nothing, because broadband noise has energy everywhere.
	var hovering := _observables(1450.0, 3400.0, 0.25)
	var block := RotorSynth.new(SAMPLE_RATE).render_block(hovering, 1.0, 16384)
	var on_tone := RotorSynth.goertzel_energy(block, 1450.0, SAMPLE_RATE)
	var off_tone := RotorSynth.goertzel_energy(block, 1200.0, SAMPLE_RATE)
	results.append(TestResult.new(
		"the rendered fundamental sits at the published blade-pass frequency",
		on_tone > off_tone * 20.0,
		"energy at 1450 Hz is %.1fx the energy at 1200 Hz" % (on_tone / maxf(off_tone, 1e-9))
	))

	results.append(TestResult.new(
		"harmonics are present, so it is a rotor rather than a sine tone",
		RotorSynth.goertzel_energy(block, 2900.0, SAMPLE_RATE) > off_tone * 5.0,
		"second harmonic is %.1fx the off-tone floor" % (RotorSynth.goertzel_energy(block, 2900.0, SAMPLE_RATE) / maxf(off_tone, 1e-9))
	))

	# --- Beating: the signature quad sound, and the point of synthesising four rotors ---
	# Broadband and commutation whine are both switched off for this measurement, so the
	# envelope being measured is rotor-against-rotor interference and nothing else. The
	# whine matters here: it sits at an inharmonic ratio to blade-pass, so it beats against
	# the fundamental all by itself and would put a few percent of envelope depth on the
	# control case, muddying the very comparison this test exists to make.
	var spread := _observables_per_motor([1000.0, 1008.0, 1000.0, 1008.0], 0.0, 0.25)
	var uniform := _observables_per_motor([1000.0, 1000.0, 1000.0, 1000.0], 0.0, 0.25)
	_mute_electrical(spread)
	_mute_electrical(uniform)
	var spread_depth := _envelope_depth(RotorSynth.new(SAMPLE_RATE).render_block(spread, 1.0, 22050))
	var uniform_depth := _envelope_depth(RotorSynth.new(SAMPLE_RATE).render_block(uniform, 1.0, 22050))

	results.append(TestResult.new(
		"four rotors at slightly different RPM beat; four at identical RPM do not",
		spread_depth > 0.15 and uniform_depth < 0.02,
		"8 Hz apart -> envelope depth %.3f, identical -> %.3f" % [spread_depth, uniform_depth]
	))

	# --- Tonal level follows thrust, not RPM ---
	# Same RPM, different loading. A model that scaled the tone off RPM alone renders these
	# two identically, and loses the difference between a prop holding an aircraft up and a
	# prop spinning in free air.
	var loaded := _observables(1450.0, 3400.0, 0.40)
	var unloaded := _observables(1450.0, 3400.0, 0.10)
	var loaded_energy := RotorSynth.goertzel_energy(
		RotorSynth.new(SAMPLE_RATE).render_block(loaded, 1.0, 8192), 1450.0, SAMPLE_RATE)
	var unloaded_energy := RotorSynth.goertzel_energy(
		RotorSynth.new(SAMPLE_RATE).render_block(unloaded, 1.0, 8192), 1450.0, SAMPLE_RATE)
	results.append(TestResult.new(
		"tonal level tracks thrust: the same RPM under load is louder than unloaded",
		loaded_energy > unloaded_energy * 4.0,
		"4x the thrust renders %.1fx the tonal energy" % (loaded_energy / maxf(unloaded_energy, 1e-9))
	))

	# --- Aliasing ---
	# A fundamental above Nyquist must be silenced, not rendered. Rendered anyway it folds
	# back down as a tone that DESCENDS as RPM rises, which is the most recognisable
	# artefact of naive digital synthesis.
	# Tip speed is zeroed so this measures the tonal path alone: broadband noise is
	# legitimately loud at a tip speed this high, and would mask the artefact being checked.
	var too_fast := _observables_per_motor([30000.0, 30000.0, 30000.0, 30000.0], 0.0, 0.25, 40000.0)
	var alias_block := RotorSynth.new(SAMPLE_RATE).render_block(too_fast, 1.0, 8192)
	results.append(TestResult.new(
		"a blade-pass frequency above Nyquist is silenced, not folded back as a phantom tone",
		_peak(alias_block) < 0.0001,
		"peak = %.6f at a 30 kHz fundamental (Nyquist = %.0f Hz)" % [_peak(alias_block), SAMPLE_RATE * 0.5]
	))

	var harmonics := RotorWavetable.harmonics_below_nyquist(1450.0, SAMPLE_RATE)
	results.append(TestResult.new(
		"the wavetable's top harmonic always stays below Nyquist",
		float(harmonics) * 1450.0 < SAMPLE_RATE * 0.5,
		"%d harmonics x 1450 Hz = %.0f Hz, Nyquist = %.0f Hz" % [harmonics, harmonics * 1450.0, SAMPLE_RATE * 0.5]
	))

	# --- The broadband filter must stay stable at any tip speed the sim can reach ---
	# Found by this suite rather than by ear: the noise band's centre frequency is Strouhal-
	# scaled and climbs past a sixth of the sample rate on a fast 5" prop, where a
	# Chamberlin filter diverges. It does not distort — it goes to NaN within a few samples
	# and stays there, so the sound simply stops, permanently, mid-flight.
	var screaming := _observables_per_motor([2400.0, 2400.0, 2400.0, 2400.0], 400.0, 1.0)
	var screaming_block := RotorSynth.new(SAMPLE_RATE).render_block(screaming, 1.0, 8192)
	var finite := true
	for i in screaming_block.size():
		if is_nan(screaming_block[i]) or is_inf(screaming_block[i]):
			finite = false
			break
	results.append(TestResult.new(
		"the broadband filter stays finite at an absurd tip speed, rather than going to NaN",
		finite and _peak(screaming_block) <= 1.0,
		"400 m/s tip -> peak %.4f, all samples finite: %s" % [_peak(screaming_block), finite]
	))

	# --- Block boundaries are inaudible ---
	# Phase is carried across blocks and every parameter ramps. If either were dropped, the
	# waveform would step at each boundary, and at ~86 buffers a second that is heard as a
	# steady buzz laid over the sound.
	var continuous := RotorSynth.new(SAMPLE_RATE)
	var first := continuous.render_block(hovering, 1.0, 1024)
	var second := continuous.render_block(hovering, 1.0, 1024)
	var seam := absf(second[0] - first[first.size() - 1])
	var interior := _max_step(first)
	results.append(TestResult.new(
		"no discontinuity where two rendered blocks meet",
		seam <= interior * 1.5,
		"step at the seam %.5f vs largest step inside a block %.5f" % [seam, interior]
	))

	# --- Doppler ---
	var approaching := RotorSynth.doppler_scale(Vector3.ZERO, Vector3(0, 0, -30.0), Vector3(0, 0, -50.0))
	var receding := RotorSynth.doppler_scale(Vector3.ZERO, Vector3(0, 0, 30.0), Vector3(0, 0, -50.0))
	var crossing := RotorSynth.doppler_scale(Vector3.ZERO, Vector3(30.0, 0, 0), Vector3(0, 0, -50.0))
	results.append(TestResult.new(
		"doppler rises when closing, falls when receding, and is absent when crossing",
		approaching > 1.05 and receding < 0.95 and is_equal_approx(crossing, 1.0),
		"closing %.3f, receding %.3f, crossing %.3f" % [approaching, receding, crossing]
	))

	var shifted := RotorSynth.new(SAMPLE_RATE).render_block(hovering, 1.1, 16384)
	results.append(TestResult.new(
		"a doppler factor actually shifts the rendered frequency",
		RotorSynth.goertzel_energy(shifted, 1595.0, SAMPLE_RATE) > RotorSynth.goertzel_energy(shifted, 1450.0, SAMPLE_RATE),
		"at 1.1x, energy moved from 1450 Hz to 1595 Hz"
	))

	# --- Nothing ever leaves the range the audio device accepts ---
	var punched := _observables_per_motor([2000.0, 2010.0, 1990.0, 2005.0], 250.0, 1.0)
	var punch_block := RotorSynth.new(SAMPLE_RATE).render_block(punched, 1.0, 16384)
	results.append(TestResult.new(
		"full throttle on all four rotors stays inside [-1, 1] without hard clipping",
		_peak(punch_block) <= 1.0 and _peak(punch_block) > 0.5,
		"peak = %.4f" % _peak(punch_block)
	))

	# --- The gate: does per-sample synthesis in GDScript actually fit? ---
	# One second of audio must render in far less than one second, because it shares a
	# frame with the physics, the renderer and the HUD.
	#
	# What this guards is a systematic regression — someone adding per-sample work that
	# makes the synth structurally slower — not a single slow scheduling moment. A lone
	# timing sample cannot tell those apart: on a loaded machine or a CI runner the OS
	# steals time from any one run. So take the *best* of several runs: the fastest run is
	# the one least disturbed by other load, and it is still far above the budget if the
	# synth itself got slower. A first run also pays warm-up costs, so discard one.
	var bench_obs := _observables_per_motor([1450.0, 1462.0, 1448.0, 1455.0], 193.0, 0.25)
	var bench := RotorSynth.new(SAMPLE_RATE)
	_bench_one_second(bench, bench_obs)   # warm-up, not measured
	var best_s := INF
	for _i in range(BENCH_RUNS):
		best_s = minf(best_s, _bench_one_second(bench, bench_obs))

	results.append(TestResult.new(
		"one second of four-rotor audio renders in a fraction of realtime",
		best_s < BENCH_BUDGET_S,
		"%.1f ms of CPU per second of audio (%.1f%% of one core), best of %d, budget %.0f ms"
			% [best_s * 1000.0, best_s * 100.0, BENCH_RUNS, BENCH_BUDGET_S * 1000.0]
	))

	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## An Observables filled by hand. Legitimate here in a way it would not be in
## test_observables.gd: these tests are about what the synthesiser does with published
## values, so the values are the input, and driving them from a real flight would make it
## impossible to hold RPM fixed while varying thrust.
## Render one second of audio in 512-sample blocks and return the wall time it took.
static func _bench_one_second(bench: RotorSynth, obs: Observables) -> float:
	var started := Time.get_ticks_usec()
	var rendered := 0
	while rendered < int(SAMPLE_RATE):
		bench.render_block(obs, 1.0, 512)
		rendered += 512
	return float(Time.get_ticks_usec() - started) / 1_000_000.0

static func _observables(blade_hz: float, elec_hz: float, thrust_fraction: float) -> Observables:
	return _observables_per_motor([blade_hz, blade_hz, blade_hz, blade_hz],
		blade_hz * 0.133, thrust_fraction, elec_hz)

static func _observables_per_motor(blade_hz: Array, tip_speed: float, thrust_fraction: float,
		elec_hz: float = 0.0) -> Observables:
	var obs := Observables.new()
	obs.weight_n = 4.87   # the reference build, ~496 g
	obs.prop_radius_m = 0.0635
	obs.blades = 3.0
	obs.pole_pairs = 7.0
	for i in Observables.MOTOR_COUNT:
		obs.blade_pass_hz[i] = blade_hz[i]
		obs.electrical_hz[i] = elec_hz if elec_hz > 0.0 else blade_hz[i] * 2.333
		obs.rpm[i] = blade_hz[i] * 20.0
		obs.thrust_n[i] = obs.weight_n * thrust_fraction
		obs.tip_speed_mps[i] = tip_speed
	obs.total_thrust_n = obs.weight_n * thrust_fraction * 4.0
	return obs

## Silences the commutation whine by zeroing RPM, which is what its amplitude scales off.
## Used where a measurement needs the blade tone on its own.
static func _mute_electrical(obs: Observables) -> void:
	for i in Observables.MOTOR_COUNT:
		obs.rpm[i] = 0.0
		obs.electrical_hz[i] = 0.0

static func _peak(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for i in samples.size():
		peak = maxf(peak, absf(samples[i]))
	return peak

## Largest sample-to-sample step inside a block — the yardstick a block seam is judged
## against, since a waveform at 1450 Hz legitimately moves a fair amount per sample.
static func _max_step(samples: PackedFloat32Array) -> float:
	var largest := 0.0
	for i in range(1, samples.size()):
		largest = maxf(largest, absf(samples[i] - samples[i - 1]))
	return largest

## Depth of the amplitude envelope, as (peak - trough) / peak measured over windows long
## enough to contain several cycles of the carrier but short enough to resolve a beat of a
## few Hz. This is what "you can hear it throbbing" reduces to numerically.
static func _envelope_depth(samples: PackedFloat32Array) -> float:
	const WINDOW := 512
	var highest := 0.0
	var lowest := 1e9
	var i := 0
	while i + WINDOW <= samples.size():
		var window_peak := 0.0
		for n in WINDOW:
			window_peak = maxf(window_peak, absf(samples[i + n]))
		highest = maxf(highest, window_peak)
		lowest = minf(lowest, window_peak)
		i += WINDOW
	if highest <= 0.0:
		return 0.0
	return (highest - lowest) / highest
