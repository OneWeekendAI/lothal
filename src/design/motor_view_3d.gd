class_name MotorView3D
extends SubViewportContainer
## The motor drawn in 3D in the motor designer's middle column: the same MotorMesh the Airframe
## room draws, built from the designer's catalog-shaped record (stator and bell dimensions), with
## a class-typical prop on the shaft. It turns slowly on its own; nothing here is interactive.
## The camera frames the whole prop disc, so nothing is cut at the column's edge.

const SPIN_RAD_PER_S := 0.3

var viewport: SubViewport
var motor: MotorDetailMesh
var prop: PropellerMesh
var camera: Camera3D
var _pivot: Node3D


func _init() -> void:
	name = "MotorView3D"
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
	viewport.add_child(_pivot)
	motor = MotorDetailMesh.new()
	_pivot.add_child(motor)
	prop = PropellerMesh.new()
	_pivot.add_child(prop)
	camera = Camera3D.new()
	camera.fov = 30.0
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
	# The fov spans the narrower side; the size is only known once laid out, so re-pick on resize.
	resized.connect(func(): camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT)
	set_process(true)


## Redraws motor and prop. `prop_record` may be {} (no prop drawn).
func show_motor(record: Dictionary, prop_record: Dictionary) -> void:
	var stack := 0.0
	if not prop_record.is_empty():
		prop.visible = true
		prop.rebuild(prop_record)
		stack = prop.stack_height_m
	else:
		prop.visible = false
	motor.rebuild(record, stack)
	prop.position = Vector3(0.0, motor.prop_mount_height_m + prop.underside_m, 0.0)
	# Centre the motor's own height on the pivot, then frame the whole prop disc (it turns with the
	# pivot, so its full diameter must fit) or the motor, whichever is larger, with a little air.
	var h := motor.total_height_m
	motor.position.y = -h * 0.5
	prop.position.y -= h * 0.5
	var radius := maxf(Vector2(motor.bell_radius_m * 2.0, h).length() * 0.5, 0.002)
	if prop.visible:
		radius = maxf(radius, prop.radius_m)
	var dist := radius / sin(deg_to_rad(camera.fov) * 0.5) * 1.12
	var tilt := deg_to_rad(38.0)
	# Pure transform maths, so it works before the view is in the tree (headless tests).
	camera.transform = Transform3D(Basis(), Vector3(0.0, sin(tilt) * dist, cos(tilt) * dist)) \
		.looking_at(Vector3.ZERO, Vector3.UP)
	camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pivot.rotation.y += SPIN_RAD_PER_S * delta
