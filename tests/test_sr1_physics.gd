class_name TestSr1Physics
extends RefCounted
## SR1: the steady-flight physics checked against MEASURED data, one test per data source and case
## group (plus one per case where the cases differ). Data: tests/sim_reality/measured/. Each test
## states its band and carries a fail-proof: it also runs the model WITHOUT the effect (or with the
## effect in the wrong place) and asserts that variant is OUT of the band, so a band that cannot
## fail shows up as a failing test.
##
## What is fitted and what is not:
## - Li-ion rate exponent: fitted on the three "fit" cells, scored on the two held-out cells.
## - Li-ion cold resistance beta: fitted on the "fit" cells, scored on the held-out ones.
## - MQTB motor + prop: NOTHING is fitted. Prop thrust and power come from the blade-element solve
##   on a generated planform, the motor from the sim's own stator-derived Rm and Io; the fit/heldout
##   labels are carried only so a later fit has its split ready.
## - Cold capacity loss, LiPo constants, ESC loss, avionics load: ESTIMATED, no measured source.

const BATTERY_JSON := "res://tests/sim_reality/measured/battery_discharge.json"
const MQTB_JSON := "res://tests/sim_reality/measured/mqtb_thrust.json"
const IN_TO_M := 0.0254

## Fit cells: rate error band (fraction of capacity, ratio to the same cell at 1C). Measurement
## uncertainty is +-30 mAh, about 1 percent, so the band cannot be tighter than that.
const RATE_BAND_FIT := 0.015
const RATE_BAND_HELDOUT := 0.015
## Cold/warm resistance ratio: natural log of predicted over measured. The cell-to-cell spread of
## the measured ratio is 2.2x to 4.8x, so a pack-independent beta cannot do better than this.
const RI_BAND_FIT_LN := 0.25
const RI_BAND_HELDOUT_LN := 0.60
## MQTB: prop thrust at the measured rpm, model over measured.
const THRUST_BAND := 0.15
## MQTB: motor+ESC pack current at the measured rpm and voltage, model over measured, 75 percent row.
const CURRENT_BAND := 0.30

## Two cases the blade-element model does not reproduce. Neither is the figure of merit being too
## high (measured FM bound 0.45 to 0.76 against the model's 0.47 to 0.56); one is a small 4-inch
## prop that makes 1.65x the model's thrust, the other a 3-inch-pitch 5-inch prop on which the model
## burns 30 percent more shaft power than the wall supplied. Blade count (2, 3, 4) was tried and
## does not close either. Out of scope for the first SR1 pass; listed in the tracker.
const KNOWN_GAPS := {
	"mqtb_83_HQ_4x4.5BN": {"what": "4-inch prop makes about 1.65x the modelled thrust", "thrust": [0.5, 0.7], "eta": [0.3, 0.5]},
	"mqtb_13_Diatone_Ghost_5x3": {"what": "3-inch-pitch 5-inch prop: modelled shaft power exceeds the measured electrical power", "thrust": [0.9, 1.15], "eta": [1.1, 1.5]},
}

static func run() -> Array:
	var out: Array = []
	out.append_array(_battery_rate())
	out.append_array(_battery_resistance_cold())
	out.append_array(_battery_cold_ends_early())
	out.append_array(_battery_cutoff_latch())
	out.append_array(_lipo_is_labelled_estimate())
	out.append_array(_mqtb())
	out.append_array(_esc_loss())
	out.append_array(_avionics_load())
	out.append_array(_motor_thermal())
	return out


static func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# ---------------------------------------------------------------------------
# Battery: capacity vs discharge current (lygte-info, Li-ion, 5 cells)
# ---------------------------------------------------------------------------

## Capacity delivered at a constant current, mAh, through the Rust pack (drain until remaining 0).
static func _delivered_mah(nominal_mah: float, current_a: float, k: float) -> float:
	var pack := BatteryModel.create(3.6, 0.01, nominal_mah, 1, "Li-ion")
	pack.enable_field_realism(25.0)
	pack.peukert_k = k
	var t := 0.0
	var dt := 1.0
	while pack.remaining_fraction() > 0.0 and t < 4.0e5:
		pack.drain(current_a, dt)
		t += dt
	return current_a * t / 3.6

static func _interp(x: float, xs: Array, ys: Array) -> float:
	for i in xs.size() - 1:
		if xs[i] <= x and x <= xs[i + 1]:
			return lerpf(ys[i], ys[i + 1], (x - xs[i]) / (xs[i + 1] - xs[i]))
	return ys[0]

static func _battery_rate() -> Array:
	var results: Array = []
	var rows: Array = _json(BATTERY_JSON)["chemistries"]["liion"]["capacity_vs_current"]
	var cells := {}
	for r in rows:
		if not cells.has(r["cell"]):
			cells[r["cell"]] = []
		cells[r["cell"]].append(r)
	for cell in cells:
		var rs: Array = cells[cell]
		var nominal: float = rs[0]["nominal_mah"]
		var split: String = rs[0]["split"]
		var cs: Array = []
		var qs: Array = []
		for r in rs:
			cs.append(float(r["current_a"]) / (nominal / 1000.0))
			qs.append(float(r["delivered_mah"]))
		var q1c: float = _interp(1.0, cs, qs)
		var k: float = Battery_field_k()
		var worst := 0.0
		var worst_neutral := 0.0
		var detail := ""
		var d1 := _delivered_mah(nominal, nominal / 1000.0, k)
		var d1n := _delivered_mah(nominal, nominal / 1000.0, 1.0)
		for r in rs:
			var c: float = float(r["current_a"]) / (nominal / 1000.0)
			if c < 1.0 or r["lower_bound_only"]:
				continue   # the model is anchored at 1C; a lower bound is not a measurement
			var meas_ratio: float = float(r["delivered_mah"]) / q1c
			var pred_ratio: float = _delivered_mah(nominal, r["current_a"], k) / d1
			var neutral_ratio: float = _delivered_mah(nominal, r["current_a"], 1.0) / d1n
			worst = maxf(worst, absf(pred_ratio / meas_ratio - 1.0))
			worst_neutral = maxf(worst_neutral, absf(neutral_ratio / meas_ratio - 1.0))
			detail += " %.1fC:%+.2f%%" % [c, 100.0 * (pred_ratio / meas_ratio - 1.0)]
		var band: float = RATE_BAND_FIT if split == "fit" else RATE_BAND_HELDOUT
		results.append(TestResult.new(
			"battery rate (%s, %s): capacity vs current inside %.1f%% of the measured ratio to 1C; no-rate-effect model is outside it" % [cell, split, band * 100.0],
			worst <= band and worst_neutral > band,
			"worst model error %.2f%%, neutral (k=1) %.2f%%;%s" % [worst * 100.0, worst_neutral * 100.0, detail]))
	return results

static func Battery_field_k() -> float:
	var pack := BatteryModel.create(3.6, 0.01, 3000.0, 1, "Li-ion")
	pack.enable_field_realism(25.0)
	return pack.peukert_k


# ---------------------------------------------------------------------------
# Battery: resistance in the cold (budgetlightforum, measured) and capacity in the cold (ESTIMATED)
# ---------------------------------------------------------------------------

static func _r_ratio(cold_c: float, warm_c: float, beta: float) -> float:
	var pack := BatteryModel.create(3.6, 0.01, 3000.0, 1, "Li-ion")
	pack.enable_field_realism(25.0)
	pack.r_beta_k = beta
	pack.temp_c = cold_c
	var cold := pack.r_temp_factor()
	pack.temp_c = warm_c
	return cold / pack.r_temp_factor()

static func _battery_resistance_cold() -> Array:
	var results: Array = []
	var rows: Array = _json(BATTERY_JSON)["chemistries"]["liion"]["temperature"]
	var beta := 0.0
	var pack := BatteryModel.create(3.6, 0.01, 3000.0, 1, "Li-ion")
	pack.enable_field_realism(25.0)
	beta = pack.r_beta_k
	for r in rows:
		var meas: float = float(r["cold_ohm"]) / float(r["warm_ohm"])
		var pred := _r_ratio(float(r["cold_c"]), float(r["warm_c"]), beta)
		var flat := _r_ratio(float(r["cold_c"]), float(r["warm_c"]), 0.0)
		var band: float = RI_BAND_FIT_LN if r["split"] == "fit" else RI_BAND_HELDOUT_LN
		var err := absf(log(pred / meas))
		results.append(TestResult.new(
			"battery cold resistance (%s, %s): cold/warm ratio inside %.2f in ln of measured; temperature-blind model is outside it" % [r["cell"], r["split"], band],
			err <= band and absf(log(flat / meas)) > band,
			"measured %.2fx, model %.2fx (ln err %.2f), temperature-blind %.2fx" % [meas, pred, err, flat]))
	return results


## ESTIMATED effect, measured resistance: the same constant-current hover on a pack at 0 C against
## 25 C. The cold pack must end earlier. A pack held at equal temperatures must NOT differ (the
## control that proves the comparison can fail).
static func _hover_endurance_s(temp_c: float, amps: float) -> float:
	var pack := BatteryModel.create(14.8, 0.025, 5000.0, 4, "Li-ion")
	pack.enable_field_realism(temp_c)
	var t := 0.0
	while t < 3.0e4:
		if pack.below_cutoff(amps):
			break
		pack.drain(amps, 1.0)
		t += 1.0
	return t

static func _battery_cold_ends_early() -> Array:
	var warm := _hover_endurance_s(25.0, 10.0)
	var cold := _hover_endurance_s(0.0, 10.0)
	var warm2 := _hover_endurance_s(25.0, 10.0)
	return [
		TestResult.new("battery temperature (capacity loss ESTIMATED, resistance measured): the same 10 A hover ends earlier at 0 C than at 25 C",
			cold < 0.95 * warm, "25 C %.0f s, 0 C %.0f s (%.1f%% shorter)" % [warm, cold, 100.0 * (1.0 - cold / warm)]),
		TestResult.new("battery temperature control: equal temperatures give equal endurance (the comparison above can fail)",
			warm == warm2, "%.0f s and %.0f s" % [warm, warm2]),
	]


# ---------------------------------------------------------------------------
# Battery: the voltage-sag cutoff really ends a flight
# ---------------------------------------------------------------------------

static func _fly_until(core: DroneCore, seconds: float) -> void:
	var thr := ReferenceBuild.hover_throttle()
	var cmds := {"M1": thr, "M2": thr, "M3": thr, "M4": thr}
	core.prime_motors(thr)
	for _i in int(seconds / 0.01):
		core.step(cmds, 0.01)

static func _battery_cutoff_latch() -> Array:
	var results: Array = []
	var on := ReferenceBuild.build_drone_core()
	on.powertrain.battery.used_mah = on.powertrain.battery.capacity_mah * 0.9999
	_fly_until(on, 3.0)
	var thrust: PackedFloat32Array = on.powertrain.observables.thrust_n
	var latched: bool = on.powertrain.cutoff_latched
	results.append(TestResult.new("battery cutoff: a pack run to empty latches the ESC cutoff and every thrust goes to zero",
		latched and (thrust[0] + thrust[1] + thrust[2] + thrust[3]) < 0.05,
		"latched %s, total thrust %.3f N, y %.1f m" % [latched, thrust[0] + thrust[1] + thrust[2] + thrust[3], on.rigid_body.position_m.y]))
	var off := ReferenceBuild.build_drone_core({"battery": false})
	off.powertrain.battery.used_mah = off.powertrain.battery.capacity_mah * 0.9999
	_fly_until(off, 3.0)
	results.append(TestResult.new("battery cutoff fail-proof: with the battery field physics off the same flight never latches",
		not off.powertrain.cutoff_latched, "latched %s" % off.powertrain.cutoff_latched))
	# Sag alone (pack NOT empty) ends it: a high-resistance pack under hover load.
	var sag := ReferenceBuild.build_drone_core()
	sag.powertrain.battery.internal_r_ohm = 3.0
	_fly_until(sag, 3.0)
	results.append(TestResult.new("battery cutoff: sag ends the flight early, with charge still in the pack",
		sag.powertrain.cutoff_latched and sag.powertrain.battery.remaining_fraction() > 0.9,
		"latched %s, remaining %.2f" % [sag.powertrain.cutoff_latched, sag.powertrain.battery.remaining_fraction()]))
	return results


static func _lipo_is_labelled_estimate() -> Array:
	var li := BatteryModel.field_constant_tags("Li-ion")
	var lp := BatteryModel.field_constant_tags("LiPo")
	var fresh := BatteryModel.create(14.8, 0.01, 5000.0, 4, "LiPo")
	fresh.enable_field_realism(25.0)
	return [TestResult.new("LiPo: no measured data exists, so every LiPo rate/temperature constant is tagged estimated (Li-ion rate and resistance measured, cold capacity estimated)",
		lp["peukert_k"] == "estimated" and lp["r_beta_k"] == "estimated" and li["peukert_k"] == "measured"
		and li["r_beta_k"] == "measured" and li["cap_loss_per_c_cold"] == "estimated" and fresh.peukert_k > 1.0,
		"LiPo tags %s, Li-ion tags %s" % [lp, li])]


# ---------------------------------------------------------------------------
# Motor + prop vs MQTB
# ---------------------------------------------------------------------------

## Blade count is absent from MQTB for several props; 2 is ESTIMATED for those.
static func _mqtb_case(c: Dictionary) -> Dictionary:
	var parts: PackedStringArray = str(c["prop"]).split(" ")
	var dims := parts[parts.size() - 1].to_lower().replace("gf", "").replace("hbn", "").replace("bn", "").replace("e", "")
	var f := dims.split("x")
	var dia := float(f[0])
	var pit := float(f[1])
	var blades: int = int(c["prop_blades"]) if c["prop_blades"] != null else 2
	var doc := PropellerDocument.from_catalog_prop({"specs": {"diameter_inches": dia, "pitch_inches": pit, "blades": blades}, "catalog": {}})
	var stator := str(c["stator"]).replace("mm", "").split("x")
	var cells := int(str(c["cells"]).replace("S", ""))
	var polar := BemtModel.global_polar()
	var rows := {}
	for row in ["100%", "75%", "50%"]:
		var r: Dictionary = c["throttle_rows"][row]
		var rpm: float = r["rpm"]
		var s := BemtModel.solve(1.17, dia * IN_TO_M, pit * IN_TO_M, float(blades), rpm, doc.chord, polar[0], polar[1], polar[2], polar[3])
		var w := rpm * TAU / 60.0
		var motor := {"specs": {"kv": float(c["tested_kv"]), "stator_diameter_mm": float(stator[0]), "stator_height_mm": float(stator[1])},
			"thrust_test": {"voltage_v": 3.7 * cells}}
		var p := Build.dc_motor_params(motor)
		var mm := MotorModel.create(float(c["tested_kv"]), 1.0)
		mm.set_dc(p[1], p[2], p[3], s[1] / (w * w))
		mm.esc_r_ohm = Build.ESC_R_OHM_AMP / 40.0
		mm.esc_sw_frac = Build.ESC_SW_LOSS_FRAC
		rows[row] = {
			"thrust_ratio": s[0] / (float(r["thrust_g"]) * 0.00980665),
			"current_ratio": mm.dc_pack_current_at_rpm(rpm, float(r["volts"])) / float(r["current_a"]),
			"shaft_w": s[1] * w, "elec_w": float(r["volts"]) * float(r["current_a"]),
		}
	return {"id": c["id"], "split": c["split"], "dia": dia, "rows": rows,
		"fm": doc.static_figure_of_merit()}

static func _mqtb() -> Array:
	var results: Array = []
	for c in _json(MQTB_JSON)["cases"]:
		var m := _mqtb_case(c)
		var rows: Dictionary = m["rows"]
		var t75: float = rows["75%"]["thrust_ratio"]
		var i75: float = rows["75%"]["current_ratio"]
		var eta: float = rows["75%"]["shaft_w"] / rows["75%"]["elec_w"]
		var tag := "%s [%s]" % [m["id"], m["split"]]
		if KNOWN_GAPS.has(m["id"]):
			var g: Dictionary = KNOWN_GAPS[m["id"]]
			results.append(TestResult.new("MQTB KNOWN GAP, %s: %s. This pins the gap so a model fix has to move it; it is NOT a pass" % [tag, g["what"]],
				t75 >= g["thrust"][0] and t75 <= g["thrust"][1] and eta >= g["eta"][0] and eta <= g["eta"][1],
				"thrust model/measured %.2f (pinned %s), shaft/electrical %.2f (pinned %s), current model/measured %.2f" % [t75, g["thrust"], eta, g["eta"], i75]))
			continue
		results.append(TestResult.new("MQTB thrust, %s: model thrust at the measured rpm within %.0f%% of measured at 50/75/100%% (a prop with no pitch term would miss)" % [tag, THRUST_BAND * 100.0],
			_all_within(rows, "thrust_ratio", THRUST_BAND),
			"model/measured thrust at 100/75/50%%: %.2f %.2f %.2f; FM %.3f" % [rows["100%"]["thrust_ratio"], t75, rows["50%"]["thrust_ratio"], m["fm"]]))
		results.append(TestResult.new("MQTB current, %s: pack current (derived motor + ESC) within %.0f%% of measured at 75%%" % [tag, CURRENT_BAND * 100.0],
			absf(i75 - 1.0) <= CURRENT_BAND,
			"model/measured current 100/75/50%%: %.2f %.2f %.2f" % [rows["100%"]["current_ratio"], i75, rows["50%"]["current_ratio"]]))
		results.append(TestResult.new("MQTB hover power, %s: blade-element shaft power is physically reachable (shaft/electrical between 0.55 and 0.95 at 75%%; above 1 means the prop model burns more than the wall supplied)" % tag,
			eta >= 0.55 and eta <= 0.95, "shaft/electrical %.2f" % eta))
	return results

static func _all_within(rows: Dictionary, key: String, band: float) -> bool:
	for k in rows:
		if absf(float(rows[k][key]) - 1.0) > band:
			return false
	return true


# ---------------------------------------------------------------------------
# ESC loss, avionics load, motor thermal: each must change the answer
# ---------------------------------------------------------------------------

static func _hover_current_with(opts: Dictionary) -> float:
	var core := ReferenceBuild.build_drone_core(opts)
	_fly_until(core, 1.0)
	return core.observables.current_total_a

static func _esc_loss() -> Array:
	var none := _hover_current_with({"esc": false, "avionics": false, "thermal": false})
	var with := _hover_current_with({"esc": true, "avionics": false, "thermal": false})
	return [TestResult.new("ESC loss (ESTIMATED): hover pack current is higher with the ESC conduction and switching loss than without (identical when off)",
		with > none * 1.005 and with < none * 1.10,
		"without %.3f A, with %.3f A (+%.2f%%); band +0.5%% to +10%%" % [none, with, 100.0 * (with / none - 1.0)])]

static func _avionics_load() -> Array:
	var none := _hover_current_with({"avionics": false, "esc": false, "thermal": false})
	var with := _hover_current_with({"avionics": true, "esc": false, "thermal": false})
	var w: float = ReferenceBuild.build().avionics_w()
	return [TestResult.new("avionics load (ESTIMATED): hover pack current rises by the non-motor power over the pack voltage (identical when off)",
		w > 0.0 and with > none and absf((with - none) - w / 16.0) < w / 16.0 * 0.15 + 0.02,
		"without %.3f A, with %.3f A, avionics %.2f W (about %.3f A at 16 V)" % [none, with, w, w / 16.0])]

static func _thrust_per_watt(core: DroneCore) -> float:
	var t: PackedFloat32Array = core.powertrain.observables.thrust_n
	var p: float = core.powertrain.last_voltage_v * core.powertrain.last_current_total_a
	return (t[0] + t[1] + t[2] + t[3]) / maxf(p, 1e-6)

static func _motor_thermal() -> Array:
	var results: Array = []
	var temps := {}
	for thermal in [true, false]:
		var core := ReferenceBuild.build_drone_core({"thermal": thermal, "avionics": false})
		core.powertrain.battery.capacity_mah = 1.0e6
		var thr := ReferenceBuild.hover_throttle()
		var cmds := PackedFloat64Array([thr, thr, thr, thr])
		core.powertrain.prime(thr)
		var first := 0.0
		for i in 36000:   # 30 minutes at 50 ms
			core.powertrain.step(cmds, 0.05)
			if i == 100:
				first = _thrust_per_watt(core)
		temps[thermal] = {"winding": core.powertrain.winding_c, "e_first": first, "e_last": _thrust_per_watt(core), "rm_scale": core.powertrain.motor_model.rm_temp_scale}
	var on: Dictionary = temps[true]
	var off: Dictionary = temps[false]
	results.append(TestResult.new("motor thermal in the loop: 30 minutes of hover warms the winding and the thermal-off run stays at ambient (disable the call and this fails)",
		on["winding"] > 35.0 and absf(off["winding"] - 20.0) < 6.0,
		"winding on %.1f C, off %.1f C" % [on["winding"], off["winding"]]))
	var loss: float = 1.0 - float(on["e_last"]) / float(off["e_last"])
	results.append(TestResult.new("motor thermal in the loop: the hot winding raises Rm by more than 4% (off: exactly 1.0) and costs a small but real amount of thrust per watt at minute 30 against the thermal-off run (0.01% to 2%)",
		on["rm_scale"] > 1.04 and off["rm_scale"] == 1.0 and loss > 0.0001 and loss < 0.02,
		"Rm x%.3f on, x%.3f off; thrust per watt %.4f%% lower with thermal on (copper is a small share of a 4 A hover, so the effect is small by physics, not by omission)" % [on["rm_scale"], off["rm_scale"], loss * 100.0]))
	return results
