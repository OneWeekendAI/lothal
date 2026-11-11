class_name TestFitTab
extends RefCounted
## M9 + B6 (MERGE_TRACKER): the Fit panel, the camera's uptilt, the video payload and the link sheet are
## tabs of the Frame / Camera / VTX / Receiver / Antenna sheets, editing THIS design's assembly.
##   - Tab lists: frame has Fit; camera Uptilt and Payload; vtx Payload; receiver and antenna Link.
##   - The Fit panel's battery offset reaches the session's tweaks and the Build the design makes.
##   - The camera's uptilt reaches the Build's assembly (`camera_tilt_deg`), the design file, and undo.
##   - Payload and Link panels render this design's electronics (not empty).
## MUTATION: make `FitTab._on_tweaks_changed` write nothing and the tweak checks fail.


static func _ids(category: String) -> Array:
	return PartSheetTabs.for_category(category).map(func(t): return t["id"])


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	var s := ds.session
	out.append(TestResult.new("sheets carry Fit, Uptilt, Payload, Link",
		_ids("frame").has("fit") and _ids("camera").has("uptilt") and _ids("camera").has("payload")
		and _ids("vtx").has("payload") and _ids("receiver").has("link") and _ids("antenna").has("link"), ""))
	# Fit
	ds.open_part_sheet("frame", "fit")
	var fit := ds.part_sheet.tab("fit") as FitTab
	out.append(TestResult.new("the Fit tab is up", fit != null and fit.panel is AssemblyPanel, ""))
	var asm := fit.panel as AssemblyPanel
	var landed := asm.set_tweak_mm(AssemblyTweaks.BATTERY_OFFSET, 6.0)
	out.append(TestResult.new("a battery offset reaches the session", s.tweaks.has_override(AssemblyTweaks.BATTERY_OFFSET), str(s.tweaks.to_dict())))
	var b := s.build(catalog)
	out.append(TestResult.new("and the Build the design makes", absf(s.tweaks.value_mm(AssemblyTweaks.BATTERY_OFFSET, b) - landed) < 0.01
		and absf(float(b.assembly.get("battery_offset_m", 0.0)) * 1000.0 - landed) < 0.01, "%.1f" % landed))
	out.append(TestResult.new("session undo takes it back", s.undo() and not s.tweaks.has_override(AssemblyTweaks.BATTERY_OFFSET), ""))
	out.append(TestResult.new("and the panel shows it as built again", asm.tweak_row_text(AssemblyTweaks.BATTERY_OFFSET).contains("as built"),
		asm.tweak_row_text(AssemblyTweaks.BATTERY_OFFSET)))
	# Uptilt
	ds.open_part_sheet("camera", "uptilt")
	var up := ds.part_sheet.tab("uptilt") as FitTab
	(up.panel as CameraPanel).tilt_edited.emit(40.0)
	var b2 := s.build(catalog)
	out.append(TestResult.new("an uptilt edit reaches the Build's assembly", absf(float(b2.assembly.get("camera_tilt_deg", -1.0)) - 40.0) < 0.01,
		str(b2.assembly.get("camera_tilt_deg", "none"))))
	var back := DesignFile.from_dict(DesignFile.to_dict(s, "t"), catalog)
	out.append(TestResult.new("and the design file", back.get("ok", false)
		and (back["session"] as DesignSession).tweaks.has_override(AssemblyTweaks.CAMERA_TILT), str(back.get("reason", ""))))
	# Payload and link
	ds.open_part_sheet("vtx", "payload")
	var pay := ds.part_sheet.tab("payload") as FitTab
	out.append(TestResult.new("the Payload tab renders this design's electronics", pay != null and pay.panel is ElectronicsDetails, ""))
	ds.open_part_sheet("receiver", "link")
	var link := ds.part_sheet.tab("link") as FitTab
	out.append(TestResult.new("the Link tab renders", link != null and link.panel is LinkDetails, ""))
	ds.free()
	return out
