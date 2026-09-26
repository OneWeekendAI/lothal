class_name PowerPageChecks
extends RefCounted
## The Power section of the Lab dock on a laid-out shell: each of Battery, ESC and Harness opens its
## own drawing beside its own sheet, across the stage, with the row's two numbers and only the
## row's warnings; the pack bench, the ESC bench and the harness designer stay one press away; the
## Pack sheet's rows are on screen under the charger; and the Harness page fits beside the list,
## which the harness designer (a room) does not. Called from `TestShellLayout.run` after
## `PropulsionPageChecks`.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	# Put the section back afterwards: later checks open rows of the section they found.
	var was := shell._focused_name()
	shell.back_to_drone()
	shell.select_system_by_name("Power")
	await _settle(tree)

	shell.open_row(&"battery")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Battery", shell.power_diagram()))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"battery"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"battery"))
	out.append(TestResult.new("power dock: the Pack sheet carries no whole-build warning list",
		not shell.lab.battery_details.warnings_visible(), ""))
	out.append(_a_label_is_on_screen(shell, shell.lab.battery_details, "Cells"))
	out.append(_a_button_is_on_screen(shell, shell.lab.battery_details, "Open pack bench…"))

	shell.open_row(&"esc")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "ESC", shell.power_diagram()))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"esc"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"esc"))
	out.append(TestResult.new("power dock: the ESC sheet carries no whole-build warning list",
		not shell.lab.esc_details.warnings_visible(), ""))
	out.append(_a_button_is_on_screen(shell, shell.lab.esc_details, "Open ESC bench…"))

	shell.open_row(&"harness")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Harness", shell.harness_diagram()))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"harness"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"harness"))
	out.append(TestResult.new("power dock: the Harness page fits beside the list (no fold)",
		shell.section_list().is_visible_in_tree() and not shell.section_list().collapsed,
		"collapsed %s" % shell.section_list().collapsed))
	out.append(_a_button_is_on_screen(shell, shell.lab.harness_panel, "Open harness designer…"))

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("power dock: Back leaves no Power page up",
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


## The drawing takes the left of the stage, the sheet stands against the list, and between them
## they span it.
static func _the_page_is_a_drawing_beside_its_sheet(shell: GlassShell, name: String,
		drawing_control: Control) -> TestResult:
	var view := shell.item_page()
	var drawing := view.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var stage := shell.stage_rect()
	var body := shell.item_page_view().body
	var ok := view.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and body == drawing_control and body.is_visible_in_tree() \
		and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x \
		and drawing.position.x - stage.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0
	return TestResult.new("power dock: the %s page is its drawing beside its sheet, across the stage"
		% name, ok, "drawing %s, body %s, sheet %s, list %s" % [drawing,
		body.size if body != null else Vector2.ZERO, sheet, list])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("power dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness())
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("power dock: the %s page shows its two numbers" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])


static func _a_button_is_on_screen(shell: GlassShell, panel: Control, text: String) -> TestResult:
	var found: Button = null
	for child in panel.find_children("*", "Button", true, false):
		if (child as Button).text == text:
			found = child
	var rect := found.get_global_rect() if found != null else Rect2()
	var ok := found != null and found.is_visible_in_tree() and not found.disabled \
		and rect.size.y > 0.0 and shell.get_global_rect().encloses(rect)
	return TestResult.new("power dock: '%s' is on screen on its page" % text, ok, str(rect))


## A spec row's caption laid out with height and inside the window — the Pack sheet's rows folded
## to nothing under the charger before its inner scroll was turned off.
static func _a_label_is_on_screen(shell: GlassShell, panel: Control, text: String) -> TestResult:
	var found: Label = null
	for child in panel.find_children("*", "Label", true, false):
		if (child as Label).text == text:
			found = child
	var rect := found.get_global_rect() if found != null else Rect2()
	# Inside what EVERY scroll around it shows — the Pack tab's and the sheet's own inner one, which
	# had no height under the charger — not merely inside the sheet.
	var ok := found != null and found.is_visible_in_tree() and rect.size.y > 0.0 \
		and shell.get_global_rect().encloses(rect)
	var clips: Array = []
	var node: Node = found.get_parent() if found != null else null
	while node != null and node != panel.get_parent().get_parent():
		if node is ScrollContainer:
			var clip := (node as Control).get_global_rect()
			clips.append(clip)
			ok = ok and clip.encloses(rect)
		node = node.get_parent()
	ok = ok and clips.size() >= 1
	return TestResult.new("power dock: the Pack sheet's '%s' row is on screen" % text, ok,
		"%s in scrolls %s" % [rect, clips])
