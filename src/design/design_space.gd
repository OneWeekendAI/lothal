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
const PICKER_W := 360.0
const PICKER_MAX_H := 430.0
## Readout delta bars: a delta of this size fills half the track.
const DELTA_SCALE := {"auw_g": 150.0, "thrust_to_weight": 4.0, "hover_throttle": 0.2,
	"flight_time_min": 3.0, "top_speed_kmh": 40.0}
const DELTA_TRACK_W := 120.0
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
var _pad_marker: MeshInstance3D
var _last_click_ndc := Vector2(INF, INF)
var _last_click_order: Array = []
## Click to swap (Section 3).
var picker: PanelContainer
var picker_slot := ""
var warnings_box: VBoxContainer
var delta_labels: Dictionary = {}
var delta_bars: Dictionary = {}
var previewing := {}
var _picker_list: VBoxContainer
var _picker_title: Label
var _picker_rows: Array = []
var _verdicts := {}
var _motor_hulls := {}
## The drawn parts (the class seed the model was built for) and each swappable node as drawn.
var _drawn_selection: Dictionary = {}
var _look_base: Dictionary = {}
var _look_nodes: Dictionary = {}
var _pack_label: Label3D
var _plain_wrap: StandardMaterial3D
## Frame edits (Section 4): the tool row, the active tool, and what the plates were as drawn.
var tool_row: FrameToolRow
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
var _pocket_from := Vector2.ZERO


func _init(p_session: DesignSession, p_catalog: PartsCatalog = null) -> void:
	session = p_session
	_catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	name = "DesignSpace"
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_stage()
	_build_panel()
	_build_inspector()
	_build_picker()
	_build_frame_tools()
	refresh()
	apply_look()


# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------

## Sets a part with no fit check and no history, and refreshes. The test seam for "the build
## changed"; the user's path is `choose`.
func set_part(category: String, part_id: String) -> bool:
	if not session.set_part(category, part_id):
		return false
	_after_change()
	return true


## Click to swap: fits `part_id` as `category` through the session (refused for a hard misfit,
## leaving everything as it was). Returns the verdict {ok, reason, ...}.
func choose(category: String, part_id: String) -> Dictionary:
	var verdict := session.swap(_catalog, category, part_id)
	if verdict["ok"]:
		_after_change()
	return verdict


func undo() -> bool:
	if not session.undo():
		return false
	_after_change()
	return true


func redo() -> bool:
	if not session.redo():
		return false
	_after_change()
	return true


## Everything a changed selection moves: readouts, the drawn parts, pick shapes, picker, inspector.
func _after_change() -> void:
	clear_preview()
	refresh()
	regenerate_frame()
	apply_look()
	if selected != "" and not picks.addresses().has(selected):
		selected = _plate_address_of(selected)
	_update_tool_row()
	if picker_slot != "":
		open_picker(picker_slot)
	if selected != "":
		_fill_inspector()


## Re-reads the session's build into the panel.
func refresh() -> void:
	var r := session.readouts(_catalog)
	var entry := DroneClass.by_id(session.drone_class)
	title_label.text = String(entry.get("name", "Drone"))
	var keys := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
	for key in keys:
		(value_labels[key] as Label).text = format_readout(key, r)
	for c in warnings_box.get_children():
		warnings_box.remove_child(c)
		c.queue_free()
	var b := session.build(_catalog)
	if b != null:
		var shown := 0
		for w in BuildWarning.by_severity(b.warnings()):
			if w.severity == BuildWarning.Severity.CHARACTERISTIC or shown >= 3:
				continue
			var l := Label.new()
			l.text = PartSwap.first_sentence(w.message)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
			l.add_theme_color_override("font_color", WARN_INK)
			warnings_box.add_child(l)
			shown += 1


## The panel's warning lines as text, for tests.
func warning_lines() -> Array:
	return warnings_box.get_children().map(func(l): return (l as Label).text)


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
	warnings_box.visible = false
	return previewing.duplicate()


func clear_preview() -> void:
	previewing = {}
	warnings_box.visible = true
	for key in delta_labels:
		(delta_labels[key] as Label).visible = false
		(delta_bars[key].get_parent() as Control).visible = false


## One readout as shown. Static so the tests can name the exact string.
static func format_readout(key: String, r: Dictionary) -> String:
	if not r.has(key):
		return "n/a"
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


func go_home() -> void:
	rig.go_home()


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
	hover_label.visible = hovered != ""
	hover_label.position = screen_pos + Vector2(16, 14)
	_apply_marks()
	return hovered


## Selects `address` ("" clears) and shows its numbers in the inspector.
func select(address: String) -> void:
	selected = address
	_fill_inspector()
	_apply_marks()
	_update_tool_row()
	var slot := PartSwap.slot_of(address)
	if slot != "":
		open_picker(slot)
	else:
		close_picker()


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


## Outlines the hovered and selected pieces: drawn meshes get an ink hull, holes and pockets (hidden
## proxies) are filled, a pad gets a filled disc on its arm. Monochrome; hover grey, selection white.
func _apply_marks() -> void:
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
				if frame_tool == "drill":
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
	elif key == KEY_H or key == KEY_HOME:
		go_home()
	elif key == KEY_BACKSPACE:
		back_requested.emit()
	elif key == KEY_ESCAPE:
		if frame_tool != "":
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
	place_picker()


## Eases the readouts panel out while zoomed in or framing a part, and back at normal distance.
func step_panel(delta: float) -> void:
	var want := 0.0 if rig.is_zoomed_in() else 1.0
	panel_alpha = move_toward(panel_alpha, want, delta / PANEL_FADE_S)
	# smoothstep gives the ease; the panel never takes clicks, so nothing else changes.
	panel.modulate.a = smoothstep(0.0, 1.0, panel_alpha)


func apply_camera() -> void:
	camera.fov = CameraRig.FOV_DEG
	camera.near = rig.near()
	camera.far = rig.far()
	camera.global_transform = Transform3D(rig.basis(), rig.position())


# ---------------------------------------------------------------------------
# The stage (the picker's look)
# ---------------------------------------------------------------------------

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

	_stage = Node3D.new()
	_stage.name = "StageRoot"
	viewport.add_child(_stage)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.31, 0.33)
	sky_mat.sky_horizon_color = Color(0.52, 0.52, 0.54)
	sky_mat.ground_horizon_color = Color(0.20, 0.20, 0.21)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.06)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = STAGE_BG
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.40
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = ClassPicker.EXPOSURE
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
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
	key.light_angular_distance = 0.8
	key.shadow_blur = 1.6
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 3.0
	key.shadow_normal_bias = 1.0
	key.shadow_bias = 0.02
	key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0.0)
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(65.0), 0.0)
	_stage.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.6
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(165.0), 0.0)
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


# ---------------------------------------------------------------------------
# The panel: five numbers, nothing else
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	panel = VBoxContainer.new()
	panel.name = "Readouts"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -300
	panel.offset_right = -40
	panel.offset_top = 48
	panel.offset_bottom = 400
	panel.add_theme_constant_override("separation", 14)
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

	var rows := [["auw_g", "All-up weight"], ["thrust_to_weight", "Thrust to weight"],
		["hover_throttle", "Hover throttle"], ["flight_time_min", "Flight time (est.)"],
		["top_speed_kmh", "Top speed (est.)"]]
	for row in rows:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := Label.new()
		cap.text = String(row[1])
		cap.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		cap.add_theme_color_override("font_color", INK_MUTED)
		box.add_child(cap)
		var val := Label.new()
		val.name = String(row[0])
		val.add_theme_font_size_override("font_size", 26)
		val.add_theme_color_override("font_color", INK)
		box.add_child(val)
		var dl := Label.new()
		dl.name = "delta_" + String(row[0])
		dl.visible = false
		dl.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		dl.add_theme_color_override("font_color", INK_MUTED)
		box.add_child(dl)
		var track := Control.new()
		track.custom_minimum_size = Vector2(DELTA_TRACK_W, 3)
		track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
		panel.add_child(box)
		value_labels[row[0]] = val
		delta_labels[row[0]] = dl
		delta_bars[row[0]] = bar

	warnings_box = VBoxContainer.new()
	warnings_box.name = "Warnings"
	warnings_box.add_theme_constant_override("separation", 4)
	warnings_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(warnings_box)

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
	home_button.pressed.connect(go_home)
	add_child(home_button)

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
	back_button.pressed.connect(func(): back_requested.emit())
	add_child(back_button)


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
	# No seam yet: the Airframe room opens on Lab's own frame document (FrameWorkbench.open_fitted),
	# and nothing hands a Design Space document back. Labelled, not hidden.
	tool_row.plan_button.disabled = true
	tool_row.plan_button.text = "Plan editor (not yet)"
	tool_row.plan_button.tooltip_text = "Opening this frame in the Airframe room is not wired yet."


## Whether the tool row shows: a frame region of an editable frame (the 5") is the selection.
func frame_tools_shown() -> bool:
	return tool_row != null and tool_row.visible


func _update_tool_row() -> void:
	if tool_row == null:
		return
	var want := selected.begins_with("frame/") and session.frame_editable()
	tool_row.visible = want
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
		_after_change()
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
	return node != null and node.mesh != _glb_meshes.get(String(node.name))


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
	if not edited:
		node.mesh = _glb_meshes[mesh_name]
		for proxy in glb:
			if (proxy as Node).get_parent() == null:
				parent.add_child(proxy)
		return
	for proxy in glb:
		if (proxy as Node).get_parent() != null:
			(proxy as Node).get_parent().remove_child(proxy)
	var mat := (_glb_meshes[mesh_name] as Mesh).surface_get_material(0)
	var turn := String(plate.get("role", "")) != AirframeDocument.ROLE_ARM
	node.mesh = FrameView.plate_mesh(plate, PickRegistry._xform_to(node, _doc_root).affine_inverse(), mat, turn)
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
# The swap picker (Section 3)
# ---------------------------------------------------------------------------

func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.name = "SwapPicker"
	picker.visible = false
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.065, 0.96)
	sb.border_color = INK_FAINT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	picker.add_theme_stylebox_override("panel", sb)
	add_child(picker)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	picker.add_child(vb)
	_picker_title = Label.new()
	_picker_title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	_picker_title.add_theme_color_override("font_color", INK)
	vb.add_child(_picker_title)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(PICKER_W - 24.0, 0)
	vb.add_child(scroll)
	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_picker_list)


## Opens the picker for a pick slot ("battery", "motor", "stack", ...): every catalog alternative
## with its deciding numbers, the fitted one marked, misfits disabled with their reason.
func open_picker(slot: String) -> void:
	if not PartSwap.SLOTS.has(slot):
		close_picker()
		return
	picker_slot = slot
	for c in _picker_list.get_children():
		_picker_list.remove_child(c)
		c.queue_free()
	_picker_rows.clear()
	_picker_title.text = "Swap  \u00b7  %s" % PickRegistry.PART_NAMES.get(slot, slot)
	var cats: Array = PartSwap.SLOTS[slot]
	var height := 0.0
	for cat in cats:
		if cats.size() > 1:
			var head := Label.new()
			head.text = String(PartSwap.CATEGORY_NAMES.get(cat, cat)).to_upper()
			head.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
			head.add_theme_color_override("font_color", INK_FAINT)
			_picker_list.add_child(head)
			height += head.get_combined_minimum_size().y + _picker_sep()
		for opt in PartSwap.options(session, _catalog, String(cat), _verdicts):
			height += _add_row(opt)
	var scroll := _picker_list.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = minf(maxf(height - _picker_sep(), 0.0), PICKER_MAX_H)
	picker.reset_size()
	picker.visible = true
	_make_room_for_picker()
	place_picker()
	var fitted := _picker_rows.map(func(r): return r["fitted"]).find(true)
	reveal_row(maxi(fitted, 0))


func _add_row(opt: Dictionary) -> float:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	var numbers := " · ".join(PackedStringArray(opt["numbers"]))
	if opt["fitted"]:
		numbers = (numbers + "  ·  fitted") if numbers != "" else "fitted"
	b.text = String(opt["name"]) + ("\n" + numbers if numbers != "" else "")
	b.disabled = not opt["ok"]
	b.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	b.add_theme_color_override("font_color", INK if opt["fitted"] else INK_MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.06)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(6)
	var plain := StyleBoxEmpty.new()
	plain.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", (hover as StyleBox) if opt["fitted"] else (plain as StyleBox))
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", plain)
	var row := opt.duplicate()
	row["button"] = b
	row["reason_label"] = null
	var i := _picker_rows.size()
	b.mouse_entered.connect(func(): hover_row(i))
	b.mouse_exited.connect(clear_preview)
	b.pressed.connect(func(): press_row(i))
	_picker_list.add_child(b)
	var h := b.get_combined_minimum_size().y + _picker_sep()
	if not opt["ok"]:
		var why := Label.new()
		why.text = String(opt["reason"])
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(PICKER_W - 48.0, 0)
		why.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
		why.add_theme_color_override("font_color", WARN_INK)
		why.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_picker_list.add_child(why)
		row["reason_label"] = why
		h += why.get_combined_minimum_size().y + _picker_sep()
	_picker_rows.append(row)
	return h


func close_picker() -> void:
	picker_slot = ""
	picker.visible = false
	clear_preview()


## The picker's rows, for tests and the seams below: {category, id, name, ok, reason, fitted,
## deltas, button, reason_label}.
func picker_rows() -> Array:
	return _picker_rows


## The pointer over a row: preview its readout deltas (nothing for a disabled row).
func hover_row(i: int) -> Dictionary:
	var row: Dictionary = _picker_rows[i]
	reveal_row(i)
	if (row["button"] as Button).disabled:
		clear_preview()
		return {}
	return preview(String(row["category"]), String(row["id"]))


## A row chosen. A disabled row does nothing, and `choose` judges again regardless.
func press_row(i: int) -> Dictionary:
	var row: Dictionary = _picker_rows[i]
	if (row["button"] as Button).disabled:
		return {"ok": false, "reason": row["reason"]}
	return choose(String(row["category"]), String(row["id"]))


## Keeps the picker beside the drone (never over it) and near the selected part, clear of the
## right column (readouts, inspector). Placed for the view the camera is easing to. When the picker
## has closed, gives back any room the camera made for it (see `_make_room_for_picker`).
func place_picker() -> void:
	if picker == null:
		return
	if not picker.visible:
		_give_back_room()
		return
	if selected == "":
		return
	_finish_reveal()
	var view := PickerPlace.settled(rig)
	var p := PickerPlace.to_px(view.project(picks.box_of(selected).get_center()), size)
	var w := maxf(picker.size.x, PICKER_W)
	var h := picker.size.y
	var x := PickerPlace.side_x(PickerPlace.screen_rect(view, _mesh_aabbs(), size), w, size, p.x)
	if is_nan(x):
		# No side clear of the drone (zoomed in, or the user moved the camera): beside the part.
		x = p.x + 48.0
		if x + w > size.x - PickerPlace.COLUMN_W:
			x = p.x - 48.0 - w
		x = clampf(x, PickerPlace.MARGIN, maxf(size.x - PickerPlace.COLUMN_W - w, PickerPlace.MARGIN))
	picker.position = Vector2(x, PickerPlace.near_y(p.y, h, size))


# ---------------------------------------------------------------------------
# Swap picker placement and scrolling helpers (Section 3 fixes)
# ---------------------------------------------------------------------------

var _room_before := {}         ## the camera goal before the picker made room; {} when it made none
var _room_goal := {}           ## the goal it set, to tell whether the user has moved since
var _reveal_pending := -1      ## a row to reveal again while the list is being laid out
var _reveal_frames := 0


## The drone on screen now: the union of every drawn mesh's box, its 8 corners projected (px).
func drone_screen_rect() -> Rect2:
	return PickerPlace.screen_rect(rig, _mesh_aabbs(), size)


func _mesh_aabbs() -> Array:
	return mesh_boxes().map(func(e): return e["box"])


func _picker_sep() -> float:
	return float(_picker_list.get_theme_constant("separation"))


## The list's full height, summed from its children (the list's own cached minimum size is stale
## until the deferred layout runs, and never refreshes headless).
func _picker_content_h() -> float:
	var y := 0.0
	for c in _picker_list.get_children():
		y += (c as Control).get_combined_minimum_size().y + _picker_sep()
	return maxf(y - _picker_sep(), 0.0)


func _picker_scroll() -> ScrollContainer:
	return _picker_list.get_parent() as ScrollContainer


## At a view where neither side of the drone has room for the picker, backs the camera off and
## slides the drone left until the picker fits beside it. Not while zoomed in or framing a part.
func _make_room_for_picker() -> void:
	if rig.is_zoomed_in() or size.x <= 0.0:
		return
	var w := maxf(picker.size.x, PICKER_W)
	var view := PickerPlace.settled(rig)
	var p := PickerPlace.to_px(view.project(picks.box_of(selected).get_center()), size)
	if not is_nan(PickerPlace.side_x(PickerPlace.screen_rect(view, _mesh_aabbs(), size), w, size, p.x)):
		return
	if _room_before.is_empty():
		_room_before = {"target": rig.goal_target, "distance": rig.goal_distance}
	var g := PickerPlace.room_goal(rig, _mesh_aabbs(), size, w)
	rig.goal_target = g["target"]
	rig.goal_distance = g["distance"]
	_room_goal = g


## The picker closed: the camera goes back, unless the user moved it since it made room.
func _give_back_room() -> void:
	if _room_before.is_empty():
		return
	if rig.goal_target.is_equal_approx(_room_goal["target"]) and is_equal_approx(rig.goal_distance, _room_goal["distance"]):
		rig.goal_target = _room_before["target"]
		rig.goal_distance = _room_before["distance"]
	_room_before = {}
	_room_goal = {}


## Row i's span in the list (px from the list's top): its button and any reason line under it.
## From minimum sizes: a VBox with no expanding children gives each child exactly its minimum
## height, so this is the layout itself, and it holds before the deferred layout has run (and
## headless, where it never runs).
func picker_row_span(i: int) -> Vector2:
	var row: Dictionary = _picker_rows[i]
	var b := row["button"] as Button
	var last: Control = row["reason_label"] if row["reason_label"] != null else b
	var y := 0.0
	var top := 0.0
	for c in _picker_list.get_children():
		var hc := (c as Control).get_combined_minimum_size().y
		if c == b:
			top = y
		if c == last:
			return Vector2(top, y + hc)
		y += hc + _picker_sep()
	return Vector2.ZERO


## Scrolls the picker so row i shows whole (the least move; nothing if it already shows), and
## again over the next few frames: a wrapped reason line only knows its height once laid out.
func reveal_row(i: int) -> void:
	_reveal_pending = i
	_reveal_frames = 3
	_apply_reveal(i)


func _apply_reveal(i: int) -> void:
	if i < 0 or i >= _picker_rows.size():
		return
	var scroll := _picker_scroll()
	var span := picker_row_span(i)
	var view_h := scroll.custom_minimum_size.y
	var content := _picker_content_h()
	var bar := scroll.get_v_scroll_bar()
	# Before the deferred layout the bar still has the old list's range; give it this one's.
	bar.max_value = content
	bar.page = view_h
	var want := PickerPlace.reveal(span.x, span.y, view_h, float(scroll.scroll_vertical))
	scroll.scroll_vertical = int(roundf(clampf(want, 0.0, maxf(content - view_h, 0.0))))


func _finish_reveal() -> void:
	if _reveal_pending < 0:
		return
	_apply_reveal(_reveal_pending)
	_reveal_frames -= 1
	if _reveal_frames <= 0:
		_reveal_pending = -1
