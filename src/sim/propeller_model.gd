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
const K_Q_TO_K_T_RATIO := 0.02

static func fit_k_t(max_thrust_g: float, max_rpm: float) -> float:
	var max_thrust_n := (max_thrust_g / 1000.0) * 9.81
	var max_omega := rpm_to_rad_s(max_rpm)
	return max_thrust_n / (max_omega * max_omega)

static func fit_k_q(k_t: float) -> float:
	return k_t * K_Q_TO_K_T_RATIO

static func rpm_to_rad_s(rpm: float) -> float:
	return rpm * TAU / 60.0

static func thrust_n(k_t: float, rpm: float) -> float:
	var omega := rpm_to_rad_s(rpm)
	return k_t * omega * omega

static func reaction_torque_n_m(k_q: float, rpm: float) -> float:
	var omega := rpm_to_rad_s(rpm)
	return k_q * omega * omega
