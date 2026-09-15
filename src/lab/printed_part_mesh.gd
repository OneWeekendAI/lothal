class_name PrintedPartMesh
extends Node3D
## One printed part, drawn — printed-room slices PR16–PR18. The drawing is the part's own
## `triangles_mm` and nothing else: millimetres to metres through a PROPER rotation from the part's
## print frame into this node's frame, so what is drawn is wound the way what is printed is wound (the
## drawn signed volume keeps its sign).
##
## AirframeModel decides where the node goes, from the same seat the mass model weighs (mast, pad) or
## from the drawn component the part holds (camera cheeks, antenna mount). Nothing here decides a seat.
##
## The three print frames in use, each written as where print X, Y and Z go (all determinant +1):

## Z up, +Y towards the nose: GuardMesh's `_to_local_m`. The GPS mast and the battery pad.
const Z_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
## The camera cheek: the silhouette in (X forward, Y up), thickness along Z, which lands across the aircraft.
const CHEEK := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
## The antenna mount: standoffs along X, +Y aft, Z up. X is mirrored to keep the rotation proper; the
## mount is symmetric across X, so the mirror changes nothing drawn.
const AFT_Y := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))

const TPU_COLOR := Color(0.85, 0.42, 0.16)

var triangle_count := 0
var _mesh_instance: MeshInstance3D


func rebuild(triangles_mm: Array, print_frame: Basis) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	triangle_count = 0
	_mesh_instance = null
	if triangles_mm.is_empty():
		return
	triangle_count = triangles_mm.size()

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in triangles_mm:
		for point in triangle:
			tool.add_vertex(print_frame * (point as Vector3) / StlWriter.MM_PER_M)
	tool.generate_normals()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Solid"
	_mesh_instance.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TPU_COLOR
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## Vertices handed to the GPU, in THIS node's frame. Three per triangle.
func drawn_vertices_m() -> PackedVector3Array:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return PackedVector3Array()
	var arrays := (_mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array


## The drawn vertices where they are seated, in the parent's frame (no tree needed).
func seated_vertices_m() -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in drawn_vertices_m():
		out.append(transform * v)
	return out
