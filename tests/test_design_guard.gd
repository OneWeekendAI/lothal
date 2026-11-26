class_name TestDesignGuard
extends RefCounted
## "New guard" on the Design Space shelf (plan item 7): the tile, the form, the store, and what a saved
## guard does to the aircraft. The guard PHYSICS (kind, R^2 inertia, clearance, fitted ring) is
## PropGuard's and is tested by "prop guard" / "guard mesh" / "guard row"; this suite proves the new
## door reaches it with the right numbers, and does not re-test it.
##
## ## Checks that could have passed while proving nothing
## - Every expected number is written out HERE from the form's own inputs (hoop volume from the
##   mean radius, the ring sized to tip + gap + wall, four rings at the motor positions), not read
##   back from the code that produced it. AUW is the DELTA against the same drone with no guard.
## - Centre of mass: the first moment is written out by hand: m*(p - com)/(M + 4m) summed.
## - Yaw inertia: the sum of m*(x^2+z^2) over the four rings, written out (tolerance covers the
##   sub-millimetre move of the centre); the full tensor is compared with `MassProperties` run on the
##   bare parts plus four hand-made rings.
## - Each refusal is checked with a form that is valid but for that one field, and the valid form is
##   checked to save, so a form that refuses everything cannot pass.
## - The user's custom-parts file is held and put back.

const CLASS_ID := "five_inch"
const REL := 1.0e-9


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	return ds


static func _fill(f: CustomGuardDialog, part_name: String, kind: String, gap: float, wall: float,
		height: float, density: float, mount: float) -> void:
	f.set_fields(part_name, kind, gap, wall, height, density, mount, "ABS", "measured on my scale")


## The ring's mass in kg, from the form's numbers, by the hoop formula written out here.
static func _ring_kg(tip_mm: float, gap: float, wall: float, height: float, density: float) -> float:
	var outer := tip_mm + gap + wall
	var mean_r := (outer - wall * 0.5) * 0.001
	return density * TAU * mean_r * height * 0.001 * wall * 0.001


static func run() -> Array:
	var out: Array = []
	var held := RealFiles.hold([CustomParts.SAVE_PATH])
	if FileAccess.file_exists(CustomParts.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomParts.SAVE_PATH))
	var catalog := PartsCatalog.load_default()
	var results := _body(catalog)
	out.append_array(results)
	out.append(TestResult.new("the guard design checks ran to their last line (a crash would drop them silently)",
		not results.is_empty() and (results[-1] as TestResult).name == "done", "%d results" % results.size()))
	held.restore()
	return out


static func _body(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var bench := ds.bench_build()
	var tip := float((bench.propeller["specs"] as Dictionary)["diameter_inches"]) * 0.0254 * 500.0

	# --- the tile and the form ------------------------------------------------------------
	out.append(TestResult.new("guard is a design-tile category: New guard",
		PartsShelf.DESIGN_TILES.has("guard") and String(PartsShelf.DESIGN_TILES["guard"][1]) == "New guard", ""))
	ds.select("part/prop/FL")
	ds.shelf.set_open(true)
	ds.shelf.expanded["guard"] = true
	ds.refresh_shelf()
	var tile := ds.shelf.find_child("AddGuard", true, false) as Button
	out.append(TestResult.new("with a prop selected the guard group ends in a New guard tile", tile != null, ""))
	if tile != null:
		tile.pressed.emit()
	var form := ds.custom_form as CustomGuardDialog
	out.append(TestResult.new("pressing the tile opens the guard form over this drone's bench", form != null and form.bench != null
		and form.bench.propeller.get("part_id", "") == bench.propeller.get("part_id", "x"), str(form)))
	out.append(TestResult.new("open_custom_part_form accepts the guard category", ds.open_custom_part_form("guard"), ""))
	form = ds.custom_form as CustomGuardDialog
	if form == null:
		out.append(TestResult.new("done", true, ""))
		return out

	# --- refusals, each on an otherwise valid form -----------------------------------------
	var saved := {"id": ""}
	form.guard_saved.connect(func(pid: String): saved["id"] = pid)
	var cases := {
		"zero gap (ring through the blade tips)": ["bumper", 0.0, 3.0, 12.0, 1050.0, 110.0, "clearance"],
		"negative gap": ["bumper", -1.0, 3.0, 12.0, 1050.0, 110.0, "tip_gap"],
		"a duct that states no gap": ["duct", NAN, 3.0, 12.0, 1050.0, 96.0, "required for a duct"],
		"a bumper whose gap is inside a tip chord (geometry says duct)": ["bumper", 0.5, 3.0, 12.0, 1050.0, 110.0, "other side"],
		"a duct whose gap is more than two tip chords (geometry says bumper)": ["duct", 30.0, 3.0, 12.0, 1050.0, 96.0, "other side"],
		"zero wall (no ring to read)": ["bumper", 6.0, 0.0, 12.0, 1050.0, 110.0, "cannot be read"],
		"zero density": ["bumper", 6.0, 3.0, 12.0, 0.0, 110.0, "cannot be read"],
	}
	for label in cases:
		var c: Array = cases[label]
		_fill(form, "Refused ring", c[0], c[1], c[2], c[3], c[4], c[5])
		var problems := form.submit()
		out.append(TestResult.new("refused: " + label,
			not problems.is_empty() and "; ".join(problems).contains(String(c[6])) and String(saved["id"]) == ""
			and CustomGuards.load_from().guards().is_empty(), str(problems)))
	_fill(form, "Refused ring", "bumper", 6.0, 3.0, 12.0, 1050.0, 110.0)
	form.set_fields("", "bumper", 6.0, 3.0, 12.0, 1050.0, 110.0, "ABS", "x")
	out.append(TestResult.new("refused: no name", not form.submit().is_empty(), ""))
	form.set_fields("Refused ring", "bumper", 6.0, 3.0, 12.0, 1050.0, 110.0, "ABS", "")
	out.append(TestResult.new("refused: no source", not form.submit().is_empty(), ""))
	var bad_text: Array[String] = []
	form.set_fields("Refused ring", "bumper", 6.0, 3.0, 12.0, 1050.0, 110.0, "ABS", "x")
	form._gap.text = "six"
	bad_text = form.submit()
	out.append(TestResult.new("refused: a tip gap that is not a number", not bad_text.is_empty() and String(saved["id"]) == "", str(bad_text)))
	var tipless := CustomGuardDialog.new(null)
	_fill(tipless, "Orphan", "bumper", 6.0, 3.0, 12.0, 1050.0, 110.0)
	out.append(TestResult.new("refused: no propeller on the bench to measure against", not tipless.submit().is_empty(), ""))
	tipless.free()

	# --- a valid guard saves ---------------------------------------------------------------
	var gap := 6.0
	var wall := 2.5
	var height := 10.0
	var rho := 1100.0
	var mount := float((bench.frame["specs"] as Dictionary)["arm_mm"])
	_fill(form, "Test Ring", "bumper", gap, wall, height, rho, mount)
	var probs := form.submit()
	var id := String(saved["id"])
	out.append(TestResult.new("a valid guard saves", probs.is_empty() and id == "custom_test_ring", str(probs)))
	var stored := CustomGuards.load_from().get_record(id)
	var want_g := _ring_kg(tip, gap, wall, height, rho) * 1000.0
	out.append(TestResult.new("the saved record carries the form's numbers and the derived mass",
		not stored.is_empty() and absf(float(stored["mass_g"]) - want_g) < 1e-9
		and float(stored["specs"]["tip_gap_mm"]) == gap and float(stored["specs"]["wall_mm"]) == wall
		and float(stored["specs"]["height_mm"]) == height and float(stored["specs"]["density_kg_m3"]) == rho
		and float(stored["specs"]["mount_radius_mm"]) == mount and String(stored["specs"]["kind"]) == "bumper"
		and absf(float(stored["specs"]["outer_radius_mm"]) - (tip + gap + wall)) < 1e-9, str(stored)))
	var on_shelf := ds._catalog.get_part(id)
	out.append(TestResult.new("the saved guard is on the shelf at once", not on_shelf.is_empty()
		and (ds._catalog.list_category("guard") as Array).any(func(p): return String(p["part_id"]) == id), ""))
	var dup := CustomGuards.load_from().add(CustomGuards.make_record("Test Ring", stored["specs"], "5\"", "ABS", "again"))
	out.append(TestResult.new("a second guard with the same name is refused by the store", not dup.is_empty(), ""))

	var forged := stored.duplicate(true)
	forged["part_id"] = "custom_forged_ring"
	forged["mass_g"] = float(stored["mass_g"]) * 0.5
	out.append(TestResult.new("a hand-edited file whose mass_g is not the ring's own geometry is refused by the store",
		not CustomGuards.load_from().add(forged).is_empty(), ""))

	# --- what it does to the aircraft ------------------------------------------------------
	var base_build := ds.session.build(ds._catalog)
	var base_auw := base_build.all_up_weight_g()
	var base_com := base_build.mass_properties.com_m
	var base_mass_kg := base_build.mass_properties.total_mass_kg
	var base_parts := base_build.mass_parts()
	var base_inertia := base_build.mass_properties.inertia
	var pick := ds.choose("guard", id)
	var b := ds.session.build(ds._catalog)
	out.append(TestResult.new("the saved guard can be fitted", pick["ok"] and String(b.guard.get("part_id", "")) == id, str(pick)))
	var m := _ring_kg(tip, gap, wall, height, rho)
	out.append(TestResult.new("AUW rises by exactly four rings",
		absf((b.all_up_weight_g() - base_auw) - 4.0 * m * 1000.0) < 1e-6,
		"%.9f g vs %.9f g" % [b.all_up_weight_g() - base_auw, 4.0 * m * 1000.0]))
	var arm_m := b.arm_m
	var moment := base_com * base_mass_kg
	var yaw_shift := 0.0
	var extra: Array = []
	for n in MotorLayout.MOTOR_NAMES:
		var p := MotorLayout.motor_position(n, arm_m)
		moment += p * m
		yaw_shift += m * (p.x * p.x + p.z * p.z)
		extra.append(PartMass.new(m, p, Vector3.ZERO, "hand ring"))
	var want_com := moment / (base_mass_kg + 4.0 * m)
	var com := b.mass_properties.com_m
	out.append(TestResult.new("the centre of mass moves by the first moment of four rings at the motors",
		(com - want_com).length() < 1e-7 and (com - base_com).length() > 1e-6, "%s vs %s (was %s)" % [com, want_com, base_com]))
	var yaw_delta := b.mass_properties.inertia.y.y - base_inertia.y.y
	out.append(TestResult.new("yaw inertia rises by the sum of m (x^2 + z^2) over the rings",
		absf(yaw_delta - yaw_shift) < yaw_shift * 1.0e-3, "%s vs %s" % [yaw_delta, yaw_shift]))
	var hand := MassProperties.compute(base_parts + extra)
	var worst := 0.0
	for col in 3:
		worst = maxf(worst, (b.mass_properties.inertia[col] - hand.inertia[col]).length())
	out.append(TestResult.new("the whole tensor equals the bare parts plus four hand-placed rings (once, not twice)",
		worst < 1.0e-8 and b.mass_properties.inertia.y.y > base_inertia.y.y, "worst %s" % worst))
	out.append(TestResult.new("the ring is sized to the fitted prop: inner wall = tip + the gap entered",
		absf(PropGuard.tip_clearance_mm(b.guard["specs"], tip) - gap) < 1e-9, str(PropGuard.tip_clearance_mm(b.guard["specs"], tip))))

	# --- defaults bit-identical -------------------------------------------------------------
	var plain := _ds(catalog)
	var ref_b := plain.session.build(catalog)
	var with_file := _ds(ds._catalog)
	var file_b := with_file.session.build(with_file._catalog)
	out.append(TestResult.new("with a custom guard saved but unfitted the default drone is bit-identical (AUW, CG, inertia, TWR)",
		file_b.all_up_weight_g() == ref_b.all_up_weight_g() and file_b.mass_properties.com_m == ref_b.mass_properties.com_m
		and file_b.mass_properties.inertia == ref_b.mass_properties.inertia
		and file_b.thrust_to_weight() == ref_b.thrust_to_weight() and file_b.guard.is_empty(), ""))
	with_file.free()
	plain.free()
	var oracle := ReferenceBuild.build()
	out.append(TestResult.new("the reference build is untouched", absf(oracle.all_up_weight_g() - 507.48) < 0.5, "%.3f" % oracle.all_up_weight_g()))

	# --- removing it restores everything ---------------------------------------------------
	var none := ds.choose("guard", "")
	var back := ds.session.build(ds._catalog)
	out.append(TestResult.new("removing the guard restores AUW, CG and inertia exactly",
		none["ok"] and back.all_up_weight_g() == base_auw and back.mass_properties.com_m == base_com
		and back.mass_properties.inertia == base_inertia, ""))

	# --- a different prop resizes the same saved guard (it is a ring for ANY prop) ---------
	ds.choose("guard", id)
	var resized := false
	var detail := "no other prop took"
	for p in catalog.list_category("propeller"):
		var d_in := float((p["specs"] as Dictionary)["diameter_inches"])
		if d_in == float((bench.propeller["specs"] as Dictionary)["diameter_inches"]):
			continue
		var trial := DesignSession.from_selection(ds.session, "propeller", String(p["part_id"]))
		var tb := trial.build(ds._catalog)
		if tb == null or tb.guard.is_empty():
			continue
		var new_tip := d_in * 0.0254 * 500.0
		var specs: Dictionary = tb.guard["specs"]
		resized = absf(PropGuard.tip_clearance_mm(specs, new_tip) - gap) < 1e-9 \
			and absf(float(specs["outer_radius_mm"]) - (new_tip + gap + wall)) < 1e-9
		detail = "%s: %s" % [p["part_id"], specs]
		break
	out.append(TestResult.new("on another prop the same saved guard keeps its entered gap (ring resized to that prop)", resized, detail))

	# --- persists ---------------------------------------------------------------------------
	ds.choose("guard", id)
	var project := Project.create("guard design")
	for cat in ds.session.selection:
		if String(ds.session.selection[cat]) != "":
			project.parts[cat] = ds.session.selection[cat]
	var reopened := Project.from_dict(project.to_dict())
	var catalog2 := PartsCatalog.load_with_custom(CustomParts.SAVE_PATH)
	var missing: Array = []
	var b2 := reopened.to_build(catalog2, missing)
	var want := ds.session.build(ds._catalog)
	out.append(TestResult.new("saved, written and reopened the guard is fitted again with the same AUW, CG and inertia",
		b2 != null and String(b2.guard.get("part_id", "")) == id and b2.all_up_weight_g() == want.all_up_weight_g()
		and b2.mass_properties.com_m == want.mass_properties.com_m
		and b2.mass_properties.inertia == want.mass_properties.inertia, str(missing)))
	var lost := reopened.to_build(PartsCatalog.load_default(), [])
	out.append(TestResult.new("without the custom file the missing guard is reported rather than fitted as a ghost", lost == null, ""))

	# --- the file: old files load, other categories survive a guard save -------------------
	var doc := JsonStore.read_document(CustomParts.SAVE_PATH)
	doc.erase("guards")
	doc["motors"] = []
	doc["schema"] = 3
	JsonStore.write_document(CustomParts.SAVE_PATH, doc, true)
	out.append(TestResult.new("an older file with no guards key loads with none", CustomGuards.load_from().guards().is_empty()
		and not PartsCatalog.load_with_custom(CustomParts.SAVE_PATH).list_category("guard").is_empty(), ""))
	var frame_ids := catalog.list_category("frame").size()
	var doc2 := JsonStore.read_document(CustomParts.SAVE_PATH)
	doc2["gps"] = [{"keep": "me"}]
	JsonStore.write_document(CustomParts.SAVE_PATH, doc2, true)
	var d := CustomGuards.load_from()
	d.add(CustomGuards.make_record("Keeper", CustomGuards.make_specs("bumper", tip + 6.0 + 3.0, 3.0, 12.0, 1050.0, 110.0, 6.0), "5\"", "ABS", "x"))
	d.save()
	var doc3 := JsonStore.read_document(CustomParts.SAVE_PATH)
	out.append(TestResult.new("saving a guard keeps the file's other arrays", doc3.has("gps") and doc3.has("guards") and frame_ids > 0, str(doc3.keys())))

	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()
	out.append(TestResult.new("done", true, ""))
	return out
