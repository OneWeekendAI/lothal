class_name TestPartColour
extends RefCounted
## The colour inside the shelf icons: PartColour's value -> colour/fill mapping, per category, and
## that the shelf's cards carry it.
##
## ## The checks that could have passed while proving nothing
##
## - EVERY EXPECTED NUMBER IS TYPED HERE BY HAND (a 1500 mAh pack in a 300..5600 range fills 0.2264),
##   never computed by PartColour. One generated test per category, so a category that lost its
##   mapping fails by name.
## - The ramp is checked at its three stops AND for direction (red never falls, blue never rises as
##   the value climbs), so a reversed or flat ramp fails.
## - The catalogue test reads the real parts and computes the range ITSELF; it also demands that
##   parts of a category are told apart (at least two distinct shares), so a mapping that read a key
##   no part has (every share 0.5) fails.
## - The shelf test compares each card's picture with the encoding of ITS part, and demands the
##   colours vary across the cards of a category.

const CLASS_ID := "five_inch"
const EPS := 0.001

## category -> [part, range, expected property, expected kind, expected t]; t typed by hand.
const CASES := {
	"battery": [{"specs": {"mah": 1500.0}}, Vector2(300.0, 5600.0), "capacity", "fill", 0.22642],
	"motor": [{"specs": {"kv": 1950.0}}, Vector2(1300.0, 19000.0), "KV", "hue", 0.15117],
	"propeller": [{"specs": {"pitch_inches": 4.5}}, Vector2(2.5, 12.0), "pitch", "hue", 0.21053],
	"esc": [{"specs": {"continuous_a": 45.0}}, Vector2(5.0, 85.0), "current", "fill", 0.5],
	"flight_controller": [{"specs": {"gyro_sample_rate_hz": 8000.0}}, Vector2(2000.0, 32000.0), "gyro rate", "fill", 0.2],
	"guard": [{"mass_g": 30.0}, Vector2(10.0, 110.0), "mass", "fill", 0.2],
	"receiver": [{"mass_g": 3.0}, Vector2(1.0, 5.0), "mass", "fill", 0.5],
	"camera": [{"mass_g": 8.0}, Vector2(4.0, 24.0), "mass", "fill", 0.2],
	"vtx": [{"mass_g": 15.0}, Vector2(5.0, 35.0), "mass", "fill", 0.33333],
	"antenna": [{"mass_g": 2.0}, Vector2(1.0, 11.0), "mass", "fill", 0.1],
}
const FILL_COLOURS := {"battery": Color(0.45, 0.70, 0.50), "esc": Color(0.48, 0.62, 0.80),
	"flight_controller": Color(0.62, 0.55, 0.80), "guard": Color(0.76, 0.66, 0.46),
	"receiver": Color(0.45, 0.70, 0.70), "camera": Color(0.45, 0.70, 0.70),
	"vtx": Color(0.45, 0.70, 0.70), "antenna": Color(0.45, 0.70, 0.70)}


static func run() -> Array:
	var out: Array = []
	for cat in CASES:
		out.append(_test_category(String(cat)))
	out.append_array(_test_unit())
	out.append_array(_test_ramp())
	out.append_array(_test_calm())
	out.append_array(_test_values())
	out.append_array(_test_catalogue())
	out.append_array(_test_shelf_cards())
	return out


static func _test_category(cat: String) -> TestResult:
	var c: Array = CASES[cat]
	var e := PartColour.encode(c[0], cat, c[1])
	var kind_ok := not e.is_empty() and String(e["property"]) == String(c[2]) and String(e["kind"]) == String(c[3]) \
		and absf(float(e["t"]) - float(c[4])) < EPS
	var colour_ok := false
	if not e.is_empty():
		if String(c[3]) == "fill":
			colour_ok = (e["colour"] as Color).is_equal_approx(FILL_COLOURS[cat])
		else:
			# A hue is the ramp at t: cool side below the middle, warm side above it.
			var col: Color = e["colour"]
			colour_ok = (col.r < col.b) == (float(c[4]) < 0.5) and not col.is_equal_approx(PartColour.MID)
	return TestResult.new("the %s icon shows %s as a %s at share %.3f" % [cat, c[2], c[3], c[4]],
		kind_ok and colour_ok, str(e))


static func _test_unit() -> Array:
	var out: Array = []
	var cases := [
		["the middle of a range is 0.5", PartColour.unit(5.0, 0.0, 10.0), 0.5],
		["the least value is 0", PartColour.unit(0.0, 0.0, 10.0), 0.0],
		["the greatest is 1", PartColour.unit(10.0, 0.0, 10.0), 1.0],
		["above the range is held at 1", PartColour.unit(20.0, 0.0, 10.0), 1.0],
		["below it is held at 0", PartColour.unit(-5.0, 0.0, 10.0), 0.0],
		["on a log scale 1000 is the middle of 100..10000", PartColour.unit(1000.0, 100.0, 10000.0, true), 0.5],
		["a one-value range makes no claim (0.5)", PartColour.unit(3.0, 5.0, 5.0), 0.5],
		["a missing value makes no claim (0.5)", PartColour.unit(NAN, 0.0, 10.0), 0.5],
		["a log scale from zero makes no claim (0.5)", PartColour.unit(4.0, 0.0, 10.0, true), 0.5],
	]
	for c in cases:
		out.append(TestResult.new("unit: " + String(c[0]), absf(float(c[1]) - float(c[2])) < 1e-6, "%f vs %f" % [c[1], c[2]]))
	return out


static func _test_ramp() -> Array:
	var out: Array = []
	out.append(TestResult.new("the ramp starts cool, ends warm and passes a neutral middle",
		PartColour.ramp(0.0).is_equal_approx(Color(0.50, 0.64, 0.78)) and PartColour.ramp(1.0).is_equal_approx(Color(0.82, 0.60, 0.48))
		and PartColour.ramp(0.5).is_equal_approx(Color(0.82, 0.82, 0.78)), ""))
	var mid := PartColour.ramp(0.25)
	out.append(TestResult.new("a quarter of the way is half way from cool to the middle",
		absf(mid.r - 0.66) < EPS and absf(mid.g - 0.73) < EPS and absf(mid.b - 0.78) < EPS, str(mid)))
	var steady := true
	var prev := PartColour.ramp(0.0)
	var worst := ""
	for k in range(1, 21):
		var c := PartColour.ramp(k / 20.0)
		if c.r < prev.r - 1e-6 or c.b > prev.b + 1e-6:
			steady = false
			worst = "step %d" % k
		prev = c
	out.append(TestResult.new("as the value climbs the red never falls and the blue never rises (cool to warm)",
		steady and PartColour.ramp(1.0).r > PartColour.ramp(0.0).r and PartColour.ramp(1.0).b < PartColour.ramp(0.0).b, worst))
	return out


## "Calm and desaturated": every colour the icons use is muted, and none is grey.
static func _test_calm() -> Array:
	var out: Array = []
	var palette: Array = FILL_COLOURS.values()
	var ends: Array = [PartColour.ramp(0.0), PartColour.ramp(1.0)]
	var worst := 0.0
	var least := 1.0
	for k in range(0, 11):
		worst = maxf(worst, PartColour.ramp(k / 10.0).s)
	for c in palette + ends:
		worst = maxf(worst, (c as Color).s)
		least = minf(least, (c as Color).s)
	out.append(TestResult.new("every icon colour, the whole ramp included, is desaturated (HSV saturation at most 0.45)", worst <= 0.45, "%.2f" % worst))
	out.append(TestResult.new("and the fills and the ramp's two ends are not grey (saturation at least 0.15)", least >= 0.15, "%.2f" % least))
	return out


static func _test_values() -> Array:
	var out: Array = []
	var got: Array = []
	for cat in CASES:
		got.append(PartColour.value_of(CASES[cat][0], String(cat)))
	var want := [1500.0, 1950.0, 4.5, 45.0, 8000.0, 30.0, 3.0, 8.0, 15.0, 2.0]
	out.append(TestResult.new("each category reads its own property (mAh, KV, pitch, A, gyro Hz, then mass)",
		got == want, "%s" % [got]))
	out.append(TestResult.new("a part with no such number reads NAN, and an empty slot encodes to nothing",
		is_nan(PartColour.value_of({"specs": {}}, "motor")) and PartColour.encode({}, "motor", Vector2(1, 2)).is_empty(), ""))
	out.append(TestResult.new("the range is the least and greatest among the parts, skipping any without the number",
		PartColour.range_of([{"specs": {"kv": 900.0}}, {"specs": {}}, {"specs": {"kv": 2400.0}}, {"specs": {"kv": 1700.0}}], "motor") == Vector2(900.0, 2400.0)
		and is_nan(PartColour.range_of([{"specs": {}}], "motor").x), ""))
	return out


static func _test_catalogue() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	for cat in CASES:
		var parts: Array = catalog.list_category(String(cat))
		if parts.is_empty():
			out.append(TestResult.new("the catalogue has %s parts" % cat, false, ""))
			continue
		var lo := INF
		var hi := -INF
		var key := String(PartColour.spec_of(String(cat))["key"])
		var vals: Array = []
		for p in parts:
			var v: float = float(p["mass_g"]) if key == "" else float((p.get("specs", {}) as Dictionary).get(key, NAN))
			vals.append(v)
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var r := PartColour.range_of(parts, String(cat))
		var shares := {}
		var in_range := true
		for p in parts:
			var t := float(PartColour.encode(p, String(cat), r)["t"])
			shares[snappedf(t, 0.001)] = true
			in_range = in_range and t >= 0.0 and t <= 1.0
		out.append(TestResult.new("%s: the catalogue's range is %.3g..%.3g, shares stay in 0..1 and tell its %d parts apart" % [cat, lo, hi, parts.size()],
			r == Vector2(lo, hi) and in_range and (shares.size() >= 2 or parts.size() < 2), "%d distinct shares of %d" % [shares.size(), parts.size()]))
	var packs: Array = catalog.list_category("battery")
	var lo_p: Dictionary = packs[0]
	var hi_p: Dictionary = packs[0]
	for p in packs:
		if float(p["specs"]["mah"]) < float(lo_p["specs"]["mah"]):
			lo_p = p
		if float(p["specs"]["mah"]) > float(hi_p["specs"]["mah"]):
			hi_p = p
	var br := PartColour.range_of(packs, "battery")
	out.append(TestResult.new("the smallest pack is empty and the largest full",
		float(PartColour.encode(lo_p, "battery", br)["t"]) == 0.0 and float(PartColour.encode(hi_p, "battery", br)["t"]) == 1.0, ""))
	return out


static func _test_shelf_cards() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.shelf.set_open(true)
	for cat in ["battery", "motor", "propeller"]:
		ds.shelf.toggle_category(cat)
		ds.shelf.set_show_misfits(cat, true)
	var bad: Array = []
	var seen := {}
	var n := 0
	for r in ds.shelf.rows:
		var cat := String(r["category"])
		var pic := ((r["button"] as Button).get_child(0) as Control).get_node("Picture") as PartPicture
		var part := catalog.get_part(String(r["id"]))
		var want := PartColour.encode(part, cat, PartColour.range_of(catalog.list_category(cat), cat))
		n += 1
		if pic.code != want or want.is_empty():
			bad.append(String(r["id"]))
		if not seen.has(cat):
			seen[cat] = {}
		seen[cat][snappedf(float((want as Dictionary).get("t", -1.0)), 0.001)] = true
	out.append(TestResult.new("every card's picture carries the encoding of its own part (%d cards)" % n, n > 20 and bad.is_empty(), str(bad.slice(0, 3))))
	out.append(TestResult.new("and the cards of a category are told apart by it",
		seen.size() == 3 and seen.values().all(func(s): return s.size() >= 3), str(seen.keys().map(func(k): return seen[k].size()))))
	ds.free()
	return out
