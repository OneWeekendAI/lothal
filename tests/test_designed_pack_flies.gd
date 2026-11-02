class_name TestDesignedPackFlies
extends RefCounted
## A pack saved from the designer joins the Design Space shelf and flies like any preset.
##
## The checks that could have passed while proving nothing:
## - The pack is saved through the pop-up's own Save (and the shelf is looked at AFTER that, with no
##   manual catalog refresh in the test): a missing refresh_catalog wiring fails "appears on shelf".
## - The flying figures come from a catalog the TEST loads from the saved file and a Build made from
##   ids, the way TestPresetPackPin does it, not from the Design Space's own readouts.
## - "Coherent" compares a 4S1P to a 4S2P of the same cell and the same wiring: only P differs, so
##   every difference in the figures is P's doing; the mass delta is read from the saved records.

const SCRATCH := "user://test_designed_pack_flies_parts.json"
const CHARGE := "user://test_designed_pack_flies_charge.json"


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _save_pack(ds: DesignSpace, p_name: String, s: int, p: int, connector: String) -> String:
	var d := ds.pack_designer
	d.open_new()
	d.set_series(s)
	d.set_parallel(p)
	d.set_wiring(connector, 14, 100.0)
	d.name_field.text = p_name
	return d.save()


static func _build(catalog: PartsCatalog, battery_id: String) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, battery_id)


static func _fit_pins(ds: DesignSpace) -> Array:
	var out: Array = []
	for p in ds.warning_pins:
		var w := String(p.get("warning", ""))
		if w == "pack_in_prop_disc" or w == "pack_wider_than_plate":
			out.append(w)
	return out


static func run() -> Array:
	var results: Array = []
	_wipe(SCRATCH)
	_wipe(CHARGE)
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	ds.custom_parts_path = SCRATCH
	ds.pack_charge_path = CHARGE
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	var before_rows := ds.shelf.rows.size()
	ds.open_pack_designer()
	var id_1p := _save_pack(ds, "Flies 4S1P", 4, 1, "XT60")
	var id_2p := _save_pack(ds, "Flies 4S2P", 4, 2, "XT60")
	var id_90 := _save_pack(ds, "Flies 4S XT90", 4, 1, "XT90")

	# On the shelf, under the CELLS chip, with no manual refresh.
	ds.shelf.set_show_misfits("battery", true)
	ds.shelf.set_filter("battery", "cells", "n4")
	var row := ds.shelf.row_of(id_2p)
	var saved_part := PartsCatalog.load_with_custom(SCRATCH).get_part(id_2p)
	results.append(_t("saved pack appears on shelf under its CELLS chip",
		id_2p != "" and not row.is_empty() and not saved_part.is_empty()
		and PartFilter.matches(saved_part, "battery", {"cells": "n4"})
		and not PartFilter.matches(saved_part, "battery", {"cells": "n6"}),
		"id %s rows %d (was %d)" % [id_2p, ds.shelf.rows.size(), before_rows]))
	ds.shelf.set_filter("battery", "cells", "n6")
	results.append(_t("and not under a different CELLS chip", ds.shelf.row_of(id_2p).is_empty()))

	# It flies, coherently.
	var flies := PartsCatalog.load_with_custom(SCRATCH)
	var b1 := _build(flies, id_1p)
	var b2 := _build(flies, id_2p)
	var m1 := float(flies.get_part(id_1p).get("mass_g", 0.0))
	var m2 := float(flies.get_part(id_2p).get("mass_g", 0.0))
	var auw_delta := b2.all_up_weight_g() - b1.all_up_weight_g()
	results.append(_t("fitting it changes weight, T:W, hover, flight time, top speed coherently",
		m2 > m1 and absf(auw_delta - (m2 - m1)) < 0.01
		and b2.thrust_to_weight() < b1.thrust_to_weight()
		and b2.hover_throttle() > b1.hover_throttle()
		and b2.flight_time_min() > b1.flight_time_min()
		and b2.top_speed_kmh() != b1.top_speed_kmh(),
		"auw %+.3f vs mass %+.3f; tw %.3f->%.3f hover %.4f->%.4f ft %.3f->%.3f top %.2f->%.2f" % [
			auw_delta, m2 - m1, b1.thrust_to_weight(), b2.thrust_to_weight(), b1.hover_throttle(),
			b2.hover_throttle(), b1.flight_time_min(), b2.flight_time_min(), b1.top_speed_kmh(),
			b2.top_speed_kmh()]))

	# The same pack through the Design Space's own swap.
	var sw := ds.choose("battery", id_2p)
	var readouts := ds.session.readouts(ds._catalog)
	results.append(_t("the Design Space can fit it (swap accepted, AUW reads the saved mass)",
		bool(sw.get("ok", false)) and absf(float(readouts["auw_g"]) - b2.all_up_weight_g()) < 0.5,
		"%s %s auw %s vs %s" % [sw.get("ok"), sw.get("reason", ""), readouts["auw_g"], b2.all_up_weight_g()]))

	var h90 := Harness.defaults(_build(flies, id_90))
	var h60 := Harness.defaults(b1)
	var fam90 := String((flies.get_part(String(h90[Harness.CONNECTOR])).get("catalog", {}) as Dictionary).get("family", ""))
	var fam60 := String((flies.get_part(String(h60[Harness.CONNECTOR])).get("catalog", {}) as Dictionary).get("family", ""))
	results.append(_t("harness picks the designer's connector", fam90 == "XT90" and fam60 == "XT60",
		"%s / %s" % [fam90, fam60]))

	# Fit: an oversize designed pack raises an issue in the Design Space, a fitting one does not, and a
	# shelf preset's pins are exactly what they were.
	var shelf_id := "battery_6s_5600"
	ds.choose("battery", shelf_id)
	var shelf_pins := ds.warning_pins.size()
	var shelf_fit := _fit_pins(ds)
	ds.choose("battery", id_2p)
	var small_fit := _fit_pins(ds)
	ds.open_pack_designer()
	ds.pack_designer.open_new()
	ds.pack_designer.set_cell("cell_molicel_p42a")
	ds.pack_designer.set_series(6)
	ds.pack_designer.set_parallel(4)
	ds.pack_designer.name_field.text = "Flies huge"
	var id_big := ds.pack_designer.save()
	ds.choose("battery", id_big)
	var big_fit := _fit_pins(ds)
	results.append(_t("an oversize designed pack raises a fit issue in the Design Space",
		not big_fit.is_empty() and ds.issues_label.text == WarningPins.count_text(ds.warning_pins.size()),
		"big %s small %s" % [str(big_fit), str(small_fit)]))
	results.append(_t("a designed pack that fits raises none", small_fit.is_empty(), str(small_fit)))
	ds.choose("battery", shelf_id)
	results.append(_t("a shelf preset's issues are unchanged (no fit pin, same count)",
		shelf_fit.is_empty() and _fit_pins(ds).is_empty() and ds.warning_pins.size() == shelf_pins,
		"%d vs %d" % [ds.warning_pins.size(), shelf_pins]))

	var pin_failures := 0
	for r in TestPresetPackPin.run():
		if not (r as TestResult).passed:
			pin_failures += 1
	results.append(_t("preset pin still green", pin_failures == 0, "%d failures" % pin_failures))

	if ds.pack_designer != null:
		ds.pack_designer.close()
	_wipe(SCRATCH)
	_wipe(CHARGE)
	return results
