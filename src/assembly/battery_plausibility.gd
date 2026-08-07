class_name BatteryPlausibility
extends RefCounted
## What a build says about a pack whose numbers came from a builder rather than from the catalog.
##
## The custom-parts sibling to FramePlausibility and MotorPlausibility, and the same rules hold:
## nothing here blocks anything (labs-and-sim.md §2 warns and never blocks — the refusals are all
## in CustomBatteries, where the alternative is silence), and every bound was PRE-REGISTERED
## against the shipped catalog before it was run against any custom data.
##
## ---------------------------------------------------------------------------
## THE ONE WARNING EVERY CUSTOM PACK CARRIES
## ---------------------------------------------------------------------------
##
## `custom_battery` fires for every builder-entered pack, quotes the builder's own `source`, and
## says the two things worth saying out loud:
##
##   - `internal_r_ohm` was DERIVED from mAh and C when it was not overridden, and that derivation
##     is a self-consistency fit against the shipped catalog's own representative figures. It is
##     not a measurement; a real pack may sag more or less than this predicts.
##   - Flight time carries `Build.FLIGHT_CURRENT_TO_HOVER_RATIO`, an admitted guess with no
##     independent validation. Every flight-time number this build reports rides on it. Custom
##     packs make this urgent because capacity is the whole reason someone enters a custom pack —
##     they are chasing flight time, and flight time is the number they will check against a
##     stopwatch.
##
## ---------------------------------------------------------------------------
## THE TWO CROSS-CHECKS, AND WHY EACH IS WHERE IT IS
## ---------------------------------------------------------------------------
##
## g/Wh BANDS. LiPo packs in this catalog run 6.4-8.6 g/Wh (median 8.06, spread 1.34x); Li-ion run
## 6.8-7.5 (median 7.12, spread 1.08x). A pack far outside its chemistry's band is a typo — grams
## for ounces, or a decimal slip in mAh — and it produces an aircraft whose weight and energy do
## not agree. Warn, never block, because a slightly-out-of-band pack is a curiosity and the point
## is to describe it rather than to grey it out.
##
## CHEMISTRY vs C. Li-ion in this catalog is 10C; LiPo is 30-120C. A Li-ion pack entered at 75C is
## almost certainly a chemistry mis-selection, and it would let a long-range pack claim punch-out
## current it physically cannot deliver — which then bites twice, because `Build.pack_max_amps`
## reads C as a hard cap on the whole build. So a Li-ion pack claiming a LiPo-class C rating gets
## a warning naming both fields, and the builder can act on the one that is actually wrong.

## The C rating above which a Li-ion pack is almost certainly a chemistry mis-selection. Set at
## 20, which sits well above the 10C every Li-ion in the shipped catalog carries and well below
## the 30-120C every LiPo carries — the gap between the two is the whole reason this check works.
const LI_ION_C_SUSPICIOUS_ABOVE := 20.0


## Every pack g/Wh band this catalog has to say something about, by chemistry. Derived at call
## time from the shipped catalog rather than hardcoded — see the same argument in
## MotorPlausibility.k_t_band_for_prop for why. Returns min, max and count; count 0 means the
## chemistry has no shipped packs, in which case the check bows out rather than inventing a
## band it cannot measure against.
static func g_per_wh_band(catalog: PartsCatalog, chemistry: String) -> Dictionary:
	var lowest := INF
	var highest := -INF
	var count := 0
	for pack in catalog.list_category("battery"):
		# Shipped packs only. A custom pack in the band would let a builder's typo widen the very
		# band that is meant to catch it — the same defence MotorPlausibility applies.
		if PartsCatalog.is_custom(str((pack as Dictionary).get("part_id", ""))):
			continue
		if str((pack as Dictionary).get("specs", {}).get("chemistry", "")) != chemistry:
			continue
		var g_per_wh := _g_per_wh_of(pack as Dictionary)
		if g_per_wh <= 0.0:
			continue
		lowest = minf(lowest, g_per_wh)
		highest = maxf(highest, g_per_wh)
		count += 1
	if count == 0:
		return {"low": 0.0, "high": INF, "count": 0}
	return {"low": lowest, "high": highest, "count": count}


static func _g_per_wh_of(pack: Dictionary) -> float:
	var specs: Dictionary = pack.get("specs", {})
	var mah := float(specs.get("mah", 0.0))
	var nominal_v := float(specs.get("nominal_v", 0.0))
	var mass_g := float(pack.get("mass_g", 0.0))
	var wh := nominal_v * mah / 1000.0
	if wh <= 0.0:
		return 0.0
	return mass_g / wh


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not PartsCatalog.is_custom(str(build.battery.get("part_id", ""))):
		return out

	out.append(_provenance(build.battery))
	out.append_array(_g_per_wh(build.catalog, build.battery))
	out.append_array(_chemistry_vs_c(build.battery))
	return out


## Custom-pack provenance, in one sentence that says both things: the derived resistance is an
## assumption reproduced (not a measurement), and every flight-time figure this build shows is
## multiplied by FLIGHT_CURRENT_TO_HOVER_RATIO, which is an admitted guess. The name of the
## constant appears literally in the message — a builder chasing an unexpected flight time can
## grep for it.
static func _provenance(pack: Dictionary) -> BuildWarning:
	var source := str(pack.get("source", "")).strip_edges()
	var derivation: Dictionary = pack.get("derivation", {})
	var derived_r := bool(derivation.get("internal_r_ohm", true))
	var r_clause := "internal resistance was derived from mAh and C (a self-consistency fit against the shipped catalog's own representative figures, not a measurement)" \
		if derived_r \
		else "internal resistance was your own measurement, kept as entered"
	return BuildWarning.characteristic(&"custom_battery",
		"The %s is a pack you entered yourself (%s). Its %s. Flight time here carries Build.FLIGHT_CURRENT_TO_HOVER_RATIO — an unvalidated multiplier over hover current — so every minute figure on this build is exactly as good as that constant, and a stopwatch is the only thing that will settle it." % [
			pack.get("name", pack.get("part_id", "?")), source, r_clause],
		{"part_id": str(pack.get("part_id", "")), "source": source, "derived_r": derived_r,
			"flight_current_to_hover_ratio": Build.FLIGHT_CURRENT_TO_HOVER_RATIO})


## Mass against energy, per chemistry. A pack that agrees with neither end of its own chemistry's
## band is almost certainly a decimal slip.
static func _g_per_wh(catalog: PartsCatalog, pack: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var chemistry := str(pack.get("specs", {}).get("chemistry", ""))
	var band := g_per_wh_band(catalog, chemistry)
	if int(band["count"]) == 0:
		return out
	var g_per_wh := _g_per_wh_of(pack)
	if g_per_wh <= 0.0:
		return out
	var low := float(band["low"])
	var high := float(band["high"])
	if g_per_wh >= low and g_per_wh <= high:
		return out
	var direction := "heavier for its energy" if g_per_wh > high else "lighter for its energy"
	out.append(BuildWarning.characteristic(&"implausible_pack_mass_per_energy",
		"%.0f g on a %s pack of %.1f Wh is %.2f g/Wh, against %.2f-%.2f for every %s pack in the catalog. Lithium chemistries sit in a narrow g/Wh band because the electrolyte, foil and casing scale with the cells — a pack this much %s is usually a decimal slip in the mass or the mAh, not a remarkable chemistry." % [
			float(pack.get("mass_g", 0.0)), chemistry, float(pack.get("specs", {}).get("nominal_v", 0.0)) * float(pack.get("specs", {}).get("mah", 0.0)) / 1000.0,
			g_per_wh, low, high, chemistry, direction],
		{"g_per_wh": g_per_wh, "band_low": low, "band_high": high, "chemistry": chemistry}))
	return out


## A Li-ion pack claiming a LiPo-class C rating. The shipped Li-ion is 10C, every shipped LiPo is
## 30-120C, and a Li-ion entered above LI_ION_C_SUSPICIOUS_ABOVE is almost certainly a chemistry
## mis-selection — the number itself would then feed Build.pack_max_amps as though it were real,
## and the aircraft would claim punch-out current the pack cannot physically deliver.
static func _chemistry_vs_c(pack: Dictionary) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var specs: Dictionary = pack.get("specs", {})
	if str(specs.get("chemistry", "")) != "Li-ion":
		return out
	var c := float(specs.get("c_rating", 0.0))
	if c <= LI_ION_C_SUSPICIOUS_ABOVE:
		return out
	out.append(BuildWarning.characteristic(&"implausible_li_ion_c_rating",
		"%.0fC on a Li-ion pack is well above the 10C the shipped Li-ion packs carry and inside the LiPo range (30-120C). Check whether this is actually a LiPo — Build.pack_max_amps reads C as a hard current cap, so a wrong chemistry lets this build ask for %.0f A from a pack that physically cannot deliver it." % [
			c, float(specs.get("mah", 0.0)) / 1000.0 * c],
		{"c_rating": c, "chemistry": "Li-ion",
			"implied_pack_max_amps": float(specs.get("mah", 0.0)) / 1000.0 * c}))
	return out
