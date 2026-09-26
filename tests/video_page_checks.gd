class_name VideoPageChecks
extends RefCounted
## The Video section of the Lab dock on a laid-out shell: Camera and VTX & antenna each open their
## own side view beside their own sheet, with the Electronics rail (the only place these parts are
## picked) stood over the sheet, the row's two numbers and only the row's warnings; the sheets drop
## the whole build's warnings and their paragraphs; the Camera row reads its angle off the drawn
## airframe; and a fitted guard's obstruction warning reaches the Camera row and page. Called from
## `TestShellLayout.run` after `ControlPageChecks`.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	var was := shell._focused_name()
	shell.back_to_drone()

	# After the Receiver page (Control's stacked rail), the Camera page stacks its OWN rail over its
	# OWN sheet — the Receiver's sizes must not carry over.
	shell.select_system_by_name("Control")
	await _settle(tree)
	shell.open_row(&"receiver")
	await _settle(tree)
	shell.select_system_by_name("Video")
	await _settle(tree)

	shell.open_row(&"camera")
	await _settle(tree)
	out.append(_the_page_stacks_the_rail_over_the_sheet(shell, "Camera", VideoDiagram.MODE_CAMERA))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"camera"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"camera"))
	out.append(TestResult.new("video dock: the Camera sheet carries no warning list and no sentences",
		not shell.lab.camera_panel.warnings_visible() and not shell.lab.camera_panel.prose_visible(), ""))
	out.append(TestResult.new("video dock: the Electronics rail's budget paragraph is off the page",
		not shell.lab.electronics_picker.note_visible(), ""))
	out.append(_a_label_is_on_screen(shell, shell.lab.camera_panel, "Box L × W × H"))
	out.append(_a_label_is_on_screen(shell, shell.lab.camera_panel, "Camera uptilt"))
	out.append(_a_label_is_on_screen(shell, shell.lab.electronics_picker, "Antenna"))
	out.append(TestResult.new("video dock: the Camera row reads its angle off the drawn airframe",
		str(_row(shell, &"camera").get("line3")) == VideoFigures.nearest_text(
			shell.lab.airframe.camera_clearances())
			and str(_row(shell, &"camera").get("line3")).begins_with("frame edge ~"),
		str(_row(shell, &"camera").get("line3"))))
	# Nothing fitted is further into the picture than the frame, so the nearest-object line is an
	# informational note and the row stays green.
	out.append(TestResult.new("video dock: with nothing intruding, the Camera row is green",
		_row(shell, &"camera").get("status") == SectionRows.OK,
		str(_row(shell, &"camera").get("status"))))

	shell.open_row(&"vtx")
	await _settle(tree)
	out.append(_the_page_stacks_the_rail_over_the_sheet(shell, "VTX & antenna", VideoDiagram.MODE_VTX))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"vtx"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"vtx"))
	out.append(TestResult.new("video dock: the VTX sheet is its two parts, with no whole-build warning list",
		shell.lab.electronics_details.shown_keys() == ElectronicsDetails.VTX_SHEET_ROWS
			and not shell.lab.electronics_details.warnings_visible(),
		str(shell.lab.electronics_details.shown_keys())))
	out.append(_a_label_is_on_screen(shell, shell.lab.electronics_details, "— output"))

	# A FITTED GUARD REACHES THE CAMERA ROW AND PAGE: its obstruction warning is measured on the
	# drawn airframe, not in Build.warnings(), so only the shell can hand it to the row.
	var details := shell.lab.propeller_details
	var index := details._guard_ids.find("guard_bumper_5in_abs")
	details._guard_selector.select(index)
	details._on_guard_selected(index)
	await _settle(tree)
	shell.open_row(&"camera")
	await _settle(tree)
	var row := _row(shell, &"camera")
	var owned: Array = row.get("warnings", [])
	out.append(TestResult.new("video dock: a fitted guard's obstruction warning is the Camera row's and its page's",
		owned.size() == 1 and (owned[0] as BuildWarning).id == &"camera_obstruction"
			and shell.item_page_view().warning_count() == 1
			and str(row.get("line3")).begins_with("⚠ guard "),
		"%d owned, %d shown, '%s'" % [owned.size(), shell.item_page_view().warning_count(),
			row.get("line3")]))
	# RELEVANT, SO AMBER: the obstruction check found the guard further into the lens's view than
	# the airframe itself (its own threshold, no lens angle invented).
	out.append(TestResult.new("video dock: a guard intruding into the camera's view turns the Camera row amber",
		row.get("status") == SectionRows.WARN, str(row.get("status"))))
	out.append(TestResult.new("video dock: with a camera warning live, the Camera sheet still lists none of its own",
		not shell.lab.camera_panel.warnings_visible(), ""))
	out.append(TestResult.new("video dock: with the guard fitted the Camera drawing draws the frame's cone too",
		is_finite(shell.video_diagram().frame_deg)
			and str(shell.video_diagram().nearest.get("name", "")).begins_with("guard "), ""))
	details._guard_selector.select(0)
	details._on_guard_selected(0)
	await _settle(tree)

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("video dock: Back leaves no Video page up",
		not shell.item_page().visible and not shell._inspector.visible
			and not shell._rail_glass.visible, ""))
	if was != "":
		shell.select_system_by_name(was)
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


## The rail over the sheet, one column against the list; the drawing from the stage's left edge to
## that column; the rail its own height; nothing overlapping, everything inside the window.
static func _the_page_stacks_the_rail_over_the_sheet(shell: GlassShell, name: String,
		mode: String) -> TestResult:
	var drawing := shell.item_page().get_global_rect()
	var rail := shell._rail_glass.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var body := shell.item_page_view().body
	var window := shell.get_global_rect()
	var own_height := shell._rail_glass.get_combined_minimum_size().y
	var ok := shell._rail_glass.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and shell.item_page().is_visible_in_tree() and body == shell.video_diagram() \
		and shell.video_diagram().mode == mode \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and rail.end.y <= sheet.position.y and absf(rail.size.y - own_height) < 1.0 \
		and sheet.size.y > 150.0 \
		and absf(rail.position.x - sheet.position.x) < 1.0 and absf(rail.end.x - sheet.end.x) < 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and drawing.end.x <= rail.position.x \
		and drawing.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and window.encloses(rail) and window.encloses(sheet)
	return TestResult.new("video dock: the %s page stands the Electronics rail over its sheet, the drawing beside"
		% name, ok, "drawing %s, body %s, rail %s (own %.0f), sheet %s, list %s" % [drawing,
		body.size if body != null else Vector2.ZERO, rail, own_height, sheet, list])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("video dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness(),
		{"camera_view": shell.lab.airframe.camera_clearances()})
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("video dock: the %s page shows its two numbers" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])


## A caption laid out with height, inside the window and inside every scroll around it.
static func _a_label_is_on_screen(shell: GlassShell, panel: Control, text: String) -> TestResult:
	var found: Label = null
	for child in panel.find_children("*", "Label", true, false):
		if (child as Label).text == text:
			found = child
	var rect := found.get_global_rect() if found != null else Rect2()
	var ok := found != null and found.is_visible_in_tree() and rect.size.y > 0.0 \
		and shell.get_global_rect().encloses(rect)
	var node: Node = found.get_parent() if found != null else null
	while node != null and node != shell:
		if node is ScrollContainer:
			ok = ok and (node as Control).get_global_rect().encloses(rect)
		node = node.get_parent()
	return TestResult.new("video dock: '%s' is on screen on its page" % text, ok, str(rect))
