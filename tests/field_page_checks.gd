class_name FieldPageChecks
extends RefCounted
## The Field section of the Lab dock on a laid-out shell: each of the three pages shows the site
## with its row's two numbers and own warnings above it, and only its own settings and panel in one
## column beside it — and the whole page stands BESIDE the list at 1280 rather than folding it.
## Then the production path: an edit made in the room reaches the row, the page and the garage's
## air, through the shell as the app takes it (field-room.md Ruling 2 — never only the API).
## Called from `TestShellLayout.run` after `ConfigPageChecks`.
##
## One result per case, never a loop over the pages.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, window: Vector2i) -> Array:
	var out: Array = []
	var was := shell._focused_name()
	var room := shell.field_room()
	shell.back_to_drone()
	shell.select_system_by_name("Field")
	await _settle(tree)

	shell.open_row(&"site")
	await _settle(tree)
	out.append(_the_page_stands_beside_the_list(shell, window, "Site"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"site"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"site"))
	out.append(_only_its_own_settings_and_panel(shell, "site"))
	out.append(_the_panel_stands_under_the_settings(shell, "site"))

	shell.open_row(&"course")
	await _settle(tree)
	out.append(_the_page_stands_beside_the_list(shell, window, "Course"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"course"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"course"))
	out.append(_only_its_own_settings_and_panel(shell, "course"))
	out.append(_the_panel_stands_under_the_settings(shell, "course"))
	out.append(TestResult.new("field dock: the Course panel keeps its sliders and drops its warning list",
		(room.panel("Course") as FieldSystem.CoursePanel).height_slider.is_visible_in_tree()
			and not (room.panel("Course") as FieldSystem.CoursePanel).warnings.is_visible_in_tree(), ""))

	shell.open_row(&"conditions")
	await _settle(tree)
	out.append(_the_page_stands_beside_the_list(shell, window, "Conditions"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"conditions"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"conditions"))
	out.append(_only_its_own_settings_and_panel(shell, "conditions"))
	out.append(_the_panel_stands_under_the_settings(shell, "conditions"))

	# --- THE PRODUCTION PATH: an edit in the room, through the shell's own wiring.
	shell.open_row(&"site")
	await _settle(tree)
	var elevation_was := room.site().elevation_m
	room.set_field_elevation_m(920.0)
	await _settle(tree)
	out.append(_an_elevation_typed_reaches_the_row_and_the_garage(shell))
	room.set_field_elevation_m(elevation_was)
	await _settle(tree)

	shell.open_row(&"course")
	await _settle(tree)
	var width_was := room.site().extent().x
	room.set_site_width_m(FieldSystem.MIN_SITE_DIM_M)
	await _settle(tree)
	out.append(_a_site_shrunk_under_the_course_turns_the_course_row_amber(shell))
	out.append(_the_course_pages_warning_is_drawn_above_the_site(shell))
	room.set_site_width_m(width_was)
	await _settle(tree)

	shell.open_row(&"conditions")
	await _settle(tree)
	var wind_was := room.conditions.selected().wind_speed_mps
	room.set_field_wind_speed_mps(4.0)
	await _settle(tree)
	out.append(_a_wind_typed_reaches_the_row_and_the_page(shell))
	room.set_field_wind_speed_mps(wind_was)
	await _settle(tree)

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("field dock: Back leaves no Field page up",
		not shell.page_open() and not room.visible, ""))
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


## The figures the rows compute from, as the shell hands them: the rooms' own selections.
static func _numbers(shell: GlassShell, id: StringName) -> Array:
	return FieldFigures.page_numbers(id, shell.rooms.site_of_selected_course(),
		shell.rooms.course_library.selected(), shell.rooms.conditions_library.selected())


static func _the_page_stands_beside_the_list(shell: GlassShell, window: Vector2i, name: String) -> TestResult:
	var room := shell.field_room()
	var list := shell.section_list()
	var room_rect := room.get_global_rect()
	var site := room.viewport_container.get_global_rect()
	var frame := Rect2(Vector2.ZERO, Vector2(window))
	var ok := room.is_visible_in_tree() and list.is_visible_in_tree() and not list.collapsed \
		and room_rect.end.x <= list.get_global_rect().position.x + 0.5 \
		and site.size.x >= GlassShell.FIELD_SITE_FLOOR and frame.encloses(room_rect)
	return TestResult.new("field dock: the %s page stands beside the open list at %dx%d, %d+ px of site"
		% [name, window.x, window.y, int(GlassShell.FIELD_SITE_FLOOR)], ok,
		"list collapsed %s at x=%.0f · room %s · site %.0f px wide" % [list.collapsed,
		list.get_global_rect().position.x, room_rect, site.size.x])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := _numbers(shell, id)
	var view := shell.field_room().page_view
	var ok := want.size() == 2 and view.is_visible_in_tree()
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("field dock: the %s page shows its two numbers above the site" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.field_room().page_view
	var ok := not row.is_empty() and view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("field dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


static func _only_its_own_settings_and_panel(shell: GlassShell, page: String) -> TestResult:
	var room := shell.field_room()
	var own_panel := str(FieldSystem.DOCK_PANELS[page])
	var bad: Array = []
	for title in FieldSystem.PANEL_TITLES:
		if room.panel(str(title)).is_visible_in_tree() != (str(title) == own_panel):
			bad.append("panel %s" % title)
	var wanted := room.rail_controls_for(page)
	var shown := 0
	for child in room.site_list.get_parent().get_children():
		if child is SpecPanel:
			continue
		var on := (child as Control).is_visible_in_tree()
		if on:
			shown += 1
		if on != wanted.has(child):
			bad.append(str(child.name))
	return TestResult.new("field dock: the %s page shows its own %d settings and the %s panel, nothing else"
		% [page, wanted.size(), own_panel], bad.is_empty() and shown == wanted.size() and shown > 0,
		"%d shown · wrong: %s" % [shown, bad])


static func _the_panel_stands_under_the_settings(shell: GlassShell, page: String) -> TestResult:
	var room := shell.field_room()
	var panel := room.panel(str(FieldSystem.DOCK_PANELS[page]))
	var rail := room.rail_panel().get_global_rect()
	var rect := panel.get_global_rect()
	var lowest := 0.0
	for control in room.rail_controls_for(page):
		lowest = maxf(lowest, (control as Control).get_global_rect().end.y)
	return TestResult.new("field dock: the %s panel stands under its settings, inside the rail" % page,
		rail.encloses(rect) and rect.position.y >= lowest and rect.size.y > 40.0 and rect.size.x > 200.0,
		"panel %s · settings end y=%.0f · rail %s" % [rect, lowest, rail])


static func _an_elevation_typed_reaches_the_row_and_the_garage(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"site")
	var garage := shell.lab.current_build().air
	var want := "920 m · ~%.2f kg/m³" % garage.kgm3()
	var view := shell.field_room().page_view
	return TestResult.new("field dock: 920 m typed in the room reads on the Site row in the garage's own air",
		row.get("line3") == want and absf(garage.elevation_m - 920.0) < 0.01
			and view.number_text(0) == "Air density ~%.2f kg/m³" % garage.kgm3(),
		"row '%s' want '%s' · page '%s'" % [row.get("line3"), want, view.number_text(0)])


static func _a_site_shrunk_under_the_course_turns_the_course_row_amber(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"course")
	var view := shell.field_room().page_view
	var listed := false
	for i in view.warning_count():
		listed = listed or view.short_text(i).ends_with("course leaves the site")
	return TestResult.new("field dock: a site shrunk under the course turns the Course row amber, and its page says why",
		row.get("status") == SectionRows.WARN and row.get("line3") == "⚠ course leaves the site" and listed,
		"row %s '%s' · page lists it %s" % [row.get("status"), row.get("line3"), listed])


static func _the_course_pages_warning_is_drawn_above_the_site(shell: GlassShell) -> TestResult:
	var view := shell.field_room().page_view
	var site := shell.field_room().viewport_container.get_global_rect()
	var box := view.get_node("Warnings") as Control
	var rect := box.get_global_rect()
	return TestResult.new("field dock: the Course page's warning is drawn above the site, inside the page",
		view.warning_count() > 0 and rect.size.y > 0.0 and rect.end.y <= site.position.y
			and view.get_global_rect().encloses(rect),
		"warnings %s · site %s" % [rect, site])


static func _a_wind_typed_reaches_the_row_and_the_page(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"conditions")
	var view := shell.field_room().page_view
	var from := roundi(shell.rooms.conditions_library.selected().wind_from_deg)
	return TestResult.new("field dock: 4 m/s typed in the room reads on the Conditions row and its page",
		str(row.get("line3")).ends_with("wind 4.0 m/s from %d°" % from)
			and view.number_text(1) == "Wind 4.0 m/s from %d°" % from
			and is_equal_approx(shell.lab.current_build().field_wind_mps, 4.0),
		"row '%s' · page '%s' · garage wind %.1f" % [row.get("line3"), view.number_text(1),
		shell.lab.current_build().field_wind_mps])
