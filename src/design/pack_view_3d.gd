class_name PackView3D
extends SubViewportContainer
## The pack drawn in 3D, in the pop-up's middle column: the same BatteryMesh the Airframe room
## draws (pouches stacked for LiPo, barrels in a sleeve for Li-ion), generated from the designer's
## own catalog-shaped record, so what turns here is what the drone would be given. It turns slowly
## on its own; nothing here is interactive.

const SPIN_RAD_PER_S := 0.35

var viewport: SubViewport
var mesh: BatteryMesh
var camera: Camera3D
var _pivot: Node3D


func _init() -> void:
	name = "PackView3D"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(320, 320)
	add_child(viewport)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(35.0), 0.0)
	viewport.add_child(_pivot)
	mesh = BatteryMesh.new()
	_pivot.add_child(mesh)
	camera = Camera3D.new()
	camera.fov = 32.0
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.74, 0.82)
	e.ambient_light_energy = 0.55
	env.environment = e
	viewport.add_child(env)
	resized.connect(func(): if mesh.size_m != Vector3.ZERO: camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT)
	set_process(true)


## Redraws the pack from a catalog-shaped record (PackDesign.to_record()).
func show_record(record: Dictionary) -> void:
	mesh.rebuild(record)
	var s := mesh.size_m
	var radius := maxf(s.length(), 0.02) * 0.5
	# Fit the bounding sphere in the lens with a little air around it.
	var dist := radius / sin(deg_to_rad(camera.fov) * 0.5) * 1.08
	camera.position = Vector3(0.0, 0.0, dist)
	# The fov is across the narrower side, so a tall or a wide region both hold the whole pack.
	camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pivot.rotation.y += SPIN_RAD_PER_S * delta
