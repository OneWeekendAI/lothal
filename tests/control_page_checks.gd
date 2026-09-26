class_name ControlPageChecks
extends RefCounted
## The Control section of the Lab dock on a laid-out shell: Flight controller, Receiver & link and
## Tune each open their own drawing beside their own sheet, with the row's two numbers and only
## the row's warnings; the Receiver page's Link rail stands over its sheet (side by side, rail +
## sheet + drawing do not fit beside the list at 1280); the sheets drop the whole build's warnings
## and their paragraphs; and a gain edit reaches the Tune row and page. Called from
## `TestShellLayout.run` after `PowerPageChecks`.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	var was := shell._focused_name()
	shell.back_to_drone()
	shell.select_system_by_name("Control")
	await _settle(tree)

	shell.open_row(&"fc")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Flight controller"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"fc"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"fc"))
	out.append(TestResult.new("control dock: the FC sheet carries no whole-build warning list",
		not shell.lab.fc_details.warnings_visible(), ""))
	out.append(_a_label_is_on_screen(shell, shell.lab.fc_details, "Noise at the motors"))
	out.append(TestResult.new("control dock: the FC row reads its UARTs used on line 3",
		str(_row(shell, &"fc").get("line3")) == ControlFigures.ports_used_text(
			shell.lab.build_with_open_harness()), str(_row(shell, &"fc").get("line3"))))

	shell.open_row(&"receiver")
	await _settle(tree)
	out.append(_the_receiver_page_stacks_the_rail_over_the_sheet(shell))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"receiver"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"receiver"))
	out.append(TestResult.new("control dock: the Link sheet carries no whole-build warning list",
		not shell.lab.link_details.warnings_visible(), ""))
	out.append(TestResult.new("control dock: the Link rail's budget paragraph is off the page",
		not shell.lab.link_picker.note_visible(), ""))
	out.append(_a_label_is_on_screen(shell, shell.lab.link_picker, "Buzzer"))
	out.append(_a_label_is_on_screen(shell, shell.lab.link_details, "Link total"))

	shell.open_row(&"tune")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Tune"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"tune"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"tune"))
	out.append(TestResult.new("control dock: the Tune panel's own warning list and sentences are off the page",
		not shell.lab.tune_panel.warnings_visible() and not shell.lab.tune_panel.prose_visible(), ""))
	out.append(TestResult.new("control dock: the Tune row reads D against the ceiling of the tune in force",
		str(_row(shell, &"tune").get("line3")) == "D at ~%d%% of noise ceiling"
			% roundi(ControlFigures.d_ceiling_share(shell.lab.tune) * 100.0),
		str(_row(shell, &"tune").get("line3"))))

	# A GAIN EDIT REACHES THE ROW AND THE PAGE: the path a mouse takes (set_field, apply_axis).
	shell.lab.tune_panel.set_field(0, "p", 3.0)
	shell.lab.tune_panel.apply_axis(0)
	await _settle(tree)
	var edited := _row(shell, &"tune")
	var owned: Array = edited.get("warnings", [])
	out.append(TestResult.new("control dock: a hand gain turns the Tune row 'hand-tuned' and lists the override",
		edited.get("choice") == "hand-tuned" and owned.size() == 1
			and (owned[0] as BuildWarning).id == &"tune_override"
			and shell.item_page_view().warning_count() == 1,
		"%s, %d owned, %d shown" % [edited.get("choice"), owned.size(),
			shell.item_page_view().warning_count()]))
	shell.lab.tune_panel.reset_all()
	await _settle(tree)

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("control dock: Back leaves no Control page up",
		not shell.item_page().visible and not shell._inspector.visible
			and not shell._rail_glass.visible, ""))

	# The stacked rail is the Receiver page's alone: a column page with no drawing (Video's Camera)
	# still stands its rail at the stage's left, full height.
	shell.select_system_by_name("Video")
	await _settle(tree)
	shell.open_row(&"camera")
	await _settle(tree)
	var rail := shell._rail_glass.get_global_rect()
	out.append(TestResult.new("control dock: after the Receiver page, Camera's rail is back at the stage's left",
		shell._rail_glass.visible and rail.position.x <= GlassShell.CLUSTER_MARGIN + 1.0
			and rail.end.x <= shell._inspector.get_global_rect().position.x, str(rail)))
	shell.back_to_drone()
	await _settle(tree)
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


static func _the_page_is_a_drawing_beside_its_sheet(shell: GlassShell, name: String) -> TestResult:
	var view := shell.item_page()
	var drawing := view.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var stage := shell.stage_rect()
	var body := shell.item_page_view().body
	var ok := view.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and body == shell.control_diagram() and body.is_visible_in_tree() \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x \
		and drawing.position.x - stage.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0
	return TestResult.new("control dock: the %s page is its drawing beside its sheet, across the stage"
		% name, ok, "drawing %s, body %s, sheet %s, list %s" % [drawing,
		body.size if body != null else Vector2.ZERO, sheet, list])


## The rail over the sheet, one column against the list; the drawing from the stage's left edge to
## that column; nothing overlapping, everything inside the window.
static func _the_receiver_page_stacks_the_rail_over_the_sheet(shell: GlassShell) -> TestResult:
	var drawing := shell.item_page().get_global_rect()
	var rail := shell._rail_glass.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var body := shell.item_page_view().body
	var window := shell.get_global_rect()
	var ok := shell._rail_glass.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and shell.item_page().is_visible_in_tree() and body == shell.control_diagram() \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and rail.end.y <= sheet.position.y and rail.size.y > 100.0 and sheet.size.y > 150.0 \
		and absf(rail.position.x - sheet.position.x) < 1.0 and absf(rail.end.x - sheet.end.x) < 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and drawing.end.x <= rail.position.x \
		and drawing.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and window.encloses(rail) and window.encloses(sheet)
	return TestResult.new("control dock: the Receiver page stands the Link rail over its sheet, the drawing beside",
		ok, "drawing %s, body %s, rail %s, sheet %s, list %s" % [drawing,
		body.size if body != null else Vector2.ZERO, rail, sheet, list])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("control dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness(),
		{"tune": shell.lab.tune})
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("control dock: the %s page shows its two numbers" % id, ok,
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
	return TestResult.new("control dock: '%s' is on screen on its page" % text, ok, str(rect))
