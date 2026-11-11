class_name TestPrintTab
extends RefCounted
## M10 (MERGE_TRACKER): the Printed room is the Print tab of the Frame, Camera, Antenna, Battery and Guard
## sheets, editing THIS design.
##   - Camera sheet has Print and shows only the camera mount's page.
##   - A clearance edit reaches the session's printing and the Build.
##   - Export writes a closed STL (StlWriter refuses an open one) and notes a print record in the design.
##   - Turning the camera up afterwards makes the camera mount DIFFER from what was printed; Keep makes the
##     finding go; Reprint writes a new record and the finding goes too.
##   - Records and settings ride in the design file.
## MUTATION: make `PrintTab.export_part` skip `add_print_record` and the record/divergence checks fail.


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var dir := "user://test_print_tab"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	var s := ds.session
	for c in ["frame", "camera", "antenna", "battery", "guard"]:
		out.append(TestResult.new("%s sheet has a Print tab" % c,
			PartSheetTabs.for_category(c).any(func(t): return t["id"] == "print"), ""))
	ds.open_part_sheet("camera", "print")
	var tab := ds.part_sheet.tab("print") as PrintTab
	out.append(TestResult.new("the camera Print tab shows the camera mount only",
		tab != null and tab.panel.shown_parts() == ["camera_mount"], str(tab.panel.shown_parts()) if tab != null else "none"))
	if tab == null:
		ds.free()
		return out
	tab.export_dir = dir
	var before := PrintSettings.clearance_mm(s.build(catalog).printing)
	tab.panel.clearance_edited.emit(before + 0.1)
	out.append(TestResult.new("a clearance edit reaches the session and the Build",
		absf(PrintSettings.clearance_mm(s.printing()) - (before + 0.1)) < 0.001
		and absf(PrintSettings.clearance_mm(s.build(catalog).printing) - (before + 0.1)) < 0.001, str(s.printing())))
	tab.panel.export_button("camera_mount").pressed.emit()
	var recs := s.print_records()
	out.append(TestResult.new("Export notes a print record", recs.size() == 1 and String(recs[0].get("part", "")) == "camera_mount",
		tab.last_message))
	out.append(TestResult.new("and the STL is on disk", recs.size() == 1 and FileAccess.file_exists(String(recs[0].get("exported_to", ""))), ""))
	out.append(TestResult.new("nothing differs from what was just printed", s.print_divergence(catalog).is_empty(),
		str(s.print_divergence(catalog))))
	# Tilt the camera: the mount no longer matches the print.
	var tw := AssemblyTweaks.new()
	tw.set_mm(AssemblyTweaks.CAMERA_TILT, 45.0)
	s.set_tweaks(tw)
	var found := s.print_divergence(catalog)
	out.append(TestResult.new("turning the camera up makes the mount differ", found.size() == 1 and String(found[0]["part"]) == "camera_mount", str(found)))
	var back := DesignFile.from_dict(DesignFile.to_dict(s, "t"), catalog)
	out.append(TestResult.new("the design file carries records and settings", back.get("ok", false)
		and (back["session"] as DesignSession).print_records().size() == 1
		and not (back["session"] as DesignSession).printing().is_empty(), str(back.get("reason", ""))))
	tab.panel.divergence_button("camera_mount", "keep").pressed.emit()
	out.append(TestResult.new("Keep clears the finding", s.print_divergence(catalog).is_empty(), ""))
	s.set_tweaks(AssemblyTweaks.new())
	tw.set_mm(AssemblyTweaks.CAMERA_TILT, 20.0)
	s.set_tweaks(tw)
	found = s.print_divergence(catalog)
	out.append(TestResult.new("a different change finds it again", found.size() == 1, str(found)))
	tab.panel.divergence_button("camera_mount", "reprint").pressed.emit()
	out.append(TestResult.new("Reprint writes a second record and the finding goes", s.print_records().size() == 2 and s.print_divergence(catalog).is_empty(),
		"%d records" % s.print_records().size()))
	ds.free()
	return out
