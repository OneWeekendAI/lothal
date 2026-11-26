class_name TestMountsConnector
extends RefCounted
## Item 6: the soft mount and the battery connector are choosable in the live Design Space.
##
## SOFT MOUNT (category "mount", data/parts/mounts.json): on the shelf under Motors (one set of grommets per
## motor, dropped on any of the four motor mounts), a part sheet, a None card, removable, saved and reopened.
## The physics is not duplicated: the part reaches `Build.mount`, and `SoftMount` / `VibrationModel` read it.
## The catalog carries hardness, contact area and grommet count (stiffness) and NO damping ratio (no vendor
## publishes one), so damping is the labelled band and nothing is fed to the model for it.
## CONNECTOR (data/parts/connectors.json) in the Harness tab: a picker on the plug in the schematic.
## The mass, the rating warning and the "does not mate" warning were already read off `Harness.CONNECTOR`;
## the choice is what is new, so every check goes through the choice.
##
## How each check is kept from proving nothing:
## - the golden numbers are LITERALS captured before the change (TestStrapsHarness holds the 5-inch and
##   10-inch ones), so "default reproduces today" is a comparison with the past.
## - masses are deltas against the same drone without the part, compared with the catalog row read from the
##   file, so a part that weighed nothing, twice or the wrong row fails.
## - the mount's frequency is asked of `SoftMount` with the part's own spec (not recomputed here), and the
##   three hardnesses must come out in the order their durometers say.
## - the rating warning is checked on both sides of its threshold by editing the catalog row in memory to
##   just under and just over the build's own sustained current.
## - one result per case, never a looping check that fails once.

const CLASS_ID := "five_inch"
const GLB := "res://assets/models/classes/five_inch.glb"
const EPS := 1e-9
const SOFT := "mount_grommet_50a_soft"
const STD := "mount_grommet_60a"
const FIRM := "mount_grommet_70a_firm"
const THE_END := "the mounts and connector checks ran to their last line"


static func _auw(s: DesignSession, catalog: PartsCatalog) -> float:
	var b := s.build(catalog)
	return b.all_up_weight_g() if b != null else NAN


static func _part(b: Build, label: String) -> PartMass:
	for p in b.mass_parts():
		if (p as PartMass).label == label:
			return p
	return null


static func _with_mount(id: String) -> DesignSession:
	var s := DesignSession.default_for_class(CLASS_ID)
	s.selection["mount"] = id
	return s


static func _with_harness(overrides: Dictionary) -> DesignSession:
	var s := DesignSession.default_for_class(CLASS_ID)
	if not overrides.is_empty():
		s.set_harness_overrides(overrides)
	return s


static func _warn(w: Array, id: StringName) -> BuildWarning:
	for e in w:
		if (e as BuildWarning).id == id:
			return e
	return null


static func _hz(b: Build) -> float:
	return VibrationModel.for_build(b).mount_hz()


## GLB node name -> its drawn centre, the way the shelf suite reads the model.
static func _centres(root: Node) -> Dictionary:
	var out := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("pick_"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out[String(mi.name)] = (xf * mi.get_aabb()).get_center()
	return out


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var catalog := PartsCatalog.load_default()
	out.append_array(_mount_data_and_chrome(catalog))
	out.append_array(_mount_physics(catalog))
	out.append_array(_connector_choice(catalog))
	out.append_array(_connector_warnings(catalog))
	out.append_array(_persistence(catalog))
	var live := _live(tree, catalog)
	out.append_array(live)
	out.append(TestResult.new(THE_END, not live.is_empty() and (live[-1] as TestResult).name == "the live blocks finished", ""))
	return out


# ---------------------------------------------------------------------------
# Soft mount: what the catalog has, and where the Design Space puts it
# ---------------------------------------------------------------------------

static func _mount_data_and_chrome(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var mounts: Array = catalog.list_category("mount")
	var ids: Array = mounts.map(func(p): return String(p["part_id"]))
	out.append(TestResult.new("the catalog stocks the three grommet sets the checks use", ids.has(SOFT) and ids.has(STD) and ids.has(FIRM), str(ids)))
	var no_damping := true
	for p in mounts:
		if (p["specs"] as Dictionary).has("damping_ratio"):
			no_damping = false
	out.append(TestResult.new("no catalog mount carries a damping ratio (nothing is invented; damping stays the labelled band)", no_damping, ""))
	out.append(TestResult.new("a soft mount is a shelf category, named, in the Motors slot",
		PartSnap.SHELF_CATEGORIES.has("mount") and PartSwap.SLOTS["motor"] == ["motor", "mount"]
		and String(PartSwap.CATEGORY_NAMES.get("mount", "")) == "Soft mounts", str(PartSwap.SLOTS["motor"])))
	out.append(TestResult.new("it mounts on the four motor mounts, like the motor",
		PartSnap.MOUNTS_BY_CATEGORY["mount"] == PartSnap.MOUNTS_BY_CATEGORY["motor"], ""))
	out.append(TestResult.new("it has a part sheet",
		PartSheetTabs.SHELF_CATEGORIES_WITH_SHEET.has("mount")
		and PartSheetTabs.for_category("mount").map(func(t): return String(t["id"])) == ["sheet"], ""))
	out.append(TestResult.new("it is optional: it can be left off, and the session carries the key",
		PartSwap.can_be_empty("mount") and DesignSession.default_for_class(CLASS_ID).selection.has("mount"), ""))
	var nums: Array = PartSwap.deciding_numbers(catalog.get_part(SOFT), "mount")
	out.append(TestResult.new("the shelf card names the hardness and the grommet count (not the milligram mass)",
		nums == ["50A Shore", "4 per motor"], str(nums)))
	out.append(TestResult.new("the shelf caption is the durometer", PartCaption.key_spec(catalog.get_part(FIRM), "mount") == "Shore 70A",
		PartCaption.key_spec(catalog.get_part(FIRM), "mount")))
	var spec: Dictionary = PartColour.spec_of("mount")
	out.append(TestResult.new("the icon fill is hardness", String(spec["key"]) == "shore_a"
		and PartColour.value_of(catalog.get_part(SOFT), "mount") == 50.0, str(spec)))
	return out


static func _mount_physics(catalog: PartsCatalog) -> Array:
	var out: Array = []
	# --- the default is today's aircraft, exactly: no mount, no pad, nothing resolved
	var base := DesignSession.default_for_class(CLASS_ID).build(catalog)
	out.append(TestResult.new("default 5-inch: AUW, centre of mass and inertia are today's, exactly",
		base.all_up_weight_g() == TestStrapsHarness.GOLD_AUW and base.mass_properties.com_m == TestStrapsHarness.GOLD_COM
		and base.mass_properties.inertia == TestStrapsHarness.GOLD_INERTIA, "%.12f" % base.all_up_weight_g()))
	out.append(TestResult.new("default 5-inch: no mount fitted, no pad (tier no_mount), assembly untouched",
		base.mount.is_empty() and VibrationModel.for_build(base).mount_tier() == "no_mount" and base.assembly.is_empty(), str(base.assembly)))
	var b_none := _with_mount("").build(catalog)
	out.append(TestResult.new("choosing 'none' by name builds exactly the default", b_none.all_up_weight_g() == base.all_up_weight_g()
		and b_none.mass_properties.com_m == base.mass_properties.com_m and b_none.mass_properties.inertia == base.mass_properties.inertia, ""))

	var hzs := {}
	for id in [SOFT, STD, FIRM]:
		var part := catalog.get_part(id)
		var s := _with_mount(id)
		var b := s.build(catalog)
		var each_g: float = float(part["mass_g"])
		out.append(TestResult.new("%s: AUW is the no-mount AUW plus four sets (one per motor), read from the catalog row" % id,
			absf((b.all_up_weight_g() - base.all_up_weight_g()) - 4.0 * each_g) < 1e-9,
			"%.9f vs %.9f" % [b.all_up_weight_g() - base.all_up_weight_g(), 4.0 * each_g]))
		var at_motors := true
		for m in MotorLayout.MOTOR_NAMES:
			var p := _part(b, "Soft mount %s" % m)
			if p == null or p.position_m.distance_to(MotorLayout.motor_position(m, b.arm_m)) > 1e-9 or absf(p.mass_kg * 1000.0 - each_g) > 1e-9:
				at_motors = false
		out.append(TestResult.new("%s: one set is weighed at each of the four motors" % id, at_motors, ""))
		var model := VibrationModel.for_build(b)
		out.append(TestResult.new("%s: the vibration model reads the pad (tier computed, finite frequency)" % id,
			model.mount_tier() == "computed" and is_finite(model.mount_hz()), model.mount_tier()))
		# the model's own function, asked with this part's own spec and the pad thickness the part declares
		var want_hz := SoftMount.f_n_hz(float(part["specs"]["thickness_mm"]) / 1000.0, model.tip_load_kg, SoftMount.spec_from_part(part))
		out.append(TestResult.new("%s: the frequency is SoftMount's answer for this part at its own thickness" % id,
			absf(model.mount_hz() - want_hz) < 1e-9 and want_hz > 0.0, "%.6f vs %.6f" % [model.mount_hz(), want_hz]))
		hzs[id] = model.mount_hz()
	out.append(TestResult.new("harder grommets ring higher: 50A < 60A < 70A",
		hzs[SOFT] < hzs[STD] and hzs[STD] < hzs[FIRM], str(hzs)))
	# a different part id reaches the vibration model: swapping hardness changes the frequency, not the mass
	out.append(TestResult.new("hardness changes the frequency and not the weight",
		_auw(_with_mount(SOFT), catalog) == _auw(_with_mount(FIRM), catalog) and hzs[SOFT] != hzs[FIRM], ""))
	# the centre of mass is the weighted mean of the old parts and the four sets at the four motors
	var bs := _with_mount(STD).build(catalog)
	var m_each := float(catalog.get_part(STD)["mass_g"]) / 1000.0
	var m0 := base.mass_properties.total_mass_kg
	var acc := base.mass_properties.com_m * m0
	for m in MotorLayout.MOTOR_NAMES:
		acc += MotorLayout.motor_position(m, bs.arm_m) * m_each
	var want_com: Vector3 = acc / (m0 + 4.0 * m_each)
	out.append(TestResult.new("the centre of mass moves by exactly the first moment of the four sets at the four motors",
		bs.mass_properties.com_m.distance_to(want_com) < 1e-7 and bs.mass_properties.com_m != base.mass_properties.com_m,
		"%s vs %s" % [bs.mass_properties.com_m, want_com]))
	# an unknown id reads as no mount: nothing is substituted
	var ghost := _with_mount("mount_nope").build(catalog)
	out.append(TestResult.new("a mount id the catalog does not know does not build a pad", ghost == null or ghost.mount.is_empty(), ""))
	# other tweaks still win: a design with a tweak builds its pad from the tweak's resolved assembly
	var s_tw := _with_mount(STD)
	var tw := AssemblyTweaks.new()
	tw.set_mm(AssemblyTweaks.SOFT_MOUNT, 2.0)
	s_tw.set_tweaks(tw)
	var b_tw := s_tw.build(catalog)
	out.append(TestResult.new("an authored pad thickness (2 mm) still wins over the part's own 1 mm, and softens it",
		absf(float(b_tw.assembly_value("soft_mount_m")) - 0.002) < 1e-12 and _hz(b_tw) < hzs[STD], "%.3f" % _hz(b_tw)))
	return out


# ---------------------------------------------------------------------------
# Connector: the choice
# ---------------------------------------------------------------------------

static func _connector_choice(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var conns: Array = catalog.list_category("connector")
	var ids: Array = conns.map(func(p): return String(p["part_id"]))
	out.append(TestResult.new("the catalog has XT30, XT60 and XT90 among its connectors", ids.has("connector_xt30") and ids.has("connector_xt60")
		and ids.has("connector_xt90"), str(ids)))
	var base := _with_harness({}).build(catalog)
	var default_id := String(base.harness.connector_row(base).get("part_id", ""))
	out.append(TestResult.new("the default is the pack's own plug (4S 1500 -> XT60)", default_id == "connector_xt60", default_id))
	out.append(TestResult.new("choosing the default by name weighs exactly what no choice weighs",
		_auw(_with_harness({Harness.CONNECTOR: default_id}), catalog) == base.all_up_weight_g(), ""))
	var none := _with_harness({Harness.CONNECTOR: ""}).build(catalog)
	out.append(TestResult.new("None removes exactly half the default pair's mass (the aircraft carries one half)",
		absf((base.all_up_weight_g() - none.all_up_weight_g()) - float(catalog.get_part(default_id)["mass_g"]) * 0.5) < 1e-9
		and _part(none, "Connector") == null, ""))
	var pack_pos: Vector3 = base.battery_seat()["position"]
	for id in ids:
		var row := catalog.get_part(id)
		var b := _with_harness({Harness.CONNECTOR: id}).build(catalog)
		out.append(TestResult.new("%s: AUW is the no-connector AUW plus half its catalog pair mass" % id,
			absf((b.all_up_weight_g() - none.all_up_weight_g()) - float(row["mass_g"]) * 0.5) < 1e-9,
			"%.9f" % (b.all_up_weight_g() - none.all_up_weight_g())))
		var p := _part(b, "Connector")
		out.append(TestResult.new("%s: weighed at the pack lead (the pack's own seat)" % id,
			p != null and p.position_m.distance_to(pack_pos) < 1e-9 and absf(p.mass_kg * 1000.0 - float(row["mass_g"]) * 0.5) < 1e-9,
			str(p.position_m) if p != null else "none"))
	# the position follows the pack: slide the pack and the connector goes with it
	var s_off := _with_harness({Harness.CONNECTOR: "connector_xt90"})
	var tw := AssemblyTweaks.new()
	tw.set_mm(AssemblyTweaks.BATTERY_OFFSET, 10.0)
	s_off.set_tweaks(tw)
	var b_off := s_off.build(catalog)
	var moved: Vector3 = b_off.battery_seat()["position"]
	out.append(TestResult.new("slide the pack 10 mm and the connector follows it",
		moved.distance_to(pack_pos) > 1e-4 and _part(b_off, "Connector").position_m.distance_to(moved) < 1e-9, ""))
	# the pigtail is not counted on top of the lead (the schema's double-count rule)
	var h := _with_harness({Harness.CONNECTOR: "connector_xt60h"}).build(catalog)
	out.append(TestResult.new("the XT60H's pigtail mass is not added on top of the lead (only half its pair mass)",
		absf(h.harness.connector_mass_g(h) - 4.0) < 1e-9, "%.3f" % h.harness.connector_mass_g(h)))
	# burst is shown and never a limit
	var xt = catalog.get_part("connector_xt30")
	var w_before := HarnessChecks.warnings_for(_with_harness({Harness.CONNECTOR: "connector_xt30"}).build(catalog)).map(func(w): return String((w as BuildWarning).id))
	var burst_was: float = xt["specs"]["burst_a"]
	xt["specs"]["burst_a"] = 1.0
	var b_burst := _with_harness({Harness.CONNECTOR: "connector_xt30"}).build(catalog)
	var w_after := HarnessChecks.warnings_for(b_burst).map(func(w): return String((w as BuildWarning).id))
	xt["specs"]["burst_a"] = burst_was
	out.append(TestResult.new("burst rating is read by nothing: setting it to 1 A changes neither warnings nor mass",
		w_before == w_after and absf(b_burst.all_up_weight_g() - _auw(_with_harness({Harness.CONNECTOR: "connector_xt30"}), catalog)) < 1e-12, str(w_before)))
	# contact resistance: carried through the existing voltage-drop check, so a worse plug sags more
	var rs := catalog.get_part("connector_xt30")
	var r_was: float = rs["specs"]["contact_resistance_ohm"]
	var v0: float = HarnessChecks.draw(_with_harness({Harness.CONNECTOR: "connector_xt30"}).build(catalog))["terminal_v"]
	out.append(TestResult.new("the XT30 and XT90 are different plugs (rows differ in rating, mass and contact resistance)",
		float(catalog.get_part("connector_xt90")["specs"]["continuous_a"]) > float(rs["specs"]["continuous_a"])
		and float(catalog.get_part("connector_xt90")["mass_g"]) > float(rs["mass_g"]) and r_was > 0.0 and v0 > 0.0, ""))
	return out


# ---------------------------------------------------------------------------
# Connector: the warnings follow the choice
# ---------------------------------------------------------------------------

static func _connector_warnings(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var base := _with_harness({}).build(catalog)
	var reading := HarnessChecks.draw(base)
	var sustained := float(reading["sustained_a"])
	out.append(TestResult.new("the default build draws a sustained current well under the XT60's 60 A (no rating warning today)",
		sustained > 0.0 and sustained < 60.0 and _warn(HarnessChecks.warnings_for(base), &"connector_rating") == null, "%.2f A" % sustained))
	# under-rated by data: PH2.0 is 5 A and this build draws about 8 A sustained
	var ph := _with_harness({Harness.CONNECTOR: "connector_ph20"}).build(catalog)
	var w := _warn(HarnessChecks.warnings_for(ph), &"connector_rating")
	out.append(TestResult.new("a PH2.0 (5 A continuous) on this build raises the limiting connector_rating warning with the rating and the draw",
		w != null and w.severity == BuildWarning.Severity.LIMITING and float(w.values["rating_a"]) == 5.0
		and absf(float(w.values["sustained_a"]) - float(HarnessChecks.draw(ph)["sustained_a"])) < 1e-9
		and absf(float(w.values["peak_a"]) - float(HarnessChecks.draw(ph)["peak_a"])) < 1e-9
		and String(w.values["connector"]) == "connector_ph20", str(w.values) if w != null else "no warning"))
	out.append(TestResult.new("the warning is the existing one (row, pin) and is not a second kind",
		w != null and WarningRows.item_of(w.id, w.values) == WarningRows.HARNESS and WarningPins.TABLE.has(&"connector_rating"), ""))
	for id in ["connector_xt30", "connector_xt60", "connector_xt90", "connector_bt20"]:
		out.append(TestResult.new("%s: rated above this build's sustained draw: no rating warning" % id,
			_warn(HarnessChecks.warnings_for(_with_harness({Harness.CONNECTOR: id}).build(catalog)), &"connector_rating") == null, ""))
	# the threshold itself, both sides, on the live row: a rating a hair under the draw warns, a hair over does not
	var row := catalog.get_part("connector_xt60")
	var was: float = row["specs"]["continuous_a"]
	row["specs"]["continuous_a"] = sustained - 0.01
	var under := _warn(HarnessChecks.warnings_for(_with_harness({}).build(catalog)), &"connector_rating")
	row["specs"]["continuous_a"] = sustained + 0.01
	var over := _warn(HarnessChecks.warnings_for(_with_harness({}).build(catalog)), &"connector_rating")
	row["specs"]["continuous_a"] = was
	out.append(TestResult.new("a rating 0.01 A under the draw warns; 0.01 A over does not (the threshold is the draw, strictly)",
		under != null and over == null, ""))
	# a pack that charges to more than the plug carries: a heavy build warns on an XT30 (data, not a flag)
	var cine := Build.from_ids(catalog, "frame_10in_long_range", "motor_2808_1300kv", "prop_10x5x2",
		"battery_6s_1300", "esc_4in1_80a_30x30", Build.DEFAULT_FC_ID, Build.no_components())
	var cs := float(HarnessChecks.draw(cine)["sustained_a"])
	cine.harness.set_value(Harness.CONNECTOR, "connector_ph20")
	var wc := _warn(HarnessChecks.warnings_for(cine), &"connector_rating")
	out.append(TestResult.new("the 10-inch cruiser (%.1f A sustained) on a PH2.0 warns" % cs, wc != null and float(wc.values.get("sustained_a", -1.0)) == cs, ""))
	# does not mate: the plug against the pack's own plug
	var xt30 := _with_harness({Harness.CONNECTOR: "connector_xt30"}).build(catalog)
	var mm := _warn(HarnessChecks.warnings_for(xt30), &"connector_mismatch")
	out.append(TestResult.new("an XT30 lead on the XT60 pack is the impossible 'does not mate' warning",
		mm != null and mm.severity == BuildWarning.Severity.IMPOSSIBLE and String(mm.values["pack_family"]) == "XT60"
		and String(mm.values["lead_family"]) == "XT30", ""))
	out.append(TestResult.new("the pack's own plug does not warn about mating",
		_warn(HarnessChecks.warnings_for(base), &"connector_mismatch") == null, ""))
	var none := _with_harness({Harness.CONNECTOR: ""}).build(catalog)
	out.append(TestResult.new("with no plug fitted both plug warnings are silent",
		_warn(HarnessChecks.warnings_for(none), &"connector_mismatch") == null and _warn(HarnessChecks.warnings_for(none), &"connector_rating") == null, ""))
	out.append(TestResult.new("the build's own warning list carries the choice's warning (not only the checks' function)",
		_warn(ph.warnings(), &"connector_rating") != null and _warn(base.warnings(), &"connector_rating") == null, ""))
	return out


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

static func _persistence(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var s := DesignSession.default_for_class(CLASS_ID)
	s.selection["mount"] = SOFT
	s.set_harness_overrides({Harness.CONNECTOR: "connector_xt90"})
	var want := s.build(catalog)
	var json := JSON.stringify(DesignFile.to_dict(s, "t"))
	var back := DesignFile.from_dict(JSON.parse_string(json), catalog)
	var bs: DesignSession = back.get("session") as DesignSession
	var rb: Build = bs.build(catalog) if bs != null else null
	out.append(TestResult.new("a design file carries the mount and the connector through real JSON (AUW, centre of mass, inertia, frequency identical)",
		back.get("ok", false) and rb != null and rb.all_up_weight_g() == want.all_up_weight_g()
		and rb.mass_properties.com_m == want.mass_properties.com_m and rb.mass_properties.inertia == want.mass_properties.inertia
		and _hz(rb) == _hz(want) and String(bs.selection.get("mount", "")) == SOFT
		and String(rb.harness.connector_row(rb).get("part_id", "")) == "connector_xt90", str(back.get("reason", ""))))
	# an older file: no mount key, no connector override: today's aircraft
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(DesignFile.to_dict(DesignSession.default_for_class(CLASS_ID), "t")))
	var parts_blocks := JSON.stringify(legacy)
	var lback := DesignFile.from_dict(legacy, catalog)
	var ls: DesignSession = lback.get("session") as DesignSession
	out.append(TestResult.new("a file written before either choice opens as today's aircraft, bit-identical",
		lback.get("ok", false) and ls != null and String(ls.selection.get("mount", "x")) == "" and ls.harness_overrides.is_empty()
		and ls.build(catalog).all_up_weight_g() == TestStrapsHarness.GOLD_AUW
		and ls.build(catalog).mass_properties.com_m == TestStrapsHarness.GOLD_COM and parts_blocks != "", str(lback.get("reason", ""))))
	# a project older than the mount key: the parts block has no "mount" at all
	var old_proj := DroneClass.starting_project(CLASS_ID, "t").to_dict()
	_erase_key(old_proj, "mount")
	var old_s := DesignSession.from_project(Project.from_dict(old_proj))
	out.append(TestResult.new("a project with no mount key opens with none fitted and today's aircraft",
		old_s != null and String(old_s.selection.get("mount", "x")) == "" and old_s.build(catalog).all_up_weight_g() == TestStrapsHarness.GOLD_AUW
		and old_s.build(catalog).mass_properties.com_m == TestStrapsHarness.GOLD_COM, ""))
	# the project path (autosave/reopen) too
	var proj := DroneClass.starting_project(CLASS_ID, "t")
	proj.parts["mount"] = FIRM
	proj.harness = {Harness.CONNECTOR: "connector_xt30"}
	var pback := Project.from_dict(JSON.parse_string(JSON.stringify(proj.to_dict())))
	var ps := DesignSession.from_project(pback)
	var pb := ps.build(catalog)
	out.append(TestResult.new("the project file round-trips both choices into a build with the pad and the plug",
		pb != null and String(pb.mount.get("part_id", "")) == FIRM and String(pb.harness.connector_row(pb).get("part_id", "")) == "connector_xt30"
		and VibrationModel.for_build(pb).mount_tier() == "computed", ""))
	# undo
	var us := DesignSession.default_for_class(CLASS_ID)
	us.swap(catalog, "mount", STD)
	us.swap(catalog, "mount", FIRM)
	out.append(TestResult.new("session undo steps back over a mount swap",
		us.undo() and us.selection["mount"] == STD and us.undo() and us.selection["mount"] == "", ""))
	var rm := DesignSession.default_for_class(CLASS_ID)
	var first := rm.remove("mount")
	rm.swap(catalog, "mount", STD)
	var second := rm.remove("mount")
	out.append(TestResult.new("remove('mount') refuses when nothing is fitted and takes a fitted one off",
		not first["ok"] and second["ok"] and rm.selection["mount"] == "", str(first)))
	return out


static func _erase_key(node: Variant, key: String) -> void:
	if node is Dictionary:
		(node as Dictionary).erase(key)
		for k in node:
			_erase_key(node[k], key)
	elif node is Array:
		for e in node:
			_erase_key(e, key)


# ---------------------------------------------------------------------------
# The live Design Space
# ---------------------------------------------------------------------------

static func _live(tree: SceneTree, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var mount_ids: Array = catalog.list_category("mount").map(func(p): return String(p["part_id"]))
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)

	# --- the shelf: selecting a motor opens Motors and Soft mounts, with a None card
	ds.select("part/motor/FL")
	var rows: Array = ds.shelf.rows.filter(func(x): return String(x["category"]) == "mount")
	out.append(TestResult.new("selecting a motor shows Soft mount cards: None first, then every catalog set",
		rows.size() == mount_ids.size() + 1 and not rows.is_empty() and String(rows[0]["id"]) == "" and ds.shelf.expanded.has("mount") and ds.shelf.expanded.has("motor"),
		"%d rows %s" % [rows.size(), str(ds.shelf.expanded)]))
	var base_auw := _auw(ds.session, catalog)
	var chosen := ds.choose("mount", SOFT)
	var each: float = float(catalog.get_part(SOFT)["mass_g"])
	out.append(TestResult.new("clicking a Soft mount card fits it: the shelf marks it, AUW rises by four sets",
		chosen["ok"] and ds.session.selection["mount"] == SOFT and ds.shelf.fitted.get("mount", "") == SOFT
		and absf((_auw(ds.session, catalog) - base_auw) - 4.0 * each) < 1e-9, str(chosen)))
	out.append(TestResult.new("the sim's build has the pad: the frequency is finite and the soft set rings below the firm one",
		is_finite(_hz(ds.session.build(catalog))), ""))
	var none := ds.choose("mount", "")
	out.append(TestResult.new("the None card removes it, back to today's weight exactly; undo puts it back",
		none["ok"] and ds.session.selection["mount"] == "" and _auw(ds.session, catalog) == base_auw
		and ds.undo() and ds.session.selection["mount"] == SOFT, str(none)))
	# a motor swap keeps the pad (the pad belongs to the aircraft, not to the motor)
	out.append(TestResult.new("the shelf lists the other two sets, not the fitted one",
		PartSnap.shelf(ds.session, catalog).filter(func(r): return String(r["category"]) == "mount").any(func(r): return (r["parts"] as Array).size() == mount_ids.size() - 1), ""))

	# --- the sheet
	var opened := ds.open_part_sheet("mount", "sheet")
	var facts := ds.part_sheet.tab("sheet") if ds.part_sheet != null else null
	var text := ""
	if facts != null:
		for c in facts.get_children():
			if c is Label:
				text += (c as Label).text + "\n"
	out.append(TestResult.new("the Soft mount sheet opens and reads hardness, contact area, grommets, frequency and damping",
		opened and text.contains("Hardness: Shore 50A") and text.contains("Contact area") and text.contains("Grommets: 4 per motor")
		and text.contains("Mount frequency") and text.contains("Hz") and text.contains("Damping: ζ 0.05–0.15 (assumed)"), text))
	out.append(TestResult.new("the sheet's mass is not rounded to nothing (0.0192 g shows as such)", text.contains("0.0192 g"), text))
	out.append(TestResult.new("the sheet's frequency is the vibration model's own",
		text.contains("%d Hz" % roundi(_hz(ds.session.build(catalog)))), text))

	# --- a drop on a motor mount fits it, on any corner, with a ghost of the four
	var root: Node = (load(GLB) as PackedScene).instantiate()
	var map := PartSnap.mount_map(root)
	var centres := _centres(root)
	for corner in PartSnap.CORNERS:
		var s := DesignSession.default_for_class(CLASS_ID)
		var v := s.drop(catalog, FIRM, (centres["motor_" + corner] as Vector3) + Vector3(0.0, 0.02, 0.0), map)
		out.append(TestResult.new("a Soft mount dropped near motor %s attaches to that motor's mount and lights all four" % corner,
			v["kind"] == "snap" and String(v["category"]) == "mount" and v["mount"] == "part/motor/" + corner
			and (v["mounts"] as Array).size() == 4 and s.selection["mount"] == FIRM and s.can_undo()
			and _auw(s, catalog) > TestStrapsHarness.GOLD_AUW, "%s %s" % [v["kind"], v["reason"]]))
	root.free()

	# --- the Harness tab: the connector picker
	var conn_ids: Array = catalog.list_category("connector").map(func(p): return String(p["part_id"]))
	var opened_h := ds.open_part_sheet("esc", "harness")
	var tab := ds.part_sheet.tab("harness") as HarnessTab if ds.part_sheet != null else null
	out.append(TestResult.new("the Harness tab opens", opened_h and tab != null and tab.room.build != null, ""))
	if tab == null or tab.room.build == null:
		ds.free()
		return out
	var room := tab.room
	var insp := room.inspector
	var sch := room.schematic
	# a click on the plug's own box selects it
	var plug_box := Rect2()
	for box in sch.geometry()["boxes"]:
		if String(box["id"]) == HarnessSchematic.CONNECTOR_ID:
			plug_box = box["rect"]
	var picked := sch.id_at(plug_box.get_center())
	out.append(TestResult.new("clicking the plug in the schematic picks the connector (and the capacitor's click still picks the capacitor)",
		plug_box.size.x > 0.0 and picked == HarnessSchematic.CONNECTOR_ID, picked))
	if picked != HarnessSchematic.CONNECTOR_ID:
		ds.free()
		out.append(TestResult.new("the live blocks finished", false, "the plug could not be picked, so the picker checks were skipped"))
		return out
	sch.select(picked)
	var picker := insp._conn_picker
	out.append(TestResult.new("selecting the plug shows a connector picker, and no gauge, length or capacitor row",
		insp._conn_row.visible and not insp._gauge_row.visible and not insp._length_row.visible and not insp._cap_row.visible, ""))
	var labels: Array = []
	for i in picker.item_count:
		labels.append(picker.get_item_text(i))
	out.append(TestResult.new("the picker lists None first, then every catalog connector in order, with its rating",
		picker.item_count == conn_ids.size() + 1 and labels[0] == "None" and insp._conn_ids == [""] + conn_ids
		and labels.size() > 1 and String(labels[conn_ids.find("connector_xt60") + 1]).contains("60 A"), str(labels)))
	out.append(TestResult.new("it starts on the pack's own plug and says 'from the parts'",
		picker.selected >= 0 and insp._conn_ids[picker.selected] == "connector_xt60" and insp._conn_note.text.begins_with("from the parts"), insp._conn_note.text))
	out.append(TestResult.new("the facts line carries the rating, the draw, the family and the source",
		insp._facts.text.contains("60 A continuous") and insp._facts.text.contains("sustained") and insp._facts.text.contains("Family XT60")
		and insp._facts.text.contains("Source:"), insp._facts.text.left(90)))
	out.append(TestResult.new("opening and rendering authored nothing", ds.session.harness_overrides.is_empty(), str(ds.session.harness_overrides)))

	var auw0 := _auw(ds.session, catalog)
	var xt90_i := conn_ids.find("connector_xt90") + 1
	picker.select(xt90_i)
	picker.item_selected.emit(xt90_i)
	out.append(TestResult.new("choosing an XT90 reaches the session's overrides",
		ds.session.harness_overrides.get(Harness.CONNECTOR, "") == "connector_xt90", str(ds.session.harness_overrides)))
	out.append(TestResult.new("and the aircraft weighs the heavier plug (half the pair mass difference)",
		absf((_auw(ds.session, catalog) - auw0) - (float(catalog.get_part("connector_xt90")["mass_g"]) - float(catalog.get_part("connector_xt60")["mass_g"])) * 0.5) < 1e-9, ""))
	out.append(TestResult.new("the inspector says authored and names the part", insp._conn_note.text.begins_with("authored") and insp._subtitle.text.contains("XT90"), insp._conn_note.text))
	out.append(TestResult.new("the XT90 on the XT60 pack puts the 'does not mate' warning in the design's own warnings",
		_warn(ds.session.build(catalog).warnings(), &"connector_mismatch") != null, ""))
	var ph_i := conn_ids.find("connector_ph20") + 1
	picker.select(ph_i)
	picker.item_selected.emit(ph_i)
	out.append(TestResult.new("choosing a PH2.0 puts the under-rated warning in the design's own warnings",
		_warn(ds.session.build(catalog).warnings(), &"connector_rating") != null, ""))
	picker.select(0)
	picker.item_selected.emit(0)
	out.append(TestResult.new("None writes an empty id and removes the plug's mass",
		ds.session.harness_overrides.get(Harness.CONNECTOR, "x") == "" and insp._subtitle.text == "none fitted"
		and absf((auw0 - _auw(ds.session, catalog)) - float(catalog.get_part("connector_xt60")["mass_g"]) * 0.5) < 1e-9, ""))
	insp.default_restored.emit(Harness.CONNECTOR)
	out.append(TestResult.new("Default drops the override: the pack's plug and today's weight are back exactly",
		not ds.session.harness_overrides.has(Harness.CONNECTOR) and _auw(ds.session, catalog) == auw0, ""))
	picker = insp._conn_picker
	picker.select(xt90_i)
	picker.item_selected.emit(xt90_i)
	room.undo()
	out.append(TestResult.new("the room's undo steps back over the connector choice",
		not ds.session.harness_overrides.has(Harness.CONNECTOR), str(ds.session.harness_overrides)))
	# selecting a wire after the plug hides the connector row again
	sch.select("main_lead")
	out.append(TestResult.new("selecting a wire after the plug hides the connector row and shows the gauge",
		not insp._conn_row.visible and insp._gauge_row.visible, ""))
	sch.select("")
	out.append(TestResult.new("selecting nothing hides it too", not insp._conn_row.visible, ""))

	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()
	out.append(TestResult.new("the live blocks finished", true, ""))
	return out
