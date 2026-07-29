class_name CourseRenderer
extends Node3D
## Renders what GateCourse describes. It holds no course state of its own — positions come
## from the course object, so the ring a pilot aims at and the ring the timer scores are
## guaranteed to be the same ring.
##
## The next gate is lit and the rest are dim, which is the entire navigation aid: week1.md's
## day 6 gate is "someone who has never seen it completes a lap with no explanation", and a
## stranger will not infer a running order from eight identical hoops.

## Thick enough to read as a structure at 18 m. The first pass used 9 cm, which is honest
## to a real race gate's tubing and rendered as an almost invisible pencil line — the ring
## has to be legible from the far side of the course or it cannot be aimed at.
const RING_THICKNESS_M := 0.18

const COLOR_NEXT := Color(0.30, 0.85, 1.0)
## Idle gates are dimmer than the target but still clearly lit: a pilot needs to see the
## shape of the whole circuit to plan a line, not just the next hoop in isolation.
const COLOR_IDLE := Color(0.62, 0.66, 0.74)
const COLOR_START_FINISH := Color(1.0, 0.62, 0.20)

var course: GateCourse
var _ring_materials: Array[StandardMaterial3D] = []

func _init(p_course: GateCourse) -> void:
	course = p_course

func _ready() -> void:
	for i in course.gates.size():
		add_child(_build_gate(course.gates[i], i))
	highlight_next()

func _build_gate(gate: Dictionary, index: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = gate["position"]
	# The torus's hole faces its local +Y, so stand it up and turn it to face down-course.
	pivot.basis = Basis.looking_at(gate["normal"], Vector3.UP) * Basis(Vector3(1, 0, 0), PI / 2.0)

	var mesh := TorusMesh.new()
	mesh.inner_radius = float(gate["radius"])
	mesh.outer_radius = float(gate["radius"]) + RING_THICKNESS_M

	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_IDLE
	# Emissive so a gate reads clearly against the sky at distance, where a lit-only material
	# on a thin ring washes out to nothing.
	material.emission_enabled = true
	material.emission = COLOR_IDLE
	material.emission_energy_multiplier = 1.0
	_ring_materials.append(material)

	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = material
	pivot.add_child(ring)

	# A post down to the ground, so a gate reads as an object in the world rather than a
	# ring floating in a void — it is most of what sells the sense of altitude.
	var post_height: float = float(gate["position"].y) - float(gate["radius"])
	if post_height > 0.05:
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.04
		post_mesh.bottom_radius = 0.06
		post_mesh.height = post_height
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		var post_material := StandardMaterial3D.new()
		post_material.albedo_color = Color(0.18, 0.19, 0.22)
		post.material_override = post_material
		# Back into world-space down, since the pivot above is rotated to face down-course.
		post.position = pivot.basis.inverse() * Vector3(0, -(post_height * 0.5 + float(gate["radius"])), 0)
		post.basis = pivot.basis.inverse()
		pivot.add_child(post)

	pivot.name = "Gate_%d" % (index + 1)
	return pivot

## Lights the gate that is due and dims the others. Gate 1 doubles as start/finish and keeps
## a distinct colour when it is not the active target.
func highlight_next() -> void:
	for i in _ring_materials.size():
		var material := _ring_materials[i]
		var color := COLOR_IDLE
		if i == course.next_gate_index:
			color = COLOR_NEXT
		elif i == 0:
			color = COLOR_START_FINISH
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 2.4 if i == course.next_gate_index else 1.0
