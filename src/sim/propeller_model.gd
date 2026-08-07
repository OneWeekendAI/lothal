class_name PropellerModel
extends RefCounted
## Thrust and reaction torque from motor RPM (physics.md §4): T = k_t * omega^2,
## Q = k_q * omega^2. Coefficients are fit from the manufacturer thrust-table figure
## (max thrust at max RPM) rather than guessed, per physics.md's explicit warning.
##
## k_q has no equivalent published-and-fit figure in v1 (no torque-test table in the
## catalog yet), so it uses a documented rule-of-thumb ratio to k_t. Only the sign of
## reaction torque is load-bearing this week (week1.md test 7); the magnitude ratio can
## be replaced with a fitted value once torque-test tables are authored into the catalog.
##
## The ratio is not a constant across prop sizes: T = C_T*rho*n^2*D^4 and
## Q = C_Q*rho*n^2*D^5, so Q/T scales with diameter. Anchored at 0.02 for a 5" prop.
const K_Q_TO_K_T_RATIO_AT_5IN := 0.02
const K_Q_REFERENCE_DIAMETER_M := 0.127   # 5 inches

## Exponents for moving a fitted k_t from the prop it was measured on to another prop.
## Diameter's D^4 is the dimensional form from physics.md §4 and is exact. Blade count and
## pitch have no such clean law — more blades add thrust with real diminishing returns from
## interference, and static thrust rises sub-linearly with pitch — so these two are
## documented rules of thumb, to be replaced when per-prop thrust tables are authored.
##
## THESE TWO REMAIN UNVALIDATED, and the shipped catalog cannot validate them. The only near-
## matched motor pairs tested on different props (2207 1750KV vs XING2 2207 1750KV on 5x4.3x3 vs
## 5.1x3.5x3; SpeedX GR2306 vs 2306 2450KV on 5x4.3x3 vs 5x5x2) cross two different manufacturers
## whose motor-to-motor k_t disagreement on the SAME prop is 1.79x — larger than the ~30% effect
## these exponents produce. So a validation from the catalog would be measuring the manufacturers'
## own noise, not the exponents. Same shape as LTHL-18: instrument works, no admissible data.
##
## PropExtrapolation names the extrapolation distance rather than pretending it is small.
const BLADE_COUNT_EXPONENT := 0.8
const PITCH_EXPONENT := 0.5

static func fit_k_t(max_thrust_g: float, max_rpm: float) -> float:
	var max_thrust_n := (max_thrust_g / 1000.0) * 9.81
	var max_omega := rpm_to_rad_s(max_rpm)
	return max_thrust_n / (max_omega * max_omega)

## Moves a k_t fitted on `from_prop` onto `to_prop`. Geometry dictionaries carry
## diameter_m, pitch_m and blades (see Build._prop_geometry).
static func scale_k_t_to_prop(k_t_from: float, from_prop: Dictionary, to_prop: Dictionary) -> float:
	var diameter_ratio: float = to_prop.diameter_m / from_prop.diameter_m
	var blade_ratio: float = to_prop.blades / from_prop.blades
	var pitch_ratio: float = to_prop.pitch_m / from_prop.pitch_m
	return k_t_from * pow(diameter_ratio, 4.0) * pow(blade_ratio, BLADE_COUNT_EXPONENT) * pow(pitch_ratio, PITCH_EXPONENT)

static func fit_k_q(k_t: float, diameter_m: float) -> float:
	return k_t * K_Q_TO_K_T_RATIO_AT_5IN * (diameter_m / K_Q_REFERENCE_DIAMETER_M)

static func rpm_to_rad_s(rpm: float) -> float:
	return rpm * TAU / 60.0

static func thrust_n(k_t: float, rpm: float) -> float:
	var omega := rpm_to_rad_s(rpm)
	return k_t * omega * omega

static func reaction_torque_n_m(k_q: float, rpm: float) -> float:
	var omega := rpm_to_rad_s(rpm)
	return k_q * omega * omega
