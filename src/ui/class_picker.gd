class_name ClassPicker
extends Control
## "Choose your drone class": the first screen of a new project.
##
## A carousel, one class at a time: `<  [DRONE]  >`. The class's Blender model (assets/models/
## classes/<id>.glb) turns slowly on a dark studio sweep. Under it: the class name, its wheelbase,
## its typical figures and the catalog parts it starts from, and one Choose button. Nothing here
## computes a physical number.
##
## ## Every class is framed large; the size row tells the size
##
## The camera distance is fitted to the class on show (its turntable circle, from the model's own
## bounds) so the drone fills FILL_WIDTH of the viewport width, whatever the class. A speck of a
## Tiny Whoop teaches nothing. Size is carried by a row of ten grey discs under the name, drawn at
## true relative wheelbase, with the current class lit, plus the wheelbase in mm. The suite pins both.
##
## ## Render quality
##
## The 3D is drawn at the window's real pixel size (the project stretches 2D by canvas_items, which
## would upscale a viewport sized in UI units), through a TextureRect that maps it back 1:1. 4x MSAA
## plus FXAA, key/fill/rim lights with a PCSS-soft key shadow, SSAO, a contact-shadow blob and a
## floor that fades into the background.

signal class_chosen(class_id: String)
signal dismissed

## Top-left way out; emits `dismissed`, as Esc does.
var back_button: Button

## Turntable speed. Slow: a model that spins fast reads as a loading indicator.
const TURN_RAD_S := 0.30
## Camera pitch below the horizon.
const PITCH_RAD := deg_to_rad(25.0)
const FOV_DEG := 24.0
## The class on show: its turntable circle spans this fraction of the viewport width.
const FILL_WIDTH := 0.56
## Size row: the X-Class disc's diameter in UI pixels; the rest scale by wheelbase.
const SIZE_ROW_MAX_PX := 30.0
## Where the drone stands on screen, as a fraction of the stage height from the top.
const STAGE_CENTRE_Y := 0.40

## Tonemap exposure. AgX with the key at KEY_ENERGY keeps black carbon dark and the grey props grey.
const EXPOSURE := 0.95
const KEY_ENERGY := 1.4

const INK := Color(0.93, 0.93, 0.93)
const INK_MUTED := Color(0.58, 0.58, 0.58)
const INK_FAINT := Color(0.34, 0.34, 0.34)
const STAGE_BG := Color(0.035, 0.035, 0.038)

const FLOOR_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, shadows_disabled;
uniform float fade_radius = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = vec3(0.020, 0.020, 0.022);
	ROUGHNESS = 0.92;
	SPECULAR = 0.0;
	float d = length(wp.xz) / fade_radius;
	ALPHA = clamp(1.0 - smoothstep(0.25, 1.0, d), 0.0, 1.0);
}
"""

## The class on show, in DroneClass.CLASSES order.
var current_id := DroneClass.DEFAULT_ID
## class id -> the class's turntable pivot (loaded on first show; scale always 1).
var models: Dictionary = {}
var viewport: SubViewport
var camera: Camera3D
var slot: Node3D
var name_label: Label
var size_label: Label
var details_label: Label
var parts_label: Label
var warning_label: Label
var choose_button: Button
var prev_button: Button
var next_button: Button

var _catalog: PartsCatalog
var _stage: Node3D
var _size_row: Control
var _tex: TextureRect
var _key: DirectionalLight3D
var _env: Environment
var _floor_mat: ShaderMaterial
var _blob: MeshInstance3D
var _radius: Dictionary = {}
## Metres per viewport pixel at the drone's depth. Set from the largest class only.
var _m_per_px := 0.0
var _distance := 3.0
var _turn := 0.0


func _init(p_catalog: PartsCatalog = null) -> void:
	_catalog = p_catalog if p_catalog != null else PartsCatalog.load_default()
	name = "ClassPicker"
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_stage()
	_build_layout()
	show_class(DroneClass.DEFAULT_ID)


# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------

## Shows a class. False for an unknown id.
func show_class(class_id: String) -> bool:
	if DroneClass.by_id(class_id).is_empty():
		return false
	current_id = class_id
	_ensure_model(class_id)
	for id in models:
		(models[id] as Node3D).visible = id == current_id
	fit_camera(Vector2(viewport.size))
	_stage_for(class_id)
	_refresh_text()
	return true


## Steps `direction` (+1 bigger, -1 smaller) through the classes in size order. Stops at the ends
## rather than wrapping: a wrap would put an X-Class next to a Tiny Whoop and break the order the
## screen teaches. Returns false at an end.
func step(direction: int) -> bool:
	var order := DroneClass.ids()
	var index := order.find(current_id) + signi(direction)
	if index < 0 or index >= order.size():
		return false
	return show_class(order[index])


## Commits the class on show (or `class_id`): the picker's one outcome.
func choose(class_id: String = "") -> bool:
	var id := class_id if class_id != "" else current_id
	if not DroneClass.is_available(id):
		return false
	current_id = id
	class_chosen.emit(id)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_left"):
		step(-1)
	elif event.is_action_pressed("ui_right"):
		step(1)
	elif event.is_action_pressed("ui_accept"):
		choose()
	elif event.is_action_pressed("ui_cancel"):
		dismissed.emit()
	else:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_turn = fmod(_turn + TURN_RAD_S * minf(delta, 0.1), TAU)
	if models.has(current_id):
		(models[current_id] as Node3D).rotation.y = _turn
	if viewport != null and is_inside_tree():
		# Real window pixels, not UI units: canvas_items stretching would otherwise upscale the 3D.
		var sc := get_viewport().get_final_transform().get_scale()
		var px := Vector2i(maxi(int(size.x * sc.x), 16), maxi(int(size.y * sc.y), 16))
		if viewport.size != px:
			viewport.size = px
		fit_camera(Vector2(px))
	# Pre-load the neighbours, one per frame, so the arrows never stall on a parse.
	var order := DroneClass.ids()
	var i := order.find(current_id)
	for j in [i + 1, i - 1]:
		if j >= 0 and j < order.size() and not models.has(order[j]):
			_ensure_model(order[j])
			(models[order[j]] as Node3D).visible = false
			break


## Sets the camera for a viewport of `vp_size` pixels, fitted to the class on show.
func fit_camera(vp_size: Vector2) -> void:
	if vp_size.x <= 0.0 or vp_size.y <= 0.0 or _radius_of_shown() <= 0.0:
		return
	var tan_half := tan(deg_to_rad(FOV_DEG) * 0.5)
	var width_units := vp_size.x / vp_size.y                    # in units of the viewport height
	var r := _radius_of_shown()
	_distance = 2.0 * r / (FILL_WIDTH * width_units * 2.0 * tan_half)
	camera.fov = FOV_DEG
	var visible_h := 2.0 * _distance * tan_half
	_m_per_px = visible_h / vp_size.y
	# Aim so the floor origin (where the drone stands) lands STAGE_CENTRE_Y down the stage.
	var lift := (0.5 - STAGE_CENTRE_Y) * visible_h
	var forward := Vector3(0.0, -sin(PITCH_RAD), -cos(PITCH_RAD))
	var up := Vector3(0.0, cos(PITCH_RAD), -sin(PITCH_RAD))
	camera.position = -forward * _distance - up * lift
	camera.near = maxf(_distance - r * 2.5, 0.005)
	camera.far = _distance + r * 4.0


func metres_per_pixel() -> float:
	return _m_per_px


func _radius_of_shown() -> float:
	return float(_radius.get(current_id, 0.0))


## Fraction of the viewport width the class on show's turntable circle spans at `vp_size`.
func fitted_width_fraction(vp_size: Vector2) -> float:
	fit_camera(vp_size)
	if _m_per_px <= 0.0:
		return 0.0
	return 2.0 * _radius_of_shown() / _m_per_px / vp_size.x


## The size row as data: one entry per class, {id, diameter_px, current}. Diameters are in true
## relative wheelbase.
func size_row() -> Array:
	var out: Array = []
	var widest := 0.0
	for entry in DroneClass.CLASSES:
		widest = maxf(widest, float(entry["wheelbase_mm"]))
	for entry in DroneClass.CLASSES:
		out.append({"id": entry["id"], "diameter_px": SIZE_ROW_MAX_PX * float(entry["wheelbase_mm"]) / widest,
			"current": entry["id"] == current_id})
	return out


## A class's turntable radius (from its model's own bounds). Loads the model if needed.
func radius_m(class_id: String) -> float:
	_ensure_model(class_id)
	return float(_radius.get(class_id, 0.0))


## Loads every class's model (the tests and the capture tool want all ten).
func load_all() -> void:
	for id in DroneClass.ids():
		_ensure_model(id)
		(models[id] as Node3D).visible = id == current_id


# ---------------------------------------------------------------------------
# The stage
# ---------------------------------------------------------------------------

func _build_stage() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_taa = false
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

	# Neutral studio environment: a dim grey gradient sky gives the carbon and anodised metal
	# something to reflect; the background itself stays a flat near-black.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.31, 0.33)
	sky_mat.sky_horizon_color = Color(0.52, 0.52, 0.54)
	sky_mat.ground_horizon_color = Color(0.20, 0.20, 0.21)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.06)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = STAGE_BG
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.40
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = EXPOSURE
	_env.tonemap_white = 6.0
	_env.ssao_enabled = true
	_env.ssao_intensity = 2.0
	_env.ssao_power = 1.6
	_env.ssao_detail = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	_stage.add_child(world_env)

	# Studio lighting: a soft-shadowing key from front-left, a fill from the right, a rim from behind.
	_key = DirectionalLight3D.new()
	_key.name = "Key"
	_key.light_energy = KEY_ENERGY
	_key.shadow_enabled = true
	_key.light_angular_distance = 0.8
	_key.shadow_blur = 1.6
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key.shadow_normal_bias = 1.0
	_key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0.0)
	_stage.add_child(_key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.45
	fill.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(65.0), 0.0)
	_stage.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_energy = 1.6
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(165.0), 0.0)
	_stage.add_child(rim)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	var floor_shader := Shader.new()
	floor_shader.code = FLOOR_SHADER
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = floor_shader
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = floor_mesh
	floor_node.material_override = _floor_mat
	_stage.add_child(floor_node)

	# Soft contact shadow: a radial-gradient blob just above the floor, under the drone.
	var grad := Gradient.new()
	# Gaussian-like falloff (many stops) so the edge has no visible ring or band.
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
	_blob = MeshInstance3D.new()
	_blob.name = "ContactShadow"
	_blob.mesh = blob_mesh
	_blob.material_override = blob_mat
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.position.y = 0.0004
	_stage.add_child(_blob)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = FOV_DEG
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.rotation = Vector3(-PITCH_RAD, 0.0, 0.0)
	camera.current = true
	_stage.add_child(camera)

	slot = Node3D.new()
	slot.name = "Slot"
	_stage.add_child(slot)

	_ensure_model(current_id)
	fit_camera(Vector2(1280, 720))


## Loads a class's model (imported scene when the editor has imported it, else straight from the
## .glb) into a turntable pivot at scale 1, standing on y=0 and centred on its own bounds.
func _ensure_model(class_id: String) -> void:
	if models.has(class_id):
		return
	var path := DroneClass.model_path(class_id)
	var root: Node = null
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			root = scene.instantiate()
	if root == null:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			root = doc.generate_scene(state)
	var pivot := Node3D.new()
	pivot.name = "Model_" + class_id
	if root != null:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		pivot.add_child(root)
		_sharpen_materials(root)
		PickRegistry.hide_proxies(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).visible:
				continue
			var inst := mi as MeshInstance3D
			var xf := _relative_transform(inst, root)
			var box := xf * inst.get_aabb()
			lo = lo.min(box.position)
			hi = hi.max(box.end)
		if lo.x < INF:
			var centre := (lo + hi) * 0.5
			root.position = Vector3(-centre.x, -lo.y, -centre.z)
			_radius[class_id] = 0.5 * Vector2(hi.x - lo.x, hi.z - lo.z).length()
	slot.add_child(pivot)
	models[class_id] = pivot


## Anisotropic filtering on every imported texture, so the carbon weave survives the 3/4 angle.
## The materials themselves are left as the GLB imported them (albedo, roughness, normal).
func _sharpen_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var mat := inst.mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null:
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root.get_parent():
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Fits the stage furniture (shadow range, SSAO radius, floor fade, contact shadow) to the class.
func _stage_for(class_id: String) -> void:
	var r := float(_radius.get(class_id, 0.1))
	_blob.scale = Vector3(r * 3.2, 1.0, r * 3.2)
	_floor_mat.set_shader_parameter("fade_radius", r * 3.2)
	_env.ssao_radius = clampf(r * 0.10, 0.004, 0.08)
	_key.directional_shadow_max_distance = _distance + r * 2.5
	_key.shadow_bias = 0.02


# ---------------------------------------------------------------------------
# The layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	var title := Label.new()
	title.text = "Choose your drone class"
	title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", INK_MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 32
	title.offset_bottom = 60
	add_child(title)

	# Back: top-left on the title's row, well clear of the big ‹ arrow at mid-height. The same
	# signal as Esc, so the shell has one place that decides where "back" goes.
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "‹ Back"
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.position = Vector2(32, 28)
	back_button.custom_minimum_size = Vector2(0, 32)
	back_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	back_button.add_theme_color_override("font_color", INK_MUTED)
	back_button.add_theme_color_override("font_hover_color", INK)
	back_button.add_theme_color_override("font_pressed_color", INK)
	back_button.pressed.connect(func() -> void: dismissed.emit())
	add_child(back_button)

	prev_button = _arrow_button("‹", -1)
	prev_button.anchor_left = 0.0
	prev_button.anchor_right = 0.0
	prev_button.offset_left = 40
	prev_button.offset_right = 96
	add_child(prev_button)
	next_button = _arrow_button("›", 1)
	next_button.anchor_left = 1.0
	next_button.anchor_right = 1.0
	next_button.offset_left = -96
	next_button.offset_right = -40
	add_child(next_button)

	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -440
	bottom.offset_right = 440
	bottom.offset_top = -262
	bottom.offset_bottom = -32
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	name_label = _centred_label(LothalTheme.FONT_SIZE_HERO, INK)
	bottom.add_child(name_label)
	size_label = _centred_label(LothalTheme.FONT_SIZE_SMALL, INK_FAINT)
	bottom.add_child(size_label)
	details_label = _centred_label(LothalTheme.FONT_SIZE_BODY, INK)
	bottom.add_child(details_label)
	parts_label = _centred_label(LothalTheme.FONT_SIZE_SMALL, INK_MUTED)
	bottom.add_child(parts_label)
	# The one accent on this screen, and only for a warning.
	warning_label = _centred_label(LothalTheme.FONT_SIZE_SMALL, LothalTheme.WARNING)
	warning_label.visible = false
	bottom.add_child(warning_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)

	choose_button = Button.new()
	choose_button.name = "Choose"
	choose_button.text = "Choose"
	choose_button.custom_minimum_size = Vector2(200, 44)
	choose_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose_button.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
	choose_button.add_theme_stylebox_override("normal", _button_box(Color(0.93, 0.93, 0.93)))
	choose_button.add_theme_stylebox_override("hover", _button_box(Color(1.0, 1.0, 1.0)))
	choose_button.add_theme_stylebox_override("pressed", _button_box(Color(0.78, 0.78, 0.78)))
	choose_button.add_theme_stylebox_override("disabled", _button_box(Color(0.14, 0.14, 0.14)))
	choose_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		choose_button.add_theme_color_override(state, Color(0.05, 0.05, 0.05))
	choose_button.add_theme_color_override("font_disabled_color", INK_FAINT)
	choose_button.pressed.connect(func() -> void: choose())
	bottom.add_child(choose_button)

	var dot_gap := Control.new()
	dot_gap.custom_minimum_size = Vector2(0, 8)
	dot_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(dot_gap)
	_size_row = Control.new()
	_size_row.name = "SizeRow"
	_size_row.custom_minimum_size = Vector2(0, SIZE_ROW_MAX_PX + 4.0)
	_size_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_size_row.draw.connect(_draw_size_row)
	bottom.add_child(_size_row)


func _refresh_text() -> void:
	var entry := DroneClass.by_id(current_id)
	name_label.text = String(entry["name"])
	size_label.text = "%d mm" % int(entry["wheelbase_mm"])
	details_label.text = DroneClass.typical_line(current_id)
	choose_button.disabled = not DroneClass.is_available(current_id)
	var order := DroneClass.ids()
	var index := order.find(current_id)
	prev_button.disabled = index <= 0
	next_button.disabled = index >= order.size() - 1
	_size_row.queue_redraw()

	var parts := DroneClass.parts_for(current_id)
	var names: Array[String] = []
	for category in ["frame", "motor", "propeller", "battery", "guard"]:
		var part := _catalog.get_part(String(parts.get(category, "")))
		if not part.is_empty():
			names.append(String(part["name"]))
	parts_label.text = "Starts from: %s" % ", ".join(PackedStringArray(names))
	# A seed that cannot be a working aircraft says so, in the screen's one accent colour.
	var blocking := ""
	var session := DesignSession.default_for_class(current_id)
	var build := session.build(_catalog) if session != null else null
	if build != null:
		for warning in build.warnings():
			if warning.severity == BuildWarning.Severity.IMPOSSIBLE:
				blocking = warning.message
				break
	warning_label.text = blocking
	warning_label.visible = blocking != ""


## Ten discs on one baseline at true relative wheelbase; the current class is lit.
func _draw_size_row() -> void:
	var entries := size_row()
	var gap := 22.0
	var total := gap * (entries.size() - 1)
	for e in entries:
		total += maxf(float(e["diameter_px"]), 3.0)
	var x := (_size_row.size.x - total) * 0.5
	var base_y := _size_row.size.y - 2.0
	for e in entries:
		var d := maxf(float(e["diameter_px"]), 3.0)
		var colour := INK if bool(e["current"]) else INK_FAINT
		_size_row.draw_circle(Vector2(x + d * 0.5, base_y - d * 0.5), d * 0.5, colour)
		x += d + gap


func _arrow_button(glyph: String, direction: int) -> Button:
	var button := Button.new()
	button.name = "Prev" if direction < 0 else "Next"
	button.text = glyph
	button.flat = true
	button.anchor_top = STAGE_CENTRE_Y
	button.anchor_bottom = STAGE_CENTRE_Y
	button.offset_top = -48
	button.offset_bottom = 48
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 56)
	button.add_theme_color_override("font_color", INK_MUTED)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.08))
	button.pressed.connect(func() -> void: step(direction))
	return button


func _centred_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(LothalTheme.RADIUS_CONTROL)
	box.content_margin_left = 18
	box.content_margin_right = 18
	return box
