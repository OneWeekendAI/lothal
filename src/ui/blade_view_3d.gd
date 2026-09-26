class_name BladeView3D
extends SubViewportContainer
## The blade in the round — what the Propulsion room was missing.
##
## ## Why a 3D view in a room that already draws the blade twice
##
## The room shows `c(r)` as a curve and the section at the caret as an outline, and between them
## they define the blade completely. They do not SHOW it. A builder drawing a planform could not
## see how many blades the propeller has, what the twist looks like as a surface, or whether the
## thing they are about to print reads as a propeller at all — the questions that need a shape and
## not a graph, and the ones every "does this look right" instinct is built on.
##
## ## It renders `PropellerMesh` and generates nothing
##
## The mesh is the one Lab flies. It builds its vertices from `PropellerDocument.section_corners_mm`
## at every station, so what is on screen here is `beta(r)` and `c(r)` as the physics reads them —
## P10d's rule, and the whole reason this view is worth having rather than a drawing of a
## propeller. A second generator here would be a picture free to disagree with the model, which is
## precisely the failure `PropellerMesh`'s own header spends thirty lines on.
##
## THE BLADE IS DRAWN STOPPED. `PropellerMesh` swaps to a swept-disc above
## `max_discrete_rpm` because a spinning rotor cannot be drawn honestly at 60 fps — true in Sim,
## and exactly wrong here, where the blade's shape is the entire subject. So this view hands the
## mesh a rate of zero and never animates it.
##
## ## What is testable and what is not
##
## A `SubViewport` has no `World3D` until it enters the tree, and a camera pose asserted through a
## rendered frame is asserted through the one part of this that no headless runner has. So the
## camera geometry lives in static functions that take numbers and return a Transform3D, and those
## are what `test_blade_room.gd` checks. That the viewport draws at all is left to the capture
## tooling, and said here rather than implied.

## The four canonical views. Named rather than free-form because "show me the top" is a question
## with one right answer, and a builder hunting for it by dragging is a builder who cannot compare
## two blades.
##
## Values are (yaw, pitch) in radians about the rotor's own axes: yaw around the shaft, pitch above
## the disc plane. TOP looks straight down the shaft — the planform view, the one that matches the
## chord curve in the editor. FRONT and SIDE sit in the disc plane, where twist reads as an angle
## rather than as foreshortening. ISO is the three-quarter view, the default, because it is the only
## one that shows blade count, twist and planform at once.
const VIEWS := {
	"iso": Vector2(0.7854, 0.5236),
	"top": Vector2(0.0, 1.5533),
	"front": Vector2(0.0, 0.0),
	"side": Vector2(1.5708, 0.0),
}

const DEFAULT_VIEW := "iso"

## How far the camera sits from the hub, as a multiple of the propeller's RADIUS. 2.6 frames a disc
## with margin at the default field of view; it is a multiple of radius rather than a fixed metre
## distance so a 2" whoop blade and a 9" cinelifter blade fill the same frame — the comparison this
## view exists to support.
const DISTANCE_TO_RADIUS := 2.6

## Straight down is unreachable by a hair, on purpose: at exactly ±π/2 the camera's up vector is
## parallel to its forward vector and `looking_at` has no basis to build. The gap is under a fifth
## of a degree, so the "top" view is a top view.
const PITCH_LIMIT := 1.5533

## Radians per pixel of drag. Slow enough that a small mouse movement inspects rather than spins.
const DRAG_SENSITIVITY := 0.008

var yaw := 0.0
var pitch := 0.0
var radius_m := 0.0645

var _viewport: SubViewport
var _camera: Camera3D
var _mesh: PropellerMesh
var _markers: Node3D
var _document: PropellerDocument
var _prop: Dictionary = {}
var _caret_r_frac := 0.7
var _stall_bands := PackedFloat64Array()
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(240, 200)
	stretch = true
	var pose: Vector2 = VIEWS[DEFAULT_VIEW]
	yaw = pose.x
	pitch = pose.y

	_viewport = SubViewport.new()
	# The room is a still picture of a stopped blade: rendering it every frame is a GPU cost for a
	# scene that changes only when the document does. UPDATE_ONCE plus an explicit poke on every
	# change is the same picture at a fraction of the cost.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	# A poke on every resize, and it is not an optimisation detail. UPDATE_ONCE renders the NEXT
	# frame and then disables itself, so every poke this class makes before the container has been
	# laid out is spent rendering a viewport of the wrong size — and the one that finally has the
	# right size never renders at all. The symptom is a blank rectangle with no error against it,
	# which is exactly how this shipped in the first capture of the room.
	resized.connect(_poke)


## The 3D contents are built on entering the tree and NOT in `_init`, because a SubViewport has no
## World3D until it is in one: nodes added earlier are added to nothing, and the failure is a black
## rectangle with no error attached to it.
func _ready() -> void:
	var world := Node3D.new()
	world.name = "BladeWorld"
	_viewport.add_child(world)

	_mesh = PropellerMesh.new()
	world.add_child(_mesh)

	_markers = Node3D.new()
	_markers.name = "Markers"
	world.add_child(_markers)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, 0.6, 0.0)
	key.light_energy = 1.2
	world.add_child(key)

	# A second light from below, which a propeller needs and a solid object does not: the underside
	# of a blade is the face whose angle a builder is trying to read, and unlit it reads as flat.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(1.1, -0.8, 0.0)
	fill.light_energy = 0.45
	world.add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = LothalTheme.SURFACE_BASE
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.44)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	world.add_child(env)

	_camera = Camera3D.new()
	# Frame by WIDTH, not by height. A Camera3D's default `KEEP_HEIGHT` fixes the vertical field of
	# view and lets the horizontal one shrink with the aspect — and this pane is a tall narrow
	# column, so the disc ended up spanning a third of the width in a viewport with empty space
	# above and below it. The disc is a width-shaped object in a height-shaped pane.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.current = true
	world.add_child(_camera)

	if not _prop.is_empty():
		_rebuild()
	_apply_camera()


# ---------------------------------------------------------------------------
# What is shown
# ---------------------------------------------------------------------------

## The propeller to draw: the room's catalog-shaped dictionary and the document behind it. Both,
## for `PropellerMesh.rebuild`'s own reason — an AUTHORED twist exists only in the document and
## cannot be recovered from the spec line.
func show_propeller(prop: Dictionary, doc: PropellerDocument) -> void:
	_prop = prop
	_document = doc
	if doc != null and doc.diameter_mm > 0.0:
		radius_m = doc.radius_mm() * 0.001
	if _mesh != null:
		_rebuild()


## Which station the room's caret is on — drawn as a ring around the disc at that radius, so the
## section outline, the α curve and the solid all point at the same slice of blade.
func set_caret(r_frac: float) -> void:
	_caret_r_frac = clampf(r_frac, 0.0, 1.0)
	if _mesh != null:
		_rebuild_markers()


## The stalled stretches, as `BladeAero.stall_bands` returns them. Drawn on the disc as red annuli.
##
## The same fact in the same place as the panel's shading, on the shape rather than on a graph:
## "the inner third is stalled" is a sentence about a region of the blade, and here it is that
## region.
func set_stall_bands(bands: PackedFloat64Array) -> void:
	_stall_bands = bands
	if _mesh != null:
		_rebuild_markers()


func snap_to(view_id: String) -> void:
	if not VIEWS.has(view_id):
		return
	var pose: Vector2 = VIEWS[view_id]
	yaw = pose.x
	pitch = pose.y
	_apply_camera()


# ---------------------------------------------------------------------------
# Camera geometry — pure, so it is provable without a rendered frame
# ---------------------------------------------------------------------------

## Where the camera sits for a given orbit, in the rotor's own frame: the shaft is +Y and the disc
## lies in XZ, which is `PropellerMesh`'s convention and not a choice made here.
static func camera_position(p_yaw: float, p_pitch: float, distance: float) -> Vector3:
	var clamped := clampf(p_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	return Vector3(
		distance * cos(clamped) * sin(p_yaw),
		distance * sin(clamped),
		distance * cos(clamped) * cos(p_yaw))


## The full camera transform, looking at the hub.
##
## Public and static for the reason in the header: this is the whole of the view's geometry, and a
## test can assert where "top" looks from without a World3D, a frame or a window.
static func camera_transform(p_yaw: float, p_pitch: float, p_radius_m: float) -> Transform3D:
	var distance := maxf(p_radius_m, 0.001) * DISTANCE_TO_RADIUS
	var eye := camera_position(p_yaw, p_pitch, distance)
	# `looking_at(-eye, UP)` and NOT `looking_at(-eye, UP, true)`. The third argument selects the
	# MODEL-FRONT convention, which aims +Z at the target; a Camera3D looks down -Z, so passing it
	# points the camera directly away from the blade. Both transforms are orthonormal, both put the
	# camera in exactly the right place, and the only symptom is an empty viewport — which is how
	# this shipped in the room's first capture, and why `test_blade_room.gd` now asserts where the
	# camera LOOKS and not only where it sits.
	return Transform3D().looking_at(-eye, Vector3.UP).translated(eye)


func _apply_camera() -> void:
	if _camera == null:
		return
	_camera.transform = camera_transform(yaw, pitch, radius_m)
	_poke()


func _poke() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# ---------------------------------------------------------------------------
# Orbiting
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * DRAG_SENSITIVITY
		# Clamped rather than wrapped: past the poles the view flips over and a builder loses which
		# way up the blade is, which is the one thing this view is for.
		pitch = clampf(pitch + event.relative.y * DRAG_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		_apply_camera()
		accept_event()


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_mesh.rebuild(_prop, _document)
	# Stopped, deliberately — see the header. The rate is set through the same input Lab and Sim
	# use rather than by reaching into the mesh, so this view has no privileged path.
	_mesh.set_rate_rpm(0.0)
	_rebuild_markers()
	_apply_camera()


func _rebuild_markers() -> void:
	if _markers == null:
		return
	for child in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()

	_markers.add_child(_ring(_caret_r_frac, LothalTheme.ACCENT, 0.9))
	var i := 0
	while i + 1 < _stall_bands.size():
		# Both edges of every stalled stretch, rather than one ring at its middle: the fact worth
		# reading off the shape is WHERE the stall starts and stops, and a single marker gives
		# neither.
		_markers.add_child(_ring(_stall_bands[i], LothalTheme.DANGER, 0.8))
		_markers.add_child(_ring(_stall_bands[i + 1], LothalTheme.DANGER, 0.8))
		i += 2
	_poke()


## A flat ring lying in the disc plane at a fraction of radius.
func _ring(r_frac: float, colour: Color, alpha: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	var r := maxf(r_frac, 0.001) * radius_m
	torus.inner_radius = maxf(r - radius_m * 0.004, 0.0001)
	torus.outer_radius = r + radius_m * 0.004
	torus.rings = 48
	ring.mesh = torus
	# `ring_material` and not `material`: `material` is a property on CanvasItem, which this class
	# inherits through SubViewportContainer, and the project treats shadowing as an error.
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_material
	return ring
