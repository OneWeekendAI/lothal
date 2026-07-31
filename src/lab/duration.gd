class_name Duration
extends RefCounted
## Seconds, as something a builder says out loud.
##
## THIS FILE EXISTS BECAUSE THERE WERE THREE OF IT. The charger, the battery bench's instrument
## panel and the voltage trace's time axis each carried their own six-line copy of the same mm:ss
## formatter, differing only in whether there is a space before the "s" — and two of them had
## already drifted apart on that. Three copies is also why one GDScript warning (INTEGER_DIVISION,
## on the `/ 60`) showed up three times in the same sweep: the warning was not three problems, it
## was one problem in three places, and the count was the only thing pointing at that.
##
## So there is one expression of minutes-and-seconds here, and the variants are named policies
## rather than near-duplicates:
##
##   `spoken`  — "45 s", "2:05". For a readout somebody reads as a sentence.
##   `short`   — "45s", "2:05". For an axis label, where the space costs pixels that matter.
##   `clock`   — "0:45", "2:05". Always minutes and seconds, for a readout that has to hold still:
##               the HUD's flight-time countdown reads as a clock and a clock does not change
##               shape as it runs down.
##   `or_dash` — `spoken`, but an absent or impossible duration reads as "—" rather than as
##               "0 s", which would be indistinguishable from a bench that had not been started.
##
## Nothing here rounds or clamps beyond what the format string does. A caller with a duration it
## does not trust uses `or_dash`; a caller that has already decided passes it straight in.
##
## LapTimer.format is deliberately NOT folded in here. A lap is quoted to hundredths — "1:07.42" —
## which is a different format for a different judgement, not a fifth copy of this one.

const MINUTE_S := 60.0


## "45 s" below a minute, "2:05" above it.
static func spoken(seconds: float) -> String:
	if seconds < MINUTE_S:
		return "%.0f s" % seconds
	return clock(seconds)


## The same, tightened for an axis label where every pixel between the tick and its neighbour is
## contested. Deliberately NOT a separate formatter: the only difference is the space.
static func short(seconds: float) -> String:
	if seconds < MINUTE_S:
		return "%.0fs" % seconds
	return clock(seconds)


## A duration that may not exist — a hold-up time on a bench drawing no current, a charge time on a
## pack already full. Nothing to say is said as nothing, not as zero.
static func or_dash(seconds: float) -> String:
	if seconds <= 0.0 or not is_finite(seconds):
		return "—"
	return spoken(seconds)


## The one place minutes and seconds are separated. The minutes term is a FLOOR of a real quotient
## rather than an integer division — `floori` says that out loud, where `int(seconds) / 60` left
## the reader to work out whether the truncation was meant. Identical output for every
## non-negative duration, which is all a clock ever gets.
##
## Truncating rather than rounding, which is what all four copies did. A caller that wants the
## nearest second rounds before it gets here, as the HUD's countdown does.
static func clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [floori(whole / MINUTE_S), whole % int(MINUTE_S)]
