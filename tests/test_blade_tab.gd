class_name TestBladeTab
extends RefCounted
## M5 (MERGE_TRACKER): the blade designer and the blades of the old Propulsion room are reachable from
## the Propeller sheet. The designer already carries the room's planform, section and mount-stack
## views; this checks the door and the one thing only the old room held, the BladeLibrary drawings.
##   - Open the blade designer from the sheet opens the designer.
##   - A drawn blade saved in BladeLibrary is listed, and opening it puts its planform in the designer
##     unchanged (chord table equal), as a new prop (no id).
##   - A station edit made there is recorded and undone (the old room's BladeHistory parity).
## MUTATION: drop the `blade_path` branch in open_prop_designer and the chord-equality check fails.


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	var prop: Dictionary = catalog.get_part(String(ds.session.selection["propeller"]))
	var drawn := PropellerDocument.from_catalog_prop(prop)
	drawn.id = "test_blade_%d" % Time.get_ticks_usec()
	drawn.name = "Test blade"
	drawn.chord = PlanformEdits.insert_station(drawn.chord, 0.33, drawn)
	drawn.chord_is_assumed = false
	out.append(TestResult.new("a drawn blade saves to the library", BladeLibrary.save(drawn), ""))
	out.append(TestResult.new("the propeller sheet has a Blade tab", ds.open_part_sheet("propeller", "blade"), ""))
	var tab := ds.part_sheet.tab("blade") as PropBladeTab
	out.append(TestResult.new("the drawn blade is listed", tab != null and tab.blade_buttons.has(drawn.id),
		str(tab.blade_buttons.keys() if tab != null else [])))
	if tab == null or not tab.blade_buttons.has(drawn.id):
		return out
	(tab.blade_buttons[drawn.id] as Button).pressed.emit()
	var d := ds.prop_designer
	out.append(TestResult.new("opening it opens the designer and closes the sheet", d != null and ds.part_sheet == null, ""))
	if d == null:
		return out
	out.append(TestResult.new("the drawn planform arrives unchanged, as a new prop",
		d.doc.chord == drawn.chord and d.doc.id == "" and not d.doc.chord_is_assumed,
		"%d stations" % d.doc.chord.size()))
	var stations := d.doc.chord.size()
	d.set_caret(0.62)
	d.add_chord_station()
	out.append(TestResult.new("adding a station is recorded", d.doc.chord.size() > stations, "%d -> %d" % [stations, d.doc.chord.size()]))
	d.undo()
	out.append(TestResult.new("and undone", d.doc.chord == drawn.chord, ""))
	BladeLibrary.delete(drawn.id)
	ds.free()
	var plain := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	plain.size = Vector2(1280, 720)
	plain.open_part_sheet("propeller", "blade")
	(plain.part_sheet.tab("blade") as PropBladeTab).designer_button.pressed.emit()
	out.append(TestResult.new("Open the blade designer opens it on this drone's prop", plain.prop_designer != null, ""))
	plain.free()
	return out
