class_name DesignSpace
extends Control
## The Design Space stage: the chosen class's model on the picker's dark studio, a free camera, and
## a calm side panel of live readouts. Nothing here computes a physical number: the panel reads the
## session's `Build` (DesignSession.readouts) every time the selection changes.
##
## Camera: drag orbits; shift+drag, right drag or middle drag pans; wheel or pinch zooms toward the
## cursor; trackpad two-finger scroll orbits; double-click a part frames it; H (or the Home button)
## eases back to the isometric view; Esc clears the selection, or leaves when nothing is selected.
##
## Picking (PLAN Section 2): a ray against the drawn triangles of every part and frame region, and
## against the export's hole and pocket proxies, through `PickRegistry`. Hover outlines the piece and
## names it; a click (press and release without dragging) selects it and the inspector shows its
## numbers (`PartFacts`); a click on nothing clears. Double-click frames what it hit.

signal dismissed
signal back_requested
## "Fly it" and "Field": the shell opens the sim / Field room on this design's build.
signal fly_requested
signal field_requested
## The Mission button: the shell opens a MissionPicker for this design.
signal mission_requested
signal room_requested(room_id: String)

const PANEL_FADE_S := 0.2

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const STAGE_BG := Color(0.035, 0.035, 0.038)
const ORBIT_RAD_PER_PX := 0.006
const WHEEL_ZOOM := 0.88
const PINCH_GAIN := 1.0
## A press that moves further than this before release is a drag, not a click.
const CLICK_SLOP_PX := 4.0
## A second click this close (NDC units) to the last, on the same ray, steps one deeper.
const CLICK_AGAIN_NDC := 0.01
## Hover is a clear light grey, selection white: monochrome, and both read against carbon and the
## dark anodised bells (0.58 at 1.5 px was too faint on a motor).
const HOVER_INK := Color(0.80, 0.80, 0.80)
const SELECT_INK := Color(0.96, 0.96, 0.96)
const HOVER_WIDTH_PX := 2.0
const SELECT_WIDTH_PX := 2.5
## The one accent: warnings and refusal reasons.
const WARN_INK := LothalTheme.WARNING
## The blocking tint's opacity over the part (the carbon weave still reads through it).
const TINT_ALPHA := 0.2
## Two warning pins on one part sit this far apart (px).
const WARN_PIN_STEP := 24.0
## The readouts column: narrow, and flush to the right edge (the stage gets the room).
const PANEL_W := 212.0
const PANEL_EDGE := 12.0
## Readout delta bars: a delta of this size fills half the track.
const DELTA_SCALE := {"auw_g": 150.0, "thrust_to_weight": 4.0, "hover_throttle": 0.2,
	"flight_time_min": 3.0, "top_speed_kmh": 40.0}
const DELTA_TRACK_W := 56.0
## The labels and callouts over the drone fade out after this long without mouse or key input,
## taking LABEL_FADE_S to go and to come back.
const IDLE_HIDE_S := 4.0
const LABEL_FADE_S := 0.3
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;
uniform vec4 ink : source_color = vec4(1.0);
uniform float width_px = 2.0;
void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 off = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	if (length(off) > 1e-6) {
		clip.xy += normalize(off) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}
void fragment() {
	ALBEDO = ink.rgb;
}
"""

var session: DesignSession
var rig: CameraRig
var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var title_label: Label
var home_button: Button
var labels_button: Button            ## the eye: hides or shows every label and callout over the drone
## The eye hides (true) or shows the labels; it beats idle. `label_alpha` is what is drawn now.
var labels_hidden := false
var label_alpha := 1.0
var _drawn_label_alpha := -1.0
## How many times the eye button was asked to redraw (tests read this).
var redraw_requests := 0
var _idle_s := 0.0
var back_button: Button
var panel: VBoxContainer
var panel_alpha := 1.0
var value_labels: Dictionary = {}
var picks := PickRegistry.new()
## The address under the pointer and the selected one ("" for none).
var hovered := ""
var selected := ""
var hover_label: Label
var inspector: VBoxContainer

var _catalog: PartsCatalog
var _stage: Node3D
var _tex: TextureRect
var _drag := ""
var _model_path := ""
var _press_pos := Vector2.ZERO
var _press_moved := false
var _hover_mat: ShaderMaterial
var _select_mat: ShaderMaterial
var _fill_mats := {}
var _marked: Array = []
## The meshes wearing the blocking tint (`tinted_parts()`), and the tint materials by the outline
## they carry as next pass (key 0 = none).
var _tinted: Array = []
var _tint_mats := {}
var _pad_marker: MeshInstance3D
var _last_click_ndc := Vector2(INF, INF)
var _last_click_order: Array = []
## Click to swap (Section 3): the pick slot of the selected part ("" when none); its categories are
## the ones the shelf swaps in place.
var swap_slot := ""
## Section 8 warnings on the parts (WarningPins): the pins of the drone on screen, the panel's count,
## the readout marks, and which pins the inspector is showing.
var warning_pins: Array = []
var issues_label: Label
var charge_chip: ChargeChip
## A battery card clicked on the shelf; it is the one the chip shows until the build changes.
var _clicked_battery := ""
var gauges: Dictionary = {}          ## readout key -> its ReadoutGauge (fill = where the value sits in its range)
var mark_buttons: Dictionary = {}    ## readout key -> its mark Button ("\u25b2 8.0 in air")
var warning_open: Array = []          ## pin ids the inspector shows ([] for none)
var _refusal := {}                    ## the last refused drop's pin, until the next change or drag
var delta_labels: Dictionary = {}
var delta_bars: Dictionary = {}
var previewing := {}
var _motor_hulls := {}
## The drawn parts (the class seed the model was built for) and each swappable node as drawn.
var _drawn_selection: Dictionary = {}
var _look_base: Dictionary = {}
var _look_nodes: Dictionary = {}
var _pack_label: Label3D
var _plain_wrap: StandardMaterial3D
## Frame edits (Section 4): the tool row, the active tool, and what the plates were as drawn.
var tool_row: FrameToolRow
var file_bar: DesignFileBar
## A drawer another layer shows at the left (the shell's Mission picker): callouts keep clear of it.
var side_drawer: DsDrawer
## The name this design is saved under ("" until first saved or opened).
var design_name := ""
## Where the design came from (DsIdentity.SOURCES): the class seed until opened from or saved to a design file.
var design_source := "class seed"
## The identity sheet (B5), a left drawer opened by the chip in the top bar.
var identity_sheet: DsDrawer
## "", "drill", "pocket" or "fill".
var frame_tool := ""
var drill_d_mm: float = FrameTools.DRILL_SIZES["M3"]
## "rect" or "slot".
var pocket_shape := "rect"
const POCKET_SLOT_WIDTH_MM := 4.0
## The last frame op's verdict ({} before any), for tests and the refusal line.
var last_frame_verdict: Dictionary = {}
var _doc_root: Node3D
var _frame_orig: AirframeDocument
var _glb_meshes := {}
var _glb_proxies := {}
var _made_proxies := {}
## Section 6: every plate is drawn by FrameGen. The catalog (unedited) mesh per plate node name, which
## plates are edited, the cut-edge material (surface 1), and the instanced hardware holder.
var _gen_meshes := {}
var _plate_edited := {}
var edge_material: Material
## Section 6: the carbon twill on every generated plate face (FrameLook.face_material).
var face_material: Material
var hardware_root: Node3D
var _pocket_from := Vector2.ZERO

## Section 5: the shelf, the drag, the drop.
var shelf: PartsShelf
var drop_label: Label
## "" | "shelf" (a part from the shelf) | "off" (a mounted part being dragged off the drone).
var drag_kind := ""
var drag_part := ""
var drag_address := ""
var drag_verdict := {}
var _mount_map := {}
var _ghosts: Array = []
var _ghost_mat: StandardMaterial3D
var _lit: Array = []
var _shelf_verdicts := {}

# Section 8: callouts that explain why (Callouts = table + layout; CalloutLayer draws).
var callouts: CalloutLayer
var callout_focus := ""          ## the callout whose label the pointer is on
var _callout_hulls: Array = []   ## per drawn mesh, its convex hull points in stage space
var _hull_cache := {}            ## mesh RID -> hull points in the mesh's own space
var _callout_numbers := {}       ## callout id -> {number, confidence}; {} without a build
var _callout_inputs: Array = []  ## everything the last layout read, to skip an unchanged frame
var _callout_version := 0        ## bumped when the numbers or the drawn meshes change


func _init(p_session: DesignSession, p_catalog: PartsCatalog = null) -> void:
	session = p_session
	session.changed.connect(_sync)
	_catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	name = "DesignSpace"
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_stage()
	_build_panel()
	_build_inspector()
	_build_frame_tools()
	_build_shelf()
	_build_file_bar()
	refresh()
	apply_look()
	refresh_shelf()


# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------

## Sets a part with no fit check and no history, and refreshes. The test seam for "the build
## changed"; the user's path is `choose`.
func set_part(category: String, part_id: String) -> bool:
	return session.set_part(category, part_id)


## Click to swap: fits `part_id` as `category` through the session (refused for a hard misfit,
## leaving everything as it was). Returns the verdict {ok, reason, ...}.
func choose(category: String, part_id: String) -> Dictionary:
	var rev := session.revision
	var verdict := session.swap(_catalog, category, part_id)
	# Choosing the part already fitted changes nothing, so the session says nothing; the stage is still re-read.
	if verdict["ok"] and session.revision == rev:
		_after_change()
	return verdict


func undo() -> bool:
	return session.undo()


func redo() -> bool:
	return session.redo()


## Everything a changed selection moves: readouts, the drawn parts, pick shapes, picker, inspector.
## The session changed (by any path): re-read everything it feeds. A no-op when `_after_change` already ran
## for this revision, so a change through our own methods does not redraw twice.
func _sync() -> void:
	if session.revision != _synced_revision:
		_after_change()


var _synced_revision := -1


func _after_change() -> void:
	_synced_revision = session.revision
	refresh_identity()
	_refusal = {}
	_clicked_battery = ""
	clear_preview()
	refresh()
	regenerate_frame()
	apply_look()
	if selected != "" and not picks.addresses().has(selected):
		selected = _plate_address_of(selected)
	_update_tool_row()
	if selected != "":
		_fill_inspector()
	refresh_shelf()


## The identity of what is on the stage (DsIdentity.describe with this design's name and source).
func identity() -> Dictionary:
	return DsIdentity.describe(session, _catalog, design_name, design_source)


## Rewrites the chip and the sheet from `identity()`.
func refresh_identity() -> void:
	if file_bar == null or identity_sheet == null:
		return
	var info := identity()
	file_bar.show_identity(String(info["chip"]))
	file_bar.identity_button.tooltip_text = String(info.get("text", ""))
	DsIdentity.fill(identity_sheet, info)


## The chip: opens the sheet (closing the Parts list and any other left drawer), or closes it.
func toggle_identity() -> void:
	if identity_sheet.visible:
		identity_sheet.hide()
		return
	shelf.set_open(false)
	if side_drawer != null and is_instance_valid(side_drawer) and side_drawer != identity_sheet:
		side_drawer.hide()
	side_drawer = identity_sheet
	refresh_identity()
	identity_sheet.show()


## Re-reads the session's build into the panel.
func refresh() -> void:
	var r := session.readouts(_catalog)
	var entry := DroneClass.by_id(session.drone_class)
	title_label.text = String(entry.get("name", "Drone"))
	var keys := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
	for key in keys:
		(value_labels[key] as Label).text = format_readout(key, r)
		(gauges[key] as ReadoutGauge).set_value(r.get(key, null))
	var fs := session.flight_state(_catalog)
	var b := session.build(_catalog)
	_refresh_warnings(b, fs)
	_refresh_callout_numbers(b)


## The warning pins of what is on screen: a missing required part, the build's IMPOSSIBLE and
## LIMITING warnings (most severe first), and the last refused drop. The panel shows only their
## count and a mark beside each readout they affect; the sentences open in the inspector.
func _refresh_warnings(b: Build, fs: Dictionary) -> void:
	var pins: Array = []
	for cat in fs["missing"]:
		pins.append(WarningPins.of_missing(String(cat)))
	pins.append_array(WarningPins.of_build(b))
	pins.append_array(WarningPins.of_pack_fit(b))
	if not _refusal.is_empty():
		pins.append(_refusal)
	warning_pins = pins
	_callout_version += 1
	_apply_tint()
	issues_label.text = WarningPins.count_text(pins.size())
	refresh_charge_chip()
	var m := WarningPins.marks(pins)
	for key in mark_buttons:
		(mark_buttons[key] as Button).text = String(m[key]["text"]) if m.has(key) else ""
		(gauges[key] as ReadoutGauge).set_warn(m.has(key))
	_show_warning_panel(previewing.is_empty())
	if not warning_open.is_empty():
		var ids: Array = pins.map(func(p): return String(p["id"]))
		warning_open = warning_open.filter(func(id): return ids.has(id))
		_fill_inspector()


## The count and the marks, shown (or hidden while a picker row previews another part).
func _show_warning_panel(on: bool) -> void:
	# "1 issue" is the one statement of a missing part too (the old "cannot fly" line is gone).
	issues_label.visible = on and issues_label.text != ""
	for key in mark_buttons:
		var btn := mark_buttons[key] as Button
		btn.visible = on and btn.text != ""


## The pin dicts (WarningPins) with these ids, in pin order.
func warning_pin(id: String) -> Dictionary:
	for p in warning_pins:
		if String(p["id"]) == id:
			return p
	return {}


## Shows these pins' full sentences in the inspector (the selection is cleared: one thing at a time).
func open_warning(ids: Array) -> void:
	var known: Array = ids.filter(func(id): return not warning_pin(String(id)).is_empty())
	if known.is_empty():
		return
	if selected != "":
		select("")
	warning_open = known
	_fill_inspector()


## A click on a warning pin or its label (px): opens it. False when there is none there.
func open_warning_at(px: Vector2) -> bool:
	if callouts == null or not callouts.visible:
		return false
	var id := callouts.warning_at(px)
	if id == "":
		return false
	open_warning([id])
	return true


## A readout's mark pressed: opens every pin that marks that readout.
func open_readout_warning(key: String) -> void:
	var m := WarningPins.marks(warning_pins)
	if m.has(key):
		open_warning(m[key]["ids"])


## The address a pin is drawn on: its anchor, or the fallback when that is not drawn; "" if neither.
func _pin_anchor(w: Dictionary, have: Array) -> String:
	for a in [String(w["anchor"]), WarningPins.FALLBACK_ANCHOR]:
		if have.has(a):
			return a
	return ""


## The parts a blocking pin tints (their addresses), for the look to colour.
func tinted_parts() -> Array:
	var have := picks.addresses()
	var out: Array = []
	for w in warning_pins:
		var a := _pin_anchor(w, have)
		if bool(w["tint"]) and a != "" and not out.has(a):
			out.append(a)
	return out


## Signed readout change as shown beside a readout while a picker row is hovered.
static func format_delta(key: String, d: float) -> String:
	match key:
		"auw_g": return "%+.1f g" % d
		"thrust_to_weight": return "%+.2f" % d
		"hover_throttle": return "%+.1f pts" % (d * 100.0)
		"flight_time_min": return "%+.1f min" % d
		"top_speed_kmh": return "%+.0f km/h" % d
	return "%+f" % d


## Shows what choosing `part_id` would do to each readout (signed number and bar). Nothing for a
## refused part. Returns the deltas shown.
func preview(category: String, part_id: String) -> Dictionary:
	clear_preview()
	var v := PartSwap.judge(session, _catalog, category, part_id)
	var now := session.readouts(_catalog)
	if not v["ok"] or now.is_empty() or (v["readouts"] as Dictionary).is_empty():
		return {}
	for key in PartSwap.READOUT_KEYS:
		var d := float(v["readouts"][key]) - float(now[key])
		previewing[key] = d
		var l := delta_labels[key] as Label
		l.text = format_delta(key, d)
		l.visible = true
		var bar := delta_bars[key] as ColorRect
		var frac := clampf(absf(d) / float(DELTA_SCALE[key]), 0.0, 1.0) * 0.5
		var w := maxf(frac * DELTA_TRACK_W, 1.0 if absf(d) > 1e-9 else 0.0)
		bar.size = Vector2(w, 3)
		bar.position = Vector2(DELTA_TRACK_W * 0.5 - (w if d < 0.0 else 0.0), 0)
		(bar.get_parent() as Control).visible = true
	# The warnings describe the fitted drone, not the hovered one, and with the deltas showing the
	# panel grows into the inspector at 720 tall: hidden while previewing, back on clear_preview.
	_show_warning_panel(false)
	return previewing.duplicate()


func clear_preview() -> void:
	previewing = {}
	if issues_label != null:
		_show_warning_panel(true)
	for key in delta_labels:
		(delta_labels[key] as Label).visible = false
		(delta_bars[key].get_parent() as Control).visible = false


## One readout as shown. Static so the tests can name the exact string.
static func format_readout(key: String, r: Dictionary) -> String:
	# Absent, not zero: a drone that cannot fly (Section 5, a required part removed) has no figures.
	if not r.has(key) or r[key] == null:
		return "—"
	var v := float(r[key])
	match key:
		"auw_g": return "%.1f g" % v
		"thrust_to_weight": return "%.2f : 1" % v
		"hover_throttle": return "%.1f %%" % (v * 100.0)
		"flight_time_min": return "%.1f min" % v
		"top_speed_kmh": return "%.0f km/h" % v
	return str(v)


func model_path() -> String:
	return _model_path


## Home: the isometric view, with the drone clear of whatever is open beside it (the shelf on the
## left, the picker on the right). With neither open it is the plain home view.
func go_home() -> void:
	rig.go_home()
	_room_before = {}
	_room_goal = {}
	_update_room()


## The world-space bounds of every mesh the user sees, by mesh (pick proxies excluded).
func mesh_boxes() -> Array:
	var out: Array = []
	for entry in picks.entries:
		if not entry["proxy"]:
			out.append({"name": String((entry["node"] as Node).name), "box": entry["box"]})
	return out


## The thing under the screen point `ndc`: {address, name, position, box} or {} for nothing.
func pick(ndc: Vector2) -> Dictionary:
	var ray := rig.ray(ndc)
	var h := picks.hit(ray["origin"], ray["dir"])
	if h.is_empty():
		return {}
	var address := String(h["address"])
	return {"address": address, "name": PickRegistry.display_name(address),
		"position": h["position"], "box": picks.box_of(address)}


## Double-click: frames what is under `ndc`. False if the click hit nothing.
func frame_at(ndc: Vector2) -> bool:
	var hit := pick(ndc)
	if hit.is_empty():
		return false
	rig.frame(hit["box"])
	return true


## A click: selects what is under `ndc`, or clears the selection on empty space. Clicking again in
## the same place selects the next thing behind it along the same ray (a hole inside the frame
## sandwich, the plate under the pack), wrapping back to the front. Returns the address.
func click_at(ndc: Vector2) -> String:
	var ray := rig.ray(ndc)
	var all := picks.hits(ray["origin"], ray["dir"])
	var order: Array = all.map(func(h): return String(h["address"]))
	var again := ndc.distance_to(_last_click_ndc) < CLICK_AGAIN_NDC and order == _last_click_order
	_last_click_ndc = ndc
	_last_click_order = order
	if order.is_empty():
		select("")
	elif again and order.has(selected):
		select(order[(order.find(selected) + 1) % order.size()])
	else:
		select(order[0])
	return selected


## Hover: outlines and names what is under `ndc` (or nothing).
func hover_at(ndc: Vector2, screen_pos: Vector2 = Vector2.ZERO) -> String:
	var hit := pick(ndc)
	hovered = String(hit.get("address", ""))
	hover_label.text = String(hit.get("name", ""))
	hover_label.visible = hovered != "" and not labels_hidden
	hover_label.position = screen_pos + Vector2(16, 14)
	callout_focus = callouts.at(screen_pos) if callouts != null and callouts.visible else ""
	_apply_marks()
	return hovered


## Selects `address` ("" clears) and shows its numbers in the inspector.
func select(address: String) -> void:
	selected = address
	warning_open = []
	_fill_inspector()
	_apply_marks()
	_update_tool_row()
	var slot := PartSwap.slot_of(address)
	if slot != "":
		open_slot(slot)
	else:
		close_slot()


func clear_selection() -> void:
	select("")


## The inspector's rows as text, for tests: ["Mass: 185.0 g", ...]; empty when nothing is selected.
func inspector_lines() -> Array:
	var out: Array = []
	if not inspector.visible:
		return out
	for row in inspector.get_children():
		if row is Label:
			out.append((row as Label).text)
	return out


func _fill_inspector() -> void:
	for c in inspector.get_children():
		inspector.remove_child(c)
		c.queue_free()
	if not warning_open.is_empty():
		_fill_warning_inspector()
		return
	inspector.visible = selected != ""
	if selected == "":
		return
	var rows := PartFacts.rows(selected, session, _catalog, picks.measure_box(selected))
	for i in rows.size():
		var row: Array = rows[i]
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == 0:
			l.text = String(row[1])
			l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_TITLE)
			l.add_theme_color_override("font_color", INK)
		elif String(row[0]) == "":
			l.text = String(row[1])
			l.custom_minimum_size = Vector2(0, 4)
		else:
			l.text = "%s: %s" % [row[0], row[1]]
			l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
			l.add_theme_color_override("font_color", INK if String(row[0]) in ["Mass", "Part"] else INK_MUTED)
		inspector.add_child(l)
	if selected.begins_with("frame/") and frame_change_text() != "":
		var ch := Label.new()
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.text = frame_change_text()
		ch.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		ch.add_theme_color_override("font_color", INK)
		inspector.add_child(ch)
	var sheet_category := PartSheetTabs.category_of_address(selected)
	if sheet_category != "":
		var open_sheet := DsUi.button("Open sheet")
		open_sheet.name = "OpenSheet"
		open_sheet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		open_sheet.pressed.connect(func(): open_part_sheet(sheet_category))
		inspector.add_child(open_sheet)


## The open warning pins: each one's tag, then its full sentence (the existing long text).
func _fill_warning_inspector() -> void:
	inspector.visible = true
	for id in warning_open:
		var w := warning_pin(String(id))
		var tag := Label.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.text = String(w["tag"])
		tag.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
		tag.add_theme_color_override("font_color", WARN_INK)
		inspector.add_child(tag)
		var long := Label.new()
		long.mouse_filter = Control.MOUSE_FILTER_IGNORE
		long.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		long.text = String(w["long"])
		long.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		long.add_theme_color_override("font_color", INK)
		inspector.add_child(long)


## Outlines the hovered and selected pieces: drawn meshes get an ink hull, holes and pockets (hidden
## proxies) are filled, a pad gets a filled disc on its arm. Monochrome; hover grey, selection white.
func _apply_marks() -> void:
	_clear_tint()
	for node in _marked:
		if not is_instance_valid(node):
			continue
		var mi := node as MeshInstance3D
		mi.material_overlay = null
		if String(mi.name).begins_with(PickRegistry.PROXY_PREFIX):
			mi.material_override = null
			mi.visible = false
	_marked.clear()
	_pad_marker.visible = false
	for k in _motor_hulls:
		(_motor_hulls[k] as MeshInstance3D).visible = false
	for pair in [[hovered, false], [selected, true]]:
		var address := String(pair[0])
		if address == "" or (pair[1] == false and address == selected):
			continue
		var sel: bool = pair[1]
		var entry := picks.entry_for(address)
		if entry.is_empty():
			continue
		if address.begins_with("frame/pad/"):
			var box := picks.box_of(address)
			(_pad_marker.mesh as CylinderMesh).top_radius = box.size.x * 0.5
			(_pad_marker.mesh as CylinderMesh).bottom_radius = box.size.x * 0.5
			(_pad_marker.mesh as CylinderMesh).height = box.size.y * 1.02
			_pad_marker.position = box.get_center()
			_pad_marker.material_override = _fill_mat(sel)
			_pad_marker.visible = true
			continue
		if address.begins_with("part/motor/"):
			# A motor is outlined by a hull round its bell, not by its own mesh: the bell's vents
			# and cooling slots would each get an outline of their own and the motor read as noise.
			var mbox := picks.box_of(address)
			var hull := _motor_hulls[sel] as MeshInstance3D
			var cyl := hull.mesh as CylinderMesh
			var rad := maxf(mbox.size.x, mbox.size.z) * 0.5
			cyl.top_radius = rad
			cyl.bottom_radius = rad
			cyl.height = mbox.size.y
			hull.position = mbox.get_center()
			hull.material_override = _select_mat if sel else _hover_mat
			hull.visible = true
			continue
		var mi := entry["node"] as MeshInstance3D
		if entry["proxy"]:
			mi.material_override = _fill_mat(sel)
			mi.visible = true
		else:
			mi.material_overlay = _select_mat if sel else _hover_mat
		_marked.append(mi)
	_apply_tint()


## The blocking tint: a part a blocking pin names (`tinted_parts()`) wears a translucent amber
## overlay. A hovered or selected part keeps its outline, chained as the tint's next pass, so the
## tint never fights the selection overlay. Holes and pockets (proxies) are never tinted.
func _apply_tint() -> void:
	_clear_tint()
	for a in tinted_parts():
		var entry := picks.entry_for(String(a))
		if entry.is_empty() or entry["proxy"] or not is_instance_valid(entry["node"]):
			continue
		var mi := entry["node"] as MeshInstance3D
		if mi == null or _tinted.has(mi):
			continue
		mi.material_overlay = tint_material(mi.material_overlay)
		_tinted.append(mi)


## Takes the tint off, leaving whatever outline it carried.
func _clear_tint() -> void:
	for mi in _tinted:
		if is_instance_valid(mi) and _tint_mats.values().has(mi.material_overlay):
			mi.material_overlay = (mi.material_overlay as Material).next_pass
	_tinted.clear()


## The tint material over `outline` (null, the hover or the selection outline).
func tint_material(outline: Material) -> StandardMaterial3D:
	var key := 0 if outline == null else outline.get_instance_id()
	if not _tint_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(WARN_INK, TINT_ALPHA)
		m.next_pass = outline
		_tint_mats[key] = m
	return _tint_mats[key]


func _fill_mat(sel: bool) -> StandardMaterial3D:
	if not _fill_mats.has(sel):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := SELECT_INK if sel else HOVER_INK
		m.albedo_color = Color(c.r, c.g, c.b, 0.75 if sel else 0.5)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fill_mats[sel] = m
	return _fill_mats[sel]


func _ndc_of(pos: Vector2) -> Vector2:
	return Vector2(pos.x / maxf(size.x, 1.0) * 2.0 - 1.0, 1.0 - pos.y / maxf(size.y, 1.0) * 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					rig.zoom_toward(WHEEL_ZOOM, _ndc_of(mb.position))
				MOUSE_BUTTON_WHEEL_DOWN:
					rig.zoom_toward(1.0 / WHEEL_ZOOM, _ndc_of(mb.position))
				MOUSE_BUTTON_LEFT:
					if mb.double_click and frame_tool == "":
						frame_at(_ndc_of(mb.position))
					_drag = "pan" if mb.shift_pressed else "orbit"
					if frame_tool == "pocket" and not mb.shift_pressed and plate_hit(_ndc_of(mb.position)).has("plate"):
						_drag = "pocket"
						_pocket_from = mb.position
					elif frame_tool == "" and not mb.shift_pressed and not mb.double_click \
							and PartSnap.category_at(selected) != "" \
							and _ray_meets(_ndc_of(mb.position), selected):
						# Pressed on the selected part: a drag carries it (off the drone removes it).
						_drag = "part"
					_press_pos = mb.position
					_press_moved = mb.double_click
				MOUSE_BUTTON_RIGHT:
					_drag = "pan"
				MOUSE_BUTTON_MIDDLE:
					_drag = "pan" if mb.shift_pressed else "orbit"
			if is_inside_tree():
				grab_focus()
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT and _drag == "pocket":
				pocket_between(_ndc_of(_pocket_from), _ndc_of(mb.position))
			elif mb.button_index == MOUSE_BUTTON_LEFT and _drag != "" and not _press_moved \
					and mb.position.distance_to(_press_pos) <= CLICK_SLOP_PX:
				if open_warning_at(mb.position):
					pass
				elif frame_tool == "drill":
					drill_at(_ndc_of(mb.position))
				elif frame_tool == "fill":
					fill_at(_ndc_of(mb.position))
				else:
					click_at(_ndc_of(mb.position))
			_drag = ""
		accept_event()
	elif event is InputEventMouseMotion and _drag == "":
		var mm := event as InputEventMouseMotion
		hover_at(_ndc_of(mm.position), mm.position)
	elif event is InputEventMouseMotion and _drag != "":
		var rel := (event as InputEventMouseMotion).relative
		if (event as InputEventMouseMotion).position.distance_to(_press_pos) > CLICK_SLOP_PX:
			_press_moved = true
		if _drag == "pocket":
			pass
		elif _drag == "part":
			if _press_moved and drag_kind == "":
				begin_off_drag(selected)
				drag_over((event as InputEventMouseMotion).position)
		elif _drag == "orbit":
			rig.orbit(rel.x * ORBIT_RAD_PER_PX, rel.y * ORBIT_RAD_PER_PX)
		else:
			rig.pan(rel.x / maxf(size.y, 1.0), rel.y / maxf(size.y, 1.0))
		accept_event()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		rig.zoom_toward(1.0 / maxf(g.factor * PINCH_GAIN, 0.05), _ndc_of(g.position))
		accept_event()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if Input.is_key_pressed(KEY_SHIFT):
			rig.pan(-pg.delta.x * 0.01, -pg.delta.y * 0.01)
		else:
			rig.orbit(pg.delta.x * 0.02, pg.delta.y * 0.02)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var ke := event as InputEventKey
	var key := ke.keycode
	var command := ke.ctrl_pressed or ke.meta_pressed
	if command and key == KEY_Z:
		if ke.shift_pressed:
			redo()
		else:
			undo()
	elif command and key == KEY_Y:
		redo()
	elif command and key == KEY_S:
		if ke.shift_pressed or design_name == "":
			open_save_as()
		else:
			save_design()
	elif command and key == KEY_O:
		open_open_dialog()
	elif key == KEY_F and not command and not ke.shift_pressed and not ke.alt_pressed:
		fly_requested.emit()
	elif key == KEY_H or key == KEY_HOME:
		go_home()
	elif key == KEY_L and not command:
		toggle_labels()
	elif key == KEY_DELETE:
		remove_selected()
	elif key == KEY_BACKSPACE:
		back_requested.emit()
	elif key == KEY_ESCAPE:
		if file_bar.dialog_open():
			file_bar.close_dialog()
		elif drag_kind != "":
			cancel_drag()
		elif frame_tool != "":
			set_frame_tool("")
		elif selected != "":
			clear_selection()
		else:
			dismissed.emit()
	else:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if viewport != null and is_inside_tree():
		var sc := get_viewport().get_final_transform().get_scale()
		var px := Vector2i(maxi(int(size.x * sc.x), 16), maxi(int(size.y * sc.y), 16))
		if viewport.size != px:
			viewport.size = px
		rig.aspect = float(px.x) / float(px.y)
	rig.step(delta)
	apply_camera()
	step_panel(delta)
	step_labels(delta)
	_update_callouts_if_moved()


## Eases the readouts panel out while zoomed in or framing a part, and back at normal distance.
func step_panel(delta: float) -> void:
	var want := 0.0 if rig.is_zoomed_in() else 1.0
	panel_alpha = move_toward(panel_alpha, want, delta / PANEL_FADE_S)
	# smoothstep gives the ease; the panel never takes clicks, so nothing else changes.
	panel.modulate.a = smoothstep(0.0, 1.0, panel_alpha)


## The eye (or L): hides every label, callout and warning pin over the drone, or shows them. Hiding
## is immediate; showing fades in. It beats the idle fade: input never brings back what it hid.
func toggle_labels() -> void:
	set_labels_hidden(not labels_hidden)


func set_labels_hidden(on: bool) -> void:
	labels_hidden = on
	if on:
		label_alpha = 0.0
	# The name tag by the cursor is a label too: hidden with the rest, back as the pointer moves.
	if hover_label != null:
		hover_label.visible = hovered != "" and not on
	_idle_s = 0.0
	_apply_label_alpha()


## Any mouse or key input: the idle clock restarts and the labels fade back in.
func note_input() -> void:
	_idle_s = 0.0


## True once the user has been inactive for IDLE_HIDE_S.
func labels_idle() -> bool:
	return _idle_s >= IDLE_HIDE_S


## Advances the idle clock and the fade by `delta` seconds (the frame loop's call; tests pass time).
func step_labels(delta: float) -> void:
	_idle_s += delta
	var want := 0.0 if labels_hidden or labels_idle() else 1.0
	label_alpha = move_toward(label_alpha, want, delta / LABEL_FADE_S)
	_apply_label_alpha()


func _apply_label_alpha() -> void:
	if callouts == null:
		return
	callouts.modulate.a = label_alpha
	callouts.visible = label_alpha > 0.0
	if labels_button != null and not is_equal_approx(label_alpha, _drawn_label_alpha):
		_drawn_label_alpha = label_alpha
		redraw_requests += 1
		labels_button.queue_redraw()


func apply_camera() -> void:
	camera.fov = CameraRig.FOV_DEG
	camera.near = rig.near()
	camera.far = rig.far()
	camera.global_transform = Transform3D(rig.basis(), rig.position())


# ---------------------------------------------------------------------------
# The stage (the picker's look)
# ---------------------------------------------------------------------------

## The Design Space is only hidden while the sim/Field/picker is up, never freed: stop its 3D
## world rendering and its frame loop while hidden, restore both on return.
func set_active(on: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if viewport != null:
		viewport.render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_tex = TextureRect.new()
	_tex.name = "Stage"
	_tex.texture = viewport.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	# Over the stage, under every panel.
	callouts = CalloutLayer.new()
	add_child(callouts)

	_stage = Node3D.new()
	_stage.name = "StageRoot"
	viewport.add_child(_stage)

	# Section 6 studio (FrameLook): the sky is a dark room with a key softbox and a rim strip, only ever
	# reflected; no glow, no motion blur, gentle SSAO.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = STAGE_BG
	env.sky = FrameLook.studio_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.40
	env.glow_enabled = false
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = ClassPicker.EXPOSURE
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_intensity = FrameLook.SSAO_INTENSITY
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_radius = 0.01
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_stage.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = ClassPicker.KEY_ENERGY
	key.shadow_enabled = true
	key.light_angular_distance = FrameLook.KEY_ANGULAR_DEG
	key.shadow_blur = 2.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 3.0
	key.shadow_normal_bias = 1.0
	key.shadow_bias = 0.02
	key.rotation = FrameLook.KEY_ROTATION_DEG * (PI / 180.0)
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.45
	fill.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(65.0), 0.0)
	_stage.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_energy = 1.6
	rim.rotation = FrameLook.RIM_ROTATION_DEG * (PI / 180.0)
	_stage.add_child(rim)

	_load_model()
	var r := float(rig.radius)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	var floor_shader := Shader.new()
	floor_shader.code = ClassPicker.FLOOR_SHADER
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = floor_shader
	floor_mat.set_shader_parameter("fade_radius", r * 3.2)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_mat
	_stage.add_child(floor_node)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for i in 17:
		var t := float(i) / 16.0
		grad.add_point(t, Color(0, 0, 0, 0.8 * exp(-t * t * 5.0) * (1.0 - smoothstep(0.7, 1.0, t))))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 256
	gtex.height = 256
	var blob_mat := StandardMaterial3D.new()
	blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.albedo_texture = gtex
	blob_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blob_mesh := PlaneMesh.new()
	blob_mesh.size = Vector2.ONE
	var blob := MeshInstance3D.new()
	blob.name = "ContactShadow"
	blob.mesh = blob_mesh
	blob.material_override = blob_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.0004
	blob.scale = Vector3(r * 3.2, 1.0, r * 3.2)
	_stage.add_child(blob)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	_stage.add_child(camera)
	apply_camera()


## Loads the class's GLB, standing on y=0 and centred on its bounds; sizes the rig from it.
func _load_model() -> void:
	_model_path = DroneClass.model_path(session.drone_class)
	model = Node3D.new()
	model.name = "Model"
	var root: Node = null
	if ResourceLoader.exists(_model_path):
		var scene := load(_model_path) as PackedScene
		if scene != null:
			root = scene.instantiate()
	if root == null:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(_model_path, state) == OK:
			root = doc.generate_scene(state)
	rig = CameraRig.new()
	if root != null:
		model.add_child(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			for i in inst.mesh.get_surface_count():
				var mat := inst.mesh.surface_get_material(i) as BaseMaterial3D
				if mat != null:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if String(inst.name).begins_with(PickRegistry.PROXY_PREFIX):
				continue
			var xf := Transform3D.IDENTITY
			var n: Node = inst
			while n != null and n != root.get_parent():
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var box := xf * inst.get_aabb()
			lo = lo.min(box.position)
			hi = hi.max(box.end)
		if lo.x < INF:
			var centre := (lo + hi) * 0.5
			(root as Node3D).position = Vector3(-centre.x, -lo.y, -centre.z)
			rig = CameraRig.new(0.5 * Vector2(hi.x - lo.x, hi.z - lo.z).length(), hi.y - lo.y)
		_doc_root = root as Node3D
		_mount_map = PartSnap.mount_map(root)
		_stash_frame(root)
		_capture_look(root)
	_stage.add_child(model)
	rebuild_picks()


## Records each swappable node as drawn, with the local point it is scaled about (SwapLook).
func _capture_look(root: Node) -> void:
	var drawn := DesignSession.default_for_class(session.drone_class)
	_drawn_selection = drawn.selection.duplicate() if drawn != null else session.selection.duplicate()
	for node_name in SwapLook.NODES:
		var mi := root.find_child(node_name, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.mesh.get_aabb()
		var pivot := Vector3.ZERO
		match node_name:
			"battery":
				pivot = Vector3(0, _wrap_extent_y(mi.mesh).x, 0)
			"stack":
				pivot = Vector3(0, box.position.y, 0)
			"antennas":
				pivot = Vector3(0, box.position.y, box.position.z)
		_look_base[node_name] = {"xf": mi.transform, "pivot": pivot}
		_look_nodes[node_name] = mi


## The pack's cells (wrap and end shrink), bottom and top (local y): the strap and pad excluded.
static func _wrap_extent_y(mesh: Mesh) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat == null or not String(mat.resource_name).begins_with("lipo_"):
			continue
		for v in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			lo = minf(lo, (v as Vector3).y)
			hi = maxf(hi, (v as Vector3).y)
	if lo == INF:
		var box := mesh.get_aabb()
		return Vector2(box.position.y, box.end.y)
	return Vector2(lo, hi)


## Redraws every swappable part at its fitted part's catalog size (SwapLook), relabels a swapped
## pack, and regenerates the pick shapes from the moved meshes.
func apply_look() -> void:
	if _look_base.is_empty():
		return
	var t := SwapLook.transforms(_look_base, _drawn_selection, session.selection, _catalog)
	for node_name in t:
		var node := _look_nodes[node_name] as MeshInstance3D
		node.transform = t[node_name]["xf"]
		node.visible = t[node_name]["visible"]
	_update_pack_label()
	rebuild_picks()
	_apply_marks()


## The model is printed with its seed pack's label; a swapped pack loses that print (it would lie)
## and wears its own figures on top instead.
func _update_pack_label() -> void:
	var node := _look_nodes.get("battery") as MeshInstance3D
	if node == null:
		return
	var id := String(session.selection.get("battery", ""))
	var swapped := id != String(_drawn_selection.get("battery", ""))
	if _plain_wrap == null:
		_plain_wrap = StandardMaterial3D.new()
		_plain_wrap.albedo_color = Color(0.11, 0.11, 0.12)
		_plain_wrap.roughness = 0.55
	for i in node.mesh.get_surface_count():
		var mat := node.mesh.surface_get_material(i)
		if mat != null and String(mat.resource_name).begins_with("lipo_wrap"):
			node.set_surface_override_material(i, _plain_wrap if swapped else null)
	if _pack_label == null:
		_pack_label = Label3D.new()
		_pack_label.name = "PackLabel"
		_pack_label.font_size = 48
		_pack_label.pixel_size = 0.0001
		_pack_label.outline_size = 0
		_pack_label.modulate = Color(0.85, 0.85, 0.85)
		_pack_label.shaded = false
		_pack_label.double_sided = false
		_pack_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.get_parent().add_child(_pack_label)
	_pack_label.visible = swapped and node.visible
	if not _pack_label.visible:
		return
	_pack_label.text = SwapLook.pack_label(_catalog.get_part(id))
	var top := _wrap_extent_y(node.mesh).y
	var at := node.transform * Vector3(0, top, 0)
	# Flat on the top face, reading along the pack (the way the drawn labels read).
	_pack_label.transform = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5),
		at + Vector3(0, 0.0004, 0))


## The text a swapped pack wears, or "" when it wears the drawn print.
func pack_label_text() -> String:
	return _pack_label.text if _pack_label != null and _pack_label.visible else ""


## Regenerates every pick shape from the model's current meshes. The one call any mesh change makes.
func rebuild_picks() -> void:
	picks.rebuild(model, _stage)
	_rebuild_callout_hulls()


# ---------------------------------------------------------------------------
# The panel: five numbers, nothing else
# ---------------------------------------------------------------------------

## The eye button: an open eye while labels show, struck through while hidden.
class LabelsEye extends Button:
	var _ds: DesignSpace

	func _init(ds: DesignSpace) -> void:
		_ds = ds
		flat = true
		focus_mode = Control.FOCUS_NONE
		anchor_top = 1.0
		anchor_bottom = 1.0

	func _draw() -> void:
		var c := Color(0.93, 0.93, 0.93) if is_hovered() else Color(0.58, 0.58, 0.58)
		var o := size * 0.5
		var pts := PackedVector2Array()
		for i in 21:
			var t := float(i) / 20.0
			var x := lerpf(-9.0, 9.0, t)
			pts.append(o + Vector2(x, -5.0 * sin(PI * t)))
		for i in range(20, -1, -1):
			var t := float(i) / 20.0
			var x := lerpf(-9.0, 9.0, t)
			pts.append(o + Vector2(x, 5.0 * sin(PI * t)))
		draw_polyline(pts, c, 1.5, true)
		draw_circle(o, 2.5, c)
		if _ds != null and _ds.labels_hidden:
			draw_line(o + Vector2(-8, 8), o + Vector2(8, -8), c, 1.5, true)


func _build_panel() -> void:
	panel = VBoxContainer.new()
	panel.name = "Readouts"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -PANEL_W - PANEL_EDGE
	panel.offset_right = -PANEL_EDGE
	panel.offset_top = 48
	panel.offset_bottom = 400
	panel.add_theme_constant_override("separation", 10)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_TITLE)
	title_label.add_theme_color_override("font_color", INK)
	panel.add_child(title_label)
	var rule := ColorRect.new()
	rule.color = INK_FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rule)
	# The selected battery's charge: "4S 1500mAh · 62%" and a plug that charges it.
	charge_chip = ChargeChip.new()
	charge_chip.charged.connect(_on_chip_charged)
	panel.add_child(charge_chip)
	# "2 issues": the count of warning pins; the sentences are on the pins (Section 8).
	issues_label = Label.new()
	issues_label.name = "Issues"
	issues_label.visible = false
	issues_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	issues_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	issues_label.add_theme_color_override("font_color", WARN_INK)
	panel.add_child(issues_label)

	# Five stacked units in a two-column grid: the ring with its number inside, the icon beneath,
	# a short label below that, and the amber mark of any warning that moves it.
	var rows := [["auw_g", "Weight"], ["thrust_to_weight", "Thrust : weight"],
		["hover_throttle", "Hover"], ["flight_time_min", "Flight (est.)"],
		["top_speed_kmh", "Top speed (est.)"]]
	var grid := GridContainer.new()
	grid.name = "ReadoutGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(grid)
	for row in rows:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gauge := ReadoutGauge.new(String(row[0]))
		var val := Label.new()
		val.name = String(row[0])
		val.set_anchors_preset(Control.PRESET_FULL_RECT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		val.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		val.add_theme_color_override("font_color", INK)
		gauge.add_child(val)
		box.add_child(gauge)
		box.add_child(ReadoutGauge.Icon.new(String(row[0])))
		var cap := Label.new()
		cap.text = String(row[1])
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		cap.add_theme_color_override("font_color", INK_MUTED)
		box.add_child(cap)
		var mark := Button.new()
		mark.name = "mark_" + String(row[0])
		mark.flat = true
		mark.visible = false
		mark.focus_mode = Control.FOCUS_NONE
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mark.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			mark.add_theme_color_override(st, WARN_INK)
		mark.pressed.connect(open_readout_warning.bind(String(row[0])))
		box.add_child(mark)
		gauges[row[0]] = gauge
		mark_buttons[row[0]] = mark
		var dl := Label.new()
		dl.name = "delta_" + String(row[0])
		dl.visible = false
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		dl.add_theme_color_override("font_color", INK_MUTED)
		box.add_child(dl)
		var track := Control.new()
		track.custom_minimum_size = Vector2(DELTA_TRACK_W, 3)
		track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.visible = false
		var tick := ColorRect.new()
		tick.color = INK_FAINT
		tick.position = Vector2(DELTA_TRACK_W * 0.5, -1)
		tick.size = Vector2(1, 5)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(tick)
		var bar := ColorRect.new()
		bar.color = INK
		bar.size = Vector2(0, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(bar)
		box.add_child(track)
		grid.add_child(box)
		value_labels[row[0]] = val
		delta_labels[row[0]] = dl
		delta_bars[row[0]] = bar


	home_button = Button.new()
	home_button.name = "Home"
	home_button.text = "Home  (H)"
	home_button.flat = true
	home_button.focus_mode = Control.FOCUS_NONE
	home_button.anchor_top = 1.0
	home_button.anchor_bottom = 1.0
	home_button.offset_left = 32
	home_button.offset_right = 140
	home_button.offset_top = -56
	home_button.offset_bottom = -24
	home_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	home_button.add_theme_color_override("font_color", INK_MUTED)
	home_button.add_theme_color_override("font_hover_color", INK)
	home_button.add_theme_color_override("font_pressed_color", INK)
	home_button.pressed.connect(go_home)
	add_child(home_button)

	labels_button = LabelsEye.new(self)
	labels_button.name = "LabelsToggle"
	labels_button.tooltip_text = "Show or hide labels  (L)"
	labels_button.offset_left = 32
	labels_button.offset_right = 60
	labels_button.offset_top = -96
	labels_button.offset_bottom = -64
	labels_button.pressed.connect(toggle_labels)
	add_child(labels_button)

	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "\u2039 Classes"
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.offset_left = 32
	back_button.offset_right = 140
	back_button.offset_top = 20
	back_button.offset_bottom = 52
	back_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	back_button.add_theme_color_override("font_color", INK_MUTED)
	back_button.add_theme_color_override("font_hover_color", INK)
	back_button.add_theme_color_override("font_pressed_color", INK)
	back_button.pressed.connect(func(): back_requested.emit())
	add_child(back_button)


# ---------------------------------------------------------------------------
# Save and open (PLAN Section 9; the file format is DesignFile)
# ---------------------------------------------------------------------------

func _build_file_bar() -> void:
	file_bar = DesignFileBar.new()
	add_child(file_bar)
	file_bar.save_pressed.connect(save_design)
	file_bar.save_as_pressed.connect(open_save_as)
	file_bar.open_pressed.connect(open_open_dialog)
	file_bar.fly_pressed.connect(func(): fly_requested.emit())
	file_bar.identity_pressed.connect(toggle_identity)
	identity_sheet = DsIdentity.sheet()
	add_child(identity_sheet)
	refresh_identity()
	file_bar.field_pressed.connect(func(): field_requested.emit())
	file_bar.mission_pressed.connect(func(): mission_requested.emit())
	file_bar.room_pressed.connect(func(id: String): room_requested.emit(id))
	file_bar.save_as_confirmed.connect(func(n: String): save_design(n))
	file_bar.open_chosen.connect(func(f: String): open_design(f))
	file_bar.show_name(design_name)


## Save under `p_name` (or the design's own name). With no name at all the Save-as dialog opens.
## {ok, reason}; a refusal shows its one line in amber in the dialog.
func save_design(p_name: String = "") -> Dictionary:
	var n := p_name.strip_edges() if p_name != "" else design_name
	if n == "":
		open_save_as()
		return {"ok": false, "reason": "Give the design a name."}
	var r := DesignFile.save(session, n)
	if not r["ok"]:
		if not file_bar.dialog_open():
			open_save_as()
		file_bar.show_reason(String(r["reason"]))
		return r
	design_name = n
	design_source = "design file"
	file_bar.show_name(n)
	file_bar.show_status("Saved")
	file_bar.close_dialog()
	return r


func open_save_as() -> void:
	file_bar.open_save_as(design_name)


func open_open_dialog() -> void:
	file_bar.open_open(recent_designs())


## Saved design file names, most recently written first.
func recent_designs() -> Array:
	var files := Array(DesignFile.list())
	var stamp := func(f: String) -> int: return FileAccess.get_modified_time(DesignFile.dir + "/" + f)
	files.sort_custom(func(a, b): return stamp.call(a) > stamp.call(b) or (stamp.call(a) == stamp.call(b) and a < b))
	return files


## Opens `file_name` from the designs folder. A refusal changes nothing and shows its one line
## in amber in the dialog; a load replaces the session (undo history starts empty). {ok, reason}.
func open_design(file_name: String) -> Dictionary:
	var r := DesignFile.load_file(DesignFile.dir + "/" + file_name, _catalog)
	if r["ok"] and (r["session"] as DesignSession).drone_class != session.drone_class:
		r = {"ok": false, "reason": "That design is a %s; open it from the class picker." % String(
			DroneClass.by_id((r["session"] as DesignSession).drone_class).get("name", "different drone")), "session": null, "name": ""}
	if not r["ok"]:
		if not file_bar.dialog_open():
			open_open_dialog()
		file_bar.show_reason(String(r["reason"]))
		file_bar.show_status("")
		return r
	session.changed.disconnect(_sync)
	session = r["session"]
	session.changed.connect(_sync)
	design_source = "design file"
	design_name = String(r["name"]) if String(r["name"]) != "" else file_name.get_basename()
	close_slot()
	set_frame_tool("")
	select("")
	_after_change()
	file_bar.show_name(design_name)
	file_bar.show_status("Opened")
	file_bar.close_dialog()
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------------------
# Hover name and the inspector
# ---------------------------------------------------------------------------

func _build_inspector() -> void:
	_hover_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	_hover_mat.shader = sh
	_hover_mat.set_shader_parameter("ink", HOVER_INK)
	_hover_mat.set_shader_parameter("width_px", HOVER_WIDTH_PX)
	_select_mat = ShaderMaterial.new()
	_select_mat.shader = sh
	_select_mat.set_shader_parameter("ink", SELECT_INK)
	_select_mat.set_shader_parameter("width_px", SELECT_WIDTH_PX)

	_pad_marker = MeshInstance3D.new()
	_pad_marker.name = "PadMarker"
	_pad_marker.mesh = CylinderMesh.new()
	_pad_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pad_marker.visible = false
	_stage.add_child(_pad_marker)
	for sel in [false, true]:
		var hull := MeshInstance3D.new()
		hull.name = "MotorHull" + ("Selected" if sel else "Hover")
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 48
		cyl.rings = 1
		hull.mesh = cyl
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hull.visible = false
		_stage.add_child(hull)
		_motor_hulls[sel] = hull

	hover_label = Label.new()
	hover_label.name = "HoverName"
	hover_label.visible = false
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	hover_label.add_theme_color_override("font_color", INK)
	hover_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hover_label.add_theme_constant_override("shadow_offset_x", 1)
	hover_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(hover_label)

	inspector = VBoxContainer.new()
	inspector.name = "Inspector"
	inspector.visible = false
	inspector.anchor_left = 1.0
	inspector.anchor_right = 1.0
	inspector.anchor_top = 1.0
	inspector.anchor_bottom = 1.0
	inspector.offset_left = -340
	inspector.offset_right = -40
	inspector.offset_top = -24
	inspector.offset_bottom = -24
	inspector.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inspector.add_theme_constant_override("separation", 2)
	inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inspector)


# ---------------------------------------------------------------------------
# Frame edits (Section 4): the tools, the click on a plate, the regenerated plates
# ---------------------------------------------------------------------------

func _build_frame_tools() -> void:
	tool_row = FrameToolRow.new()
	tool_row.offset_left = 32
	tool_row.offset_top = 64
	tool_row.offset_right = 32 + 300
	tool_row.visible = false
	add_child(tool_row)
	tool_row.tool_chosen.connect(set_frame_tool)
	tool_row.drill_size_chosen.connect(func(d: float):
		drill_d_mm = d
		_update_tool_row())
	tool_row.pocket_shape_chosen.connect(func(shape: String):
		pocket_shape = shape
		_update_tool_row())
	tool_row.fill_pressed.connect(fill_selected)
	tool_row.thickness_committed.connect(set_plate_thickness)
	tool_row.width_committed.connect(set_arm_width)
	tool_row.undo_pressed.connect(undo)
	tool_row.redo_pressed.connect(redo)
	tool_row.plan_editor_pressed.connect(func(): open_part_sheet("frame", "shape"))


## Whether the tool row shows: a frame region of an editable frame (the 5") is the selection.
func frame_tools_shown() -> bool:
	return tool_row != null and tool_row.visible


func _update_tool_row() -> void:
	if tool_row == null:
		return
	var want := selected.begins_with("frame/") and session.frame_editable()
	tool_row.visible = want
	if shelf != null:
		# The tool row and the shelf share the left column; frame editing has it while a plate is
		# selected.
		shelf.visible = not want
	if not want:
		frame_tool = ""
		return
	var plate := selected_plate()
	var doc := session.frame_document()
	var pd: Dictionary = doc.plates[plate] if plate >= 0 else {}
	var width := FrameTools.arm_width(doc, plate) if plate >= 0 and String(pd.get("role", "")) == AirframeDocument.ROLE_ARM else 1.0
	tool_row.show_state(frame_tool, drill_d_mm, pocket_shape, pd, width, session.can_undo(), session.can_redo())
	tool_row.show_change(frame_change_text())


## Arms one tool ("" for none). A click on the stage then drills or fills instead of selecting;
## with Pocket, a drag on a plate cuts instead of orbiting.
func set_frame_tool(tool: String) -> void:
	frame_tool = tool if tool in ["drill", "pocket", "fill"] else ""
	tool_row.show_reason("")
	_update_tool_row()


## The GLB scene's transform on the stage: what `FrameView` maps plan mm through.
func doc_xf() -> Transform3D:
	return PickRegistry._xform_to(_doc_root, _stage) if _doc_root != null else Transform3D.IDENTITY


## The document plate the selection is on (an arm, its pad, a plate, or a cut in one); -1 if none.
func selected_plate() -> int:
	var doc := session.frame_document()
	if doc == null:
		return -1
	var p := selected.split("/")
	if p.size() < 3 or p[0] != "frame":
		return -1
	match p[1]:
		"arm", "pad": return session.plate_of_mesh("frame_arm_" + p[2])
		"plate": return session.plate_of_mesh("frame_plate_" + p[2])
		"hole", "pocket":
			for i in doc.plates.size():
				if String((doc.plates[i] as Dictionary).get("owner", "")) == p[2]:
					return i
	return -1


## The plate address a cut address belongs to (a filled hole's selection falls back to its plate).
func _plate_address_of(address: String) -> String:
	var p := address.split("/")
	if p.size() >= 3 and p[0] == "frame" and p[1] in ["hole", "pocket"]:
		var plate_owner := p[2]
		if plate_owner.begins_with("arm_"):
			return "frame/arm/" + plate_owner.substr(4)
		if plate_owner.begins_with("plate_"):
			return "frame/plate/" + plate_owner.substr(6)
	return ""


## What is under `ndc` as a frame plate: {plate, hole (-1 unless a cut's proxy), point_mm (plan),
## address, position (stage)}; {address} for something that is not a plate; {} for nothing.
func plate_hit(ndc: Vector2) -> Dictionary:
	var ray := rig.ray(ndc)
	var all := picks.hits(ray["origin"], ray["dir"])
	if all.is_empty() or session.frame_document() == null:
		return {}
	# The first FRAME hit: with a frame tool in hand, a prop blade or a wire over the arm is not what
	# the click is about. Anything frame that is not a plate (a standoff, a screw) still refuses.
	var h: Dictionary = all[0]
	for x in all:
		if String(x["address"]).begins_with("frame/"):
			h = x
			break
	var node_name := String((h["entry"]["node"] as Node).name)
	var plate := session.plate_of_mesh(node_name)
	var hole := -1
	if plate < 0:
		var ph := session.hole_of_proxy(node_name)
		plate = ph.x
		hole = ph.y
	if plate < 0:
		return {"address": String(h["address"])}
	return {"plate": plate, "hole": hole, "point_mm": FrameView.plan_point(h["position"], doc_xf()),
		"address": String(h["address"]), "position": h["position"]}


## Drill: a `drill_d_mm` hole where `ndc` meets a plate. Returns the verdict.
func drill_at(ndc: Vector2) -> Dictionary:
	var hit := plate_hit(ndc)
	if not hit.has("plate"):
		return _frame_result(FrameTools.refuse("Drill on a plate or an arm."))
	return _frame_result(session.drill(int(hit["plate"]), hit["point_mm"], drill_d_mm))


## Fill: the hole or pocket under `ndc` back in.
func fill_at(ndc: Vector2) -> Dictionary:
	var hit := plate_hit(ndc)
	if int(hit.get("hole", -1)) < 0:
		return _frame_result(FrameTools.refuse("Click a hole or a pocket to fill it."))
	return _frame_result(session.fill(int(hit["plate"]), int(hit["hole"])))


## The Fill button: fills the selected hole or pocket at once; with anything else selected, arms the
## Fill tool so the next click picks the cut.
func fill_selected() -> Dictionary:
	var p := selected.split("/")
	if p.size() >= 4 and p[0] == "frame" and p[1] in ["hole", "pocket"]:
		var at := session.hole_of_proxy("pick_%s_%s_%s" % [p[1], p[2], p[3]])
		if at.x >= 0:
			return _frame_result(session.fill(at.x, at.y))
	set_frame_tool("fill")
	return {}


## Pocket: dragged from `ndc_a` (on a plate) to `ndc_b`, as a rectangle (along an arm's axis on an
## arm) or a slot, on the plate the drag started on.
func pocket_between(ndc_a: Vector2, ndc_b: Vector2) -> Dictionary:
	var hit := plate_hit(ndc_a)
	if not hit.has("plate"):
		return _frame_result(FrameTools.refuse("Start the pocket on a plate or an arm."))
	var doc := session.frame_document()
	var plate: Dictionary = doc.plates[int(hit["plate"])]
	var top := AirframeDocument.plate_z_mm(plate) + AirframeDocument.plate_thickness_mm(plate)
	var ray := rig.ray(ndc_b)
	var end := FrameView.ray_on_plane(ray["origin"], ray["dir"], top, doc_xf())
	if end.is_empty():
		return _frame_result(FrameTools.refuse("Drag across the plate to size the pocket."))
	var a := FrameView.ray_on_plane(rig.ray(ndc_a)["origin"], rig.ray(ndc_a)["dir"], top, doc_xf())
	var pa: Vector2 = a["point"] if not a.is_empty() else hit["point_mm"]
	var pb: Vector2 = end["point"]
	return pocket_from_to(int(hit["plate"]), pa, pb)


## The pocket a drag from `a` to `b` (plan mm) on plate `plate_index` cuts. The seam both the drag
## and the tests call.
func pocket_from_to(plate_index: int, a: Vector2, b: Vector2) -> Dictionary:
	var doc := session.frame_document()
	var plate: Dictionary = doc.plates[plate_index]
	var shape: PackedVector2Array
	if pocket_shape == "slot":
		if a.distance_to(b) < 0.5:
			return _frame_result(FrameTools.refuse("Drag along the plate to draw the slot."))
		shape = FrameTools.slot_pocket(a, b, POCKET_SLOT_WIDTH_MM)
	else:
		var angle := 0.0
		if String(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			var root := AirframeDocument.point_of(plate.get("root_point", [0, 0]))
			var tip := AirframeDocument.point_of(plate.get("tip_point", [1, 0]))
			angle = (tip - root).angle()
		var d := (b - a).rotated(-angle).abs()
		if d.x < 1.0 or d.y < 1.0:
			return _frame_result(FrameTools.refuse("Drag across the plate to size the pocket."))
		shape = FrameTools.rect_pocket((a + b) * 0.5, d, angle)
	return _frame_result(session.pocket(plate_index, shape))


func set_plate_thickness(mm: float) -> Dictionary:
	return _frame_result(session.set_plate_thickness(selected_plate(), mm))


func set_arm_width(width_scale: float) -> Dictionary:
	return _frame_result(session.set_arm_width(selected_plate(), width_scale))


## After a frame op: an applied edit moves everything (`_after_change`, which redraws the edited
## plates); a refused one shows its reason in the warning accent and touches nothing else.
func _frame_result(verdict: Dictionary) -> Dictionary:
	last_frame_verdict = verdict
	if verdict.get("ok", false):
		_sync()
		tool_row.show_reason("")
	else:
		tool_row.show_reason(String(verdict.get("reason", "")))
		_update_tool_row()
	return verdict


## The refusal line as shown ("" when hidden).
func frame_reason_text() -> String:
	return tool_row.reason_label.text if tool_row.reason_label.visible else ""


## What the edits so far did, in words: "Frame: 1 hole drilled, -0.05 g". "" when unedited.
func frame_change_text() -> String:
	var doc := session.frame_document()
	if doc == null or _frame_orig == null or doc.plates.size() != _frame_orig.plates.size():
		return ""
	var drilled := 0
	var pocketed := 0
	var filled := 0
	var thick := 0
	var wide := 0
	for i in doc.plates.size():
		var now := FrameTools.hole_names(doc.plates[i])
		var was := FrameTools.hole_names(_frame_orig.plates[i])
		for n in now:
			if not was.has(n):
				if String(n).begins_with("pick_pocket_"):
					pocketed += 1
				else:
					drilled += 1
		for n in was:
			if not now.has(n):
				filled += 1
		if absf(AirframeDocument.plate_thickness_mm(doc.plates[i]) - AirframeDocument.plate_thickness_mm(_frame_orig.plates[i])) > 1.0e-9:
			thick += 1
		if String((doc.plates[i] as Dictionary).get("role", "")) == AirframeDocument.ROLE_ARM \
				and absf(FrameTools.arm_width(doc, i) - FrameTools.arm_width(_frame_orig, i)) > 1.0e-9:
			wide += 1
	var parts: Array = []
	for pair in [[drilled, "hole drilled", "holes drilled"], [pocketed, "pocket cut", "pockets cut"],
			[filled, "cut filled", "cuts filled"], [thick, "plate thickness changed", "plate thicknesses changed"],
			[wide, "arm width changed", "arm widths changed"]]:
		if int(pair[0]) > 0:
			parts.append("%d %s" % [pair[0], pair[1] if int(pair[0]) == 1 else pair[2]])
	if parts.is_empty():
		return ""
	var dg := float(FittedFrame.drawn(doc)["mass_g"]) - float(FittedFrame.drawn(_frame_orig)["mass_g"])
	return "Frame: %s, %+.2f g" % [", ".join(PackedStringArray(parts)), dg]


## Keeps what each plate looked like in the GLB (its mesh and its cut proxies), so an unedited plate
## (or one undone back to as drawn) shows the GLB's own mesh again.
func _stash_frame(root: Node) -> void:
	var doc := session.frame_document()
	if doc == null:
		return
	_frame_orig = AirframeDocument.from_dictionary(doc.to_dictionary())
	for plate in doc.plates:
		var mesh_name := FrameTools.plate_mesh(plate)
		var node := root.find_child(mesh_name, true, false) as MeshInstance3D
		if node == null:
			continue
		_glb_meshes[mesh_name] = node.mesh
		var plate_owner := String((plate as Dictionary).get("owner", ""))
		var mine: Array = []
		for kind in ["hole", "pocket"]:
			for proxy in root.find_children("%s%s_%s_*" % [PickRegistry.PROXY_PREFIX, kind, plate_owner], "MeshInstance3D", true, false):
				mine.append(proxy)
		_glb_proxies[plate_owner] = mine
	_generate_frame(root, doc)


## Section 6: the 5" frame drawn by FrameGen, never by the GLB. Every plate node keeps its name (so
## picking and the frame tools find it) but gets the generated two-surface mesh; the GLB's standoff and
## screw nodes are hidden (PickRegistry skips hidden meshes) and replaced by one instance per document
## hardware item, under `frame_hardware_gen`, carrying the same node names.
func _generate_frame(root: Node, doc: AirframeDocument) -> void:
	if face_material == null:
		face_material = FrameLook.face_material()
	if edge_material == null:
		edge_material = FrameLook.edge_material()
	for plate in doc.plates:
		var mesh_name := FrameTools.plate_mesh(plate)
		var node := root.find_child(mesh_name, true, false) as MeshInstance3D
		if node == null or not _glb_meshes.has(mesh_name):
			continue
		_gen_meshes[mesh_name] = _plate_gen_mesh(node, plate)
		_plate_edited[mesh_name] = false
		node.mesh = _gen_meshes[mesh_name]
	if doc.hardware.is_empty():
		return
	var mats := {"standoff": FrameLook.standoff_material(), "screw": FrameLook.screw_material()}
	for glb in root.find_children("frame_s*", "MeshInstance3D", true, false):
		if String(glb.name).begins_with("frame_standoff_") or String(glb.name).begins_with("frame_screw_"):
			(glb as MeshInstance3D).visible = false
	hardware_root = FrameGen.hardware_node(doc, mats)
	root.add_child(hardware_root)


func _plate_gen_mesh(node: MeshInstance3D, plate: Dictionary) -> ArrayMesh:
	var mat := face_material
	var turn := String(plate.get("role", "")) != AirframeDocument.ROLE_ARM
	return FrameGen.plate_mesh(plate, PickRegistry._xform_to(node, _doc_root_of(node)).affine_inverse(),
		mat, edge_material, turn)


func _doc_root_of(node: Node) -> Node:
	return _doc_root if _doc_root != null else node.owner


static func _same_plate(a: Dictionary, b: Dictionary) -> bool:
	return a.get("outline") == b.get("outline") and a.get("holes") == b.get("holes") \
		and is_equal_approx(float(a.get("thickness_mm", 0.0)), float(b.get("thickness_mm", 0.0))) \
		and is_equal_approx(float(a.get("z_mm", 0.0)), float(b.get("z_mm", 0.0)))


## Whether plate `index` is drawn from the document (edited) rather than by the GLB.
func plate_regenerated(index: int) -> bool:
	var doc := session.frame_document()
	if doc == null or _doc_root == null:
		return false
	var node := _doc_root.find_child(FrameTools.plate_mesh(doc.plates[index]), true, false) as MeshInstance3D
	return node != null and bool(_plate_edited.get(String(node.name), false))


## Redraws every EDITED plate from the document (FrameView: split, clip, extrude, same material) with
## fresh pick proxies for its cuts; an unedited plate gets the GLB's mesh and proxies back. The pick
## shapes follow in `rebuild_picks` (apply_look), so a drilled hole is pickable at once.
func regenerate_frame() -> void:
	var doc := session.frame_document()
	if doc == null or _frame_orig == null or _doc_root == null:
		return
	for i in doc.plates.size():
		var plate: Dictionary = doc.plates[i]
		var mesh_name := FrameTools.plate_mesh(plate)
		var node := _doc_root.find_child(mesh_name, true, false) as MeshInstance3D
		if node == null or not _glb_meshes.has(mesh_name):
			continue
		var edited := i >= _frame_orig.plates.size() or not _same_plate(plate, _frame_orig.plates[i])
		_draw_plate(node, plate, edited)


func _draw_plate(node: MeshInstance3D, plate: Dictionary, edited: bool) -> void:
	var plate_owner := String(plate.get("owner", ""))
	var parent := node.get_parent()
	for made in _made_proxies.get(plate_owner, []):
		if is_instance_valid(made):
			(made as Node).get_parent().remove_child(made)
			(made as Node).free()
	_made_proxies[plate_owner] = []
	var glb: Array = _glb_proxies.get(plate_owner, [])
	var mesh_name := String(node.name)
	_plate_edited[mesh_name] = edited
	if not edited:
		node.mesh = _gen_meshes.get(mesh_name, _glb_meshes[mesh_name])
		for proxy in glb:
			if (proxy as Node).get_parent() == null:
				parent.add_child(proxy)
		return
	for proxy in glb:
		if (proxy as Node).get_parent() != null:
			(proxy as Node).get_parent().remove_child(proxy)
	node.mesh = _plate_gen_mesh(node, plate)
	var to_parent := PickRegistry._xform_to(parent, _doc_root).affine_inverse()
	var names := FrameTools.hole_names(plate)
	var holes := AirframeDocument.plate_holes(plate)
	var made: Array = []
	for k in holes.size():
		var n := String(names[k])
		if not n.begins_with(PickRegistry.PROXY_PREFIX):
			continue
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = FrameView.cut_proxy_mesh(holes[k], plate, to_parent)
		mi.visible = false
		parent.add_child(mi)
		made.append(mi)
	_made_proxies[plate_owner] = made


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for plate_owner in _glb_proxies:
			for proxy in _glb_proxies[plate_owner]:
				if is_instance_valid(proxy) and (proxy as Node).get_parent() == null:
					(proxy as Node).free()

# ---------------------------------------------------------------------------
# Swapping from the side panel (Section 3): a click on a part opens its category in the shelf
# ---------------------------------------------------------------------------

## Opens the shelf on a pick slot ("battery", "motor", "stack", ...): the Parts panel opens if it
## was closed, only that slot's categories are expanded, the fitted part is marked and scrolled to.
## A click on a card then swaps it in (`click_card`); a hover previews it (`hover_card`).
func open_slot(slot: String) -> void:
	if not PartSwap.SLOTS.has(slot):
		close_slot()
		return
	swap_slot = slot
	if shelf != null:
		shelf.focus_slot(PartSwap.SLOTS[slot], _fitted_now(), _shelf_groups())
		_update_room()


## No part is selected: the shelf stops swapping (what it had open stays open).
func close_slot() -> void:
	swap_slot = ""
	clear_preview()
	if shelf != null:
		shelf.clear_focus(_shelf_groups())


## The selected slot's fitted part per category ({} for no slot).
func _fitted_now() -> Dictionary:
	var out := {}
	if swap_slot == "":
		return out
	for cat in PartSwap.SLOTS[swap_slot]:
		out[String(cat)] = String(session.selection.get(cat, ""))
	return out


## A card in the shelf was clicked: swap it in place when a part is selected (the same session
## swap as ever, so undo and redo work); {} when no part is selected or the card is another slot's.
func click_card(category: String, part_id: String) -> Dictionary:
	if category == "battery":
		_clicked_battery = part_id
		refresh_charge_chip()
	if swap_slot == "" or not (PartSwap.SLOTS[swap_slot] as Array).has(category):
		return {}
	return choose(category, part_id)


## The pointer is over a card: preview its readout deltas (nothing for a misfit or another slot).
func hover_card(category: String, part_id: String) -> Dictionary:
	if swap_slot == "" or not (PartSwap.SLOTS[swap_slot] as Array).has(category) or drag_kind != "":
		return {}
	return preview(category, part_id)


## The drone on screen now: the union of every drawn mesh's box, its 8 corners projected (px).
func drone_screen_rect() -> Rect2:
	return PickerPlace.screen_rect(rig, _mesh_aabbs(), size)


func _mesh_aabbs() -> Array:
	return mesh_boxes().map(func(e): return e["box"])


var _room_before := {}         ## the camera goal before the shelf made room; {} when it made none
var _room_goal := {}           ## the goal it set, to tell whether the user has moved since


## Makes room for the open shelf (on the left): backs the camera off and slides the drone into the
## space left free, when it does not already fit; with the shelf shut, gives the room back. Not
## while zoomed in or framing a part.
func _update_room() -> void:
	if rig.is_zoomed_in() or size.x <= 0.0:
		return
	if not shelf_open():
		_give_back_room()
		return
	var view := PickerPlace.settled(rig)
	var r := PickerPlace.screen_rect(view, _mesh_aabbs(), size)
	var left := _left_edge()
	if r.position.x >= left and r.end.x <= size.x - PickerPlace.COLUMN_W:
		return
	if _room_before.is_empty():
		_room_before = {"target": rig.goal_target, "distance": rig.goal_distance}
	var g := PickerPlace.room_goal(rig, _mesh_aabbs(), size, 0.0, left)
	rig.goal_target = g["target"]
	rig.goal_distance = g["distance"]
	_room_goal = g


func shelf_open() -> bool:
	return shelf != null and shelf.visible and shelf.open


## Where the free space beside the drone starts on the left: past the open shelf, else the margin.
func _left_edge() -> float:
	if shelf_open():
		return shelf.offset_left + PartsShelf.WIDTH + PickerPlace.GAP
	return PickerPlace.MARGIN


## The shelf closed: the camera goes back, unless the user moved it since it made room.
func _give_back_room() -> void:
	if _room_before.is_empty():
		return
	if rig.goal_target.is_equal_approx(_room_goal["target"]) and is_equal_approx(rig.goal_distance, _room_goal["distance"]):
		rig.goal_target = _room_before["target"]
		rig.goal_distance = _room_before["distance"]
	_room_before = {}
	_room_goal = {}



# ---------------------------------------------------------------------------
# The shelf, the drag and the drop (Section 5)
# ---------------------------------------------------------------------------

const GHOST_INK := Color(0.96, 0.96, 0.96, 0.32)
const DROP_LABEL_OFFSET := Vector2(18, 16)


func _build_shelf() -> void:
	shelf = PartsShelf.new()
	shelf.offset_left = 32
	shelf.offset_top = 64
	shelf.offset_right = 32 + PartsShelf.WIDTH
	shelf.judge = _shelf_judge
	shelf.drag_started.connect(begin_shelf_drag)
	shelf.toggled.connect(func(_open: bool): _update_room())
	shelf.card_hovered.connect(hover_card)
	shelf.card_clicked.connect(click_card)
	shelf.card_unhovered.connect(func(): if drag_kind == "": clear_preview())
	shelf.pack_designer_requested.connect(open_pack_designer)
	shelf.motor_designer_requested.connect(open_motor_designer)
	shelf.prop_designer_requested.connect(open_prop_designer)
	shelf.custom_part_requested.connect(open_custom_part_form)
	shelf.card_menu_requested.connect(open_card_menu)
	add_child(shelf)

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = GHOST_INK
	_ghost_mat.no_depth_test = true
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_ghost_mat.render_priority = 2

	drop_label = Label.new()
	drop_label.name = "DropHint"
	drop_label.visible = false
	drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	drop_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	drop_label.add_theme_constant_override("shadow_offset_x", 1)
	drop_label.add_theme_constant_override("shadow_offset_y", 1)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.04, 0.04, 0.045, 0.88)
	pill.set_corner_radius_all(4)
	pill.content_margin_left = 7
	pill.content_margin_right = 7
	pill.content_margin_top = 3
	pill.content_margin_bottom = 3
	drop_label.add_theme_stylebox_override("normal", pill)
	add_child(drop_label)


## The drone the part designers bench against: this selection, built. With a required part taken
## off (it does not build) the class's own parts stand in for the missing ones, as a drop is judged,
## so a designer never opens on another class's aircraft.
func bench_build() -> Build:
	return PartSnap.judging_session(session, _catalog).build(_catalog)


## The shelf's verdicts for one category: part id -> {ok, reason}, judged as a drop would be (an
## empty required slot filled with the class default for judging, PartSnap.judging_session).
func _shelf_judge(category: String) -> Dictionary:
	var out := {}
	var js := PartSnap.judging_session(session, _catalog)
	# Rank: how far the part's mass is from the class's own part (log ratio), so the parts made for
	# a drone this size come first and a 1S whoop pack, which mounts on the 5" pad, sinks.
	var ref := float(_catalog.get_part(String(DroneClass.parts_for(session.drone_class).get(category, ""))).get("mass_g", 0.0))
	for opt in PartSwap.options(js, _catalog, category, _shelf_verdicts):
		var m := float(_catalog.get_part(String(opt["id"])).get("mass_g", 0.0))
		var rank := absf(log(m / ref)) if m > 0.0 and ref > 0.0 else INF
		var ok: bool = opt["ok"]
		var reason: String = opt["reason"]
		# Mounts, but made for another class: held back with the class reason (a click still swaps).
		if ok and opt["id"] != "":
			var fit := ClassFit.verdict(session.drone_class, category, String(opt["id"]), _catalog)
			if not fit["fits"]:
				ok = false
				reason = String(fit["reason"])
		out[String(opt["id"])] = {"ok": ok, "reason": reason, "rank": rank}
	return out


## The Part sheet, while it is open (null otherwise): one part's tabs over the Design Space.
var part_sheet: PartSheet


## Opens `category`'s sheet (on `tab`, else its first tab). A second call replaces the open sheet.
## False for a category without a sheet or a tab it does not have.
func open_part_sheet(category: String, tab := "") -> bool:
	var tabs := PartSheetTabs.for_category(category)
	if tabs.is_empty():
		return false
	if tab == "":
		tab = String(tabs[0]["id"])
	if part_sheet != null and is_instance_valid(part_sheet):
		part_sheet.queue_free()
	var sheet := PartSheet.new(self, category)
	part_sheet = sheet
	sheet.closed.connect(func():
		if part_sheet == sheet:
			part_sheet = null
		sheet.queue_free())
	add_child(sheet)
	if not sheet.show_tab(tab):
		sheet.queue_free()
		part_sheet = null
		return false
	sheet.grab_focus()
	return true


## The form that enters a part the catalog does not stock (ESC, flight controller, camera, VTX, receiver,
## antenna), while it is open. The forms are the old Lab dialogs, unchanged; what they save lands in the
## custom stores the catalog merges, so the new part is on the shelf the moment the form saves.
var custom_form: AcceptDialog


## Opens the form for `category`; false for a category that has none. The saved part appears on the shelf.
func open_custom_part_form(category: String) -> bool:
	if custom_form != null and is_instance_valid(custom_form):
		custom_form.queue_free()
		custom_form = null
	var form: AcceptDialog
	match category:
		"esc":
			var e := CustomEscDialog.new()
			e.esc_saved.connect(func(_id: String): _custom_saved())
			form = e
		"flight_controller":
			var f := CustomFcDialog.new()
			f.fc_saved.connect(func(_id: String): _custom_saved())
			form = f
		"camera", "vtx", "receiver", "antenna":
			var c := CustomComponentDialog.new(category)
			c.component_saved.connect(func(_id: String): _custom_saved())
			form = c
		_:
			return false
	custom_form = form
	add_child(form)
	if form.is_inside_tree() and DisplayServer.get_name() != "headless":
		form.popup_centered()
	return true


func _custom_saved() -> void:
	refresh_catalog()
	if custom_form != null and is_instance_valid(custom_form):
		custom_form.queue_free()
		custom_form = null


## The pack designer pop-up, while it is open (null otherwise). Opened by the shelf's "+" tile.
var pack_designer: PackDesigner
## Where saved packs live; the pop-up writes here and the shelf reloads from here.
var custom_parts_path: String = CustomParts.SAVE_PATH
var pack_charge_path: String = PackCharge.SAVE_PATH


## Opens the pack designer over the Design Space: a new default pack, with this drone as the "this
## drone" load. A second call while it is open does nothing.
func open_pack_designer() -> void:
	if pack_designer != null:
		return
	cancel_drag()
	var store := DesignedPacks.load_from(custom_parts_path)
	var charge := PackCharge.load_from(pack_charge_path)
	var designer := PackDesigner.new(_catalog, CellLibrary.load_default(), store, charge, bench_build())
	designer.store_path = custom_parts_path
	designer.charge_path = pack_charge_path
	designer.saved.connect(func(_id: String): refresh_catalog())
	designer.closed.connect(func():
		pack_designer = null
		refresh_charge_chip())
	pack_designer = designer
	add_child(designer)
	designer.open_new()
	if designer.is_inside_tree():
		designer.grab_focus()


## The motor designer pop-up, while it is open (null otherwise). Opened by the motor shelf's
## "Design your own" tile.
var motor_designer: MotorDesigner


## Opens the motor designer over the Design Space on its default motor. A second call while it is
## open does nothing.
func open_motor_designer(saved_id: String = "") -> void:
	if motor_designer != null:
		return
	cancel_drag()
	# The store reads against the shipped catalog (its default), never _catalog: that one already
	# holds these very motors, and every record would be refused as colliding with itself.
	var designer := MotorDesigner.new(MotorConfigs.load_default(), _catalog,
		CustomMotors.load_from(custom_parts_path))
	designer.store_path = custom_parts_path
	# The bench runs on this drone's frame, prop and pack (the reference build's when there is none).
	var drone := bench_build()
	designer.set_bench_build(drone)
	if saved_id == "" and drone != null:
		designer.start_like(drone.motor)
	designer.saved.connect(func(_id: String): refresh_catalog())
	designer.closed.connect(func(): motor_designer = null)
	designer.design_pack_requested.connect(_design_pack_for_motor)
	motor_designer = designer
	add_child(designer)
	if saved_id != "":
		designer.open_motor(saved_id)
	if designer.is_inside_tree():
		designer.grab_focus()


## The prop designer pop-up, while it is open (null otherwise). Opened by the prop shelf's "+" tile.
var prop_designer: PropDesigner


## Opens the prop designer over the Design Space, starting from this drone's prop. A second call
## while it is open does nothing.
func open_prop_designer(saved_id: String = "", blade_path: String = "") -> void:
	if prop_designer != null:
		return
	cancel_drag()
	var designer := PropDesigner.new(_catalog, FrameMaterials.load_default(), bench_build(), session.drone_class)
	designer.store_path = custom_parts_path
	# A saved prop may be on this drone: the catalog is re-read, and session.build resolves from it.
	designer.saved.connect(func(_id: String):
		refresh_catalog()
		designer.set_catalog(_catalog))
	designer.fitted.connect(func(_id: String): _after_change())
	designer.set_session(session)
	designer.closed.connect(func(): prop_designer = null)
	prop_designer = designer
	add_child(designer)
	if saved_id != "":
		designer.open_prop(saved_id)
	elif blade_path != "":
		designer.open_blade_file(blade_path)
	var draft_problem := CustomPropellers.migration_problem(draft_migration)
	if draft_problem != "":
		designer.show_warning(draft_problem)
	if designer.is_inside_tree():
		designer.grab_focus()


## Where old drafts are read from, and what the last migration reported.
var blade_drafts_dir: String = BladeLibrary.DIRECTORY
var draft_migration: Dictionary = {}


## Brings old `user://blades` drafts onto the prop shelf. Called by the shell each time it opens the
## Design Space (a draft already brought over is remembered), not by _ready, so a test's Design Space
## never reads a drafts folder it did not ask for. Anything that failed shows on the designer's bar.
func migrate_old_drafts() -> void:
	draft_migration = CustomPropellers.migrate_drafts(custom_parts_path, blade_drafts_dir, FrameMaterials.load_default())
	if not (draft_migration["added"] as Array).is_empty():
		refresh_catalog()


## "Design a pack…" in the motor designer: the pack designer opens over it, and the pack it saves
## comes back selected on the motor bench (the designer gets the fresh catalog with it).
func _design_pack_for_motor() -> void:
	if motor_designer == null:
		return
	open_pack_designer()
	if pack_designer == null:
		return
	pack_designer.saved.connect(func(id: String):
		if motor_designer != null:
			motor_designer.select_pack(id, _catalog))


## The context menu of a saved motor's card (right-click): "Edit in designer" and "Delete". Delete
## asks twice, in the menu itself: the first press relabels it, the second deletes.
var card_menu: PopupMenu
var _card_menu_id := ""
var _card_menu_category := "motor"

func open_card_menu(category: String, part_id: String) -> void:
	if (category != "motor" and category != "propeller") or not PartsCatalog.is_custom(part_id):
		return
	_card_menu_category = category
	if card_menu == null:
		card_menu = PopupMenu.new()
		card_menu.name = "CardMenu"
		card_menu.hide_on_item_selection = false
		card_menu.id_pressed.connect(_on_card_menu)
		add_child(card_menu)
	_card_menu_id = part_id
	card_menu.clear()
	card_menu.add_item("Edit in designer", 0)
	card_menu.add_item("Delete", 1)
	if card_menu.is_inside_tree():
		card_menu.popup(Rect2i(Vector2i(get_global_mouse_position()) + get_window().position, Vector2i.ZERO))


func _on_card_menu(item: int) -> void:
	var id := _card_menu_id
	var is_prop := _card_menu_category == "propeller"
	if item == 0:
		card_menu.hide()
		if is_prop:
			open_prop_designer(id)
		else:
			open_motor_designer(id)
	elif delete_saved_prop(id) if is_prop else delete_saved_motor(id):
		card_menu.hide()
	elif is_prop and prop_delete_problem != "":
		card_menu.set_item_text(1, prop_delete_problem)
	else:
		card_menu.set_item_text(1, "Press again to delete")


## Deletes a saved motor, arm-then-confirm like the pack designer: false on the first call for an
## id, true when the second call deleted it. A motor fitted on this drone goes back to the class's
## own motor first, so the drone never names a part that is gone.
var _pending_motor_delete := ""

func delete_saved_motor(part_id: String) -> bool:
	if not PartsCatalog.is_custom(part_id):
		return false
	if _pending_motor_delete != part_id:
		_pending_motor_delete = part_id
		return false
	_pending_motor_delete = ""
	var store := CustomMotors.load_from(custom_parts_path)
	if not store.delete(part_id):
		return false
	if String(session.selection.get("motor", "")) == part_id:
		session.set_part("motor", String(DroneClass.parts_for(session.drone_class).get("motor", "")))
	refresh_catalog()
	return true


## Deletes a saved prop, arm-then-confirm. Refused, with prop_delete_problem set, when a saved motor
## names it as its thrust-test prop or the file cannot be written. A prop fitted on this drone goes
## back to the class's own first.
var _pending_prop_delete := ""
var prop_delete_problem := ""

func delete_saved_prop(p_part_id: String) -> bool:
	prop_delete_problem = ""
	if not PartsCatalog.is_custom(p_part_id):
		return false
	if _pending_prop_delete != p_part_id:
		_pending_prop_delete = p_part_id
		return false
	_pending_prop_delete = ""
	var store := CustomPropellers.load_from(custom_parts_path)
	if not store.remove_or_refuse(p_part_id, PartsCatalog.saved_motors(custom_parts_path)):
		prop_delete_problem = "A saved motor was tested with this prop"
		return false
	if not store.save(custom_parts_path):
		prop_delete_problem = "Could not write your parts file"
		return false
	if String(session.selection.get("propeller", "")) == p_part_id:
		session.set_part("propeller", String(DroneClass.parts_for(session.drone_class).get("propeller", "")))
	refresh_catalog()
	return true


## A pack was saved: read the catalog again with the builder's custom parts, so the new pack is on
## the shelf, and re-fill everything that reads it.
func refresh_catalog() -> void:
	_catalog = PartsCatalog.load_with_custom(custom_parts_path)
	_ranges_cache = {}
	_shelf_verdicts = {}
	_after_change()


func refresh_shelf() -> void:
	if shelf != null:
		shelf.fitted = _fitted_now()
		shelf.value_ranges = _value_ranges()
		shelf.fill(_shelf_groups())


var _ranges_cache := {}


## Each category's range of the value its icons show, over the whole catalogue (PartColour).
func _value_ranges() -> Dictionary:
	if _ranges_cache.is_empty():
		for cat in PartSnap.SHELF_CATEGORIES:
			_ranges_cache[cat] = PartColour.range_of(_catalog.list_category(cat), cat)
	return _ranges_cache


## The shelf's groups (PartSnap.shelf: catalog parts that are not fitted). While a part is selected,
## its categories also list the fitted part, so a swap can be seen against it and put back.
func _shelf_groups() -> Array:
	var groups := session.shelf(_catalog)
	var fitted := _fitted_now()
	for g in groups:
		var cat := String(g["category"])
		var id := String(fitted.get(cat, ""))
		if id == "":
			continue
		var part := _catalog.get_part(id)
		if part.is_empty():
			continue
		(g["parts"] as Array).append({"id": id, "name": String(part.get("name", id)),
			"numbers": PartSwap.deciding_numbers(part, cat),
			"caption": PartCaption.for_card(part, cat, String(part.get("name", id))), "part": part})
	return groups


## A part picked up off the shelf; the drag follows the pointer until it is released.
func begin_shelf_drag(part_id: String) -> void:
	cancel_drag()
	_drop_refusal()
	drag_kind = "shelf"
	drag_part = part_id
	clear_preview()


## A mounted part (its address) carried off the drone; released out of reach, it is removed.
func begin_off_drag(address: String) -> void:
	cancel_drag()
	_drop_refusal()
	if PartSnap.category_at(address) == "":
		return
	drag_kind = "off"
	drag_address = address


## The drop point under `screen_pos` (px), in the class GLB's root frame (PartSnap's space): where
## the ray first meets the drone, or else its closest approach to the drone's middle, so a release
## between the arms still counts and one well off the drone does not.
func drop_point(screen_pos: Vector2) -> Vector3:
	var ray := rig.ray(_ndc_of(screen_pos))
	var hits := picks.hits(ray["origin"], ray["dir"])
	var xf := doc_xf()
	if not hits.is_empty():
		return xf.affine_inverse() * (hits[0]["position"] as Vector3)
	var b: AABB = _mount_map.get("bounds", AABB())
	var c := xf * b.get_center()
	var o: Vector3 = ray["origin"]
	var d: Vector3 = (ray["dir"] as Vector3).normalized()
	var t := maxf((c - o).dot(d), 0.0)
	return xf.affine_inverse() * (o + d * t)


## The pointer moved while dragging: the drop it would make, shown (ghost and lit mount for a snap,
## the reason beside the cursor for a refusal, nothing out of reach). Returns the verdict.
func drag_over(screen_pos: Vector2) -> Dictionary:
	_clear_ghosts()
	drop_label.visible = false
	if drag_kind == "":
		drag_verdict = {}
		return {}
	var point := drop_point(screen_pos)
	if drag_kind == "off":
		var away := not PartSnap.in_reach(_mount_map, point)
		drag_verdict = {"kind": "remove" if away else "nothing", "mount": drag_address}
		_show_drop_label("Remove %s" % PickRegistry.display_name(drag_address) if away
			else "Drag off the drone to remove", INK, screen_pos)
		return drag_verdict
	drag_verdict = PartSnap.resolve(session, _catalog, drag_part, point, _mount_map)
	match String(drag_verdict["kind"]):
		"snap":
			_show_ghosts(drag_verdict)
			var to := PickRegistry.display_name(String(drag_verdict["mount"]))
			if (drag_verdict["mounts"] as Array).size() > 1:
				to = PickRegistry.PART_NAMES.get(String(drag_verdict["mount"]).split("/")[1], to) + " (all four)"
			_show_drop_label("On %s" % to, INK, screen_pos)
		"refused":
			_show_drop_label(String(drag_verdict["reason"]), WARN_INK, screen_pos)
	return drag_verdict


## Released: a snap attaches through the session (one undo step; the old part goes back on the
## shelf), a carried part released off the drone is removed, anything else changes nothing.
func end_drag(screen_pos: Vector2) -> Dictionary:
	var v := drag_over(screen_pos)
	var kind := drag_kind
	var part := drag_part
	var address := drag_address
	cancel_drag()
	_drag = ""
	# Pressed and released on the same card while a part is selected: a click, which swaps it in.
	if kind == "shelf" and swap_slot != "" and pointer_on_card(part, screen_pos):
		return click_card(String(shelf.row_of(part)["category"]), part)
	if kind == "shelf" and String(v.get("kind", "")) == "snap":
		var done := session.drop(_catalog, part, drop_point(screen_pos), _mount_map)
		_sync()
		return done
	if kind == "off" and String(v.get("kind", "")) == "remove":
		return _remove(address)
	if kind == "shelf" and String(v.get("kind", "")) == "refused":
		# A refused drop stays on the drone as a blocking pin on the mount it was refused at,
		# until the next change or drag.
		_refusal = WarningPins.of_refusal(v, _refusal_mount(String(v["category"]), drop_point(screen_pos)))
		refresh()
	return v


## Whether `screen_pos` (px, this control's own) is over the shelf card of `part_id`.
func pointer_on_card(part_id: String, screen_pos: Vector2) -> bool:
	var row := shelf.row_of(part_id)
	if row.is_empty():
		return false
	var b := row["button"] as Button
	return Rect2(_local_px(b.get_global_rect().position), b.size).has_point(screen_pos)


## The category's mount nearest the drop point (PartSnap's space); "" when it has none.
func _refusal_mount(category: String, point: Vector3) -> String:
	var best := ""
	var best_d := INF
	var mounts: Dictionary = _mount_map.get("mounts", {})
	for address in PartSnap.mounts_for(_mount_map, category):
		var d := point.distance_to(mounts[address]["centre"])
		if d < best_d:
			best_d = d
			best = address
	return best


func _drop_refusal() -> void:
	if not _refusal.is_empty():
		_refusal = {}
		refresh()


## Whether the ray through `ndc` meets `address` anywhere along it (in front or behind).
func _ray_meets(ndc: Vector2, address: String) -> bool:
	var ray := rig.ray(ndc)
	return picks.hits(ray["origin"], ray["dir"]).any(func(h): return String(h["address"]) == address)


func cancel_drag() -> void:
	drag_kind = ""
	drag_part = ""
	drag_address = ""
	drag_verdict = {}
	_clear_ghosts()
	if drop_label != null:
		drop_label.visible = false


## Delete: takes the selected part off the drone ({ok, reason}; the frame and non-parts refuse).
func remove_selected() -> Dictionary:
	if selected == "":
		return {"ok": false, "reason": "Nothing is selected."}
	return _remove(selected)


func _remove(address: String) -> Dictionary:
	var r := session.remove_at(address)
	if r["ok"]:
		_sync()
		if not picks.addresses().has(selected):
			select("")
	return r


## The ghost meshes now showing (for tests and captures).
func ghost_nodes() -> Array:
	return _ghosts.duplicate()


## The mount addresses lit for the current drag.
func lit_mounts() -> Array:
	return (drag_verdict.get("mounts", []) as Array).duplicate() if String(drag_verdict.get("kind", "")) == "snap" else []


func drop_hint_text() -> String:
	return drop_label.text if drop_label.visible else ""


func _show_drop_label(text: String, ink: Color, screen_pos: Vector2) -> void:
	drop_label.text = text
	drop_label.add_theme_color_override("font_color", ink)
	drop_label.reset_size()
	var at := screen_pos + DROP_LABEL_OFFSET
	var w := drop_label.get_combined_minimum_size().x
	# Beside the cursor, never over the readouts column: flip to the cursor's left when it would.
	if at.x + w > size.x - PickerPlace.COLUMN_W:
		at.x = maxf(screen_pos.x - DROP_LABEL_OFFSET.x - w, 16.0)
	drop_label.position = at
	drop_label.visible = text != ""


## A translucent copy of the part at each mount it would fill, drawn at the new part's catalog size
## (SwapLook on the trial selection), and the mount's own part outlined.
func _show_ghosts(v: Dictionary) -> void:
	var trial: Dictionary = session.selection.duplicate()
	trial[String(v["category"])] = String(v["part_id"])
	var t := SwapLook.transforms(_look_base, _drawn_selection, trial, _catalog)
	for address in v["mounts"]:
		var node_name := String(_mount_map["mounts"][address]["node"])
		var src := _doc_root.find_child(node_name, true, false) as MeshInstance3D
		if src == null:
			continue
		var g := MeshInstance3D.new()
		g.name = "Ghost_" + node_name
		g.mesh = src.mesh
		g.material_override = _ghost_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.transform = t[node_name]["xf"] if t.has(node_name) else src.transform
		src.get_parent().add_child(g)
		_ghosts.append(g)
		if src.visible:
			src.material_overlay = _select_mat
			_lit.append(src)


func _clear_ghosts() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			(g as Node).get_parent().remove_child(g)
			(g as Node).free()
	_ghosts.clear()
	for n in _lit:
		if is_instance_valid(n) and not _marked.has(n):
			(n as MeshInstance3D).material_overlay = null
	_lit.clear()


func _input(event: InputEvent) -> void:
	if visible and (event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey
			or event is InputEventPanGesture or event is InputEventMagnifyGesture):
		note_input()
	if drag_kind == "" or not visible:
		return
	if event is InputEventMouseMotion:
		drag_over(_local_px((event as InputEventMouseMotion).position))
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed:
		end_drag(_local_px((event as InputEventMouseButton).position))
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _local_px(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos if is_inside_tree() else viewport_pos


# ---------------------------------------------------------------------------
# Callouts that explain why (Section 8)
# ---------------------------------------------------------------------------

## Re-reads every callout's number off `b` (the build the panel just showed); {} without one.
func _refresh_callout_numbers(b: Build) -> void:
	_callout_numbers = {}
	_callout_version += 1
	if b == null:
		return
	for e in Callouts.TABLE:
		var t := Callouts.number_text(e, b)
		if t != "":
			_callout_numbers[String(e["id"])] = {"number": t,
				"confidence": Callouts.confidence_of(e, session, _catalog)}


func _rebuild_callout_hulls() -> void:
	_callout_hulls = []
	_callout_version += 1
	for entry in picks.entries:
		if entry["proxy"]:
			continue
		var mi := entry["node"] as MeshInstance3D
		var key := mi.mesh.get_rid()
		if not _hull_cache.has(key):
			_hull_cache[key] = Callouts.hull_points(mi.mesh)
		_callout_hulls.append((entry["xform"] as Transform3D) * (_hull_cache[key] as PackedVector3Array))


## The drone's silhouette now: one convex polygon (px) per drawn mesh.
func silhouette_polys() -> Array:
	return Callouts.silhouette(rig, _callout_hulls, size)


## Every on-screen rect a callout label must stay clear of (px): the back and home links, the
## readouts, and whichever of inspector, tool row, shelf and picker is showing. From offsets and
## minimum sizes, so it holds headless (where containers never lay out) as well as in the window.
func callout_avoid_rects() -> Array:
	var out: Array = []
	for b in [back_button, home_button, labels_button]:
		var c := b as Control
		var y0 := c.offset_top + (size.y if c.anchor_top == 1.0 else 0.0)
		out.append(Rect2(c.offset_left, y0, c.offset_right - c.offset_left, c.offset_bottom - c.offset_top))
	var ph := maxf(panel.offset_bottom - panel.offset_top, panel.get_combined_minimum_size().y)
	out.append(Rect2(size.x + panel.offset_left, panel.offset_top, panel.offset_right - panel.offset_left, ph))
	if inspector.visible:
		var ih := maxf(inspector.size.y, inspector.get_combined_minimum_size().y)
		out.append(Rect2(size.x + inspector.offset_left, size.y + inspector.offset_bottom - ih,
			inspector.offset_right - inspector.offset_left, ih))
	out.append_array(file_bar.rects(size))
	if side_drawer != null and is_instance_valid(side_drawer) and side_drawer.visible:
		out.append(side_drawer.avoid_rect())
	if tool_row.visible:
		var tm := tool_row.get_combined_minimum_size()
		out.append(Rect2(tool_row.offset_left, tool_row.offset_top, maxf(tool_row.offset_right - tool_row.offset_left, tm.x),
			maxf(tool_row.size.y, tm.y)))
	if shelf.visible:
		var sm := shelf.get_combined_minimum_size()
		out.append(Rect2(shelf.offset_left, shelf.offset_top, maxf(PartsShelf.WIDTH, sm.x), maxf(shelf.size.y, sm.y)))
	return out


## The frame loop's call: lays out again only when something the layout reads has changed (the
## shown camera, the size, hover, selection, the panels, the numbers or the meshes). A layout costs
## about 5 ms; a still frame costs a comparison.
func _update_callouts_if_moved() -> void:
	var inputs := [rig.yaw, rig.pitch, rig.distance, rig.target, size, hovered, selected, callout_focus,
		drag_kind, _callout_version, shelf.visible, side_drawer != null and is_instance_valid(side_drawer) and side_drawer.visible,
		file_bar.menu.visible,
		shelf.open, shelf.size, file_bar.dialog_open(), tool_row.visible, tool_row.size, inspector.visible, inspector.size,
		panel.size]
	if inputs == _callout_inputs:
		return
	_callout_inputs = inputs
	update_callouts()


## Where the k-th warning pin on `anchor` sits (px): the top of the part's box, then a step right
## for each further warning on the same part, so two pins on the battery are two dots.
func warning_pin_px(anchor: String, k: int) -> Vector2:
	var box := picks.box_of(anchor)
	var top := box.get_center() + Vector3(0.0, box.size.y * 0.5, 0.0)
	return PickerPlace.to_px(rig.project(top), size) + Vector2(WARN_PIN_STEP * k, 0.0)


## Lays the callouts out for the camera as it is now and hands them to the layer. Called every
## frame (pins track their parts while the camera eases or orbits), and by tests directly.
## Hidden with no build, while zoomed in, and during a drag.
func update_callouts() -> void:
	if callouts == null:
		return
	if (_callout_numbers.is_empty() and warning_pins.is_empty()) or rig.is_zoomed_in() \
			or drag_kind != "" or size.x <= 0.0:
		callouts.clear()
		return
	var have := picks.addresses()
	var items: Array = []
	var info := {}
	for i in Callouts.TABLE.size():
		var e: Dictionary = Callouts.TABLE[i]
		var id := String(e["id"])
		if not _callout_numbers.has(id) or not have.has(String(e["anchor"])):
			continue
		var expanded := callout_focus == id or Callouts.matches(e, hovered) or Callouts.matches(e, selected)
		var n: Dictionary = _callout_numbers[id]
		var lines := [String(e["why"]), "%s  \u00b7  %s" % [n["number"], n["confidence"]]]
		var pin := PickerPlace.to_px(rig.project(picks.box_of(String(e["anchor"])).get_center()), size)
		# The one being looked at is placed first, so a crowded view never drops it.
		items.append({"id": id, "kind": "callout", "pin": pin, "priority": -1 if expanded else i,
			"size": CalloutLayer.label_size(String(e["name"]), lines, expanded)})
		info[id] = {"number": i + 1, "name": String(e["name"]), "lines": lines, "expanded": expanded}
	# The warning pins, in the same layout so every no-overlap rule holds between the kinds. Placed
	# before any callout (blocking first), so a crowded view drops callouts, never a warning; the
	# cap is the callouts' six plus the warnings.
	var per_anchor := {}
	var n_warn := 0
	for i in warning_pins.size():
		var w: Dictionary = warning_pins[i]
		var anchor := _pin_anchor(w, have)
		if anchor == "":
			continue
		var k := int(per_anchor.get(anchor, 0))
		per_anchor[anchor] = k + 1
		var blocking := String(w["severity"]) == WarningPins.BLOCKING
		var wid := String(w["id"])
		items.append({"id": wid, "kind": "warning", "pin": warning_pin_px(anchor, k),
			"priority": (-200 if blocking else -100) + i,
			"size": CalloutLayer.label_size(String(w["tag"]), [], false)})
		info[wid] = {"number": 0, "name": String(w["tag"]), "lines": [], "expanded": false,
			"severity": String(w["severity"]), "solid": blocking, "tint": bool(w["tint"]), "anchor": anchor}
		n_warn += 1
	var placed: Array = Callouts.layout(items, silhouette_polys(), callout_avoid_rects(), size,
		Callouts.MAX_SHOWN + n_warn)
	for p in placed:
		p.merge(info[String(p["id"])])
	callouts.show_items(placed)


## The battery the chip speaks of: the last one clicked on the shelf, else the one fitted. "" if none.
func selected_battery() -> String:
	if _clicked_battery != "":
		return _clicked_battery
	return String(session.selection.get("battery", ""))


## Points the chip at the selected battery with its stored charge; hides it with none.
func refresh_charge_chip() -> void:
	if charge_chip == null:
		return
	var id := selected_battery()
	var part := _catalog.get_part(id) if id != "" else {}
	var specs: Dictionary = part.get("specs", {})
	var mah := float(specs.get("mah", 0.0))
	if part.is_empty() or mah <= 0.0:
		charge_chip.clear_pack()
		return
	var cells := int(specs.get("cells", 0))
	var text := "%s%dmAh" % ["%dS " % cells if cells > 0 else "", roundi(mah)]
	charge_chip.set_pack(id, text, mah, PackCharge.load_from(pack_charge_path).used_mah(id))


func _on_chip_charged(id: String) -> void:
	var charge := PackCharge.load_from(pack_charge_path)
	charge.set_used_mah(id, 0.0)
	charge.save(pack_charge_path)
