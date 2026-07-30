class_name PropellerMesh
extends Node3D
## Procedural propeller geometry, generated from diameter, pitch and blade count. Same rule as
## FrameModel and MotorMesh — read FrameModel's header for why nothing here is a fixed asset —
## but this is the one where the generated shape carries information no other view of the build
## does, so it is worth saying what the shape MEANS.
##
## A propeller is a helical surface. Pitch is the distance it would advance in one revolution
## if it did not slip, which fixes the blade angle at every radius:
##
##     tan(beta(r)) = pitch / (2*pi*r)
##
## So the angle is steep at the root and shallow at the tip, and a 4.8" pitch blade is visibly
## more feathered than a 4.3" one of the same diameter. That is not decoration: it is the same
## pitch number the physics reads through PropellerModel, drawn. A flat disc, or one blade mesh
## scaled to size, would let the picture and the physics disagree about the only prop property
## you cannot read off a spec line at a glance. tests/test_propeller_mesh.gd reads the angle
## back out of the generated vertices at every station and converts it to a pitch.
##
## Blades do NOT spin here. Lab is the garage and nothing in it flies (labs-and-sim.md §2);
## the spinning thrust stand is its own slice.
##
## Node layout after rebuild():
##   Hub        — the centre boss the blades come out of
##   Blade_0..N — one MeshInstance3D per blade, all sharing ONE generated mesh, each rotated
##                about the vertical by its share of a full turn
##
## The blades share a mesh deliberately: they are the same object bolted on at different
## angles, and generating three copies of identical vertices would be three chances for them
## to drift apart. Blade-local space has +X radial, so a blade's own mesh is independent of
## where it sits around the hub.

const INCH_M := 0.0254

## Radial stations along the blade. Fourteen is enough that the twist reads as a smooth
## surface rather than a run of flat facets; the cost is 4 vertices each.
const STATIONS := 14

## Blade chord (front-to-back width) at its widest, as a fraction of diameter, quoted for a
## 3-blade prop. A 5" tri-blade is about 13 mm at its widest on a 127 mm diameter.
const CHORD_TO_DIAMETER_AT_3_BLADE := 0.105
## Fewer blades, wider each. A bi-blade has to recover the blade area a tri-blade gets from
## the third blade, so it is broader — which is exactly how the two look side by side in the
## real world, and a big part of what makes a 2-blade recognisable as one at a glance. The
## exponent keeps total blade area roughly constant rather than exactly so; blade area is not
## a spec parts.md carries, so this is a documented rule of thumb like PropellerModel's own
## blade-count exponent, not a fitted law.
const CHORD_BLADE_COUNT_EXPONENT := 0.45

## Where along the blade the chord peaks, and how full the profile is. Expressed as a slice of
## a sine arch: the root starts part-way up the arch (so it is narrow but not zero) and the tip
## stops just short of the far end (so it tapers to a narrow tip rather than a point).
const CHORD_ROOT_FRACTION := 0.18
const CHORD_TIP_FRACTION := 0.98
const CHORD_FULLNESS := 0.7

## Blade thickness as a fraction of the local chord, so the blade thins toward the tip on its
## own. Real props run 8-12% thickness-to-chord.
const THICKNESS_TO_CHORD_RATIO := 0.10

## The centre boss, as a fraction of the prop's radius. A real 5" hub is around 9 mm deep on a
## 63 mm radius, which is chunkier than it looks in a photograph and is the number this ratio
## carries — it was 0.055 in the previous slice, which drew a disc rather than a boss.
##
## The depth is load-bearing rather than cosmetic. A blade ROOT is steeply feathered (beta is
## nearly 70 degrees where the blade leaves the hub) so its section stands several millimetres
## proud of the plane of rotation, above AND below. On a real propeller that section is buried in
## the hub. If the hub is shallower than the root it carries, the blade emerges below the hub's
## own underside and the lowest part of the propeller is a blade tucked under the motor — which
## is what put blade roots inside the bell. So the hub is at least as deep as its root section:
## see stack_height_m, which is measured from the generated blade rather than assumed.
const HUB_RADIUS_TO_RADIUS := 0.10
const HUB_HEIGHT_TO_RADIUS := 0.14

## Half the prop's published diameter — what the sweep actually occupies, and therefore the
## number that decides whether it clears the arms. AirframeModel reads it.
var radius_m := 0.0
var blade_count := 0
## The propeller's full vertical extent: hub depth, deep enough to contain its own blade roots.
## This is what a motor has to leave room for between its adapter and its nut, and what
## AirframeModel hands to MotorMesh.rebuild().
var stack_height_m := 0.0
## How far the geometry reaches below and above this node's origin. Symmetric, because a blade
## section is symmetric about the plane of rotation, but named separately because the two are
## asked different questions: `underside_m` is what rests on the adapter, `topside_m` is what the
## nut has to clear.
var underside_m := 0.0
var topside_m := 0.0


## Clears any previously generated blades and rebuilds from `prop`. The 4-blade-to-2-blade
## direction is the one that matters: leftover blades on a larger prop just look like a larger
## prop, so a missed clear-out here is invisible rather than obviously broken.
func rebuild(prop: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var specs: Dictionary = prop.get("specs", {})
	var diameter_m: float = float(specs.get("diameter_inches", 5.0)) * INCH_M
	var pitch_m: float = float(specs.get("pitch_inches", 4.0)) * INCH_M
	blade_count = maxi(int(specs.get("blades", 2)), 1)
	radius_m = diameter_m * 0.5

	var hub_radius := radius_m * HUB_RADIUS_TO_RADIUS
	var material := _material_for(prop)

	# Blades first, because the hub has to be deep enough to contain their roots and the only
	# honest source for how deep that is is the geometry itself.
	var blade_mesh := _build_blade_mesh(hub_radius, pitch_m)
	var blade_aabb := blade_mesh.get_aabb()
	var blade_reach: float = maxf(absf(blade_aabb.position.y), blade_aabb.end.y)

	stack_height_m = maxf(radius_m * HUB_HEIGHT_TO_RADIUS, blade_reach * 2.0)
	underside_m = stack_height_m * 0.5
	topside_m = stack_height_m * 0.5

	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = hub_radius
	hub_mesh.bottom_radius = hub_radius
	hub_mesh.height = stack_height_m
	hub_mesh.radial_segments = 16
	hub_mesh.rings = 1
	hub.mesh = hub_mesh
	hub.material_override = material
	add_child(hub)

	for i in blade_count:
		var blade := MeshInstance3D.new()
		blade.name = "Blade_%d" % i
		blade.mesh = blade_mesh
		blade.material_override = material
		blade.rotation = Vector3(0, TAU * float(i) / float(blade_count), 0)
		add_child(blade)


## One blade, as a twisted tapered prism running out along +X from the hub to the tip.
##
## Each station is a rectangular section: the chord line, rotated about the radial axis by the
## angle the pitch demands at that radius, given thickness either side. Consecutive sections
## are stitched into four faces, and the two ends are capped, so the blade is a closed solid
## that catches light differently on its upper and lower surfaces — which is what makes the
## twist legible on screen at all. A single-sided ribbon reads as paper.
func _build_blade_mesh(hub_radius: float, pitch_m: float) -> ArrayMesh:
	var chord_max: float = radius_m * 2.0 * CHORD_TO_DIAMETER_AT_3_BLADE \
		* pow(3.0 / float(blade_count), CHORD_BLADE_COUNT_EXPONENT)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in STATIONS:
		var span := float(i) / float(STATIONS - 1)
		# The blade starts at the hub's edge and ends exactly on the published radius, so the
		# sweep the geometry occupies is the diameter the catalog quotes — no more, no less.
		var radius: float = hub_radius + (radius_m - hub_radius) * span
		var chord := _chord_at(span, chord_max)
		var thickness := chord * THICKNESS_TO_CHORD_RATIO
		var twist := twist_angle_rad(pitch_m, radius)

		# Chord direction, rotated about the radial (+X) axis by the twist. At zero twist it
		# lies tangentially (+Z) and the blade is flat; at 90 degrees it stands on edge.
		var chordwise := Vector3(0.0, sin(twist), cos(twist))
		var face := Vector3(0.0, -cos(twist), sin(twist))

		var centre := Vector3(radius, 0.0, 0.0)
		for corner in [Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]:
			tool.add_vertex(centre + chordwise * (chord * corner.x) + face * (thickness * corner.y))

	for i in STATIONS - 1:
		var base := i * 4
		for f in 4:
			var a := base + f
			var b := base + (f + 1) % 4
			tool.add_index(a)
			tool.add_index(b)
			tool.add_index(a + 4)
			tool.add_index(b)
			tool.add_index(b + 4)
			tool.add_index(a + 4)

	# Root and tip caps, wound opposite ways so both face outward.
	var tip := (STATIONS - 1) * 4
	for triangle in [[0, 2, 1], [0, 3, 2]]:
		for index in triangle:
			tool.add_index(index)
	for triangle in [[tip, tip + 1, tip + 2], [tip, tip + 2, tip + 3]]:
		for index in triangle:
			tool.add_index(index)

	tool.generate_normals()
	return tool.commit()


## The blade angle at radius r for a given pitch — the whole propeller model in one line, and
## the reason this class exists rather than a scaled stand-in. Static so the relationship is
## quotable on its own.
static func twist_angle_rad(pitch_m: float, radius_m: float) -> float:
	if radius_m <= 0.0:
		return 0.0
	return atan(pitch_m / (TAU * radius_m))


## Chord at a fractional position along the blade, as a slice of a sine arch: narrow at the
## root, widest around two-thirds out, tapering to a narrow tip.
func _chord_at(span: float, chord_max: float) -> float:
	var arch: float = CHORD_ROOT_FRACTION + (CHORD_TIP_FRACTION - CHORD_ROOT_FRACTION) * span
	return chord_max * pow(sin(PI * arch), CHORD_FULLNESS)


## Appearance from catalog.material, by substring, with a neutral default for a prop whose
## contributor has not filled the field in — same shape and same reasoning as
## FrameModel._material_for, including its perceptual-transform argument: these are read
## against a dark viewport and a near-black airframe, so nothing here is at its true
## reflectance.
func _material_for(prop: Dictionary) -> StandardMaterial3D:
	var material_name := String(prop.get("catalog", {}).get("material", "")).to_lower()

	var mat := StandardMaterial3D.new()
	if material_name.contains("carbon"):
		mat.albedo_color = Color(0.22, 0.23, 0.26)
		mat.roughness = 0.4
		mat.metallic = 0.1
	elif material_name.contains("glass"):
		mat.albedo_color = Color(0.74, 0.75, 0.72)
		mat.roughness = 0.7
		mat.metallic = 0.0
	elif material_name.contains("polycarbonate"):
		mat.albedo_color = Color(0.82, 0.84, 0.88)
		mat.roughness = 0.25
		mat.metallic = 0.05
	else:
		mat.albedo_color = Color(0.55, 0.56, 0.58)
		mat.roughness = 0.5
		mat.metallic = 0.05
	return mat
