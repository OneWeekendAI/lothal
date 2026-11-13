class_name LiftVerdict
extends RefCounted
## Whether an aircraft can lift itself, in the words the Design Space prints beside its weight and
## thrust figures. One function, read off the Build: "can it" is `Build.can_hover()` (peak thrust, pack
## sag and current cap included, against the weight), never a second comparison written here.
##
## Three states. LIFTS: thrust-to-weight in the air is at least MARGINAL_BELOW. MARGINAL: it hovers but
## has little left to climb or manoeuvre on. CANNOT: peak thrust is below the weight, so at full throttle
## the aircraft stays on the ground (or, free in the air, sinks), whatever the hover-throttle figure says.

const LIFTS := "lifts"
const MARGINAL := "marginal"
const CANNOT := "cannot"
## Below this thrust-to-weight an aircraft flies but is a poor one: a quarter of the climb a 2:1 build has,
## and no authority left for a punch-out or to recover from a stall. A rule of thumb, not a standard.
const MARGINAL_BELOW := 1.5

const GRAVITY := 9.80665


## {state, needs_g, max_g, twr, text}. `needs_g` is the aircraft's own weight as grams of thrust; `max_g` the
## most thrust it can reach in the air (the peak, not the bench figure at nominal volts); `twr` their ratio.
## `text` is "" for LIFTS.
static func of(b: Build) -> Dictionary:
	if b == null:
		return {"state": LIFTS, "needs_g": 0.0, "max_g": 0.0, "twr": 0.0, "text": ""}
	var needs_g := b.weight_n() / GRAVITY * 1000.0
	var max_g := float(b.peak_thrust()["thrust_n"]) / GRAVITY * 1000.0
	var twr := max_g / needs_g if needs_g > 0.0 else 0.0
	var state := LIFTS
	var text := ""
	if not b.can_hover():
		state = CANNOT
		text = "Can't lift: needs %.0f g thrust, max %.0f g (T/W %.2f)" % [needs_g, max_g, twr]
	elif twr < MARGINAL_BELOW:
		state = MARGINAL
		text = "Marginal lift: T/W %.2f, little left to climb on" % twr
	return {"state": state, "needs_g": needs_g, "max_g": max_g, "twr": twr, "text": text}
