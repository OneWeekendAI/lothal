class_name TestMotorDc
extends RefCounted
## Motor Designer M1: the Kv/Rm/Io model in MotorModel, driven from a real BatteryModel pack.

const KV := 1960.0
const RM := 0.065
const IO := 1.2
const IO_V := 24.0
const K_Q := 1.8e-8


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _pack(r_ohm: float) -> BatteryModel:
	return BatteryModel.create(22.2, r_ohm, 1500.0, 6, "LiPo")


static func run() -> Array:
	var results: Array = []
	var low := MotorModel.operating_point_on_pack(_pack(0.01), 1.0, KV, RM, IO, IO_V, K_Q)
	var high := MotorModel.operating_point_on_pack(_pack(0.08), 1.0, KV, RM, IO, IO_V, K_Q)
	results.append(_t("same motor and prop on a higher-R pack: lower rpm",
		high.rpm < low.rpm, "%.0f vs %.0f" % [high.rpm, low.rpm]))
	results.append(_t("same motor and prop on a higher-R pack: lower current",
		high.current_a < low.current_a, "%.1f vs %.1f" % [high.current_a, low.current_a]))
	results.append(_t("the higher-R pack sags more", high.sag_v > low.sag_v,
		"%.2f vs %.2f" % [high.sag_v, low.sag_v]))
	var pk := _pack(0.02)
	var full := MotorModel.operating_point_on_pack(pk, 1.0, KV, RM, IO, IO_V, K_Q)
	pk.used_mah = 1200.0
	var tired := MotorModel.operating_point_on_pack(pk, 1.0, KV, RM, IO, IO_V, K_Q)
	results.append(_t("a part-discharged pack (lower open-circuit V) spins slower",
		tired.rpm < full.rpm and tired.voc_v < full.voc_v, "%.0f vs %.0f" % [tired.rpm, full.rpm]))
	results.append(_t("terminal voltage is open-circuit minus pack current times R",
		absf(full.terminal_v - (full.voc_v - full.pack_current_a * 0.02)) < 1e-9, ""))
	var part := MotorModel.operating_point_on_pack(_pack(0.02), 0.5, KV, RM, IO, IO_V, K_Q)
	results.append(_t("half throttle: less rpm, pack carries throttle x motor current",
		part.rpm < full.rpm and absf(part.pack_current_a - 0.5 * part.current_a) < 1e-9, ""))
	var kt := MotorModel.kt(1000.0)
	results.append(_t("Kt = 60 / (2 pi Kv)", absf(kt - 60.0 / (TAU * 1000.0)) < 1e-12, str(kt)))
	var w: float = full.rpm * TAU / 60.0
	results.append(_t("solved torque equals the prop load torque",
		absf(full.torque_nm - K_Q * w * w) < 1e-9, ""))
	results.append(_t("efficiency is shaft over electrical power",
		absf(full.efficiency - full.shaft_w / full.electrical_w) < 1e-9 and full.efficiency > 0.5, str(full.efficiency)))
	var th := MotorModel.thermal_mass_j_per_k(8.0, 14.0)
	var h := MotorModel.cooling_w_per_k(30.0, 5.0)
	var t_ss := MotorModel.steady_temp_c(full.loss_w, h)
	results.append(_t("steady temperature is ambient (25) plus loss over conductance",
		absf(t_ss - (25.0 + full.loss_w / h)) < 1e-9 and t_ss > 25.0, str(t_ss)))
	var temp := 25.0
	for i in 2000:
		temp = MotorModel.temp_step_c(temp, full.loss_w, th, h, 0.5)
	results.append(_t("winding temperature settles on the steady value", absf(temp - t_ss) < 1e-3 * t_ss, str(temp)))
	# Old behaviour intact.
	var m := MotorModel.create(KV, 1.0)
	results.append(_t("create()/step() unchanged: max_rpm is Kv x V and step moves toward it",
		absf(m.max_rpm(24.0) - KV * 24.0) < 1e-9 and m.step(0.0, 1.0, 24.0, 0.03) > 0.0, ""))
	return results
