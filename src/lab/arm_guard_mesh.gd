class_name ArmGuardMesh
extends Node3D
## One arm guard, drawn — printed-room slice PR1. The drawing is `ArmGuard.triangles_mm` and nothing
## else: millimetres back to metres, and the print frame (bore along X, Z up) turned into this node's
## frame (bore along X, Y up) by the same proper rotation GuardMesh uses, so what is drawn is wound the
## way what is printed is wound.
##
## AirframeModel seats it at `ArmGuard.seat_position_m` and turns its X onto the arm. Nothing here
## decides where a sleeve goes.

var triangle_count := 0
var _mesh_instance: MeshInstance3D


func rebuild(dims: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	triangle_count = 0
	_mesh_instance = null

	var triangles := ArmGuard.triangles_mm(dims)
	if triangles.is_empty():
		return
	triangle_count = triangles.size()

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in triangles:
		for point in triangle:
			tool.add_vertex(GuardMesh._to_local_m(point))
	tool.generate_normals()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Sleeve"
	_mesh_instance.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.42, 0.16)
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## Vertices actually handed to the GPU. Three per triangle when the drawing is the triangle list.
func drawn_vertex_count() -> int:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return 0
	var arrays := (_mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


## Turns local X onto the arm direction in plan, about Y. Static so a test can check the sign without a
## node in the tree (`look_at` does nothing outside it).
static func arm_basis(motor_name: String) -> Basis:
	var dir := MotorLayout.motor_position(motor_name, 1.0).normalized()
	return Basis(Vector3.UP, atan2(-dir.z, dir.x))
