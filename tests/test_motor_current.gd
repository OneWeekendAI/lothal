class_name TestMotorCurrent
extends RefCounted
## Motor Designer M4: the drone's motor current comes from the DC model (Kv, Rm, Io) when the
## motor's record says current_model is "dc", and from the legacy rated-amps law otherwise.
##
## The shelf presets carry Rm and Io since M3 but NOT the flag, so they keep their legacy figures
## (tests/test_motor_presets.gd). The first group shows the switch is real and gated; the second
## shows Rm and Io matter to flight figures; the third shows the flying powertrain and the stats
## panel read one model; the last records how far a preset would drift if it were switched.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _build(dc: bool, rm_scale: float = 1.0, io_scale: float = 1.0,
		motor_id: String = ReferenceBuild.MOTOR_ID) -> Build:
	var catalog := PartsCatalog.load_default()
	var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)
	var m: Dictionary = b.motor.duplicate(true)
	m["specs"]["rm_ohm"] = float(m["specs"]["rm_ohm"]) * rm_scale
	m["specs"]["io_a"] = float(m["specs"]["io_a"]) * io_scale
	if dc:
		m["specs"]["current_model"] = "dc"
	b.motor = m
	b._recompute()
	return b


static func run() -> Array:
	var results: Array = []

	var shelf := _build(false)
	var dc := _build(true)
	results.append(_t("a shelf preset (Rm/Io present, no current_model flag) stays on the legacy law",
		not shelf.uses_dc_motor(), ""))
	results.append(_t("the flag switches the build to the DC model", dc.uses_dc_motor(), ""))
	var rpm := 20000.0
	var legacy_i := Fitting.current_at_rpm(rpm, shelf.effective_max_amps, shelf.rated_rpm())
	results.append(_t("unflagged current_at_rpm is exactly the rated-amps law",
		shelf.current_at_rpm(rpm) == legacy_i, "%f vs %f" % [shelf.current_at_rpm(rpm), legacy_i]))
	results.append(_t("flagged current_at_rpm is not",
		absf(dc.current_at_rpm(rpm) - legacy_i) > 0.01, "%f vs %f" % [dc.current_at_rpm(rpm), legacy_i]))
	var no_rm: Dictionary = dc.motor.duplicate(true)
	no_rm["specs"].erase("rm_ohm")
	var stripped := _build(true)
	stripped.motor = no_rm
	results.append(_t("a flagged motor without Rm falls back to the legacy law, not to zeros",
		not stripped.uses_dc_motor(), ""))

	# Rm and Io matter.
	var hi_rm := _build(true, 3.0, 1.0)
	var hi_io := _build(true, 1.0, 3.0)
	var rpm_base := dc.rpm_at_throttle(0.6)
	var rpm_hi_rm := hi_rm.rpm_at_throttle(0.6)
	results.append(_t("more Rm: the same throttle spins slower",
		rpm_hi_rm < rpm_base - 50.0, "%.0f vs %.0f" % [rpm_hi_rm, rpm_base]))
	results.append(_t("more Rm: the hover throttle rises",
		hi_rm.hover_throttle() > dc.hover_throttle() + 0.001,
		"%.4f vs %.4f" % [hi_rm.hover_throttle(), dc.hover_throttle()]))
	results.append(_t("more Io: the average flight current rises and the flight time falls",
		hi_io.average_flight_current_a() > dc.average_flight_current_a() + 0.05
		and hi_io.flight_time_min() < dc.flight_time_min() - 0.01,
		"%.3f A %.3f min vs %.3f A %.3f min" % [hi_io.average_flight_current_a(), hi_io.flight_time_min(),
			dc.average_flight_current_a(), dc.flight_time_min()]))
	results.append(_t("unflagged, Rm and Io change nothing (legacy ignores them)",
		_build(false, 3.0, 3.0).flight_time_min() == shelf.flight_time_min(), ""))
	results.append(_t("the fresh-pack draw at full throttle follows the DC model",
		absf(hi_rm.fresh_draw_at_a(1.0) - dc.fresh_draw_at_a(1.0)) > 1.0,
		"%.1f vs %.1f" % [hi_rm.fresh_draw_at_a(1.0), dc.fresh_draw_at_a(1.0)]))

	# One model between the panel and the flying powertrain.
	for pair in [["legacy", shelf], ["dc", dc], ["dc high Rm", hi_rm]]:
		var b: Build = pair[1]
		var g := b.prop_geometry()
		var pt := Powertrain.create(b.motor_model(), b.k_t, b.k_q, b.battery_model(),
			b.effective_max_amps, b.rated_rpm(), b.pole_pairs(), g.blades, g.diameter_m * 0.5,
			g.pitch_m, b.air.kgm3(), b.blade_chord())
		results.append(_t("%s: the powertrain's per-motor current equals the build's" % pair[0],
			absf(pt.current_at_rpm(18000.0) - b.current_at_rpm(18000.0)) < 1e-9,
			"%f vs %f" % [pt.current_at_rpm(18000.0), b.current_at_rpm(18000.0)]))
		if b.uses_dc_motor():
			# The flying tick and the stats panel solve the same operating point: priming at 0.5
			# must land where Fitting's DC solve does, on the powertrain's own pack.
			pt.prime(0.5)
			var args := b._dc_args()
			var expect := Fitting.dc_rpm_at_throttle(0.5, 1.0, args[0], args[1], args[2], args[3], args[4],
				pt.battery.resting_voltage_v(), pt.battery.internal_r_ohm, 4.0)
			results.append(_t("%s: priming the powertrain at 0.5 reaches the DC solve's rpm" % pair[0],
				absf(pt.motor_rpm[0] - expect) < 0.01 * expect, "%.0f vs %.0f" % [pt.motor_rpm[0], expect]))
			var amps := Fitting.dc_pack_draw_a(0.5, args[0], args[1], args[2], args[3], args[4],
				pt.battery.resting_voltage_v(), pt.battery.internal_r_ohm, 4.0)
			results.append(_t("%s: the pack current the powertrain draws is the DC solve's" % pair[0],
				absf(pt.last_current_total_a - amps) < 0.02 * amps, "%.2f vs %.2f" % [pt.last_current_total_a, amps]))

	# The drift a preset would see if it were switched: recorded in the detail, bounded loosely.
	var rows: Array = []
	var worst := 0.0
	for raw in JsonStore.read_document("res://data/parts/motors.json").get("parts", []):
		var id := String(raw["part_id"])
		var p := PartsCatalog.load_default().get_part(id)
		var base := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID, id,
			String(p["thrust_test"]["prop_id"]), ReferenceBuild.BATTERY_ID)
		var sw := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID, id,
			String(p["thrust_test"]["prop_id"]), ReferenceBuild.BATTERY_ID)
		var m2: Dictionary = sw.motor.duplicate(true)
		m2["specs"]["current_model"] = "dc"
		sw.motor = m2
		sw._recompute()
		var a := base.flight_time_min()
		var d := sw.flight_time_min()
		if a > 0.0:
			worst = maxf(worst, absf(d - a) / a)
			rows.append("%s %+.0f%%" % [id.replace("motor_", ""), 100.0 * (d - a) / a])
	results.append(_t("DRIFT if presets were switched to dc (flight time, % vs legacy)",
		worst < 10.0, "worst %.0f%%: %s" % [100.0 * worst, ", ".join(rows)]))
	return results
