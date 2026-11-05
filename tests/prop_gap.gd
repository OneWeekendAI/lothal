class_name PropGap
extends RefCounted
## The model against UIUC wind-tunnel tables, through the shipped Rust solve (spec finding 4). All
## figures are unit-free, so density and rpm cancel except where the model has an rpm of its own.

const FIXTURE := "res://tests/fixtures/uiuc_props.json"
const RHO := 1.225
const INCH_TO_M := 0.0254
const J_STEP := 0.01
const J_MAX := 2.0


static func props() -> Dictionary:
	return JsonStore.read_document(FIXTURE).get("props", {})


## [r/R, chord mm, ...] from the measured c/R column, as `PropellerDocument.chord` stores it.
static func chord_of(p: Dictionary) -> PackedFloat64Array:
	var radius_mm: float = float(p["diameter_in"]) * INCH_TO_M * 1000.0 * 0.5
	var out := PackedFloat64Array()
	for row in p["geom_rR_cR_betaDeg"]:
		out.append(float(row[0]))
		out.append(float(row[1]) * radius_mm)
	return out


## Ct and Cp at an advance ratio. Solve refusals come back zero, which the sweep reads as no thrust.
static func model_point(p: Dictionary, j: float) -> Vector2:
	var d: float = float(p["diameter_in"]) * INCH_TO_M
	var rpm: float = float(p["run_rpm"])
	var n: float = rpm / 60.0
	var polar := BemtModel.global_polar()
	var r := BemtModel.solve_forward(RHO, d, float(p["pitch_in"]) * INCH_TO_M, float(p["blades"]), rpm,
		chord_of(p), polar[0], polar[1], polar[2], polar[3], j * n * d, 0.0)
	return Vector2(r[0] / (RHO * n * n * pow(d, 4.0)), r[1] * TAU * n / (RHO * pow(n, 3.0) * pow(d, 5.0)))


## The model's four figures: static Ct and Cp, peak efficiency with its J, and the zero-thrust J.
static func model_figures(p: Dictionary) -> Dictionary:
	var s := model_point(p, 0.0)
	var peak := 0.0
	var peak_j := 0.0
	var j0 := -1.0
	var prev := s.x
	var j := J_STEP
	while j <= J_MAX:
		var q := model_point(p, j)
		if q.x <= 0.0:
			j0 = j - J_STEP * q.x / (q.x - prev) if q.x != prev else j
			break
		var eta: float = j * q.x / q.y
		if eta > peak:
			peak = eta
			peak_j = j
		prev = q.x
		j += J_STEP
	return {"ct": s.x, "cp": s.y, "eta": peak, "eta_j": peak_j, "j0": j0}


## The same four from the tables. Static is the row nearest the run rpm. The tunnel stops short of
## zero thrust, so J0 is the last two rows extended in a straight line, a small extrapolation.
static func measured_figures(p: Dictionary) -> Dictionary:
	var rpm: float = float(p["run_rpm"])
	var best: Array = p["static_rpm_ct_cp"][0]
	for row in p["static_rpm_ct_cp"]:
		if absf(float(row[0]) - rpm) < absf(float(best[0]) - rpm):
			best = row
	var run: Array = p["run_j_ct_cp_eta"]
	var peak := 0.0
	var peak_j := 0.0
	for row in run:
		if float(row[3]) > peak:
			peak = float(row[3])
			peak_j = float(row[0])
	var a: Array = run[run.size() - 2]
	var b: Array = run[run.size() - 1]
	var j0: float = float(b[0]) + float(b[1]) * (float(b[0]) - float(a[0])) / (float(a[1]) - float(b[1]))
	return {"ct": float(best[1]), "cp": float(best[2]), "eta": peak, "eta_j": peak_j, "j0": j0}
