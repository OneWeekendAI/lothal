class_name TestBatteryPad
extends RefCounted
## The battery pad — printed-room slice PR11 (plans/2026-09-14-printed-room-plan.md, PR11).
##
## Where each check could pass while proving nothing, and what stops it:
##   - "manifold" on an empty list: counted first; the volume is held to three bands and four rails,
##     written out here.
##   - "the slots are open" is asserted in the solid: no triangle lies inside a slot, so a pad emitted
##     as one slab (manifold, right footprint) fails.
##   - "clearance opens the slots" at the default: 0.10 vs 0.35, measured on the slot opening.
##   - "a strap wider than the pad refuses" beside the reference pack it accepts.
##   - "mass is opt-in" with Fitted ticked on the reference build; unfitted with settings adds nothing.
##   - "weighed under the pack" against Build's OWN pack seat, read off the "Pack" PartMass — not a seat
##     recomputed in the test the same way the code does.


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var build := ReferenceBuild.build()
	results.append_array(_the_solid_is_bands_and_rails_with_open_slots(build))
	results.append(_clearance_opens_the_slots(build))
	results.append_array(_a_strap_wider_than_the_pad_is_refused(build, catalog))
	results.append_array(_mass_is_opt_in_and_under_the_pack())
	results.append(_its_guesses_are_labelled_and_fitted_from_the_panel())
	results.append(_the_pad_follows_the_pack_when_it_is_slid())
	results.append(_each_guess_is_named_and_a_set_one_loses_its_marker(build))
	return results


## that forgot the offset disagree.
static func _the_pad_follows_the_pack_when_it_is_slid() -> TestResult:
	var printing := {}
	BatteryPad.set_value(printing, BatteryPad.FITTED, true)
	var build := ReferenceBuild.build()
	build.set_printing(printing)
	build.set_assembly({"battery_offset_m": -0.009})
	var pad_seat := Vector3.INF
	var pack_seat := Vector3.INF
	for pm in build.mass_parts():
		if (pm as PartMass).label == "Battery pad":
			pad_seat = (pm as PartMass).position_m
		if (pm as PartMass).label == "Pack":
			pack_seat = (pm as PartMass).position_m
	return TestResult.new(
		"slid 9 mm aft by the battery offset, the pack moves and the pad moves with it, directly beneath",
		pack_seat != Vector3.INF and absf(pack_seat.z - 0.009) < 1e-9
			and absf(pad_seat.z - pack_seat.z) < 1e-9 and absf(pad_seat.x - pack_seat.x) < 1e-9
			and pad_seat.y < pack_seat.y,
		"pack %s, pad %s" % [pack_seat, pad_seat])


## Each guess is named against its OWN value, so a row that stops calling one of them a guess fails even
## while the others still say "(guess)". A set 3 mm thickness reads without the marker.
static func _each_guess_is_named_and_a_set_one_loses_its_marker(build: Build) -> TestResult:
	var untouched := _pad_note(build, {})
	var printing := {}
	BatteryPad.set_value(printing, BatteryPad.THICKNESS, 3.0)
	var edited := _pad_note(build, printing)
	return TestResult.new(
		"untouched, the margin, thickness and strap width are each marked a guess; a set 3 mm thickness reads without the marker",
		untouched.contains("2.0 mm margin (guess)") and untouched.contains("2.0 mm thick (guess)")
			and untouched.contains("20.0 mm strap slots (guess)")
			and edited.contains("3.0 mm thick,") and edited.contains("2.0 mm margin (guess)"),
		"untouched \"%s\" | edited \"%s\"" % [untouched, edited])


static func _pad_note(build: Build, printing: Dictionary) -> String:
	var copy := ReferenceBuild.build()
	copy.set_printing(printing)
	for row in PrintedParts.for_build(copy):
		if String(row["id"]) == BatteryPad.PART_ID:
			return String(row["note"])
	return ""


static func _the_solid_is_bands_and_rails_with_open_slots(build: Build) -> Array:
	var d := BatteryPad.dimensions(build.battery, {})
	var triangles := BatteryPad.triangles_mm(d)
	var report := StlWriter.check_manifold(triangles)
	var t := float(d.get("thickness_mm", 0.0))
	var expected := 3.0 * float(d.get("band_mm", 0.0)) * float(d.get("pad_width_mm", 0.0)) * t \
		+ 4.0 * (float(d.get("slot_open_mm", 0.0)) + 1.0) * float(d.get("rail_mm", 0.0)) * t
	var volume := float(report["volume_mm3"])

	# A point in the middle of the first slot, across the pad's centreline: no triangle may cover it.
	var half_l := float(d.get("pad_length_mm", 0.0)) * 0.5
	var slot_centre_y := -half_l + float(d.get("band_mm", 0.0)) + float(d.get("slot_open_mm", 0.0)) * 0.5
	var covered := false
	for tri in triangles:
		var lo_y := minf(minf(tri[0].y, tri[1].y), tri[2].y)
		var hi_y := maxf(maxf(tri[0].y, tri[1].y), tri[2].y)
		var lo_x := minf(minf(tri[0].x, tri[1].x), tri[2].x)
		var hi_x := maxf(maxf(tri[0].x, tri[1].x), tri[2].x)
		if lo_y < slot_centre_y - 1e-6 and hi_y > slot_centre_y + 1e-6 and lo_x < -1e-6 and hi_x > 1e-6:
			covered = true
	return [
		TestResult.new("the reference pack's pad has triangles, closed and outward, whose volume is three bands and four rails",
			triangles.size() > 0 and bool(report["ok"]) and expected > 0.0 and absf(volume - expected) < 1e-4 * expected,
			"%d triangles, ok %s, %.3f vs %.3f mm³, reasons %s" % [triangles.size(), report["ok"], volume, expected,
				report["reasons"]]),
		TestResult.new("and the strap slots are open: nothing crosses the middle of a slot",
			triangles.size() > 0 and not covered, "covered %s at y %.3f" % [covered, slot_centre_y]),
	]


static func _clearance_opens_the_slots(build: Build) -> TestResult:
	var tight := {}
	PrintSettings.set_clearance_mm(tight, 0.10)
	var loose := {}
	PrintSettings.set_clearance_mm(loose, 0.35)
	var t := BatteryPad.dimensions(build.battery, tight)
	var l := BatteryPad.dimensions(build.battery, loose)
	return TestResult.new("0.25 mm more clearance opens each strap slot by 0.5 mm along the pad",
		absf((float(l.get("slot_open_mm", 0.0)) - float(t.get("slot_open_mm", 0.0))) - 0.5) < 1e-6,
		"%.3f → %.3f mm" % [t.get("slot_open_mm", 0.0), l.get("slot_open_mm", 0.0)])


static func _a_strap_wider_than_the_pad_is_refused(build: Build, catalog: PartsCatalog) -> Array:
	var wide := {}
	BatteryPad.set_value(wide, BatteryPad.SLOT, 30.0)
	var narrow_pack := catalog.get_part("battery_1s_300")
	var refused := BatteryPad.dimensions(narrow_pack, wide)
	var unpublished := BatteryPad.dimensions({"part_id": "battery_unpublished", "specs": {"cells": 4}}, {})
	var path := "user://exports/_wide_strap_pad.stl"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var written := StlWriter.write("battery_pad", BatteryPad.triangles_mm(refused), path)
	var accepted := BatteryPad.dimensions(build.battery, {})
	return [
		TestResult.new("a 30 mm strap across an 11 mm 1S pack's pad is refused by name, and writes nothing",
			not bool(refused["ok"]) and String(refused["reason"]).begins_with("battery_pad:")
				and String(refused["reason"]).contains("battery_1s_300") and not bool(written["ok"])
				and not FileAccess.file_exists(path),
			String(refused.get("reason", ""))),
		TestResult.new("a pack publishing no footprint is refused naming the field; the reference pack is accepted",
			not bool(unpublished["ok"]) and String(unpublished["reason"]).contains("length_mm") and bool(accepted["ok"]),
			"%s; reference ok %s" % [unpublished.get("reason", ""), accepted["ok"]]),
	]


static func _mass_is_opt_in_and_under_the_pack() -> Array:
	var base := ReferenceBuild.build()
	var set_only := ReferenceBuild.build()
	var settings := {}
	BatteryPad.set_value(settings, BatteryPad.THICKNESS, 3.0)
	set_only.set_printing(settings)
	var fitted := ReferenceBuild.build()
	var printing := settings.duplicate(true)
	BatteryPad.set_value(printing, BatteryPad.FITTED, true)
	fitted.set_printing(printing)

	var d := BatteryPad.dimensions(fitted.battery, printing)
	var each := BatteryPad.mass_kg(d)
	var m0 := base.mass_properties.total_mass_kg
	var pad_seat := Vector3.INF
	var pack_seat := Vector3.INF
	for pm in fitted.mass_parts():
		if (pm as PartMass).label == "Battery pad":
			pad_seat = (pm as PartMass).position_m
		if (pm as PartMass).label == "Pack":
			pack_seat = (pm as PartMass).position_m
	# Build's own pack seat and its own pack height: the pad sits half a pad beneath the pack's underside,
	# on the side of the pack facing its mount (the reference pack is strapped on top, so below it).
	var drop := fitted.battery_size_m().y * 0.5 + 0.0015
	return [
		TestResult.new("the reference build weighs 507.48 g, and pad settings alone add nothing",
			absf(m0 * 1000.0 - TestHarness.REFERENCE_AUW_G) < 0.01
				and absf(set_only.mass_properties.total_mass_kg - m0) < 1e-12,
			"%.3f g; with settings %.3f g" % [m0 * 1000.0, set_only.mass_properties.total_mass_kg * 1000.0]),
		TestResult.new("Fitted adds exactly one pad, weighed under Build's own pack seat by half a pack and half a 3 mm pad",
			each > 0.0 and absf((fitted.mass_properties.total_mass_kg - m0) - each) < 1e-12
				and pad_seat.distance_to(pack_seat - Vector3(0.0, drop, 0.0)) < 1e-9,
			"+%.4f g for %.4f g; pad %s, pack %s" % [(fitted.mass_properties.total_mass_kg - m0) * 1000.0,
				each * 1000.0, pad_seat, pack_seat]),
	]


static func _its_guesses_are_labelled_and_fitted_from_the_panel() -> TestResult:
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Padded"))
	var note := shell.lab.print_panel.row_note(BatteryPad.PART_ID)
	var before := shell.lab.current_build().mass_properties.total_mass_kg
	shell.lab.print_panel.battery_pad_edited.emit(BatteryPad.FITTED, true)
	var after := shell.lab.current_build().mass_properties.total_mass_kg
	var toggle := shell.lab.print_panel.fit_toggle(BatteryPad.PART_ID)
	# Read BEFORE the shell is freed: the toggle is the shell's child and goes with it.
	var pressed := toggle != null and toggle.button_pressed
	shell.free()
	return TestResult.new("the pad row names its guesses, and its Fitted toggle on the panel adds its weight",
		note.contains("(guess)") and note.contains("strap") and after > before and pressed,
		"note \"%s\"; %+.3f g; toggle pressed %s" % [note, (after - before) * 1000.0, pressed])
