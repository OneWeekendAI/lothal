class_name RotorWavetable
extends RefCounted
## Band-limited wavetables for the rotor's tonal signature.
##
## Why a table at all: the naive way to synthesise a harmonic tone is to call sin() once
## per harmonic per sample. Four rotors x ~12 harmonics x 44100 samples is two million
## transcendental calls a second from an interpreted language, and it does not fit. A
## table is built once, then costs one array read and a lerp per sample.
##
## Why BAND-LIMITED, which is the part that is easy to skip and ruins the sound: a table
## containing harmonics above the Nyquist frequency does not simply lose them. They fold
## back down into the audible range as inharmonic tones that move the WRONG WAY as RPM
## rises — throttle up and you hear a descending whistle underneath. It is the single most
## recognisable signature of cheap digital synthesis. So the table is chosen per block for
## the highest harmonic count that still fits below Nyquist, and tables are cached because
## the choice only changes as RPM sweeps.

const TABLE_SIZE := 2048
## The strongest harmonic count worth building. Beyond this the amplitudes are far below
## anything audible under the broadband noise.
const MAX_HARMONICS := 16

## Per-harmonic amplitude rolloff for rotor loading noise. A small, heavily loaded prop is
## harmonically rich — the pressure pulse from a blade is nothing like a sine — so this is
## a gentle slope. Steeper than about -12 dB and it turns into a flute; shallower than
## about -4 dB and it turns into a buzzer.
const HARMONIC_ROLLOFF_DB := -7.0

static var _cache: Dictionary = {}

## Table for `harmonic_count` harmonics, with a wrap sample appended so the interpolating
## reader never needs a modulo or a bounds test.
static func get_table(harmonic_count: int) -> PackedFloat32Array:
	var n := clampi(harmonic_count, 1, MAX_HARMONICS)
	if _cache.has(n):
		return _cache[n]

	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE + 1)

	var peak := 0.0
	for i in TABLE_SIZE:
		var phase := TAU * float(i) / float(TABLE_SIZE)
		var sample := 0.0
		for h in range(1, n + 1):
			sample += _harmonic_amplitude(h) * sin(phase * float(h))
		table[i] = sample
		peak = maxf(peak, absf(sample))

	# Normalise to unit peak so that swapping tables as RPM crosses a Nyquist boundary is
	# not also a step change in loudness.
	if peak > 0.0:
		var scale := 1.0 / peak
		for i in TABLE_SIZE:
			table[i] = table[i] * scale
	table[TABLE_SIZE] = table[0]

	_cache[n] = table
	return table

static func _harmonic_amplitude(harmonic: int) -> float:
	return pow(10.0, (HARMONIC_ROLLOFF_DB * float(harmonic - 1)) / 20.0)

## The largest harmonic count whose top partial still sits below Nyquist at `fundamental_hz`.
## Returns at least 1: a fundamental already above Nyquist is silenced by the caller
## rather than aliased down by this function.
static func harmonics_below_nyquist(fundamental_hz: float, sample_rate_hz: float) -> int:
	if fundamental_hz <= 0.0:
		return 1
	var nyquist := sample_rate_hz * 0.5
	return clampi(int(floor(nyquist / fundamental_hz)), 1, MAX_HARMONICS)
