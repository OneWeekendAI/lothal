class_name TestBatteryDensity
extends RefCounted
## Catalog-wide energy-density check: every battery's pack-level Wh/kg (nominal_v x Ah / mass) must sit inside a band for its
## chemistry. Added 2026-11-10 after the mapper survey pack was found at 288 Wh in 520 g = 554 Wh/kg, about twice any real pack.
## BANDS (pack level, ESTIMATED from the catalog's own spread and from public cell data): small LiPo 90-210 (catalog today 116-157),
## LiPo HV 180-260 (DJI Mavic 3M pack 77 Wh / 335 g = 230, published), Li-ion 21700-class 100-280 (cell level tops out near 270-280
## for the best 21700s; packs lose 5-10 percent to holders, strip and BMS; catalog today 135-250).
## FAIL-PROOF (observed 2026-11-10): with mapper_battery_4s_10000_liion at the old 520 g with 20000 mAh the catalog case FAILS (554 Wh/kg > 280)
## and the other cases stay green; the 'old data' case is the same check on the old numbers, so it is red-by-construction on the checker.

const BANDS := {"LiPo": [90.0, 210.0], "LiPo HV": [180.0, 260.0], "Li-ion": [100.0, 280.0]}


## "" when in band, else the reason.
static func check(chemistry: String, nominal_v: float, mah: float, mass_g: float) -> String:
	if not BANDS.has(chemistry):
		return "chemistry '%s' has no density band" % chemistry
	if mass_g <= 0.0:
		return "mass must be positive"
	var whkg := nominal_v * mah / 1000.0 / (mass_g / 1000.0)
	var band: Array = BANDS[chemistry]
	if whkg < float(band[0]) or whkg > float(band[1]):
		return "%.0f Wh/kg outside %s band %.0f-%.0f" % [whkg, chemistry, band[0], band[1]]
	return ""


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var bad: Array = []
	var packs: Array = catalog.list_category("battery")
	for p in packs:
		var s: Dictionary = p["specs"]
		var r := check(str(s["chemistry"]), float(s["nominal_v"]), float(s["mah"]), float(p["mass_g"]))
		if r != "":
			bad.append("%s: %s" % [p["part_id"], r])
	out.append(TestResult.new("battery density: every catalog pack is inside the Wh/kg band for its chemistry", bad.is_empty() and packs.size() >= 16, "; ".join(bad) if not bad.is_empty() else "%d packs" % packs.size()))
	out.append(TestResult.new("battery density: the old mapper pack (288 Wh, 520 g, 554 Wh/kg) is refused by the check",
		check("Li-ion", 14.4, 20000.0, 520.0) != "", check("Li-ion", 14.4, 20000.0, 520.0)))
	out.append(TestResult.new("battery density: the new mapper pack is 200-280 Wh/kg and its source names the mass as ESTIMATED with a range",
		_mapper_ok(catalog), ""))
	out.append(TestResult.new("battery density: a pack too heavy for its chemistry is also refused (checker has a lower edge)",
		check("Li-ion", 14.4, 20000.0, 5000.0) != "" and check("LiPo", 11.1, 1000.0, 20.0) != "", ""))
	return out


static func _mapper_ok(catalog: PartsCatalog) -> bool:
	var p: Dictionary = catalog.get_part("mapper_battery_4s_10000_liion")
	var s: Dictionary = p["specs"]
	var d := float(s["nominal_v"]) * float(s["mah"]) / 1000.0 / (float(p["mass_g"]) / 1000.0)
	var src := str(p.get("source", ""))
	return d >= 200.0 and d <= 280.0 and src.contains("ESTIMATED") and src.contains("range")
