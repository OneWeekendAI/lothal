class_name TestCapacitorChoice
extends RefCounted
## The capacitor is choosable in the live Design Space's Harness tab: None, or any row of
## data/parts/capacitors.json. Checks that could have passed while proving nothing, and how each is
## kept honest:
## - every AUW figure is read off a Build the test makes itself (DesignSession.build) and compared with
##   the catalog row's `mass_g` read from the file, as a delta against the SAME drone with no capacitor,
##   so a capacitor that weighed nothing, twice, or the default one regardless of the choice, fails.
## - the seat is worked out here from the stack mount and the ESC board height, not read from the
##   build's own capacitor accessors.
## - the voltage rule is checked on both sides (the under-rated part warns, the adequate one does not)
##   and with the HV figure (4.35 V per cell) in the message values.
## - the picker is driven through its own signal (select + item_selected), the room applies it.
## - ESR and ripple: capacitors.json's esr_ohm is shown and read by no check; two capacitors that differ
##   only in ESR must weigh and warn identically (nothing models ESR, and the suite says so).
## - one result per case, never a looping check that fails once.

const CLASS_ID := "five_inch"
const EPS := 1e-9
const THE_END := "the capacitor choice checks ran to their last line"


static func _auw(s: DesignSession, catalog: PartsCatalog) -> float:
	var b := s.build(catalog)
	return b.all_up_weight_g() if b != null else NAN


static func _cap_id(s: DesignSession, catalog: PartsCatalog) -> String:
	var b := s.build(catalog)
	return String(b.harness.capacitor_row(b).get("part_id", ""))


static func _with(_catalog: PartsCatalog, overrides: Dictionary) -> DesignSession:
	var s := DesignSession.default_for_class(CLASS_ID)
	if not overrides.is_empty():
		s.set_harness_overrides(overrides)
	return s


static func _cap_part(b: Build) -> PartMass:
	for p in b.mass_parts():
		if (p as PartMass).label == "Capacitor":
			return p
	return null


static func _warn(w: Array, id: StringName) -> BuildWarning:
	for e in w:
		if (e as BuildWarning).id == id:
			return e
	return null


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	var caps: Array = catalog.list_category("capacitor")
	var ids: Array = caps.map(func(p): return String(p["part_id"]))

	# --- the data
	var volts: Array = caps.map(func(p): return float(p["specs"]["voltage_v"]))
	var ufs: Array = caps.map(func(p): return float(p["specs"]["capacitance_uf"]))
	out.append(TestResult.new("the catalog has 25, 35 and 50 V parts and 470, 680 and 1000 uF parts",
		volts.has(25.0) and volts.has(35.0) and volts.has(50.0)
		and ufs.has(470.0) and ufs.has(680.0) and ufs.has(1000.0), "%s / %s" % [volts, ufs]))
	for p in caps:
		var s: Dictionary = p["specs"]
		out.append(TestResult.new("%s: capacitance, rating, ESR, size, mass and a typical-labelled source" % p["part_id"],
			float(s.get("capacitance_uf", 0.0)) > 0.0 and float(s.get("voltage_v", 0.0)) > 0.0
			and float(s.get("esr_ohm", 0.0)) > 0.0 and float(s.get("diameter_mm", 0.0)) > 0.0
			and float(s.get("height_mm", 0.0)) > 0.0 and float(p.get("mass_g", 0.0)) > 0.0
			and String(p.get("source", "")).contains("class-typical"), String(p.get("source", "")).left(40)))

	# --- the default is today's part, to the gram and the millimetre
	var base := _with(catalog, {})
	var default_id := _cap_id(base, catalog)
	out.append(TestResult.new("a design with no capacitor choice keeps today's default (4S -> 470 uF 35 V, 3.5 g)",
		default_id == "cap_470uf_35v" and absf(float(catalog.get_part(default_id)["mass_g"]) - 3.5) < EPS, default_id))
	var auw_default := _auw(base, catalog)
	var auw_none := _auw(_with(catalog, {Harness.CAPACITOR: ""}), catalog)
	out.append(TestResult.new("choosing the default part by name weighs exactly what no choice weighs",
		_auw(_with(catalog, {Harness.CAPACITOR: default_id}), catalog) == auw_default, "%.9f" % auw_default))
	out.append(TestResult.new("None removes exactly the default part's mass",
		absf((auw_default - auw_none) - 3.5) < 1e-6, "%.6f -> %.6f" % [auw_default, auw_none]))
	out.append(TestResult.new("None leaves no capacitor in the mass list and no capacitor row",
		_cap_part(_with(catalog, {Harness.CAPACITOR: ""}).build(catalog)) == null
		and _cap_id(_with(catalog, {Harness.CAPACITOR: ""}), catalog) == "", ""))

	# --- every part: AUW by exact delta, seat on the ESC pads
	var seat_b := base.build(catalog)
	var stack_seat := MountLayout.by_id(seat_b.mount_points(), "stack")
	var want_seat: Vector3 = stack_seat.position + Vector3(0.0, StackMesh.BOARD_THICKNESS_M * 0.5, 0.0)
	for id in ids:
		var s := _with(catalog, {Harness.CAPACITOR: id})
		var b := s.build(catalog)
		out.append(TestResult.new("%s: AUW is the no-capacitor AUW plus its catalog mass" % id,
			absf((_auw(s, catalog) - auw_none) - float(catalog.get_part(id)["mass_g"])) < 1e-6,
			"%.6f vs %.6f + %s" % [_auw(s, catalog), auw_none, catalog.get_part(id)["mass_g"]]))
		var part := _cap_part(b)
		out.append(TestResult.new("%s: weighed on the ESC pads (stack seat + half the board)" % id,
			part != null and part.position_m.distance_to(want_seat) < 1e-6
			and absf(part.mass_kg * 1000.0 - float(catalog.get_part(id)["mass_g"])) < 1e-6,
			"%s vs %s" % [str(part.position_m) if part != null else "none", want_seat]))
	var heavy := _with(catalog, {Harness.CAPACITOR: "cap_1000uf_35v"}).build(catalog)
	var light := _with(catalog, {Harness.CAPACITOR: "cap_100uf_16v"}).build(catalog)
	out.append(TestResult.new("the can's own box follows the part (a 12.5 x 20 mm can has more roll inertia than a 6.3 x 11)",
		heavy.mass_properties.inertia.x.x > light.mass_properties.inertia.x.x + 1e-12, ""))

	# --- the voltage rule
	var cine := Build.from_ids(catalog, "frame_10in_long_range", "motor_2808_1300kv", "prop_10x5x2",
		"battery_6s_1300", "esc_4in1_80a_30x30", Build.DEFAULT_FC_ID, Build.no_components())
	var cine_default := _warn(HarnessChecks.warnings_for(cine), &"capacitor_voltage")
	out.append(TestResult.new("6S with the default 35 V part: no voltage warning", cine_default == null, ""))
	cine.harness.set_value(Harness.CAPACITOR, "cap_470uf_25v")
	var w25 := _warn(HarnessChecks.warnings_for(cine), &"capacitor_voltage")
	out.append(TestResult.new("6S with a 25 V part (pack charges to 25.2 V): a limiting capacitor_voltage warning",
		w25 != null and w25.severity == BuildWarning.Severity.LIMITING
		and absf(float(w25.values["pack_full_v"]) - 25.2) < 1e-9 and float(w25.values["rated_v"]) == 25.0, ""))
	cine.harness.set_value(Harness.CAPACITOR, "cap_470uf_50v")
	out.append(TestResult.new("6S with a 50 V part: no voltage warning",
		_warn(HarnessChecks.warnings_for(cine), &"capacitor_voltage") == null, ""))
	cine.harness.set_value(Harness.CAPACITOR, "")
	out.append(TestResult.new("6S with none: the existing capacitor_rule speaks and the voltage rule does not",
		_warn(HarnessChecks.warnings_for(cine), &"capacitor_voltage") == null
		and _warn(HarnessChecks.warnings_for(cine), &"capacitor_rule") != null, ""))
	var four := ReferenceBuild.build()
	four.harness.set_value(Harness.CAPACITOR, "cap_470uf_25v")
	out.append(TestResult.new("4S (16.8 V) with a 25 V part: no voltage warning",
		_warn(HarnessChecks.warnings_for(four), &"capacitor_voltage") == null, ""))
	four.harness.set_value(Harness.CAPACITOR, "cap_220uf_16v")
	var w16 := _warn(HarnessChecks.warnings_for(four), &"capacitor_voltage")
	out.append(TestResult.new("4S with a 16 V part: warns, and the pack's full voltage is 16.8",
		w16 != null and absf(float(w16.values["pack_full_v"]) - 16.8) < 1e-9, ""))
	var hv := (four.battery.duplicate(true) as Dictionary)
	(hv["specs"] as Dictionary)["chemistry"] = "LiPo HV"
	four.battery = hv
	var whv := _warn(HarnessChecks.warnings_for(four), &"capacitor_voltage")
	out.append(TestResult.new("a LiPo HV pack's full voltage is 4.35 V per cell (4S -> 17.4 V)",
		whv != null and absf(float(whv.values["pack_full_v"]) - 17.4) < 1e-9, ""))
	var pin := WarningPins.of_warning(w25, cine) if w25 != null else {}
	out.append(TestResult.new("the voltage warning has a row and a pin tag that names the rating",
		not pin.is_empty() and String(pin["tag"]) == "Capacitor under-rated · 25 V"
		and WarningRows.item_of(w25.id, w25.values) == WarningRows.HARNESS, str(pin.get("tag", ""))))

	# --- ESR is carried, not modelled
	var e1 := ReferenceBuild.build()
	e1.harness.set_value(Harness.CAPACITOR, "cap_470uf_35v")
	var warn_before := HarnessChecks.warnings_for(e1).map(func(x): return String((x as BuildWarning).id))
	var row := e1.catalog.get_part("cap_470uf_35v")
	var esr_was: float = row["specs"]["esr_ohm"]
	row["specs"]["esr_ohm"] = esr_was * 10.0
	var aw := e1.all_up_weight_g()
	var warn_after := HarnessChecks.warnings_for(e1).map(func(x): return String((x as BuildWarning).id))
	row["specs"]["esr_ohm"] = esr_was
	out.append(TestResult.new("ESR is read by nothing: x10 changes neither the warnings nor the mass",
		warn_before == warn_after and absf(aw - e1.all_up_weight_g()) < EPS, str(warn_before)))

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
	var insp := room.inspector
	room.schematic.select(HarnessSchematic.CAPACITOR_ID)
	var picker := insp._cap_picker
	out.append(TestResult.new("selecting the capacitor shows a picker, and no gauge or length",
		insp._cap_row.visible and not insp._gauge_row.visible and not insp._length_row.visible, ""))
	var labels: Array = []
	for i in picker.item_count:
		labels.append(picker.get_item_text(i))
	out.append(TestResult.new("the picker lists None first, then every catalog capacitor in order",
		picker.item_count == ids.size() + 1 and labels[0] == "None" and insp._cap_ids == [""] + ids, str(labels)))
	out.append(TestResult.new("it starts on today's default part, which it calls 'from the parts'",
		insp._cap_ids[picker.selected] == default_id and insp._cap_note.text.begins_with("from the parts"),
		insp._cap_note.text))
	out.append(TestResult.new("the facts line carries ESR, size and the source string",
		insp._facts.text.contains("ESR") and insp._facts.text.contains("Source:")
		and insp._facts.text.contains("class-typical"), insp._facts.text.left(80)))

	var pick := ids.find("cap_680uf_35v") + 1
	picker.select(pick)
	picker.item_selected.emit(pick)
	out.append(TestResult.new("choosing a part reaches the session's harness overrides",
		ds.session.harness_overrides.get(Harness.CAPACITOR, "") == "cap_680uf_35v", str(ds.session.harness_overrides)))
	out.append(TestResult.new("and the aircraft the design builds weighs the new part (exact delta)",
		absf((_auw(ds.session, catalog) - auw_none) - float(catalog.get_part("cap_680uf_35v")["mass_g"])) < 1e-6, ""))
	out.append(TestResult.new("the inspector now says 'authored' and names the part",
		insp._cap_note.text.begins_with("authored") and insp._subtitle.text.contains("680"), insp._cap_note.text))
	var none_i := 0
	picker.select(none_i)
	picker.item_selected.emit(none_i)
	out.append(TestResult.new("None writes an empty capacitor id and removes the part's mass",
		ds.session.harness_overrides.get(Harness.CAPACITOR, "x") == ""
		and absf(_auw(ds.session, catalog) - auw_none) < 1e-6 and insp._subtitle.text == "none fitted", ""))
	out.append(TestResult.new("with none fitted the existing hint appears in the build's warnings (4S: characteristic)",
		_warn(ds.session.build(catalog).warnings(), &"capacitor_rule") != null, ""))
	insp.default_restored.emit(Harness.CAPACITOR)
	out.append(TestResult.new("Default drops the override and the default part is back, AUW as before",
		not ds.session.harness_overrides.has(Harness.CAPACITOR) and _auw(ds.session, catalog) == auw_default, ""))
	picker = insp._cap_picker
	pick = ids.find("cap_470uf_50v") + 1
	picker.select(pick)
	picker.item_selected.emit(pick)
	out.append(TestResult.new("undo steps the session back over the capacitor choice",
		ds.session.undo() and not ds.session.harness_overrides.has(Harness.CAPACITOR), str(ds.session.harness_overrides)))

	# --- the design file round-trips the choice
	ds.session.set_harness_overrides({Harness.CAPACITOR: "cap_470uf_50v"})
	var want_auw := _auw(ds.session, catalog)
	var back := DesignFile.from_dict(DesignFile.to_dict(ds.session, "t"), catalog)
	var bs: DesignSession = back.get("session") as DesignSession
	out.append(TestResult.new("the design file carries the capacitor choice (AUW identical)",
		back.get("ok", false) and bs != null and _cap_id(bs, catalog) == "cap_470uf_50v"
		and _auw(bs, catalog) == want_auw, str(back.get("reason", ""))))
	ds.free()
	out.append(TestResult.new(THE_END, true, ""))
	return out
