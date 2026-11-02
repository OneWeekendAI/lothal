class_name PartFilter
extends RefCounted
## The shelf's quick filters, as pure functions of catalog parts (no window, no theme).
##
## A category has chips (a group each: cells, stator, KV, ...). A group's options are a numeric
## band [lo, hi) of one spec, or an exact value. `filters` is {group key: option id}; a group left
## out (or "") does not narrow. `view` is the shelf's default: only the parts that fit this drone,
## the rest counted and held back behind a toggle.

const BAND_INF := 1.0e9


## category -> [{key, label, options: [{id, label, lo, hi} | {id, label, eq}]}]
static func chips(category: String) -> Array:
	match category:
		"battery":
			return [_g("cells", "CELLS", [_n(1, "1S"), _n(2, "2S"), _n(3, "3S"), _n(4, "4S"), _n(5, "5S"), _n(6, "6S")])]
		"motor":
			return [
				_g("stator", "STATOR", [_b("s_small", "08-15", 0, 20), _b("s_mid", "21-23", 20, 24), _b("s_big", "25-28", 24, BAND_INF)]),
				_g("kv", "KV", [_b("kv_low", "<1800", 0, 1800), _b("kv_mid", "1800-2500", 1800, 2500), _b("kv_high", "2500+", 2500, BAND_INF)]),
			]
		"propeller":
			return [
				_g("diameter", "SIZE", [_d(2), _d(3), _d(4), _d(5), _d(6), _d(7), _d(8), _d(10)]),
				_g("blades", "BLADES", [_n(2, "2"), _n(3, "3"), _n(4, "4")]),
			]
		"esc":
			return [_g("amps", "CURRENT", [_b("a_low", "<25 A", 0, 25), _b("a_mid", "25-50 A", 25, 50), _b("a_high", "50 A+", 50, BAND_INF)])]
		"flight_controller":
			return [_g("pattern", "MOUNT", [_e("20x20", "20x20"), _e("25.5x25.5", "25.5"), _e("30.5x30.5", "30.5")])]
		"guard":
			return [_g("kind", "KIND", [_e("bumper", "bumper"), _e("duct", "duct")])]
	return [_g("length", "LENGTH", [_b("l_short", "<20 mm", 0, 20), _b("l_mid", "20-50 mm", 20, 50), _b("l_long", "50 mm+", 50, BAND_INF)])]


## Whether `part` passes every chosen option in `filters`.
static func matches(part: Dictionary, category: String, filters: Dictionary) -> bool:
	for g in chips(category):
		var want := String(filters.get(g["key"], ""))
		if want == "":
			continue
		var opt := {}
		for o in g["options"]:
			if String(o["id"]) == want:
				opt = o
		if opt.is_empty():
			return false
		var v: Variant = value_of(part, String(g["key"]))
		if v == null:
			return false
		if opt.has("eq"):
			if str(v) != str(opt["eq"]):
				return false
		elif float(v) < float(opt["lo"]) or float(v) >= float(opt["hi"]):
			return false
	return true


## The spec a group reads from `part` (null when it has none).
static func value_of(part: Dictionary, key: String) -> Variant:
	var s: Dictionary = part.get("specs", {})
	match key:
		"cells": return s.get("cells")
		"stator": return s.get("stator_diameter_mm")
		"kv": return s.get("kv")
		"diameter": return s.get("diameter_inches")
		"blades": return s.get("blades")
		"amps": return s.get("continuous_a")
		"pattern": return part.get("mounting", {}).get("pattern")
		"kind": return s.get("kind")
		"length": return s.get("length_mm")
	return null


## The shelf's list for one category. `entries` is [{part, ok}] in shelf order. Default: only the
## parts that fit this drone; `show_misfits` adds the rest after them. `hidden` counts the misfits
## held back (those that pass the chips), the N of "show parts that don't fit (N)".
## -> {fits: [entry], misfits: [entry] (empty unless show_misfits), hidden: int, total_misfits: int}
static func view(entries: Array, category: String, filters: Dictionary, show_misfits: bool) -> Dictionary:
	var fits: Array = []
	var misfits: Array = []
	for e in entries:
		if not matches(e["part"], category, filters):
			continue
		(fits if bool(e["ok"]) else misfits).append(e)
	return {"fits": fits, "misfits": misfits if show_misfits else [],
		"hidden": 0 if show_misfits else misfits.size(), "total_misfits": misfits.size()}


static func _g(key: String, label: String, options: Array) -> Dictionary:
	return {"key": key, "label": label, "options": options}


## Exactly n (cells, blades).
static func _n(n: int, label: String) -> Dictionary:
	return {"id": "n%d" % n, "label": label, "lo": float(n), "hi": float(n) + 1.0}


## A prop diameter that rounds to d inches.
static func _d(d: int) -> Dictionary:
	return {"id": "d%d" % d, "label": "%d\"" % d, "lo": d - 0.5, "hi": d + 0.5}


static func _b(id: String, label: String, lo: float, hi: float) -> Dictionary:
	return {"id": id, "label": label, "lo": lo, "hi": hi}


static func _e(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label, "eq": id}
