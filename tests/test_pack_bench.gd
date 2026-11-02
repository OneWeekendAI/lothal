class_name TestPackBench
extends RefCounted
## PackBench: discharge, CC/CV recharge, display-only heat and plain-words warnings.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _has(lines: Array, word: String) -> bool:
	for l in lines:
		if String(l).to_lower().contains(word):
			return true
	return false


static func run() -> Array:
	var results: Array = []
	var lib := CellLibrary.load_default()
	var d := PackDesign.default_design(lib)
	var f := d.derive()
	var ah := float(f.mah) / 1000.0
	var r := float(f.internal_r_ohm)

	var one_c := PackBench.discharge(d, ah)
	var minutes := float(one_c.run_time_s) / 60.0
	results.append(_t("1C discharge of a 1500 mAh pack runs ~60 min to cutoff",
		minutes > 54.0 and minutes < 66.0 and one_c.t.size() > 100, "%.1f min, %s" % [minutes, one_c.stopped_by]))

	results.append(_t("live V = rest - I*R at t0",
		absf(float(one_c.v_live[0]) - (float(one_c.v_rest[0]) - ah * r)) < 1e-9
		and absf(float(one_c.v_rest[0]) - float(f.full_v)) < 0.05, "%s %s" % [one_c.v_live[0], one_c.v_rest[0]]))

	var slow := PackBench.discharge(d, ah * 0.2)
	var expect_wh := float(f.nominal_v) * ah
	results.append(_t("wh_delivered ~ nominal_v * Ah at low C",
		absf(float(slow.wh_delivered) - expect_wh) / expect_wh < 0.10,
		"%.2f vs %.2f" % [slow.wh_delivered, expect_wh]))

	var hot := PackBench.discharge(d, 60.0)
	var cool := PackBench.discharge(d, 6.0)
	var peak_hot := _max(hot.cell_temp_c)
	var peak_cool := _max(cool.cell_temp_c)
	var no_thermal := PackBench._run_discharge(d, 60.0, 1.0, false)
	results.append(_t("temp rises with current and never feeds back into V",
		peak_hot > peak_cool and peak_cool >= 25.0 and peak_hot > 26.0
		and JSON.stringify(no_thermal.v_live) == JSON.stringify(hot.v_live)
		and JSON.stringify(no_thermal.v_rest) == JSON.stringify(hot.v_rest),
		"hot %.1f cool %.1f" % [peak_hot, peak_cool]))

	var sag := PackBench.discharge(d, 60.0)
	results.append(_t("peak sag is the largest rest minus live gap",
		absf(float(sag.peak_sag_v) - 60.0 * r) < 0.02, "%s vs %s" % [sag.peak_sag_v, 60.0 * r]))

	var rc := PackBench.recharge(d, float(f.mah), 1.0)
	var cv_ok := float(rc.cv_start_s) > 0.0 and float(rc.cv_start_s) < float(rc.time_to_full_s)
	var last_i := float(rc.i[rc.i.size() - 1])
	results.append(_t("recharge from empty at 1C takes > 60 min and ends in CV",
		float(rc.time_to_full_s) > 3600.0 and cv_ok and last_i < ah / 20.0 + 1e-9
		and absf(float(rc.v[rc.v.size() - 1]) - float(f.full_v)) < 0.05
		and absf(float(rc.i[0]) - ah) < 1e-9,
		"%.0f s cv@%.0f last I %.3f" % [rc.time_to_full_s, rc.cv_start_s, last_i]))
	results.append(_t("recharge of a full pack takes no time",
		float(PackBench.recharge(d, 0.0, 1.0).time_to_full_s) == 0.0, ""))

	results.append_array(_warnings(lib, d))
	return results


static func _max(a: PackedFloat64Array) -> float:
	var m := -1e30
	for v in a:
		m = maxf(m, v)
	return m


static func _warnings(lib: CellLibrary, d: PackDesign) -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var drone_a := PackBench.this_drone_current_a(build)
	out.append(_t("this drone current equals Build.average_flight_current_a",
		drone_a == build.average_flight_current_a() and drone_a > 0.0, str(drone_a)))
	var peak := PackBench.peak_drone_current_a(build)
	out.append(_t("peak drone current is the full-throttle draw",
		peak == build.fresh_draw_at_a(build.max_throttle_fraction()) and peak > drone_a, str(peak)))

	var calm := PackBench.discharge(d, drone_a)
	var none := PackBench.warnings(d, calm, build, 1.0)
	out.append(_t("the default pack on this drone raises no warning", none.is_empty(), str(none)))

	var abuse := PackBench.discharge(d, 400.0)
	var w1 := PackBench.warnings(d, abuse)
	out.append(_t("warning: a cell sags under its minimum voltage",
		_has(w1, "minimum voltage"), str(w1)))
	var w2 := PackBench.warnings(d, PackBench.discharge(d, 200.0))
	out.append(_t("warning: current over the cell's continuous rating",
		_has(w2, "continuous"), str(w2)))
	var w3 := PackBench.warnings(d, PackBench.discharge(d, 100.0))
	out.append(_t("warning: temperature over the chemistry limit", _has(w3, "temperature"), str(w3)))
	var w4 := PackBench.warnings(d, calm, null, 9.0)
	out.append(_t("warning: charge rate over the maximum", _has(w4, "charge rate"), str(w4)))

	var tiny := PackDesign.default_design(lib)
	tiny.cell = lib.get_cell("cell_lipo_450")
	tiny.series = 4
	var w5 := PackBench.warnings(tiny, PackBench.discharge(tiny, 1.0), build, 1.0)
	out.append(_t("warning: pack cannot supply the drone's peak current",
		_has(w5, "peak") and not _has(w5, "temperature"), "peak %.0f A vs burst %.0f A: %s" % [
			peak, float(tiny.derive().burst_a), str(w5)]))

	var each_distinct := not (_has(w4, "minimum voltage") or _has(w4, "continuous") or _has(w4, "temperature"))
	out.append(_t("a charge-rate warning does not drag the discharge warnings with it", each_distinct, str(w4)))

	# Pigtail ampacity and connector rating: continuous ratings, checked against the sustained load
	# (the harness precedent), never the full-throttle punch.
	var thin := PackDesign.default_design(lib)
	thin.lead_awg = 22
	var w6 := PackBench.warnings(thin, PackBench.discharge(thin, 20.0))
	out.append(_t("warning: pigtail wire over its ampacity (22 AWG at 20 A)",
		_has(w6, "pigtail") and _has(w6, "22 awg"), str(w6)))
	var small_plug := PackDesign.default_design(lib)
	small_plug.connector_family = "XT30"
	small_plug.lead_awg = 12
	var w7 := PackBench.warnings(small_plug, PackBench.discharge(small_plug, 40.0))
	out.append(_t("warning: connector over its continuous rating (XT30 at 40 A)",
		_has(w7, "xt30") and _has(w7, "connector") and not _has(w7, "pigtail"), str(w7)))
	var fat := PackDesign.default_design(lib)
	fat.connector_family = "XT90"
	fat.lead_awg = 12
	var w8 := PackBench.warnings(fat, PackBench.discharge(fat, 30.0))
	out.append(_t("no lead or connector warning when both clear the load",
		not _has(w8, "pigtail") and not _has(w8, "connector"), str(w8)))
	var w9 := PackBench.warnings(thin, calm, build)
	out.append(_t("with a drone the lead is judged on its sustained draw, not the punch-out",
		_has(w9, "pigtail") == (drone_a > WireGauge.ampacity_a(22)), "%.1f A: %s" % [drone_a, str(w9)]))

	var ax := PackBench.voltage_axis(d)
	var fig := d.derive()
	out.append(_t("voltage axis spans the pack's own empty and full resting voltage",
		ax.x <= float(fig.empty_v) and ax.y >= float(fig.full_v) and ax.y - ax.x < float(fig.full_v), str(ax)))
	return out
