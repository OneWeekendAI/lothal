class_name TestFittedFrame
extends RefCounted
## The fitted frame as one object (FittedFrame): the document the Airframe pages draw is the frame
## the physics flies. One test per case.
##
## The pairs that keep these honest: the unedited case must leave the reference build BIT-IDENTICAL
## (so every existing physics oracle is untouched), and each edit case is asserted against numbers
## measured off the edited document — not against `edit_of`'s own output.


static func run() -> Array:
	return [
		_unedited_document_flies_the_catalogue_frame(),
		_unedited_build_is_bit_identical(),
		_thinner_arms_fly_lighter_by_what_they_drew(),
		_longer_arms_fly_longer(),
		_an_edit_reaches_mass_and_inertia(),
		_an_edit_survives_the_field_twin(),
		_an_edit_for_another_frame_is_ignored(),
		_a_hex_is_not_flown_and_says_so(),
		_a_quad_raises_no_unflown_warning(),
		_row_mass_is_weighed_until_edited(),
		_flies_as_explains_the_difference(),
		_the_sim_door_flies_the_edit(),
	]


static func _frame() -> Dictionary:
	return PartsCatalog.load_default().get_part(ReferenceBuild.FRAME_ID)


static func _thin_arms(document: AirframeDocument) -> AirframeDocument:
	var out := AirframeDocument.from_dictionary(document.to_dictionary())
	for i in out.plates.size():
		if str((out.plates[i] as Dictionary).get("role", "")) == AirframeDocument.ROLE_ARM:
			FrameEdits.set_thickness(out, i, 4.0)
	return out


static func _unedited_document_flies_the_catalogue_frame() -> TestResult:
	var frame := _frame()
	var document := AirframeDocument.from_catalog_frame(frame)
	var edit := FittedFrame.edit_of(frame, document, FittedFrame.baseline(frame))
	return TestResult.new("fitted frame: the document as generated changes nothing that flies",
		edit.is_empty(), "edit %s" % edit)


static func _unedited_build_is_bit_identical() -> TestResult:
	var plain := ReferenceBuild.build()
	var with_empty := ReferenceBuild.build()
	with_empty.set_frame_edit({})
	return TestResult.new("fitted frame: an empty edit leaves the reference build's AUW and inertia bit-identical",
		plain.all_up_weight_g() == with_empty.all_up_weight_g()
			and plain.mass_properties.inertia == with_empty.mass_properties.inertia,
		"%f vs %f" % [plain.all_up_weight_g(), with_empty.all_up_weight_g()])


static func _thinner_arms_fly_lighter_by_what_they_drew() -> TestResult:
	var frame := _frame()
	var base := AirframeDocument.from_catalog_frame(frame)
	var thin := _thin_arms(base)
	var drawn_before := AirframeProperties.compute(base, AirframePanel.materials()).total_mass_g()
	var drawn_after := AirframeProperties.compute(thin, AirframePanel.materials()).total_mass_g()
	var edit := FittedFrame.edit_of(frame, thin, FittedFrame.baseline(frame))
	var want := float(frame["mass_g"]) + (drawn_after - drawn_before)
	return TestResult.new("fitted frame: 4 mm arms fly at the weighed mass less the carbon drawn away",
		not edit.is_empty() and drawn_after < drawn_before - 1.0
			and absf(float(edit["mass_g"]) - want) < 1e-6,
		"edit %s, want %.3f" % [edit, want])


static func _longer_arms_fly_longer() -> TestResult:
	var frame := _frame()
	var document := AirframeDocument.from_catalog_frame(frame)
	for motor in document.motors:
		var p := AirframeDocument.point_of((motor as Dictionary)["position_mm"])
		(motor as Dictionary)["position_mm"] = [p.x * 120.0 / 110.0, p.y * 120.0 / 110.0]
	var edit := FittedFrame.edit_of(frame, document, FittedFrame.baseline(frame))
	return TestResult.new("fitted frame: motors moved out to 120 mm fly on a 120 mm arm",
		not edit.is_empty() and absf(float(edit["arm_mm"]) - 120.0) < 0.01, "edit %s" % edit)


static func _an_edit_reaches_mass_and_inertia() -> TestResult:
	# Mass alone first (arm unchanged), so the AUW moves by exactly the frame's -20 g; then the arm
	# alone, which also lengthens the default motor leads — so its AUW is not asserted here.
	var plain := ReferenceBuild.build()
	var lighter := ReferenceBuild.build()
	lighter.set_frame_edit({"part_id": ReferenceBuild.FRAME_ID, "mass_g": 90.0, "arm_mm": 110.0})
	var longer := ReferenceBuild.build()
	longer.set_frame_edit({"part_id": ReferenceBuild.FRAME_ID, "mass_g": 110.0, "arm_mm": 130.0})
	var d_auw := lighter.all_up_weight_g() - plain.all_up_weight_g()
	return TestResult.new("fitted frame: a 90 g edit moves AUW by -20 g; a 130 mm arm flies and raises roll inertia",
		absf(d_auw + 20.0) < 1e-6 and longer.arm_m == 0.13
			and longer.mass_properties.inertia.z.z > plain.mass_properties.inertia.z.z,
		"dAUW %.3f, arm %.3f, Izz %.6f vs %.6f" % [d_auw, longer.arm_m,
			longer.mass_properties.inertia.z.z, plain.mass_properties.inertia.z.z])


static func _an_edit_survives_the_field_twin() -> TestResult:
	var edited := ReferenceBuild.build()
	edited.set_frame_edit({"part_id": ReferenceBuild.FRAME_ID, "mass_g": 90.0, "arm_mm": 110.0})
	var twin := edited.at_air(AirDensity.new(2000.0, 15.0))
	var bare := PropulsionFigures.without_guard(edited)
	return TestResult.new("fitted frame: the field twin and the unguarded twin fly the same edited frame",
		float(twin.frame["mass_g"]) == 90.0 and float(bare.frame["mass_g"]) == 90.0,
		"twin %s, bare %s" % [twin.frame["mass_g"], bare.frame["mass_g"]])


static func _an_edit_for_another_frame_is_ignored() -> TestResult:
	var build := ReferenceBuild.build()
	build.set_frame_edit({"part_id": "frame_some_other", "mass_g": 1.0, "arm_mm": 50.0})
	return TestResult.new("fitted frame: an edit drawn on a different frame does not land on this one",
		float(build.frame["mass_g"]) == 110.0 and not FittedFrame.is_edited(build.frame),
		"mass %s" % build.frame["mass_g"])


static func _a_hex_is_not_flown_and_says_so() -> TestResult:
	var frame := _frame()
	var hex := FrameLayouts.build("hex_plus")
	var edit := FittedFrame.edit_of(frame, hex, FittedFrame.baseline(frame))
	var warning := FittedFrame.unflown_warning(hex)
	return TestResult.new("fitted frame: a six-motor drawing is not flown, and the Frame row says so",
		hex.motors.size() == 6 and edit.is_empty() and warning != null
			and warning.item == WarningRows.FRAME and warning.short != "",
		"motors %d, edit %s, warning %s" % [hex.motors.size(), edit,
			warning.short if warning != null else "none"])


static func _a_quad_raises_no_unflown_warning() -> TestResult:
	var document := AirframeDocument.from_catalog_frame(_frame())
	return TestResult.new("fitted frame: the fitted quad raises no not-flown warning",
		document.motors.size() == 4 and FittedFrame.unflown_warning(document) == null, "")


static func _row_mass_is_weighed_until_edited() -> TestResult:
	var plain := ReferenceBuild.build()
	var edited := ReferenceBuild.build()
	edited.set_frame_edit({"part_id": ReferenceBuild.FRAME_ID, "mass_g": 97.6, "arm_mm": 110.0})
	var a := SectionRows.number_of(&"frame", plain)
	var b := SectionRows.number_of(&"frame", edited)
	return TestResult.new("fitted frame: the Frame row says 110 g as weighed, ~98 g once edited",
		a == "110 g" and b == "~98 g", "'%s' / '%s'" % [a, b])


static func _flies_as_explains_the_difference() -> TestResult:
	var frame := _frame()
	var thin := _thin_arms(AirframeDocument.from_catalog_frame(frame))
	var flown := FittedFrame.apply(frame, FittedFrame.edit_of(frame, thin, FittedFrame.baseline(frame)))
	var plain := FittedFrame.flown_text(frame)
	var edited := FittedFrame.flown_text(flown)
	return TestResult.new("fitted frame: Flies as reads '110 g, as weighed', then the weighed-minus-drawn sum",
		plain == "110 g, as weighed" and edited.begins_with("~") and edited.contains("110 weighed − "),
		"'%s' / '%s'" % [plain, edited])


static func _the_sim_door_flies_the_edit() -> TestResult:
	var panel := BuildPanel.new(PartsCatalog.load_default(), {})
	panel.frame_edit = {"part_id": ReferenceBuild.FRAME_ID, "mass_g": 90.0, "arm_mm": 110.0}
	panel._rebuild()
	var mass := float(panel.build.frame["mass_g"])
	panel.free()
	return TestResult.new("fitted frame: Sim's build panel flies the edit handed across the door",
		mass == 90.0, "mass %s" % mass)
