class_name BatteryMesh
extends Node3D
## Procedural pack geometry, generated from the pack's published dimensions. Same rule as
## FrameModel, MotorMesh and PropellerMesh — read FrameModel's header for why nothing here is a
## fixed asset — with one difference that is the reason this class was the last of the four to be
## written, and the reason it does not own a single dimension.
##
## THIS CLASS DOES NOT KNOW HOW BIG A PACK IS. IT ASKS.
##
## The other three generators are the only answer to their part's size: nothing else in the project
## has an opinion about how tall a 2207's bell is. The pack is not like that. Build has estimated a
## box for the pack since day 2, because the inertia tensor needs one, and it did so from MASS —
## which meant the app held a private opinion about the size of its heaviest component and never
## showed it. Generating a visible pack from a second estimate would have reproduced exactly the
## divergence AirframeModel was created to eliminate (its header: main.tscn hardcoded 0.0778 while
## the physics read MotorLayout), except invisible, because an inertia tensor does not appear on
## screen.
##
## So the size comes from Build.battery_size_of() — the same call mass_parts() makes — and the
## catalog dimensions were added to `specs` so that call had something real to return. What is
## drawn here and what is integrated in the field are one set of numbers, and
## tests/test_battery_mesh.gd asserts that for every pack in the catalog rather than for the one
## that happened to be selected.
##
## WHERE IT SITS IS NOT DECIDED HERE EITHER. This node measures from its own centre, and
## AirframeModel puts it on the top centre plate — the MotorMesh pattern, for the MotorMesh reason:
## a part that placed itself would need to know the plate stack's height, which is FrameModel's
## (and the standoff tweak's), and that is a second copy of an arithmetic that already exists.
##
## Node layout after rebuild():
##   Cell_0..N-1  — one per cell: stacked pouches for a LiPo, cylindrical barrels for a Li-ion
##   Groove_0..N-2 — the recessed seam between adjacent pouches (LiPo only)
##   Shrink       — the heat-shrink sleeve the barrels sit in (Li-ion only)
##   Strap_0, Strap_1 — the battery straps around the pack's girth
##   Lead_Positive, Lead_Negative — the discharge leads, out of the rear

## The cell seam, as a fraction of one cell's own height, capped so a 6S pack's six seams do not
## turn the block into a stack of slats. Recessed rather than proud: it is a groove between two
## wrapped pouches, and drawing it proud would also make the pack measure wider than the catalog
## says it is, which is the one thing this class must never do.
const GROOVE_TO_CELL_HEIGHT_RATIO := 0.12
const GROOVE_MAX_M := 0.0015
## How far in from the pack's sides the groove is inset, so it reads as a shadow line rather than
## as a gap the pack could come apart at.
const GROOVE_INSET := 0.94

## The heat-shrink sleeve on a cylindrical-cell pack, as a fraction of the pack's length. Short of
## the full length on purpose: the barrel ends stand proud of the wrap, which is what makes a
## Li-ion pack recognisable as one across a room.
const SHRINK_TO_LENGTH_RATIO := 0.86
## Barrels sit just inside their share of the cross-section, so neighbouring cells touch without
## intersecting.
const CELL_PACKING := 0.98

## The straps, as fractions of the pack. They are drawn slightly proud of the pack's sides — they
## are the one thing here that legitimately sticks out, since a strap goes around the pack AND the
## plate. Excluded from the pack's measured extent for that reason.
const STRAP_OVERSIZE := 1.04
const STRAP_WIDTH_TO_LENGTH_RATIO := 0.09
const STRAP_WIDTH_MAX_M := 0.010
const STRAP_POSITION_TO_LENGTH_RATIO := 0.25

## The discharge leads: a pair of silicone wires out of the back. Nose is -Z, so the back is +Z.
## Connector geometry (XT60/XT30) is deliberately not drawn — it is catalog metadata nothing reads,
## and a connector is a part in its own right the day it becomes one.
const LEAD_RADIUS_TO_CROSS_SECTION_RATIO := 0.045
const LEAD_LENGTH_TO_LENGTH_RATIO := 0.18
const LEAD_SPACING_TO_WIDTH_RATIO := 0.15
const LEAD_HEIGHT_TO_HEIGHT_RATIO := 0.15

## The pack as a box in BODY axes: width across X, height up Y, length along Z. Read by
## AirframeModel to seat it and to measure its overhang, so the number the fit check uses is the
## number that was drawn.
var size_m := Vector3.ZERO
## How many cells are drawn, which is how many the pack has.
var cell_count := 0


## Clears any previously generated pack and rebuilds it from `battery`. Safe to call on every
## selection change; nothing survives a call except this node.
##
## The 6S-to-1S direction is the one that matters: leftover cells inside a smaller pack are hidden
## by the pack itself, so a missed clear-out here would be invisible rather than obviously broken —
## the same trap PropellerMesh's header names for blade counts.
func rebuild(battery: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	# The one place a pack's size enters this file, and it is a question rather than an answer.
	size_m = Build.battery_size_of(battery)

	var specs: Dictionary = battery.get("specs", {})
	cell_count = maxi(int(specs.get("cells", 1)), 1)
	var chemistry := String(specs.get("chemistry", "LiPo")).to_lower()

	# Cylindrical cells are what "Li-ion" means in this catalog — 18650s and 21700s. Matched by
	# substring for the same reason FrameModel matches materials that way: an entry that says
	# "Li-Ion 21700" should not fall through to the pouch branch on a hyphen.
	if chemistry.contains("ion"):
		_build_cylindrical_cells()
	else:
		_build_pouch_cells()

	_build_straps()
	_build_leads()


# ---------------------------------------------------------------------------
# The cells
# ---------------------------------------------------------------------------

## A LiPo: N pouches stacked vertically inside one sleeve, which is how a multi-cell pack is
## actually built and why a 6S pack of a given footprint is taller than a 4S one.
##
## The outermost faces of the first and last cell land exactly on the published height — the
## grooves are taken out of the INSIDE of the stack rather than off its ends, so the block measures
## what the catalog says however many cells it is divided into.
func _build_pouch_cells() -> void:
	var slot := size_m.y / float(cell_count)
	var groove: float = minf(slot * GROOVE_TO_CELL_HEIGHT_RATIO, GROOVE_MAX_M)
	var material := _shrink_material()

	for i in cell_count:
		var bottom := -size_m.y * 0.5 + slot * float(i)
		var top := bottom + slot
		if i > 0:
			bottom += groove * 0.5
		if i < cell_count - 1:
			top -= groove * 0.5

		var cell := MeshInstance3D.new()
		cell.name = "Cell_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(size_m.x, top - bottom, size_m.z)
		cell.mesh = box
		cell.material_override = material
		cell.position = Vector3(0, (top + bottom) * 0.5, 0)
		add_child(cell)

	for i in cell_count - 1:
		var groove_node := MeshInstance3D.new()
		groove_node.name = "Groove_%d" % i
		var box := BoxMesh.new()
		# Narrower than the pack on both horizontal axes, so it sits inside the silhouette and
		# reads as a shadow line rather than as a slice through the pack.
		box.size = Vector3(size_m.x * GROOVE_INSET, groove, size_m.z * GROOVE_INSET)
		groove_node.mesh = box
		groove_node.material_override = _groove_material()
		groove_node.position = Vector3(0, -size_m.y * 0.5 + slot * float(i + 1), 0)
		add_child(groove_node)


## A Li-ion: N cylindrical cells lying along the pack's length inside a heat-shrink sleeve.
##
## The GRID is derived rather than authored, and that is what makes this right for both entries in
## the catalog at once. Cells are laid out in the arrangement that best fills the pack's own
## cross-section — columns chosen so the grid's aspect matches the pack's — which lands on 2x2 for
## the 4S 18650 pack (37 x 37 mm) and 3x2 for the 6S 21700 one (64 x 43 mm), the way both are
## really built. An authored "2 rows" would have been correct for exactly the packs it was written
## against.
func _build_cylindrical_cells() -> void:
	var columns := _cell_columns()
	var rows := int(ceil(float(cell_count) / float(columns)))
	var column_pitch := size_m.x / float(columns)
	var row_pitch := size_m.y / float(rows)
	var radius: float = minf(column_pitch, row_pitch) * 0.5 * CELL_PACKING
	var material := _cell_material()

	for i in cell_count:
		var column := i % columns
		# Integer division on purpose: the row is which full row of `columns` cells this index has
		# got past, so the truncation IS the answer rather than a lost fraction.
		@warning_ignore("integer_division")
		var row := i / columns

		var cell := MeshInstance3D.new()
		cell.name = "Cell_%d" % i
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = size_m.z
		cylinder.radial_segments = 16
		cylinder.rings = 1
		cell.mesh = cylinder
		cell.material_override = material
		# CylinderMesh runs along its own Y; a cell in a pack lies along the aircraft's length.
		cell.rotation = Vector3(PI * 0.5, 0, 0)
		cell.position = Vector3(
			-size_m.x * 0.5 + column_pitch * (float(column) + 0.5),
			-size_m.y * 0.5 + row_pitch * (float(row) + 0.5),
			0)
		add_child(cell)

	var shrink := MeshInstance3D.new()
	shrink.name = "Shrink"
	var box := BoxMesh.new()
	box.size = Vector3(size_m.x, size_m.y, size_m.z * SHRINK_TO_LENGTH_RATIO)
	shrink.mesh = box
	shrink.material_override = _shrink_material()
	add_child(shrink)


## How many cells across, chosen so the grid's proportions follow the pack's own. Clamped to the
## cell count at both ends so a 1S entry cannot ask for a fractional column.
func _cell_columns() -> int:
	if size_m.y <= 0.0:
		return cell_count
	var ideal := sqrt(float(cell_count) * size_m.x / size_m.y)
	return clampi(int(round(ideal)), 1, cell_count)


# ---------------------------------------------------------------------------
# The hardware that holds it on
# ---------------------------------------------------------------------------

## Two straps around the pack's girth. Slightly oversized on both horizontal axes, because a strap
## goes around the pack AND the plate under it — this is the detail that makes the block read as
## fitted rather than as floating, which is the whole difference between a pack that is mounted and
## a pack that is merely present (labs-and-sim.md §2.2).
func _build_straps() -> void:
	var width: float = minf(size_m.z * STRAP_WIDTH_TO_LENGTH_RATIO, STRAP_WIDTH_MAX_M)
	var offset: float = size_m.z * STRAP_POSITION_TO_LENGTH_RATIO
	var material := _strap_material()

	for i in 2:
		var strap := MeshInstance3D.new()
		strap.name = "Strap_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(size_m.x * STRAP_OVERSIZE, size_m.y * STRAP_OVERSIZE, width)
		strap.mesh = box
		strap.material_override = material
		strap.position = Vector3(0, 0, offset if i == 0 else -offset)
		add_child(strap)


## The discharge leads, out of the back. Both entirely aft of the pack, so they never read as wires
## buried in the cells, and both the same size — the pair is what says "this end is the business
## end", which is the cheapest possible cue for which way round the pack is fitted.
func _build_leads() -> void:
	var cross_section: float = minf(size_m.x, size_m.y)
	var radius: float = cross_section * LEAD_RADIUS_TO_CROSS_SECTION_RATIO
	var length: float = size_m.z * LEAD_LENGTH_TO_LENGTH_RATIO
	var spacing: float = size_m.x * LEAD_SPACING_TO_WIDTH_RATIO
	var centre_z: float = size_m.z * 0.5 + length * 0.5
	var height: float = size_m.y * LEAD_HEIGHT_TO_HEIGHT_RATIO

	for lead in [
		{"name": "Lead_Positive", "x": spacing, "material": _positive_lead_material()},
		{"name": "Lead_Negative", "x": -spacing, "material": _negative_lead_material()},
	]:
		var node := MeshInstance3D.new()
		node.name = lead["name"]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = length
		cylinder.radial_segments = 10
		cylinder.rings = 1
		node.mesh = cylinder
		node.material_override = lead["material"]
		node.rotation = Vector3(PI * 0.5, 0, 0)
		node.position = Vector3(lead["x"], height, centre_z)
		add_child(node)


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------

## Heat shrink: a dark, faintly glossy sleeve. Lifted well above the near-black most packs really
## are, for the reason FrameModel's header sets out at length — this viewport is read against a
## dark background and a near-black airframe, and a pack rendered at its true reflectance is a hole
## in the middle of the build. Cooled slightly toward blue so it separates from the carbon it sits
## on rather than reading as another plate.
func _shrink_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.21, 0.28)
	mat.roughness = 0.42
	mat.metallic = 0.05
	return mat


func _groove_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.10, 0.13)
	mat.roughness = 0.8
	mat.metallic = 0.0
	return mat


## A wrapped cylindrical cell: lighter than the sleeve it sits in, and glossier, so the barrels
## are legible against the shrink at the pack's ends.
func _cell_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.42, 0.47)
	mat.roughness = 0.3
	mat.metallic = 0.35
	return mat


## Woven nylon: matte and lighter than everything around it, because the strap's whole job on
## screen is to be seen crossing the pack.
func _strap_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.45, 0.43)
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat


func _positive_lead_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.16, 0.14)
	mat.roughness = 0.6
	mat.metallic = 0.0
	return mat


func _negative_lead_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.10, 0.11)
	mat.roughness = 0.6
	mat.metallic = 0.0
	return mat
