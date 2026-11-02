class_name PackBench
extends RefCounted
## The bench behind the pack designer: pure, headless time series on BatteryModel and its
## display-only thermal step. Every figure is ideal / datasheet.
##
## THERMAL IS DISPLAY-ONLY. cell_temp_c is computed beside the electrical run and never read back
## into resistance or voltage (tests rerun with the heat switched off and compare v_live exactly).
##
## RECHARGE is a standard CC/CV profile. During constant current the terminal voltage is the
## resting voltage plus I x (pack R + a charge polarisation term); when it reaches the chemistry's
## maximum the charger holds that voltage and the current tapers until it falls under C/20. The
## polarisation term (CHARGE_POLARISATION_OHM_AH_PER_CELL / capacity) is an ideal guess, labelled
## as one: it is what puts the CC/CV hand-over below 100 % the way real chargers do.

const AMBIENT_C := 25.0
const TAPER_END_C := 1.0 / 20.0
const MAX_STEPS := 400000

## Ohm x Ah per cell; a guess, not a measurement.
const CHARGE_POLARISATION_OHM_AH_PER_CELL := 0.04


## Constant-current discharge from full to the voltage floor (or empty).
static func discharge(design: PackDesign, current_a: float, dt_s: float = 1.0) -> Dictionary:
	return _run_discharge(design, current_a, dt_s, true)


static func _run_discharge(design: PackDesign, current_a: float, dt_s: float, thermal: bool) -> Dictionary:
	var f := design.derive()
	var lay := _layout(design, f)
	var chem := design.chemistry()
	var pack := BatteryModel.create(float(f.nominal_v), float(f.internal_r_ohm), float(f.mah),
		int(lay.s), chem)
	var floor_v := BatteryModel.min_cell_v(chem)
	var t := PackedFloat64Array()
	var v_live := PackedFloat64Array()
	var v_rest := PackedFloat64Array()
	var temp := PackedFloat64Array()
	var used := PackedFloat64Array()
	var temp_c := AMBIENT_C
	var clock := 0.0
	var wh := 0.0
	var sag := 0.0
	var stopped := "empty"
	var cell_a := current_a / float(lay.p)
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		var rest := pack.resting_voltage_v()
		var live := pack.voltage_live(current_a)
		t.append(clock)
		v_rest.append(rest)
		v_live.append(live)
		temp.append(temp_c)
		used.append(pack.used_mah)
		sag = maxf(sag, rest - live)
		if live / float(lay.s) <= floor_v:
			stopped = "cutoff"
			break
		if pack.used_mah >= pack.capacity_mah:
			break
		wh += live * current_a * dt_s / 3600.0
		pack.drain(current_a, dt_s)
		if thermal:
			temp_c = BatteryModel.cell_temp_step(temp_c, cell_a, float(lay.r_cell), float(lay.m_cell), dt_s)
		else:
			temp_c = AMBIENT_C
		clock += dt_s
	return {
		"t": t, "v_live": v_live, "v_rest": v_rest, "cell_temp_c": temp, "used_mah": used,
		"run_time_s": clock, "wh_delivered": wh, "peak_sag_v": sag, "stopped_by": stopped,
		"current_a": current_a,
	}


## CC to the chemistry's maximum cell voltage, then CV until the current falls under C/20.
## `from_used_mah` is the charge already taken out of the pack; 0 means already full.
static func recharge(design: PackDesign, from_used_mah: float, c_rate: float, dt_s: float = 1.0) -> Dictionary:
	var f := design.derive()
	var lay := _layout(design, f)
	var chem := design.chemistry()
	var cap_mah := float(f.mah)
	var ah := cap_mah / 1000.0
	var r_total := float(f.internal_r_ohm) + float(lay.s) * CHARGE_POLARISATION_OHM_AH_PER_CELL / maxf(ah, 1e-9)
	var v_max := float(lay.s) * BatteryModel.max_cell_v(chem)
	var i_cc := c_rate * ah
	var i_end := ah * TAPER_END_C
	var pack := BatteryModel.create(float(f.nominal_v), float(f.internal_r_ohm), cap_mah, int(lay.s), chem)
	pack.used_mah = clampf(from_used_mah, 0.0, cap_mah)
	var t := PackedFloat64Array()
	var v := PackedFloat64Array()
	var i := PackedFloat64Array()
	var clock := 0.0
	var cv_start := 0.0
	var in_cv := false
	if pack.used_mah <= 0.0 or i_cc <= 0.0:
		return {"t": t, "v": v, "i": i, "time_to_full_s": 0.0, "cv_start_s": 0.0}
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		var rest := pack.resting_voltage_v()
		var cur := i_cc
		var volts := rest + cur * r_total
		if not in_cv and volts >= v_max:
			in_cv = true
			cv_start = clock
		if in_cv:
			volts = v_max
			cur = minf(i_cc, maxf(v_max - rest, 0.0) / r_total)
		t.append(clock)
		v.append(volts)
		i.append(cur)
		if in_cv and cur < i_end:
			break
		if pack.used_mah <= 0.0:
			break
		pack.used_mah = maxf(pack.used_mah - cur * dt_s / 3.6, 0.0)
		clock += dt_s
	return {"t": t, "v": v, "i": i, "time_to_full_s": clock, "cv_start_s": cv_start}


static func this_drone_current_a(build: Build) -> float:
	return build.average_flight_current_a()


static func peak_drone_current_a(build: Build) -> float:
	return build.fresh_draw_at_a(build.max_throttle_fraction())


## Plain words for each limit the run crossed. `build` adds the drone's peak-current check;
## `charge_c` (NAN to skip) the charge-rate check.
static func warnings(design: PackDesign, run: Dictionary, build: Build = null,
		charge_c: float = NAN) -> Array[String]:
	var out: Array[String] = []
	var f := design.derive()
	var chem := design.chemistry()
	var mah := float(f.mah)
	var cur := float(run.get("current_a", 0.0))

	if String(run.get("stopped_by", "")) == "cutoff":
		var used: PackedFloat64Array = run.used_mah
		if used.size() > 0 and used[used.size() - 1] < Build.USABLE_CAPACITY_FRACTION * mah:
			out.append("A cell fell below its minimum voltage (%.1f V) after only %.0f%% of the pack was used. The pack cannot hold this load." % [
				BatteryModel.min_cell_v(chem),
				100.0 * used[used.size() - 1] / maxf(mah, 1e-9)])
	if cur > float(f.cont_a) and float(f.cont_a) > 0.0:
		out.append("The load is %.0f A, over the pack's continuous rating of %.0f A." % [cur, float(f.cont_a)])
	var temps: PackedFloat64Array = run.get("cell_temp_c", PackedFloat64Array())
	var peak_t := -1e30
	for x in temps:
		peak_t = maxf(peak_t, x)
	if peak_t > BatteryModel.max_temp_c(chem):
		out.append("Cell temperature reaches %.0f C, over the %.0f C limit for %s." % [
			peak_t, BatteryModel.max_temp_c(chem), chem])
	if not is_nan(charge_c) and charge_c > BatteryModel.max_charge_c(chem):
		out.append("A charge rate of %.1fC is over the %.1fC maximum for %s." % [
			charge_c, BatteryModel.max_charge_c(chem), chem])
	if build != null:
		var peak := peak_drone_current_a(build)
		if peak > float(f.burst_a) and float(f.burst_a) > 0.0:
			out.append("This drone can draw a peak of %.0f A, more than the pack's burst rating of %.0f A." % [
				peak, float(f.burst_a)])
	return out


## The chart's voltage range: the pack's own empty and full resting voltage, rounded outward to
## whole volts so the lines never touch the frame (and so a Vector2's float32 cannot clip them).
static func voltage_axis(design: PackDesign) -> Vector2:
	var f := design.derive()
	return Vector2(floorf(float(f.empty_v)), ceilf(float(f.full_v)))


## Series count, parallel count and per-cell figures for the thermal step. A legacy pack has no
## cell data of its own, so it is one string of series cells sharing its typed mass and resistance.
static func _layout(design: PackDesign, f: Dictionary) -> Dictionary:
	if design.is_legacy():
		var s := maxi(int(design.legacy_specs.get("cells", 1)), 1)
		return {"s": s, "p": 1, "r_cell": float(f.internal_r_ohm) / float(s),
			"m_cell": float(f.mass_g) / float(s)}
	var s2 := clampi(design.series, PackDesign.S_RANGE.x, PackDesign.S_RANGE.y)
	var p2 := clampi(design.parallel, PackDesign.P_RANGE.x, PackDesign.P_RANGE.y)
	var cs: Dictionary = design.cell.get("specs", {})
	return {"s": s2, "p": p2, "r_cell": float(cs.get("r_mohm", 0.0)) / 1000.0,
		"m_cell": float(cs.get("mass_g", 0.0))}
