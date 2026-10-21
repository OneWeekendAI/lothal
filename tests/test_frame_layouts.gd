class_name TestFrameLayouts
extends RefCounted
## The nine layouts a builder can start from, and the parametric generator behind them.
##
## ## What these tests are guarding
##
## A layout is a TOPOLOGY — how many arms, where they point, which way each motor turns — and every
## one of those three is a thing that can be subtly wrong while the frame still looks like a frame.
## An arm at the wrong bearing produces a perfectly plausible drawing of a different aircraft; a
## motor turning the wrong way produces one that cannot hold heading; a coaxial pair generated as
## two arms instead of two motors on one mast produces a hexacopter drawn as a hexacopter and flown
## as something else. None of those crash, and none of them look like faults on screen.
##
## So the assertions below are about CONSEQUENCES rather than about fields: the motors are where
## the template says the arms point, the spins sum to zero, the mass moves when the size does.
##
## ## MUTATION NOTES
##
##   - `_test_the_motors_stand_where_the_template_points` fails if the generator's angle convention
##     drifts from `FrameEdits.add_arm`'s. That is the failure that produces a beautiful drawing of
##     the wrong aircraft, and nothing else in the suite would see it.
##   - `_test_every_even_layout_can_hold_heading` fails if spins stop alternating, including for the
##     coaxial layouts, where the pair — not the ring — is what balances.
##   - `_test_a_coaxial_layout_puts_two_motors_on_one_mast` fails if a Y6 is generated as six arms.
##     Six arms at three bearings would give the same motor count and the same total mass, so only
##     the shared plan position catches it.
##   - `_test_regenerating_replaces_rather_than_accumulates` fails if `apply_layout` appends instead
##     of clearing: dragging the arm-length slider once would then double the frame's mass, and the
##     picture would still look right because the new arms land on top of the old ones.
##   - `_test_every_motor_hole_sits_on_its_arm_with_margin` fails if the arm stops at the motor centre
##     (`add_arm`'s outline, which the generator used as-is): the outer two holes of every motor are
##     then off the plate, and on a 5" default the side two as well.
##   - `_test_a_motor_hole_off_the_plate_warns` and `_test_a_stack_hole_off_the_plate_warns` fail if
##     the edge distance goes back to unsigned: a hole hanging in the air then reads as a hole with
##     material all round it, and the tear-out check passes it.

const EPS := 1.0e-6


## Every motor hole of every template, at a 5" default and a 3" on a 12×12 pattern, has its centre on
## its own arm with 1.5×d of material behind it — the rule the tear-out check applies.
static func _test_every_motor_hole_sits_on_its_arm_with_margin() -> TestResult:
	var bad: Array = []
	var holes_seen := 0
	for overrides in [{}, {"arm_length_mm": 75.0, "arm_tip_width_mm": 12.0, "motor_pitch_mm": 12.0}]:
		for layout_id in FrameLayouts.ids():
			var document := FrameLayouts.build(layout_id, overrides)
			for plate in document.plates:
				if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM:
					continue
				var outline := AirframeDocument.plate_outline(plate)
				for hole in AirframeDocument.plate_holes(plate):
					holes_seen += 1
					var diameter := sqrt(absf(PolygonProps.area(hole)) * 4.0 / PI)
					var margin := FrameHardware.signed_edge_distance_mm(outline,
						PolygonProps.centroid(hole))
					if margin < HardwareMass.EDGE_DISTANCE_RATIO * diameter - 0.05:
						bad.append("%s %.1f mm" % [layout_id, margin])
	return TestResult.new(
		"every generated motor hole is on its arm, 1.5×d from the edge",
		holes_seen > 100 and bad.is_empty(),
		"%d holes, %d short: %s" % [holes_seen, bad.size(), str(bad.slice(0, 4))])


## A motor hole drilled past the end of an arm warns. Built by hand — `add_arm` stops at the motor —
## so the test does not depend on the generator having been fixed.
static func _test_a_motor_hole_off_the_plate_warns() -> TestResult:
	var document := AirframeDocument.new()
	var arm := FrameEdits.add_arm(document, 0.0, 70.0, 20.0, 20.0, 5.0)
	FrameEdits.add_hole(document, arm, Vector2(62.0, 0.0), 2.2)
	FrameEdits.add_hole(document, arm, Vector2(78.0, 0.0), 2.2)
	document.hardware.append({"kind": "screw", "material_id": "steel_fastener", "thread_d_mm": 2.0,
		"shank_len_mm": 8.0, "head_d_mm": 3.8, "head_h_mm": 1.2, "position_mm": [70.0, 0.0],
		"z_mm": 5.0})
	var ids: Array = []
	for warning in FrameHardware.joint_warnings(document):
		ids.append(String(warning.id))
	return TestResult.new(
		"a motor hole whose centre is off the end of the arm is a hole-to-edge warning",
		ids.has("hole_to_edge") and FrameHardware.motor_hole_edge_distance_mm(document) < 0.0,
		"warnings %s, worst distance %.2f mm" % [ids, FrameHardware.motor_hole_edge_distance_mm(document)])


## The same for a stack hole cut outside a centre plate.
static func _test_a_stack_hole_off_the_plate_warns() -> TestResult:
	var document := AirframeDocument.new()
	var plate := FrameEdits.add_rectangle(document, Vector2.ZERO, 30.0, 30.0, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	FrameEdits.add_hole(document, plate, Vector2(10.0, 10.0), 3.2)
	FrameEdits.add_hole(document, plate, Vector2(25.0, 0.0), 3.2)
	var ids: Array = []
	for warning in FrameHardware.mount_hole_warnings(document):
		ids.append(String(warning.id))
	return TestResult.new(
		"a stack hole whose centre is off the plate is a hole-to-edge warning",
		ids.has("hole_to_edge"), "warnings %s" % [ids])


static func run() -> Array:
	var results: Array = []
	results.append(_test_every_template_builds_the_arms_and_motors_it_promises())
	results.append(_test_the_motors_stand_where_the_template_points())
	results.append(_test_every_even_layout_can_hold_heading())
	results.append(_test_a_coaxial_layout_puts_two_motors_on_one_mast())
	results.append(_test_arm_length_moves_the_motors_and_the_mass())
	results.append(_test_regenerating_replaces_rather_than_accumulates())
	results.append(_test_a_generated_frame_knows_its_layout_across_a_save())
	results.append(_test_a_generated_frame_has_no_vendor_mass())
	results.append(_test_every_motor_hole_sits_on_its_arm_with_margin())
	results.append(_test_a_motor_hole_off_the_plate_warns())
	results.append(_test_a_stack_hole_off_the_plate_warns())
	return results


static func _materials() -> FrameMaterials:
	return FrameMaterials.load_default()


static func _mass_g(document: AirframeDocument) -> float:
	return AirframeProperties.compute(document, _materials()).total_mass_g()


## Arms in, arms out. The count is the one thing a builder chose by clicking the chip, so a
## generator that quietly produced four arms for a hexacopter would be wrong about the only thing
## the click said.
static func _test_every_template_builds_the_arms_and_motors_it_promises() -> TestResult:
	var wrong: Array = []
	for entry in FrameLayouts.TEMPLATES:
		var document := FrameLayouts.build(str(entry["id"]))
		var arms := 0
		for plate in document.plates:
			if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
				arms += 1
		var wanted_arms: int = (entry["arms"] as Array).size()
		var wanted_motors: int = wanted_arms * int(entry.get("motors_per_arm", 1))
		if arms != wanted_arms or document.motors.size() != wanted_motors:
			wrong.append("%s: %d arms %d motors (wanted %d/%d)" % [
				entry["id"], arms, document.motors.size(), wanted_arms, wanted_motors])
	return TestResult.new(
		"every layout builds the arms and motors its diagram shows",
		wrong.is_empty(),
		"all %d layouts" % FrameLayouts.TEMPLATES.size() if wrong.is_empty() else ", ".join(wrong))


## The bearings, checked against the table the chip is drawn from.
##
## This is the test that keeps the picture and the geometry the same thing. The shelf draws a line
## at `arms[slot]` degrees and the generator builds an arm from the same number; if the two ever
## interpret it differently — degrees versus radians, +v up versus +v down — the chip shows one
## aircraft and the canvas another, and both look entirely normal.
static func _test_the_motors_stand_where_the_template_points() -> TestResult:
	var entry := FrameLayouts.template("hex_v")
	var document := FrameLayouts.build("hex_v", {"arm_length_mm": 150.0})
	var missing: Array = []
	for angle in entry["arms"]:
		var wanted := Vector2(cos(deg_to_rad(float(angle))), sin(deg_to_rad(float(angle)))) * 150.0
		var found := false
		for motor in document.motors:
			if AirframeDocument.point_of(motor["position_mm"]).distance_to(wanted) < 0.01:
				found = true
		if not found:
			missing.append("%.1f°" % float(angle))
	return TestResult.new(
		"a layout's motors stand at exactly the bearings its diagram draws",
		missing.is_empty(),
		"6 of 6 at 150 mm" if missing.is_empty() else "no motor at %s" % ", ".join(missing))


## Yaw comes from the difference between clockwise and counter-clockwise reaction torque, so the
## spins of a layout that can hold heading must sum to zero. Every layout on the shelf has an even
## number of motors, so every one of them must.
static func _test_every_even_layout_can_hold_heading() -> TestResult:
	var wrong: Array = []
	for entry in FrameLayouts.TEMPLATES:
		var document := FrameLayouts.build(str(entry["id"]))
		if document.motors.size() % 2 != 0:
			continue
		var balance := FrameEdits.spin_balance(document)
		if absf(balance) > EPS:
			wrong.append("%s off by %+.0f" % [entry["id"], balance])
	return TestResult.new(
		"every layout on the shelf comes out able to hold heading",
		wrong.is_empty(),
		"all balanced" if wrong.is_empty() else ", ".join(wrong))


## A Y6 has three arms and six motors, which is a different aircraft from a hexacopter with six
## arms even though the two agree about mass, motor count and thrust. The difference is that a
## coaxial pair shares one plan position and turns opposite ways.
static func _test_a_coaxial_layout_puts_two_motors_on_one_mast() -> TestResult:
	var document := FrameLayouts.build("y6", {"arm_length_mm": 200.0, "coaxial_gap_mm": 90.0})
	var arms := 0
	for plate in document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			arms += 1
	var pairs := 0
	var opposed := 0
	var separated := 0
	for i in document.motors.size():
		for j in range(i + 1, document.motors.size()):
			var a: Dictionary = document.motors[i]
			var b: Dictionary = document.motors[j]
			if AirframeDocument.point_of(a["position_mm"]).distance_to(
					AirframeDocument.point_of(b["position_mm"])) > 0.001:
				continue
			pairs += 1
			if float(a.get("spin", 1.0)) * float(b.get("spin", 1.0)) < 0.0:
				opposed += 1
			if absf(float(a["z_mm"]) - float(b["z_mm"])) > 1.0:
				separated += 1
	return TestResult.new(
		"a Y6 is three arms carrying six motors, paired on each mast and counter-rotating",
		arms == 3 and document.motors.size() == 6 and pairs == 3 and opposed == 3
			and separated == 3,
		"%d arms, %d motors, %d pairs (%d opposed, %d separated in height)" % [
			arms, document.motors.size(), pairs, opposed, separated])


## THE POINT OF THE PARAMETRIC SHELF: the same chip makes a 3" and a 10" aircraft, and the
## difference is one number. A longer arm has to move the motor AND weigh more, because the arm is
## a real plate — a generator that moved the motor without re-cutting the plate would give a frame
## whose thrust is applied 90 mm from where its structure ends.
static func _test_arm_length_moves_the_motors_and_the_mass() -> TestResult:
	var short_frame := FrameLayouts.build("quad_x", {"arm_length_mm": 90.0})
	var long_frame := FrameLayouts.build("quad_x", {"arm_length_mm": 180.0})
	var short_reach := AirframeDocument.point_of(short_frame.motors[0]["position_mm"]).length()
	var long_reach := AirframeDocument.point_of(long_frame.motors[0]["position_mm"]).length()
	var light := _mass_g(short_frame)
	var heavy := _mass_g(long_frame)
	return TestResult.new(
		"arm length moves the motors out and takes the mass with it",
		absf(short_reach - 90.0) < 0.01 and absf(long_reach - 180.0) < 0.01 and heavy > light,
		"%.0f mm / %.1f g  →  %.0f mm / %.1f g" % [short_reach, light, long_reach, heavy])


## Dragging the arm-length slider calls `apply_layout` on the SAME document, over and over. If it
## appended rather than cleared, the second drag would give a frame of double mass with its new
## arms drawn exactly on top of the old ones — invisible on the canvas, and wrong in every number.
static func _test_regenerating_replaces_rather_than_accumulates() -> TestResult:
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 110.0})
	var plates := document.plates.size()
	var motors := document.motors.size()
	var hardware := document.hardware.size()
	for step in 3:
		FrameLayouts.apply_layout(document, FrameLayouts.template("quad_x"),
			FrameLayouts.params({"arm_length_mm": 110.0 + step * 5.0}))
	return TestResult.new(
		"regenerating a layout replaces its parts instead of stacking new ones on top",
		document.plates.size() == plates and document.motors.size() == motors
			and document.hardware.size() == hardware,
		"%d plates, %d motors, %d fasteners (started at %d/%d/%d)" % [
			document.plates.size(), document.motors.size(), document.hardware.size(),
			plates, motors, hardware])


## The controls column shows the layout sliders only for a frame that is still a layout, and it
## works that out by asking the DOCUMENT rather than by remembering. So the tag has to survive the
## document being written to disk and read back, or reopening a saved hexacopter would present it
## as an unstructured drawing.
static func _test_a_generated_frame_knows_its_layout_across_a_save() -> TestResult:
	var document := FrameLayouts.build("oct_v")
	var reloaded := AirframeDocument.from_dictionary(document.to_dictionary())
	var drawn := FrameEdits.new_frame("hand drawn")
	return TestResult.new(
		"a generated frame still knows which layout it is after a round trip, and a drawn one has none",
		FrameLayouts.layout_id_of(document) == "oct_v"
			and FrameLayouts.layout_id_of(reloaded) == "oct_v"
			and FrameLayouts.layout_id_of(drawn) == "",
		"%s / %s / \"%s\"" % [FrameLayouts.layout_id_of(document),
			FrameLayouts.layout_id_of(reloaded), FrameLayouts.layout_id_of(drawn)])


## §2's rule, at the one place it is easiest to breach: a generator that knows how to make a frame
## is one line away from also stating what it weighs. Nothing generated has a vendor, so the
## Structure panel must have nothing to compare against — a published mass of zero would print a
## −100% disagreement against a frame nobody published.
static func _test_a_generated_frame_has_no_vendor_mass() -> TestResult:
	var stated: Array = []
	for entry in FrameLayouts.TEMPLATES:
		var document := FrameLayouts.build(str(entry["id"]))
		if document.published_mass_g != 0.0:
			stated.append(str(entry["id"]))
	return TestResult.new(
		"no generated layout claims a published mass",
		stated.is_empty(),
		"none of %d" % FrameLayouts.TEMPLATES.size() if stated.is_empty() else ", ".join(stated))
