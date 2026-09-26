class_name TestAntennaMount
extends RefCounted
## The antenna mount — printed-room slice PR3 (plans/2026-09-14-printed-room-plan.md, PR3 checks).
##
## Two standoff rings joined by a bar, and a tube leaning aft that holds the antenna. Three closed
## shells that overlap where they join — StlWriter allows that, and every slicer unions it.
##
## Where each check could pass while proving nothing, and what stops it:
##   - "manifold" on an empty list: counted first, and the volume is held to the three closed forms.
##   - "the tube leans at the whip's angle": a tube re-authored at 25° agrees with a shared 25° in
##     every picture. So there are two checks — every tube vertex must lie on its bore or its wall
##     about an axis leaning aft by ComponentMesh.WHIP_LEAN_DEGREES (catches a flipped or dropped
##     lean), AND the source must name that constant and write no 25 of its own (catches the copy).
##   - "clearance applies" at the default: 0.10 vs 0.35, measured in the triangles.
##   - "refuses rings that merge" needs the default it accepts beside the case it refuses.
##   - "adds no mass" on a build whose printing names an antenna mount.

const WHOLE_SOURCE := "res://src/print/antenna_mount.gd"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var rhcp := catalog.get_part("antenna_rhcp_ufl")
	var nano := catalog.get_part("antenna_dipole_ufl_nano")

	results.append_array(_the_solid_is_rings_bar_and_tube(rhcp))
	results.append(_the_tube_leans_at_the_whips_angle(rhcp))
	results.append(_the_lean_is_the_drawn_whips_constant())
	results.append(_the_mount_sits_on_the_bed(rhcp))
	results.append(_clearance_opens_both_bores(rhcp))
	results.append(_the_tube_follows_the_antenna(rhcp, nano))
	results.append_array(_merging_rings_are_refused(rhcp))
	results.append(_an_antenna_that_publishes_no_width_is_refused())
	results.append(_it_weighs_nothing_of_its_own())
	results.append(_no_antenna_no_row())
	results.append(_the_standoffs_are_labelled_guesses_edited_per_drone())
	results.append(_a_set_diameter_bores_the_rings(rhcp))
	results.append_array(_a_published_mount_diameter_wins_and_the_fallback_says_width(rhcp))
	return results


## PR3b. An antenna that publishes `mount_diameter_mm` (the barrel the tube actually holds) is bored to
## it; one that does not falls back to its published width and SAYS so on the row. No catalog antenna
## publishes one today, so the accepting fixture is a copy of the RHCP entry with the field added —
## the only arrangement where "reads the field" and "reads width" give different bores.
static func _a_published_mount_diameter_wins_and_the_fallback_says_width(rhcp: Dictionary) -> Array:
	var barrel := rhcp.duplicate(true)
	barrel["part_id"] = "antenna_rhcp_with_barrel"
	(barrel["specs"] as Dictionary)["mount_diameter_mm"] = 6.0
	var d_barrel := AntennaMount.dimensions(barrel, {})
	var d_width := AntennaMount.dimensions(rhcp, {})

	var build := ReferenceBuild.build()
	var width_note := _antenna_note(build)
	build.components["antenna"] = barrel
	var barrel_note := _antenna_note(build)
	return [
		TestResult.new("a published 6 mm mount diameter bores the tube to 3.2 mm radius, not the 15 mm width",
			absf(float(d_barrel.get("tube_bore_radius_mm", 0.0)) - 3.2) < 1e-6
				and not bool(d_barrel.get("bore_from_width", true))
				and absf(float(d_width.get("tube_bore_radius_mm", 0.0)) - 7.7) < 1e-6
				and bool(d_width.get("bore_from_width", false)),
			"barrel %.3f (from width %s), rhcp %.3f (from width %s)" % [d_barrel.get("tube_bore_radius_mm", 0.0),
				d_barrel.get("bore_from_width"), d_width.get("tube_bore_radius_mm", 0.0), d_width.get("bore_from_width")]),
		TestResult.new("the row says the fallback bore comes from the published width, and says nothing of width once a diameter is published",
			width_note.contains("from published width") and width_note.contains("no mount_diameter_mm")
				and barrel_note.contains("6.0 mm mount diameter (published)")
				and not barrel_note.contains("from published width"),
			"width \"%s\" | barrel \"%s\"" % [width_note, barrel_note]),
	]


static func _antenna_note(build: Build) -> String:
	for row in PrintedParts.for_build(build):
		if String(row["id"]) == AntennaMount.PART_ID:
			return String(row["note"])
	return ""


static func _the_solid_is_rings_bar_and_tube(antenna: Dictionary) -> Array:
	var d := AntennaMount.dimensions(antenna, {})
	var triangles := AntennaMount.triangles_mm(d)
	var report := StlWriter.check_manifold(triangles)
	var n := float(d.get("segments", 0))
	var gon := n * 0.5 * sin(TAU / maxf(n, 1.0))
	var ri := float(d.get("standoff_bore_radius_mm", 0.0))
	var ro := float(d.get("ring_outer_radius_mm", 0.0))
	var h := float(d.get("ring_height_mm", 0.0))
	var s := float(d.get("standoff_spacing_mm", 0.0))
	var rt := float(d.get("tube_bore_radius_mm", 0.0))
	var big_rt := float(d.get("tube_outer_radius_mm", 0.0))
	# Written out here, not read from AntennaMount: two rings, the bar between their walls, the tube.
	var expected := 2.0 * gon * (ro * ro - ri * ri) * h \
		+ (s - (ri + ro)) * 2.0 * float(d.get("bar_half_width_mm", 0.0)) * h \
		+ gon * (big_rt * big_rt - rt * rt) * float(d.get("tube_length_mm", 0.0))
	var volume := float(report["volume_mm3"])
	return [
		TestResult.new("the RHCP antenna's mount has triangles to check", triangles.size() > 0,
			"%d triangles" % triangles.size()),
		TestResult.new("they are closed outward shells whose volume is two rings, the bar and the tube",
			bool(report["ok"]) and n >= 12 and expected > 0.0 and absf(volume - expected) < 1e-4 * expected,
			"ok %s, %.3f mm³ vs %.3f mm³, reasons %s" % [report["ok"], volume, expected, report["reasons"]]),
	]


## Every vertex of the tube shell is at the bore radius or the wall radius from a line through the
## shell's centroid, leaning aft (+Y, Z up) by the whip's angle. A tube upright, or leaning forward,
## puts vertices off both radii.
static func _the_tube_leans_at_the_whips_angle(antenna: Dictionary) -> TestResult:
	var d := AntennaMount.dimensions(antenna, {})
	var tube: Array = AntennaMount.shells_mm(d).get("tube", [])
	var phi := deg_to_rad(ComponentMesh.WHIP_LEAN_DEGREES)
	var axis := Vector3(0.0, sin(phi), cos(phi))
	var fit := _radial_fit(tube, axis)
	var rt := float(d.get("tube_bore_radius_mm", 0.0))
	var big_rt := float(d.get("tube_outer_radius_mm", 0.0))
	return TestResult.new(
		"the tube leans aft by ComponentMesh.WHIP_LEAN_DEGREES: every vertex sits on its bore or its wall about that axis",
		tube.size() > 0 and rt > 0.0 and fit["worst"] < 1e-3 and absf(fit["min"] - rt) < 1e-3
			and absf(fit["max"] - big_rt) < 1e-3,
		"%d tube triangles; radii %.4f..%.4f vs %.4f / %.4f, worst miss %.5f mm" % [tube.size(), fit["min"],
			fit["max"], rt, big_rt, fit["worst"]])


static func _the_lean_is_the_drawn_whips_constant() -> TestResult:
	var text := FileAccess.get_file_as_string(WHOLE_SOURCE)
	var code := PackedStringArray()
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("#"):
			code.append(line)
	var body := "\n".join(code)
	return TestResult.new(
		"the mount's lean is read from ComponentMesh.WHIP_LEAN_DEGREES, and its code writes no 25 of its own",
		text.length() > 0 and body.contains("ComponentMesh.WHIP_LEAN_DEGREES") and not body.contains("25"),
		"read %d chars; names constant %s; a 25 in the code %s" % [text.length(),
			body.contains("ComponentMesh.WHIP_LEAN_DEGREES"), body.contains("25")])


static func _the_mount_sits_on_the_bed(antenna: Dictionary) -> TestResult:
	var shells := AntennaMount.shells_mm(AntennaMount.dimensions(antenna, {}))
	var low_all := _min_z(AntennaMount.triangles_mm(AntennaMount.dimensions(antenna, {})))
	var low_tube := _min_z(shells.get("tube", []))
	return TestResult.new("printed as it bolts on: nothing below the bed, and the leaning tube's lowest rim on it",
		absf(low_all) < 1e-4 and absf(low_tube) < 1e-4, "lowest %.5f mm, tube lowest %.5f mm" % [low_all, low_tube])


static func _clearance_opens_both_bores(antenna: Dictionary) -> TestResult:
	var tight := {}
	PrintSettings.set_clearance_mm(tight, 0.10)
	var loose := {}
	PrintSettings.set_clearance_mm(loose, 0.35)
	var phi := deg_to_rad(ComponentMesh.WHIP_LEAN_DEGREES)
	var axis := Vector3(0.0, sin(phi), cos(phi))
	var t := AntennaMount.dimensions(antenna, tight)
	var l := AntennaMount.dimensions(antenna, loose)
	var tube_grew: float = _radial_fit(AntennaMount.shells_mm(l).get("tube", []), axis)["min"] \
		- _radial_fit(AntennaMount.shells_mm(t).get("tube", []), axis)["min"]
	var ring_grew := _ring_bore(AntennaMount.shells_mm(l).get("rings", []), l) \
		- _ring_bore(AntennaMount.shells_mm(t).get("rings", []), t)
	return TestResult.new(
		"0.25 mm more clearance opens the antenna bore and the standoff bores by 0.25 mm radius, in the solid",
		absf(tube_grew - 0.25) < 1e-3 and absf(ring_grew - 0.25) < 1e-3,
		"tube bore +%.4f, standoff bore +%.4f mm" % [tube_grew, ring_grew])


static func _the_tube_follows_the_antenna(rhcp: Dictionary, nano: Dictionary) -> TestResult:
	var phi := deg_to_rad(ComponentMesh.WHIP_LEAN_DEGREES)
	var axis := Vector3(0.0, sin(phi), cos(phi))
	var big: float = _radial_fit(AntennaMount.shells_mm(AntennaMount.dimensions(rhcp, {})).get("tube", []), axis)["min"]
	var small: float = _radial_fit(AntennaMount.shells_mm(AntennaMount.dimensions(nano, {})).get("tube", []), axis)["min"]
	return TestResult.new(
		"the tube bore is the fitted antenna's published width plus clearance: 15 mm RHCP → 7.7, 4 mm nano → 2.2 mm radius",
		absf(big - 7.7) < 1e-3 and absf(small - 2.2) < 1e-3, "RHCP %.4f, nano %.4f mm" % [big, small])


static func _merging_rings_are_refused(antenna: Dictionary) -> Array:
	var tight := {}
	AntennaMount.set_value(tight, AntennaMount.STANDOFF_SPACING, 12.0)
	AntennaMount.set_value(tight, AntennaMount.STANDOFF_DIAMETER, 8.0)
	var refused := AntennaMount.dimensions(antenna, tight)
	var accepted := AntennaMount.dimensions(antenna, {})
	var path := "user://exports/_merged_antenna_mount.stl"
	# Cleared first: a broken refusal writes this file, and a leftover would fail every later run.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var written := StlWriter.write("antenna_mount", AntennaMount.triangles_mm(refused), path)
	return [
		TestResult.new("8 mm standoffs 12 mm apart are refused — the rings would run into each other — naming the part and the spacing",
			not bool(refused["ok"]) and String(refused["reason"]).begins_with("antenna_mount:")
				and String(refused["reason"]).contains("12.0"),
			String(refused.get("reason", ""))),
		TestResult.new("and write no file, while the guessed default is accepted",
			not bool(written["ok"]) and not FileAccess.file_exists(path) and bool(accepted["ok"]),
			"write ok %s, default ok %s" % [written["ok"], accepted["ok"]]),
	]


static func _an_antenna_that_publishes_no_width_is_refused() -> TestResult:
	var d := AntennaMount.dimensions({"part_id": "antenna_unpublished", "specs": {"length_mm": 40.0}}, {})
	return TestResult.new("an antenna with no published width is refused by name, not given a guessed bore",
		not bool(d["ok"]) and String(d["reason"]).contains("antenna_unpublished")
			and String(d["reason"]).contains("width_mm"),
		String(d.get("reason", "")))


static func _it_weighs_nothing_of_its_own() -> TestResult:
	var base := ReferenceBuild.build()
	var with_mount := ReferenceBuild.build()
	var printing := {}
	AntennaMount.set_value(printing, AntennaMount.STANDOFF_SPACING, 28.0)
	with_mount.set_printing(printing)
	return TestResult.new(
		"an antenna mount adds no mass: the antenna's share already holds it, so the build is still 507.48 g",
		absf(base.mass_properties.total_mass_kg * 1000.0 - TestHarness.REFERENCE_AUW_G) < 0.01
			and absf(with_mount.mass_properties.total_mass_kg - base.mass_properties.total_mass_kg) < 1e-12
			and bool(AntennaMount.dimensions(with_mount.components.get("antenna", {}), printing).get("ok", false)),
		"%.3f g with a mount set, %.3f g without" % [with_mount.mass_properties.total_mass_kg * 1000.0,
			base.mass_properties.total_mass_kg * 1000.0])


static func _no_antenna_no_row() -> TestResult:
	var build := ReferenceBuild.build()
	var with_antenna := _ids(PrintedParts.for_build(build))
	build.components.erase("antenna")
	var without := _ids(PrintedParts.for_build(build))
	return TestResult.new("a build with an antenna lists the antenna mount; with none it lists none, and no error",
		with_antenna.has(AntennaMount.PART_ID) and not without.has(AntennaMount.PART_ID),
		"with %s, without %s" % [with_antenna, without])


static func _the_standoffs_are_labelled_guesses_edited_per_drone() -> TestResult:
	var shell := GlassShell.new()
	var project := Project.create("Antenna")
	project.parts["antenna"] = "antenna_rhcp_ufl"
	shell.apply_project(project)
	var untouched := shell.lab.print_panel.row_note(AntennaMount.PART_ID)
	shell.lab.print_panel.antenna_mount_edited.emit(AntennaMount.STANDOFF_SPACING, 28.0)
	var edited := shell.lab.print_panel.row_note(AntennaMount.PART_ID)
	shell._sync_project()
	var reloaded := Project.from_dict(shell.container.project.to_dict())
	var stored := float(AntennaMount.settings(reloaded.printing).get(AntennaMount.STANDOFF_SPACING, 0.0))
	# A/B/A: a second drone that never set it reads the guess, and the first still reads 28.
	var other := Project.create("Other")
	other.parts["antenna"] = "antenna_rhcp_ufl"
	shell.apply_project(other)
	var b_note := shell.lab.print_panel.row_note(AntennaMount.PART_ID)
	shell.apply_project(reloaded)
	var a_again := shell.lab.print_panel.row_note(AntennaMount.PART_ID)
	shell.free()
	return TestResult.new(
		"untouched, both standoff numbers say (guess); an edited spacing shows, loses its marker, reaches the project, and stays with that drone (A/B/A)",
		untouched.contains("standoffs 30.0 mm apart (guess)") and untouched.contains("5.0 mm across (guess)")
			and edited.contains("standoffs 28.0 mm apart,") and edited.contains("5.0 mm across (guess)")
			and is_equal_approx(stored, 28.0) and b_note.contains("standoffs 30.0 mm apart (guess)")
			and a_again.contains("standoffs 28.0 mm apart,"),
		"untouched \"%s\" | edited \"%s\" | stored %.1f | B \"%s\" | A \"%s\"" % [untouched, edited, stored,
			b_note, a_again])


## The diameter is the other guess, and nothing else would notice it being ignored: the refusal case
## refuses at the default diameter too. A 6 mm standoff at the default clearance bores 3.2 mm.
static func _a_set_diameter_bores_the_rings(antenna: Dictionary) -> TestResult:
	var printing := {}
	AntennaMount.set_value(printing, AntennaMount.STANDOFF_DIAMETER, 6.0)
	var d := AntennaMount.dimensions(antenna, printing)
	var bore := _ring_bore(AntennaMount.shells_mm(d).get("rings", []), d)
	return TestResult.new("a 6 mm standoff set by the builder bores the rings to 3.2 mm radius, in the solid",
		absf(bore - 3.2) < 1e-3, "ring bore %.4f mm" % bore)


static func _radial_fit(triangles: Array, axis: Vector3) -> Dictionary:
	var centroid := Vector3.ZERO
	var count := 0
	for t in triangles:
		for p in t:
			centroid += p
			count += 1
	if count == 0:
		return {"min": 0.0, "max": 0.0, "worst": INF}
	centroid /= count
	var lo := INF
	var hi := -INF
	var distances: Array = []
	for t in triangles:
		for p in t:
			var rel: Vector3 = p - centroid
			var dist := (rel - axis * rel.dot(axis)).length()
			distances.append(dist)
			lo = minf(lo, dist)
			hi = maxf(hi, dist)
	var worst := 0.0
	for dist in distances:
		worst = maxf(worst, minf(absf(dist - lo), absf(dist - hi)))
	return {"min": lo, "max": hi, "worst": worst}


## The first ring's bore radius, from its vertices about its own vertical axis.
static func _ring_bore(rings: Array, d: Dictionary) -> float:
	var centre := Vector2(-float(d.get("standoff_spacing_mm", 0.0)) * 0.5, 0.0)
	var lo := INF
	for t in rings:
		for p in t:
			if p.x < 0.0:
				lo = minf(lo, (Vector2(p.x, p.y) - centre).length())
	return lo if lo < INF else 0.0


static func _min_z(triangles: Array) -> float:
	var lo := INF
	for t in triangles:
		for p in t:
			lo = minf(lo, p.z)
	return lo if lo < INF else -1.0


static func _ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row["id"]))
	return out
