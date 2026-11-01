class_name TestDesignFile
extends RefCounted
## Save/load of a Design Space drone (PLAN Section 9, logic half). Every check goes through a real
## file written by DesignFile.save and read by DesignFile.load_file, in a scratch folder: DesignFile.dir
## is pointed at user://test_design_file and the folder is removed at the end. The real user://designs
## is never touched. One test per case.

const CLASS_ID := "five_inch"
const SCRATCH := "user://test_design_file"
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var saved_dir := DesignFile.dir
	DesignFile.dir = SCRATCH
	_wipe()
	var s := _edited(catalog)
	var path := String(DesignFile.save(s, "my drone")["path"])
	var r := DesignFile.load_file(path, catalog)
	var l: DesignSession = r["session"]
	out.append(TestResult.new("save lands in the scratch dir, not the real one", path.begins_with(SCRATCH) and FileAccess.file_exists(path), path))
	out.append(TestResult.new("a saved edited design loads ok", r["ok"] and l != null, str(r["reason"])))
	if l == null:
		l = DesignSession.default_for_class(CLASS_ID)
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	out.append(TestResult.new("the class is in the file and round-trips",
		on_disk is Dictionary and on_disk.get("class", "") == CLASS_ID and l.drone_class == s.drone_class, l.drone_class))
	out.append(TestResult.new("every part id round-trips (swapped motor, removed camera)", l.selection == s.selection, str(l.selection)))
	out.append(TestResult.new("a removed part stays removed", String(l.selection["camera"]) == "", ""))
	out.append(TestResult.new("the frame document round-trips element for element",
		_as_values(l.frame_document()) == _as_values(s.frame_document()), ""))
	var a := s.build(catalog)
	var b := l.build(catalog)
	var same := a != null and b != null
	if same:
		var ra := DesignSession.readouts_of(a)
		var rb := DesignSession.readouts_of(b)
		for k in KEYS:
			same = same and var_to_str(ra[k]) == var_to_str(rb[k])
	out.append(TestResult.new("readouts are bit-for-bit identical after reload", same, ""))
	out.append(TestResult.new("flown frame mass is bit-for-bit identical",
		same and var_to_str(float(a.frame["mass_g"])) == var_to_str(float(b.frame["mass_g"])), ""))
	out.append(TestResult.new("the edit really is in the design (frame mass differs from the unedited drone)",
		same and float(a.frame["mass_g"]) != float(DesignSession.default_for_class(CLASS_ID).build(catalog).frame["mass_g"]), ""))
	out.append(TestResult.new("the name round-trips", r["name"] == "my drone", str(r["name"])))
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var junk := FileAccess.open(SCRATCH + "/notes.txt", FileAccess.WRITE)
	junk.store_string("x")
	junk.close()
	out.append(TestResult.new("list() shows only design files", DesignFile.list() == PackedStringArray(["my drone.lothaldesign"]), str(DesignFile.list())))
	out.append(TestResult.new("list() shows the saved file", DesignFile.list().has("my drone.lothaldesign"), str(DesignFile.list())))
	out.append(TestResult.new("no .tmp is left beside the file", not FileAccess.file_exists(path + ".tmp"), ""))
	# Refusals.
	var good := DesignFile.to_dict(s, "x")
	out.append(_refused("unknown part id", _with(good, ["parts", "motor"], "no_such_motor"), catalog, "no_such_motor"))
	out.append(_refused("part id in the wrong category", _with(good, ["parts", "motor"], String(s.selection["battery"])), catalog, "motor"))
	out.append(_refused("newer version", _with(good, ["version"], VERSION_PLUS()), catalog, "newer"))
	out.append(_refused("version with a fraction", _with(good, ["version"], 1.5), catalog, "version"))
	out.append(_refused("version zero", _with(good, ["version"], 0), catalog, "version"))
	out.append(_refused("version not a number", _with(good, ["version"], "1"), catalog, "version"))
	out.append(_refused("unknown class", _with(good, ["class"], "nine_inch"), catalog, "class"))
	out.append(_refused("wrong format tag", _with(good, ["format"], "other"), catalog, "not a Lothal"))
	out.append(_refused("unknown category", _with(good, ["parts", "flux_capacitor"], "x"), catalog, "category"))
	out.append(_refused("missing category", _without(good, ["parts", "esc"]), catalog, "does not say"))
	out.append(_refused("part id not a string", _with(good, ["parts", "esc"], 7), catalog, "not a part id"))
	out.append(_refused("missing frame document", _without(good, ["frame_document"]), catalog, "no frame document"))
	out.append(_refused("frame document of another frame", _with(good, ["frame_document", "id"], "other_frame"), catalog, "different frame"))
	out.append(_refused("frame document with wrong plate count", _with(good, ["frame_document", "plates"], []), catalog, "plates"))
	out.append(_refused("frame document holes malformed", _with(good, ["frame_document", "plates"], _bad_holes(good)), catalog, "holes"))
	out.append(_refused("frame document plate malformed", _with(good, ["frame_document", "plates"], _bad_plates(good)), catalog, "malformed"))
	out.append(_refused("parts not a dictionary", _with(good, ["parts"], [1]), catalog, "parts"))
	# Files.
	out.append(_file_refused("missing file", SCRATCH + "/nope.lothaldesign", null, catalog, "does not exist"))
	out.append(_file_refused("garbage file", SCRATCH + "/junk.lothaldesign", "{{ not json", catalog, "readable"))
	out.append(_file_refused("json array file", SCRATCH + "/arr.lothaldesign", "[1,2]", catalog, "not a design file"))
	out.append(_file_refused("empty file", SCRATCH + "/empty.lothaldesign", "", catalog, "readable"))
	# Overwrite.
	var s2 := DesignSession.default_for_class(CLASS_ID)
	DesignFile.save(s2, "my drone")
	var back: DesignSession = DesignFile.load_file(path, catalog)["session"]
	out.append(TestResult.new("saving again under the same name replaces the file", back != null and back.selection == s2.selection, ""))
	# restore_state on a session that has history.
	var h := _edited(catalog)
	var keep := h.selection.duplicate(true)
	var given := DesignSession.default_for_class(CLASS_ID).selection.duplicate(true)
	h.restore_state(given, {})
	given["motor"] = "mutated_after"
	out.append(TestResult.new("restore_state clears undo and redo", h.can_undo() == false and h.can_redo() == false and keep != h.selection, ""))
	out.append(TestResult.new("restore_state copies the selection it is given", String(h.selection["motor"]) != "mutated_after", String(h.selection["motor"])))
	out.append(TestResult.new("a name with path characters stays in the dir", DesignFile.path_for("../x/y").get_base_dir() == SCRATCH, DesignFile.path_for("../x/y")))
	out.append(TestResult.new("an empty name still gets a file name", DesignFile.path_for("  ").get_file() == "design." + DesignFile.EXTENSION, DesignFile.path_for("  ")))
	out.append_array(_section7(catalog))
	_wipe()
	DesignFile.dir = saved_dir
	return out


## The document as plain parsed JSON values (packed arrays flattened), compared with == (exact doubles).
static func _as_values(doc: AirframeDocument) -> Variant:
	return JSON.parse_string(JSON.stringify(doc.to_dictionary(), "", true, true))


static func _any_label_has(n: Node, needle: String) -> bool:
	if n is Label and (n as Label).visible and (n as Label).text.contains(needle):
		return true
	for c in n.get_children():
		if _any_label_has(c, needle):
			return true
	return false


## The two Section 7 leftovers, on the real panel at 1280x720.
static func _section7(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	var a := ds.warning_pin_px("part/battery", 0)
	var b := ds.warning_pin_px("part/battery", 1)
	out.append(TestResult.new("the seed's two warning dots on the pack are at least 20 px apart",
		ds.warning_pins.size() == 2 and a.distance_to(b) >= 20.0, "%.1f px" % a.distance_to(b)))
	out.append(TestResult.new("seed: the count is shown", ds.issues_label.visible, ""))
	ds.select("part/battery")
	var r := ds.remove_selected()
	# Owner-approved warnings design: "1 issue" is the one statement of a missing battery; the old
	# duplicate "no battery: cannot fly" flight line is gone, so no label may carry that text.
	out.append(TestResult.new("no battery: the count stays and says \"1 issue\"", r["ok"] and ds.issues_label.visible and ds.issues_label.text == "1 issue", ds.issues_label.text))
	out.append(TestResult.new("no battery: no label repeats \"cannot fly\" (the old flight line is removed)", not _any_label_has(ds, "cannot fly"), ""))
	out.append(TestResult.new("no battery: the warning pin itself still exists", ds.warning_pins.size() == 1, str(ds.warning_pins.size())))
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()
	return out


static func VERSION_PLUS() -> int:
	return DesignFile.VERSION + 1


## A session with a swapped motor, a removed camera, and every kind of frame edit.
static func _edited(catalog: PartsCatalog) -> DesignSession:
	var s := DesignSession.default_for_class(CLASS_ID)
	for m in catalog.list_category("motor"):
		var id := String(m["part_id"])
		if id != String(s.selection["motor"]) and s.swap(catalog, "motor", id)["ok"]:
			break
	s.remove("camera")
	var doc := s.frame_document()
	var fl := s.plate_of_mesh("frame_arm_FL")
	var axis := AirframeDocument.point_of(doc.plates[fl]["tip_point"]).normalized()
	s.drill(fl, axis * 91.0, 3.0)
	s.set_arm_width(fl, 1.1)
	var top := s.plate_of_mesh("frame_plate_top")
	s.set_plate_thickness(top, 2.5)
	s.pocket(fl, FrameTools.slot_pocket(axis * 60.0 - Vector2(-axis.y, axis.x) * 4.0, axis * 60.0 + Vector2(-axis.y, axis.x) * 4.0, 3.0))
	var n := AirframeDocument.plate_holes(s.frame_document().plates[fl]).size()
	s.drill(fl, axis * 75.0, 2.2)
	s.fill(fl, n)
	return s


static func _refused(label: String, d: Dictionary, catalog: PartsCatalog, word: String) -> TestResult:
	var v := DesignFile.from_dict(d, catalog)
	var reason := String(v["reason"])
	var ok: bool = not v["ok"] and v["session"] == null and reason != "" and reason.find("\n") < 0 and reason.contains(word)
	return TestResult.new("refused with one line: " + label, ok, reason)


static func _file_refused(label: String, path: String, content: Variant, catalog: PartsCatalog, word: String) -> TestResult:
	if content != null:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var h := FileAccess.open(path, FileAccess.WRITE)
		h.store_string(String(content))
		h.close()
	var v := DesignFile.load_file(path, catalog)
	var reason := String(v["reason"])
	return TestResult.new("file refused: " + label, not v["ok"] and v["session"] == null and reason.contains(word) and reason.find("\n") < 0, reason)


static func _bad_holes(d: Dictionary) -> Array:
	var plates: Array = (d["frame_document"]["plates"] as Array).duplicate(true)
	plates[0]["holes"] = 5
	return plates


static func _bad_plates(d: Dictionary) -> Array:
	var plates: Array = (d["frame_document"]["plates"] as Array).duplicate(true)
	plates[0] = "oops"
	return plates


static func _with(d: Dictionary, keys: Array, value: Variant) -> Dictionary:
	var c := d.duplicate(true)
	var node: Dictionary = c
	for i in keys.size() - 1:
		node = node[keys[i]]
	node[keys[-1]] = value
	return c


static func _without(d: Dictionary, keys: Array) -> Dictionary:
	var c := d.duplicate(true)
	var node: Dictionary = c
	for i in keys.size() - 1:
		node = node[keys[i]]
	node.erase(keys[-1])
	return c


static func _wipe() -> void:
	var d := DirAccess.open(SCRATCH)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
