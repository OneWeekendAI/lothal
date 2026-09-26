class_name PrintedPageChecks
extends RefCounted
## The Printed section of the Lab dock on a laid-out shell: one row per printed part, each opening
## its own drawing beside the Print sheet cut to that part, with the row's two numbers and only the
## row's warnings; and a divergence from a print record turns that part's row amber, lists on its
## page behind Why?, and leaves its own Keep / Reprint on the sheet. Called from
## `TestShellLayout.run` after `VideoPageChecks`.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	var was := shell._focused_name()
	shell.back_to_drone()
	shell.select_system_by_name("Printed")
	await _settle(tree)

	out.append(TestResult.new("printed dock: the list has a row for the arm guards and one for the battery pad",
		not _row(shell, &"printed:arm_guard").is_empty() and not _row(shell, &"printed:battery_pad").is_empty(),
		str(shell.section_list().rows().map(func(r: Dictionary) -> String: return str(r["id"])))))

	shell.open_row(&"printed:arm_guard")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_sheet(shell, "arm_guard"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"printed:arm_guard"))
	out.append(TestResult.new("printed dock: the arm guard page's sheet is the arm guard's line alone, without the room's sentences",
		shell.lab.print_panel.shown_parts() == ["arm_guard"] and not shell.lab.print_panel.prose_visible(),
		str(shell.lab.print_panel.shown_parts())))
	out.append(TestResult.new("printed dock: the arm guard page lists no warnings on a fresh drone",
		shell.item_page_view().warning_count() == 0, ""))

	shell.open_row(&"printed:battery_pad")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_sheet(shell, "battery_pad"))
	out.append(TestResult.new("printed dock: moving to the pad's page moves the sheet to the pad",
		shell.lab.print_panel.shown_parts() == ["battery_pad"], str(shell.lab.print_panel.shown_parts())))

	# A DIVERGENCE REACHES ITS ROW AND ITS PAGE: the shell holds the findings; the row reads them.
	shell.printed_divergence = [{"part": "battery_pad", "kind": "differs", "date": "2026-09-20",
		"key": "battery_pad|a|b", "message": "The battery pad you printed on 2026-09-20 differs (a check)."}]
	shell.lab.print_panel.set_divergence(shell.printed_divergence)
	shell._refresh_list()
	await _settle(tree)
	var row := _row(shell, &"printed:battery_pad")
	out.append(TestResult.new("printed dock: a diverged battery pad is amber on its own row",
		str(row.get("status")) == SectionRows.WARN
			and str(row.get("line3")) == "⚠ differs from the 2026-09-20 print"
			and str(_row(shell, &"printed:arm_guard").get("status")) == SectionRows.OK, str(row.get("line3"))))
	out.append(TestResult.new("printed dock: the diverged pad's page lists it once, Why? closed, and keeps its Keep and Reprint",
		shell.item_page_view().warning_count() == 1 and not shell.item_page_view().why_visible(0)
			and shell.lab.print_panel.divergence_button("battery_pad", "keep").is_visible_in_tree()
			and shell.lab.print_panel.divergence_button("battery_pad", "reprint").is_visible_in_tree()
			and not shell.lab.print_panel.finding_text_visible("battery_pad"), ""))
	shell.printed_divergence = []
	shell.lab.print_panel.set_divergence([])
	shell._refresh_list()
	await _settle(tree)

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("printed dock: Back leaves no Printed page up",
		not shell.item_page().visible and not shell._inspector.visible, ""))
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


static func _the_drawing_stands_beside_the_sheet(shell: GlassShell, part: String) -> TestResult:
	var drawing := shell.item_page().get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var body := shell.item_page_view().body
	var window := shell.get_global_rect()
	var ok := shell._inspector.is_visible_in_tree() and shell.item_page().is_visible_in_tree() \
		and body == shell.printed_diagram() and shell.printed_diagram().part_id == part \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x + 1.0 \
		and window.encloses(sheet) and window.encloses(drawing)
	return TestResult.new("printed dock: the %s page draws the part beside its sheet, inside the window" % part,
		ok, "drawing %s, body %s, sheet %s, list %s" % [drawing, body.size if body != null else Vector2.ZERO,
		sheet, list])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness())
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("printed dock: the %s page shows its two numbers" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])
