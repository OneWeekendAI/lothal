class_name AirframePageChecks
extends RefCounted
## The Airframe section of the Lab dock on a laid-out shell: its rows read the LIVE geometry — the
## frame document the pages render and the assembled airframe — and each row's page shows its own
## item. Called from `TestShellLayout.run` after `LabDockChecks`, for the reason that file gives:
## these are claims about what ended up on screen, and only that suite processes frames.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	shell.back_to_drone()
	shell.select_system_by_name("Airframe")
	await _settle(tree)
	out.append(_the_frame_is_lit(shell))
	out.append(_the_pack_is_dimmed(shell))
	out.append(_a_propeller_is_dimmed(shell))
	out.append(_hardware_row_reads_the_live_document(shell))
	out.append(_hardware_row_carries_the_joint_verdict(shell))
	out.append(_layout_row_reads_the_assembled_airframe(shell))
	out.append_array(await _an_edit_in_the_designer_reaches_the_row(shell, tree))
	shell.open_row(&"frame")
	await _settle(tree)
	out.append(_the_frame_page_carries_the_fitted_catalogue_sheet(shell))
	shell.back_to_drone()

	# THE THREE DRAWN PAGES — each asserted on its own lines, not in a loop.
	shell.open_row(&"arms")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Arms", "arms"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"arms"))
	out.append(_no_paragraph_under_the_sheet(shell, "Arms", shell.lab.arms_details))
	shell.open_row(&"hardware")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Screws & standoffs", "hardware"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"hardware"))
	out.append(_no_paragraph_under_the_sheet(shell, "Screws & standoffs", shell.lab.fasteners_details))
	shell.open_row(&"layout")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Layout & fit", "layout"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"layout"))
	out.append(_no_paragraph_under_the_sheet(shell, "Layout & fit", shell.lab.layout_details))
	out.append(TestResult.new("airframe dock: the dock's Fit sheet is told to carry no warning block",
		not shell.lab.assembly_panel.warnings_shown(), ""))
	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("airframe dock: Back takes the drawing down with the page",
		not shell.item_page().is_visible_in_tree(), ""))
	shell.back_to_drone()
	shell.select_system_by_name("Propulsion")
	await _settle(tree)
	return out


static func _settle(tree: SceneTree) -> void:
	for i in SETTLE:
		await tree.process_frame


static func _row(shell: GlassShell, id: StringName) -> Dictionary:
	for row in shell.section_list().rows():
		if row["id"] == id:
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "choice='%s' number='%s' line3='%s' status=%s" % [row.get("choice"), row.get("number"),
		row.get("line3"), row.get("status")]


static func _hardware_row_reads_the_live_document(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"hardware")
	var document := shell.lab.frame_document
	var grams := FrameHardware.mass_g(document, AirframePanel.materials())
	return TestResult.new("airframe dock: Screws & standoffs reads the frame document the page shows",
		document != null and row.get("choice") == FrameHardware.choice(document)
			and row.get("number") == "~%d g hardware" % roundi(grams), _show(row))


static func _hardware_row_carries_the_joint_verdict(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"hardware")
	var joint := FrameHardware.joint_warnings(shell.lab.frame_document)
	var want_status := SectionRows.OK if joint.is_empty() else (
		SectionRows.BAD if joint[0].severity == BuildWarning.Severity.IMPOSSIBLE else SectionRows.WARN)
	var want_line3 := str(row.get("number")) if joint.is_empty() else "⚠ " + joint[0].short
	return TestResult.new("airframe dock: Screws & standoffs shows the joint check the page runs",
		row.get("status") == want_status and row.get("line3") == want_line3,
		_show(row) + " joint=%d" % joint.size())


static func _layout_row_reads_the_assembled_airframe(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"layout")
	var closest := shell.lab.airframe.closest_to_prop()
	var want := "%s %d mm from a prop" % [str(closest.get("part", "?")),
		roundi(float(closest.get("mm", 0.0)))]
	return TestResult.new("airframe dock: Layout & fit quotes the assembled airframe's worst clearance",
		not closest.is_empty() and row.get("number") == want, _show(row) + " want '%s'" % want)


## Drawing in the Frame page changes the hardware, so the row under it must follow — on the next
## frame, not on the next section change.
static func _an_edit_in_the_designer_reaches_the_row(shell: GlassShell, tree: SceneTree) -> Array:
	var out: Array = []
	var before := shell.lab.frame_document
	var bare := AirframeDocument.from_dictionary(before.to_dictionary())
	bare.hardware = []
	shell.workbench().document_changed.emit(bare)
	await _settle(tree)
	var row := _row(shell, &"hardware")
	out.append(TestResult.new("airframe dock: removing the hardware in the designer empties the row",
		row.get("choice") == "" and row.get("number") == "", _show(row)))
	shell.workbench().document_changed.emit(before)
	await _settle(tree)
	return out


static func _the_frame_page_carries_the_fitted_catalogue_sheet(shell: GlassShell) -> TestResult:
	var frame: Dictionary = shell.lab.current_build().frame
	var drawer := shell.workbench().numbers
	return TestResult.new("airframe dock: the Frame page's Catalogue tab shows the fitted frame",
		drawer.catalogue_text("mass_g") == FrameDetails.published(frame, "mass_g")
			and drawer.catalogue_text("frame_type") == FrameDetails.published(frame, "frame_type"),
		"tab '%s' / fitted '%s'" % [drawer.catalogue_text("mass_g"),
			FrameDetails.published(frame, "mass_g")])


## The stage is used: the drawing takes the left of it, the sheet stands against the list, and
## between them they span the stage — no narrow panel in an empty field.
static func _the_page_is_a_drawing_beside_its_sheet(shell: GlassShell, name: String,
		mode: String) -> TestResult:
	var view := shell.item_page()
	var drawing := view.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var stage := shell.stage_rect()
	var ok := view.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and shell.item_diagram().mode == mode \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x \
		and drawing.position.x - stage.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and drawing.size.x >= 300.0
	return TestResult.new("airframe dock: the %s page is a %s drawing beside its sheet, across the stage"
		% [name, mode], ok, "drawing %s, sheet %s, list %s, mode %s" % [drawing, sheet, list,
		shell.item_diagram().mode])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("airframe dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


## The sheet's footer (the frame's whole warning list and its prose note) is not on a dock page:
## the page's own "Why?" list above the drawing replaces it.
static func _no_paragraph_under_the_sheet(_shell: GlassShell, name: String,
		panel: AirframePanel) -> TestResult:
	return TestResult.new("airframe dock: the %s sheet shows no warning paragraph or footer note" % name,
		not panel.footer_visible(), "")


## The Airframe section lights the frame and dims what is not the frame (the brief: "still dims
## non-frame parts correctly? verify"). Three separate lines, so a regression names its part.
static func _transparencies(node: Node) -> Array:
	var out: Array = []
	for child in [node] + node.find_children("*", "GeometryInstance3D", true, false):
		if child is GeometryInstance3D:
			out.append((child as GeometryInstance3D).transparency)
	return out


## The frame's OWN meshes — every one with no system-named node (Motor_, Battery, Stack …) on its
## path — are lit; the model's frame node also carries the parts bolted to it, which are not.
static func _the_frame_is_lit(shell: GlassShell) -> TestResult:
	var root: Node = shell.lab.airframe.frame_model
	var dimmed: Array = []
	var count := 0
	for child in root.find_children("*", "GeometryInstance3D", true, false):
		var path := root.get_path_to(child)
		var owned := false
		for i in path.get_name_count():
			owned = owned or GlassShell._system_of_name(path.get_name(i)) != ""
		if owned:
			continue
		count += 1
		if (child as GeometryInstance3D).transparency != 0.0:
			dimmed.append(str(path))
	return TestResult.new("airframe dock: with Airframe chosen, every frame mesh is lit",
		count > 0 and dimmed.is_empty(), "%d frame meshes, dimmed: %s" % [count, dimmed])


static func _the_pack_is_dimmed(shell: GlassShell) -> TestResult:
	var values := _transparencies(shell.lab.airframe.battery_mesh)
	return TestResult.new("airframe dock: with Airframe chosen, the pack is dimmed",
		not values.is_empty() and values.all(func(t): return is_equal_approx(t, GlassShell.DIM_TRANSPARENCY)),
		str(values.slice(0, 6)))


static func _a_propeller_is_dimmed(shell: GlassShell) -> TestResult:
	var values := _transparencies(shell.lab.airframe.propeller_meshes["M1"])
	return TestResult.new("airframe dock: with Airframe chosen, a propeller is dimmed",
		not values.is_empty() and values.all(func(t): return is_equal_approx(t, GlassShell.DIM_TRANSPARENCY)),
		str(values.slice(0, 6)))
