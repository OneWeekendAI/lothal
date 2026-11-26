class_name TestStrapsHarness
extends RefCounted
## Item 5: the harness's flat 5 g "remainder" is a battery strap (a catalog part, 1 or 2 of them, at the
## pack) plus an explicit labelled sundries estimate (solder, shrink, tape, zip ties, at the origin).
## How each check is kept from passing while proving nothing:
## - the golden numbers (AUW, centre of mass, inertia) are LITERALS captured from the build BEFORE the
##   change, so "default reproduces today" is a comparison with the past, not with the new code.
## - every mass is a delta against the same drone with the strap removed, checked against the catalog
##   row read from the file, so a strap that weighed nothing, twice or the wrong row fails.
## - positions are checked analytically: with the total mass unchanged, moving a mass m from the origin
##   to the pack moves the centre of mass by exactly m * pack / M. And the inertia tensor is rebuilt
##   independently from the parts list and `MassProperties.compute`.
## - the strap follows the pack when the pack is slid, so "at the pack" is not "at where it started".
## - the wires are not charged twice: wire gauge and length leave the strap and sundries masses alone.
## - one result per case, never a looping check that fails once.

const EPS := 1e-9
const CLASS_ID := "five_inch"
const THE_END := "the straps harness checks ran to their last line"

## Captured on dev 5e265b6 (before this change) with tests/_base5.gd.
const GOLD_AUW := 507.480708465516
const GOLD_COM := Vector3(0, 0.01183166, 0.00017882453)
const GOLD_INERTIA := Basis(Vector3(0.0013882801, 0, 0), Vector3(0, 0.0024081008, -1.0602207e-07),
	Vector3(0, -1.0602207e-07, 0.0012917928))
const GOLD_CINE_AUW := 845.242691932282
const GOLD_CINE_COM := Vector3(0, 0.0077158203, 0)
const GOLD_CINE_INERTIA := Basis(Vector3(0.009611295, 0, 0), Vector3(0, 0.018732522, 0),
	Vector3(0, 0, 0.009492555))


static func _with(overrides: Dictionary) -> DesignSession:
	var s := DesignSession.default_for_class(CLASS_ID)
	if not overrides.is_empty():
		s.set_harness_overrides(overrides)
	return s


static func _part(b: Build, label: String) -> PartMass:
	for p in b.mass_parts():
		if (p as PartMass).label == label:
			return p
	return null


## A part's mass in kg, or -1 when the build has no such entry (a failing number, not a crash).
static func _kg(b: Build, label: String) -> float:
	var p := _part(b, label)
	return p.mass_kg if p != null else -1.0


static func _pos(b: Build, label: String) -> Vector3:
	var p := _part(b, label)
	return p.position_m if p != null else Vector3(1e9, 1e9, 1e9)


static func _cine(catalog: PartsCatalog) -> Build:
	return Build.from_ids(catalog, "frame_10in_long_range", "motor_2808_1300kv", "prop_10x5x2",
		"battery_6s_1300", "esc_4in1_80a_30x30", Build.DEFAULT_FC_ID, Build.no_components())


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	var straps: Array = catalog.list_category("strap")
	var ids: Array = straps.map(func(p): return String(p["part_id"]))

	# --- the data
	out.append(TestResult.new("the strap catalog has five rows, 15x200 up to 25x300", straps.size() == 5, str(ids)))
	for p in straps:
		var sp: Dictionary = p["specs"]
		out.append(TestResult.new("%s: width, length, mass and a class-typical source" % p["part_id"],
			float(sp.get("width_mm", 0.0)) > 0.0 and float(sp.get("length_mm", 0.0)) > 0.0
			and float(p.get("mass_g", 0.0)) > 0.0 and String(p.get("source", "")).contains("class-typical")
			and String(p["category"]) == "strap", String(p.get("source", "")).left(40)))
	var def_row := catalog.get_part(Harness.DEFAULT_STRAP_ID)
	out.append(TestResult.new("the default strap plus the default sundries is exactly the old 5 g remainder",
		not def_row.is_empty() and float(def_row["mass_g"]) + Harness.SUNDRIES_DEFAULT_G == Harness.REMAINDER_MASS_G
		and Harness.REMAINDER_MASS_G == 5.0, str(def_row.get("mass_g", "none"))))

	# --- defaults reproduce today, bit for bit
	var base := _with({}).build(catalog)
	out.append(TestResult.new("default 5-inch: AUW is today's 507.480708465516 g, exactly", base.all_up_weight_g() == GOLD_AUW,
		"%.12f" % base.all_up_weight_g()))
	out.append(TestResult.new("default 5-inch: centre of mass is today's, exactly", base.mass_properties.com_m == GOLD_COM,
		str(base.mass_properties.com_m)))
	out.append(TestResult.new("default 5-inch: inertia tensor is today's, exactly", base.mass_properties.inertia == GOLD_INERTIA,
		str(base.mass_properties.inertia)))
	var cine := _cine(catalog)
	out.append(TestResult.new("default 10-inch long range: AUW, centre of mass and inertia are today's, exactly",
		cine.all_up_weight_g() == GOLD_CINE_AUW and cine.mass_properties.com_m == GOLD_CINE_COM
		and cine.mass_properties.inertia == GOLD_CINE_INERTIA, "%.12f" % cine.all_up_weight_g()))
	var lump := _part(base, "Harness remainder")
	out.append(TestResult.new("by default the 5 g is one entry at the origin and no strap entry exists",
		lump != null and lump.position_m == Vector3.ZERO and absf(lump.mass_kg * 1000.0 - 5.0) < EPS
		and _part(base, "Battery straps") == null, ""))
	out.append(TestResult.new("the harness total still includes exactly 5 g of remainder by default",
		absf(base.harness.total_mass_g(base) - (base.harness.connector_mass_g(base) + base.harness.main_lead_mass_g(base)
			+ 4.0 * base.harness.motor_lead_mass_g(base) + base.harness.capacitor_mass_g(base) + 5.0)) < EPS, ""))

	# --- choosing a strap: mass is the catalog's, at the pack
	var none_s := _with({Harness.STRAP: ""}).build(catalog)
	out.append(TestResult.new("no strap leaves exactly the sundries (2.5 g) at the origin",
		absf((base.all_up_weight_g() - none_s.all_up_weight_g()) - 2.5) < 1e-6
		and _part(none_s, "Battery straps") == null
		and absf(_kg(none_s, "Harness remainder") * 1000.0 - 2.5) < EPS, ""))
	var pack_pos: Vector3 = base.battery_seat()["position"]
	for id in ids:
		var mass: float = float(catalog.get_part(id)["mass_g"])
		var b1 := _with({Harness.STRAP: id}).build(catalog)
		out.append(TestResult.new("%s: AUW is the no-strap AUW plus its catalog mass" % id,
			absf((b1.all_up_weight_g() - none_s.all_up_weight_g()) - mass) < 1e-6, "%.6f" % b1.all_up_weight_g()))
		var sp := _part(b1, "Battery straps")
		out.append(TestResult.new("%s: weighed at the pack's seat" % id,
			sp != null and sp.position_m.distance_to(pack_pos) < 1e-9 and absf(sp.mass_kg * 1000.0 - mass) < 1e-9,
			str(sp.position_m) if sp != null else "none"))
		var b2 := _with({Harness.STRAP: id, Harness.STRAP_COUNT: 2}).build(catalog)
		out.append(TestResult.new("%s: two of them weigh twice" % id,
			absf((b2.all_up_weight_g() - none_s.all_up_weight_g()) - 2.0 * mass) < 1e-6, ""))
	out.append(TestResult.new("count is read clamped: 0 is one, 9 is two, 1.6 is two",
		absf(_with({Harness.STRAP_COUNT: 0}).build(catalog).harness.strap_mass_g(base) - 2.5) < EPS
		and absf(_with({Harness.STRAP_COUNT: 9}).build(catalog).harness.strap_mass_g(base) - 5.0) < EPS
		and absf(_with({Harness.STRAP_COUNT: 1.6}).build(catalog).harness.strap_mass_g(base) - 5.0) < EPS, ""))
	out.append(TestResult.new("an unknown strap id weighs nothing and does not crash",
		absf(_with({Harness.STRAP: "strap_nope"}).build(catalog).all_up_weight_g() - none_s.all_up_weight_g()) < EPS, ""))

	# --- choosing the default strap by name keeps the mass, and moves it to the pack (analytic centre of mass)
	var named := _with({Harness.STRAP: Harness.DEFAULT_STRAP_ID}).build(catalog)
	out.append(TestResult.new("choosing the default strap by name weighs exactly what no choice weighs",
		absf(named.all_up_weight_g() - base.all_up_weight_g()) < 1e-9, "%.9f" % named.all_up_weight_g()))
	var want_com := base.mass_properties.com_m + (2.5 / 1000.0) * pack_pos / base.mass_properties.total_mass_kg
	out.append(TestResult.new("and the centre of mass moves by exactly m * pack / M toward the pack",
		named.mass_properties.com_m.distance_to(want_com) < 1e-9 and named.mass_properties.com_m != base.mass_properties.com_m,
		"%s vs %s" % [named.mass_properties.com_m, want_com]))
	# the inertia tensor, rebuilt independently from the same parts with the lump split by hand
	var rebuilt: Array = []
	for p in named.mass_parts():
		if (p as PartMass).label != "Battery straps" and (p as PartMass).label != "Harness remainder":
			rebuilt.append(p)
	rebuilt.append(PartMass.new(0.0025, pack_pos, InertiaPrimitives.box(0.0025, named.battery_size_m()), "s"))
	rebuilt.append(PartMass.new(0.0025, Vector3.ZERO, InertiaPrimitives.box(0.0025, Build.ELECTRONICS_SIZE_M), "r"))
	var mp := MassProperties.compute(rebuilt)
	var di: Basis = mp.inertia
	var gi: Basis = named.mass_properties.inertia
	out.append(TestResult.new("the inertia tensor equals the independent rebuild with the strap at the pack",
		absf(di.x.x - gi.x.x) < 1e-12 and absf(di.y.y - gi.y.y) < 1e-12 and absf(di.z.z - gi.z.z) < 1e-12
		and absf(di.y.z - gi.y.z) < 1e-12 and mp.com_m.distance_to(named.mass_properties.com_m) < 1e-12, ""))
	out.append(TestResult.new("the inertia is not the default's (the strap really left the origin)",
		named.mass_properties.inertia != base.mass_properties.inertia, ""))

	var count_only := _with({Harness.STRAP_COUNT: 2}).build(catalog)
	out.append(TestResult.new("a count alone is a choice: two default straps at the pack, 5 g, none left in the lump",
		absf(_kg(count_only, "Battery straps") * 1000.0 - 5.0) < EPS and _pos(count_only, "Battery straps").distance_to(pack_pos) < 1e-9
		and absf(_kg(count_only, "Harness remainder") * 1000.0 - 2.5) < EPS, ""))
	var strap_only := _with({Harness.STRAP: "strap_15x200_nylon"}).build(catalog)
	out.append(TestResult.new("a type alone is a choice: one strap at the pack, count defaulting to 1",
		absf(_kg(strap_only, "Battery straps") * 1000.0 - 1.5) < EPS, ""))

	# --- the strap rides with the pack when the pack is slid
	var tw := AssemblyTweaks.new()
	tw.set_mm(AssemblyTweaks.BATTERY_OFFSET, 12.0)
	var slid := DesignSession.default_for_class(CLASS_ID)
	slid.set_harness_overrides({Harness.STRAP: Harness.DEFAULT_STRAP_ID})
	slid.set_tweaks(tw)
	var sb := slid.build(catalog)
	var slid_pos: Vector3 = sb.battery_seat()["position"]
	var ssp := _part(sb, "Battery straps")
	out.append(TestResult.new("slide the pack 12 mm and the strap goes with it (and the pack really moved)",
		ssp != null and ssp.position_m.distance_to(slid_pos) < 1e-9 and slid_pos.distance_to(pack_pos) > 0.005,
		"%s vs %s" % [str(ssp.position_m) if ssp != null else "none", slid_pos]))
	var lump_slid := _part(sb, "Harness remainder")
	out.append(TestResult.new("while the sundries stay at the origin",
		lump_slid != null and lump_slid.position_m == Vector3.ZERO, ""))

	# --- the sundries estimate
	var s0 := _with({Harness.SUNDRIES_G: 0.0}).build(catalog)
	out.append(TestResult.new("sundries 0 removes 2.5 g and leaves the default strap's 2.5 g in the origin lump",
		absf((base.all_up_weight_g() - s0.all_up_weight_g()) - 2.5) < 1e-6
		and absf(_kg(s0, "Harness remainder") * 1000.0 - 2.5) < EPS, ""))
	var s75 := _with({Harness.SUNDRIES_G: 7.5}).build(catalog)
	out.append(TestResult.new("sundries 7.5 adds exactly 5 g, at the origin",
		absf((s75.all_up_weight_g() - base.all_up_weight_g()) - 5.0) < 1e-6
		and _pos(s75, "Harness remainder") == Vector3.ZERO, ""))
	out.append(TestResult.new("a negative sundries box is floored at zero",
		absf(_with({Harness.SUNDRIES_G: -3.0}).build(catalog).all_up_weight_g() - s0.all_up_weight_g()) < EPS, ""))
	var both := _with({Harness.STRAP: "strap_25x300_rubber", Harness.STRAP_COUNT: 2, Harness.SUNDRIES_G: 4.0}).build(catalog)
	out.append(TestResult.new("strap, count and sundries combine: 2 x 5 g at the pack and 4 g at the origin",
		absf(_kg(both, "Battery straps") * 1000.0 - 10.0) < EPS
		and absf(_kg(both, "Harness remainder") * 1000.0 - 4.0) < EPS
		and absf((both.all_up_weight_g() - base.all_up_weight_g()) - 9.0) < 1e-6, ""))

	# --- mass identity: the harness total is the sum of its entries, and the wire is not charged twice
	var labels := ["Connector", "Main lead", "Motor lead", "Capacitor", "Battery straps", "Harness remainder"]
	var sum_g := 0.0
	for p in both.mass_parts():
		for l in labels:
			if String((p as PartMass).label).begins_with(l):
				sum_g += (p as PartMass).mass_kg * 1000.0
				break
	out.append(TestResult.new("the harness total equals the sum of its entries in the mass list",
		absf(sum_g - both.harness.total_mass_g(both)) < 1e-9, "%.6f vs %.6f" % [sum_g, both.harness.total_mass_g(both)]))
	out.append(TestResult.new("the electronics total follows the harness (strap change moves it by the same grams)",
		absf((both.electronics_mass_g() - base.electronics_mass_g()) - 9.0) < 1e-6, ""))
	var thick := _with({Harness.MAIN_LEAD_AWG: 12, Harness.MAIN_LEAD_LENGTH_MM: 200.0, Harness.MOTOR_LEAD_AWG: 14}).build(catalog)
	out.append(TestResult.new("rewiring changes the wire and leaves the strap and sundries masses alone",
		thick.harness.main_lead_mass_g(thick) > base.harness.main_lead_mass_g(base) + 1.0
		and thick.harness.strap_mass_g(thick) == base.harness.strap_mass_g(base)
		and thick.harness.origin_mass_g(thick) == base.harness.origin_mass_g(base), ""))

	# --- save and reopen
	var authored := {Harness.STRAP: "strap_20x250_rubber", Harness.STRAP_COUNT: 2, Harness.SUNDRIES_G: 3.5}
	var sess := _with(authored)
	var want := sess.build(catalog)
	var json := JSON.stringify(DesignFile.to_dict(sess, "t"))
	var back := DesignFile.from_dict(JSON.parse_string(json), catalog)
	var bs: DesignSession = back.get("session") as DesignSession
	var rb: Build = bs.build(catalog) if bs != null else null
	out.append(TestResult.new("a design file carries strap, count and sundries through real JSON (AUW and centre of mass identical)",
		back.get("ok", false) and rb != null and rb.all_up_weight_g() == want.all_up_weight_g()
		and rb.mass_properties.com_m == want.mass_properties.com_m
		and rb.harness.strap_count(rb) == 2 and String(rb.harness.strap_row(rb).get("part_id", "")) == "strap_20x250_rubber"
		and absf(rb.harness.sundries_mass_g(rb) - 3.5) < EPS, str(back.get("reason", ""))))
	var legacy := {Harness.MAIN_LEAD_AWG: 12.0}
	var lsess := _with(legacy)
	var lback := DesignFile.from_dict(JSON.parse_string(JSON.stringify(DesignFile.to_dict(lsess, "t"))), catalog)
	var lb: Build = (lback["session"] as DesignSession).build(catalog) if lback.get("ok", false) else null
	var ldefault := _with(legacy).build(catalog)
	out.append(TestResult.new("an older harness block without strap keys opens with the default straps (5 g lump, no strap entry)",
		lb != null and lb.all_up_weight_g() == ldefault.all_up_weight_g() and _part(lb, "Battery straps") == null
		and not lb.harness.straps_authored() and absf(lb.harness.strap_mass_g(lb) + lb.harness.sundries_mass_g(lb) - 5.0) < EPS, ""))
	var proj := DroneClass.starting_project(CLASS_ID, "t")
	proj.harness = authored.duplicate(true)
	var proj_back := Project.from_dict(JSON.parse_string(JSON.stringify(proj.to_dict())))
	var ps := DesignSession.from_project(proj_back)
	out.append(TestResult.new("the project file's harness block round-trips the strap keys into an identical build",
		ps != null and ps.build(catalog).all_up_weight_g() == want.all_up_weight_g()
		and ps.build(catalog).mass_properties.com_m == want.mass_properties.com_m, ""))

	# --- undo through the session
	var us := _with({})
	us.set_harness_overrides({Harness.STRAP: "strap_15x200_nylon"})
	us.set_harness_overrides({Harness.STRAP: "strap_15x200_nylon", Harness.STRAP_COUNT: 2})
	out.append(TestResult.new("session undo steps back over a strap count",
		us.undo() and us.harness_overrides == {Harness.STRAP: "strap_15x200_nylon"}, str(us.harness_overrides)))

	# --- the live tab
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	var opened := ds.open_part_sheet("esc", "harness")
	var tab := ds.part_sheet.tab("harness") as HarnessTab if ds.part_sheet != null else null
	out.append(TestResult.new("the Harness tab opens", opened and tab != null and tab.room.build != null, ""))
	if tab == null or tab.room.build == null:
		ds.free()
		return out
	var room := tab.room
	var hs := room.straps
	out.append(TestResult.new("opening the tab authors nothing (rendering is not an edit)", ds.session.harness_overrides.is_empty(),
		str(ds.session.harness_overrides)))
	var labels_ui: Array = []
	for i in hs._strap_picker.item_count:
		labels_ui.append(hs._strap_picker.get_item_text(i))
	out.append(TestResult.new("the picker lists None first, then every catalog strap in order",
		hs._strap_picker.item_count == ids.size() + 1 and labels_ui[0] == "None" and hs._strap_ids == [""] + ids, str(labels_ui)))
	out.append(TestResult.new("it starts on the default strap, count 1, sundries 2.5 est., and says so",
		hs._strap_ids[hs._strap_picker.selected] == Harness.DEFAULT_STRAP_ID and hs._count_spin.value == 1.0
		and absf(hs._sundries_spin.value - 2.5) < EPS and hs._strap_note.text.begins_with("from the parts")
		and hs._sundries_note.text.contains("estimate") and hs._sundries_spin.suffix.contains("est."),
		hs._strap_note.text))
	out.append(TestResult.new("the facts line names the mass, the size and the source",
		hs._facts.text.contains("2.5 g") and hs._facts.text.contains("20 x 250") and hs._facts.text.contains("Source:"),
		hs._facts.text.left(80)))
	var auw0 := base.all_up_weight_g()
	var pick := ids.find("strap_25x300_rubber") + 1
	hs._strap_picker.select(pick)
	hs._strap_picker.item_selected.emit(pick)
	out.append(TestResult.new("picking a strap reaches the session's overrides and the build's weight",
		ds.session.harness_overrides.get(Harness.STRAP, "") == "strap_25x300_rubber"
		and absf(ds.session.build(catalog).all_up_weight_g() - (auw0 - 2.5 + 5.0)) < 1e-6,
		str(ds.session.harness_overrides)))
	out.append(TestResult.new("the note now says authored, at the pack", hs._strap_note.text.begins_with("authored"), hs._strap_note.text))
	hs._count_spin.value = 2.0
	out.append(TestResult.new("the count box writes a 2 and doubles the strap mass",
		int(ds.session.harness_overrides.get(Harness.STRAP_COUNT, 0)) == 2
		and absf(ds.session.build(catalog).all_up_weight_g() - (auw0 - 2.5 + 10.0)) < 1e-6, str(ds.session.harness_overrides)))
	hs._sundries_spin.value = 1.0
	out.append(TestResult.new("the sundries box writes its estimate and the weight follows",
		absf(float(ds.session.harness_overrides.get(Harness.SUNDRIES_G, 0.0)) - 1.0) < EPS
		and absf(ds.session.build(catalog).all_up_weight_g() - (auw0 - 2.5 + 10.0 - 1.5)) < 1e-6, ""))
	out.append(TestResult.new("the facts line follows the edit",
		hs._facts.text.contains("10.0 g") and hs._facts.text.contains("1.0 g, est."), hs._facts.text.left(60)))
	room.undo()
	out.append(TestResult.new("the room's undo steps back over the sundries edit",
		not ds.session.harness_overrides.has(Harness.SUNDRIES_G) and absf(hs._sundries_spin.value - 2.5) < EPS, str(ds.session.harness_overrides)))
	var b_strap := hs.find_child("Default_" + Harness.STRAP, true, false) as Button
	var b_count := hs.find_child("Default_" + Harness.STRAP_COUNT, true, false) as Button
	out.append(TestResult.new("each row has its own Default button", b_strap != null and b_count != null
		and hs.find_child("Default_" + Harness.SUNDRIES_G, true, false) != null, ""))
	if b_strap != null and b_count != null:
		b_strap.pressed.emit()
		b_count.pressed.emit()
	out.append(TestResult.new("Default on strap and count drops both overrides; the 5 g lump and today's AUW are back",
		not ds.session.harness_overrides.has(Harness.STRAP) and not ds.session.harness_overrides.has(Harness.STRAP_COUNT)
		and ds.session.build(catalog).all_up_weight_g() == GOLD_AUW and ds.session.build(catalog).mass_properties.com_m == GOLD_COM, str(ds.session.harness_overrides)))
	hs._strap_picker.select(0)
	hs._strap_picker.item_selected.emit(0)
	out.append(TestResult.new("None writes an empty strap id and removes the strap's mass",
		ds.session.harness_overrides.get(Harness.STRAP, "x") == ""
		and absf(ds.session.build(catalog).all_up_weight_g() - (auw0 - 2.5)) < 1e-6, ""))
	ds.free()
	out.append(TestResult.new(THE_END, true, ""))
	return out
