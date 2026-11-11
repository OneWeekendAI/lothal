class_name TestFrameShape
extends RefCounted
## M2 (MERGE_TRACKER): the frame sheet's Shape tab, the Airframe room restored inside the Parts drawer.
## An edit in the plan editor reaches the design: the aircraft's mass moves, Undo takes it back, and
## a frame that is not the fitted one (a layout, or a class without a drawing) does not overwrite it.
##
## MUTATION: make `DesignSession.adopt_frame_document` return false, or drop the `document_changed`
## connection in FrameShapeTab: "an added plate moves the aircraft's weight" fails.


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	out.append(TestResult.new("the frame sheet opens on Shape", ds.open_part_sheet("frame", "shape")
		and ds.part_sheet.current_tab == "shape", ""))
	var shape := ds.part_sheet.tab("shape") as FrameShapeTab
	out.append(TestResult.new("the room is the real one: plan editor, layout shelf, controls, numbers",
		shape != null and shape.workbench.editor != null and shape.workbench.shelf != null
		and shape.workbench.controls != null and shape.workbench.numbers != null, ""))
	out.append(TestResult.new("on the 5\" the room edits the fitted frame (the seam is live)",
		shape.seam_live and shape.workbench.editor.document.plates.size() == ds.session.frame_document().plates.size(), ""))
	var before := float(ds.session.readouts(catalog).get("auw_g", 0.0))
	var plates_before := ds.session.frame_document().plates.size()
	shape.workbench._on_add_plate()
	var took := shape.flush()
	var after := float(ds.session.readouts(catalog).get("auw_g", 0.0))
	out.append(TestResult.new("an added plate reaches the design", took and ds.session.frame_document().plates.size() == plates_before + 1,
		"%d -> %d" % [plates_before, ds.session.frame_document().plates.size()]))
	out.append(TestResult.new("an added plate moves the aircraft's weight", after > before + 0.05, "%.2f -> %.2f g" % [before, after]))
	out.append(TestResult.new("the design's Undo takes the visit back", ds.session.can_undo() and ds.session.undo()
		and ds.session.frame_document().plates.size() == plates_before, ""))
	# A layout is another frame: it must not overwrite the fitted one.
	shape.workbench._on_layout_chosen("hex_v")
	var flown := ds.session.frame_document().plates.size()
	shape.workbench._on_add_plate()
	out.append(TestResult.new("a layout chosen in the room does not replace the fitted frame",
		not shape.seam_live and not shape.flush() and ds.session.frame_document().plates.size() == flown, ""))
	ds.free()

	var four := DesignSpace.new(DesignSession.default_for_class("four_inch"), catalog)
	four.size = Vector2(1280, 720)
	out.append(TestResult.new("a class with no frame drawing still gets the room, as a workbench",
		four.open_part_sheet("frame", "shape") and not (four.part_sheet.tab("shape") as FrameShapeTab).seam_live
		and (four.part_sheet.tab("shape") as FrameShapeTab).workbench.editor.document != null, ""))
	four.free()
	return out
