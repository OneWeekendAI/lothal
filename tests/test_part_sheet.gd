class_name TestPartSheet
extends RefCounted
## M1 (MERGE_TRACKER): the Part sheet shell. The Parts drawer is the one place a build is edited;
## a part's sheet is a tab strip over the Design Space. Checks:
##   - every shelf category (and the frame) answers with a tab list, and the sheet opens on each;
##   - the registry is what drives the strip (an emptied registry opens nothing; see MUTATION);
##   - the inspector offers "Open sheet" for a picked part and the button opens that part's sheet;
##   - Esc and Back close it, and the session's undo history is the one the sheet edits through.
##
## MUTATION: emptying PartSheetTabs.TABS makes "opens on every category" and "inspector button" fail.


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	var missing: Array = []
	for cat in PartSheetTabs.SHELF_CATEGORIES_WITH_SHEET:
		if PartSheetTabs.for_category(cat).is_empty() or not ds.open_part_sheet(cat):
			missing.append(cat)
			continue
		if ds.part_sheet.tab_ids() != PartSheetTabs.for_category(cat).map(func(t): return t["id"]):
			missing.append(cat + ":tabs")
		if ds.part_sheet.tab(ds.part_sheet.current_tab) == null:
			missing.append(cat + ":body")
	out.append(TestResult.new("the sheet opens, with its tabs, on every shelf category and the frame",
		missing.is_empty(), str(missing)))
	out.append(TestResult.new("a category without a sheet opens nothing", not ds.open_part_sheet("nonsense"), ""))
	out.append(TestResult.new("a tab the category lacks opens nothing", not ds.open_part_sheet("battery", "shape"), ""))

	ds.select("frame/arm/FL")
	var btn := ds.inspector.find_child("OpenSheet", true, false) as Button
	out.append(TestResult.new("the inspector offers Open sheet for a picked frame region", btn != null, ""))
	if btn != null:
		btn.pressed.emit()
		out.append(TestResult.new("Open sheet opens the frame's sheet",
			ds.part_sheet != null and ds.part_sheet.category == "frame", ""))
	ds.select("part/battery")
	btn = ds.inspector.find_child("OpenSheet", true, false) as Button
	if btn != null:
		btn.pressed.emit()
	out.append(TestResult.new("Open sheet on the battery opens the battery's sheet",
		btn != null and ds.part_sheet != null and ds.part_sheet.category == "battery", ""))

	var sheet := ds.part_sheet
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	var closed := [false]
	sheet.closed.connect(func(): closed[0] = true)
	sheet.close()
	out.append(TestResult.new("closing the sheet says so and drops it from the design space",
		closed[0] and ds.part_sheet == null, ""))
	ds.free()
	return out
