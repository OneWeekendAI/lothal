class_name TestDesignGps
extends RefCounted
## The GPS in the live Design Space: on the shelf for EVERY class, swappable, removable, enterable by
## hand, weighed and seated where it stands, and feeding the failsafe and UART warnings.
##
## ## The checks that could have passed while proving nothing
##
## - AUW is read off a `Build` the test makes ITSELF (`DesignSession.build`) from a selection the test
##   names, and compared with the catalog part's `mass_g`; the delta is against the SAME drone without
##   a GPS, so a GPS that weighed nothing or twice fails.
## - THE CENTRE OF MASS is not asserted against `Build`'s own `component_centre_m`. The test takes the
##   GPS bay from `MountLayout` and adds the module's half height and its mast itself, then checks the
##   build's weighed part sits THERE, and that the centre moved by the first moment
##   `m * (seat - com_before) / (M + m)` written out here. A GPS weighed at the origin, at the bay
##   without its mast, or on the plate instead of the stalk fails one of the two.
## - The mast is checked at two heights (the module's 45 mm, then a 20 mm tweak): the centre of mass
##   must rise by `m * dh / M`, which a GPS whose mast was ignored does not do.
## - Every class is its own result (a looping check fails once and hides the rest).
## - The warning checks go both ways round: with the GPS rescue configured the warning is PRESENT with
##   no GPS and ABSENT with one, and PRESENT again after removing it.
## - The user's custom-parts file is held and put back (RealFiles) so a run leaves it as found.
##
## DRAWN ONLY WHERE A NODE EXISTS: only seven_lr's model carries a gps mesh. There it follows the
## selection (hidden when not fitted); everywhere else a GPS has no mesh and no pick address. It is
## swapped and removed from the shelf's stack cards (with a "None" card), a drop on the stack fits it
## like the receiver and buzzer, and a drag-off cannot remove it. The drawn puck is a picture: the
## mass is seated at Build's gps_mount, which is where the checks below look.
## POWER: `Build.AVIONICS_W` budgets a GPS per prop size class (0.4/0.5/0.6 W, an estimate), and a part's
## own `specs.power_w` wins; no catalog GPS publishes one, so the table is what is checked. The table is
## item 12's subject, not changed here.

const MASTED := "gps_masted_compact"      # 11 g on a 45 mm mast
const OTHER := "gps_micro_flat"           # 4 g, flat
const EPS := 1e-6
const COM_EPS := 1e-7   # Vector3 is float32 here


const THE_SPACE_DONE := "the live Design Space block finished"


static func _build(s: DesignSession, catalog: PartsCatalog) -> Build:
	return s.build(catalog)


static func _auw(s: DesignSession, catalog: PartsCatalog) -> float:
	var b := s.build(catalog)
	return b.all_up_weight_g() if b != null else NAN


static func _mass(catalog: PartsCatalog, id: String) -> float:
	return float(catalog.get_part(id).get("mass_g", NAN))


static func _ds(class_id: String, catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(class_id), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	return ds


## Where the GPS must sit, worked out here from the bay and the module's own published numbers.
static func _seat(b: Build, gps: Dictionary, mast_m: float) -> Vector3:
	var bay := MountLayout.by_id(b.mount_points(), "gps_mount")
	var h := float(gps["specs"]["height_mm"]) / 1000.0
	return bay.position + Vector3(0.0, bay.normal * (h * 0.5 + mast_m), 0.0)


static func _warning(b: Build, id: StringName) -> BuildWarning:
	for w in b.warnings():
		if w.id == id:
			return w
	return null


static func _rescue_config() -> Dictionary:
	var cfg := {}
	FailsafeSettings.set_stage2(cfg, FailsafeSettings.GPS_RESCUE)
	return cfg


static func run() -> Array:
	var out: Array = []
	var held := RealFiles.hold([CustomParts.SAVE_PATH])
	if FileAccess.file_exists(CustomParts.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomParts.SAVE_PATH))
	var catalog := PartsCatalog.load_default()
	var ids: Array = catalog.list_category("gps").map(func(p): return String(p["part_id"]))
	out.append(TestResult.new("the catalog stocks the masted and the flat GPS the checks use",
		ids.has(MASTED) and ids.has(OTHER) and ids.size() >= 3, str(ids)))
	if not (ids.has(MASTED) and ids.has(OTHER)):
		held.restore()
		return out

	out.append_array(_the_chrome(catalog, ids))
	for class_id in DroneClass.ids():
		if DroneClass.is_available(class_id):
			out.append_array(_one_class(class_id, catalog, ids))
	out.append_array(_the_mast_moves_the_centre(catalog))
	out.append_array(_the_warnings(catalog))
	var space := _the_space(catalog, ids)
	out.append_array(space)
	# A script error inside _the_space drops every check it had gathered and the runner counts it as
	# nothing, not as a failure — so the block must prove it ran to its last line.
	out.append(TestResult.new("the live Design Space checks ran to their last line (a crash would drop them silently)",
		not space.is_empty() and (space[-1] as TestResult).name == THE_SPACE_DONE, "%d results" % space.size()))
	held.restore()
	return out


## Sheet, shelf order, slot, not-drawn: what does not depend on a class.
static func _the_chrome(catalog: PartsCatalog, ids: Array) -> Array:
	var out: Array = []
	out.append(TestResult.new("GPS is a shelf category with a name, a stack slot and no drawn mount of its own",
		PartSnap.SHELF_CATEGORIES.has("gps") and PartSwap.SLOTS["stack"].has("gps")
		and String(PartSwap.CATEGORY_NAMES.get("gps", "")) == "GPS"
		and PartSnap.MOUNTS_BY_CATEGORY["gps"] == ["stack"], ""))
	out.append(TestResult.new("the GPS has a part sheet with the Link and Print (mast) tabs",
		PartSheetTabs.SHELF_CATEGORIES_WITH_SHEET.has("gps")
		and PartSheetTabs.for_category("gps").map(func(t): return String(t["id"])) == ["sheet", "link", "print"], ""))
	out.append(TestResult.new("the shelf's GPS card names the mast, the number that moves the centre of mass",
		PartSwap.deciding_numbers(catalog.get_part(MASTED), "gps").has("45 mm mast")
		and PartSwap.deciding_numbers(catalog.get_part(OTHER), "gps").has("flat"),
		str(PartSwap.deciding_numbers(catalog.get_part(MASTED), "gps"))))
	# drawn only where the model has a node: seven_lr's glb carries a gps mesh, nothing else does
	for class_id in DroneClass.ids():
		if not DroneClass.is_available(class_id):
			continue
		var ds := DesignSpace.new(DesignSession.default_for_class(class_id), catalog)
		ds.size = Vector2(1280, 720)
		var has_node := ds._look_nodes.has("gps")
		var seven := class_id == "seven_lr"
		out.append(TestResult.new("%s: the model %s a GPS mesh" % [class_id, "draws" if seven else "has no"],
			has_node == seven, str(ds._look_nodes.keys())))
		if has_node:
			var mi := ds._look_nodes["gps"] as MeshInstance3D
			out.append(TestResult.new("%s: with no GPS fitted its drawn GPS is hidden, and not pickable" % class_id,
				not mi.visible and not ds.picks.addresses().has("part/gps"), str(mi.visible)))
			ds.choose("gps", MASTED)
			out.append(TestResult.new("%s: fitting a GPS shows the drawn puck and makes it pickable" % class_id,
				mi.visible and ds.picks.addresses().has("part/gps"), str(ds.picks.addresses().filter(func(a): return String(a).contains("gps")))))
			ds.choose("gps", "")
			out.append(TestResult.new("%s: taking the GPS off hides it again" % class_id, not mi.visible, ""))
		else:
			out.append(TestResult.new("%s: no pick address names a GPS (it is not drawn)" % class_id,
				not ds.picks.addresses().any(func(a): return String(a).contains("gps")), ""))
		out.append(TestResult.new("%s: a drag-off cannot remove a GPS (no mount address maps to it)" % class_id,
			PartSnap.category_at("part/gps") == "", ""))
		ds.free()
	return out


static func _one_class(class_id: String, catalog: PartsCatalog, ids: Array) -> Array:
	var out: Array = []
	var s := DesignSession.default_for_class(class_id)
	var seeded := String(s.selection.get("gps", "x"))
	out.append(TestResult.new("%s: the default drone names a gps slot (seeded or empty), never an absent key" % class_id,
		s.selection.has("gps"), seeded))
	# the shelf lists every catalog GPS but the fitted one
	var group: Array = s.shelf(catalog).filter(func(g): return String(g["category"]) == "gps")
	var listed: Array = []
	if not group.is_empty():
		listed = (group[0]["parts"] as Array).map(func(p): return String(p["id"]))
	var want_listed: Array = ids.filter(func(i): return i != seeded)
	out.append(TestResult.new("%s: the shelf lists a GPS group with every catalog GPS not fitted" % class_id,
		not group.is_empty() and listed == want_listed and String(group[0]["name"]) == "GPS", "%s vs %s" % [listed, want_listed]))

	# base = this class without a GPS
	if seeded != "":
		var rm := s.remove("gps")
		out.append(TestResult.new("%s: its seeded GPS (%s) can be removed" % [class_id, seeded],
			rm["ok"] and s.selection["gps"] == "", str(rm)))
	else:
		out.append(TestResult.new("%s: removing a GPS that is not fitted is refused politely" % class_id,
			not s.remove("gps")["ok"], ""))
	var b0 := _build(s, catalog)
	var auw0 := _auw(s, catalog)
	if b0 == null:
		out.append(TestResult.new("%s builds without a GPS" % class_id, false, ""))
		return out
	var m0 := b0.mass_properties.total_mass_kg
	var com0 := b0.mass_properties.com_m
	var w0 := b0.avionics_w()
	var t0 := b0.flight_time_min()

	# fit the masted GPS
	var v := s.swap(catalog, "gps", MASTED)
	var gps := catalog.get_part(MASTED)
	var m := float(gps["mass_g"]) / 1000.0
	var b1 := _build(s, catalog)
	out.append(TestResult.new("%s: swapping the GPS in fits it and adds exactly its mass to the AUW" % class_id,
		v["ok"] and s.selection["gps"] == MASTED and absf((_auw(s, catalog) - auw0) - _mass(catalog, MASTED)) < EPS,
		"%s delta %s" % [v, _auw(s, catalog) - auw0]))
	var seat := _seat(b1, gps, 0.045)
	var weighed := b1.mass_parts().filter(func(p): return str(p.label) == str(gps["name"]))
	out.append(TestResult.new("%s: the GPS is weighed ONCE, at its bay plus half its height plus its 45 mm mast" % class_id,
		weighed.size() == 1 and (weighed[0].position_m as Vector3).distance_to(seat) < COM_EPS
		and absf(float(weighed[0].mass_kg) - m) < EPS, "%s want %s" % [weighed.map(func(p): return p.position_m), seat]))
	var expect_com := (com0 * m0 + seat * m) / (m0 + m)
	out.append(TestResult.new("%s: the centre of mass moved by the first moment m*(seat - com)/(M+m)" % class_id,
		b1.mass_properties.com_m.distance_to(expect_com) < COM_EPS,
		"%s want %s (shift %s)" % [b1.mass_properties.com_m, expect_com, b1.mass_properties.com_m - com0]))
	out.append(TestResult.new("%s: the stalk raises the centre of mass (the mast is the point of the part)" % class_id,
		b1.mass_properties.com_m.y > com0.y, "%s -> %s" % [com0.y, b1.mass_properties.com_m.y]))
	# power: the table's figure per size class, flight time shortens
	var table: Dictionary = Build.AVIONICS_W[b1.avionics_size_class()]
	out.append(TestResult.new("%s: avionics power rises by the GPS's own row of the size-class table, and flight time falls" % class_id,
		absf((b1.avionics_w() - w0) - float(table["gps"])) < EPS and b1.avionics_breakdown().has("gps")
		and b1.flight_time_min() < t0, "dW %s want %s; t %s -> %s" % [b1.avionics_w() - w0, table["gps"], t0, b1.flight_time_min()]))

	# swap to the flat one: AUW by the mass difference, centre follows the flat seat
	var v2 := s.swap(catalog, "gps", OTHER)
	var b2 := _build(s, catalog)
	var flat := catalog.get_part(OTHER)
	var m2 := float(flat["mass_g"]) / 1000.0
	var seat2 := _seat(b2, flat, 0.0)
	var expect2 := (com0 * m0 + seat2 * m2) / (m0 + m2)
	out.append(TestResult.new("%s: swapping to a flat GPS moves AUW by the mass difference and seats it on the plate" % class_id,
		v2["ok"] and absf((_auw(s, catalog) - auw0) - _mass(catalog, OTHER)) < EPS
		and b2.mass_properties.com_m.distance_to(expect2) < COM_EPS, "%s want %s" % [b2.mass_properties.com_m, expect2]))
	out.append(TestResult.new("%s: the replaced GPS is back on the shelf and the fitted one is not" % class_id,
		_shelf_ids(s, catalog).has(MASTED) and not _shelf_ids(s, catalog).has(OTHER), str(_shelf_ids(s, catalog))))

	# remove: still flies, AUW and CG back to exactly the base
	var r := s.remove("gps")
	var fs := s.flight_state(catalog)
	var b3 := _build(s, catalog)
	out.append(TestResult.new("%s: removing the GPS leaves a flying drone with nothing reported missing" % class_id,
		r["ok"] and s.selection["gps"] == "" and fs["flies"] and (fs["missing"] as Array).is_empty() and String(fs["line"]) == "",
		"%s %s" % [r, fs]))
	out.append(TestResult.new("%s: removing it returns AUW, the centre of mass and the power draw to the no-GPS build exactly" % class_id,
		absf(_auw(s, catalog) - auw0) < EPS and b3.mass_properties.com_m.distance_to(com0) < COM_EPS
		and absf(b3.avionics_w() - w0) < EPS and not b3.avionics_breakdown().has("gps"), ""))
	out.append(TestResult.new("%s: a drone with no GPS has no impossible warning" % class_id,
		BuildWarning.by_severity(b3.warnings()).filter(func(w): return w.severity == BuildWarning.Severity.IMPOSSIBLE).is_empty(), ""))
	return out


static func _shelf_ids(s: DesignSession, catalog: PartsCatalog) -> Array:
	for g in s.shelf(catalog):
		if String(g["category"]) == "gps":
			return (g["parts"] as Array).map(func(p): return String(p["id"]))
	return []


## The mast tweak moves the centre of mass by m * dh / M, and nothing else about the GPS changes.
static func _the_mast_moves_the_centre(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := DesignSession.default_for_class("five_inch")
	s.swap(catalog, "gps", MASTED)
	var b45 := _build(s, catalog)
	var tw := AssemblyTweaks.from_dict(s.tweaks.to_dict())
	tw.set_mm(AssemblyTweaks.MAST_HEIGHT, 20.0)
	s.set_tweaks(tw)
	var b20 := _build(s, catalog)
	var m := _mass(catalog, MASTED) / 1000.0
	var total := b45.mass_properties.total_mass_kg
	var want_dy := -m * 0.025 / total
	var got_dy := b20.mass_properties.com_m.y - b45.mass_properties.com_m.y
	out.append(TestResult.new("a 20 mm mast tweak lowers the centre of mass by m*dh/M (45 -> 20 mm) and AUW does not move",
		absf(got_dy - want_dy) < COM_EPS and absf(b20.all_up_weight_g() - b45.all_up_weight_g()) < EPS
		and absf(b20.rise_m_for(b20.components["gps"]) - 0.020) < COM_EPS, "dy %s want %s" % [got_dy, want_dy]))
	out.append(TestResult.new("the mast tweak leaves the sideways and fore-aft centre alone",
		absf(b20.mass_properties.com_m.x - b45.mass_properties.com_m.x) < COM_EPS
		and absf(b20.mass_properties.com_m.z - b45.mass_properties.com_m.z) < COM_EPS, ""))
	return out


## GPS-rescue failsafe and the UART row follow the GPS in both directions.
static func _the_warnings(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for class_id in ["five_inch", "mapper"]:
		var s := DesignSession.default_for_class(class_id)
		if String(s.selection.get("gps", "")) != "":
			s.remove("gps")
		s.set_config(_rescue_config(), false)
		var none := _warning(_build(s, catalog), &"failsafe_gps_rescue_no_gps")
		out.append(TestResult.new("%s: GPS rescue configured and no GPS fitted raises the rescue warning" % class_id,
			none != null, ""))
		var ports0 := ControlPlausibility.serial_parts(_build(s, catalog)).size()
		s.swap(catalog, "gps", MASTED)
		var b := _build(s, catalog)
		out.append(TestResult.new("%s: fitting a GPS clears the rescue warning" % class_id,
			_warning(b, &"failsafe_gps_rescue_no_gps") == null, ""))
		var ports1 := ControlPlausibility.serial_parts(b)
		var row := _warning(b, &"serial_peripherals")
		out.append(TestResult.new("%s: fitting a GPS takes one more UART, named in the serial-peripherals row" % class_id,
			ports1.size() == ports0 + 1 and row != null and int(row.values["serial_peripherals"]) == ports1.size()
			and (row.values["peripherals"] as Array).any(func(n): return str(n).contains("GPS") or str(n) == "gps")
			and ports1.any(func(p): return p["category"] == "gps"),
			"%d -> %d %s" % [ports0, ports1.size(), str(row.values) if row != null else "no row"]))
		s.remove("gps")
		var back := _build(s, catalog)
		out.append(TestResult.new("%s: removing the GPS with rescue still on brings the warning back, and the UART with it" % class_id,
			_warning(back, &"failsafe_gps_rescue_no_gps") != null
			and ControlPlausibility.serial_parts(back).size() == ports0, ""))
		# with rescue NOT configured, removing a GPS warns nothing about rescue
		s.set_config({}, false)
		out.append(TestResult.new("%s: without GPS rescue configured, no GPS is no rescue warning" % class_id,
			_warning(_build(s, catalog), &"failsafe_gps_rescue_no_gps") == null, ""))
	return out


## The live Design Space: stack cards, None card, undo, the tile, the form, and the form refusing a mast it was not told.
static func _the_space(catalog: PartsCatalog, ids: Array) -> Array:
	var out: Array = []
	var ds := _ds("five_inch", catalog)
	ds.select("part/stack")
	var rows: Array = ds.shelf.rows.filter(func(x): return String(x["category"]) == "gps")
	out.append(TestResult.new("selecting the stack shows GPS cards, a None card first and every catalog GPS",
		rows.size() == ids.size() + 1 and String(rows[0]["id"]) == "", "%d rows" % rows.size()))
	var base := _auw(ds.session, catalog)
	var chosen := ds.choose("gps", MASTED)
	out.append(TestResult.new("clicking a GPS card fits it, the shelf marks it fitted, AUW rises by its mass",
		chosen["ok"] and ds.session.selection["gps"] == MASTED and ds.shelf.fitted.get("gps", "") == MASTED
		and absf((_auw(ds.session, catalog) - base) - _mass(catalog, MASTED)) < EPS, str(chosen)))
	var none := ds.choose("gps", "")
	out.append(TestResult.new("the None card removes it again, and undo puts it back",
		none["ok"] and ds.session.selection["gps"] == "" and ds.undo() and ds.session.selection["gps"] == MASTED, str(none)))

	# its Print tab shows the mast and nothing else
	ds.open_part_sheet("gps", "print")
	var ptab := ds.part_sheet.tab("print") as PrintTab if ds.part_sheet != null else null
	out.append(TestResult.new("the GPS Print tab shows the GPS mast only",
		ptab != null and ptab.panel.shown_parts() == ["gps_mast"],
		str(ptab.panel.shown_parts()) if ptab != null else "no tab"))
	# design your own
	ds.session.selection["gps"] = ""
	ds.refresh_shelf()
	ds.shelf.set_open(true)
	ds.shelf.expanded["gps"] = true
	ds.refresh_shelf()
	var tile := ds.shelf.find_child("AddGps", true, false) as Button
	out.append(TestResult.new("the GPS group ends in a New GPS tile", tile != null, ""))
	if tile != null:
		tile.pressed.emit()
	var form := ds.custom_form as CustomComponentDialog
	out.append(TestResult.new("pressing the tile opens the GPS form", form != null and form.category == "gps", str(form)))
	out.append(TestResult.new("open_custom_part_form accepts the gps category", ds.open_custom_part_form("gps"), ""))
	form = ds.custom_form as CustomComponentDialog
	var refused: Array = []
	if form != null:
		form.set_fields("Shed GPS", 8.0, 24.0, 24.0, 7.0, {"compass": true}, "measured")
		refused = form.submit()
	out.append(TestResult.new("the form refuses a GPS whose mast was not entered (mass in the wrong place is not defaulted)",
		not refused.is_empty(), str(refused)))
	var saved := {"id": ""}
	var probs: Array = ["unset"]
	if form != null:
		form.component_saved.connect(func(pid: String): saved["id"] = pid)
		form.set_fields("Shed GPS", 8.0, 24.0, 24.0, 7.0, {"mast_height_mm": 55.0, "compass": true}, "measured")
		probs = form.submit()
	var saved_id := String(saved["id"])
	out.append(TestResult.new("the form saves a GPS with its mast", probs.is_empty() and saved_id != "", str(probs)))
	var on_shelf := _shelf_ids(ds.session, ds._catalog)
	out.append(TestResult.new("the saved GPS is on the shelf at once", saved_id != "" and on_shelf.has(saved_id), str(on_shelf)))
	var before := _auw(ds.session, ds._catalog)
	var pick := ds.choose("gps", saved_id)
	var b := ds.session.build(ds._catalog)
	var m := 8.0 / 1000.0
	var com_before := ds.session.build(ds._catalog).mass_properties.com_m
	out.append(TestResult.new("the saved GPS can be chosen: it adds exactly 8 g and stands on its own 55 mm mast",
		pick["ok"] and ds.session.selection.get("gps", "") == saved_id and absf((_auw(ds.session, ds._catalog) - before) - 8.0) < EPS
		and absf(b.rise_m_for(b.components["gps"]) - 0.055) < COM_EPS and com_before.y > 0.0, str(pick)))
	var seat := _seat(b, b.components["gps"], 0.055)
	var parts := b.mass_parts().filter(func(p): return str(p.label) == "Shed GPS")
	out.append(TestResult.new("the custom GPS is weighed at its seat on that mast",
		parts.size() == 1 and (parts[0].position_m as Vector3).distance_to(seat) < COM_EPS and m > 0.0, ""))
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()
	out.append(TestResult.new(THE_SPACE_DONE, true, ""))
	return out
