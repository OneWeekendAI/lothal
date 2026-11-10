class_name WorldEditModel
extends RefCounted
## L2.1-L2.3: the pure-data edit model behind the world editor. Wraps a DUPLICATE of a World (the original is never mutated),
## applies vertex / obstacle / preset / sun / wind edits, and reports a source tag for every editable field (P3).
##
## Tags live in the World's own `sources` so they save and load with it. A field starts with the tag the world gave it
## (obstacle heights and radii start "estimated": a guess with an editable field). Once the user sets it, its tag is "user" and
## `default_tag()` keeps what it was before, so the original provenance is not lost. Paths: "field.polygon", "wind.speed",
## "wind.from", "wind.gust", "sun.time" (the UTC stamp), "sun.origin" (lat/lon), "obstacle.<i>.<key>" (key = x, z or a dims key).
## Polygon vertices are Vector2(lat, lon); a Vector2 holds 32 bits, so edits through it resolve to about a metre (the
## stored polygon itself is 64-bit).

const TAG_USER := "user"
const ALIASES := {"sun.time": "time", "sun.origin": "origin"}

var _world: World


static func duplicate_world(w: World) -> World:
	return World.from_data(JSON.parse_string(w.to_json()))


func _init(world: World) -> void:
	_world = duplicate_world(world)


## The edited World (a copy: later edits to the model do not change it).
func result() -> World:
	return duplicate_world(_world)


# ---- tags
func field_tag(path: String) -> String:
	var s: Variant = _world.sources.get(ALIASES.get(path, path))
	return String((s as Dictionary).get("tag", "")) if s is Dictionary else ""


## The tag a field had before the user touched it (equals field_tag until then).
func default_tag(path: String) -> String:
	var s: Variant = _world.sources.get(ALIASES.get(path, path))
	if not (s is Dictionary):
		return ""
	return String((s as Dictionary).get("default_tag", (s as Dictionary).get("tag", "")))


func _mark_user(path: String) -> void:
	var key: String = ALIASES.get(path, path)
	var prev: Variant = _world.sources.get(key)
	var d: Dictionary = (prev as Dictionary).duplicate(true) if prev is Dictionary else {}
	var base := String(d.get("default_tag", d.get("tag", "estimated")))
	if base == TAG_USER or base == "":
		base = "estimated"
	d["default_tag"] = base
	d["tag"] = TAG_USER
	d["note"] = "Set by the user in the world editor (was %s: %s)" % [base, String(d.get("note", "no note"))]
	_world.sources[key] = d


func _mark_estimated(path: String, note: String) -> void:
	_world.sources[path] = {"tag": "estimated", "note": note}


# ---- polygon
func vertex_count() -> int:
	return floori(_world.polygon.size() * 0.5)


func add_vertex(index: int, v: Vector2) -> bool:
	var n := vertex_count()
	if index < 0 or index > n:
		return false
	_world.polygon.insert(2 * index, v.y)
	_world.polygon.insert(2 * index, v.x)
	_mark_user("field.polygon")
	return true


func move_vertex(i: int, v: Vector2) -> bool:
	if i < 0 or i >= vertex_count():
		return false
	_world.polygon[2 * i] = v.x
	_world.polygon[2 * i + 1] = v.y
	_mark_user("field.polygon")
	return true


## Refuses (false) when the polygon would drop below 3 vertices.
func delete_vertex(i: int) -> bool:
	if i < 0 or i >= vertex_count() or vertex_count() <= 3:
		return false
	_world.polygon.remove_at(2 * i + 1)
	_world.polygon.remove_at(2 * i)
	_mark_user("field.polygon")
	return true


# ---- obstacles
## `rec` is an Obstacle record: {kind, x, z, dims}. False if the kind is not recognised.
func add_obstacle(rec: Dictionary) -> bool:
	var o := Obstacle.from_data(rec, null)
	if o == null:
		return false
	_world.obstacles.append(o)
	var i := _world.obstacles.size() - 1
	for k in ["x", "z"]:
		_mark_estimated("obstacle.%d.%s" % [i, k], "Placed by the user; the position is a guess until surveyed.")
	for k in o.dims:
		_mark_estimated("obstacle.%d.%s" % [i, k], "Obstacle size is an estimate until measured; edit it.")
	return true


func remove_obstacle(i: int) -> bool:
	if i < 0 or i >= _world.obstacles.size():
		return false
	var keep: Dictionary = {}
	for k in _world.sources:
		var parts := String(k).split(".")
		if parts.size() >= 3 and parts[0] == "obstacle" and parts[1].is_valid_int():
			var n := int(parts[1])
			if n == i:
				continue
			if n > i:
				parts[1] = str(n - 1)
				keep[".".join(parts)] = _world.sources[k]
				continue
		keep[k] = _world.sources[k]
	_world.sources = keep
	_world.obstacles.remove_at(i)
	return true


func set_obstacle_field(i: int, key: String, value: float) -> bool:
	if i < 0 or i >= _world.obstacles.size():
		return false
	var o := _world.obstacles[i]
	if key == "x":
		o.position.x = value
	elif key == "z":
		o.position.z = value
	else:
		o.dims[key] = value
	_mark_user("obstacle.%d.%s" % [i, key])
	return true


# ---- preset / sun / wind
## Replaces the whole world with the preset's content (nothing of the old world, including user tags, is kept).
func set_preset(id: String) -> bool:
	var p := WorldPresets.by_id(id)
	if p == null:
		return false
	_world = duplicate_world(p)
	return true


## Sun position is computed from the time and the origin (World.sun, NOAA algorithm); the inputs are what the user sets.
func set_sun(utc: String, lat: float, lon: float) -> void:
	_world.utc = utc
	_world.origin_lat = lat
	_world.origin_lon = lon
	_world.location_placeholder = false
	_mark_user("sun.time")
	_mark_user("sun.origin")


func set_wind(speed_mps: float, from_deg: float, gustiness_mps: float) -> void:
	_world.wind_speed_mps = speed_mps
	_world.wind_from_deg = from_deg
	_world.gustiness_mps = gustiness_mps
	_mark_user("wind.speed")
	_mark_user("wind.from")
	_mark_user("wind.gust")
