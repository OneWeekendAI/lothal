class_name TestAirframePage
extends RefCounted
## The Airframe item pages' two new pieces, headless: `FramePlanDiagram` (the drawing beside the
## sheet) and `ItemPageView` (two numbers, then the row's own warnings as short + "Why?").
##
## The rule this suite guards is labs-and-sim.md §2.2's: the fit check and the picture are the same
## geometry. The Layout & fit page draws the pack, the parts and the prop discs, and marks the
## closest gap; that gap must be the row's number, measured by the same function, or the picture
## and the list disagree about the one thing the page exists to show.
##
## One test per case.


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	out.append(_four_discs_at_the_prop_radius(build, airframe))
	out.append(_the_pack_is_drawn_where_it_is_measured(airframe))
	out.append(_the_drawn_gap_is_the_rows_number(airframe))
	out.append(_the_diagram_knows_its_mode())
	out.append(_hardware_mode_marks_a_flagged_hole())
	out.append(_hardware_mode_marks_nothing_on_a_clean_joint(build))
	out.append_array(_the_item_view(build))
	out.append_array(_a_hidden_fit_block_stays_hidden_through_a_render())

	airframe.free()
	return out


static func _four_discs_at_the_prop_radius(_build: Build, airframe: AirframeModel) -> TestResult:
	var discs := airframe.prop_discs_mm()
	var radius := float((airframe.propeller_meshes["M1"] as PropellerMesh).radius_m) * 1000.0
	var ok := discs.size() == 4
	for disc in discs:
		ok = ok and is_equal_approx(float(disc["radius"]), radius)
	return TestResult.new("airframe page: four prop discs, each at the radius the prop drew",
		ok and radius > 50.0, "%d discs, radius %.1f mm" % [discs.size(), radius])


static func _the_pack_is_drawn_where_it_is_measured(airframe: AirframeModel) -> TestResult:
	var pack := {}
	for part in airframe.plan_parts_mm():
		if part["label"] == "pack":
			pack = part
	var size := airframe.battery_mesh.size_m * 1000.0
	var rect: Rect2 = pack.get("rect", Rect2())
	return TestResult.new("airframe page: the pack's footprint is the battery mesh's, in mm",
		not pack.is_empty() and is_equal_approx(rect.size.x, size.x)
			and is_equal_approx(rect.size.y, size.z), "pack %s, mesh %s" % [rect, size])


static func _the_drawn_gap_is_the_rows_number(airframe: AirframeModel) -> TestResult:
	var closest := airframe.closest_to_prop()
	var gap := FramePlanDiagram.closest_gap(airframe.plan_parts_mm(), airframe.prop_discs_mm())
	return TestResult.new("airframe page: the gap the drawing marks is the row's clearance, same part",
		gap.get("label") == closest.get("part")
			and absf(float(gap.get("mm", INF)) - float(closest.get("mm", 0.0))) < 0.05,
		"drawn %s, row %s" % [gap, closest])


static func _the_diagram_knows_its_mode() -> TestResult:
	var diagram := FramePlanDiagram.new()
	diagram.show_plan(FrameLayouts.build("quad_x"), FramePlanDiagram.MODE_ARMS)
	var ok := diagram.mode == "arms" and diagram.document != null
	diagram.free()
	return TestResult.new("airframe page: the diagram holds its document and mode", ok, "")


## The Quad X preset's motor-pad hole sits 1.9 mm from its edge (the Fasteners page flags it); the
## Screws & standoffs drawing rings exactly that hole.
static func _hardware_mode_marks_a_flagged_hole() -> TestResult:
	var document := FrameLayouts.build("quad_x")
	var diagram := FramePlanDiagram.new()
	diagram.show_plan(document, FramePlanDiagram.MODE_HARDWARE)
	var marked := diagram.flagged_hole
	var worst := FrameHardware.worst_edge_hole(document)
	diagram.free()
	return TestResult.new("airframe page: the hardware drawing rings the hole the joint check flags",
		not marked.is_empty() and marked["centre_mm"] == worst["centre_mm"]
			and is_equal_approx(float(marked["distance_mm"]), float(worst["distance_mm"]))
			and float(marked["distance_mm"]) < HardwareMass.EDGE_DISTANCE_RATIO * 3.0,
		"marked %s" % marked)


static func _hardware_mode_marks_nothing_on_a_clean_joint(build: Build) -> TestResult:
	var document := AirframeDocument.from_catalog_frame(build.frame)
	var diagram := FramePlanDiagram.new()
	diagram.show_plan(document, FramePlanDiagram.MODE_HARDWARE)
	var marked := diagram.flagged_hole
	diagram.free()
	return TestResult.new("airframe page: a joint that passes has no ringed hole",
		FrameHardware.joint_warnings(document).is_empty() and marked.is_empty(), str(marked))


static func _the_item_view(build: Build) -> Array:
	var out: Array = []
	var edge := HardwareMass.hole_to_edge_warning(1.9, 3.0)
	var row: Dictionary = SectionRows.rows("Airframe", build, [edge])[2]
	var view := ItemPageView.new()
	view.show_item(row, [["Hardware", "~21 g"], ["Screws", "24 × M3"]])
	out.append(TestResult.new("item view: the two page numbers, label and value",
		view.number_text(0) == "Hardware ~21 g" and view.number_text(1) == "Screws 24 × M3",
		"'%s' / '%s'" % [view.number_text(0), view.number_text(1)]))
	out.append(TestResult.new("item view: a warning shows its short line, not its sentence",
		view.warning_count() == 1 and view.short_text(0) == "⚠ hole too close to the edge"
			and not view.why_visible(0), "%d, '%s'" % [view.warning_count(), view.short_text(0)]))
	view.toggle_why(0)
	out.append(TestResult.new("item view: Why? reveals the long text, word for word",
		view.why_visible(0) and view.why_text(0) == edge.long(), view.why_text(0).left(50)))
	var clean: Dictionary = SectionRows.rows("Airframe", build, [])[2]
	view.show_item(clean, [])
	out.append(TestResult.new("item view: a row with no warnings says nothing is wrong, in one line",
		view.warning_count() == 0 and view.clear_text() == "Nothing to fix", view.clear_text()))
	view.free()
	return out


## The dock's Layout & fit page hides the Fit sheet's own warning block (it mixes in the camera's and
## the mounts' warnings — other rows'). A render must not bring it back.
static func _a_hidden_fit_block_stays_hidden_through_a_render() -> Array:
	var catalog := PartsCatalog.load_default()
	var absurd := Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion")
	var airframe := AirframeModel.new()
	airframe.rebuild(absurd)
	var panel := AssemblyPanel.new(AssemblyTweaks.new())
	panel.render(absurd, airframe)
	var shown := panel.fit_warning_text()
	panel.set_warnings_visible(false)
	panel.render(absurd, airframe)
	var hidden := panel.fit_warning_text()
	panel.free()
	airframe.free()
	return [TestResult.new("fit sheet: the fixture does have a fit warning to hide", shown != "",
			shown.left(60)),
		TestResult.new("fit sheet: hidden, its warning block stays hidden after a render", hidden == "",
			hidden.left(60))]
