class_name TestProjectMenu
extends RefCounted
## The drone menu and the chip it drops out of — §5's "the project name IS the menu".
##
## Five of the seven entries work; the two exports wait on features that are not built. The tests are
## mostly about that split being TRUE rather than merely intended. Three are written to fail in the
## specific way this feature is likely to rot:
##
## **1. Half-built entries must be unreachable, not just unimplemented.** The failure this guards
## is somebody adding `waiting_on` to an entry and forgetting to disable it — a menu item that
## looks live, fires, and does nothing. So the check walks EVERY entry and asserts the pairing in
## both directions: waiting means disabled with a tooltip, live means enabled. It is a property of
## the whole table, so it keeps holding as entries are turned on one by one.
##
## **2. A refused rename must leave the dialog up.** AcceptDialog hides itself before `confirmed`
## reaches the handler, so the natural implementation closes the form and silently keeps the old
## name. The check asserts `visible` after a blank submit — the one assertion that distinguishes
## "refused and said so" from "refused and vanished".
##
## **3. The state line must not be able to claim a save.** "saved 4s ago" is the phrase the whole
## chip exists to eventually show, and it would be a lie today. The check is not that the label
## happens to read the unsaved text; it is that the SAVED text is unreachable without a path.

static func run() -> Array:
	var results: Array = []
	results.append_array(_test_the_table_is_the_feature_list())
	results.append_array(_test_waiting_entries_are_unreachable())
	results.append_array(_test_the_menu_has_a_recent_section())
	results.append_array(_test_which_entries_are_live())
	results.append_array(_test_a_refused_rename_does_not_vanish())
	results.append_array(_test_the_chip_cannot_claim_to_be_saved())
	results.append_array(_test_relative_time_reads_like_a_person_wrote_it())
	return results


static func _test_the_table_is_the_feature_list() -> Array:
	var results: Array = []
	var ids := ProjectMenu.entry_ids()
	var unique: Dictionary = {}
	for id in ids:
		unique[id] = true

	results.append(TestResult.new(
		"every entry in the menu has a distinct id",
		ids.size() == unique.size() and ids.size() == 7,
		"%d entries: %s" % [ids.size(), ids]
	))

	# The mockup's own list. Named here so that dropping one silently is a failing test rather than
	# a screenshot nobody compares against.
	var expected := ["new", "open", "duplicate", "rename", "export_build_sheet",
		"export_printed", "reveal"]
	results.append(TestResult.new(
		"and the menu still offers everything the design put in it",
		ids == expected,
		"%s" % [ids]
	))
	return results


static func _test_waiting_entries_are_unreachable() -> Array:
	var menu := ProjectMenu.new()
	var wrong: Array = []
	var index := 0
	for entry in ProjectMenu.ENTRIES:
		if bool((entry as Dictionary).get("separator", false)):
			index += 1
			continue
		var waiting := str((entry as Dictionary).get("waiting_on", ""))
		var disabled := menu.is_item_disabled(index)
		var tooltip := menu.get_item_tooltip(index)
		# Both directions. An entry that waits must be disabled AND explain itself; an entry that
		# is live must be clickable. Either half alone passes on a menu that disables everything.
		if waiting == "" and disabled:
			wrong.append("%s is live but disabled" % entry["id"])
		if waiting != "" and not disabled:
			wrong.append("%s waits on something but is clickable" % entry["id"])
		if waiting != "" and tooltip.strip_edges() == "":
			wrong.append("%s is greyed and does not say why" % entry["id"])
		index += 1

	var results: Array = [TestResult.new(
		"a greyed entry is disabled and says what it waits on; a live one is clickable",
		wrong.is_empty(),
		"problems: %s" % [wrong]
	)]

	# The accelerators are drawn even on disabled entries, so the shortcuts read correctly from the
	# first day rather than appearing when the feature does.
	results.append(TestResult.new(
		"the shortcuts the design promises are shown, even while greyed",
		menu.get_item_accelerator(0) == (KEY_MASK_META | KEY_N)
			and menu.get_item_accelerator(1) == (KEY_MASK_META | KEY_O)
			and menu.get_item_accelerator(2) == (KEY_MASK_META | KEY_D),
		"new=%d open=%d duplicate=%d" % [menu.get_item_accelerator(0),
			menu.get_item_accelerator(1), menu.get_item_accelerator(2)]
	))
	menu.free()
	return results


static func _test_the_menu_has_a_recent_section() -> Array:
	var menu := ProjectMenu.new()
	var found_empty := false
	var disabled := false
	for i in menu.item_count:
		if menu.get_item_text(i) == ProjectMenu.RECENT_EMPTY:
			found_empty = true
			disabled = menu.is_item_disabled(i)
	menu.free()
	return [TestResult.new(
		"the recent section exists and says it is empty rather than being empty",
		found_empty and disabled,
		"found=%s disabled=%s" % [found_empty, disabled]
	)]


## What is live, and what is not, stated once.
##
## This assertion is the one that CHANGES as the app grows, and that is deliberate: turning an
## entry on should require saying so here, out loud, next to the entries that already work. The
## durable invariant — waiting means disabled, live means clickable — is checked separately above
## and holds no matter which entries are on.
static func _test_which_entries_are_live() -> Array:
	var results: Array = []
	results.append(TestResult.new(
		"everything the container made possible is live; the two exports are not",
		ProjectMenu.is_live("new")
			and ProjectMenu.is_live("open")
			and ProjectMenu.is_live("duplicate")
			and ProjectMenu.is_live("rename")
			and ProjectMenu.is_live("reveal")
			and not ProjectMenu.is_live("export_build_sheet")
			and not ProjectMenu.is_live("export_printed"),
		"new=%s open=%s duplicate=%s reveal=%s sheet=%s printed=%s" % [
			ProjectMenu.is_live("new"), ProjectMenu.is_live("open"),
			ProjectMenu.is_live("duplicate"), ProjectMenu.is_live("reveal"),
			ProjectMenu.is_live("export_build_sheet"), ProjectMenu.is_live("export_printed")]
	))

	var chip := ProjectChip.new()
	var heard: Array = []
	chip.project_renamed.connect(func(n: String) -> void: heard.append(n))
	var problem := chip.submit_rename('  Weekend 5"  ')
	results.append(TestResult.new(
		"renaming trims, applies and announces itself",
		problem == "" and chip.project.name == 'Weekend 5"' and heard == ['Weekend 5"'],
		"problem='%s' name='%s' heard=%s" % [problem, chip.project.name, heard]
	))
	chip.free()
	return results


static func _test_a_refused_rename_does_not_vanish() -> Array:
	var results: Array = []
	var chip := ProjectChip.new()
	chip.submit_rename("Named once")

	var problem := chip.submit_rename("   ")
	results.append(TestResult.new(
		"a blank name is refused, and the old one is left alone",
		problem != "" and chip.project.name == "Named once",
		"problem='%s' name='%s'" % [problem, chip.project.name]
	))

	# The dialog half, which is where the real bug lives: AcceptDialog closes itself on OK before
	# the handler runs, so a refusal that does not re-show leaves the builder with no form, no
	# message, and the old name.
	var tree := SceneTree.new()
	var root := Control.new()
	var housed := ProjectChip.new()
	root.add_child(housed)
	housed.begin_rename()
	housed._rename_field.text = "   "
	housed._on_rename_confirmed()
	results.append(TestResult.new(
		"a refused rename puts the form straight back up instead of closing on nothing",
		housed._rename_dialog.visible and housed._rename_problem.visible,
		"dialog visible=%s problem visible=%s" % [housed._rename_dialog.visible,
			housed._rename_problem.visible]
	))
	root.free()
	tree.free()
	chip.free()
	return results


static func _test_the_chip_cannot_claim_to_be_saved() -> Array:
	var results: Array = []
	var chip := ProjectChip.new()
	results.append(TestResult.new(
		"with nowhere to write it, the chip says exactly that",
		chip.state_text() == "not saved anywhere yet",
		"'%s'" % chip.state_text()
	))

	# And the other half: the saved wording is not dead code that will be wrong when it arrives.
	# Given a path it appears, which is what makes the line above a consequence rather than a
	# hardcoded string.
	chip.saved_path = "user://builds/whatever.lothal"
	chip.project.updated_at = Time.get_datetime_string_from_system(true) + "Z"
	results.append(TestResult.new(
		"and once there is a path, it reports when it was written",
		chip.state_text().begins_with("saved "),
		"'%s'" % chip.state_text()
	))
	chip.free()
	return results


static func _test_relative_time_reads_like_a_person_wrote_it() -> Array:
	var cases := [
		[0, "just now"], [1, "just now"], [4, "4s ago"], [59, "59s ago"],
		[60, "1m ago"], [3599, "59m ago"], [3600, "1h ago"], [86399, "23h ago"],
		[86400, "yesterday"], [172800, "2 days ago"], [604800, "last week"],
	]
	var wrong: Array = []
	for case in cases:
		var got := ProjectChip.relative_time(int(case[0]))
		if got != String(case[1]):
			wrong.append("%ds -> '%s', wanted '%s'" % [case[0], got, case[1]])
	return [TestResult.new(
		"the age of a save is worded the way the design writes it, at every boundary",
		wrong.is_empty(),
		"problems: %s" % [wrong]
	)]
