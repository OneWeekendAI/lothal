class_name Callouts
extends RefCounted
## Callouts that explain why (PLAN Section 8), as pure data and pure arithmetic, so the table and
## the layout are testable headless.
##
## ## The table
##
## One row per callout: the pick address its pin sits on, the addresses that expand it (hover or
## selection), its name, ONE hand-written why-sentence, and the ONE number it drives, named as a
## `Build` method (`method`) and a format string. Nothing here types a number: `number_text` calls
## the method on the current Build, and a test calls the same method and compares the label.
## The confidence tag comes from the fitted part's catalogue source (PartFacts.confidence), or
## "computed" for a number Build works out itself.
##
## ## The layout
##
## `layout` takes generic ITEMS ({id, pin, size, priority, kind}), not callouts: anything that
## wants a pin on a part and a label beside the drone (Section 8's part-anchored warnings next)
## is fed through the same call and obeys the same rules:
## - a label sits beside the drone's silhouette, outside the silhouette's extent along its own rows
##   (left labels left of everything drawn in their rows, right labels right of it), so it can
##   never cover the drone;
## - it never covers an avoid rect (readouts, inspector, shelf, tool row, picker, buttons) or
##   another label, all grown by GAP;
## - labels on one side keep their pins' vertical order, and no leader crosses another leader or
##   passes through another label;
## - items are placed in priority order (1 first); one that cannot be placed is dropped, so a
##   crowded view loses its least important callouts first; at most `cap` are shown.

const MAX_SHOWN := 6
const GAP := 8.0             ## label to silhouette, to a UI rect, to another label (px)
const MARGIN := 16.0         ## label to the screen edge (px)
const LEADER_MIN := 18.0     ## shortest leader, where nothing drawn is in the label's rows (px)
const ROW_PX := 2.0          ## the silhouette profile's row height (px)
const SCAN_STEP := 3.0       ## label y candidates (px)

## Callouts, in priority order (also their pin numbers: row i is pin i + 1).
## method: a Build method returning the number; format: printf for it; confidence: the selection
## category whose catalogue source sets the tag, or "computed".
const TABLE := [
	{"id": "battery", "anchor": "part/battery", "match": ["part/battery"], "name": "Battery",
		"why": "Cells in series set the speed; capacity sets the time. It is also a third of your weight.",
		"method": "battery_mass_g", "format": "%.0f g pack", "confidence": "battery"},
	{"id": "motors", "anchor": "part/motor/FR", "match": ["part/motor/"], "name": "Motors",
		"why": "KV times the pack's volts sets how fast the props can spin; the current limit sets how hard.",
		"method": "max_rpm_at_nominal", "format": "%.0f rpm top", "confidence": "motor"},
	{"id": "props", "anchor": "part/prop/FL", "match": ["part/prop/"], "name": "Props",
		"why": "Diameter and pitch turn spin into thrust; a bigger bite pulls harder and draws more current.",
		"method": "max_total_thrust_n", "format": "%.1f N bench thrust", "confidence": "propeller"},
	{"id": "frame", "anchor": "frame/arm/BL", "match": ["frame/"], "name": "Frame",
		"why": "The arms carry every motor's thrust into one body; the pockets cut weight. Stiffness is not modelled.",
		"method": "frame_mass_g", "format": "%.0f g frame", "confidence": "frame"},
	{"id": "stack", "anchor": "part/stack", "match": ["part/stack"], "name": "FC / ESC stack",
		"why": "The ESC hands the pack's current to the motors; its rating caps how hard they can pull.",
		"method": "esc_max_amps", "format": "%.0f A continuous", "confidence": "esc"},
	{"id": "wiring", "anchor": "part/wires", "match": ["part/wires"], "name": "Wiring",
		"why": "Every amp the motors draw runs through these wires; thin wire costs volts and weighs little.",
		"method": "harness_mass_g", "format": "%.1f g harness", "confidence": "computed"},
]


static func entry(id: String) -> Dictionary:
	for e in TABLE:
		if String(e["id"]) == id:
			return e
	return {}


## The callout's number, from its named Build method. NAN without a build or a method.
static func value_of(e: Dictionary, b: Build) -> float:
	if b == null or not b.has_method(String(e["method"])):
		return NAN
	return float(b.call(String(e["method"])))


static func number_text(e: Dictionary, b: Build) -> String:
	var v := value_of(e, b)
	return "" if is_nan(v) else String(e["format"]) % v


static func confidence_of(e: Dictionary, session: DesignSession, catalog: PartsCatalog) -> String:
	var cat := String(e["confidence"])
	if cat == "computed":
		return "computed"
	if cat == "frame" and not session.frame_edit(catalog).is_empty():
		return "computed from your edit"
	var part := catalog.get_part(String(session.selection.get(cat, "")))
	return PartFacts.confidence(String(part.get("source", "")))


## Whether hovering or selecting `address` expands callout `e`.
static func matches(e: Dictionary, address: String) -> bool:
	if address == "":
		return false
	for p in e["match"]:
		if address == String(p) or (String(p).ends_with("/") and address.begins_with(String(p))):
			return true
	return false


# ---------------------------------------------------------------------------
# Silhouette
# ---------------------------------------------------------------------------

## The convex hull points of a mesh, in its own space (QuickHull through the engine).
static func hull_points(mesh: Mesh) -> PackedVector3Array:
	var shape := mesh.create_convex_shape(true, false)
	return shape.points if shape != null else PackedVector3Array()


## Each hull (stage-space points) projected through `view`: one convex polygon (px, y down) per mesh.
## A point behind the camera drops its mesh (it cannot be outlined on screen).
static func silhouette(view: CameraRig, hulls: Array, size: Vector2) -> Array:
	var out: Array = []
	var b := view.basis()
	var eye := view.position()
	for pts in hulls:
		var flat := PackedVector2Array()
		var behind := false
		for p in (pts as PackedVector3Array):
			if (b.inverse() * (p - eye)).z >= 0.0:
				behind = true
				break
			flat.append(PickerPlace.to_px(view.project(p), size))
		if behind or flat.size() < 3:
			continue
		out.append(Geometry2D.convex_hull(flat))
	return out


## Per screen row (ROW_PX tall): the leftmost and rightmost x of anything drawn in it (INF / -INF
## for an empty row). Exact for polygons: within a band, a polygon's extreme x lies on its boundary.
static func row_profile(polys: Array, size: Vector2) -> Dictionary:
	var rows := int(ceil(size.y / ROW_PX)) + 1
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(rows)
	hi.resize(rows)
	lo.fill(INF)
	hi.fill(-INF)
	for poly in polys:
		var n := (poly as PackedVector2Array).size()
		for i in n:
			var a: Vector2 = poly[i]
			var c: Vector2 = poly[(i + 1) % n]
			var y0 := minf(a.y, c.y)
			var y1 := maxf(a.y, c.y)
			var r0 := clampi(int(floor(y0 / ROW_PX)), 0, rows - 1)
			var r1 := clampi(int(floor(y1 / ROW_PX)), 0, rows - 1)
			if y1 < 0.0 or y0 > size.y:
				continue
			for r in range(r0, r1 + 1):
				var b0 := maxf(y0, r * ROW_PX)
				var b1 := minf(y1, (r + 1) * ROW_PX)
				var xa: float
				var xb: float
				if is_equal_approx(a.y, c.y):
					xa = a.x
					xb = c.x
				else:
					xa = lerpf(a.x, c.x, (b0 - a.y) / (c.y - a.y))
					xb = lerpf(a.x, c.x, (b1 - a.y) / (c.y - a.y))
				lo[r] = minf(lo[r], minf(xa, xb))
				hi[r] = maxf(hi[r], maxf(xa, xb))
	return {"lo": lo, "hi": hi}


## The silhouette's extent over the rows [y0, y1]: Vector2(leftmost, rightmost).
static func band_extent(profile: Dictionary, y0: float, y1: float) -> Vector2:
	var lo: PackedFloat32Array = profile["lo"]
	var hi: PackedFloat32Array = profile["hi"]
	var r0 := clampi(int(floor(y0 / ROW_PX)), 0, lo.size() - 1)
	var r1 := clampi(int(floor(y1 / ROW_PX)), 0, lo.size() - 1)
	var out := Vector2(INF, -INF)
	for r in range(r0, r1 + 1):
		out.x = minf(out.x, lo[r])
		out.y = maxf(out.y, hi[r])
	return out


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

## Places `items` ([{id, pin: Vector2 px, size: Vector2, priority: int, kind?}]) beside the
## silhouette `polys`, clear of `avoid` (Rect2 px) and each other. Returns the placed ones:
## [{id, kind, pin, rect, side ("left"|"right"), end (the leader's label end)}], in priority order.
static func layout(items: Array, polys: Array, avoid: Array, size: Vector2, cap: int = MAX_SHOWN) -> Array:
	var profile := row_profile(polys, size)
	var mid := 0.5 * size.x
	var ext := Vector2(INF, -INF)
	for poly in polys:
		for p in (poly as PackedVector2Array):
			ext.x = minf(ext.x, p.x)
			ext.y = maxf(ext.y, p.x)
	if ext.x < ext.y:
		mid = 0.5 * (ext.x + ext.y)
	var pool := items.filter(func(it):
		var p: Vector2 = it["pin"]
		return p.x >= 0.0 and p.y >= 0.0 and p.x <= size.x and p.y <= size.y)
	pool.sort_custom(func(a, b): return int(a["priority"]) < int(b["priority"]))
	var placed: Array = []
	for it in pool:
		if placed.size() >= cap:
			break
		var pin: Vector2 = it["pin"]
		var first := "left" if pin.x < mid else "right"
		var second := "right" if first == "left" else "left"
		var got := _place(it, first, placed, profile, avoid, size)
		if got.is_empty():
			got = _place(it, second, placed, profile, avoid, size)
		if not got.is_empty():
			placed.append(got)
	return placed


static func _place(it: Dictionary, side: String, placed: Array, profile: Dictionary, avoid: Array,
		size: Vector2) -> Dictionary:
	var pin: Vector2 = it["pin"]
	var sz: Vector2 = it["size"]
	# Same-side neighbours by pin y: this label must sit between their labels.
	var top := MARGIN
	var bottom := size.y - MARGIN
	for q in placed:
		if q["side"] != side:
			continue
		var qp: Vector2 = q["pin"]
		var qr: Rect2 = q["rect"]
		if qp.y <= pin.y:
			top = maxf(top, qr.end.y + GAP)
		else:
			bottom = minf(bottom, qr.position.y - GAP)
	if bottom - top < sz.y:
		return {}
	var want := pin.y - 0.5 * sz.y
	var ys: Array = []
	var y := top
	while y + sz.y <= bottom:
		ys.append(y)
		y += SCAN_STEP
	ys.append(bottom - sz.y)
	ys.sort_custom(func(a, b): return absf(a - want) < absf(b - want))
	for cy in ys:
		var band := band_extent(profile, cy - GAP, cy + sz.y + GAP)
		var r: Rect2
		if side == "left":
			var right := pin.x - LEADER_MIN
			if band.x < INF:
				right = minf(right, band.x - GAP)
			r = Rect2(right - sz.x, cy, sz.x, sz.y)
		else:
			var left := pin.x + LEADER_MIN
			if band.y > -INF:
				left = maxf(left, band.y + GAP)
			r = Rect2(left, cy, sz.x, sz.y)
		if r.position.x < MARGIN or r.end.x > size.x - MARGIN:
			continue
		var end := Vector2(r.end.x if side == "left" else r.position.x, r.get_center().y)
		if _clear(r, pin, end, placed, avoid):
			return {"id": it["id"], "kind": it.get("kind", "callout"), "pin": pin, "rect": r,
				"side": side, "end": end}
	return {}


static func _clear(r: Rect2, pin: Vector2, end: Vector2, placed: Array, avoid: Array) -> bool:
	var grown := r.grow(GAP)
	for a in avoid:
		if grown.intersects(a as Rect2):
			return false
	for q in placed:
		var qr: Rect2 = q["rect"]
		if grown.intersects(qr):
			return false
		if leaders_cross(pin, end, q["pin"], q["end"]):
			return false
		if segment_hits_rect(pin, end, qr) or segment_hits_rect(q["pin"], q["end"], r):
			return false
	return true


## Whether two leaders cross (sharing an end point does not count).
static func leaders_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var x = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if x == null:
		return false
	var p: Vector2 = x
	for e in [a0, a1]:
		if p.distance_to(e) < 0.5 and (p.distance_to(b0) < 0.5 or p.distance_to(b1) < 0.5):
			return false
	return true


static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false
