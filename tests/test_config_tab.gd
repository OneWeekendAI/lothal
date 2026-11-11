class_name TestConfigTab
extends RefCounted
## M8 + M11 (MERGE_TRACKER): Tune, Rates, Ports, Failsafe (and the board sheet, and the motor Spin) are tabs
## of the Flight controller / Motor sheets, editing THIS design's Config.
##   - FC sheet has Board, Tune, Rates, Ports, Failsafe; Motor sheet has Spin.
##   - A rates edit reaches the session's config, the Build the design makes, the DroneCore the sim
##     flies (`core.config`), the panel's own sentence, the design file, and is undone by session undo.
##   - Ports, Failsafe and Spin edits land the same way.
##   - A tune edit is written to PidTunes (the store the sim flies its gains from).
## MUTATION: make `ConfigTab._edit` write nothing and every config check fails.


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	var fc_ids: Array = PartSheetTabs.for_category("flight_controller").map(func(t): return t["id"])
	out.append(TestResult.new("the FC sheet has Board, Tune, Rates, Ports, Failsafe, Config sheet",
		fc_ids == ["sheet", "board", "tune", "rates", "ports", "failsafe", "configsheet"], str(fc_ids)))
	var s := ds.session
	# Rates
	ds.open_part_sheet("flight_controller", "rates")
	var rates := ds.part_sheet.tab("rates") as ConfigTab
	out.append(TestResult.new("the Rates tab is up", rates != null and rates.panel is ConfigRatesPanel, ""))
	var before_rate := RateSettings.intended_max_rate_deg_s(s.build(catalog).config)
	var want := before_rate + 100.0
	(rates.panel as ConfigRatesPanel).max_rate_edited.emit(want)
	var b := s.build(catalog)
	out.append(TestResult.new("a max-rate edit reaches the session's config", RateSettings.intended_max_rate_deg_s(s.config()) == want, str(s.config())))
	out.append(TestResult.new("and the Build the design makes", RateSettings.intended_max_rate_deg_s(b.config) == want, ""))
	var core := b.build_drone_core()
	out.append(TestResult.new("and the DroneCore the sim flies", RateSettings.intended_max_rate_deg_s(core.config) == want, ""))
	out.append(TestResult.new("and the panel says it", (rates.panel as ConfigRatesPanel)._rate_row.text.contains(str(roundi(want))),
		"want=%s " % want + (rates.panel as ConfigRatesPanel)._rate_row.text))
	var back := DesignFile.from_dict(DesignFile.to_dict(s, "t"), catalog)
	out.append(TestResult.new("and the design file", back.get("ok", false)
		and RateSettings.intended_max_rate_deg_s((back["session"] as DesignSession).config()) == want, str(back.get("reason", ""))))
	out.append(TestResult.new("session undo takes it back", s.undo() and RateSettings.intended_max_rate_deg_s(s.config()) == before_rate, ""))
	# Ports
	ds.open_part_sheet("flight_controller", "ports")
	var ports := ds.part_sheet.tab("ports") as ConfigTab
	(ports.panel as ConfigPortsPanel).uart_count_edited.emit(5)
	out.append(TestResult.new("a ports edit lands", PortBudget.typed_count(s.config()) == 5, str(s.config())))
	# Failsafe
	ds.open_part_sheet("flight_controller", "failsafe")
	var fs := ds.part_sheet.tab("failsafe") as ConfigTab
	var was := FailsafeSettings.bidir_dshot(s.config())
	(fs.panel as ConfigFailsafePanel).bidir_dshot_edited.emit(not was)
	out.append(TestResult.new("a bidirectional DShot edit lands in the Build", FailsafeSettings.bidir_dshot(s.build(catalog).config) == (not was), ""))
	# Spin
	ds.open_part_sheet("motor", "spin")
	var spin := ds.part_sheet.tab("spin") as ConfigTab
	(spin.panel as ConfigMotorsPanel).motor_spin_edited.emit("props_in")
	out.append(TestResult.new("a motor-spin edit lands", String(s.config().get("motor_spin", "")) == "props_in", str(s.config())))
	# Tune
	var tunes_path := "user://test_config_tab_tunes.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tunes_path))
	ds.part_sheet.close()
	ds.open_part_sheet("flight_controller", "tune")
	var tune := ds.part_sheet.tab("tune") as ConfigTab
	tune.tunes_path = tunes_path
	tune.refresh()
	var tp := tune.panel as TunePanel
	tp.set_field(0, "p", 61.0)
	tp.apply_axis(0)
	var store := PidTunes.load_from(tunes_path)
	out.append(TestResult.new("a tune edit is written to the gain store the sim reads", store.has_tune(s.build(catalog)), ""))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tunes_path))
	# M11: the config sheet. The preview is the file.
	ds.part_sheet.close()
	var sheet_dir := "user://test_config_tab_sheet"
	ds.open_part_sheet("flight_controller", "configsheet")
	var cs := ds.part_sheet.tab("configsheet") as ConfigTab
	cs.export_dir = sheet_dir
	var sp := cs.panel as ConfigSheetPanel
	out.append(TestResult.new("the config sheet shows this design's rate", sp.preview_text().contains("900") or sp.preview_text().contains("800"), ""))
	sp.export_button().pressed.emit()
	var files := DirAccess.get_files_at(ProjectSettings.globalize_path(sheet_dir))
	var text := FileAccess.get_file_as_string(sheet_dir.path_join(files[0])) if files.size() > 0 else ""
	out.append(TestResult.new("export writes a file", files.size() == 1, str(files)))
	# The file is the preview plus its one dated line (and the blank above it); nothing else differs.
	var lines := text.split("\n")
	var at := -1
	for i in lines.size():
		if lines[i].begins_with("Written: "):
			at = i
	if at > 0:
		lines.remove_at(at)
		lines.remove_at(at - 1)
	out.append(TestResult.new("and the preview is that file, character for character (bar its dated line)",
		at > 0 and "\n".join(lines) == sp.preview_text(), "%d vs %d chars" % [text.length(), sp.preview_text().length()]))
	out.append(TestResult.new("and the panel says where it went", sp.status_text().begins_with("Wrote "), sp.status_text()))
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sheet_dir.path_join(f)))
	ds.free()
	return out
