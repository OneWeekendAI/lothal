class_name TestHarnessTab
extends RefCounted
## M7 (MERGE_TRACKER): the Power room's harness designer is the ESC sheet's Harness tab, editing the
## DESIGN's harness.
##   - The ESC sheet has a Harness tab holding the room, on this design's aircraft.
##   - A gauge edit reaches the session (`harness_overrides`), the aircraft the design builds (lead
##     mass moves), the undo history, and the design file (round-trip).
##   - The battery offset slider writes the session's assembly tweak, which the built aircraft carries.
## MUTATION: disconnect `document_changed` in HarnessTab and the session checks fail.


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	out.append(TestResult.new("the ESC sheet has a Harness tab", ds.open_part_sheet("esc", "harness"), ""))
	var tab := ds.part_sheet.tab("harness") as HarnessTab if ds.part_sheet != null else null
	out.append(TestResult.new("the room is up on this design's aircraft", tab != null and tab.room.build != null, ""))
	if tab == null or tab.room.build == null:
		ds.free()
		return out
	var session := ds.session
	var before := session.build(catalog).harness.total_mass_g(session.build(catalog))
	out.append(TestResult.new("a design starts with an as-built harness", session.harness_overrides.is_empty(), ""))
	tab.room._on_value_edited(Harness.MAIN_LEAD_LENGTH_MM, 400.0)
	out.append(TestResult.new("a lead edit reaches the session", session.harness_overrides.get(Harness.MAIN_LEAD_LENGTH_MM, 0.0) == 400.0,
		str(session.harness_overrides)))
	var b := session.build(catalog)
	var after := b.harness.total_mass_g(b)
	out.append(TestResult.new("and the aircraft the design builds is heavier", after > before + 1.0, "%.1f -> %.1f g" % [before, after]))
	# Design file round trip.
	var d := DesignFile.to_dict(session, "t")
	var back := DesignFile.from_dict(d, catalog)
	out.append(TestResult.new("the design file carries the harness",
		back.get("ok", false) and (back["session"] as DesignSession).harness_overrides == session.harness_overrides, str(back.get("reason", ""))))
	# Undo: the session's history steps back over the edit.
	out.append(TestResult.new("the session undoes the edit", session.undo() and session.harness_overrides.is_empty(), ""))
	# Battery offset.
	tab.room._offset_slider.value = 7.0
	tab.room._on_offset_moved(7.0)
	out.append(TestResult.new("the offset slider writes the session's tweak",
		session.tweaks.has_override(AssemblyTweaks.BATTERY_OFFSET), str(session.tweaks.to_dict())))
	var rebuilt := session.build(catalog)
	out.append(TestResult.new("the built aircraft carries it", absf(session.tweaks.value_mm(AssemblyTweaks.BATTERY_OFFSET, rebuilt) - 7.0) < 0.5, ""))
	ds.free()
	return out
