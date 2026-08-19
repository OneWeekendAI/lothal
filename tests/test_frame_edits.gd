class_name TestFrameEdits
extends RefCounted
## Every edit the plan editor can make to a frame — airframe.md §7.1, slice A7.
##
## ## Why the edits are tested without any editor
##
## `FrameEdits` is pure: document in, document changed, no Control, no input, no drawing. That is
## deliberate and it is what makes this suite possible at all. The alternative — putting the
## mutations inside the canvas that draws them — would mean the only way to check that dragging a
## vertex produces the right polygon is to synthesise a mouse event and read pixels back, which is
## slow, flaky, and tests the wrong thing.
##
## So the canvas owns *where the mouse is* and nothing else. Everything below is arithmetic on
## polygons, and every assertion is a number somebody can check by hand.
##
## ## What these tests are really guarding
##
## §0's rule: the picture and the physics are the same polygon. Every edit here changes geometry
## that `AirframeProperties` integrates and `ArmProfile` measures, so an edit that produced a
## plausible-looking but degenerate outline would show a perfectly normal frame with a wrong mass.
## Several tests below therefore assert the CONSEQUENCE — mass moved, the arm got stiffer — rather
## than only the vertex coordinates, because the coordinates alone cannot tell you the two halves
## stayed connected.
##
## ## MUTATION NOTES
##
##   - `_test_a_polygon_cannot_be_cut_below_three_points` fails if the vertex-delete guard goes.
##     A two-point "polygon" has zero area, so the frame silently loses that plate's entire mass
##     while still drawing a line on screen.
##   - `_test_radial_symmetry_puts_arms_where_the_motors_are` fails if the replication rotates the
##     outline but not the centreline (or the reverse). Both are stored per arm, and an arm whose
##     centreline no longer lies inside its own outline is refused by `ArmProfile` — so this failure
##     mode turns "add four arms" into "add three unanalysable arms and one good one".
##   - `_test_an_edit_is_undoable_exactly_once` fails if history stores the LIVE document rather
##     than a snapshot of it, which is the classic version of this bug: undo appears to work until
##     you edit twice, because both history entries are the same object.

const EPS := 1.0e-6


static func run() -> Array:
	var results: Array = []
	results.append(_test_a_new_frame_starts_empty_and_valid())
	results.append(_test_adding_a_plate_adds_its_mass())
	results.append(_test_moving_a_vertex_moves_the_mass())
	results.append(_test_inserting_a_vertex_keeps_the_area())
	results.append(_test_a_polygon_cannot_be_cut_below_three_points())
	results.append(_test_snapping_lands_on_the_grid())
	results.append(_test_a_drawn_arm_is_measurable_and_widening_it_stiffens_it())
	results.append(_test_radial_symmetry_puts_arms_where_the_motors_are())
	results.append(_test_a_hole_removes_mass())
	results.append(_test_adding_hardware_makes_a_whole_joint())
	results.append(_test_a_motor_mount_cuts_holes_and_keeps_the_spins_balanced())
	results.append(_test_a_motor_mount_that_will_not_fit_is_refused_whole())
	results.append(_test_an_edit_is_undoable_exactly_once())
	results.append(_test_undo_survives_a_round_trip_through_json())
	return results


# ---------------------------------------------------------------------------
# Hardware and mounts
# ---------------------------------------------------------------------------

## A standoff arrives WITH its screws, and the set has a real mass and a real check.
##
## The count is asserted because the failure it guards is silent: a lone standoff weighs something
## and draws nothing, so a frame with eight of them and no screws shows a plausible mass and not one
## of §5's three warnings — the builder is told nothing precisely where the joint is unchecked. The
## masses are then taken from `HardwareMass` rather than typed, so this test stays true if the
## standoff's dimensions are ever revised.
static func _test_adding_hardware_makes_a_whole_joint() -> TestResult:
	var document := _document_with_plate()
	var index := FrameEdits.add_hardware(document, Vector2(12.0, 0.0), 25.0, 0.0, 2.0)
	var kinds: Array = []
	for entry in document.hardware:
		kinds.append(str(entry.get("kind", "?")))
	var materials := FrameMaterials.load_default()
	var standoff_g := HardwareMass.standoff_round_mass_g(
		FrameEdits.DEFAULT_STANDOFF_OUTER_D_MM, FrameEdits.DEFAULT_STANDOFF_BORE_D_MM, 25.0,
		materials.density(FrameEdits.DEFAULT_STANDOFF_MATERIAL))
	var screws := kinds.count("screw")
	return TestResult.new("added hardware is a whole joint, not a lone standoff",
		index == 0 and kinds.count("standoff_round") == 1 and screws == 2 and standoff_g > 0.0,
		"%d standoff, %d screws, standoff %.2f g" % [
			kinds.count("standoff_round"), screws, standoff_g])


## A mount is holes AND a motor, and the ring still balances afterwards.
##
## Balance is checked on a frame that had three motors: adding the fourth must leave the sum of the
## spins at zero, which it does only because `add_motor_mount` re-alternates rather than appending
## whatever spin it felt like. A mount that appended a fixed +1 would give three up and one down —
## a quad that cannot hold heading, and nothing on screen to say so.
static func _test_a_motor_mount_cuts_holes_and_keeps_the_spins_balanced() -> TestResult:
	var document := FrameEdits.new_frame("mount")
	for angle in [45.0, 135.0, 225.0]:
		FrameEdits.add_arm(document, angle, 100.0, 20.0, 20.0, 5.0)
	FrameEdits.alternate_spins(document)
	var plate := FrameEdits.add_rectangle(document, Vector2(70.0, -70.0), 30.0, 30.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var area_before := absf(PolygonProps.area(
		AirframeDocument.plate_outline(document.plates[plate])))
	var region_before: float = PolygonProps.region_properties(
		AirframeDocument.plate_outline(document.plates[plate]),
		AirframeDocument.plate_holes(document.plates[plate]))["area"]

	var motor := FrameEdits.add_motor_mount(document, plate, Vector2(70.0, -70.0), 16.0, 0.0)
	var holes := AirframeDocument.plate_holes(document.plates[plate])
	var region_after: float = PolygonProps.region_properties(
		AirframeDocument.plate_outline(document.plates[plate]), holes)["area"]

	return TestResult.new("a motor mount cuts four holes, adds a motor, and stays balanced",
		motor == 3 and holes.size() == 4 and document.motors.size() == 4
			and region_after < region_before
			and is_zero_approx(FrameEdits.spin_balance(document))
			and is_equal_approx(area_before, absf(PolygonProps.area(
				AirframeDocument.plate_outline(document.plates[plate])))),
		"%d holes, %d motors, %.1f mm² left of %.1f, spin sum %.0f" % [
			holes.size(), document.motors.size(), region_after, region_before,
			FrameEdits.spin_balance(document)])


## A pattern that does not fit inside the plate is refused, and refused BEFORE anything is written.
##
## Holes outside their plate are not a warning — they are nothing at all: they subtract no area,
## they weaken nothing, and the motor they imply is bolted to air. Cutting them anyway would put
## four circles on the cut sheet that the plate does not contain, which a cutter will happily
## reproduce as four marks on the waste.
static func _test_a_motor_mount_that_will_not_fit_is_refused_whole() -> TestResult:
	var document := _document_with_plate()
	var plate: Dictionary = document.plates[0]
	var holes_before := AirframeDocument.plate_holes(plate).size()
	var motors_before := document.motors.size()
	# The plate is 40 mm; a 60 mm pattern puts every corner outside it.
	var refused := FrameEdits.add_motor_mount(document, 0, Vector2.ZERO, 60.0, 0.0)
	return TestResult.new("a motor mount that will not fit is refused whole",
		refused == -1 and AirframeDocument.plate_holes(document.plates[0]).size() == holes_before
			and document.motors.size() == motors_before,
		"returned %d, %d holes, %d motors" % [refused,
			AirframeDocument.plate_holes(document.plates[0]).size(), document.motors.size()])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _materials() -> FrameMaterials:
	return FrameMaterials.load_default()


## One 40 mm centre plate at the origin — the smallest frame a joint or a mount can be added to.
static func _document_with_plate() -> AirframeDocument:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	return document


## The density every expectation below is built from, read from the same table the maths reads.
##
## NOT HARD-CODED. An earlier draft of this suite wrote 1550 kg/m³ into three assertions from
## memory; the table says 1525, and three tests failed for a reason that had nothing to do with the
## code under test. A test that carries its own copy of a physical constant is a test that fails
## when somebody corrects the constant — which is precisely backwards.
static func _carbon_density() -> float:
	return _materials().density("carbon_3k_twill_0_90")


## The mass of a flat plate, from the same rho * t * A the polygon integrals compute.
static func _plate_mass_g(area_mm2: float, thickness_mm: float) -> float:
	return area_mm2 * thickness_mm * 1.0e-9 * _carbon_density() * 1000.0


static func _mass_g(document: AirframeDocument) -> float:
	return AirframeProperties.compute(document, _materials()).total_mass_g()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## The blank canvas §7.1 opens on. It has to be a REAL document — one you can compute over — rather
## than a null that every consumer special-cases.
static func _test_a_new_frame_starts_empty_and_valid() -> TestResult:
	var document := FrameEdits.new_frame("My frame")
	var mass := _mass_g(document)
	var warnings := FrameWarnings.of(document, AirframeProperties.compute(document, _materials()))
	var says_empty := false
	for warning in warnings:
		if warning.id == &"frame_has_no_plates":
			says_empty = true
	return TestResult.new(
		"a new frame is an empty document that weighs nothing and says so",
		document.plates.is_empty() and mass == 0.0 and says_empty
			and document.published_mass_g == 0.0,
		"%d plates, %.1f g, %d warnings" % [document.plates.size(), mass, warnings.size()])


## ρ·t·A, against the same three numbers computed independently of the integral: a 40 × 40 mm plate
## of 2 mm carbon is 3200 mm³ of stock at the table's own density.
##
## MUTATION: build the rectangle with its corners in the wrong winding and the signed area goes
## negative; `PolygonProps` would then report a negative mass, which this catches.
static func _test_adding_a_plate_adds_its_mass() -> TestResult:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var mass := _mass_g(document)
	var expected := _plate_mass_g(40.0 * 40.0, 2.0)
	return TestResult.new(
		"adding a plate adds exactly rho * t * A of mass",
		absf(mass - expected) < 0.01,
		"%.4f g (expected %.4f g)" % [mass, expected])


## THE POINT OF THE WHOLE EDITOR (§0): drag a corner, and the numbers move because they are
## integrals of the polygon you dragged. Doubling one side of a square doubles its mass.
static func _test_moving_a_vertex_moves_the_mass() -> TestResult:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var before := _mass_g(document)
	# The rectangle's corners are (-20,-20), (20,-20), (20,20), (-20,20). Pull both right-hand
	# corners out to x = 60, which makes the plate 80 mm wide: twice the area.
	FrameEdits.move_vertex(document, 0, 1, Vector2(60.0, -20.0))
	FrameEdits.move_vertex(document, 0, 2, Vector2(60.0, 20.0))
	var after := _mass_g(document)
	return TestResult.new(
		"dragging a vertex changes the mass, because mass is an integral of the outline",
		absf(after - before * 2.0) < 0.01,
		"%.3f g -> %.3f g (expected %.3f)" % [before, after, before * 2.0])


## Inserting a point ON an existing edge must not change the shape at all — it adds a handle, not
## material. This is the operation that makes an outline editable beyond four corners.
##
## MUTATION: insert at the wrong index (off by one) and the polygon self-crosses; the signed area
## drops and this fails.
static func _test_inserting_a_vertex_keeps_the_area() -> TestResult:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var before := _mass_g(document)
	# Midpoint of the bottom edge, between vertex 0 (-20,-20) and vertex 1 (20,-20).
	var inserted := FrameEdits.insert_vertex(document, 0, 0, Vector2(0.0, -20.0))
	var after := _mass_g(document)
	var count := AirframeDocument.plate_outline(document.plates[0]).size()
	return TestResult.new(
		"inserting a vertex on an edge adds a handle and no material",
		inserted and count == 5 and absf(after - before) < EPS,
		"%d points, %.4f g -> %.4f g" % [count, before, after])


## A polygon with two points is a line, and a line has no area — so the plate would silently stop
## contributing mass while still being drawn. Refused, and the refusal is the test.
static func _test_a_polygon_cannot_be_cut_below_three_points() -> TestResult:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var first := FrameEdits.delete_vertex(document, 0, 0)     # 4 -> 3, allowed
	var second := FrameEdits.delete_vertex(document, 0, 0)    # 3 -> 2, refused
	var count := AirframeDocument.plate_outline(document.plates[0]).size()
	var mass := _mass_g(document)
	return TestResult.new(
		"a plate cannot be cut below three points, so it can never lose its area",
		first and not second and count == 3 and mass > 0.0,
		"%d points left, %.3f g" % [count, mass])


## Snapping is what makes freehand drawing produce numbers a shop can cut. Asserted on the exact
## boundary cases, because "round to nearest" and "round half up" differ there and a 0.5 mm error
## on a bolt hole is a hole in the wrong place.
static func _test_snapping_lands_on_the_grid() -> TestResult:
	var cases := [
		[Vector2(12.3, -7.8), 1.0, Vector2(12.0, -8.0)],
		[Vector2(12.5, -12.5), 1.0, Vector2(13.0, -13.0)],
		[Vector2(3.2, 3.2), 0.5, Vector2(3.0, 3.0)],
		[Vector2(3.3, 3.3), 0.5, Vector2(3.5, 3.5)],
		# A zero or negative grid means no snapping, not a division by zero.
		[Vector2(1.234, 5.678), 0.0, Vector2(1.234, 5.678)],
	]
	var wrong: Array[String] = []
	for case in cases:
		var got := FrameEdits.snap(case[0], case[1])
		if got.distance_to(case[2]) > EPS:
			wrong.append("%s @ %s -> %s (want %s)" % [case[0], case[1], got, case[2]])
	return TestResult.new(
		"snapping rounds to the nearest grid step, away from zero at the half",
		wrong.is_empty(),
		"none wrong" if wrong.is_empty() else ", ".join(wrong))


## An arm drawn here must be analysable by the same `ArmProfile` a preset goes through, and the
## physics must respond the right way: width is LINEAR in stiffness (§4.2), so a 2x wider arm is
## exactly 2x stiffer. Exactly, because it is the definition rather than an approximation.
static func _test_a_drawn_arm_is_measurable_and_widening_it_stiffens_it() -> TestResult:
	var narrow := FrameEdits.new_frame("narrow")
	FrameEdits.add_arm(narrow, 0.0, 100.0, 10.0, 10.0, 5.0)
	var wide := FrameEdits.new_frame("wide")
	FrameEdits.add_arm(wide, 0.0, 100.0, 20.0, 20.0, 5.0)

	var narrow_beam := _beam_of(narrow)
	var wide_beam := _beam_of(wide)
	if narrow_beam == null or wide_beam == null:
		return TestResult.new(
			"an arm drawn in the editor is measurable, and twice as wide is twice as stiff",
			false, "narrow measurable: %s, wide measurable: %s" % [
				narrow_beam != null, wide_beam != null])
	var ratio := wide_beam.k_tip_n_per_m() / narrow_beam.k_tip_n_per_m()
	return TestResult.new(
		"an arm drawn in the editor is measurable, and twice as wide is twice as stiff",
		absf(ratio - 2.0) < 1.0e-9,
		"%.1f N/m vs %.1f N/m, ratio %.9f" % [
			narrow_beam.k_tip_n_per_m(), wide_beam.k_tip_n_per_m(), ratio])


## §7.1: "edit one arm, get four". The replicas must be complete arms — outline AND centreline AND
## a motor at the tip — or the frame looks symmetric and analyses as though it is not.
static func _test_radial_symmetry_puts_arms_where_the_motors_are() -> TestResult:
	var document := FrameEdits.new_frame("quad")
	FrameEdits.add_arm(document, 45.0, 100.0, 12.0, 12.0, 5.0)
	FrameEdits.replicate_radially(document, 0, 4)

	var arms := 0
	var unmeasurable: Array[String] = []
	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
			continue
		arms += 1
		var root := AirframeDocument.point_of(plate["root_point"])
		var tip := AirframeDocument.point_of(plate["tip_point"])
		var profile := ArmProfile.measure_flat(
			plate.get("outline", PackedFloat64Array()), root.x, root.y, tip.x, tip.y)
		if not profile["errors"].is_empty():
			unmeasurable.append("arm %d: %s" % [index, profile["errors"]])

	# Four motors, one per arm tip, and a symmetric X is controllable — which is the whole reason to
	# replicate rather than draw four arms by hand.
	var props := AirframeProperties.compute(document, _materials())
	var uncontrollable := false
	for warning in FrameWarnings.of(document, props):
		if warning.id == &"layout_not_controllable":
			uncontrollable = true
	# Roll and pitch inertia are equal on a symmetric X, which no amount of correct-looking
	# individual arms guarantees.
	var balanced := absf(props.roll_inertia_kg_m2() - props.pitch_inertia_kg_m2()) \
		< props.roll_inertia_kg_m2() * 1.0e-6
	return TestResult.new(
		"replicating an arm four ways gives four measurable arms, four motors and a balanced frame",
		arms == 4 and unmeasurable.is_empty() and document.motors.size() == 4
			and not uncontrollable and balanced,
		"%d arms, %d motors, roll %.9f vs pitch %.9f; %s" % [
			arms, document.motors.size(), props.roll_inertia_kg_m2(),
			props.pitch_inertia_kg_m2(),
			"all measurable" if unmeasurable.is_empty() else ", ".join(unmeasurable)])


## A lightening hole is a hole: it takes mass OUT. Asserted against the arithmetic, because the
## winding convention that makes a hole subtract is easy to get backwards and a hole that ADDS mass
## looks entirely normal on screen.
static func _test_a_hole_removes_mass() -> TestResult:
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	var solid := _mass_g(document)
	FrameEdits.add_hole(document, 0, Vector2.ZERO, 10.0)
	var drilled := _mass_g(document)
	# A 10 mm hole through 2 mm carbon. The bound is one-sided and deliberately so: the hole is drawn
	# as a TESSELLATED polygon inscribed in the circle, so it removes slightly LESS than πr² — about
	# 3% at the kernel's default chord tolerance on a 5 mm radius. Removing more than the true
	# circle would mean the winding or the radius is wrong, so that side is tight.
	var expected := _plate_mass_g(PI * 25.0, 2.0)
	var removed := solid - drilled
	return TestResult.new(
		"a hole removes its own area of material, not adds it",
		drilled < solid and removed <= expected + 1.0e-6 and removed > expected * 0.95,
		"%.4f g -> %.4f g, removed %.4f g (expected %.4f g)" % [
			solid, drilled, solid - drilled, expected])


## Undo has to restore the geometry as it was, and exactly once — a history that hands back the
## live object appears to work on the first undo and then cannot go further.
static func _test_an_edit_is_undoable_exactly_once() -> TestResult:
	var history := FrameHistory.new()
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_rectangle(document, Vector2.ZERO, 40.0, 40.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)

	history.record(document)
	FrameEdits.move_vertex(document, 0, 1, Vector2(60.0, -20.0))
	FrameEdits.move_vertex(document, 0, 2, Vector2(60.0, 20.0))
	var edited := _mass_g(document)

	history.record(document)
	FrameEdits.add_rectangle(document, Vector2(0.0, 100.0), 20.0, 20.0, 2.0, 0.0,
		AirframeDocument.ROLE_TOP)
	var two_plates := document.plates.size()

	var back_one := history.undo(document)
	var after_one := _mass_g(back_one)
	var plates_after_one := back_one.plates.size()

	var back_two := history.undo(back_one)
	var after_two := _mass_g(back_two)

	var original := _plate_mass_g(40.0 * 40.0, 2.0)
	return TestResult.new(
		"undo steps back one edit at a time, and keeps stepping",
		two_plates == 2 and plates_after_one == 1 and absf(after_one - edited) < 0.01
			and absf(after_two - original) < 0.01 and not history.can_undo(),
		"edited %.3f g, undo1 %.3f g (%d plates), undo2 %.3f g (want %.3f)" % [
			edited, after_one, plates_after_one, after_two, original])


## The snapshot has to survive the same serialisation a save does, or undo restores something that
## could not have been saved — the float64 outlines are the part that would quietly degrade.
static func _test_undo_survives_a_round_trip_through_json() -> TestResult:
	var history := FrameHistory.new()
	var document := FrameEdits.new_frame("test")
	FrameEdits.add_arm(document, 45.0, 100.0, 12.0, 8.0, 5.0)
	var before := _beam_of(document)
	history.record(document)
	FrameEdits.move_vertex(document, 0, 0, Vector2(3.0, 3.0))
	var restored := history.undo(document)
	var after := _beam_of(restored)
	if before == null or after == null:
		return TestResult.new(
			"an undone arm measures exactly what it measured before the edit",
			false, "before %s, after %s" % [before != null, after != null])
	var relative := absf(after.k_tip_n_per_m() - before.k_tip_n_per_m()) / before.k_tip_n_per_m()
	return TestResult.new(
		"an undone arm measures exactly what it measured before the edit",
		relative < 1.0e-12,
		"%.6f N/m vs %.6f N/m, relative %.12f" % [
			before.k_tip_n_per_m(), after.k_tip_n_per_m(), relative])


## The first arm of a document as a beam, through the same path the Arms tab uses.
static func _beam_of(document: AirframeDocument) -> ArmBeam:
	for plate in document.plates:
		if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
			continue
		var root := AirframeDocument.point_of(plate.get("root_point", [0.0, 0.0]))
		var tip := AirframeDocument.point_of(plate.get("tip_point", [0.0, 0.0]))
		return ArmProfile.beam_flat(
			plate.get("outline", PackedFloat64Array()),
			root.x, root.y, tip.x, tip.y,
			AirframeDocument.plate_thickness_mm(plate),
			document.plate_material_id(plate),
			_materials())
	return null
