class_name CutCost
extends RefCounted
## What cutting this frame might cost — airframe gaps G6. A RANGE, from PLACEHOLDER rates, never one
## number.
##
## ## What is priced
##
## A carbon-cutting shop charges for two things: the stock it puts on the bed and the time the
## spindle spends moving. Here those are:
##
##   - **Sheet:** for each stock (material + thickness), the bounding area of that stock's nest — the
##     cut sheet `FrameExport` draws, parts at the rotation they were designed at — times a per-cm²
##     price for that thickness. Per stock, because a 5 mm arm and a 2.5 mm top plate cannot come off
##     one sheet: the single nested SVG draws them together, the shop does not cut them together.
##   - **Cut:** the length of every closed contour, outlines and holes, times a per-metre price. Holes
##     cost as much per millimetre as outlines; that is why a lightened plate is not free.
##
## Pads are not priced: they are printed TPU, not cut plate.
##
## ## Why a range, and why the label
##
## The rates in `data/cut_rates.json` are round guesses for a builder to replace with a quote. Each is
## a low/high pair and the estimate carries both ends plus the table's `tier_label`, so nothing
## downstream can print one exact-looking figure. `range_text` rounds the low end down and the high
## end up to whole units, because a cents figure on a guess is a precision claim the guess cannot make.

const RATES_PATH := "res://data/cut_rates.json"

static var _default_rates: Dictionary = {}


## The rates table, `{}` when it cannot be read. Cached; `path` other than the default is re-read.
static func load_rates(path: String = RATES_PATH) -> Dictionary:
	if path == RATES_PATH and not _default_rates.is_empty():
		return _default_rates
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var rows: Array = (parsed as Dictionary).get("sheet_price_per_cm2", [])
	rows.sort_custom(func(a, b): return float(a["thickness_mm"]) < float(b["thickness_mm"]))
	(parsed as Dictionary)["sheet_price_per_cm2"] = rows
	if path == RATES_PATH:
		_default_rates = parsed
	return parsed


## `{low, high}` price per cm² of sheet at `thickness_mm`: linear between the table's stock, and in
## proportion to thickness beyond either end, so it rises with thickness everywhere.
static func sheet_rate_per_cm2(rates: Dictionary, thickness_mm: float) -> Dictionary:
	var rows: Array = rates.get("sheet_price_per_cm2", [])
	if rows.is_empty() or thickness_mm <= 0.0:
		return {"low": 0.0, "high": 0.0}
	var first: Dictionary = rows[0]
	var last: Dictionary = rows[rows.size() - 1]
	if thickness_mm <= float(first["thickness_mm"]):
		var k := thickness_mm / float(first["thickness_mm"])
		return {"low": float(first["low"]) * k, "high": float(first["high"]) * k}
	if thickness_mm >= float(last["thickness_mm"]):
		var k := thickness_mm / float(last["thickness_mm"])
		return {"low": float(last["low"]) * k, "high": float(last["high"]) * k}
	for i in rows.size() - 1:
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		var ta := float(a["thickness_mm"])
		var tb := float(b["thickness_mm"])
		if thickness_mm >= ta and thickness_mm <= tb:
			var f := (thickness_mm - ta) / (tb - ta) if tb > ta else 0.0
			return {"low": lerpf(float(a["low"]), float(b["low"]), f),
				"high": lerpf(float(a["high"]), float(b["high"]), f)}
	return {"low": float(last["low"]), "high": float(last["high"])}


## Perimeter of one closed contour, mm.
static func contour_length_mm(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		total += points[i].distance_to(points[(i + 1) % points.size()])
	return total if points.size() >= 3 else 0.0


## Every cut on one plate: its outline plus each hole, mm.
static func plate_cut_length_mm(plate: Dictionary) -> float:
	var total := contour_length_mm(AirframeDocument.plate_outline(plate))
	for hole in AirframeDocument.plate_holes(plate):
		total += contour_length_mm(hole)
	return total


## Every cut on the frame, metres. Plates only, upright side plates included (they are cut flat).
static func cut_length_m(document: AirframeDocument) -> float:
	var total := 0.0
	if document == null:
		return total
	for plate in document.plates:
		total += plate_cut_length_mm(plate)
	return total / 1000.0


## The plates grouped by the stock they come off: `[{material_id, thickness_mm, plates}]`, in the
## order each stock first appears.
static func stocks(document: AirframeDocument) -> Array:
	var out: Array = []
	if document == null:
		return out
	var index_of: Dictionary = {}
	for plate in document.plates:
		if AirframeDocument.plate_outline(plate).size() < 3:
			continue
		var material := document.plate_material_id(plate)
		var thickness := AirframeDocument.plate_thickness_mm(plate)
		var key := "%s|%.3f" % [material, thickness]
		if not index_of.has(key):
			index_of[key] = out.size()
			out.append({"material_id": material, "thickness_mm": thickness, "plates": []})
		(out[index_of[key]]["plates"] as Array).append(plate)
	return out


## The whole estimate. Keys:
##   ok, tier, tier_label, currency, symbol, priced_as,
##   stocks: [{material_id, thickness_mm, plate_count, nest_mm (Vector2), area_cm2, rate_low, rate_high,
##             low, high}],
##   sheet_low, sheet_high, cut_length_m, cut_low, cut_high, low, high.
## `ok` is false when the rates cannot be read or there is nothing to cut; the figures are then zero.
static func estimate(document: AirframeDocument, rates: Dictionary = {}) -> Dictionary:
	if rates.is_empty():
		rates = load_rates()
	var out := {"ok": false, "tier": str(rates.get("tier", "placeholder")),
		"tier_label": str(rates.get("tier_label", "placeholder rates")),
		"currency": str(rates.get("currency", "")), "symbol": str(rates.get("currency_symbol", "")),
		"priced_as": str(rates.get("priced_as", "")),
		"stocks": [], "sheet_low": 0.0, "sheet_high": 0.0, "cut_length_m": 0.0, "cut_low": 0.0,
		"cut_high": 0.0, "low": 0.0, "high": 0.0}
	if rates.is_empty() or document == null:
		return out
	var sheet_low := 0.0
	var sheet_high := 0.0
	var found: Array = []
	for stock in stocks(document):
		var rect := FrameExport.nest_rect_mm(stock["plates"])
		var area_cm2 := rect.size.x * rect.size.y / 100.0
		var rate := sheet_rate_per_cm2(rates, float(stock["thickness_mm"]))
		var low := area_cm2 * float(rate["low"])
		var high := area_cm2 * float(rate["high"])
		sheet_low += low
		sheet_high += high
		found.append({"material_id": stock["material_id"], "thickness_mm": stock["thickness_mm"],
			"plate_count": (stock["plates"] as Array).size(), "nest_mm": rect.size,
			"area_cm2": area_cm2, "rate_low": rate["low"], "rate_high": rate["high"],
			"low": low, "high": high})
	var cut := cut_length_m(document)
	var per_m: Dictionary = rates.get("cut_price_per_m", {})
	out["stocks"] = found
	out["sheet_low"] = sheet_low
	out["sheet_high"] = sheet_high
	out["cut_length_m"] = cut
	out["cut_low"] = cut * float(per_m.get("low", 0.0))
	out["cut_high"] = cut * float(per_m.get("high", 0.0))
	out["low"] = sheet_low + float(out["cut_low"])
	out["high"] = sheet_high + float(out["cut_high"])
	out["ok"] = not found.is_empty()
	return out


## "$41–$83": low end rounded down, high end up, to whole units. "" when there is nothing to price.
static func range_text(estimate_result: Dictionary) -> String:
	if not bool(estimate_result.get("ok", false)):
		return ""
	var symbol := str(estimate_result.get("symbol", ""))
	return "%s%d–%s%d" % [symbol, floori(float(estimate_result["low"])), symbol,
		ceili(float(estimate_result["high"]))]


## The range with its tier: "$41–$83 (placeholder rates — replace with your shop's quote)".
static func labelled_text(estimate_result: Dictionary) -> String:
	var text := range_text(estimate_result)
	if text.is_empty():
		return ""
	return "%s (%s)" % [text, str(estimate_result.get("tier_label", "placeholder rates"))]
