class_name TestAirframeDocument
extends RefCounted
## AirframeDocument is the §2 data model and the migration of the catalog frames onto it. These
## tests are about the DOCUMENT — what it holds, what survives a save, and whether a preset lands
## its motors where the physics already thinks they are. What the geometry WEIGHS is
## test_airframe_properties.gd's subject, deliberately: mass is a claim about ρ·t·A, and a mass
## check living here would make a persistence failure look like a physics failure.
##
## The generator is checked against MotorLayout rather than against its own constants, in the
## manner test_frame_model.gd established: reading `arm_mm` back out of the JSON that produced the
## document proves only that a number was copied.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_every_catalog_frame_becomes_a_document(catalog))
	results.append(_test_preset_motors_land_at_motor_layout_positions(catalog))
	results.append(_test_preset_holes_are_wound_as_holes(catalog))
	results.append(_test_round_trip_is_unchanged(catalog))
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_thickness_snaps_to_real_stock())
	results.append(_test_material_mapping_follows_the_catalog_string())
	results.append(_test_a_bad_file_loads_as_an_empty_airframe())
	results.append(_test_sourced_geometry_is_used_and_arms_are_not_plates(catalog))
	results.append(_test_a_frame_without_sourced_geometry_still_loads())
	return results


static func _test_every_catalog_frame_becomes_a_document(catalog: PartsCatalog) -> TestResult:
	var presets := AirframeDocument.presets_from_catalog(catalog)
	var frames := catalog.list_category("frame")
	var problems: Array = []

	for frame in frames:
		var id := str(frame["part_id"])
		if not presets.has(id):
			problems.append("%s: no preset" % id)
			continue
		var doc: AirframeDocument = presets[id]
		var moulded := str(frame.get("specs", {}).get("construction",
			AirframeDocument.CONSTRUCTION_PLATE)) == AirframeDocument.CONSTRUCTION_MOULDED
		if moulded:
			# A ONE-PIECE MOULDED FRAME GETS NO PLATES AND NO HARDWARE, and that is the assertion
			# rather than an exemption from one. §0 says the plate model owes it nothing, so a
			# preset that grew plates for it would be quoting a carbon arm's mass and resonance for
			# a part that has neither — which is exactly what this generator used to do. The motors
			# still have to be there: `arm_mm` is published, and where thrust is applied is a fact
			# about the product whatever holds it there.
			if not doc.plates.is_empty():
				problems.append("%s: moulded, but got %d plates" % [id, doc.plates.size()])
			if not doc.hardware.is_empty():
				problems.append("%s: moulded, but got hardware" % id)
		else:
			# Four arms plus a bottom and a top plate is the shape the generator promises; anything
			# less means a plate was dropped and its mass with it.
			if doc.plates.size() != 6:
				problems.append("%s: %d plates" % [id, doc.plates.size()])
			if doc.hardware.is_empty():
				problems.append("%s: no hardware" % id)
		if doc.motors.size() != 4:
			problems.append("%s: %d motors" % [id, doc.motors.size()])
		# No mass field, ever (§2). Asserted rather than assumed, because the field that would
		# appear here is the one that makes every downstream number a lie.
		if doc.to_dictionary().has("mass_g") or doc.to_dictionary().has("mass_kg"):
			problems.append("%s: carries an authored mass" % id)
		for plate in doc.plates:
			if AirframeDocument.plate_thickness_mm(plate) <= 0.0:
				problems.append("%s: a plate has no thickness" % id)
			if AirframeDocument.plate_outline(plate).size() < 3:
				problems.append("%s: a plate outline is degenerate" % id)

	return TestResult.new(
		"every catalog frame migrates to an AirframeDocument with no authored mass, and only a plate frame gets plates",
		problems.is_empty(),
		"%d frames migrated" % frames.size() if problems.is_empty() else "; ".join(problems))


static func _test_preset_motors_land_at_motor_layout_positions(catalog: PartsCatalog) -> TestResult:
	# The generated document must put its motors where the SIMULATOR already puts them. A preset
	# whose motors sit anywhere else is a frame whose picture and whose thrust torques disagree,
	# and MotorLayout is the authority (motor_layout.gd is the project's only cross product).
	var problems: Array = []
	var frames := catalog.list_category("frame")

	for frame in frames:
		var doc := AirframeDocument.from_catalog_frame(frame)
		var arm_m := float(frame["specs"]["arm_mm"]) / 1000.0
		for motor in doc.motors:
			var expected := MotorLayout.motor_position(str(motor["name"]), arm_m)
			var actual := AirframeDocument.world_m(
				AirframeDocument.point_of(motor["position_mm"]), 0.0)
			var d := Vector2(actual.x - expected.x, actual.z - expected.z).length()
			if d > 1e-5:
				problems.append("%s/%s off by %.6f m" % [frame["part_id"], motor["name"], d])
			if float(motor["spin"]) != MotorLayout.SPIN[str(motor["name"])]:
				problems.append("%s/%s spin disagrees with MotorLayout" % [
					frame["part_id"], motor["name"]])

	return TestResult.new(
		"preset motors land on MotorLayout's positions and spins",
		problems.is_empty(),
		"%d frames x 4 motors within 1e-5 m" % frames.size() if problems.is_empty()
			else "; ".join(problems))


static func _test_preset_holes_are_wound_as_holes(catalog: PartsCatalog) -> TestResult:
	# §3.1's whole hole mechanism is the winding. A bolt hole wound the same way as its outline
	# ADDS area, so a frame with forty holes comes out heavier than the same frame with none —
	# an error in the direction nobody checks, since a heavier frame still looks like a frame.
	var problems: Array = []
	var holes_seen := 0

	for frame in catalog.list_category("frame"):
		var doc := AirframeDocument.from_catalog_frame(frame)
		for plate in doc.plates:
			var outline_area := PolygonProps.area(AirframeDocument.plate_outline(plate))
			for hole in AirframeDocument.plate_holes(plate):
				holes_seen += 1
				var hole_area := PolygonProps.area(hole)
				if signf(hole_area) == signf(outline_area):
					problems.append("%s: hole wound with its outline" % frame["part_id"])
				if absf(hole_area) >= absf(outline_area):
					problems.append("%s: hole is not smaller than its plate" % frame["part_id"])

	return TestResult.new(
		"preset bolt holes are wound opposite their outline",
		problems.is_empty() and holes_seen > 0,
		"%d holes, all negative-area against a positive outline" % holes_seen
			if problems.is_empty() else "; ".join(problems))


static func _test_round_trip_is_unchanged(catalog: PartsCatalog) -> TestResult:
	# Save, load, save. The two serialised forms must be byte-identical — not approximately equal.
	# That is the reason outlines are stored as doubles rather than as PackedVector2Array: a
	# single-precision round trip forces the assertion down to is_equal_approx, at which point the
	# test has stopped being about persistence.
	var problems: Array = []
	var checked := 0

	for frame in catalog.list_category("frame"):
		var doc := AirframeDocument.from_catalog_frame(frame)
		var path := "user://test_airframe_%s.json" % frame["part_id"]
		if not doc.save_to(path):
			problems.append("%s: save failed" % frame["part_id"])
			continue
		var reloaded := AirframeDocument.load_from(path)
		var first := JSON.stringify(doc.to_dictionary(), "  ")
		var second := JSON.stringify(reloaded.to_dictionary(), "  ")
		if first != second:
			problems.append("%s: differs after a round trip (%d vs %d chars)" % [
				frame["part_id"], first.length(), second.length()])
		elif reloaded.plates.size() != doc.plates.size():
			problems.append("%s: lost plates" % frame["part_id"])
		else:
			checked += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	return TestResult.new(
		"a preset round-trips through save/load byte-identically",
		problems.is_empty(),
		"%d documents identical after save/load/save" % checked if problems.is_empty()
			else "; ".join(problems))


static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	# json_store.gd's fourth rule, at three depths: the document, a plate, and a motor. A file
	# written by a later Lothal must come back out of an older one intact — otherwise opening a
	# build to look at it destroys the half of it this version cannot draw.
	var authored := {
		"schema": AirframeDocument.SCHEMA_VERSION,
		"id": "future", "name": "Future frame", "author": "", "revision": "",
		"material_id": "carbon_3k_twill_0_90",
		"ply_schedule": ["0", "45", "90"],          # unknown, top level
		"plates": [{
			"outline": [-10.0, -10.0, 10.0, -10.0, 10.0, 10.0, -10.0, 10.0],
			"holes": [], "thickness_mm": 2.0, "z_mm": 0.0, "role": "bottom",
			"fillet_radius_mm": 3.5,                 # unknown, on a plate
			"nesting": {"rotation_deg": 12.0},       # unknown and nested
		}],
		"motors": [{"position_mm": [50.0, 50.0], "z_mm": 2.0, "spin": 1.0,
			"tilt_deg": 0.0, "esc_channel": 3}],     # unknown, on a motor
		"hardware": [], "straps": [], "pads": [], "payload_mounts": [],
	}

	var path := "user://test_airframe_unknown.json"
	JsonStore.write_document(path, authored)
	var doc := AirframeDocument.load_from(path)
	var out := doc.to_dictionary()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var problems: Array = []
	if not out.has("ply_schedule") or str(out["ply_schedule"]) != str(authored["ply_schedule"]):
		problems.append("top-level ply_schedule lost")
	var plate: Dictionary = out["plates"][0] if out["plates"].size() > 0 else {}
	if float(plate.get("fillet_radius_mm", 0.0)) != 3.5:
		problems.append("plate fillet_radius_mm lost")
	if not (plate.get("nesting", {}) is Dictionary) \
			or float((plate.get("nesting", {}) as Dictionary).get("rotation_deg", 0.0)) != 12.0:
		problems.append("nested plate field lost")
	var motor: Dictionary = out["motors"][0] if out["motors"].size() > 0 else {}
	if int(motor.get("esc_channel", -1)) != 3:
		problems.append("motor esc_channel lost")
	# And the known half must still be right, or "nothing was lost" would be satisfiable by simply
	# echoing the input back.
	if AirframeDocument.plate_outline(doc.plates[0]).size() != 4:
		problems.append("outline was not parsed")

	return TestResult.new(
		"unknown fields survive a load/save at document, plate and motor depth",
		problems.is_empty(),
		"ply_schedule, fillet_radius_mm, nesting.rotation_deg and esc_channel all returned"
			if problems.is_empty() else "; ".join(problems))


static func _test_thickness_snaps_to_real_stock() -> TestResult:
	# You cannot buy 4.95 mm carbon. A generated thickness that is not on the stock list is a mass
	# computed from a plate that does not exist.
	var problems: Array = []
	for value in [0.4, 1.6, 2.3, 2.9, 4.4, 5.6, 12.0]:
		var stock_mm := AirframeDocument.snap_to_stock(value)
		if not AirframeDocument.PLATE_STOCK_MM.has(stock_mm):
			problems.append("%.1f -> %.2f, not stock" % [value, stock_mm])
	# And it must snap to the NEAREST, not merely to something in the list: a rule that always
	# returned 1.5 would pass the check above and make every frame paper-thin.
	if AirframeDocument.snap_to_stock(4.9) != 5.0:
		problems.append("4.9 did not snap to 5.0")
	if AirframeDocument.snap_to_stock(1.6) != 1.5:
		problems.append("1.6 did not snap to 1.5")
	if AirframeDocument.snap_to_stock(99.0) != 6.0:
		problems.append("99.0 did not clamp to the thickest stock")

	return TestResult.new(
		"generated thicknesses snap to the nearest real plate stock",
		problems.is_empty(),
		"7 values snapped into %s" % [AirframeDocument.PLATE_STOCK_MM] if problems.is_empty()
			else "; ".join(problems))


static func _test_material_mapping_follows_the_catalog_string() -> TestResult:
	var cases := {
		"injection-moulded nylon (PA12)": "pa12_sls",
		"carbon fibre 3K": "carbon_3k_twill_0_90",
		"carbon fibre 4K high-modulus": "carbon_quasi_isotropic",
		"CF plates + moulded nylon ducts": "carbon_3k_twill_0_90",
	}
	var materials := FrameMaterials.load_default()
	var problems: Array = []
	for description in cases:
		var got := AirframeDocument.material_id_for_catalog(description)
		if got != cases[description]:
			problems.append("'%s' -> %s, expected %s" % [description, got, cases[description]])
		# And whatever it maps to must be a material the table can actually weigh, or the plate
		# silently drops out of the mass sum.
		if materials.density(got) <= 0.0:
			problems.append("'%s' -> %s which has no density" % [description, got])

	return TestResult.new(
		"catalog material prose maps to a FrameMaterials id that has a density",
		problems.is_empty(),
		"4 descriptions mapped and all have densities" if problems.is_empty()
			else "; ".join(problems))


static func _test_a_bad_file_loads_as_an_empty_airframe() -> TestResult:
	# json_store.gd's first rule. An unopenable frame must not be an unopenable workbench.
	var path := "user://test_airframe_broken.json"
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string("{\"plates\": [ not json at all")
	handle.close()

	var doc := AirframeDocument.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var missing := AirframeDocument.load_from("user://test_airframe_does_not_exist.json")
	var ok := doc.plates.is_empty() and doc.motors.is_empty() \
		and missing.plates.is_empty() and doc.id == ""

	return TestResult.new(
		"a truncated or missing airframe file loads as an empty document, not a crash",
		ok,
		"malformed: %d plates; missing: %d plates" % [doc.plates.size(), missing.plates.size()])


# ---------------------------------------------------------------------------
# A2b — the three sourced geometry fields
# ---------------------------------------------------------------------------

## SOURCED GEOMETRY REACHES THE DOCUMENT, AND ARM THICKNESS IS NOT PLATE THICKNESS.
##
## The 5" freestyle frame is the one entry in frames.json that carries all three A2b fields
## (`plate_thickness_mm` 2.5, `arm_width_mm` 12.0, `arm_thickness_mm` 5.0), sourced from surveyed
## products. Three claims, and each one fails on its own mutation:
##
##   1. The arm plates are cut at the ARM thickness and the centre plates at the PLATE thickness.
##      MUTATION: make from_catalog_frame() read `plate_thickness_mm` for the arms (the "one
##      thickness per airframe" collapse this slice exists to forbid) and the arm check fails at
##      2.5 mm against 5.0 mm.
##   2. Those two numbers are INDEPENDENT — asserted by requiring the document to keep them
##      different, on a frame whose sources publish them as different. This is what makes claim 1
##      un-satisfiable by a generator that happens to snap both to the same stock, and it is why
##      the two are read from the catalog rather than written as literals here: were frames.json
##      ever edited to make an arm as thin as a plate, this fails rather than silently agreeing.
##   3. The arm's ROOT WIDTH is the sourced 12.0 mm, not the derived 0.12*arm_mm (13.2 mm here, so
##      the two are distinguishable). MUTATION: drop the specs.has("arm_width_mm") branch and the
##      width check fails at 13.2 mm.
static func _test_sourced_geometry_is_used_and_arms_are_not_plates(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var specs: Dictionary = frame["specs"]
	var problems: Array = []
	for key in ["plate_thickness_mm", "arm_width_mm", "arm_thickness_mm"]:
		if not specs.has(key):
			problems.append("frames.json no longer carries %s for the 5\" freestyle" % key)
	if not problems.is_empty():
		return TestResult.new(
			"a frame WITH sourced geometry uses it, and its arms stay thicker than its plates",
			false, "; ".join(problems))

	var published_plate := float(specs["plate_thickness_mm"])
	var published_arm := float(specs["arm_thickness_mm"])
	var published_width := float(specs["arm_width_mm"])
	var doc := AirframeDocument.from_catalog_frame(frame)

	var arm_plates := 0
	var centre_plates := 0
	for plate in doc.plates:
		var t := AirframeDocument.plate_thickness_mm(plate)
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			arm_plates += 1
			if not is_equal_approx(t, published_arm):
				problems.append("an arm is %.2f mm, published %.2f" % [t, published_arm])
			# The root is the FIRST and LAST vertex of the trapezoid, straddling the centre: their
			# separation is the authored root width. Measured off the polygon rather than read back
			# off a field, because the polygon is what the mass and the beam maths integrate.
			var outline := AirframeDocument.plate_outline(plate)
			var root_width: float = (outline[0] - outline[outline.size() - 1]).length()
			if absf(root_width - published_width) > 0.01:
				problems.append("arm root is %.2f mm wide, published %.2f" % [root_width, published_width])
		else:
			centre_plates += 1
			if not is_equal_approx(t, published_plate):
				problems.append("a %s plate is %.2f mm, published %.2f" % [
					str(plate.get("role", "?")), t, published_plate])
	if arm_plates != 4 or centre_plates != 2:
		problems.append("%d arm plates and %d centre plates" % [arm_plates, centre_plates])
	# Claim 2. The whole point of the slice: these are two specs, not one.
	if is_equal_approx(published_arm, published_plate):
		problems.append("the catalog now says an arm is as thick as a plate (%.2f mm), which collapses the "
			+ "distinction A2b exists to record" % published_arm)

	return TestResult.new(
		"a frame WITH sourced geometry uses it, and its arms stay thicker than its plates",
		problems.is_empty(),
		"arms %.1f mm x %.1f mm wide, plates %.1f mm, all from frames.json" % [
			published_arm, published_width, published_plate]
			if problems.is_empty() else "; ".join(problems))


## A FRAME WITH NO SOURCED GEOMETRY STILL LOADS. Absence is the expected state for the moulded
## frames (§0) and for arm width everywhere, so the fallback is not an error path — it is the path
## most of the catalog takes, and it must produce a document rather than a zero-thickness ghost.
##
## The fixture is a bare dictionary rather than a catalog entry: a catalog frame could acquire the
## fields later and quietly turn this into a copy of the test above.
##
## MUTATION: make from_catalog_frame() read specs["arm_thickness_mm"] unconditionally and this
## fails — GDScript's Dictionary returns null for a missing key, float(null) is 0.0, and the
## document comes out with zero-thickness arms that weigh nothing.
static func _test_a_frame_without_sourced_geometry_still_loads() -> TestResult:
	var frame := {
		"part_id": "frame_test_unsourced", "name": "Unsourced", "category": "frame",
		"mass_g": 100.0,
		"specs": {"arm_mm": 110.0, "max_prop_inches": 5.0,
			"motor_mount": "16x16", "stack_mount": "30.5x30.5"},
		"catalog": {"material": "carbon fibre 3K"},
	}
	var doc := AirframeDocument.from_catalog_frame(frame)
	var problems: Array = []
	if doc.plates.size() != 6:
		problems.append("%d plates" % doc.plates.size())

	# The documented fallbacks: 4.5% of arm length for an arm, 2% for a plate, both snapped to real
	# stock. Recomputed here from the same constants rather than hard-coded, so this asserts "the
	# fallback ran" and not "the fallback is still 4.5%".
	var expected_arm := AirframeDocument.snap_to_stock(
		110.0 * AirframeDocument.ARM_THICKNESS_PER_ARM_MM)
	var expected_plate := AirframeDocument.snap_to_stock(
		110.0 * AirframeDocument.PLATE_THICKNESS_PER_ARM_MM)
	for plate in doc.plates:
		var t := AirframeDocument.plate_thickness_mm(plate)
		if t <= 0.0:
			problems.append("a plate came out %.2f mm thick" % t)
		var wanted := (expected_arm if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM
			else expected_plate)
		if not is_equal_approx(t, wanted):
			problems.append("%s plate %.2f mm, fallback says %.2f" % [
				str(plate.get("role", "?")), t, wanted])

	return TestResult.new(
		"a frame with NO plate or arm thickness still loads, on the documented fallback",
		problems.is_empty(),
		"fallback gave %.1f mm arms on %.1f mm plates" % [expected_arm, expected_plate]
			if problems.is_empty() else "; ".join(problems))
