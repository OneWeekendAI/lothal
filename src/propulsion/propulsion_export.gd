class_name PropulsionExport
## Propulsion's printable parts, out to STL — plans/2026-08-26-propulsion-room-design.md §1, the
## P10f row ("Guards and mounts export as STL via `StlWriter`").
##
## ## What is exported, and what is deliberately not
##
## Two things: the **guard**, which is the printed part of a propulsion system and the reason this
## exists; and the **mount stack**, which is not printed at all and is exported for fit. A guard
## you have designed a clearance for is a part you send to a printer. A motor stack is a part you
## drop into somebody else's CAD to check that your camera clears the bell, or that the frame you
## are drawing has room for the pad under it — which is the same reason `FrameExport` emits an
## assembly STL of a frame nobody prints.
##
## The propeller is NOT here. A blade is a foil whose section this app authors at 40 stations for
## a physics integral, and a printed propeller is a part whose surface finish, balance and layer
## adhesion decide whether it survives 20,000 rpm — none of which this model knows anything about.
## Emitting one would be handing a builder a file that looks like a propeller. Named here rather
## than left missing, on the same posture P10b took with the exports it refused.
##
## ## Where the geometry comes from, and why it is not built here
##
## Neither solid is modelled in this file. The guard's annulus is `GuardMesh.ring_triangles_mm()`
## — the same triangles the ring on screen is built from — and the stack is read off the cylinders
## `MotorMesh` generated, in the manner `PropellerMountProfile.parts()` already reads them. That is
## the rule the whole propulsion room holds: what you look at is what the physics read, and now
## also what the printer gets. A second copy of either shape here could disagree with the picture,
## and a disagreement in an exported solid is one nobody sees until the part is in their hand.
##
## The one thing this file DOES build is the closed cylinder for a stack part, because `CylinderMesh`
## is a Godot resource with no triangle accessor and the profile view only ever needed its radius
## and its extent. It is wound outward and checked like everything else.

## Segments around a stack cylinder. `MotorMesh` draws each part at a segment count chosen for how
## it reads on screen (28 for a bell, 10 for a shaft); a fit check wants them consistent, and 32 is
## fine enough that a 3 mm shaft is round to 0.01 mm — beneath what any of these parts is toleranced
## to and beneath the nozzle of anything that would print it.
const STACK_SEGMENTS := 32


## The guard's ring as printable triangles, in millimetres. Empty when the build fits no guard, or
## when `PropGuard` refuses the spec — the same posture `GuardMesh.rebuild` and
## `PropGuard.as_part_mass` both take: an unreadable part produces no part.
##
## Builds and frees its own `GuardMesh` rather than taking a live one, because the caller with a
## guard record in hand (an inspector row) is not the caller with the aircraft's ring node in hand
## (the 3D view), and asking the inspector to reach into the scene for it would make the export
## depend on the guard being on screen.
static func guard_triangles_mm(guard: Dictionary, prop_tip_radius_m: float) -> Array:
	var mesh := GuardMesh.new()
	mesh.rebuild(guard, prop_tip_radius_m)
	var triangles := mesh.ring_triangles_mm()
	mesh.free()
	return triangles


## Writes the guard, or refuses by name. Returns StlWriter's own report.
##
## The solid is named for the part id rather than for the file, so a folder of exports opened in a
## slicer shows which catalog entry each one is — an STL's solid name is the only identity that
## survives being renamed on the way to somebody else's machine.
static func write_guard(guard: Dictionary, prop_tip_radius_m: float, path: String) -> Dictionary:
	var part_id := String(guard.get("part_id", "guard"))
	return StlWriter.write(part_id, guard_triangles_mm(guard, prop_tip_radius_m), path)


## The motor's mount stack as printable triangles, in millimetres, read off the cylinders
## `MotorMesh` generated.
##
## **Several closed shells that interpenetrate, deliberately.** A base, a bell, an adapter, a shaft
## and a nut overlap where they are assembled, every one of them is individually closed and wound
## outward, and every slicer resolves that union. Boolean-unioning them here would be writing a
## slicer — the same judgement track.md W1P.3 records about holes ("tessellated, not subtracted —
## Godot CSG is not slicer-grade"). `StlWriter.check_manifold` allows it for that reason and says
## so in its own header.
static func mount_stack_triangles_mm(motor_mesh: MotorMesh) -> Array:
	var out: Array = []
	if motor_mesh == null:
		return out
	# The profile view is the thing that knows how to read a generated stack back — one reader,
	# and this export is its second caller rather than a second reader. Constructed and freed here
	# because it is a Control and nothing is putting it on screen.
	var profile := PropellerMountProfile.new(motor_mesh)
	var stack := profile.parts()
	profile.free()
	for part in stack:
		var radius_mm := float(part["radius_m"]) * StlWriter.MM_PER_M
		var bottom_mm := float(part["bottom_m"]) * StlWriter.MM_PER_M
		var top_mm := float(part["top_m"]) * StlWriter.MM_PER_M
		out.append_array(cylinder_triangles_mm(radius_mm, bottom_mm, top_mm))
	return out


static func write_mount_stack(motor_mesh: MotorMesh, solid_name: String, path: String) -> Dictionary:
	return StlWriter.write(solid_name, mount_stack_triangles_mm(motor_mesh), path)


## A closed cylinder on the Z axis, wound outward: the side, then a fan cap at each end.
##
## The caps fan from the axis rather than from a rim vertex, which costs one extra triangle per
## segment and buys a cap whose triangles all have area — a fan from the rim degenerates at the two
## triangles adjacent to its own hub, and `StlWriter` refuses a zero-area facet by name.
static func cylinder_triangles_mm(radius_mm: float, bottom_mm: float, top_mm: float) -> Array:
	var out: Array = []
	if radius_mm <= 0.0 or top_mm <= bottom_mm:
		return out

	var centre_bottom := Vector3(0, 0, bottom_mm)
	var centre_top := Vector3(0, 0, top_mm)
	for i in STACK_SEGMENTS:
		var theta_a := TAU * float(i) / float(STACK_SEGMENTS)
		var theta_b := TAU * float((i + 1) % STACK_SEGMENTS) / float(STACK_SEGMENTS)
		var ba := Vector3(radius_mm * cos(theta_a), radius_mm * sin(theta_a), bottom_mm)
		var bb := Vector3(radius_mm * cos(theta_b), radius_mm * sin(theta_b), bottom_mm)
		var ta := Vector3(radius_mm * cos(theta_a), radius_mm * sin(theta_a), top_mm)
		var tb := Vector3(radius_mm * cos(theta_b), radius_mm * sin(theta_b), top_mm)
		# Side — normals away from the axis.
		out.append(PackedVector3Array([ba, bb, tb]))
		out.append(PackedVector3Array([ba, tb, ta]))
		# Top cap (+Z) and bottom cap (−Z).
		out.append(PackedVector3Array([centre_top, ta, tb]))
		out.append(PackedVector3Array([centre_bottom, bb, ba]))
	return out
