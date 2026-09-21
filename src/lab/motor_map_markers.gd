class_name MotorMapMarkers
extends Node3D
## The motor map, drawn ON THE AIRCRAFT — Config room slice C3
## (plans/2026-09-20-config-room-design.md §4.3).
##
## Four markers, one per arm tip: the motor's number in Betaflight's numbering, the direction it is
## configured to turn, and an arrow swept that way around the propeller disc.
##
## ## Why this is the section that justifies the room being in a 3D app
##
## §4.3's argument, and it is the reason this node exists rather than a diagram in the panel: every
## motor-order picture a builder can google is of A quad. This is of THEIRS — their arm length,
## their props, whatever is in the way — so the map they are about to check against a Configurator
## is drawn on the aircraft they designed rather than on a stock five-inch.
##
## ## The arrow is not decoration
##
## A label alone would let the picture lie in the one way that matters here: the rotor a builder
## watches turning and the text beside it could disagree, and the rotor is what is believed. So the
## arrow's WINDING is generated from the same signed value that reaches `PropellerMesh.spin` and
## `MotorMixer.mix()` — `MotorLayout.spin_map(build.config)`, the single accessor C2 built — and a
## test reads the winding back off the drawn points rather than off the field.
##
## ## Everything here is read, nothing is decided
##
## The positions are `MotorLayout.motor_position`, which is the point the physics measures its
## torque arm from; the radius is the fitted propeller's own drawn radius, handed in by the
## assembler. Neither is re-derived here — a second copy of either would be a picture that agrees
## with the aircraft until the day it does not.
##
## Hidden by default. The map belongs to the section that asks the question (GlassShell shows it
## while Config is focused); four labels floating over the aircraft in Sim would be Lab's chrome in
## the field.

## How many points the swept arrow is drawn with. Enough that the winding is unambiguous and the
## curve does not read as a polygon at any radius in the catalog.
const ARROW_SEGMENTS := 16

## How much of a full turn the arrow sweeps. Three-quarters would close into a circle and lose the
## start-to-end reading that makes it an arrow at all.
const ARROW_SWEEP_RAD := TAU * 0.55

## Where the arrow is drawn, as a fraction of the propeller's swept radius. Inside the disc, so the
## arrow describes the rotor rather than a ring of its own beside it.
const ARROW_RADIUS_FRACTION := 0.72

## Where the label sits above the arm tip, in metres. Clear of the motor bell on every build in the
## catalog, which is a legibility choice and nothing more.
const LABEL_HEIGHT_M := 0.035

## How big the text is drawn. Label3D's own units: metres per pixel of the rasterised glyph.
const LABEL_PIXEL_SIZE := 0.0004

## motor name -> Label3D.
var labels: Dictionary = {}
## motor name -> MeshInstance3D holding the swept arrow.
var arrows: Dictionary = {}
## motor name -> the marker's root Node3D, seated at the arm tip.
var markers: Dictionary = {}

var _arrow_points: Dictionary = {}


func _init() -> void:
	name = "MotorMap"
	# Down until the room that asks for it is open. The aircraft is the default picture.
	visible = false


## Draws the map for this build. `radius_m` is the drawn propeller's swept radius — handed in by
## whoever assembled the aircraft, because the propeller already knows it and this node deciding a
## radius of its own is the second copy §4.3 warns about.
func rebuild(build: Build, radius_m: float) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	labels.clear()
	arrows.clear()
	markers.clear()
	_arrow_points.clear()

	# THE ONE ACCESSOR, and the whole point of drawing this at all: what is on screen is what the
	# mixer and the torque model read, not a second opinion about which way a motor goes.
	var spin := MotorLayout.spin_map(build.config)
	var arrow_radius: float = maxf(radius_m, 0.0) * ARROW_RADIUS_FRACTION

	for motor_name in MotorLayout.MOTOR_NAMES:
		var direction := float(spin[motor_name])
		var marker := Node3D.new()
		marker.name = "Marker_%s" % motor_name
		marker.position = MotorLayout.motor_position(motor_name, build.arm_m)
		add_child(marker)
		markers[motor_name] = marker

		var points := _sweep(arrow_radius, direction)
		_arrow_points[motor_name] = points
		var arrow := MeshInstance3D.new()
		arrow.name = "Arrow_%s" % motor_name
		arrow.mesh = _arrow_mesh(points)
		arrow.position = Vector3(0, LABEL_HEIGHT_M * 0.5, 0)
		marker.add_child(arrow)
		arrows[motor_name] = arrow

		var label := Label3D.new()
		label.name = "Label_%s" % motor_name
		label.text = "%s %s" % [motor_name, MotorLayout.direction_name(direction)]
		label.pixel_size = LABEL_PIXEL_SIZE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = LothalTheme.TEXT_MAIN
		label.position = Vector3(0, LABEL_HEIGHT_M, 0)
		marker.add_child(label)
		labels[motor_name] = label


## What one marker reads — "M1 CW", in Betaflight's numbering and the project's one spelling of a
## direction. Empty for a motor that has not been drawn.
func label_text(motor_name: String) -> String:
	if not labels.has(motor_name):
		return ""
	return String((labels[motor_name] as Label3D).text)


## Where the marker sits, in the airframe's own frame — `MotorLayout.motor_position`'s answer, read
## back off the node so a test measures the drawing rather than the intention.
func marker_position_m(motor_name: String) -> Vector3:
	if not markers.has(motor_name):
		return Vector3.ZERO
	return (markers[motor_name] as Node3D).position


## The arrow's points, in the marker's own frame and in the order they are drawn. Consecutive
## points wind the way the motor turns, about +Y.
func arrow_points_m(motor_name: String) -> PackedVector3Array:
	if not _arrow_points.has(motor_name):
		return PackedVector3Array()
	return _arrow_points[motor_name]


## A partial circle at `radius`, advancing in the sense a positive spin rotates about +Y. Godot
## rotates (1,0,0) to (cos θ, 0, −sin θ) for a positive θ about +Y, which is what the propeller
## itself does with the same sign — so the arrow and the rotor cannot wind opposite ways.
static func _sweep(radius: float, direction: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var sign_of := 1.0 if direction > 0.0 else -1.0
	for i in ARROW_SEGMENTS + 1:
		var theta := sign_of * ARROW_SWEEP_RAD * float(i) / float(ARROW_SEGMENTS)
		points.append(Vector3(radius * cos(theta), 0.0, -radius * sin(theta)))
	return points


static func _arrow_mesh(points: PackedVector3Array) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if points.size() < 2:
		return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	# The head, so the strip reads as an arrow rather than as an arc: two short segments folded
	# back from the last point toward the one before it.
	var tip := points[points.size() - 1]
	var back := points[points.size() - 2]
	var along := (tip - back)
	if along.length() > 0.0:
		along = along.normalized() * (tip.length() * 0.18)
		var inward := -tip.normalized() * (tip.length() * 0.12)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		mesh.surface_add_vertex(tip - along + inward)
		mesh.surface_add_vertex(tip)
		mesh.surface_add_vertex(tip - along - inward)
		mesh.surface_end()
	return mesh
