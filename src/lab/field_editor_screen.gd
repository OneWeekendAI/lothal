class_name FieldEditorScreen
extends Control
## The field editor — the room where the world gets built (labs-and-sim.md §2.4).
##
## Lothal's central rule is that Lab authors and Sim flies, and §2.4 puts the world on Lab's side
## of it: a gate's position is what the world IS, and only flying through it is what is happening.
## The aircraft has honoured that since the beginning. The course did not — it was eight constants
## in gate_course.gd, authored in a source file, which is neither room. This is that room.
##
## ---------------------------------------------------------------------------
## WHY THE AUTHORING IS IN 3D
## ---------------------------------------------------------------------------
##
## §2.2's argument about the assembly space applies here without modification: **the render is the
## engineering check.** A gate you can see from the line you would fly at it is a gate you can
## judge; a row of numbers is not. So the course is laid out by dragging rings around a ground
## grid at the scale they will be flown at, and the three things a drag cannot express — how high
## a gate is, which way it faces, and how big its ring is — are the only sliders on the screen.
##
## The one place this screen deliberately departs from LabScreen is the camera. Lab's distance is
## FIXED across the catalog, and that is load-bearing: a 65 mm whoop must look tiny beside a 10"
## long-range. Here the opposite is true. A course may be a 6 m whoop box or a 400 m long-range
## route, both are legitimate, and the thing being judged is the SHAPE of the layout rather than
## its size against some other layout. So the camera frames whatever course is open.
##
## ---------------------------------------------------------------------------
## THE FIELD IS MORE THAN THE GATES
## ---------------------------------------------------------------------------
##
## A course also has AIR — an elevation and a temperature, from which density is derived
## (air_density.gd). That belongs here for exactly the reason the gates do: §1's rule asks whether
## a thing changes what the world IS, and where the world sits above sea level plainly does. A quad
## does not carry its atmosphere with it, and being flown in thin air is not something that
## HAPPENS to an aircraft the way a gust is; it is a fact about the place.
##
## It lives on the COURSE rather than app-wide, because a course is a place. The whoop box in a
## garage and the bando forty minutes up the road are different fields, and a builder who has laid
## out both should not have to retype the altitude when they switch between them.
##
## Its two controls are TYPED rather than dragged, which departs from this screen's own rule that
## the only controls are the three things a drag cannot express. That rule is about a gate, whose
## height and heading are judged by eye. An elevation is not judged, it is looked up — parts.md's
## "ask for what they can look up" decides it — and hunting for 920 on a slider would turn an exact
## known fact into an approximate gesture.
##
## ---------------------------------------------------------------------------
## WHAT THIS ROOM COSTS
## ---------------------------------------------------------------------------
##
## Nothing. §5 charges a bench run because a motor is turning and drawing current; laying out
## gates turns no motors, so there is no consequence to record and none is invented. There is no
## PackCharge in this file, no powertrain, no integrator and no audio. A preview flythrough would
## be flying, and flying is the other room.
##
## ---------------------------------------------------------------------------
## WHO WRITES WHAT
## ---------------------------------------------------------------------------
##
## This screen is the only writer of `user://courses.json`, and it writes on every change rather
## than on exit — the same bargain the assembly tweaks strike, for the same reason: there is no
## exit. Lothal is closed by closing the window, and a configuration that only persists when you
## quit politely is a configuration that does not persist.
##
## The rings are drawn by CourseRenderer, off the same GateCourse Sim reads. That is not
## convenience: an editor that drew its own gates would be the second implementation of the world,
## and the ring you dragged could stop being the ring the timer scores without anything looking
## wrong. gate_course.gd's opening line says the scene renders what the course describes and never
## decides anything, and it stays true while gates are being dragged.

## How much of the viewport the open course should span. Comfortably inside the edges, so a gate
## dragged to the rim of the layout is still on screen and still grabbable.
const COURSE_SCREEN_FRACTION := 0.78
const CAMERA_FOV := 50.0
## Looking down on the layout steeply enough to read the plan, shallowly enough that gate heights
## are still visible as heights. A pure top-down view makes every gate look like it is on the
## ground, which is exactly the mistake a field editor must not encourage.
const START_ELEVATION_DEG := 46.0
const START_AZIMUTH_DEG := 0.0
const ELEVATION_LIMIT_DEG := 85.0
const DRAG_DEG_PER_PIXEL := 0.4

## The slider ranges. Unlike AssemblyPanel's, these are NOT derived from parts, and the difference
## is worth stating: a shim's limit is a fact about a motor's thread, while a gate's height is a
## fact about nothing — you may put a gate wherever you like. So these are the extent of the
## control rather than a claim about what is allowed, and the warnings (not the slider) are what
## say a ring is in the ground or smaller than the aircraft. Warn, never block.
const MIN_HEIGHT_M := 0.1
const MAX_HEIGHT_M := 40.0
const MIN_RADIUS_M := 0.25
const MAX_RADIUS_M := 6.0
const HEIGHT_STEP_M := 0.1
const RADIUS_STEP_M := 0.05
const HEADING_STEP_DEG := 1.0

## The air inputs step in units a builder actually knows their field in. A metre of elevation and a
## degree of temperature are both finer than anybody can state their own site to, which is the
## point: the control should not be the thing that limits the answer's precision, and it should not
## pretend to a precision the builder does not have either.
const ELEVATION_STEP_M := 1.0
const TEMPERATURE_STEP_C := 1.0

const VIEWPORT_SIZE := Vector2i(1280, 720)

signal course_changed

var library: CourseLibrary
## The places those courses are laid out in. The elevation the air panel below writes lives HERE
## now rather than on the course — see site.gd's header for why — and this room is still its only
## writer, which is what §1's "Lab authors the world" asks for.
var sites: SiteLibrary
var sites_path: String
## The build the course is being laid out for. Read-only here — this room does not touch the
## aircraft — and used for exactly one thing: comparing a ring's aperture against the span of the
## machine that has to fly through it.
var build: Build
var save_path: String

var renderer: CourseRenderer
var selected_gate := 0

var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _orbit: Node3D
var _camera: Camera3D
var _ground: MeshInstance3D
var _start_marker: Node3D

var _course_list: ItemList
var _name_field: LineEdit
var _delete_button: Button
var _elevation_field: SpinBox
var _temperature_field: SpinBox
var _air_readout: Label
var _gate_label: Label
var _position_label: Label
var _height_slider: HSlider
var _heading_slider: HSlider
var _radius_slider: HSlider
var _height_value: Label
var _heading_value: Label
var _radius_value: Label
var _remove_button: Button
var _warning_list: WarningList

var _azimuth_rad := deg_to_rad(START_AZIMUTH_DEG)
var _elevation_rad := deg_to_rad(START_ELEVATION_DEG)
var _orbiting := false
var _dragging_gate := false
## Set while the panel writes its own controls from the model, so a programmatic slider move does
## not read back as the builder having dragged something.
var _updating := false


func _init(p_library: CourseLibrary, p_build: Build,
		p_save_path: String = CourseLibrary.SAVE_PATH, p_sites: SiteLibrary = null) -> void:
	library = p_library
	build = p_build
	save_path = p_save_path
	# The sites file that pairs with this courses file, so a caller handing over a scratch library
	# cannot overwrite the builder's own fields. SiteLibrary owns that pairing; this room only asks.
	sites_path = SiteLibrary.path_beside(p_save_path)
	sites = p_sites if p_sites != null else SiteLibrary.load_from(sites_path)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	row.add_child(_build_course_rail())

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.gui_input.connect(_on_viewport_input)
	row.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	# Its own World3D, for the same reason Lab's viewport has one: Sim is a separate scene with its
	# own cameras and lights, and a shared world is how two rooms end up rendering into each other.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_container.add_child(_viewport)

	_build_world()

	row.add_child(_build_gate_panel())

	render()


# ---------------------------------------------------------------------------
# The rails
# ---------------------------------------------------------------------------

func _build_course_rail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(292, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)

	var title := Label.new()
	title.text = "COURSES"
	title.theme_type_variation = &"TitleLabel"
	column.add_child(title)

	var note := Label.new()
	note.text = "The world is built here and flown in the field. Nothing here flies."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(260, 0)
	note.theme_type_variation = &"MutedLabel"
	column.add_child(note)

	_course_list = ItemList.new()
	_course_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_course_list.item_selected.connect(_on_course_row_selected)
	column.add_child(_course_list)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Course name"
	_name_field.text_submitted.connect(func(text: String) -> void: rename_course(text))
	column.add_child(_name_field)

	var new_button := Button.new()
	new_button.text = "New course"
	new_button.pressed.connect(func() -> void: new_course(_next_course_name()))
	column.add_child(new_button)

	_delete_button = Button.new()
	_delete_button.text = "Delete course"
	_delete_button.pressed.connect(func() -> void: delete_course())
	column.add_child(_delete_button)

	column.add_child(HSeparator.new())
	_build_air_section(column)

	return panel


## Where you fly, and what it does to the air.
##
## IN THE COURSE RAIL RATHER THAN THE GATE PANEL, because air is a property of the COURSE and not
## of a gate — the same reason the course's name is here. Selecting a different course changes the
## field; selecting a different gate does not.
##
## TYPED RATHER THAN DRAGGED, and this is a deliberate departure from §2.4's "the only controls are
## the three things a drag cannot express". That rule is about a gate, whose height and heading are
## JUDGED — you move them until the line looks right. Elevation is not judged, it is LOOKED UP: a
## builder knows their field is at 920 m, and hunting for 920 on a slider would make an exact known
## fact into an approximate gesture. parts.md's rule decides it — ask for what can be looked up.
##
## The derived density is shown back because it is the whole justification for asking. A builder
## who types 920 and 35 and sees "16.3% below sea level" has learnt the thing this feature exists
## to teach, before a single number on the build has moved.
func _build_air_section(column: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "THE FIELD"
	title.theme_type_variation = &"TitleLabel"
	column.add_child(title)

	var note := Label.new()
	note.text = "Where this course is. Thinner air is less thrust, and every figure on the build knows it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(260, 0)
	note.theme_type_variation = &"MutedLabel"
	column.add_child(note)

	_elevation_field = _add_field(column, "Elevation", "m",
		AirDensity.MIN_ELEVATION_M, AirDensity.MAX_ELEVATION_M, ELEVATION_STEP_M,
		func(v: float) -> void: set_field_elevation_m(v))
	_temperature_field = _add_field(column, "Temperature", "°C",
		AirDensity.MIN_TEMPERATURE_C, AirDensity.MAX_TEMPERATURE_C, TEMPERATURE_STEP_C,
		func(v: float) -> void: set_field_temperature_c(v))

	_air_readout = Label.new()
	_air_readout.theme_type_variation = &"ReadoutLabel"
	_air_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_air_readout.custom_minimum_size = Vector2(260, 0)
	column.add_child(_air_readout)


## A labelled numeric entry. The sibling of _add_slider, and separate from it because a SpinBox is
## for a number you KNOW and a slider is for one you are choosing by eye.
func _add_field(column: VBoxContainer, label_text: String, suffix: String,
		minimum: float, maximum: float, step: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.suffix = suffix
	field.select_all_on_focus = true
	# A SpinBox is a Range, so the same rule the sliders live under applies: value_changed does not
	# fire for a value set from code, and the guard stops the panel writing its own controls from
	# reading back as the builder having typed something.
	field.value_changed.connect(func(v: float) -> void:
		if not _updating:
			on_change.call(v))
	row.add_child(field)
	column.add_child(row)
	return field


func _build_gate_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(336, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_gate_label = Label.new()
	_gate_label.theme_type_variation = &"TitleLabel"
	column.add_child(_gate_label)

	var hint := Label.new()
	hint.text = "Drag a ring on the grid to move it. Drag anywhere else to look around."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	hint.theme_type_variation = &"MutedLabel"
	column.add_child(hint)

	_position_label = Label.new()
	_position_label.theme_type_variation = &"ReadoutLabel"
	column.add_child(_position_label)

	column.add_child(HSeparator.new())

	_height_slider = _add_slider(column, "Height", MIN_HEIGHT_M, MAX_HEIGHT_M, HEIGHT_STEP_M,
		func(v: float) -> void: set_gate_height_m(v))
	_height_value = column.get_child(column.get_child_count() - 1) as Label

	_heading_slider = _add_slider(column, "Heading", -180.0, 180.0, HEADING_STEP_DEG,
		func(v: float) -> void: set_gate_heading_deg(v))
	_heading_value = column.get_child(column.get_child_count() - 1) as Label

	_radius_slider = _add_slider(column, "Ring radius", MIN_RADIUS_M, MAX_RADIUS_M, RADIUS_STEP_M,
		func(v: float) -> void: set_gate_radius_m(v))
	_radius_value = column.get_child(column.get_child_count() - 1) as Label

	column.add_child(HSeparator.new())

	var order_row := HBoxContainer.new()
	column.add_child(order_row)
	var earlier := Button.new()
	earlier.text = "Earlier"
	earlier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	earlier.pressed.connect(func() -> void: reorder_gate(-1))
	order_row.add_child(earlier)
	var later := Button.new()
	later.text = "Later"
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	later.pressed.connect(func() -> void: reorder_gate(1))
	order_row.add_child(later)

	var gate_row := HBoxContainer.new()
	column.add_child(gate_row)
	var add := Button.new()
	add.text = "Add gate"
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(add_gate)
	gate_row.add_child(add)
	_remove_button = Button.new()
	_remove_button.text = "Remove gate"
	_remove_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_remove_button.pressed.connect(func() -> void: remove_gate())
	gate_row.add_child(_remove_button)

	column.add_child(HSeparator.new())

	# The same severity treatment the build readout uses, because it is the same kind of statement
	# about a different question. A course that cannot be flown and a course that is merely long
	# must never arrive in the same colour.
	_warning_list = WarningList.new(300)
	column.add_child(_warning_list)

	return panel


## A labelled slider with its value beside it. The value label is added LAST so the caller can pick
## it up off the column, which keeps this helper from having to return two things.
func _add_slider(column: VBoxContainer, label_text: String, minimum: float, maximum: float,
		step: float, on_change: Callable) -> HSlider:
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	column.add_child(header)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	# Range.value_changed does NOT fire for a value set from code, so the model update lives in a
	# plain method this signal calls rather than in the handler — which is also what keeps the
	# editor drivable from a headless test with no sliders to move.
	slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			on_change.call(v))
	column.add_child(slider)

	var value := Label.new()
	value.theme_type_variation = &"ReadoutLabel"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(value)
	return slider


# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	# The same procedural grid the field itself uses. It is not decoration here either: the grid
	# is the only thing that gives a gate's position a scale you can read, and a course laid out
	# over a blank plane could be six metres across or six hundred.
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_ground.mesh = plane
	_viewport.add_child(_ground)

	renderer = CourseRenderer.new(course())
	_viewport.add_child(renderer)

	_start_marker = _build_start_marker()
	_viewport.add_child(_start_marker)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)

	_orbit = Node3D.new()
	_viewport.add_child(_orbit)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.1
	_camera.far = 4000.0
	_orbit.add_child(_camera)


## Where the pilot starts, drawn as a post with an arrow over it. DERIVED from the course rather
## than authored — GateCourse.start_position() is the one answer to where a lap begins — so this
## is a picture of a fact and not a second copy of one. It matters on screen because the start line
## is the one part of the layout a builder cannot otherwise see, and a course whose first gate has
## been turned round starts the pilot facing the wrong way with nothing to warn them.
func _build_start_marker() -> Node3D:
	var pivot := Node3D.new()

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.08
	post_mesh.bottom_radius = 0.08
	post_mesh.height = 1.0
	var post := MeshInstance3D.new()
	post.mesh = post_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = LothalTheme.SUCCESS
	marker_material.emission_enabled = true
	marker_material.emission = LothalTheme.SUCCESS
	post.material_override = marker_material
	pivot.add_child(post)

	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.3
	arrow_mesh.height = 0.9
	var arrow := MeshInstance3D.new()
	arrow.mesh = arrow_mesh
	arrow.material_override = marker_material
	# Laid on its side so the cone points along the pivot's -Z, which is where a Basis.looking_at
	# aims — the same convention the drone's own forward uses (physics.md §1).
	arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	arrow.position = Vector3(0.0, 0.8, -0.6)
	pivot.add_child(arrow)

	return pivot


# ---------------------------------------------------------------------------
# The course being edited
# ---------------------------------------------------------------------------

func course() -> GateCourse:
	return library.selected()


func select_gate(index: int) -> void:
	selected_gate = clampi(index, 0, maxi(course().gates.size() - 1, 0))
	if renderer != null:
		renderer.highlight_index = selected_gate
		renderer.highlight_next()
	_render_panel()


## A new gate halfway along the leg from the selected gate to the next one, at the height and ring
## size of the gate it follows, facing the way that leg runs.
##
## On the route rather than at the origin, deliberately. An editor that drops a new gate in a
## corner of the map makes you drag every one of them somewhere before the course means anything,
## which turns authoring back into data entry — and the halfway point of a leg is where a gate
## being added to a circuit almost always wants to go.
func add_gate() -> void:
	var gates := course().gates
	if gates.is_empty():
		gates.append(GateCourse.make_gate(Vector3(0.0, GateCourse.GATE_LOW_M, 0.0), 0.0,
			GateCourse.GATE_INNER_RADIUS_M))
		selected_gate = 0
		_changed()
		return

	var here: Dictionary = gates[selected_gate]
	var next: Dictionary = gates[(selected_gate + 1) % gates.size()]
	var midpoint: Vector3 = (here["position"] + next["position"]) * 0.5
	var along: Vector3 = next["position"] - here["position"]
	var heading := GateCourse.gate_heading_rad(here) if along.length() < 0.01 \
		else atan2(along.x, -along.z)

	gates.insert(selected_gate + 1, GateCourse.make_gate(midpoint, heading, float(here["radius"])))
	selected_gate += 1
	_changed()


## Removes the gate being edited. Refuses to remove the last one: a course with no gates is not a
## course, it is an empty field with a start line pointing at nothing.
func remove_gate() -> bool:
	if course().gates.size() <= 1:
		return false
	course().gates.remove_at(selected_gate)
	selected_gate = clampi(selected_gate, 0, course().gates.size() - 1)
	_changed()
	return true


## Moves the gate being edited earlier or later in the running order, and the selection follows it.
## The order IS part of the authored world — the same rings taken in a different sequence is a
## different course to fly, and the fingerprint says so.
func reorder_gate(delta: int) -> bool:
	var target := selected_gate + delta
	if target < 0 or target >= course().gates.size():
		return false
	var gate: Dictionary = course().gates[selected_gate]
	course().gates.remove_at(selected_gate)
	course().gates.insert(target, gate)
	selected_gate = target
	_changed()
	return true


## Where on the ground the gate stands. The Y of the argument is ignored — height is the slider's
## business, so that dragging a gate across the grid cannot quietly change how high it is.
func set_gate_ground_position(p_position: Vector3) -> void:
	var gate: Dictionary = course().gates[selected_gate]
	gate["position"] = Vector3(p_position.x, float(gate["position"].y), p_position.z)
	_changed()


func set_gate_height_m(height_m: float) -> void:
	var gate: Dictionary = course().gates[selected_gate]
	var at: Vector3 = gate["position"]
	gate["position"] = Vector3(at.x, height_m, at.z)
	_changed()


func set_gate_heading_deg(heading_deg: float) -> void:
	var gate: Dictionary = course().gates[selected_gate]
	gate["normal"] = GateCourse.make_gate(
		gate["position"], deg_to_rad(heading_deg), float(gate["radius"]))["normal"]
	_changed()


func set_gate_radius_m(radius_m: float) -> void:
	course().gates[selected_gate]["radius"] = radius_m
	_changed()


func warnings() -> Array[BuildWarning]:
	return CourseWarnings.evaluate(course(), build)


# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------

## A new course, AND A NEW PLACE TO PUT IT. One site per course, which is the same rule the v1
## migration follows and for the same reason: a course dropped into the last one's site would
## inherit an elevation nobody typed for it, which is the silent wrongness this whole slice moves
## the elevation to close. Two routes at one field is a thing a builder asks for explicitly, and
## F4 is where they ask.
func new_course(p_name: String) -> void:
	var created := library.create(p_name)
	created.site_id = sites.create(p_name).site_id
	library.select(created.course_id)
	selected_gate = 0
	_changed()


## Where this course is, in metres above sea level.
##
## A NEW AirDensity RATHER THAN A MUTATED ONE, deliberately. AirDensity clamps in its constructor,
## so building a fresh one is what applies the domain guard; assigning to elevation_m on the
## existing object would slip past it and let a hand-driven caller put 10^9 m into the barometric
## formula, which is NaN and then "nan g" on the stats panel.
func set_field_elevation_m(elevation_m: float) -> void:
	site().elevation_m = AirDensity.new(elevation_m, 0.0).elevation_m
	_changed()


func set_field_temperature_c(temperature_c: float) -> void:
	site().migrated_temperature_c = AirDensity.new(0.0, temperature_c).temperature_c
	_changed()


## The place the open course is laid out in. A course pointing at a site that is not there falls
## back to the selected one rather than to nothing, on load_from()'s rule: a damaged file lands
## somewhere flyable and the room opens.
func site() -> Site:
	var where := sites.site(course().site_id)
	return where if where != null else sites.selected()


## The air the open course is flown in, composed from the site's elevation and the temperature
## (design §3.1). This is the number the panel quotes and the number the physics runs on — one
## derivation, not a second copy of it.
func air() -> AirDensity:
	return site().air()


## Renames without changing the id, so nothing that pointed at the course — a saved selection, a
## best lap — is orphaned by a typo being fixed.
func rename_course(p_name: String) -> void:
	if p_name.strip_edges() == "":
		return
	library.rename(course().course_id, p_name.strip_edges())
	_changed()


func delete_course() -> bool:
	if not library.remove(course().course_id):
		return false
	selected_gate = 0
	_changed()
	return true


func choose_course(id: String) -> bool:
	if not library.select(id):
		return false
	selected_gate = 0
	_changed()
	return true


func _next_course_name() -> String:
	return "Course %d" % (library.ids().size() + 1)


func _on_course_row_selected(index: int) -> void:
	var ids := library.ids()
	if index >= 0 and index < ids.size():
		choose_course(ids[index])


# ---------------------------------------------------------------------------
# One path from a change to everything that shows it
# ---------------------------------------------------------------------------

## Every edit lands here: the rings are rebuilt, the camera reframes, the panels and the warnings
## are re-read, and the library is written to disk. One path, in the manner of LabScreen's
## _on_selection_changed, and for the same reason — there is no ordering in which the panel could
## be describing a gate the viewport is no longer drawing.
func _changed() -> void:
	library.put(course())
	library.save(save_path)
	sites.save(sites_path)
	render()
	course_changed.emit()


func render() -> void:
	selected_gate = clampi(selected_gate, 0, maxi(course().gates.size() - 1, 0))
	if renderer != null:
		renderer.course = course()
		renderer.highlight_index = selected_gate
		renderer.rebuild()
	_frame_course()
	_render_course_list()
	_render_panel()


func _render_course_list() -> void:
	if _course_list == null:
		return
	var ids := library.ids()
	_course_list.clear()
	for i in ids.size():
		_course_list.add_item(library.names()[i])
		if ids[i] == library.selected_id:
			_course_list.select(i)
	_name_field.text = course().course_name
	# The last course cannot be deleted — there has to be somewhere to fly — so the button says so
	# by being unavailable rather than by refusing after the fact.
	_delete_button.disabled = ids.size() <= 1
	_render_air()


## The field's own readout. Written from the model on every change like every other control here,
## so switching courses shows the NEW course's field rather than leaving the last one's numbers
## sitting under a different name.
func _render_air() -> void:
	if _elevation_field == null:
		return
	var here := air()

	_updating = true
	_elevation_field.value = here.elevation_m
	_temperature_field.value = here.temperature_c
	_updating = false

	# Standard air gets a sentence rather than "0.0% below sea level", which reads like a
	# measurement of nothing. A course at sea level should say what it is, once, and stop.
	if here.is_standard():
		_air_readout.text = "%.3f kg/m³ — standard sea-level air." % here.kgm3()
		return

	# Both densities, and the comparison in the units a pilot already thinks in. The percentage is
	# the number that means something; the kg/m³ is there because it is what the physics uses and a
	# builder should be able to see the quantity the app is actually reasoning about.
	var fraction := here.fraction_below_standard()
	_air_readout.text = "%.3f kg/m³ — %.1f%% %s sea-level air (%.3f)." % [
		here.kgm3(), absf(fraction) * 100.0,
		"below" if fraction > 0.0 else "above", AirDensity.standard_kgm3()]


func _render_panel() -> void:
	if _gate_label == null:
		return
	var gates := course().gates
	_gate_label.text = "GATE %d / %d" % [selected_gate + 1, gates.size()]
	_remove_button.disabled = gates.size() <= 1

	var gate: Dictionary = gates[selected_gate]
	var at: Vector3 = gate["position"]
	_position_label.text = "x %+7.1f m    z %+7.1f m" % [at.x, at.z]

	_updating = true
	_height_slider.value = at.y
	_heading_slider.value = rad_to_deg(GateCourse.gate_heading_rad(gate))
	_radius_slider.value = float(gate["radius"])
	_updating = false

	_height_value.text = "%.1f m" % at.y
	_heading_value.text = "%.0f deg" % rad_to_deg(GateCourse.gate_heading_rad(gate))
	_radius_value.text = "%.2f m ring" % float(gate["radius"])

	_warning_list.show_warnings(warnings())

	if _start_marker != null:
		_start_marker.position = course().start_position()
		var forward := course().start_forward()
		var flat := Vector3(forward.x, 0.0, forward.z)
		if flat.length() > 0.001:
			_start_marker.basis = Basis.looking_at(flat.normalized(), Vector3.UP)


# ---------------------------------------------------------------------------
# Framing
# ---------------------------------------------------------------------------

## Centres and frames whatever course is open. See the header for why this zooms where Lab
## deliberately does not: a whoop box and a long-range route are both legitimate, and what is being
## judged here is the shape of the layout rather than its size against another layout.
func _frame_course() -> void:
	if _camera == null:
		return
	var gates := course().gates
	var centre := Vector3.ZERO
	for gate in gates:
		centre += gate["position"]
	centre /= maxf(float(gates.size()), 1.0)
	centre.y = 0.0

	var extent_m := 4.0
	for gate in gates:
		var offset: Vector3 = gate["position"] - centre
		extent_m = maxf(extent_m, Vector3(offset.x, 0.0, offset.z).length() + float(gate["radius"]))

	_orbit.position = centre
	var distance := (extent_m / COURSE_SCREEN_FRACTION) / tan(deg_to_rad(CAMERA_FOV) * 0.5)
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, distance))
	_apply_orbit()

	# The ground is sized to the layout for the same reason the camera is: a fixed 400 m plane is
	# a grey haze behind a 6 m whoop box and runs out from under a long-range route.
	var ground_size := maxf(extent_m * 3.0, 40.0)
	(_ground.mesh as PlaneMesh).size = Vector2(ground_size, ground_size)
	_ground.material_override = GroundGrid.build_material(ground_size)
	_ground.position = centre


func set_orbit(azimuth_rad: float, elevation_rad: float) -> void:
	var limit := deg_to_rad(ELEVATION_LIMIT_DEG)
	_azimuth_rad = azimuth_rad
	_elevation_rad = clampf(elevation_rad, -limit, limit)
	_apply_orbit()


func _apply_orbit() -> void:
	if _orbit != null:
		_orbit.rotation = Vector3(-_elevation_rad, _azimuth_rad, 0.0)


## There is deliberately no idle orbit here, and that is the opposite of LabScreen's choice. In the
## garage a slow turn makes a static object read as solid. Here it would be moving the ground under
## a gate you are trying to put somewhere, which is unusable.
func camera_world_transform() -> Transform3D:
	return _orbit.transform * _camera.transform


# ---------------------------------------------------------------------------
# Dragging a gate on the grid
# ---------------------------------------------------------------------------

func _on_viewport_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			var hit := gate_at(button.position)
			if hit >= 0:
				select_gate(hit)
				_dragging_gate = true
			else:
				_orbiting = true
		else:
			_dragging_gate = false
			_orbiting = false
		return

	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _dragging_gate:
		var ground: Variant = ground_point(motion.position)
		if ground != null:
			set_gate_ground_position(ground)
	elif _orbiting:
		set_orbit(
			_azimuth_rad + deg_to_rad(motion.relative.x * DRAG_DEG_PER_PIXEL),
			_elevation_rad + deg_to_rad(-motion.relative.y * DRAG_DEG_PER_PIXEL))


## Which gate is under a point on the viewport, or -1. Picked by projecting each gate's centre back
## to the screen and taking the nearest within its own drawn radius, rather than by a physics
## query: there are no collision shapes in this room and adding some would mean a second geometry
## describing where the gates are.
func gate_at(local_position: Vector2) -> int:
	var point := _to_viewport(local_position)
	var camera_transform := camera_world_transform()
	var best := -1
	var best_distance := INF
	for i in course().gates.size():
		var gate: Dictionary = course().gates[i]
		var centre: Vector3 = gate["position"]
		# Behind the camera: unprojectable, and not something you can click on.
		if (camera_transform.affine_inverse() * centre).z > -_camera.near:
			continue
		var screen := _unproject(camera_transform, centre)
		var edge := _unproject(camera_transform,
			centre + camera_transform.basis.x * float(gate["radius"]))
		var distance := point.distance_to(screen)
		if distance <= screen.distance_to(edge) and distance < best_distance:
			best_distance = distance
			best = i
	return best


## Where a point on the viewport lands on the horizontal plane the selected gate stands on. Null
## when the ray never meets that plane — looking up at the sky from below the gate's height, which
## is a legitimate camera angle and not a place to drop a gate.
func ground_point(local_position: Vector2) -> Variant:
	var point := _to_viewport(local_position)
	var camera_transform := camera_world_transform()
	var origin := camera_transform.origin
	var direction := (_project_ray(camera_transform, point)).normalized()
	# The gate's OWN height, not y = 0. Dragging across the ground plane and then re-projecting at
	# the gate's height is what keeps a gate 6 m up under the cursor instead of sliding away from
	# it by however far the camera is tilted.
	var plane := Plane(Vector3.UP, float(course().gates[selected_gate]["position"].y))
	var hit: Variant = plane.intersects_ray(origin, direction)
	return hit


## Control-local pixels to viewport pixels. The container stretches its SubViewport to whatever
## width the middle column has, so a click at the container's half-width is at the viewport's
## half-width and not at the same pixel.
func _to_viewport(local_position: Vector2) -> Vector2:
	var container_size := _viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local_position
	return local_position * (Vector2(_viewport.size) / container_size)


## Composed by hand rather than read off the Camera3D, for the reason LabScreen's
## camera_world_transform gives: this screen is constructed before it is parented, and in the
## headless tests it is never parented at all, so the camera's own projection helpers have no
## viewport to answer about.
func _unproject(camera_transform: Transform3D, world: Vector3) -> Vector2:
	var local := camera_transform.affine_inverse() * world
	var half_width := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var viewport_size := Vector2(_viewport.size)
	var ndc := Vector2(local.x, -local.y) / (-local.z * half_width)
	# KEEP_WIDTH: the horizontal half-angle is fixed and the vertical follows from the aspect.
	return (Vector2(ndc.x, ndc.y * (viewport_size.x / maxf(viewport_size.y, 1.0))) * 0.5 + Vector2(0.5, 0.5)) * viewport_size


func _project_ray(camera_transform: Transform3D, point: Vector2) -> Vector3:
	var viewport_size := Vector2(_viewport.size)
	var ndc := (point / viewport_size - Vector2(0.5, 0.5)) * 2.0
	var half_width := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var local := Vector3(
		ndc.x * half_width,
		-ndc.y * half_width * (maxf(viewport_size.y, 1.0) / viewport_size.x),
		-1.0)
	return camera_transform.basis * local
