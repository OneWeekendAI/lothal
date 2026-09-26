class_name TestPrintRoom
extends RefCounted
## The Printed room stops being a stub — printed-room slice PR0
## (plans/2026-09-14-printed-room-plan.md, checks 1–7).
##
## The two checks that carry the slice are the PER-DRONE one and the no-guard fixture. "Per drone"
## is only distinguishable from "global" when two drones hold DIFFERENT values and both survive a
## switch away and back (plans-that-cannot-fail, case 5); a single drone reads the same under either
## design. And "the guard row follows the build" is only a check with a build that fits no guard.
##
## No `user://` file is written: a clearance edit is not an assembly tweak and saves nothing, and
## `apply_project` fits a project without writing its container.

const GUARD_ID := "guard_bumper_5in_abs"


static func run() -> Array:
	var results: Array = []
	results.append_array(_settings_are_pure_and_say_they_guess())
	results.append_array(_the_room_shows_its_panel())
	results.append_array(_clearance_is_per_drone())
	results.append(_an_edit_reaches_the_project())
	results.append_array(_the_guard_row_follows_the_build())
	results.append_array(_the_arm_guard_is_fitted_from_the_panel())
	results.append_array(_the_panel_scrolls_above_the_dock())
	return results


## The Print panel's content must scroll inside the inspector, which ends BOTTOM_KEEPOUT above the
## window's bottom edge so the Lab / Sim / Rooms dock never covers it. A panel that is not inside a
## ScrollContainer reports its whole content height as its MINIMUM height, and a Control's minimum
## beats its offsets: the inspector grows past the keepout and the rows run off the window. Measured
## as minimum heights, so no render is needed. The fixture fits a camera and an antenna, because a
## fresh project fits neither and its short panel would pass without scrolling at all.
static func _the_panel_scrolls_above_the_dock() -> Array:
	var results: Array = []
	var project := Project.create("Tall")
	project.parts["camera"] = "cam_micro_analog"
	project.parts["antenna"] = "antenna_rhcp_ufl"
	var shell := GlassShell.new()
	shell.apply_project(project)
	shell.select_system_by_name("Printed")
	var content := shell.lab.print_panel.content_height()
	for height: float in [720.0, 1837.0]:
		var room: float = height - shell._inspector.offset_top - GlassShell.BOTTOM_KEEPOUT
		# Measured on the panel, not the inspector: the shell moves the panels into the inspector in
		# _ready, which never runs outside a tree, so the inspector alone reports 0 px and passes.
		var wanted: float = shell.lab.print_panel.get_combined_minimum_size().y
		results.append(TestResult.new(
			"at %.0f px tall the Print panel fits between the top bar and the dock, and scrolls the rest" % height,
			wanted <= room,
			"panel needs %.0f px, %.0f px free above the dock; content is %.0f px" % [wanted, room, content]))
	results.append(TestResult.new(
		"the tall fixture really is taller than a 720 px window, so the check above can fail",
		content > 720.0 - shell._inspector.offset_top - GlassShell.BOTTOM_KEEPOUT,
		"content %.0f px" % content))
	shell.free()
	return results


## PR1 check 7. The row is on the panel for a frame that publishes its arm thickness, names its
## guesses, and its toggle moves the aircraft's weight by four sleeves — then back, on untick.
static func _the_arm_guard_is_fitted_from_the_panel() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Guarded"))
	var panel := shell.lab.print_panel
	var before := shell.lab.current_build().mass_properties.total_mass_kg
	var toggle := panel.fit_toggle(PrintedParts.ARM_GUARD)
	var note := panel.row_note(PrintedParts.ARM_GUARD)
	results.append(TestResult.new(
		"the default 5\" build lists arm guards, unfitted, with their guesses named on the row",
		toggle != null and not toggle.button_pressed and note.contains("(guess)") and note.contains("guesses"),
		"toggle %s, note \"%s\"" % [toggle, note]))

	panel.arm_guard_edited.emit(ArmGuard.FITTED, true)
	var build := shell.lab.current_build()
	var after := build.mass_properties.total_mass_kg
	var each := ArmGuard.mass_kg(ArmGuard.dimensions(build.frame, shell.lab.printing))
	var ticked := panel.fit_toggle(PrintedParts.ARM_GUARD)
	panel.arm_guard_edited.emit(ArmGuard.FITTED, false)
	var untouched := shell.lab.current_build().mass_properties.total_mass_kg
	results.append(TestResult.new(
		"ticking Fitted adds four sleeves to the weight and shows ticked; unticking takes them off",
		each > 0.0 and absf((after - before) - 4.0 * each) < 1e-12 and ticked != null
			and ticked.button_pressed and absf(untouched - before) < 1e-12,
		"%+.3f g for 4 × %.3f g; after untick %+.3f g" % [(after - before) * 1000.0, each * 1000.0,
			(untouched - before) * 1000.0]))
	shell.free()
	return results


static func _settings_are_pure_and_say_they_guess() -> Array:
	var results: Array = []
	var empty := {}
	results.append(TestResult.new(
		"an untouched drone prints at the default clearance and the row says it is a guess",
		is_equal_approx(PrintSettings.clearance_mm(empty), 0.20)
			and PrintSettings.clearance_row_text(empty) == "0.20 mm  (guess)",
		"reads \"%s\"" % PrintSettings.clearance_row_text(empty)))

	var edited := {}
	PrintSettings.set_clearance_mm(edited, 5.0)
	var clamped := PrintSettings.clearance_mm(edited)
	# What is STORED is clamped too, not only what is read: the project file is read by other things
	# (the print record, a later Lothal) that should not meet a 5 mm clearance nobody can set.
	var stored := float(edited[PrintSettings.CLEARANCE])
	var raw_read := PrintSettings.clearance_mm({PrintSettings.CLEARANCE: 5.0})
	PrintSettings.set_clearance_mm(edited, 0.35)
	results.append(TestResult.new(
		"a clearance clamps to 0.60 mm when stored and when read, and a set one reads without the guess marker",
		is_equal_approx(clamped, 0.60) and is_equal_approx(stored, 0.60) and is_equal_approx(raw_read, 0.60)
			and PrintSettings.clearance_row_text(edited) == "0.35 mm",
		"5.0 -> read %.2f, stored %.2f, a hand-written 5.0 reads %.2f; 0.35 reads \"%s\"" % [
			clamped, stored, raw_read, PrintSettings.clearance_row_text(edited)]))

	var bad := {PrintSettings.CLEARANCE: "loose"}
	results.append(TestResult.new(
		"an unreadable clearance reads as the default, still marked a guess",
		is_equal_approx(PrintSettings.clearance_mm(bad), 0.20)
			and PrintSettings.clearance_row_text(bad).contains("(guess)"),
		"reads \"%s\"" % PrintSettings.clearance_row_text(bad)))
	return results


static func _the_room_shows_its_panel() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.select_system_by_name("Printed")
	var shown := _shown_titles(shell.lab.panels)
	results.append(TestResult.new(
		"selecting Printed shows the Print panel and nothing else",
		shown == ["Print"], "showing %s" % [shown]))
	var hint := shell.lab.print_panel.hint_text()
	results.append(TestResult.new(
		"the clearance is called a guess where it is edited",
		hint.contains("guess") and shell.lab.print_panel.clearance_row_text().contains("(guess)"),
		"hint \"%s\"" % hint))
	results.append(TestResult.new(
		"the shell listens to the panel's Export buttons",
		shell.lab.print_panel.export_requested.get_connections().size() > 0,
		"%d connection(s)" % shell.lab.print_panel.export_requested.get_connections().size()))
	shell.free()
	return results


## A at 0.35, B untouched, A again. A global implementation reads 0.35 for B.
static func _clearance_is_per_drone() -> Array:
	var shell := GlassShell.new()
	var a := Project.create("Drone A")
	PrintSettings.set_clearance_mm(a.printing, 0.35)
	var b := Project.create("Drone B")

	shell.apply_project(a)
	var first := shell.lab.print_panel.clearance_row_text()
	shell.apply_project(b)
	var second := shell.lab.print_panel.clearance_row_text()
	shell.apply_project(a)
	var third := shell.lab.print_panel.clearance_row_text()
	shell.free()

	return [TestResult.new(
		"clearance is per drone: A 0.35, then B the default guess, then A 0.35 again",
		first == "0.35 mm" and second == "0.20 mm  (guess)" and third == "0.35 mm",
		"A \"%s\", B \"%s\", A \"%s\"" % [first, second, third])]


static func _an_edit_reaches_the_project() -> TestResult:
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Edited"))
	shell.lab.print_panel.clearance_edited.emit(0.45)
	var panel_text := shell.lab.print_panel.clearance_row_text()
	shell._sync_project()
	var reloaded := Project.from_dict(shell.container.project.to_dict())
	var stored := PrintSettings.clearance_mm(reloaded.printing)
	shell.free()
	return TestResult.new(
		"a clearance edit shows on the panel, reaches the project, and survives a round trip",
		panel_text == "0.45 mm" and is_equal_approx(stored, 0.45),
		"panel \"%s\", reloaded %.2f" % [panel_text, stored])


static func _the_guard_row_follows_the_build() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.lab.propeller_details.select_guard("")
	shell.lab.refresh_build()
	var bare := shell.lab.print_panel.export_button(PrintedParts.PROP_GUARD)
	results.append(TestResult.new(
		"a build with no guard lists no guard to print",
		bare == null, "button %s" % [bare]))

	var fitted := shell.lab.propeller_details.select_guard(GUARD_ID)
	shell.lab.refresh_build()
	var button := shell.lab.print_panel.export_button(PrintedParts.PROP_GUARD)
	var emitted: Array = []
	# The shell's own handler would write into user://exports; this check is about the panel's
	# wiring, so the shell's handler is detached first and the check listens in its place.
	for connection in shell.lab.print_panel.export_requested.get_connections():
		shell.lab.print_panel.export_requested.disconnect(connection["callable"])
	shell.lab.print_panel.export_requested.connect(func(id: String) -> void: emitted.append(id))
	if button != null:
		button.pressed.emit()
	results.append(TestResult.new(
		"fitting the 5\" bumper lists it with Export enabled, and pressing Export asks for the guard",
		fitted and button != null and not button.disabled and emitted.has(PrintedParts.PROP_GUARD),
		"fitted %s, button %s, emitted %s" % [fitted, button, emitted]))
	shell.free()
	return results


static func _shown_titles(tabs: TabContainer) -> Array:
	var shown: Array = []
	for i in tabs.get_tab_count():
		if not tabs.is_tab_hidden(i):
			shown.append(tabs.get_tab_title(i))
	return shown
