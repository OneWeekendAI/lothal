class_name LabDockChecks
extends RefCounted
## The Lab dock (plans/2026-09-26-lab-dock-design.md §2, §5.3, §5.4) on a laid-out shell.
##
## Called from `TestShellLayout.run`, because every claim here is about where something ENDED UP —
## the list's rect, what the stage shows, which row is lit — and only that suite processes frames.
##
## One result per case. The "every row opens a page" sweep emits one line PER ROW, named by the row,
## so a row whose page went missing is its own red line (the Quiet Canvas near-miss: parts silently
## unreachable).

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, window: Vector2i) -> Array:
	var out: Array = []
	shell.back_to_drone()
	shell.select_system_by_name("Propulsion")
	await _settle(tree)

	out.append(_the_list_stands_at_the_right_between_the_bars(shell, window))
	out.append(_the_viewport_is_the_stage(shell))
	out.append(_the_top_bar_carries_the_build_numbers(shell))
	out.append(_the_motor_page_no_longer_repeats_them(shell))

	# A row click opens its page, the list stays, and the row is lit.
	shell.section_list().row_opened.emit(&"motors")
	await _settle(tree)
	out.append(_a_row_opens_its_page_in_the_stage(shell))
	out.append(_the_list_stays_with_the_open_row_lit(shell))
	out.append(_the_page_bar_says_where_you_are(shell))
	out.append(_the_page_stays_clear_of_the_list(shell))

	# Moving between rows without going back first.
	shell.section_list().row_opened.emit(&"propellers")
	await _settle(tree)
	out.append(TestResult.new("lab dock: another row's page replaces the first, no Back needed",
		shell.open_page().get("id") == &"propellers" and _shown_tab(shell) == "Prop",
		"page %s, tab %s" % [shell.open_page().get("id"), _shown_tab(shell)]))

	# Esc returns to the drone.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell._unhandled_key_input(escape)
	await _settle(tree)
	out.append(_back_on_the_drone(shell, "Esc"))

	# ← Back to drone returns to the drone.
	shell.open_row(&"motors")
	await _settle(tree)
	shell._back_button.pressed.emit()
	await _settle(tree)
	out.append(_back_on_the_drone(shell, "← Back to drone"))

	# The choice line opens the finder on that row's own rail.
	shell.section_list().pick_requested.emit(&"propellers")
	await _settle(tree)
	var header := str(shell.finder()._header.text) if shell.finder() != null else ""
	out.append(TestResult.new("lab dock: a row's choice line opens the finder on its own rail",
		shell.finder_open() and header == "Propulsion · Propeller", "open %s, header '%s'" % [
			shell.finder_open(), header]))
	shell.close_finder()
	await _settle(tree)

	# A section word selects and does NOT summon the finder.
	shell._dock.system_chosen.emit(_index_of("Power"))
	await _settle(tree)
	out.append(TestResult.new("lab dock: a section word selects the section and summons nothing",
		shell.section_list().section == "Power" and not shell.finder_open(),
		"list shows %s, finder open %s" % [shell.section_list().section, shell.finder_open()]))

	# Collapse and restore.
	out.append_array(await _collapse(shell, tree))

	# The Frame row's page is the frame designer, in the stage.
	shell.select_system_by_name("Airframe")
	await _settle(tree)
	shell.open_row(&"frame")
	await _settle(tree)
	out.append(_the_frame_page_is_the_designer(shell))
	shell.back_to_drone()

	# No row wraps, in every section.
	for section in SectionRows.SECTIONS:
		shell.select_system_by_name(str(section))
		await _settle(tree)
		out.append(_no_row_wraps(shell, str(section)))

	# EVERY ROW OPENS A PAGE — one line per row.
	for section in SectionRows.SECTIONS:
		shell.select_system_by_name(str(section))
		await _settle(tree)
		for row in shell.section_list().rows():
			if bool(row.get("soon", false)):
				continue
			shell.open_row(row["id"])
			await _settle(tree)
			out.append(_the_row_reached_its_page(shell, str(section), row))
			shell.back_to_drone()
	shell.select_system_by_name("Propulsion")
	await _settle(tree)
	return out


static func _settle(tree: SceneTree) -> void:
	for i in SETTLE:
		await tree.process_frame


static func _index_of(system_name: String) -> int:
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == system_name:
			return i
	return -1


static func _shown_tab(shell: GlassShell) -> String:
	var tabs := shell.lab.panels
	return tabs.get_tab_title(tabs.current_tab) if tabs.current_tab >= 0 else ""


static func _viewport_up(shell: GlassShell) -> bool:
	var canvas := shell.lab.viewport().get_parent() as Control
	return canvas != null and canvas.is_visible_in_tree()


static func _the_list_stands_at_the_right_between_the_bars(shell: GlassShell,
		window: Vector2i) -> TestResult:
	var rect := shell.section_list().get_global_rect()
	var dock_top := shell._dock.get_global_rect().position.y
	var ok := shell.section_list().is_visible_in_tree() \
		and absf(rect.end.x - window.x) <= 1.0 \
		and absf(rect.size.x - SectionList.WIDTH) <= 1.0 \
		and rect.position.y >= GlassShell.TOP_BAR_HEIGHT - 1.0 and rect.end.y <= dock_top + 1.0
	return TestResult.new("lab dock: the list stands at the right edge, ~280 px, between the bars",
		ok, "list %s, dock top %.0f" % [rect, dock_top])


## The viewport takes the stage and ends where the list begins — the drone is not under the list.
static func _the_viewport_is_the_stage(shell: GlassShell) -> TestResult:
	var canvas := shell.lab.viewport().get_parent() as Control
	var rect := canvas.get_global_rect() if canvas != null else Rect2()
	var list_left := shell.section_list().get_global_rect().position.x
	return TestResult.new("lab dock: the viewport fills the stage and stops at the list",
		_viewport_up(shell) and rect.end.x <= list_left + 1.0 and rect.size.x > 600.0
			and rect.position.y >= GlassShell.TOP_BAR_HEIGHT - 1.0,
		"viewport %s, list starts x=%.0f" % [rect, list_left])


static func _the_top_bar_carries_the_build_numbers(shell: GlassShell) -> TestResult:
	var text := shell.build_stats_text()
	var want := GlassShell.build_stats_for(shell.lab.build_with_open_harness())
	return TestResult.new("lab dock: the top bar reads Dry · AUW · T:W · Flight for the live build",
		text == want and text.begins_with("Dry ") and text.contains("AUW ")
			and text.contains("T:W ") and text.contains("Flight "), "'%s' want '%s'" % [text, want])


## §2: the whole-build numbers are "never repeated inside a section".
static func _the_motor_page_no_longer_repeats_them(shell: GlassShell) -> TestResult:
	return TestResult.new("lab dock: the Motor page no longer carries the whole-build stat rows",
		not shell.lab.motor_details.build_stats_visible()
			and shell.lab.motor_details.stat_text("weight") != "(missing)",
		"stats visible %s" % shell.lab.motor_details.build_stats_visible())


static func _a_row_opens_its_page_in_the_stage(shell: GlassShell) -> TestResult:
	return TestResult.new("lab dock: clicking Motors replaces the viewport with the Motor page",
		shell.page_open() and not _viewport_up(shell) and shell._inspector.is_visible_in_tree()
			and _shown_tab(shell) == "Motor",
		"page %s, viewport up %s, page body up %s, tab %s" % [shell.open_page(),
			_viewport_up(shell), shell._inspector.visible, _shown_tab(shell)])


static func _the_list_stays_with_the_open_row_lit(shell: GlassShell) -> TestResult:
	var list := shell.section_list()
	return TestResult.new("lab dock: the list stays on screen with the open row highlighted",
		list.is_visible_in_tree() and list.open_row == &"motors", "open row %s" % list.open_row)


static func _the_page_bar_says_where_you_are(shell: GlassShell) -> TestResult:
	return TestResult.new("lab dock: the page bar reads ← Back to drone and Lab / Propulsion / Motors",
		shell._page_bar.is_visible_in_tree() and shell._back_button.text == "← Back to drone"
			and shell.page_crumb() == "Lab  /  Propulsion  /  Motors",
		"crumb '%s'" % shell.page_crumb())


static func _the_page_stays_clear_of_the_list(shell: GlassShell) -> TestResult:
	var page := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	return TestResult.new("lab dock: the page body and the list do not overlap",
		page.end.x <= list.position.x and page.size.x > 200.0,
		"page %s, list %s" % [page, list])


static func _back_on_the_drone(shell: GlassShell, how: String) -> TestResult:
	return TestResult.new("lab dock: %s returns the stage to the drone" % how,
		not shell.page_open() and _viewport_up(shell) and not shell._inspector.visible
			and not shell._page_bar.visible and shell.section_list().open_row == &"",
		"page %s, viewport %s" % [shell.open_page(), _viewport_up(shell)])


static func _collapse(shell: GlassShell, tree: SceneTree) -> Array:
	var out: Array = []
	var canvas := shell.lab.viewport().get_parent() as Control
	var before := canvas.get_global_rect().size.x
	var project_id := shell.container.project.project_id
	(shell.section_list().find_child("Collapse", true, false) as Button).pressed.emit()
	await _settle(tree)
	var after := canvas.get_global_rect().size.x
	var list := shell.section_list().get_global_rect()
	out.append(TestResult.new("lab dock: ›| collapses the list to a thin strip and the drone gets the room",
		shell.section_list().collapsed and list.size.x <= SectionList.STRIP_WIDTH + 1.0
			and after >= before + SectionList.WIDTH - SectionList.STRIP_WIDTH - 1.0,
		"list %.0f px wide, viewport %.0f -> %.0f" % [list.size.x, before, after]))
	out.append(TestResult.new("lab dock: the collapsed state is saved for this project",
		shell.settings.list_collapsed(project_id)
			and AppSettings.load_from().list_collapsed(project_id), "project %s" % project_id))
	out.append(TestResult.new("lab dock: collapsing keeps the section selected",
		shell.section_list().section == "Power", shell.section_list().section))
	(shell.section_list().find_child("Strip", true, false) as Button).pressed.emit()
	await _settle(tree)
	out.append(TestResult.new("lab dock: the strip brings the list back",
		not shell.section_list().collapsed
			and absf(shell.section_list().get_global_rect().size.x - SectionList.WIDTH) <= 1.0
			and not shell.settings.list_collapsed(project_id), ""))
	return out


static func _the_frame_page_is_the_designer(shell: GlassShell) -> TestResult:
	var room := shell.workbench().get_global_rect()
	var list := shell.section_list().get_global_rect()
	return TestResult.new("lab dock: the Frame row opens the frame designer in the stage, beside the list",
		shell.workbench().is_visible_in_tree() and room.end.x <= list.position.x
			and shell.section_list().is_visible_in_tree()
			and room.position.y >= GlassShell.TOP_BAR_HEIGHT + GlassShell.PAGE_BAR_HEIGHT - 1.0,
		"designer %s, list %s" % [room, list])


## §5.5: "check that no row wraps to a fourth line". Every row is exactly its fixed height and
## every label in it is one line tall.
static func _no_row_wraps(shell: GlassShell, section: String) -> TestResult:
	var bad: Array = []
	var list := shell.section_list()
	for row in list.rows():
		var control := list.row_control(row["id"])
		if control == null:
			bad.append("%s missing" % row["name"])
			continue
		var want := SectionList.SOON_HEIGHT if bool(row.get("soon", false)) else SectionList.ROW_HEIGHT
		if absf(control.size.y - want) > 0.5:
			bad.append("%s is %.0f px tall" % [row["name"], control.size.y])
		for label in control.find_children("*", "Label", true, false):
			if (label as Label).get_line_count() > 1:
				bad.append("%s: '%s' wraps" % [row["name"], (label as Label).text])
		if control.get_global_rect().end.y > list.get_global_rect().end.y + 0.5:
			bad.append("%s runs past the list" % row["name"])
	return TestResult.new("lab dock: no %s row wraps or runs past the list" % section,
		bad.is_empty() and not list.rows().is_empty(), str(bad))


static func _the_row_reached_its_page(shell: GlassShell, section: String, row: Dictionary) -> TestResult:
	var page: Dictionary = row["page"]
	var ok := shell.page_open() and not _viewport_up(shell)
	var shown := ""
	if page.has("room"):
		var room: Control = {"frame": shell.workbench(), "field": shell.field_room(),
			"blade": shell.blade_room(), "power": shell.power_room()}.get(str(page["room"]))
		ok = ok and room != null and room.is_visible_in_tree()
		shown = "room %s" % page["room"]
	else:
		shown = _shown_tab(shell)
		ok = ok and shell._inspector.is_visible_in_tree() \
			and (page["panels"] as Array).has(shown)
		if page.has("column"):
			ok = ok and shell._rail_glass.is_visible_in_tree()
	return TestResult.new("lab dock: %s / %s opens its page" % [section, row["name"]], ok,
		"showing %s for %s" % [shown, page])
