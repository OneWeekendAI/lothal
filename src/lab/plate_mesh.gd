class_name PlateMesh
extends RefCounted
## Turning a plate's outline into the solid you see — airframe.md §7.2.
##
## ## The one line §7.2 asks for
##
## > `extrude(outline, thickness)` per plate, positioned at its `z`. **Nothing here is authored.**
##
## That is this file. Before it, `FrameModel` drew a frame from ratios — an arm was `L/8` wide
## because a constant said so, and half as thick as it was wide because another one did — so the
## picture and the physics were two descriptions of the same aircraft that nothing kept in step. You
## could not widen an arm, because there was nothing to widen: there was only a number the box mesh
## was scaled by.
##
## Extruding the document's own polygon closes that gap by construction. The mesh has the vertices
## the mass integral has, so a frame that looks wrong weighs wrong, and there is no third
## representation for either to drift against.
##
## ## Holes are cut in the plan view and not in the solid
##
## §7.2's formula takes an outline and a thickness, and that is deliberate: a bolt hole is 3 mm on a
## 300 mm frame, invisible at any zoom where you can see the whole aircraft, and cutting it properly
## means a polygon-with-holes triangulator. The holes are real — they are in the document, they are
## drawn in the plan view where you place them, and their area comes OUT of the mass sum through
## `PolygonProps` — they are simply not modelled in the solid. That is a stated omission in the
## picture, not a disagreement about the frame.
##
## ## Units
##
## Millimetres in (the document's language), metres out (the simulation's). `AirframeDocument.
## world_m` owns the u → X, v → Z, z → Y mapping and is used here rather than restated, because a
## frame drawn on one convention and weighed on another is the transposition trap
## `AirframeProperties` spends a screen warning about.


## An extruded plate as an ArrayMesh, or null when the outline cannot make a solid.
##
## CENTRED ON ITS OWN ORIGIN, with the height left to the node that carries it. The mesh is the
## SHAPE of a plate; where that plate sits in the stack is a property of the assembly, and a
## `MeshInstance3D.position` is where every other part of this app already keeps that. Baking the
## height into the vertices instead makes the node's own transform a lie — it reads (0, 0, 0) for a
## plate 20 mm up — and anything asking "how far apart are these two plates" gets zero.
static func extrude(
	outline: PackedVector2Array,
	thickness_mm: float
) -> ArrayMesh:
	if outline.size() < 3 or thickness_mm <= 0.0:
		return null

	# Triangulated ONCE, on the flat polygon, and reused for both faces. Godot's triangulator wants
	# a simple polygon and returns indices into the points it was given, so a self-intersecting
	# outline — which a builder can absolutely draw — comes back empty rather than as garbage.
	var indices := Geometry2D.triangulate_polygon(outline)
	if indices.is_empty():
		return null

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var signed_area := PolygonProps.area(outline)

	var bottom_y := -thickness_mm * 0.5
	var top_y := thickness_mm * 0.5

	var count := int(indices.size() / 3.0)
	for triangle in count:
		var a := indices[triangle * 3]
		var b := indices[triangle * 3 + 1]
		var c := indices[triangle * 3 + 2]
		_add_face(vertices, normals,
			AirframeDocument.world_m(outline[a], top_y),
			AirframeDocument.world_m(outline[b], top_y),
			AirframeDocument.world_m(outline[c], top_y),
			Vector3.UP)
		_add_face(vertices, normals,
			AirframeDocument.world_m(outline[a], bottom_y),
			AirframeDocument.world_m(outline[b], bottom_y),
			AirframeDocument.world_m(outline[c], bottom_y),
			Vector3.DOWN)

	# The rim: one quad per edge of the outline. This is what makes a plate read as stock with a
	# thickness rather than as a decal, and on an arm it is the surface that shows the 5 mm the
	# resonance maths cares about.
	for i in outline.size():
		var p0 := outline[i]
		var p1 := outline[(i + 1) % outline.size()]
		var edge := p1 - p0
		if edge.length_squared() <= 0.0:
			continue
		# Which side of an edge is "out" depends on the outline's winding, which a builder can
		# reverse simply by drawing a plate the other way round. Taken from the SIGNED AREA rather
		# than assumed, so both windings produce a solid with its rim facing outwards.
		var outward := Vector3(edge.y, 0.0, -edge.x).normalized()
		if signed_area < 0.0:
			outward = -outward
		var a := AirframeDocument.world_m(p0, bottom_y)
		var b := AirframeDocument.world_m(p1, bottom_y)
		var c := AirframeDocument.world_m(p1, top_y)
		var d := AirframeDocument.world_m(p0, top_y)
		_add_face(vertices, normals, a, b, c, outward)
		_add_face(vertices, normals, a, c, d, outward)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Appends one triangle wound so that it FACES the way it says it does.
##
## The winding is decided by measuring, not by reasoning about it. Godot culls back faces, so a
## triangle wound the wrong way is not a subtly wrong shade — it is invisible, and a whole frame
## drawn that way looks like four motors floating in mid-air, which is exactly what the first
## version of this file produced. The argument that got it wrong (which way the v axis points once
## it becomes world +Z, and what that does to a triangulator's winding) is precisely the kind of
## thing to stop arguing about and check: the cross product either points the intended way or it
## does not, and if it does not the two vertices swap.
##
## `test_plate_mesh.gd` asserts the invariant this maintains — every face's geometric normal agrees
## with the normal stored beside it — for both windings of the same plate.
static func _add_face(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	a: Vector3, b: Vector3, c: Vector3,
	normal: Vector3
) -> void:
	# GODOT WINDS FRONT FACES CLOCKWISE, so a triangle whose RIGHT-HAND-RULE normal points the way
	# the surface faces is the one that gets culled. The test is therefore inverted relative to the
	# textbook: the winding that survives is the one whose cross product points INTO the solid.
	# Verified by rendering rather than by argument — the first two versions of this line were both
	# defensible and both produced a frame you could not see.
	if (b - a).cross(c - a).dot(normal) <= 0.0:
		vertices.append(a); vertices.append(b); vertices.append(c)
	else:
		vertices.append(a); vertices.append(c); vertices.append(b)
	for i in 3:
		normals.append(normal)
