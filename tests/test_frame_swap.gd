class_name TestFrameSwap
extends RefCounted
## Swapping the frame from the catalog (PLAN item 8): what is offered, that the 3D shows THAT frame's own
## drawing, what edits do, and what is refused.
##
## Shipped data has ONE frame document per class (its own frame), so nothing is offered today and the
## swap checks register a second document (the 5" frame redrawn with thicker plates, under another catalog
## frame id) through `DesignSession.extra_documents`. Each check below was run against a mutant that
## breaks exactly its claim (see the item 8 report).

const CLASS_ID := "five_inch"
const OTHER := "frame_5in_race"      # a 5" catalog frame, 30.5 stack: fits the class and the fitted stack
const BAD_STACK := "frame_iflight_evoque_f5_v3"   # 5", but 20x20 stack: the 30.5 boards are refused
const BIG := "frame_10in_long_range"  # not a 5" frame
const THICK_MM := 6.0


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	out.append_array(_test_shipped(catalog))
	out.append_array(_test_shipped_readouts(catalog))
	_register(OTHER)
	_register(BAD_STACK)
	_register(BIG)
	out.append_array(_test_offerings(catalog))
	out.append_array(_test_swap_draws_that_frame(catalog))
	out.append_array(_test_edits_and_undo(catalog))
	out.append_array(_test_refusals(catalog))
	out.append_array(_test_persistence(catalog))
	DesignSession.extra_documents = {}
	out.append_array(_test_ui_cards(catalog))
	out.append_array(_test_ui_swap(catalog))
	out.append_array(_test_ui_confirm(catalog))
	DesignSession.extra_documents = {}
	return out


## Registers a document drawing `frame_id`: the 5" document with that id and every plate THICK_MM thick.
static func _register(frame_id: String) -> void:
	var d := AirframeDocument.load_from(DesignSession.FRAME_DOCUMENTS[CLASS_ID]).to_dictionary()
	d["id"] = frame_id
	for p in d["plates"]:
		p["thickness_mm"] = THICK_MM
	var path := "user://frame_swap_%s.json" % frame_id
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DesignSession.extra_documents[frame_id] = path


static func _text(doc: AirframeDocument) -> String:
	return JSON.stringify(doc.to_dictionary()) if doc != null else "null"


static func _session() -> DesignSession:
	return DesignSession.default_for_class(CLASS_ID)


static func _test_shipped(catalog: PartsCatalog) -> Array:
	var out: Array = []
	DesignSession.extra_documents = {}
	var offered := {}
	for cls in DesignSession.FRAME_DOCUMENTS:
		var ids: Array = []
		for o in FrameSwap.offerings(DesignSession.default_for_class(cls), catalog):
			ids.append(o["id"])
		offered[cls] = ids
	out.append(TestResult.new("shipped data: only the 3.5-inch and 4-inch classes can swap, each to the other's drawn frame",
		offered == {"toothpick": [], "sub250_35": ["frame_4in_freestyle"], "four_inch": ["frame_35in_freestyle"],
			"five_inch": [], "six_inch": [], "seven_lr": []}, str(offered)))
	var shipped := DesignSession.default_for_class("sub250_35")
	var r0 := shipped.swap_frame(catalog, "frame_4in_freestyle")
	var want := AirframeDocument.load_from(DesignSession.FRAME_DOCUMENTS["four_inch"])
	out.append(TestResult.new("shipped swap (3.5-inch class to the 4-inch frame) draws the 4-inch frame's own plates",
		r0["ok"] and _text(shipped.frame_document()) == _text(want) and shipped.frame_edit(catalog).is_empty(), str(r0)))
	var s := _session()
	out.append(TestResult.new("the 'why not' line for a class with a document says no other frame is drawn",
		FrameSwap.why_not(s, catalog).contains("No other frame"), FrameSwap.why_not(s, catalog)))
	var moulded := true
	for cls in ["tiny_whoop", "cinewhoop_3", "cinelifter", "x_class", "mapper"]:
		var m := DesignSession.default_for_class(cls)
		moulded = moulded and m != null and FrameSwap.offerings(m, catalog).is_empty() and FrameSwap.why_not(m, catalog).contains("moulded")
	out.append(TestResult.new("classes without a frame document offer nothing and say why", moulded, ""))
	var r := s.swap_frame(catalog, OTHER)
	out.append(TestResult.new("swapping to a frame with no drawing is refused and changes nothing",
		not r["ok"] and r["reason"].contains("no drawing") and not s.can_undo() and s.selection["frame"] == "frame_5in_freestyle", String(r["reason"])))
	return out


## The shipped 3.5-inch class swapped to the 4-inch frame: the physics follows the FITTED frame. Figures measured
## from the real catalog: frame 58 -> 70 g (+12.0), arm 88 -> 96 mm, and the four motor leads grow with the arm
## (0.7808 -> 0.9109 g each, +0.5205 g in all), so AUW rises by 12.5205 g (241.589 -> 254.110). Centre of mass
## drops 0.415 mm (8.434 -> 8.019), roll inertia rises (4.22e-4 -> 5.11e-4 kg m2).
static func _test_shipped_readouts(catalog: PartsCatalog) -> Array:
	var out: Array = []
	DesignSession.extra_documents = {}
	var s := DesignSession.default_for_class("sub250_35")
	var b0: Build = s.build(catalog)
	var ro0 := s.readouts(catalog)
	var sel0 := s.selection.duplicate(true)
	var doc0 := _text(s.frame_document())
	var com0 := b0.mass_properties.com_m
	var inertia0 := b0.mass_properties.inertia
	var r := s.swap_frame(catalog, "frame_4in_freestyle")
	var b1: Build = s.build(catalog)
	var ro1 := s.readouts(catalog)
	out.append(TestResult.new("shipped swap 3.5 -> 4 inch: the Build weighs the swapped frame (58 -> 70 g), arm 88 -> 96 mm",
		r["ok"] and is_equal_approx(b0.frame_mass_g(), 58.0) and is_equal_approx(b1.frame_mass_g(), 70.0)
		and is_equal_approx(float(b0.frame["specs"]["arm_mm"]), 88.0) and is_equal_approx(float(b1.frame["specs"]["arm_mm"]), 96.0),
		"%s -> %s" % [b0.frame_mass_g(), b1.frame_mass_g()]))
	var d_auw := float(ro1["auw_g"]) - float(ro0["auw_g"])
	out.append(TestResult.new("shipped swap: AUW rises by 12.5205 g (12.0 frame + 0.5205 longer motor leads), not zero",
		absf(d_auw - 12.5205) < 0.001 and ro1 != ro0, "delta %s" % d_auw))
	out.append(TestResult.new("shipped swap: the readouts all move (T/W, hover throttle, flight time)",
		ro1["thrust_to_weight"] != ro0["thrust_to_weight"] and ro1["hover_throttle"] != ro0["hover_throttle"]
		and ro1["flight_time_min"] != ro0["flight_time_min"], str(ro1)))
	var com1 := b1.mass_properties.com_m
	var i1 := b1.mass_properties.inertia
	out.append(TestResult.new("shipped swap: the centre of mass drops 0.415 mm and roll and yaw inertia rise (the longer arms)",
		absf((com1.y - com0.y) * 1000.0 + 0.415) < 0.02 and i1.x.x > inertia0.x.x * 1.15 and i1.z.z > inertia0.z.z * 1.15
		and absf(b1.mass_properties.total_mass_kg - b0.mass_properties.total_mass_kg - d_auw / 1000.0) < 1e-9,
		"%s %s" % [com1, i1]))
	out.append(TestResult.new("shipped swap: the swapped frame's own drawing is weighed with no edit applied (catalog mass, not a delta)",
		s.frame_edit(catalog).is_empty() and b1.frame_edit().is_empty(), str(b1.frame_edit())))
	s.undo()
	var b2: Build = s.build(catalog)
	out.append(TestResult.new("shipped swap: undo restores the selection, drawing, readouts, centre of mass and inertia bit for bit",
		s.selection == sel0 and _text(s.frame_document()) == doc0 and s.readouts(catalog) == ro0
		and b2.mass_properties.com_m == com0 and b2.mass_properties.inertia == inertia0, ""))
	return out


static func _test_offerings(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var ids: Array = []
	for o in FrameSwap.offerings(s, catalog):
		ids.append(o["id"])
	out.append(TestResult.new("a class fitting frame with a drawing is offered; the fitted frame, an undrawn frame and a 10-inch frame are not",
		ids.has(OTHER) and not ids.has("frame_5in_freestyle") and not ids.has("frame_5in_deadcat") and not ids.has(BIG), str(ids)))
	out.append(TestResult.new("ClassFit judges the 10-inch frame out of a 5-inch class and the 5-inch frame in",
		not ClassFit.verdict(CLASS_ID, "frame", BIG, catalog)["fits"] and ClassFit.verdict(CLASS_ID, "frame", OTHER, catalog)["fits"], ""))
	out.append(TestResult.new("with something on offer, why_not is empty", FrameSwap.why_not(s, catalog) == "", FrameSwap.why_not(s, catalog)))
	return out


static func _test_swap_draws_that_frame(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var before := DesignSession.readouts_of(s.build(catalog))
	var r := s.swap_frame(catalog, OTHER)
	var doc := s.frame_document()
	out.append(TestResult.new("the swap is accepted and selects the catalog frame", r["ok"] and s.selection["frame"] == OTHER, str(r)))
	out.append(TestResult.new("the drawing is the swapped-in frame's own document, not the old frame's plates",
		doc != null and doc.id == OTHER and is_equal_approx(AirframeDocument.plate_thickness_mm(doc.plates[0]), THICK_MM), ""))
	out.append(TestResult.new("the swapped-in drawing is editable and carries no edit", s.frame_editable() and s.frame_edit(catalog).is_empty(), ""))
	var ref := DesignSession.new()
	ref.drone_class = CLASS_ID
	var direct := DesignSession.from_selection(_session(), "frame", OTHER).build(catalog)
	var now := s.build(catalog)
	out.append(TestResult.new("the build is the catalog frame's: mass, inertia and readouts equal a direct build of that selection",
		now.all_up_weight_g() == direct.all_up_weight_g() and DesignSession.readouts_of(now) == DesignSession.readouts_of(direct)
		and DesignSession.readouts_of(now) != before, "%s vs %s" % [now.all_up_weight_g(), direct.all_up_weight_g()]))
	out.append(TestResult.new("swapping to the fitted frame again is a no-op with no undo step", s.swap_frame(catalog, OTHER)["ok"] and s._undo.size() == 1, ""))
	return out


static func _test_edits_and_undo(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var fl := s.plate_of_mesh("frame_arm_FL")
	var at := AirframeDocument.point_of(s.frame_document().plates[fl]["tip_point"]).normalized() * 91.0
	s.drill(fl, at, 3.0)
	var edited_doc := _text(s.frame_document())
	var edited_ro := DesignSession.readouts_of(s.build(catalog))
	var edited_sel := s.selection.duplicate(true)
	out.append(TestResult.new("before the swap the drilled frame reports edits to drop", FrameSwap.drops_edits(s, catalog), ""))
	var r := s.swap_frame(catalog, OTHER)
	out.append(TestResult.new("swapping away from an edited frame says its edits were dropped and they are gone",
		r["ok"] and r["dropped_edits"] and s.frame_edit(catalog).is_empty() and not FrameSwap.drops_edits(s, catalog), str(r)))
	out.append(TestResult.new("an unedited frame swap does not claim to drop edits", not _session().swap_frame(catalog, OTHER)["dropped_edits"], ""))
	var swapped_ro := DesignSession.readouts_of(s.build(catalog))
	out.append(TestResult.new("undo restores the selection AND the edited document, bit for bit",
		s.undo() and s.selection == edited_sel and _text(s.frame_document()) == edited_doc
		and DesignSession.readouts_of(s.build(catalog)) == edited_ro and FrameSwap.drops_edits(s, catalog), ""))
	out.append(TestResult.new("redo brings the swapped frame back with its own baseline (no phantom edit)",
		s.redo() and s.selection["frame"] == OTHER and DesignSession.readouts_of(s.build(catalog)) == swapped_ro and s.frame_edit(catalog).is_empty(), ""))
	return out


static func _test_refusals(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	var sel := s.selection.duplicate(true)
	var doc := _text(s.frame_document())
	var r := s.swap_frame(catalog, BAD_STACK)
	var verdict := PartSwap.judge(s, catalog, "frame", BAD_STACK, false)
	out.append(TestResult.new("a frame whose stack pattern the fitted boards do not fit is refused with the existing refusal text",
		not r["ok"] and r["reason"] != "" and not r["reason"].contains("no drawing") and r["reason"] == verdict["reason"]
		and verdict.has("refused_by") and PartSwap.HARD_IDS.has(verdict["refused_by"].id), str(r)))
	out.append(TestResult.new("a refused swap leaves selection, document and history untouched",
		s.selection == sel and _text(s.frame_document()) == doc and not s.can_undo(), ""))
	return out


static func _test_persistence(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := _session()
	s.swap_frame(catalog, OTHER)
	var fl := s.plate_of_mesh("frame_arm_FL")
	var at := AirframeDocument.point_of(s.frame_document().plates[fl]["tip_point"]).normalized() * 91.0
	s.drill(fl, at, 3.0)
	var ro := DesignSession.readouts_of(s.build(catalog))
	var saved_doc := _text(s.frame_document())
	# Save: parts + the document (what the shell's _sync_design_space writes), then reopen.
	var p := DroneClass.starting_project(CLASS_ID, "t")
	p.parts = s.selection.duplicate(true)
	p.airframe = s.frame_document().to_dictionary()
	var back := DesignSession.from_project(Project.from_dict(p.to_dict()))
	out.append(TestResult.new("reopening a saved swap keeps the frame choice AND its (edited) document",
		back.selection["frame"] == OTHER and _text(back.frame_document()) == saved_doc and DesignSession.readouts_of(back.build(catalog)) == ro, ""))
	# A swap with no edit saved as parts only (airframe empty) still opens on the swapped frame's drawing.
	var q := DroneClass.starting_project(CLASS_ID, "t")
	q.parts["frame"] = OTHER
	var plain := DesignSession.from_project(q)
	out.append(TestResult.new("a saved swap with no edit reopens drawn as the swapped-in frame, with no phantom edit",
		plain.frame_document() != null and plain.frame_document().id == OTHER and plain.frame_edit(catalog).is_empty(), ""))
	var old := DesignSession.from_project(DroneClass.starting_project(CLASS_ID, "t"))
	out.append(TestResult.new("an old file (class frame, no swap) loads the class's own document as before",
		old.frame_document().id == "frame_5in_freestyle" and old.frame_edit(catalog).is_empty(), ""))
	var r := _session()
	r.restore_state(s.selection, s.frame_document().to_dictionary())
	out.append(TestResult.new("restore_state of a saved swap restores the document and measures edits against the swapped frame",
		r.frame_document().id == OTHER and _text(r.frame_document()) == saved_doc and not r.frame_edit(catalog).is_empty() and r.frame_edit(catalog) == s.frame_edit(catalog), ""))
	return out


# ---------------------------------------------------------------------------
# The live Design Space: the Frame category of the parts shelf, the click and the confirm dialog
# ---------------------------------------------------------------------------

static func _ds(catalog: PartsCatalog, cls: String) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(cls), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("frame")
	return ds


static func _free(ds: DesignSpace) -> void:
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()


static func _row_ids(ds: DesignSpace) -> Array:
	var ids: Array = []
	for r in ds.shelf.rows:
		if String(r["category"]) == "frame":
			ids.append(String(r["id"]))
	return ids


static func _note_texts(ds: DesignSpace) -> Array:
	var out: Array = []
	for c in ds.shelf.list.get_children():
		if c is Label:
			out.append((c as Label).text)
	return out


static func _press(ds: DesignSpace, id: String) -> void:
	((ds.shelf.row_of(id)["button"]) as Button).pressed.emit()


static func _labels(ds: DesignSpace) -> Dictionary:
	var out := {}
	for k in ds.value_labels:
		out[k] = (ds.value_labels[k] as Label).text
	return out


## Undo through the UI's own path, then lets the stage read the session (as the app does on its next frame).
static func _undo(ds: DesignSpace) -> bool:
	var ok := ds.undo()
	ds._sync()
	return ok


static func _edit(ds: DesignSpace) -> void:
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var at := AirframeDocument.point_of(ds.session.frame_document().plates[fl]["tip_point"]).normalized() * 67.5
	assert(ds.session.drill(fl, at, 3.0)["ok"])
	ds._sync()


static func _test_ui_cards(catalog: PartsCatalog) -> Array:
	var out: Array = []
	DesignSession.extra_documents = {}
	for pair in [["sub250_35", "frame_4in_freestyle"], ["four_inch", "frame_35in_freestyle"]]:
		var ds := _ds(catalog, pair[0])
		var fitted := String(ds.session.selection["frame"])
		var ids := _row_ids(ds)
		out.append(TestResult.new("%s: the Frame category lists the fitted frame then the one offered frame, no why-not line" % pair[0],
			ids == [fitted, pair[1]] and ds.shelf.row_of(fitted)["fitted"] and not ds.shelf.row_of(pair[1])["fitted"]
			and not _note_texts(ds).has(FrameSwap.why_not(ds.session, catalog)) and FrameSwap.why_not(ds.session, catalog) == "", str(ids)))
		_free(ds)
	var ds5 := _ds(catalog, "five_inch")
	var ids5 := _row_ids(ds5)
	var why := FrameSwap.why_not(ds5.session, catalog)
	out.append(TestResult.new("five_inch: only the fitted frame is shown, and the why-not line says why no other is",
		ids5 == [String(ds5.session.selection["frame"])] and why != "" and _note_texts(ds5).has(why), "%s %s" % [ids5, _note_texts(ds5)]))
	_free(ds5)
	# Never a card for a frame that cannot be shown: with an undrawn 5" frame registered nowhere, none is a card.
	var ds35 := _ds(catalog, "sub250_35")
	var all_ok := true
	for id in _row_ids(ds35):
		all_ok = all_ok and (id == ds35.session.selection["frame"] or DesignSession.frame_document_path(id) != "")
	out.append(TestResult.new("every non-fitted frame card has a drawing", all_ok, ""))
	var refused := ds35.choose_frame("frame_5in_freestyle")
	out.append(TestResult.new("a frame that is not on offer is refused by the UI path and changes nothing",
		not refused["ok"] and not ds35.session.can_undo(), str(refused)))
	_free(ds35)
	# A drawn frame of another size class: the session would take it, the UI path must not (ClassFit).
	_register(BIG)
	var ds5b := _ds(catalog, CLASS_ID)
	var big := ds5b.choose_frame(BIG)
	out.append(TestResult.new("a drawn frame of the wrong size class is not a card and is refused by the UI path",
		not _row_ids(ds5b).has(BIG) and not big["ok"] and ds5b.session.selection["frame"] == "frame_5in_freestyle", str(big)))
	_free(ds5b)
	DesignSession.extra_documents = {}
	return out


static func _test_ui_swap(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog, "sub250_35")
	var other := "frame_4in_freestyle"
	var before := _labels(ds)
	var ref := DesignSession.default_for_class("sub250_35")
	ref.swap_frame(catalog, other)
	var want := {}
	var want_ro := DesignSession.readouts_of(ref.build(catalog))
	for k in before:
		want[k] = DesignSpace.format_readout(k, want_ro)
	_press(ds, other)
	out.append(TestResult.new("pressing the offered frame card swaps the frame at once (no dialog when there are no edits)",
		ds.session.selection["frame"] == other and ds.frame_confirm == null and ds.session.can_undo(), str(ds.session.selection["frame"])))
	out.append(TestResult.new("the 3D shows the new frame's document as drawn: baseline is its id, plates are the generated meshes, no phantom edit",
		ds._frame_orig.id == other and ds.frame_change_text() == "" and not ds.plate_regenerated(0)
		and _text(ds._frame_orig) == _text(AirframeDocument.load_from(DesignSession.frame_document_path(other))), ds._frame_orig.id))
	out.append(TestResult.new("the readouts show the swapped build", _labels(ds) == want, "%s vs %s" % [_labels(ds), want]))
	out.append(TestResult.new("the shelf now marks the new frame fitted and offers the old one",
		ds.shelf.row_of(other)["fitted"] and _row_ids(ds).size() == 2, str(_row_ids(ds))))
	out.append(TestResult.new("undo restores the first frame, its drawing baseline and the readouts",
		_undo(ds) and ds.session.selection["frame"] != other and ds._frame_orig.id == ds.session.frame_document().id
		and ds._frame_orig.id != other and _labels(ds) == before, ""))
	_free(ds)
	return out


static func _test_ui_confirm(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var other := "frame_4in_freestyle"
	var ds := _ds(catalog, "sub250_35")
	_edit(ds)
	var pre_ok := ds.session.frame_edit(catalog).is_empty() == false
	var fitted := String(ds.session.selection["frame"])
	var fitted_name := String(catalog.get_part(fitted)["name"])
	var sel := ds.session.selection.duplicate(true)
	var doc := _text(ds.session.frame_document())
	var labels := _labels(ds)
	var rev := ds.session.revision
	_press(ds, other)
	out.append(TestResult.new("an edited frame asks first: the dialog is up with the calm sentence and nothing has changed",
		pre_ok and ds.frame_confirm != null and ds._pending_frame == other
		and ds.frame_confirm.dialog_text == "Swapping the frame drops your edits to %s. Undo brings them back." % fitted_name
		and ds.session.selection == sel and ds.session.revision == rev, ds.frame_confirm.dialog_text if ds.frame_confirm != null else "no dialog"))
	if ds.frame_confirm == null:
		_free(ds)
		return out
	ds.frame_confirm.get_cancel_button().pressed.emit()
	out.append(TestResult.new("Cancel changes nothing: selection, document, history, readouts, baseline",
		ds.session.selection == sel and _text(ds.session.frame_document()) == doc and ds.session.revision == rev
		and _labels(ds) == labels and ds._frame_orig.id == fitted and ds._pending_frame == "", ""))
	ds.frame_confirm.hide()
	out.append(TestResult.new("closing the dialog without choosing changes nothing either", ds.session.selection == sel and ds.session.revision == rev, ""))
	_press(ds, other)
	ds.frame_confirm.get_ok_button().pressed.emit()
	out.append(TestResult.new("Confirm swaps: the new frame is fitted, drawn as itself and the edits are gone",
		ds.session.selection["frame"] == other and ds._frame_orig.id == other and ds.frame_change_text() == ""
		and ds.session.frame_edit(catalog).is_empty(), str(ds.session.selection["frame"])))
	out.append(TestResult.new("undo brings the edits back",
		_undo(ds) and ds.session.selection == sel and _text(ds.session.frame_document()) == doc
		and not ds.session.frame_edit(catalog).is_empty() and _labels(ds) == labels, ""))
	_free(ds)
	return out
