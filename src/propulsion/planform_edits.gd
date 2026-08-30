class_name PlanformEdits
extends RefCounted
## Every change a builder can make to a blade's planform, as pure functions over the document's
## flat chord table — propulsion.md §7.1, slice P10d.
##
## ## Why the edits are a separate file from the canvas that makes them
##
## The same split `FrameEdits` made for the airframe designer, for the same reason and with the
## same payoff: "dragging a station halves the blade's mass" is an assertion about arithmetic and
## is provable headless, while "the station highlights when you hover it" is not. Putting the
## arithmetic here leaves the canvas holding only what a human has to look at — what is under the
## cursor, what a drag means, and what the result looks like.
##
## ## What these functions will and will not do to a planform
##
## A planform is piecewise-linear `c(r)` (§2), stored as `[r/R, chord_mm, …]` in ASCENDING r/R.
## Every function here returns a NEW array and leaves its argument alone, and every one of them
## preserves three invariants that `PropellerDocument.chord_at` depends on and does not check:
##
##   1. **at least two stations**, because a single point is not a piecewise-linear function and
##      `chord_at` would return it for every radius — a cylinder pretending to be a blade;
##   2. **strictly ascending r/R**, because `chord_at`'s interpolation walks the list in order and
##      a station out of sequence makes a whole span unreachable rather than wrong-looking;
##   3. **no negative chord**, which is not a picked threshold but a sign: a blade of negative
##      width has no meaning, and a mass integral over `c²` would happily accept one.
##
## An edit that would break any of the three is REFUSED — the array comes back unchanged — rather
## than repaired into something adjacent that the builder did not ask for. Same posture the rest of
## this system takes with a spec it cannot read: the caller asks, the model does not guess.
##
## ## No constants
##
## There is no minimum chord, no maximum station count and no snap grid in this file. A blade
## 0.2 mm wide at the tip is a real blade; a blade 40 stations long and a blade 6 stations long are
## both real planforms. The only bound is `MIN_STATIONS`, which is a property of piecewise-linear
## interpolation rather than a number anyone picked.

## Two points make a line. Below that, `chord_at` degenerates to a constant.
const MIN_STATIONS := 2


## The flat table as (r/R, chord_mm) points. Local rather than `PropellerDocument.chord_points()`
## because that accessor returns `Vector2`, which is SINGLE precision — fine for a picture, and a
## silent 4e-7 relative haircut on every chord that round-trips through an edit.
static func points(chord: PackedFloat64Array) -> Array:
	var out: Array = []
	var i := 0
	while i + 1 < chord.size():
		out.append([chord[i], chord[i + 1]])
		i += 2
	return out


## Points back to the flat table.
static func flatten(pts: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for point in pts:
		out.append(float(point[0]))
		out.append(float(point[1]))
	return out


## How many stations the table holds.
static func station_count(chord: PackedFloat64Array) -> int:
	@warning_ignore("integer_division")
	return chord.size() / 2


## The three invariants, as one question. Public because the canvas asserts it after every gesture
## and the tests assert it about every function here — one definition of "a usable planform".
static func is_valid(chord: PackedFloat64Array) -> bool:
	if station_count(chord) < MIN_STATIONS:
		return false
	var previous_r := -INF
	for point in points(chord):
		var r: float = point[0]
		var c: float = point[1]
		if not is_finite(r) or not is_finite(c):
			return false
		if c < 0.0:
			return false
		if r <= previous_r:
			return false
		previous_r = r
	return true


## Moves ONE station's chord, leaving its radius alone. The commonest edit in the room: a builder
## drags a control point up or down to fatten or thin the blade there.
##
## The radius is deliberately immovable in this function. Dragging a station sideways past its
## neighbour is the invariant-2 failure above, and the useful version of "put a station somewhere
## else" is `insert_station` followed by `remove_station` — two edits a builder can see, rather
## than one that silently reorders the table under them.
static func set_chord(chord: PackedFloat64Array, index: int, chord_mm: float) -> PackedFloat64Array:
	var pts := points(chord)
	if index < 0 or index >= pts.size():
		return chord
	if not is_finite(chord_mm) or chord_mm < 0.0:
		return chord
	pts[index] = [pts[index][0], chord_mm]
	var result := flatten(pts)
	return result if is_valid(result) else chord


## Adds a station at `r_frac`, at whatever chord the planform already has there — so the insert
## alone changes the SHAPE not at all, and the builder then drags the new point. An insert that
## moved the curve would make "add a control point" an edit with a side effect, which is the kind
## of thing that makes an editor untrustworthy for the drag that follows.
##
## Refused, rather than snapped, when a station already sits at `r_frac`: two points at one radius
## is invariant 2, and the station the builder wanted is the one already there.
static func insert_station(chord: PackedFloat64Array, r_frac: float,
		document: PropellerDocument) -> PackedFloat64Array:
	if not is_finite(r_frac):
		return chord
	var pts := points(chord)
	if pts.is_empty():
		return chord
	for point in pts:
		if is_equal_approx(float(point[0]), r_frac):
			return chord
	# The chord AT that radius, read from the document rather than re-interpolated here — the
	# room's own rule, and the reason this function takes a document it otherwise would not need.
	var chord_mm := document.chord_at(r_frac)
	pts.append([r_frac, chord_mm])
	pts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var result := flatten(pts)
	return result if is_valid(result) else chord


## Removes one station, unless it is one of the last two.
static func remove_station(chord: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var pts := points(chord)
	if index < 0 or index >= pts.size():
		return chord
	if pts.size() <= MIN_STATIONS:
		return chord
	pts.remove_at(index)
	var result := flatten(pts)
	return result if is_valid(result) else chord


## Scales every chord by one factor — "make the whole blade 10% wider", which is the edit a builder
## reaches for after comparing a printed section against a real blade.
static func scale_chord(chord: PackedFloat64Array, factor: float) -> PackedFloat64Array:
	if not is_finite(factor) or factor <= 0.0:
		return chord
	var pts := points(chord)
	for i in pts.size():
		pts[i] = [pts[i][0], float(pts[i][1]) * factor]
	var result := flatten(pts)
	return result if is_valid(result) else chord


## The index of the station nearest `r_frac`, or −1 for an empty table. What the canvas asks when
## a click lands: which control point did they mean.
static func nearest_station(chord: PackedFloat64Array, r_frac: float) -> int:
	var pts := points(chord)
	var best := -1
	var best_distance := INF
	for i in pts.size():
		var distance: float = absf(float(pts[i][0]) - r_frac)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
