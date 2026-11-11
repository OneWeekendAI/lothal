class_name TestCustomTiles
extends RefCounted
## M12 (MERGE_TRACKER): the Parts shelf ends the ESC, flight controller, camera, VTX, receiver and antenna
## categories with a "New <part>" tile that opens the old Lab form (unchanged), and a part saved there is
## on the shelf, fits the build, and is still there after a restart (a fresh catalog read).
## MUTATION: remove a category from DESIGN_TILES (or drop the refresh) and that category's rows fail.


static func _fill(category: String, form: AcceptDialog) -> void:
	var name_ := "Shed %s %d" % [category, randi()]
	match category:
		"esc":
			(form as CustomEscDialog).set_fields(name_, 35.0, 45.0, 4, 12.0, "30.5x30.5", "3-6S", "DShot600", "spec sheet")
		"flight_controller":
			(form as CustomFcDialog).set_fields(name_, "ICM-42688-P", 8000.0, 8.0, "30.5x30.5", "F405", 8000, "spec sheet")
		_:
			(form as CustomComponentDialog).set_fields(name_, 6.0, 20.0, 20.0, 10.0, {}, "scale")


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var held := RealFiles.hold([CustomParts.SAVE_PATH])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomParts.SAVE_PATH))
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	ds.shelf.set_open(true)
	for category in ["esc", "flight_controller", "camera", "vtx", "receiver", "antenna"]:
		ds.shelf.toggle_category(category)
		var tile: BaseButton = null
		for n in ["AddEsc", "AddFc", "AddCamera", "AddVtx", "AddReceiver", "AddAntenna"]:
			var t := ds.shelf.find_child(n, true, false) as BaseButton
			if t != null and String(PartsShelf.DESIGN_TILES[category][0]) == n:
				tile = t
		out.append(TestResult.new("%s: the shelf ends with a New tile" % category, tile != null, ""))
		if tile == null:
			continue
		tile.pressed.emit()
		var form := ds.custom_form
		out.append(TestResult.new("%s: pressing it opens the form" % category, form != null and form.get_parent() == ds, ""))
		if form == null:
			continue
		_fill(category, form)
		var seen := {"id": ""}
		if form.has_signal("esc_saved"):
			form.connect("esc_saved", func(sid: String): seen["id"] = sid)
		elif form.has_signal("fc_saved"):
			form.connect("fc_saved", func(sid: String): seen["id"] = sid)
		else:
			form.connect("component_saved", func(sid: String): seen["id"] = sid)
		var refusals: Array = form.call("submit")
		out.append(TestResult.new("%s: the form saves" % category, refusals.is_empty() and String(seen["id"]) != "", str(refusals)))
		var id := String(seen["id"])
		out.append(TestResult.new("%s: it is on the shelf's catalog at once" % category, id != "" and not ds._catalog.get_part(id).is_empty(), id))
		var swapped: Dictionary = ds.session.swap(ds._catalog, category, id) if id != "" else {"ok": false}
		out.append(TestResult.new("%s: it fits the build" % category, bool(swapped.get("ok", false)), str(swapped.get("reason", ""))))
		out.append(TestResult.new("%s: and survives a restart" % category,
			id != "" and not PartsCatalog.load_with_custom().get_part(id).is_empty(), ""))
	ds.free()
	held.restore()
	return out
