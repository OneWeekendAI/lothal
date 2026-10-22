class_name PropulsionPageChecks
extends RefCounted
## The Propulsion section of the Lab dock on a laid-out shell: each of Motors, Propellers and Prop
## guards opens its own drawing beside its own sheet, across the stage, with the row's two numbers
## and only the row's warnings; the thrust bench and the blade designer stay one press away; and
## fitting a guard reaches the row, the numbers and the drawing. Called from `TestShellLayout.run`
## after `AirframePageChecks`, for the reason that file gives.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	shell.back_to_drone()
	shell.select_system_by_name("Propulsion")
	await _settle(tree)

	shell.open_row(&"motors")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Motors", "thrust"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"motors"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"motors"))
	out.append(TestResult.new("propulsion dock: the Motor sheet carries no whole-build warning list",
		not shell.lab.motor_details.warnings_visible(), ""))
	out.append(_a_button_is_on_screen(shell, shell.lab.motor_details, "Open thrust bench…"))

	shell.open_row(&"propellers")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Propellers", "prop"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"propellers"))
	out.append(_the_page_shows_the_rows_numbers(shell, &"propellers"))
	out.append(TestResult.new("propulsion dock: the Propellers sheet is the blade half, no guard",
		shell.lab.propeller_details.sheet_parts()["guard"] == false
			and shell.lab.propeller_details.sheet_parts()["rows"] == true,
		str(shell.lab.propeller_details.sheet_parts())))
	out.append(_a_button_is_on_screen(shell, shell.lab.propeller_details, "Design this blade…"))

	shell.open_row(&"guards")
	await _settle(tree)
	out.append(_the_page_is_a_drawing_beside_its_sheet(shell, "Prop guards", "guard"))
	out.append(_the_page_lists_only_its_own_warnings(shell, &"guards"))
	out.append(TestResult.new("propulsion dock: the Prop guards sheet is the guard half, no blade rows",
		shell.lab.propeller_details.sheet_parts()["guard"] == true
			and shell.lab.propeller_details.sheet_parts()["rows"] == false,
		str(shell.lab.propeller_details.sheet_parts())))

	# FIT A GUARD, the way the builder does: the selector's own handler.
	var details := shell.lab.propeller_details
	var index := details._guard_ids.find("guard_bumper_5in_abs")
	details._guard_selector.select(index)
	details._on_guard_selected(index)
	await _settle(tree)
	out.append(_a_fitted_guard_reaches_the_row(shell))
	out.append(_the_page_shows_the_rows_numbers(shell, &"guards"))
	out.append(TestResult.new("propulsion dock: a fitted guard is drawn as a ring on the page",
		shell.propulsion_diagram().ring_outer_mm > 0.0, "%.1f" % shell.propulsion_diagram().ring_outer_mm))
	details._guard_selector.select(0)
	details._on_guard_selected(0)
	await _settle(tree)

	# SM3 — Soft mounts: the stack in side elevation beside the Motor panel's mount half.
	shell.open_row(&"soft_mounts")
	await _settle(tree)
	var motor := shell.lab.motor_details
	var profile := shell.mount_profile()
	out.append(TestResult.new("propulsion dock: the Soft mounts page draws the motor stack beside its sheet",
		shell.item_page_view().body == profile and profile.is_visible_in_tree()
			and not profile.parts().is_empty() and profile.size.x >= 200.0
			and shell._inspector.is_visible_in_tree(),
		"body %s, parts %d, size %s" % [shell.item_page_view().body, profile.parts().size(), profile.size]))
	out.append(TestResult.new("propulsion dock: the Soft mounts sheet is the mount half, no motor rows",
		motor.sheet_parts()["mount"] and not motor.sheet_parts()["rows"], str(motor.sheet_parts())))
	# The overlays are hidden while a page covers the stage, so the refill every visible-tray path
	# ends in is driven directly: what is under test is WHICH build it reads (the assembled one).
	var vibration: VibrationOverlay = shell._overlays["vibration"]
	shell._refill_thrust_overlay()
	var tier_before := vibration.tier
	# PICK A MOUNT, the way the builder does: the selector's own handler.
	var m_index := motor._mount_ids.find("mount_grommet_70a_firm")
	motor._mount_selector.select(m_index)
	motor._on_mount_selected(m_index)
	await _settle(tree)
	shell._refill_thrust_overlay()
	out.append(TestResult.new("propulsion dock: a picked mount reaches the row's line 2",
		str(_row(shell, &"soft_mounts").get("choice", "")) == "70A silicone", _row(shell, &"soft_mounts").get("choice", "")))
	out.append(TestResult.new("propulsion dock: a picked mount moves the vibration caption's tier",
		tier_before == "no_mount" and vibration.tier == "computed",
		"%s -> %s" % [tier_before, vibration.tier]))
	out.append(TestResult.new("propulsion dock: a picked mount is drawn as a pad in the stack",
		profile.soft_mount_m > 0.0 and is_finite(profile.mount_f_n_hz),
		"pad %.4f m, f_n %s" % [profile.soft_mount_m, profile.mount_f_n_hz]))
	out.append(_the_page_shows_the_rows_numbers(shell, &"soft_mounts"))
	motor._mount_selector.select(0)
	motor._on_mount_selected(0)
	await _settle(tree)

	shell.back_to_drone()
	await _settle(tree)
	out.append(TestResult.new("propulsion dock: Back puts the whole Motor panel back",
		motor.sheet_parts()["mount"] and motor.sheet_parts()["rows"], str(motor.sheet_parts())))
	out.append(TestResult.new("propulsion dock: Back puts the whole Prop panel back",
		details.sheet_parts()["guard"] == true and details.sheet_parts()["rows"] == true, ""))
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
## they span it — no narrow panel in an empty field (the Motor page before this slice).
static func _the_page_is_a_drawing_beside_its_sheet(shell: GlassShell, name: String,
		mode: String) -> TestResult:
	var view := shell.item_page()
	var drawing := view.get_global_rect()
	var sheet := shell._inspector.get_global_rect()
	var list := shell.section_list().get_global_rect()
	var stage := shell.stage_rect()
	var body := shell.item_page_view().body
	var ok := view.is_visible_in_tree() and shell._inspector.is_visible_in_tree() \
		and body == shell.propulsion_diagram() and shell.propulsion_diagram().mode == mode \
		and body.is_visible_in_tree() and body.size.x >= 300.0 and body.size.y >= 240.0 \
		and drawing.end.x <= sheet.position.x and sheet.end.x <= list.position.x \
		and drawing.position.x - stage.position.x <= GlassShell.CLUSTER_MARGIN + 1.0 \
		and list.position.x - sheet.end.x <= GlassShell.CLUSTER_MARGIN + 1.0
	return TestResult.new("propulsion dock: the %s page is a %s drawing beside its sheet, across the stage"
		% [name, mode], ok, "drawing %s, body %s, sheet %s, list %s, mode %s" % [drawing,
		body.size if body != null else Vector2.ZERO, sheet, list, shell.propulsion_diagram().mode])


static func _the_page_lists_only_its_own_warnings(shell: GlassShell, id: StringName) -> TestResult:
	var row := _row(shell, id)
	var owned: Array = row.get("warnings", [])
	var view := shell.item_page_view()
	var ok := view.warning_count() == owned.size()
	for i in owned.size():
		ok = ok and view.short_text(i).ends_with((owned[i] as BuildWarning).short) \
			and not view.why_visible(i)
	return TestResult.new("propulsion dock: the %s page lists the row's own %d warning(s), Why? closed"
		% [row.get("name"), owned.size()], ok, "view %d, row %d" % [view.warning_count(), owned.size()])


static func _the_page_shows_the_rows_numbers(shell: GlassShell, id: StringName) -> TestResult:
	var want := SectionRows.page_numbers(id, shell.lab.build_with_open_harness())
	var view := shell.item_page_view()
	var ok := want.size() == 2
	for i in want.size():
		ok = ok and view.number_text(i) == "%s %s" % [want[i][0], want[i][1]]
	return TestResult.new("propulsion dock: the %s page shows its two numbers" % id, ok,
		"'%s' / '%s' want %s" % [view.number_text(0), view.number_text(1), want])


static func _a_button_is_on_screen(shell: GlassShell, panel: Control, text: String) -> TestResult:
	var found: Button = null
	for child in panel.find_children("*", "Button", true, false):
		if (child as Button).text == text:
			found = child
	var rect := found.get_global_rect() if found != null else Rect2()
	var ok := found != null and found.is_visible_in_tree() and not found.disabled \
		and shell.get_global_rect().encloses(rect)
	return TestResult.new("propulsion dock: '%s' is on screen on its page" % text, ok, str(rect))


static func _a_fitted_guard_reaches_the_row(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"guards")
	var build := shell.lab.build_with_open_harness()
	var want := "+%d g · roll inertia +%d%%" % [roundi(PropulsionFigures.guard_added_g(build)),
		roundi(PropulsionFigures.guard_roll_inertia_fraction(build) * 100.0)]
	return TestResult.new("propulsion dock: fitting a guard puts its mass and roll inertia on the row",
		row.get("choice") != "none" and row.get("number") == want,
		"choice '%s' number '%s' want '%s'" % [row.get("choice"), row.get("number"), want])
