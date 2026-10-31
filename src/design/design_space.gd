class_name DesignSpace
extends Control
## The Design Space stage: the chosen class's model on the picker's dark studio, a free camera, and
## a calm side panel of live readouts. Nothing here computes a physical number: the panel reads the
## session's `Build` (DesignSession.readouts) every time the selection changes.
##
## Camera: drag orbits; shift+drag, right drag or middle drag pans; wheel or pinch zooms toward the
## cursor; trackpad two-finger scroll orbits; double-click a part frames it; H (or the Home button)
## eases back to the isometric view; Esc leaves. Picking by double-click is a ray against each mesh's
## bounding box (smallest box wins): good enough to frame a part, and replaced by real picking in
## Section 2.

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

var _catalog: PartsCatalog
var _stage: Node3D
var _tex: TextureRect
var _drag := ""
var _model_path := ""


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
	refresh()


# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------

## Swaps a part and refreshes the readouts. The test seam for "the build changed".
func set_part(category: String, part_id: String) -> bool:
	if not session.set_part(category, part_id):
		return false
	refresh()
	return true


## Re-reads the session's build into the panel.
func refresh() -> void:
	var r := session.readouts(_catalog)
	var entry := DroneClass.by_id(session.drone_class)
	title_label.text = String(entry.get("name", "Drone"))
	var keys := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
	for key in keys:
		(value_labels[key] as Label).text = format_readout(key, r)


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


## The world-space bounds of every mesh of the model, by mesh.
func mesh_boxes() -> Array:
	var out: Array = []
	if model == null:
		return out
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model.get_parent():
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append({"name": String(mi.name), "box": xf * mi.get_aabb()})
	return out


## The part under the screen point `ndc`: {name, box} or {} (smallest hit box wins).
func pick(ndc: Vector2) -> Dictionary:
	var ray := rig.ray(ndc)
	var best := {}
	var best_vol := INF
	for entry in mesh_boxes():
		var box := entry["box"] as AABB
		if box.intersects_ray(ray["origin"], ray["dir"]) == null:
			continue
		var vol := box.size.x * box.size.y * box.size.z
		if vol < best_vol:
			best_vol = vol
			best = entry
	return best


## Double-click: frames the part under `ndc`. False if the click hit nothing.
func frame_at(ndc: Vector2) -> bool:
	var hit := pick(ndc)
	if hit.is_empty():
		return false
	rig.frame(hit["box"])
	return true


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
					if mb.double_click:
						frame_at(_ndc_of(mb.position))
					_drag = "pan" if mb.shift_pressed else "orbit"
				MOUSE_BUTTON_RIGHT:
					_drag = "pan"
				MOUSE_BUTTON_MIDDLE:
					_drag = "pan" if mb.shift_pressed else "orbit"
			grab_focus()
		else:
			_drag = ""
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		var rel := (event as InputEventMouseMotion).relative
		if _drag == "orbit":
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
	var key := (event as InputEventKey).keycode
	if key == KEY_H or key == KEY_HOME:
		go_home()
	elif key == KEY_BACKSPACE:
		back_requested.emit()
	elif key == KEY_ESCAPE:
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
	_stage.add_child(model)


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
		panel.add_child(box)
		value_labels[row[0]] = val

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
