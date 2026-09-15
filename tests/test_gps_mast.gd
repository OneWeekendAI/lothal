class_name TestGpsMast
extends RefCounted
## The GPS mast — printed-room slice PR10 (plans/2026-09-14-printed-room-plan.md, PR10).
##
## A hollow post the mast height tall, a flange at its foot and a pad for the module on top.
##
## Where each check could pass while proving nothing, and what stops it:
##   - "manifold" on an empty list: counted first; the volume is held to post + flange + pad written out.
##   - "the post follows the mast height" at the module's published 45 mm could agree with a hard-coded
##     45; it is checked at a 30 mm assembly mast (the global tweak, recorded like the tilt).
##   - "a flat GPS refuses" needs the masted GPS it accepts beside it.
##   - "mass is opt-in" on the reference build is always green, because the reference build fits no GPS:
##     the fixture FITS a masted GPS, and the reference build is checked separately with Fitted ticked.
##   - "weighed where it stands" compares the mass seat with MountLayout's own seat for the GPS bay, at
##     half the mast, computed here; a mast weighed at the origin or at the module's centre fails.

const MASTED := "gps_masted_compact"
const FLAT := "gps_micro_flat"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_the_solid_is_post_flange_and_pad(catalog))
	results.append(_the_post_follows_the_mast_height(catalog))
	results.append_array(_a_flat_or_unpublished_gps_is_refused(catalog))
	results.append(_no_gps_no_row(catalog))
	results.append(_a_mast_no_taller_than_its_pad_is_refused(catalog))
	results.append_array(_mass_is_opt_in_and_seated_on_the_mast(catalog))
	results.append(_its_guesses_are_labelled_and_fitted_from_the_panel())
	results.append(_each_guess_is_named_and_a_set_one_loses_its_marker(catalog))
	results.append(_a_moved_mast_height_is_named_on_open(catalog))
	return results


## Every guess is named against its OWN value, so a row that stops calling one of them a guess fails even
## while the other three still say "(guess)". A set bore reads without the marker.
static func _each_guess_is_named_and_a_set_one_loses_its_marker(catalog: PartsCatalog) -> TestResult:
	var build := _masted_build(catalog)
	var untouched := _mast_note(build)
	var printing := {}
	GpsMast.set_value(printing, GpsMast.BORE, 4.0)
	build.set_printing(printing)
	var edited := _mast_note(build)
	return TestResult.new(
		"untouched, the bore, wall, pad and flange are each marked a guess; a set 4 mm bore reads without the marker",
		untouched.contains("bore 3.0 mm (guess)") and untouched.contains("wall 1.6 mm (guess)")
			and untouched.contains("pad 2.0 mm (guess)") and untouched.contains("flange 14.0 mm (guess)")
			and edited.contains("bore 4.0 mm,") and edited.contains("wall 1.6 mm (guess)"),
		"untouched \"%s\" | edited \"%s\"" % [untouched, edited])


## The mast height is the GPS tweak, shared by every drone. Exported at the module's 45 mm and reopened with
## the tweak at 30 mm, the divergence must say so with both heights, not only "differs".
static func _a_moved_mast_height_is_named_on_open(catalog: PartsCatalog) -> TestResult:
	var dir := "user://exports/_test_gps_mast"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	var at_45 := _masted_build(catalog)
	var container := ProjectContainer.make(Project.create("Masted"))
	var exported := PrintedExport.export_part(at_45, GpsMast.PART_ID, dir, container)
	var at_30 := _masted_build(catalog)
	at_30.set_assembly({"mast_height_m": 0.030})
	var findings := PrintedDivergence.check(container.project, container, at_30)
	var message := ""
	for finding in findings:
		if String(finding["part"]) == GpsMast.PART_ID:
			message = String(finding["message"])
	return TestResult.new(
		"exported at 45 mm and reopened with the GPS mast at 30 mm, the message says the mast height changed from 45.0 to 30.0 mm",
		bool(exported.get("ok", false)) and message.contains("GPS mast height changed from 45.0 to 30.0 mm"),
		"exported %s; \"%s\"" % [exported.get("ok"), message])


static func _mast_note(build: Build) -> String:
	for row in PrintedParts.for_build(build):
		if String(row["id"]) == GpsMast.PART_ID:
			return String(row["note"])
	return ""


static func _masted_build(catalog: PartsCatalog) -> Build:
	var build := ReferenceBuild.build()
	build.components["gps"] = catalog.get_part(MASTED)
	build.set_printing({})
	return build


static func _the_solid_is_post_flange_and_pad(catalog: PartsCatalog) -> Array:
	var build := _masted_build(catalog)
	var d := GpsMast.dimensions(build, build.printing)
	var triangles := GpsMast.triangles_mm(d)
	var report := StlWriter.check_manifold(triangles)
	var n := float(d.get("segments", 0))
	var gon := n * 0.5 * sin(TAU / maxf(n, 1.0))
	var ri := float(d.get("bore_radius_mm", 0.0))
	var ro := float(d.get("post_outer_radius_mm", 0.0))
	# Written out here: the post annulus over the mast height, the flange slab, the pad slab.
	# PR16: the post is the mast height LESS the pad, so the module's underside is at the mast height.
	var expected := gon * (ro * ro - ri * ri) * (float(d.get("mast_height_mm", 0.0)) - float(d.get("pad_thickness_mm", 0.0))) \
		+ float(d.get("flange_mm", 0.0)) * float(d.get("flange_mm", 0.0)) * float(d.get("flange_thickness_mm", 0.0)) \
		+ 22.0 * 22.0 * float(d.get("pad_thickness_mm", 0.0))
	var volume := float(report["volume_mm3"])
	return [
		TestResult.new("the masted compact GPS's mast has triangles to check", triangles.size() > 0,
			"%d triangles" % triangles.size()),
		TestResult.new("they are closed outward shells whose volume is the post, the flange and a 22 × 22 mm pad",
			bool(report["ok"]) and expected > 0.0 and absf(volume - expected) < 1e-4 * expected,
			"ok %s, %.3f vs %.3f mm³, reasons %s" % [report["ok"], volume, expected, report["reasons"]]),
		# The weight is volume_mm3's, so it must be the solid's volume, not a second opinion of it.
		TestResult.new("the mast is weighed at the volume of the solid it exports",
			volume > 0.0 and absf(GpsMast.volume_mm3(d) - volume) < 1e-4 * volume,
			"volume_mm3 %.3f vs solid %.3f mm³" % [GpsMast.volume_mm3(d), volume]),
	]


static func _the_post_follows_the_mast_height(catalog: PartsCatalog) -> TestResult:
	var build := _masted_build(catalog)
	build.set_assembly({"mast_height_m": 0.030})
	var d := GpsMast.dimensions(build, build.printing)
	var span := _span_z(GpsMast.triangles_mm(d))
	var pad := float(d.get("pad_thickness_mm", 0.0))
	return TestResult.new(
		"with the GPS mast tweak at 30 mm (not the module's 45), the part stands 30 mm pad included — the module sits at the mast height — and records the height",
		absf(float(d.get("mast_height_mm", 0.0)) - 30.0) < 1e-6 and absf(span - 30.0) < 1e-3 and pad > 0.0,
		"mast %.3f mm, solid %.3f mm tall, pad %.2f" % [d.get("mast_height_mm", 0.0), span, pad])


static func _a_flat_or_unpublished_gps_is_refused(catalog: PartsCatalog) -> Array:
	var flat := ReferenceBuild.build()
	flat.components["gps"] = catalog.get_part(FLAT)
	var d_flat := GpsMast.dimensions(flat, {})
	var bare := ReferenceBuild.build()
	bare.components["gps"] = {"part_id": "gps_unpublished", "specs": {"mast_height_mm": 40.0}}
	var d_bare := GpsMast.dimensions(bare, {})
	var path := "user://exports/_flat_gps_mast.stl"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var written := StlWriter.write("gps_mast", GpsMast.triangles_mm(d_flat), path)
	var accepted := GpsMast.dimensions(_masted_build(catalog), {})
	return [
		TestResult.new("a flat GPS (no mast) is refused by name — there is no mast to print — and writes nothing",
			not bool(d_flat["ok"]) and String(d_flat["reason"]).begins_with("gps_mast:")
				and String(d_flat["reason"]).contains(FLAT) and not bool(written["ok"])
				and not FileAccess.file_exists(path),
			String(d_flat.get("reason", ""))),
		TestResult.new("a GPS publishing no footprint is refused naming the field, while the masted compact GPS is accepted",
			not bool(d_bare["ok"]) and String(d_bare["reason"]).contains("gps_unpublished")
				and String(d_bare["reason"]).contains("length_mm") and bool(accepted["ok"]),
			"%s; masted ok %s" % [d_bare.get("reason", ""), accepted["ok"]]),
	]


## PR16: the pad is inside the mast height, so a mast no taller than the pad leaves no post. At 4 mm with a
## 5 mm pad the part refuses naming both; at 6 mm it prints a 1 mm post.
static func _a_mast_no_taller_than_its_pad_is_refused(catalog: PartsCatalog) -> TestResult:
	var printing := {}
	GpsMast.set_value(printing, GpsMast.PAD, 5.0)
	var short := _masted_build(catalog)
	short.set_printing(printing)
	short.set_assembly({"mast_height_m": 0.004})
	var d_short := GpsMast.dimensions(short, printing)
	var tall := _masted_build(catalog)
	tall.set_printing(printing.duplicate(true))
	tall.set_assembly({"mast_height_m": 0.006})
	var d_tall := GpsMast.dimensions(tall, tall.printing)
	var reason := String(d_short.get("reason", ""))
	return TestResult.new("a 4 mm mast under a 5 mm pad is refused naming both; a 6 mm mast prints a 6 mm part",
		not bool(d_short["ok"]) and reason.begins_with("gps_mast:") and reason.contains("4.0") and reason.contains("5.0")
			and bool(d_tall["ok"]) and absf(_span_z(GpsMast.triangles_mm(d_tall)) - 6.0) < 1e-3,
		"\"%s\"; tall ok %s" % [reason, d_tall["ok"]])


static func _no_gps_no_row(catalog: PartsCatalog) -> TestResult:
	var bare := _ids(PrintedParts.for_build(ReferenceBuild.build()))
	var masted := _ids(PrintedParts.for_build(_masted_build(catalog)))
	return TestResult.new("the reference build (no GPS) lists no mast; fitting the masted GPS lists it",
		not bare.has(GpsMast.PART_ID) and masted.has(GpsMast.PART_ID), "bare %s, masted %s" % [bare, masted])


static func _mass_is_opt_in_and_seated_on_the_mast(catalog: PartsCatalog) -> Array:
	var bare_build := ReferenceBuild.build()
	var ticked := {}
	GpsMast.set_value(ticked, GpsMast.FITTED, true)
	var bare_ticked := ReferenceBuild.build()
	bare_ticked.set_printing(ticked)

	var unfitted := _masted_build(catalog)
	var fitted := _masted_build(catalog)
	fitted.set_printing(ticked.duplicate(true))
	var d := GpsMast.dimensions(fitted, fitted.printing)
	var each := GpsMast.mass_kg(d)
	var m0 := unfitted.mass_properties.total_mass_kg
	var m1 := fitted.mass_properties.total_mass_kg

	var seat := Vector3.INF
	for pm in fitted.mass_parts():
		if (pm as PartMass).label == "GPS mast":
			seat = (pm as PartMass).position_m
	var bay := MountLayout.by_id(fitted.mount_points(), String(Build.COMPONENT_MOUNTS["gps"]))
	var expected_seat := bay.position + Vector3(0.0, bay.normal * float(d.get("mast_height_mm", 0.0)) * 0.0005, 0.0) \
		if bay != null else Vector3.ZERO
	return [
		TestResult.new("the reference build weighs 507.48 g, and ticking Fitted on it adds nothing, because it fits no GPS",
			absf(bare_build.mass_properties.total_mass_kg * 1000.0 - TestHarness.REFERENCE_AUW_G) < 0.01
				and absf(bare_ticked.mass_properties.total_mass_kg - bare_build.mass_properties.total_mass_kg) < 1e-12,
			"%.3f g, ticked %.3f g" % [bare_build.mass_properties.total_mass_kg * 1000.0,
				bare_ticked.mass_properties.total_mass_kg * 1000.0]),
		TestResult.new("on a drone with the masted GPS, Fitted adds exactly the mast's mass, weighed halfway up the mast over the GPS bay",
			each > 0.0 and absf((m1 - m0) - each) < 1e-12 and seat.distance_to(expected_seat) < 1e-9,
			"+%.4f g for %.4f g; seat %s vs %s" % [(m1 - m0) * 1000.0, each * 1000.0, seat, expected_seat]),
	]


static func _its_guesses_are_labelled_and_fitted_from_the_panel() -> TestResult:
	var shell := GlassShell.new()
	var project := Project.create("Masted")
	project.parts["gps"] = MASTED
	shell.apply_project(project)
	var note := shell.lab.print_panel.row_note(GpsMast.PART_ID)
	var before := shell.lab.current_build().mass_properties.total_mass_kg
	shell.lab.print_panel.gps_mast_edited.emit(GpsMast.FITTED, true)
	var after := shell.lab.current_build().mass_properties.total_mass_kg
	var toggle := shell.lab.print_panel.fit_toggle(GpsMast.PART_ID)
	# Read BEFORE the shell is freed: the toggle is the shell's child and goes with it.
	var pressed := toggle != null and toggle.button_pressed
	shell.free()
	return TestResult.new("the mast row names its guesses, and its Fitted toggle on the panel adds its weight",
		note.contains("(guess)") and note.contains("mast") and after > before and pressed,
		"note \"%s\"; %+.3f g; toggle pressed %s" % [note, (after - before) * 1000.0, pressed])


static func _span_z(triangles: Array) -> float:
	var lo := INF
	var hi := -INF
	for t in triangles:
		for p in t:
			lo = minf(lo, p.z)
			hi = maxf(hi, p.z)
	return hi - lo if hi >= lo else 0.0


static func _ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row["id"]))
	return out
