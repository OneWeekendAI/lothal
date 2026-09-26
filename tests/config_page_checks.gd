class_name ConfigPageChecks
extends RefCounted
## The Config section of the Lab dock on a laid-out shell: each of the five pages draws its own
## ConfigDiagram mode beside its own panel, with the row's two numbers and only the row's warnings;
## the panels drop their sentences and warning lists on the dock and keep their controls. Called
## from `TestShellLayout.run` after `PrintedPageChecks`.
##
## One result per case, never a loop over the pages.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	var was := shell._focused_name()
	shell.back_to_drone()
	shell.select_system_by_name("Config")
	await _settle(tree)

	shell.open_row(&"motor_direction")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_panel(shell, "Motor direction", ConfigDiagram.MODE_MOTORS))
	out.append(_the_page_shows_the_rows_numbers(shell, &"motor_direction"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"motor_direction"))
	out.append(TestResult.new("config dock: the Motors panel keeps its chooser and drops its sentences",
		shell.lab.motors_panel._chooser.is_visible_in_tree()
			and not shell.lab.motors_panel._refusal.is_visible_in_tree(), ""))

	shell.open_row(&"ports")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_panel(shell, "Ports", ConfigDiagram.MODE_PORTS))
	out.append(_the_page_shows_the_rows_numbers(shell, &"ports"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"ports"))
	out.append(TestResult.new("config dock: the Ports panel keeps its count box and drops its sentences",
		shell.lab.ports_panel.port_field().is_visible_in_tree()
			and not shell.lab.ports_panel._supply.is_visible_in_tree(), ""))

	shell.open_row(&"failsafe")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_panel(shell, "Failsafe", ConfigDiagram.MODE_FAILSAFE))
	out.append(_the_page_shows_the_rows_numbers(shell, &"failsafe"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"failsafe"))
	out.append(TestResult.new("config dock: the Failsafe panel keeps its chooser and drops the arming notes",
		shell.lab.failsafe_panel.stage2_chooser().is_visible_in_tree()
			and not shell.lab.failsafe_panel._arming.is_visible_in_tree(), ""))

	shell.open_row(&"rates")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_panel(shell, "Rates", ConfigDiagram.MODE_RATES))
	out.append(_the_page_shows_the_rows_numbers(shell, &"rates"))
	out.append(TestResult.new("config dock: the Rates panel keeps its rate box and drops its sentences",
		shell.lab.rates_panel.rate_field().is_visible_in_tree()
			and not shell.lab.rates_panel._modes.is_visible_in_tree(), ""))

	shell.open_row(&"sheet")
	await _settle(tree)
	out.append(_the_drawing_stands_beside_the_panel(shell, "Sheet", ConfigDiagram.MODE_SHEET))
	out.append(_the_page_shows_the_rows_numbers(shell, &"sheet"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"sheet"))
	out.append(TestResult.new("config dock: the Sheet panel keeps Export and drops the full text",
		shell.lab.sheet_panel.export_button().is_visible_in_tree()
			and not shell.lab.sheet_panel._preview.is_visible_in_tree(), ""))

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("config dock: Back leaves no Config page up",
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


static func _the_drawing_stands_beside_the_panel(shell: GlassShell, name: String, mode: String) -> TestResult:
	var drawing := shell.item_page().get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var body := shell.item_page_view().body
	var window := shell.get_global_rect()
	var ok := shell._inspector.is_visible_in_tree() and shell.item_page().is_visible_in_tree() \
		and body == shell.config_diagram() and shell.config_diagram().mode == mode \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x + 1.0 \
		and window.encloses(sheet) and window.encloses(drawing)
	return TestResult.new("config dock: the %s page draws beside its panel, inside the window" % name,
		ok, "drawing %s, body %s, sheet %s, list %s" % [drawing, body.size if body != null else Vector2.ZERO,
		sheet, list])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness())
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("config dock: the %s page shows its two numbers" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("config dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])
