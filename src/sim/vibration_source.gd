class_name VibrationSource
extends RefCounted
## What the airframe shakes the gyro with — the seam, and nothing else.
##
## This file is deliberately almost empty. It exists so that the question "how does vibration
## reach the sensor" is settled and testable BEFORE the question "what is vibration", because
## those two are independently wrong-able and the first one has a trap in it.
##
## ---------------------------------------------------------------------------
## THE TRAP: WHY THIS IS NOT A BODY FORCE
## ---------------------------------------------------------------------------
##
## The physics argues for body forces — an unbalanced prop really does shake the airframe, and
## the airframe really is the rigid body this simulation integrates. The numbers forbid it.
## Work the frequencies for the reference build (2207 1960KV on 4S, three blades):
##
##                     rotation (1x)    blade pass (3x)
##   hover (~29%)         ~215 Hz          ~650 Hz
##   full throttle        ~485 Hz         ~1450 Hz
##
## The rate loop runs at 1 kHz (physics.md §6, 8 substeps of a 120 Hz frame). A rigid-body sim
## stepping at 1 kHz cannot represent anything above 500 Hz, so injecting blade-pass forces into
## the body would produce garbage across most of the throttle range — not "an approximation",
## garbage: a 1450 Hz force sampled by a 1 kHz integrator is an arbitrary low-frequency wobble
## that would then be integrated into the aircraft's actual attitude.
##
## So vibration enters HERE, in the sensor path, at the sensor's own sample instants, added
## alongside bias and noise and ahead of the PT1 (Gyro._sample). The rigid body never sees it,
## which is correct: at these frequencies and these amplitudes the AIRCRAFT barely moves. What
## moves is the sensor, and what the FC does about what the sensor reports is the entire subject.
##
## ---------------------------------------------------------------------------
## ALIASING IS BY CONSTRUCTION, NOT BY ACCIDENT
## ---------------------------------------------------------------------------
##
## The gyro samples at 1 kHz too, so at high throttle the blade-pass line genuinely exceeds
## Nyquist and folds down. A 1450 Hz tone read by a 1 kHz sampler IS a 450 Hz tone — not
## approximately, exactly, because 1450n/1000 and 450n/1000 differ by whole cycles at every
## integer n. That is a real phenomenon on real quads and a well-known reason firmware runs
## gyros at 8 kHz rather than at the loop rate.
##
## This is stated out loud because aliasing that emerges from a correct sample-and-hold and
## aliasing that happens because someone forgot look IDENTICAL in the output, and only one of
## them is trustworthy. Here it emerges: Gyro.update already holds its own sample clock and
## calls this once per sample instant, so there is no anti-alias stage to have omitted and no
## special case to have written. tests/test_gyro.gd pins the fold-down against that exact
## arithmetic.
##
## ---------------------------------------------------------------------------
## THE CONTRACT
## ---------------------------------------------------------------------------
##
## Body-axis rad/s, added to the true rate. Evaluated at t = 0, T, 2T, ... where T is the
## sensor's sample period — a monotone sequence, never revisited, so an implementation may
## integrate phase from one call to the next rather than recomputing it from t. VibrationModel
## does exactly that, because a signal whose frequency follows rpm cannot be written as
## sin(2*pi*f*t) without stepping its phase every time the throttle moves.
##
## The base returns nothing, and that is the default a Gyro gets. A sensor with no vibration
## source is the sensor this project has had since the FC slice, reading exactly what it read
## before — which is what lets 670 existing tests stay honest about what they measure.
func angular_rate_at(_t_s: float) -> Vector3:
	return Vector3.ZERO


## Returns the source to the state it was in at t = 0. Called by Gyro.reset(), and it must be
## enough on its own: gyro.gd re-seeds its RNG here so that "the same flight twice" is the same
## flight, and a vibration source that carried accumulated phase across a respawn would break
## that guarantee from the one place nobody would look for it.
func reset() -> void:
	pass
