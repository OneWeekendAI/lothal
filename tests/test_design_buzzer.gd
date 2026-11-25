class_name TestDesignBuzzer
extends RefCounted
## The buzzer in the live Design Space: on the shelf, swappable, removable, enterable by hand.
##
## ## The checks that could have passed while proving nothing
##
## - Every AUW figure is read off a `Build` the test makes ITSELF with `Build`'s own path
##   (`DesignSession.build`) from a selection the test names, and compared with the catalog part's
##   `mass_g` read from the catalog file, never from the session's own readouts alone.
## - The delta checks compare AUW with a buzzer to AUW of the SAME drone without one, so a buzzer
##   that weighed nothing, or twice, fails.
## - The custom part is entered through the real form (`open_custom_part_form` -> the dialog's own
##   `set_fields`/`submit`), and the shelf's own tile is pressed, not called around.
## - The user's custom-parts file is held and put back (RealFiles) so a run leaves it as found.
##
## NOT DRAWN: the Design Space's class models carry no buzzer node (the receiver is the same), so a
## buzzer has no pick address and no 3D mesh here. It is swapped and removed from the shelf's
## Parts cards (the stack's cards, with a "None" card), and a drag-off cannot remove it.

const CLASS_ID := "five_inch"
const EPS := 1e-6


static func _auw(s: DesignSession, catalog: PartsCatalog) -> float:
	var b := s.build(catalog)
	return b.all_up_weight_g() if b != null else NAN


static func _mass(catalog: PartsCatalog, id: String) -> float:
	return float(catalog.get_part(id).get("mass_g", NAN))


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	return ds


static func run() -> Array:
	var out: Array = []
	var held := RealFiles.hold([CustomParts.SAVE_PATH])
	if FileAccess.file_exists(CustomParts.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomParts.SAVE_PATH))
	var catalog := PartsCatalog.load_default()
	var ids: Array = catalog.list_category("buzzer").map(func(p): return String(p["part_id"]))
	out.append(TestResult.new("the catalog stocks at least two buzzers", ids.size() >= 2, str(ids)))
	if ids.size() < 2:
		held.restore()
		return out
	var a: String = ids[0]
	var b: String = ids[1]

	# --- shelf
	var s := DesignSession.default_for_class(CLASS_ID)
	var fitted0 := String(s.selection.get("buzzer", ""))
	var group: Array = s.shelf(catalog).filter(func(g): return String(g["category"]) == "buzzer")
	var listed: Array = []
	if not group.is_empty():
		listed = (group[0]["parts"] as Array).map(func(p): return String(p["id"]))
	var want_listed: Array = ids.filter(func(i): return i != fitted0)
	out.append(TestResult.new("the shelf lists a Buzzer group with every catalog buzzer not fitted",
		not group.is_empty() and listed == want_listed and String(group[0]["name"]) == "Buzzer",
		"%s vs %s" % [listed, want_listed]))
	out.append(TestResult.new("the buzzer has a part sheet",
		not PartSheetTabs.for_category("buzzer").is_empty() and PartSheetTabs.SHELF_CATEGORIES_WITH_SHEET.has("buzzer"), ""))

	# --- swap: part changes, AUW by exactly the mass
	var base := _auw(s, catalog)
	out.append(TestResult.new("the default drone builds with the buzzer slot empty",
		fitted0 == "" and not is_nan(base), "fitted=%s auw=%s" % [fitted0, base]))
	var v := s.swap(catalog, "buzzer", a)
	var with_a := _auw(s, catalog)
	out.append(TestResult.new("swapping a buzzer in fits it and adds exactly its mass to the AUW",
		v["ok"] and s.selection["buzzer"] == a and absf((with_a - base) - _mass(catalog, a)) < EPS,
		"%s delta %s want %s" % [v, with_a - base, _mass(catalog, a)]))
	var direct := DesignSession.default_for_class(CLASS_ID)
	direct.selection["buzzer"] = a
	out.append(TestResult.new("the session's AUW is a direct build of the same selection",
		absf(_auw(direct, catalog) - with_a) < EPS, ""))
	var v2 := s.swap(catalog, "buzzer", b)
	var with_b := _auw(s, catalog)
	out.append(TestResult.new("swapping to another buzzer moves the AUW by exactly the mass difference",
		v2["ok"] and s.selection["buzzer"] == b
		and absf((with_b - with_a) - (_mass(catalog, b) - _mass(catalog, a))) < EPS,
		"delta %s want %s" % [with_b - with_a, _mass(catalog, b) - _mass(catalog, a)]))
	var shelf_ids: Array = []
	for g in s.shelf(catalog):
		if String(g["category"]) == "buzzer":
			shelf_ids = (g["parts"] as Array).map(func(p): return String(p["id"]))
	out.append(TestResult.new("the replaced buzzer is back on the shelf and the fitted one is not",
		shelf_ids.has(a) and not shelf_ids.has(b), str(shelf_ids)))

	# --- remove: still flies, AUW drops by its mass, no "cannot fly" line
	var r := s.remove("buzzer")
	var after := _auw(s, catalog)
	var fs := s.flight_state(catalog)
	out.append(TestResult.new("removing the buzzer works, the drone still flies and says nothing is missing",
		r["ok"] and s.selection["buzzer"] == "" and fs["flies"] and (fs["missing"] as Array).is_empty()
		and String(fs["line"]) == "", "%s %s" % [r, fs]))
	out.append(TestResult.new("the AUW drops by exactly the removed buzzer's mass",
		absf((with_b - after) - _mass(catalog, b)) < EPS and absf(after - base) < EPS,
		"drop %s want %s" % [with_b - after, _mass(catalog, b)]))
	var bb := s.build(catalog)
	var blocking := BuildWarning.by_severity(bb.warnings()).filter(func(w): return w.severity == BuildWarning.Severity.IMPOSSIBLE)
	out.append(TestResult.new("no impossible warning appears for a drone with no buzzer", blocking.is_empty(),
		str(blocking.map(func(w): return w.id))))
	out.append(TestResult.new("removing an empty buzzer slot is refused politely, not crashed",
		not s.remove("buzzer")["ok"], ""))

	# --- through the live Design Space: the stack's cards, the None card, undo
	var ds := _ds(catalog)
	ds.select("part/stack")
	var rows: Array = ds.shelf.rows.filter(func(x): return String(x["category"]) == "buzzer")
	out.append(TestResult.new("selecting the stack shows buzzer cards, a None card first and every catalog buzzer",
		rows.size() == ids.size() + 1 and String(rows[0]["id"]) == "", "%d rows" % rows.size()))
	var ds_base := _auw(ds.session, catalog)
	var chosen := ds.choose("buzzer", a)
	out.append(TestResult.new("clicking a buzzer card fits it, and the readout is the direct build's",
		chosen["ok"] and ds.session.selection["buzzer"] == a
		and ds.shelf.fitted.get("buzzer", "") == a
		and absf((_auw(ds.session, catalog) - ds_base) - _mass(catalog, a)) < EPS, str(chosen)))
	var none := ds.choose("buzzer", "")
	out.append(TestResult.new("the None card removes it again, and undo puts it back",
		none["ok"] and ds.session.selection["buzzer"] == "" and ds.undo() and ds.session.selection["buzzer"] == a, str(none)))

	# --- design your own: the tile, the form, the saved part selectable
	ds.session.selection["buzzer"] = ""
	ds.refresh_shelf()
	ds.shelf.set_open(true)
	ds.shelf.expanded["buzzer"] = true
	ds.refresh_shelf()
	var tile := ds.shelf.find_child("AddBuzzer", true, false) as Button
	out.append(TestResult.new("the buzzer group ends in a New buzzer tile", tile != null, ""))
	if tile != null:
		tile.pressed.emit()
	var form := ds.custom_form as CustomComponentDialog
	out.append(TestResult.new("pressing the tile opens the buzzer form",
		form != null and form.category == "buzzer", str(form)))
	out.append(TestResult.new("open_custom_part_form accepts the buzzer category", ds.open_custom_part_form("buzzer"), ""))
	form = ds.custom_form as CustomComponentDialog
	var probs: Array = []
	var saved := {"id": ""}
	if form != null:
		form.component_saved.connect(func(pid: String): saved["id"] = pid)
		form.set_fields("Shed buzzer", 3.5, 20.0, 12.0, 9.0, {"self_powered": true, "loudness_db": 90.0}, "measured")
		probs = form.submit()
	var saved_id := String(saved["id"])
	out.append(TestResult.new("the form saves a buzzer", probs.is_empty() and saved_id != "", str(probs)))
	var g2: Array = ds.session.shelf(ds._catalog).filter(func(g): return String(g["category"]) == "buzzer")
	var on_shelf: Array = (g2[0]["parts"] as Array).map(func(p): return String(p["id"])) if not g2.is_empty() else []
	out.append(TestResult.new("the saved buzzer is on the shelf at once", saved_id != "" and on_shelf.has(saved_id), str(on_shelf)))
	var before := _auw(ds.session, ds._catalog)
	var pick := ds.choose("buzzer", saved_id)
	out.append(TestResult.new("the saved buzzer can be chosen and adds exactly its own mass",
		pick["ok"] and ds.session.selection["buzzer"] == saved_id
		and absf((_auw(ds.session, ds._catalog) - before) - 3.5) < EPS, "%s" % [_auw(ds.session, ds._catalog) - before]))
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()
	held.restore()
	return out
