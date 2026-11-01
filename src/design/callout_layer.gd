class_name CalloutLayer
extends Control
## Draws the Design Space's callouts (PLAN Section 8): a numbered pin on each part, a thin leader,
## and a label beside the drone. Placement is `Callouts.layout`; this node only measures labels and
## draws what it is given. Everything is drawn in `_draw` with LothalTheme.draw_font(), and the
## very strings drawn are kept in `shown` so tests read the label text that is on screen.
##
## The look lives here (constants + `_draw`); Section 8 Agent B owns it.

const NAME_SIZE := LothalTheme.FONT_SIZE_BODY
const BODY_SIZE := LothalTheme.FONT_SIZE_SMALL
const PAD := Vector2(8, 5)
const BADGE_R := 7.0             ## the number disc, on the pin and in the label
const EXPANDED_W := 236.0        ## an expanded label's width
const LINE_GAP := 3.0
const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const LEADER_INK := Color(0.93, 0.93, 0.93, 0.55)
const LABEL_BG := Color(0.04, 0.04, 0.045, 0.82)
const DISC_BG := Color(0.04, 0.04, 0.045, 0.9)
## Every leader, and a badge's ring, is a hairline.
const LEADER_W := 1.0
## The number inside a pin's disc.
const BADGE_SIZE := LothalTheme.FONT_SIZE_SMALL
## Discs closer than this (edge to edge) are nudged apart when drawn.
const DISC_GAP := 3.0
## Warning pins (kind "warning"): the ONE accent; a caution is an outline dot, a blocking one solid.
const WARN_INK := LothalTheme.WARNING
const DOT_R := 5.0
const RING_W := 1.5
## The dark rim round a solid (blocking) dot.
const KEYLINE_W := 1.5
const WARN_LEADER_INK := Color(LothalTheme.WARNING, 0.7)
## A click this close to a warning pin's dot opens it (px).
const DOT_HIT := DOT_R + 4.0

## What is drawn: [{id, number, name, lines: [String], expanded, pin, rect, side, end, kind}];
## a warning (kind "warning") also has severity ("caution"|"blocking"), solid, tint, anchor.
var shown: Array = []


func _init() -> void:
	name = "Callouts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## The label's size for `title` (collapsed) or `title` + `body` lines (expanded).
static func label_size(title: String, body: Array, expanded: bool) -> Vector2:
	var f := LothalTheme.draw_font()
	var name_w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	var head_h := maxf(f.get_height(NAME_SIZE), 2.0 * BADGE_R)
	if not expanded:
		return Vector2(PAD.x * 2.0 + 2.0 * BADGE_R + 6.0 + name_w, PAD.y * 2.0 + head_h)
	var inner := EXPANDED_W - 2.0 * PAD.x
	var h := head_h
	for line in body:
		h += LINE_GAP + f.get_multiline_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, inner, BODY_SIZE).y
	return Vector2(maxf(EXPANDED_W, PAD.x * 2.0 + 2.0 * BADGE_R + 6.0 + name_w), PAD.y * 2.0 + h)


func show_items(items: Array) -> void:
	shown = items
	queue_redraw()


func clear() -> void:
	if not shown.is_empty():
		shown = []
		queue_redraw()


## The id of the label under `px` (local), "" for none.
func at(px: Vector2) -> String:
	for s in shown:
		if (s["rect"] as Rect2).has_point(px):
			return String(s["id"])
	return ""


## The warning pin whose label or dot is under `px` (local), "" for none.
func warning_at(px: Vector2) -> String:
	for s in shown:
		if String(s.get("kind", "")) != "warning":
			continue
		if (s["rect"] as Rect2).has_point(px) or (s["pin"] as Vector2).distance_to(px) <= DOT_HIT:
			return String(s["id"])
	var discs := disc_centres(shown)
	for i in shown.size():
		if String(shown[i].get("kind", "")) == "warning" and (discs[i] as Vector2).distance_to(px) <= DOT_HIT:
			return String(shown[i]["id"])
	return ""


func item(id: String) -> Dictionary:
	for s in shown:
		if String(s["id"]) == id:
			return s
	return {}


func _draw() -> void:
	for o in draw_ops():
		match String(o["op"]):
			"line":
				draw_line(o["a"], o["b"], o["color"], o["width"])
			"disc":
				draw_circle(o["c"], o["r"], o["color"])
			"ring":
				draw_arc(o["c"], o["r"], 0.0, TAU, 24, o["color"], o["width"], true)
			"rect":
				draw_rect(o["rect"], o["color"])
			"text":
				draw_multiline_string(LothalTheme.draw_font(), o["pos"], o["text"], HORIZONTAL_ALIGNMENT_LEFT,
					o["width"], o["size"], -1, o["color"])


## Where each pin's disc is drawn: its pin, nudged sideways to its leader clear of the discs drawn
## before it (two parts whose centres project together would otherwise print one disc over the
## other, and the later leader would run through the earlier disc). The pin itself (what tests and layout use) never moves; only the disc does,
## and its leader starts from it.
static func disc_centres(items: Array) -> Array:
	var out: Array = []
	var radii: Array = []
	var ends: Array = []
	for s in items:
		var r := DOT_R if String(s.get("kind", "")) == "warning" else BADGE_R
		var c: Vector2 = s["pin"]
		var end: Vector2 = s["end"]
		for _pass in 6:
			var moved := false
			for j in out.size():
				var o: Vector2 = out[j]
				var need: float = r + float(radii[j]) + DISC_GAP
				var lead := end - c
				var ld := lead.normalized()
				var side := ld.orthogonal()
				if side == Vector2.ZERO:
					side = Vector2.UP
				if (c - o).dot(side) < 0.0:
					side = -side
				var t := (o - c).dot(ld)
				var through := t > 0.0 and t < lead.length() and (c - o).dot(side) < float(radii[j]) + 1.0
				if through:
					# Sideways to its own leader, away from the other disc: clear of that disc,
					# and the leader runs past it rather than through it.
					c += side * (need - (c - o).dot(side))
					moved = true
					continue
				if c.distance_to(o) < need - 0.01:
					# Only touching: straight away from the other disc, the least move.
					c = o + ((c - o).normalized() if c.distance_to(o) > 0.01 else side) * need
					moved = true
					continue
				# An earlier leader running through this disc: step off that leader.
				var q := Geometry2D.get_closest_point_to_segment(c, o, ends[j])
				if q.distance_to(c) < r + 1.0:
					var away := (c - q).normalized() if q.distance_to(c) > 0.01 else ((ends[j] as Vector2) - o).normalized().orthogonal()
					c = q + away * (r + 1.0 + DISC_GAP)
					moved = true
			if not moved:
				break
		out.append(c)
		radii.append(r)
		ends.append(end)
	return out


## Everything `_draw` paints, in order, as plain data (tests read it):
## {op: "line", a, b, color, width} / {op: "disc", c, r, color} / {op: "ring", c, r, color, width}
## / {op: "rect", rect, color} / {op: "text", pos, text, size, width, color, role}.
## Leaders first, then the discs, then the labels over them. Monochrome; WARN_INK only on a
## warning's dot, leader and tag.
func draw_ops() -> Array:
	var f := LothalTheme.draw_font()
	var ops: Array = []
	var discs := disc_centres(shown)
	for i in shown.size():
		var s: Dictionary = shown[i]
		var c: Vector2 = discs[i]
		var end: Vector2 = s["end"]
		if String(s.get("kind", "")) == "warning":
			ops.append({"op": "line", "a": c + (end - c).normalized() * DOT_R, "b": end, "color": WARN_LEADER_INK, "width": LEADER_W})
		else:
			ops.append({"op": "line", "a": c + (end - c).normalized() * BADGE_R, "b": end, "color": LEADER_INK, "width": LEADER_W})
	for i in shown.size():
		var s: Dictionary = shown[i]
		if String(s.get("kind", "")) == "warning":
			_dot_ops(ops, discs[i], bool(s["solid"]))
		else:
			_badge_ops(ops, f, discs[i], int(s["number"]))
	for s in shown:
		var r: Rect2 = s["rect"]
		ops.append({"op": "rect", "rect": r, "color": LABEL_BG})
		var x := r.position.x + PAD.x
		var head_h := maxf(f.get_height(NAME_SIZE), 2.0 * BADGE_R)
		var mid := Vector2(x + BADGE_R, r.position.y + PAD.y + head_h * 0.5)
		var warn := String(s.get("kind", "")) == "warning"
		if warn:
			_dot_ops(ops, mid, bool(s["solid"]))
		else:
			_badge_ops(ops, f, mid, int(s["number"]))
		ops.append({"op": "text", "pos": Vector2(x + 2.0 * BADGE_R + 6.0, mid.y + f.get_ascent(NAME_SIZE) * 0.5 - 1.0),
			"text": String(s["name"]), "size": NAME_SIZE, "width": -1.0, "color": WARN_INK if warn else INK, "role": "name"})
		if not s["expanded"]:
			continue
		var y := r.position.y + PAD.y + head_h
		var inner := r.size.x - 2.0 * PAD.x
		var lines: Array = s["lines"]
		for k in lines.size():
			var line := String(lines[k])
			y += LINE_GAP
			ops.append({"op": "text", "pos": Vector2(x, y + f.get_ascent(BODY_SIZE)), "text": line, "size": BODY_SIZE,
				"width": inner, "color": INK if k == lines.size() - 1 else INK_MUTED, "role": "number" if k == lines.size() - 1 else "why"})
			y += f.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner, BODY_SIZE).y
	return ops


## A warning's dot: solid for blocking, an outline ring for a caution.
static func _dot_ops(ops: Array, c: Vector2, solid: bool) -> void:
	if solid:
		# A dark keyline first: the dot often sits on its own amber-tinted part.
		ops.append({"op": "disc", "c": c, "r": DOT_R + KEYLINE_W, "color": DISC_BG})
		ops.append({"op": "disc", "c": c, "r": DOT_R, "color": WARN_INK})
	else:
		ops.append({"op": "disc", "c": c, "r": DOT_R, "color": DISC_BG})
		ops.append({"op": "ring", "c": c, "r": DOT_R, "color": WARN_INK, "width": RING_W})


static func _badge_ops(ops: Array, f: Font, c: Vector2, n: int) -> void:
	ops.append({"op": "disc", "c": c, "r": BADGE_R, "color": DISC_BG})
	ops.append({"op": "ring", "c": c, "r": BADGE_R, "color": INK, "width": LEADER_W})
	var t := str(n)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE).x
	ops.append({"op": "text", "pos": c + Vector2(-0.5 * w, f.get_ascent(BADGE_SIZE) * 0.5 - 1.0), "text": t,
		"size": BADGE_SIZE, "width": -1.0, "color": INK, "role": "badge"})
