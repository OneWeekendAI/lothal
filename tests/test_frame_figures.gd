class_name TestFrameFigures
extends RefCounted
## M4 (MERGE_TRACKER): the frame sheet's reading tabs (Numbers, Arms, Hardware, Layout) carry the Setup
## pages' figures. Checked three ways: each tab's text equals what the same panel class says for the
## same document built on its own (the Setup page's text), the figures are not blank, and a frame
## edit made through the design moves them at once (the tab is live, not a snapshot).
##
## MUTATION: drop `ds.session.changed.connect(refresh)` in FrameFiguresTab and "an edit moves the
## figures" fails; render a different document than the design's and the equality checks fail.


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	var doc := ds.session.frame_document()
	for tab_id in FrameFiguresTab.KINDS:
		var ok := ds.open_part_sheet("frame", tab_id)
		var tab := ds.part_sheet.tab(tab_id) as FrameFiguresTab if ok else null
		out.append(TestResult.new("the frame sheet has a %s tab" % tab_id, tab != null, ""))
		if tab == null:
			continue
		for k in tab.panels:
			var live: SpecPanel = tab.panels[k]
			var fresh: SpecPanel = _fresh(k)
			if k == "straps":
				var build := ds.session.build(catalog)
				fresh.render_straps(doc, StrapsPads.figures(build, doc))
			else:
				fresh.render(doc)
			var diffs: Array = []
			var blank := 0
			for row in _rows(k):
				var key := String(row["key"])
				if live.row_text(key) != fresh.row_text(key):
					diffs.append(key)
				if live.row_text(key) in ["", "—"]:
					blank += 1
			out.append(TestResult.new("%s tab: every %s row reads the same as the Setup page's" % [tab_id, k],
				diffs.is_empty(), str(diffs)))
			out.append(TestResult.new("%s tab: the %s figures are not all blank" % [tab_id, k],
				blank < _rows(k).size(), "%d of %d blank" % [blank, _rows(k).size()]))
	# Live: thicken a plate through the design; the mass from geometry moves.
	ds.open_part_sheet("frame", "numbers")
	var numbers := ds.part_sheet.tab("numbers") as FrameFiguresTab
	var structure := numbers.panels["structure"] as StructureDetails
	var before := structure.row_text("computed_mass")
	var verdict := ds.session.set_plate_thickness(0, 4.0 if AirframeDocument.plate_thickness_mm(doc.plates[0]) != 4.0 else 3.0)
	out.append(TestResult.new("the edit is accepted", bool(verdict.get("ok", false)), str(verdict)))
	out.append(TestResult.new("an edit moves the figures on the open tab", structure.row_text("computed_mass") != before,
		"%s -> %s" % [before, structure.row_text("computed_mass")]))
	ds.free()
	return out


static func _fresh(kind: String) -> SpecPanel:
	match kind:
		"structure": return StructureDetails.new()
		"arms": return ArmsDetails.new()
		"fasteners": return FastenersDetails.new()
		"straps": return StrapsDetails.new()
	return LayoutDetails.new()


static func _rows(kind: String) -> Array:
	match kind:
		"structure": return StructureDetails.SPEC_ROWS
		"arms": return ArmsDetails.SPEC_ROWS
		"fasteners": return FastenersDetails.SPEC_ROWS
		"straps": return StrapsDetails.SPEC_ROWS
	return LayoutDetails.SPEC_ROWS
