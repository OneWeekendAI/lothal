class_name TestPartFilter
extends RefCounted
## The shelf's quick filters (PartFilter), the fit-by-default list, the caption that must not repeat
## the name, and the cue that the shelf scrolls.
##
## ## The checks that could have passed while proving nothing
##
## - Each chip is judged against a table written HERE: which spec field it reads and where each
##   option's band lies, as literals. The expected set for an option is rebuilt from the catalog's
##   raw dictionaries with that table, never from PartFilter, and must equal the filter's set
##   exactly (a part wrongly in and a part wrongly out both fail). The option ids are compared
##   too, so a dropped or renamed option fails, and every option must select something real.
## - One test per chip (feedback: loop tests hide coverage). Each is mutation-proven by pointing the
##   chip's reader at the wrong spec (build/mut_filter.sh).
## - The fit default is checked both on the pure function and on the real shelf with the real
##   judge: the rows shown are exactly the parts the judge calls fitting, the toggle's N is the
##   count of the others, and pressing it adds exactly those.
## - A caption is checked against every catalog part's real name, normalised for spaces and case.

const CLASS_ID := "five_inch"
const SIZE := Vector2(1280, 720)

## [category, group key, spec path, {option id: [lo, hi) band | exact string}]
const CHIP_CASES := [
	["battery", "cells", "specs.cells", {"n1": [1, 2], "n2": [2, 3], "n3": [3, 4], "n4": [4, 5], "n5": [5, 6], "n6": [6, 7], "n7": [7, 8], "n8": [8, 9]}],
	["motor", "stator", "specs.stator_diameter_mm", {"s_small": [0, 20], "s_mid": [20, 24], "s_big": [24, 1000]}],
	["motor", "kv", "specs.kv", {"kv_low": [0, 1800], "kv_mid": [1800, 2500], "kv_high": [2500, 100000]}],
	["propeller", "diameter", "specs.diameter_inches", {"d2": [1.5, 2.5], "d3": [2.5, 3.5], "d4": [3.5, 4.5], "d5": [4.5, 5.5],
		"d6": [5.5, 6.5], "d7": [6.5, 7.5], "d8": [7.5, 8.5], "d10": [9.5, 10.5]}],
	["propeller", "blades", "specs.blades", {"n2": [2, 3], "n3": [3, 4], "n4": [4, 5]}],
	["esc", "amps", "specs.continuous_a", {"a_low": [0, 25], "a_mid": [25, 50], "a_high": [50, 1000]}],
	["flight_controller", "pattern", "mounting.pattern", {"20x20": "20x20", "25.5x25.5": "25.5x25.5", "30.5x30.5": "30.5x30.5"}],
	["guard", "kind", "specs.kind", {"bumper": "bumper", "duct": "duct"}],
	["receiver", "length", "specs.length_mm", {"l_short": [0, 20], "l_mid": [20, 50], "l_long": [50, 1000]}],
	["camera", "length", "specs.length_mm", {"l_short": [0, 20], "l_mid": [20, 50], "l_long": [50, 1000]}],
	["vtx", "length", "specs.length_mm", {"l_short": [0, 20], "l_mid": [20, 50], "l_long": [50, 1000]}],
	["antenna", "length", "specs.length_mm", {"l_short": [0, 20], "l_mid": [20, 50], "l_long": [50, 1000]}],
]

const CAPTION_CATEGORIES := ["battery", "motor", "propeller", "esc", "flight_controller", "guard",
	"receiver", "camera", "vtx", "antenna"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	for c in CHIP_CASES:
		results.append(_test_chip(catalog, c))
	results.append_array(_test_view())
	results.append_array(_test_shelf_default(catalog))
	results.append_array(_test_shelf_chip(catalog))
	for cat in CAPTION_CATEGORIES:
		results.append(_test_caption_distinct(catalog, cat))
	results.append_array(_test_caption_values())
	results.append_array(_test_scroll_cue(catalog))
	return results


## The value at "specs.cells" style path in a raw catalog part.
static func _read(part: Dictionary, path: String) -> Variant:
	var bits := path.split(".")
	return part.get(bits[0], {}).get(bits[1])


static func _test_chip(catalog: PartsCatalog, c: Array) -> TestResult:
	var cat := String(c[0])
	var key := String(c[1])
	var table: Dictionary = c[3]
	var label := "filter %s / %s picks exactly the parts in its bands" % [cat, key]
	var group := {}
	for g in PartFilter.chips(cat):
		if String(g["key"]) == key:
			group = g
	if group.is_empty():
		return TestResult.new(label, false, "no such chip group")
	var ids: Array = (group["options"] as Array).map(func(o): return String(o["id"]))
	var want_ids: Array = table.keys()
	if ids != want_ids:
		return TestResult.new(label, false, "options %s, expected %s" % [ids, want_ids])
	var parts: Array = catalog.list_category(cat)
	var bad: Array = []
	var picked := 0
	for oid in want_ids:
		var band: Variant = table[oid]
		var got := 0
		for p in parts:
			var v: Variant = _read(p, String(c[2]))
			var expect := false
			if v != null:
				expect = (str(v) == String(band)) if band is String else (float(v) >= float(band[0]) and float(v) < float(band[1]))
			var actual := PartFilter.matches(p, cat, {key: oid})
			got += 1 if actual else 0
			if actual != expect:
				bad.append("%s/%s" % [oid, p.get("part_id")])
		picked += got
	# Some options may match no part today (no 50 mm+ receiver); the chip as a whole must pick some.
	return TestResult.new(label, bad.is_empty() and picked > 0,
		"wrong: %s; picked %d in all" % [bad.slice(0, 4), picked])


static func _test_view() -> Array:
	var out: Array = []
	var a := {"part": {"specs": {"cells": 4}}, "ok": true}
	var b := {"part": {"specs": {"cells": 6}}, "ok": true}
	var m := {"part": {"specs": {"cells": 1}}, "ok": false}
	var m2 := {"part": {"specs": {"cells": 6}}, "ok": false}
	var entries := [a, m, b, m2]
	var d := PartFilter.view(entries, "battery", {}, false)
	out.append(TestResult.new("fit default: only parts that fit are listed, misfits are counted not shown",
		d["fits"].size() == 2 and d["misfits"].is_empty() and d["hidden"] == 2,
		"fits %d misfits %d hidden %d" % [d["fits"].size(), d["misfits"].size(), d["hidden"]]))
	var s := PartFilter.view(entries, "battery", {}, true)
	out.append(TestResult.new("fit default: showing misfits lists them after the fitting parts",
		s["fits"].size() == 2 and s["misfits"].size() == 2 and s["hidden"] == 0,
		"fits %d misfits %d hidden %d" % [s["fits"].size(), s["misfits"].size(), s["hidden"]]))
	var f := PartFilter.view(entries, "battery", {"cells": "n6"}, false)
	out.append(TestResult.new("fit default: the hidden count follows the chips (only 6S misfits count)",
		f["fits"].size() == 1 and f["hidden"] == 1, "fits %d hidden %d" % [f["fits"].size(), f["hidden"]]))
	return out


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = SIZE
	ds.rig.aspect = SIZE.x / SIZE.y
	return ds


## Ids on the shelf for `cat` that the real judge calls fitting (ok) or not.
static func _judged(ds: DesignSpace, cat: String, ok: bool) -> Array:
	var v := ds._shelf_judge(cat)
	var out: Array = []
	for g in ds.session.shelf(ds._catalog):
		if String(g["category"]) != cat:
			continue
		for p in g["parts"]:
			if bool(v.get(String(p["id"]), {"ok": true})["ok"]) == ok:
				out.append(String(p["id"]))
	return out


static func _row_ids(ds: DesignSpace) -> Array:
	return ds.shelf.rows.map(func(r): return String(r["id"]))


static func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


static func _test_shelf_default(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("motor")
	var fit := _judged(ds, "motor", true)
	var misfit := _judged(ds, "motor", false)
	out.append(TestResult.new("the shelf's motors by default are exactly the ones that fit this drone",
		not fit.is_empty() and not misfit.is_empty() and _sorted(_row_ids(ds)) == _sorted(fit),
		"rows %s, fitting %s" % [_row_ids(ds).size(), fit.size()]))
	var toggle := ds.shelf.find_child("MisfitToggle_motor", true, false) as Button
	out.append(TestResult.new("the toggle reads 'show parts that don't fit (N)' with N the misfit count",
		toggle != null and toggle.text == "show parts that don't fit (%d)" % misfit.size(),
		"text '%s', misfits %d" % [toggle.text if toggle != null else "none", misfit.size()]))
	ds.shelf.set_show_misfits("motor", true)
	out.append(TestResult.new("pressing the toggle adds exactly the parts that don't fit",
		_sorted(_row_ids(ds)) == _sorted(fit + misfit), "rows %d, expected %d" % [_row_ids(ds).size(), fit.size() + misfit.size()]))
	return out


static func _test_shelf_chip(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	ds.shelf.set_show_misfits("battery", true)
	ds.shelf.set_filter("battery", "cells", "n6")
	var ids := _row_ids(ds)
	var all_6s := not ids.is_empty()
	for id in ids:
		all_6s = all_6s and int(catalog.get_part(String(id)).get("specs", {}).get("cells", 0)) == 6
	out.append(TestResult.new("pressing the 6S chip leaves only 6S packs on the shelf", all_6s, "rows %s" % [ids]))
	ds.shelf.set_filter("battery", "cells", "n6")
	out.append(TestResult.new("pressing the chip again clears it", _row_ids(ds).size() > ids.size(),
		"%d rows after, %d before" % [_row_ids(ds).size(), ids.size()]))
	return out


static func _test_caption_distinct(catalog: PartsCatalog, cat: String) -> TestResult:
	var bad: Array = []
	for p in catalog.list_category(cat):
		var n := String(p.get("name", ""))
		var cap := PartCaption.for_card(p, cat, n)
		var a := cap.to_lower().replace(" ", "")
		var b := n.to_lower().replace(" ", "")
		if cap == "" or b.contains(a):
			bad.append("'%s' under '%s'" % [cap, n])
	return TestResult.new("%s captions are never a repeat of the name" % cat, bad.is_empty(), "%d: %s" % [bad.size(), bad.slice(0, 3)])


static func _test_caption_values() -> Array:
	var out: Array = []
	var pack := {"name": "4S 1300mAh 95C", "mass_g": 78.0, "specs": {"cells": 4, "mah": 1300.0}}
	out.append(TestResult.new("a battery named '4S 1300mAh 95C' is captioned with its mass, '78 g'",
		PartCaption.for_card(pack, "battery", "4S 1300mAh 95C") == "78 g",
		"got '%s'" % PartCaption.for_card(pack, "battery", "4S 1300mAh 95C")))
	var light := {"mass_g": 8.0, "specs": {"cells": 1, "mah": 300.0}}
	out.append(TestResult.new("a light pack's mass keeps one decimal, '8.0 g'",
		PartCaption.for_card(light, "battery", "1S 300mAh 30C") == "8.0 g", "got '%s'" % PartCaption.for_card(light, "battery", "1S 300mAh 30C")))
	var motor := {"mass_g": 30.0, "specs": {"stator_diameter_mm": 22, "stator_height_mm": 7, "kv": 1950}}
	out.append(TestResult.new("a motor named '2207 1950KV' falls back to its mass, not a repeat of the name",
		PartCaption.for_card(motor, "motor", "2207 1950KV") == "30 g", "got '%s'" % PartCaption.for_card(motor, "motor", "2207 1950KV")))
	return out


static func _test_scroll_cue(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.shelf.set_open(true)
	out.append(TestResult.new("no scroll cue while the shelf is just its category list", not ds.shelf.can_scroll_more() and not ds.shelf.more_cue.visible, ""))
	for cat in ["battery", "motor", "propeller"]:
		ds.shelf.toggle_category(cat)
		ds.shelf.set_show_misfits(cat, true)
	out.append(TestResult.new("the cue shows when the list runs off the bottom", ds.shelf.can_scroll_more() and ds.shelf.more_cue.visible,
		"content %.0f, view %.0f" % [ds.shelf._content_h, ds.shelf.scroll.custom_minimum_size.y]))
	var bar := ds.shelf.scroll.get_v_scroll_bar()
	bar.max_value = ds.shelf._content_h
	bar.page = ds.shelf.scroll.custom_minimum_size.y
	out.append(TestResult.new("with the bar's real range, the cue is up at the top", ds.shelf.can_scroll_more(), ""))
	bar.value = bar.max_value
	out.append(TestResult.new("the cue goes once scrolled to the end", not ds.shelf.can_scroll_more(), "value %d" % bar.value))
	return out
