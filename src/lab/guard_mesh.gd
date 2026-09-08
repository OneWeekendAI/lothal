class_name GuardMesh
extends Node3D
## Prop guard drawn as a peer of PropellerMesh — plans/2026-08-26-propulsion-room-design.md §5
## P10c. Not a child of PropellerMesh and not a member of that class: a guard is neither a blade
## nor a hub, PropellerMesh's own invariants are asserted against its source file (blades sharing
## one mesh, blur disc above max_discrete_rpm, class naming no speed of its own — see
## tests/test_prop_rotation.gd), and adding ring geometry there would either break those
## assertions or hide behind them. So the ring lives here, and the propeller class stays
## exactly what test_prop_rotation.gd's grep says it is.
##
## ## The one non-obvious line — and it is the whole point of this file
##
## The ring's inner wall is not `(outer_radius - wall)` computed here. It is read out of
## PropGuard.tip_clearance_mm(spec, prop_tip_radius_mm) as
##
##     inner_radius_m = (prop_tip_radius_mm + tip_clearance_mm) * 0.001
##
## The recomputation would be a second copy of the geometry PropGuard already owns, and the
## failure would be silent: measuring the visible gap from `outer_radius_mm - prop_tip_radius_mm`
## instead of from `tip_clearance_mm` reports a gap `wall_mm` too wide, which on the reference
## cinewhoop (outer 68, wall 3, tip 63.5) draws the annular gap as 4.5 mm instead of 1.5 mm —
## THREE TIMES too fat. tests/test_guard_mesh.gd asserts a mutation that does exactly that fails.
## §5's P10c bullet names this mutation-tested check as the load-bearing proof.
##
## ## What the ring is
##
## An extruded annulus at the motor's plan position. Inner radius derived above; outer radius is
## inner + wall (the wall the spec declares, unchanged); height is the ring's own extruded height.
## Y is centred on the propeller disc, because that is what a shroud wraps and it is where the
## clearance the number describes lives. Nothing here decides where the guard sits along the arm —
## AirframeModel parents this node onto the arm-tip pad the motor already sits on, so the guard
## rides the motor for free and a frame rebuild takes it with it.
##
## ## The ring polygon, for the camera-frustum check
##
## §5 P10c also asks for the guard's ring polygon in the same containment test the arms use. That
## arm frustum check does not exist in the repo today (grep for `frustum` returns nothing under
## src/), so `ring_polygon_m` is exposed but no caller reads it yet. The polygon shape is a
## 32-segment circle at `outer_radius_m` about the guard's plan position — the honest silhouette
## for the visibility question the check exists to ask. The wiring is P10c's deferred half, called
## out in the plan doc's own as-built note so the gap is a scheduled slice rather than a
## discovery.
##
## The plan CENTRE is a parameter rather than this node's own `position`, and that is not a
## style choice. AirframeModel parents the ring onto the arm-tip pad, so its own transform is
## `(0, disc_y, 0)` — its local XZ is the pad's origin, not the motor's plan position. A polygon
## built from `position` would put all four rings on top of each other at the aircraft's centre,
## and a frustum check reading them would answer a question about an aircraft nobody built. The
## caller that KNOWS the plan position passes it: `AirframeModel.guard_ring_polygons_m()` takes
## it from `MotorLayout.motor_position`, the same source `footprint_prop_clearance_m` reads, so
## there is one definition of where a motor is and the ring cannot drift from the disc it wraps.
##
## ## Rotation
##
## A guard is a fixed part. It has no rate, no `_process`, and no member whose name contains
## `RPM`, `SPEED`, `REV_PER`, or `OMEGA`. If tests/test_prop_rotation.gd is extended to sweep more
## files against its no-speed grep, this one passes it unchanged. Nothing here derives motion
## from anywhere.

const RADIAL_SEGMENTS := 32

## The visible inner wall of the ring, in metres. Derived from PropGuard.tip_clearance_mm as
## `(prop_tip_radius + clearance) * 0.001`, so a mutation from `clearance` to
## `outer_radius - prop_tip_radius` is caught by inner_radius_m alone.
var inner_radius_m := 0.0
## The outer wall — inner + wall_mm. Not read directly from the spec, so a drift between the two
## definitions of the ring cannot happen.
var outer_radius_m := 0.0
var wall_m := 0.0
var height_m := 0.0
## What was read out of PropGuard for this build, cached so a test can compare drawn inner wall
## against the source of it without re-calling PropGuard itself. NAN when no guard is fitted or
## the spec was one PropGuard refused.
var tip_clearance_mm_value := NAN

var _mesh_instance: MeshInstance3D


## Regenerates the guard geometry from `guard` (the whole catalog record — same shape as
## `Build.guard`), given `prop_tip_radius_m` in metres (the propeller's own `radius_m`, which is
## what `AirframeModel` already has in hand next to the motor loop).
##
## An empty `guard` clears any previous geometry and leaves the node empty — an aircraft that
## fits no guard shows no ring, which is what "no guard" means. A spec `PropGuard.compute()`
## refuses does the same, on the same posture `PropGuard.as_part_mass` takes for mass: an
## unreadable part draws no part rather than a class-typical default.
func rebuild(guard: Dictionary, prop_tip_radius_m: float) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	inner_radius_m = 0.0
	outer_radius_m = 0.0
	wall_m = 0.0
	height_m = 0.0
	tip_clearance_mm_value = NAN
	_mesh_instance = null

	if guard.is_empty() or prop_tip_radius_m <= 0.0:
		return

	var spec: Dictionary = guard.get("specs", {})
	var prop_tip_radius_mm := prop_tip_radius_m * 1000.0

	# The load-bearing read — see this file's header. Not a second geometry copy.
	var clearance_mm := PropGuard.tip_clearance_mm(spec, prop_tip_radius_mm)
	if is_nan(clearance_mm):
		return

	var wall_mm := float(spec.get("wall_mm", 0.0))
	var height_mm := float(spec.get("height_mm", 0.0))
	if wall_mm <= 0.0 or height_mm <= 0.0:
		return

	inner_radius_m = (prop_tip_radius_mm + clearance_mm) * 0.001
	wall_m = wall_mm * 0.001
	outer_radius_m = inner_radius_m + wall_m
	height_m = height_mm * 0.001
	tip_clearance_mm_value = clearance_mm

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GuardRing"
	_mesh_instance.mesh = _build_ring_mesh()
	_mesh_instance.material_override = _material_for(guard)
	add_child(_mesh_instance)


## The ring's silhouette in plan view — a 32-segment circle at `outer_radius_m` about
## `centre_xz`, the guard's position in the airframe's own XZ plane. Empty when no ring was
## built.
##
## For the camera-frustum containment test §5 P10c asks for, which the arm version of this
## check does not yet exist for in the codebase. Exposed so it is there the day the arm check
## lands and the guard just plugs into it, rather than becoming a second bit of code that has
## to catch up to a landed feature.
##
## `centre_xz` has no default on purpose — see this file's header. The node's own `position` is
## in its parent pad's frame and is NOT the plan position, so a default of `position` would be
## a wrong answer that looks like a right one.
func ring_polygon_m(centre_xz: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if outer_radius_m <= 0.0:
		return out
	var origin_xz := centre_xz
	for i in RADIAL_SEGMENTS:
		var theta := TAU * float(i) / float(RADIAL_SEGMENTS)
		out.append(origin_xz + Vector2(cos(theta), sin(theta)) * outer_radius_m)
	return out


## The ring as printable triangles: millimetres, Z up, wound OUTWARD, centred on the origin.
##
## **This is the ONE definition of the annulus.** `_build_ring_mesh` consumes it rather than
## building a second one, which is the same rule this file already holds for the inner wall: a
## second copy can disagree, and the disagreement here would be invisible on screen. The screen
## draws with `CULL_DISABLED` and generated normals, so a ring wound inside out looks identical;
## a slicer reading the same ring produces a part with the outside missing. Sharing the geometry
## means the winding StlWriter checks is the winding the picture was made from.
##
## Z UP rather than the node's own Y up, because that is the STL convention and every tool that
## opens one expects it — the same statement `FrameExport.to_stl` makes for a plate. The mesh
## rotates it back by -90° about X, which is a proper rotation and therefore preserves both the
## winding and the normals.
##
## Empty when no ring was built, on the same posture as `ring_polygon_m`: an aircraft that fits
## no guard exports no guard rather than a zero-radius one.
func ring_triangles_mm() -> Array:
	var out: Array = []
	if outer_radius_m <= 0.0 or height_m <= 0.0 or inner_radius_m <= 0.0:
		return out

	var inner := inner_radius_m * StlWriter.MM_PER_M
	var outer := outer_radius_m * StlWriter.MM_PER_M
	var half_h := height_m * StlWriter.MM_PER_M * 0.5
	var seg := RADIAL_SEGMENTS

	for i in seg:
		var theta_a := TAU * float(i) / float(seg)
		var theta_b := TAU * float((i + 1) % seg) / float(seg)
		var ib_a := Vector3(inner * cos(theta_a), inner * sin(theta_a), -half_h)
		var it_a := Vector3(inner * cos(theta_a), inner * sin(theta_a), half_h)
		var ot_a := Vector3(outer * cos(theta_a), outer * sin(theta_a), half_h)
		var ob_a := Vector3(outer * cos(theta_a), outer * sin(theta_a), -half_h)
		var ib_b := Vector3(inner * cos(theta_b), inner * sin(theta_b), -half_h)
		var it_b := Vector3(inner * cos(theta_b), inner * sin(theta_b), half_h)
		var ot_b := Vector3(outer * cos(theta_b), outer * sin(theta_b), half_h)
		var ob_b := Vector3(outer * cos(theta_b), outer * sin(theta_b), -half_h)

		# Outer wall — normals point away from the axis.
		out.append(PackedVector3Array([ob_a, ob_b, ot_b]))
		out.append(PackedVector3Array([ob_a, ot_b, ot_a]))
		# Inner wall — the bore, so its normals point BACK towards the axis. This is the face a
		# ring wound naively gets wrong, because it is the one whose outward direction is inward.
		out.append(PackedVector3Array([ib_a, it_b, ib_b]))
		out.append(PackedVector3Array([ib_a, it_a, it_b]))
		# Top (+Z) and bottom (−Z) annular faces.
		out.append(PackedVector3Array([it_a, ot_a, ot_b]))
		out.append(PackedVector3Array([it_a, ot_b, it_b]))
		out.append(PackedVector3Array([ib_a, ob_b, ob_a]))
		out.append(PackedVector3Array([ib_a, ib_b, ob_b]))

	return out


## The drawn ring, built from `ring_triangles_mm` — see that function for why there is only one
## annulus in this file. Millimetres come back to metres and Z-up comes back to the node's Y-up
## through `_to_local_m`, which is a rotation and not a reflection, so what is drawn is wound the
## way what is printed is wound.
func _build_ring_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in ring_triangles_mm():
		for point in triangle:
			tool.add_vertex(_to_local_m(point))
	tool.generate_normals()
	return tool.commit()


## Millimetres, Z up (the print frame) to metres, Y up (this node's frame). A -90° rotation about
## X: proper, so winding and normals survive it, which is what lets one triangle list serve both
## the screen and the slicer.
static func _to_local_m(point_mm: Vector3) -> Vector3:
	return Vector3(point_mm.x, point_mm.z, -point_mm.y) / StlWriter.MM_PER_M


## Appearance from the catalog record's `material` field, in the manner of MotorMesh /
## PropellerMesh — the same short palette, so a moulded ABS shroud reads the same as an ABS
## motor cap next to it. Neutral default for a catalog entry the material of which the
## contributor has not filled in.
func _material_for(guard: Dictionary) -> StandardMaterial3D:
	var material_name := String(guard.get("catalog", {}).get("material", "")).to_lower()
	var mat := StandardMaterial3D.new()
	if material_name.contains("abs"):
		mat.albedo_color = Color(0.30, 0.31, 0.33)
		mat.roughness = 0.55
	elif material_name.contains("tpu"):
		mat.albedo_color = Color(0.22, 0.23, 0.26)
		mat.roughness = 0.7
	elif material_name.contains("nylon"):
		mat.albedo_color = Color(0.40, 0.40, 0.38)
		mat.roughness = 0.5
	else:
		mat.albedo_color = Color(0.35, 0.36, 0.38)
		mat.roughness = 0.5
	mat.metallic = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
