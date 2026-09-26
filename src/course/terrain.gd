class_name Terrain
extends RefCounted
## The shape of the ground: a rectangle somewhere in the world, and an analytic height over it.
##
## ---------------------------------------------------------------------------
## NOTHING IS DRAWN HERE
## ---------------------------------------------------------------------------
##
## This file is arithmetic. F5 builds the mesh and F4 makes this the ground authority; both read
## `height_at(x, z)` and neither is allowed to carry a second copy of the shape. That is the whole
## reason the vocabulary lands before any geometry does: a mesh built from one formula and a
## below-ground warning computed from another agree on a fresh install and drift the first time
## either is touched, which is the stale-reading failure `labs-and-sim.md` §2.6 describes.
##
## ---------------------------------------------------------------------------
## THE BLOCK IS THE FILE FORMAT, AND IT DOES NOT CHANGE
## ---------------------------------------------------------------------------
##
## `Site` wrote a `terrain` block from day one — `shape` / `width_m` / `length_m` / `center_x_m` /
## `center_z_m` — precisely so this class could arrive behind it without a migration. So `_raw`
## keeps the record exactly as it was read and `to_data()` writes back only the values that have
## actually changed. An `int` 120 in a hand-edited file stays `120` and does not become `120.0`:
## the failure this guards is Lothal quietly editing every file a builder owns on first launch.
##
## Shape-specific numbers are SIBLING KEYS in the same block, not a nested dictionary, and `dims`
## carries every key of the block this class does not otherwise name — including ones it does not
## recognise. That is deliberate: a flat field saved by a future version that keeps a `rise_m`
## beside it must not lose it here.
##
## ---------------------------------------------------------------------------
## OUTSIDE THE EXTENT IS THE NEAREST BOUNDARY POINT, NOT ZERO
## ---------------------------------------------------------------------------
##
## A gate two metres off the edge of a hillside is still on a hillside. Answering 0 there would
## make F4's below-ground warning lie in exactly the place the design says it must not — it would
## report a gate buried in a hill as comfortably clear, because the ground under it was invented.
## So a point outside the rectangle is clamped onto the boundary and the height read there.
##
## ---------------------------------------------------------------------------
## `is_flat_at_zero()` IS `shape == FLAT` AND NOTHING ELSE
## ---------------------------------------------------------------------------
##
## It looks like it wants an optimisation: a slope whose `rise_m` is 0 is flat, a bowl of zero
## depth is flat, so why not say so? Because F9 appends a terrain term to the best-lap fingerprint
## ONLY when this is false, and every best lap ever set rests on this predicate being stable. The
## moment it starts reasoning about dims, a build that changes how a zero-rise slope is read
## silently re-hashes — and orphans laps nobody touched. Shape name, nothing else.

const FLAT := &"flat"
const SLOPE := &"slope"
const BOWL := &"bowl"
const BANKED := &"banked"
const ENCLOSURE := &"enclosure"
const SHAPES := [FLAT, SLOPE, BOWL, BANKED, ENCLOSURE]

## The edges a bank may be raised along. North is −z and south is +z, matching Godot's forward
## axis; east is +x. Named here so the one place that decides is not a string literal in a branch.
const NORTH := "north"
const SOUTH := "south"
const EAST := "east"
const WEST := "west"
const EDGES := [NORTH, SOUTH, EAST, WEST]

## The keys each shape reads, and the value each falls back to when the block does not carry it.
## Chosen numbers, not measured ones — a builder who cares types their own, and F5 owes every one
## of these an editable field.
const DIM_DEFAULTS := {
	FLAT: {},
	SLOPE: {"rise_m": 2.0, "direction_deg": 0.0},
	BOWL: {"depth_m": 2.0},
	BANKED: {"bank_height_m": 2.0, "bank_width_m": 10.0, "bank_edge": NORTH},
	ENCLOSURE: {"wall_height_m": 4.0, "roofed": true, "pillar_spacing_m": 8.0},
}

## The keys this class names itself; everything else in the block is a dim.
const BLOCK_KEYS := ["shape", "width_m", "length_m", "center_x_m", "center_z_m"]

const DEFAULT_WIDTH_M := 120.0
const DEFAULT_LENGTH_M := 120.0

## Written through a setter for ONE reason: choosing a shape has to clear `_unknown_shape`. See
## `to_data()` — without that, flat is the one shape a builder can never select on a file written
## by a newer build, because the writer keeps putting the newer name back.
var shape: StringName = FLAT:
	set(value):
		shape = value
		_unknown_shape = ""
var width_m := DEFAULT_WIDTH_M
var length_m := DEFAULT_LENGTH_M
var center_x_m := 0.0
var center_z_m := 0.0
## Shape-specific values, plus anything in the block this version does not recognise.
var dims: Dictionary = {}

## The record this terrain was read from, kept verbatim so an untouched load writes an untouched
## file. Empty for a terrain built in code.
var _raw: Dictionary = {}
## A shape name from the file that this version does not know. It reads as flat and it is WRITTEN
## BACK unchanged: a newer build's shape must survive being opened by an older one, or opening
## Lothal once flattens a field somebody sculpted.
var _unknown_shape := ""


static func flat(p_width_m: float, p_length_m: float,
		p_center_x_m := 0.0, p_center_z_m := 0.0) -> Terrain:
	var out := Terrain.new()
	out.shape = FLAT
	out.width_m = p_width_m
	out.length_m = p_length_m
	out.center_x_m = p_center_x_m
	out.center_z_m = p_center_z_m
	return out


## A terrain of any shape, with its dims. The one constructor the editor and the tests use for the
## four non-flat shapes; `flat()` stays separate because it is the default everything falls back to.
static func shaped(p_shape: StringName, p_width_m: float, p_length_m: float,
		p_dims: Dictionary = {}, p_center_x_m := 0.0, p_center_z_m := 0.0) -> Terrain:
	var out := flat(p_width_m, p_length_m, p_center_x_m, p_center_z_m)
	out.shape = p_shape if p_shape in SHAPES else FLAT
	out.dims = p_dims.duplicate(true)
	return out


func extent() -> Vector2:
	return Vector2(width_m, length_m)


func center() -> Vector2:
	return Vector2(center_x_m, center_z_m)


## Whether a world point is over this patch of ground. Horizontal only, inclusive on the edge, to
## the same hair of tolerance `Site.contains()` uses — a gate exactly on the boundary of a field
## sized to contain it is contained.
func contains(x: float, z: float) -> bool:
	# Asked ONCE. It was called twice here, which was free arithmetic at F3 and is not free now
	# that F4 asks the ground a question per gate and per frame — and, worse, it was two chances
	# for one rule to be edited into two.
	var half := half_extent()
	return absf(x - center_x_m) <= half.x + 1.0e-6 \
		and absf(z - center_z_m) <= half.y + 1.0e-6


## Half the width and half the length, and the ONE place either is halved. `contains()` used
## `width_m * 0.5` while `height_at()` used `absf(width_m) * 0.5`, which is two rules for one
## question: a negative width made a point outside every field and still gave it a height. Trivial
## today and exactly how the two answers drift apart tomorrow.
func half_extent() -> Vector2:
	return Vector2(absf(width_m), absf(length_m)) * 0.5


## The ground height in metres at a WORLD point. Relative to the site's own datum: a flat field is
## 0 everywhere, and `Site.elevation_m` is what turns that into a height above sea level.
##
## Pure. No caching, no memo, nothing read off the object that a previous call wrote — F4 calls
## this per gate per frame and a cache keyed on x alone would answer the previous z.
func height_at(x: float, z: float) -> float:
	# The boundary, not zero. See the header.
	var half := half_extent()
	var half_x := half.x
	var half_z := half.y
	var dx := clampf(x - center_x_m, -half_x, half_x)
	var dz := clampf(z - center_z_m, -half_z, half_z)

	match shape:
		SLOPE:
			return _slope_height(dx, dz, half_x, half_z)
		BOWL:
			return _bowl_height(dx, dz, half_x, half_z)
		BANKED:
			return _banked_height(dx, dz, half_x, half_z)
		_:
			# FLAT, ENCLOSURE, and anything unreadable. An enclosure's floor IS flat at zero: its
			# walls, roof and pillars are geometry for F5 and obstacles for F6, and treating a wall
			# height as a ground height would put the aircraft on the roof.
			return 0.0


## Rises linearly along `direction_deg` and is CONSTANT across it, from 0 at the low corner to
## `rise_m` at the high one — so the total rise across the field is `rise_m` whatever direction it
## runs in. 0° runs along +x; 90° runs along +z.
func _slope_height(dx: float, dz: float, half_x: float, half_z: float) -> float:
	var radians := deg_to_rad(_num("direction_deg"))
	var c := cos(radians)
	var s := sin(radians)
	# How far along the slope's own axis this point is. The distance ACROSS that axis is
	# deliberately absent from the arithmetic below — a slope is constant across itself, and a
	# cross-axis term leaking in here is invisible at 0° and wrong everywhere else.
	var along := dx * c + dz * s
	# Half the field's span along that axis — the projection of the rectangle onto it.
	var half_span := half_x * absf(c) + half_z * absf(s)
	if half_span <= 0.0:
		return 0.0
	return _num("rise_m") * (along / (2.0 * half_span) + 0.5)


## A pit: `−depth_m` at the centre, 0 at the rim, never above 0. Elliptical and quadratic, so it is
## smooth through the middle rather than a cone with a kink in it, and clamped to 0 outside the
## inscribed ellipse so the corners of the rectangle are ground rather than hills.
func _bowl_height(dx: float, dz: float, half_x: float, half_z: float) -> float:
	if half_x <= 0.0 or half_z <= 0.0:
		return 0.0
	var u := dx / half_x
	var v := dz / half_z
	var r := minf(sqrt(u * u + v * v), 1.0)
	return -_num("depth_m") * (1.0 - r * r)


## A wall of earth along ONE named edge: `bank_height_m` at the edge itself, falling to 0 over
## `bank_width_m`, and flat at 0 everywhere else. Quadratic, so it meets the flat ground without a
## crease at the toe of the bank.
func _banked_height(dx: float, dz: float, half_x: float, half_z: float) -> float:
	var edge := String(dims.get("bank_edge", DIM_DEFAULTS[BANKED]["bank_edge"]))
	var distance := 0.0
	match edge:
		SOUTH:
			distance = half_z - dz
		EAST:
			distance = half_x - dx
		WEST:
			distance = half_x + dx
		_:
			# NORTH, and anything unreadable. A bank has to be somewhere.
			distance = half_z + dz
	var bank_width := _num("bank_width_m")
	if bank_width <= 0.0 or distance >= bank_width:
		return 0.0
	var t := 1.0 - maxf(distance, 0.0) / bank_width
	return _num("bank_height_m") * t * t


## THE PREDICATE F9 READS, AND THE ONLY ONE IT READS. `shape == FLAT`. See the header for why it
## must not grow a second clause.
func is_flat_at_zero() -> bool:
	return shape == FLAT


## The terrain's contribution to a lap fingerprint: the shape's name and its rounded dimensions.
##
## The name alone is not enough. F9 hashes this into the best-lap fingerprint, and two slopes that
## differ only in their rise are two different courses to fly — a lap set on a 1 m rise must not be
## presented as a best on a 6 m one. Rounded to a centimetre so that a float read back from JSON
## does not re-hash a lap nobody touched.
func fingerprint_term() -> String:
	var parts: Array[String] = [String(shape),
		"%.2f" % width_m, "%.2f" % length_m,
		"%.2f" % center_x_m, "%.2f" % center_z_m]
	var keys: Array = DIM_DEFAULTS.get(shape, {}).keys()
	keys.sort()
	for key in keys:
		var value: Variant = dims.get(key, DIM_DEFAULTS[shape][key])
		if value is float or value is int:
			parts.append("%s=%.2f" % [key, float(value)])
		else:
			parts.append("%s=%s" % [key, str(value)])
	return "|".join(parts)


## A shape-specific number, falling back to this shape's default when the block does not carry it
## or carries something that is not a number.
func _num(key: String) -> float:
	var value: Variant = dims.get(key)
	if value is float or value is int:
		return float(value)
	var fallback: Variant = DIM_DEFAULTS.get(shape, {}).get(key, 0.0)
	return float(fallback) if fallback is float or fallback is int else 0.0


## Whether this is the untouched default: the shape, the size, the centre and the dims all as a
## `Terrain` arrives with nothing said about it. `Site` asks this rather than remembering whether
## the file it loaded had a block, because a remembered flag goes stale the moment a builder picks
## a shape on a record that never had one — which is precisely the regression this answers.
func is_default() -> bool:
	return shape == FLAT and _unknown_shape == "" and dims.is_empty() \
		and absf(width_m - DEFAULT_WIDTH_M) < 1.0e-9 \
		and absf(length_m - DEFAULT_LENGTH_M) < 1.0e-9 \
		and absf(center_x_m) < 1.0e-9 and absf(center_z_m) < 1.0e-9


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## A terrain from a block. ANYTHING UNREADABLE READS AS FLAT AND THE FILE STILL OPENS: a shape name
## from a newer build is a shape this version cannot draw, and refusing the file over it would cost
## the builder every site in it. The name itself survives in `_raw`, so saving does not destroy it.
static func from_data(data: Variant) -> Terrain:
	var out := Terrain.new()
	if not (data is Dictionary):
		return out
	var record: Dictionary = data
	out._raw = record.duplicate(true)

	var named := StringName(String(record.get("shape", FLAT)))
	if named in SHAPES:
		out.shape = named
	else:
		out.shape = FLAT
		out._unknown_shape = String(named)
	out.width_m = _read_number(record, "width_m", DEFAULT_WIDTH_M)
	out.length_m = _read_number(record, "length_m", DEFAULT_LENGTH_M)
	out.center_x_m = _read_number(record, "center_x_m", 0.0)
	out.center_z_m = _read_number(record, "center_z_m", 0.0)

	for key in record:
		if not (String(key) in BLOCK_KEYS):
			out.dims[key] = record[key]
	return out


static func _read_number(record: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = record.get(key)
	return float(value) if value is float or value is int else fallback


## The block as plain JSON values, built ON TOP of the record it was read from so that a load and a
## save with nothing touched produces the same bytes.
##
## THE HARD PART IS THE KEY THAT WAS NEVER THERE. F1's own byte-identity fixture carries a terrain
## block with `shape`, `width_m` and `length_m` and NO centre — a hand-written block, which is
## exactly the case this promise is about. Writing the centre back "because the class has one"
## grows that file by two keys its author never typed, which is the quiet-rewrite failure arriving
## through the writer. So a value that is absent from the record and still equal to the default the
## reader supplied for it stays absent; change it and it appears. An `int` 120 where this class
## holds 120.0 likewise stays `120`.
##
## A terrain built in CODE has no record behind it, and that one writes its whole block.
func to_data() -> Dictionary:
	var record := _raw.duplicate(true)
	var authored := _raw.is_empty()
	var written := String(shape)
	if shape == FLAT and _unknown_shape != "":
		written = _unknown_shape
	if not record.has("shape") or String(record["shape"]) != written:
		record["shape"] = written
	_put_number(record, "width_m", width_m, DEFAULT_WIDTH_M, authored)
	_put_number(record, "length_m", length_m, DEFAULT_LENGTH_M, authored)
	_put_number(record, "center_x_m", center_x_m, 0.0, authored)
	_put_number(record, "center_z_m", center_z_m, 0.0, authored)
	# EVERY dim, for every shape including flat. A flat block that arrived carrying a shape-specific
	# key keeps it, and a flat terrain a builder authored one on writes it: dropping dims because
	# "flat has none" is how a typed number, or a newer build's key, disappears on first save.
	for key in dims:
		var value: Variant = dims[key]
		if value is float or value is int:
			_put_number(record, String(key), float(value), NAN, true)
		elif not record.has(key) or record[key] != value:
			record[key] = value
	return record


## Writes `value` under `key`, unless the record already says the same number, or the key is absent
## and `value` is still the `implied` default the reader would have supplied for it. `force` is for
## a terrain built in code, which has no record to be faithful to.
func _put_number(record: Dictionary, key: String, value: float, implied: float,
		force: bool) -> void:
	var held: Variant = record.get(key)
	if (held is float or held is int) and absf(float(held) - value) < 1.0e-9:
		return
	if not force and not record.has(key) and is_finite(implied) \
			and absf(implied - value) < 1.0e-9:
		return
	record[key] = value
