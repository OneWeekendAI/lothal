class_name RotorHForce
extends RefCounted
## B1: the in-plane drag (H-force) of a rotor in edgewise flow, from blade-element theory.
##
## Source: Leishman, Principles of Helicopter Aerodynamics, 2nd ed., sec. 3.3-3.4 and 4.x (blade-element forces in
## forward flight, the rotor H-force); Johnson, Helicopter Theory, sec. 5.x (C_H for a rotor without flapping). A
## blade element at azimuth psi sees U_T = Omega r + V sin(psi) in plane and U_P = Lambda through the disc (axial
## airspeed plus the induced velocity). Its in-plane force against rotation is phi dL + dD with phi = U_P / U_T:
##   dF_x = 0.5 rho c [a (theta U_T U_P - U_P^2) + C_d0 U_T^2] dr
## and the H-force is the azimuthal mean of dF_x sin(psi) over B blades. The means are exact (reverse flow ignored):
## <U_T sin psi> = V / 2, <U_T^2 sin psi> = Omega r V, <sin psi> = 0, so
##   H = V (Omega * P + Lambda * I),  P = (B rho / 2) Int c C_d0 r dr,  I = (B rho a / 4) Int c theta dr.
## In coefficient form this is the textbook C_H = (sigma C_d0 / 4) mu + (sigma a / 4) theta lambda mu: the PROFILE
## term and the INDUCED/INFLOW term. Both are linear in the edgewise speed V at a given Omega and Lambda, so at a hover
## it is a linear drag (the accelerometer sees velocity); at speed it follows BET, because Lambda grows with the axial
## airspeed through a leaned disc and Omega with the throttle, not with K * T * v.
##
## BLADE FLAPPING (added B1 second pass): the rotor in edgewise flow flaps back once per rev, tilting the thrust vector
## away from the edgewise airspeed, which is a second in-plane force T * a1 (Bangura and Mahony, "Nonlinear dynamic
## modeling for high performance control of a quadrotor", ACRA 2012; Faessler, Franchi, Scaramuzza, "Differential
## flatness of quadrotor dynamics subject to rotor drag", RA-L 2018). The classical first-harmonic tilt of a rotor with
## a centrally hinged blade is a1 = 2 mu (4/3 theta_75 - lambda) / (1 - mu^2/2) (Leishman eq. 4.x, Johnson sec. 5.x);
## a stiff or offset hinge scales it by a flap-response factor that depends on the Lock number and the flap frequency
## ratio. FLAP_RESPONSE is that factor and it is a LABELLED ESTIMATE: no stiffness or Lock-number data exist for small
## plastic props. It is chosen so the TOTAL low-speed linear drag of the reference 5" build (profile + induced +
## flapping) is 0.345 /s, inside the 0.3-0.5 /s measured for small quads (Faessler et al. 2018 identify rotor-drag
## coefficients of this size; Bangura/Mahony report the same order). Its value above 1 means the measured drag is larger
## than a rigid hinged blade predicts; the excess is attributed to the elastic bending of thin plastic blades, which a
## rigid-hinge model leaves out. Because a1 falls as the inflow ratio lambda grows, the term fades at speed through a
## leaned disc, which is what keeps the 108.2 km/h top-speed calibration achievable (Build.REFERENCE_DRAG_AREA_M2).
## The tilt is clamped at zero: past lambda = 4/3 theta_75 the blades are stalled and linear theory no longer holds. Section data are the BEMT's own (bemt.rs): the same chord planform,
## pitch helix or authored twist, a0_eff = 5.5 and C_d0 = 0.03 with the same low-Reynolds correction.
##
## NO DOUBLE COUNT with the BEMT path: bemt.rs returns thrust along the rotor axis and torque about it, an
## axisymmetric closure (prop_tunnel.gd, "this model has no blade asymmetry"). The H-force is the in-plane, first
## harmonic (sin psi) part of the same element forces, which an azimuthal-mean solve integrates to exactly zero.
## So the two paths produce orthogonal force components: BEMT -> body +Y and the shaft; H -> the body XZ plane.

## bemt.rs POLAR_A0_EFF / POLAR_C_D0 and its low-Re correction constants, mirrored.
const A0_EFF := 5.5
const C_D0 := 0.03
const LOW_RE_REF := 500000.0
const LOW_RE_EXPONENT := 0.5
const LOW_RE_TIP_MPS := 150.0
const AIR_MU_PAS := 1.81e-5
const RHO_REF := 1.225
const STATIONS := 40
## Induced-velocity fixed point (momentum theory in forward flight), damped, a few passes per tick.
const INFLOW_PASSES := 6
## Flap-response factor on the hinged-blade tilt (see above). LABELLED ESTIMATE, set by the measured total damping.
const FLAP_RESPONSE := 2.0


## Blade pitch angle at 0.75 R (rad), the collective theta_75 of the flapping law.
static func theta_75(radius_m: float, pitch_m: float, twist: PackedFloat64Array) -> float:
	return _theta(pitch_m, 0.75 * radius_m, 0.75, twist)


## Flapping in-plane force per unit edgewise speed (N per m/s) for one rotor making `thrust_n` at `omega`, total inflow
## `inflow` (m/s) and edgewise speed `v_edge`: T * a1 / v_edge with a1 = k * 2 mu (4/3 theta_75 - lambda) / (1 - mu^2/2).
static func flap_per_mps(thrust_n: float, omega: float, radius_m: float, inflow: float, v_edge: float,
		theta75: float, response: float = FLAP_RESPONSE) -> float:
	var tip := omega * radius_m
	if tip <= 1.0 or thrust_n <= 0.0:
		return 0.0
	var mu := v_edge / tip
	var tilt_per_mu := maxf(2.0 * response * (4.0 / 3.0 * theta75 - inflow / tip), 0.0) / maxf(1.0 - 0.5 * mu * mu, 0.5)
	return thrust_n * tilt_per_mu / tip

## Flow (axial, edgewise) in the TIP-PATH PLANE from the shaft-frame flow, for a disc flapped back by `a1` rad (away
## from the edgewise airspeed). Flapping tilts the thrust; it does no work, so the power path must read the flow the
## tilted disc sees: axial V_ax cos a1 - V_e sin a1, edgewise V_e cos a1 + V_ax sin a1 (Leishman sec. 4.x: inflow
## and power are referred to the TPP). Energy check: T x (drop in axial flow) = T a1 V_e = H_flap V_e, exactly the
## work a shaft-frame reading would have charged for the flapping force.
static func tpp_flow(v_axial: float, v_edge: float, a1: float) -> Vector2:
	var c := cos(a1)
	var s := sin(a1)
	return Vector2(v_axial * c - v_edge * s, v_edge * c + v_axial * s)


## Profile coefficient P (kg) and induced coefficient I (kg/m), at density `rho`. Zero for a blade with no planform.
static func coefficients(blades: float, radius_m: float, pitch_m: float, chord_mm: PackedFloat64Array,
		twist: PackedFloat64Array, rho: float) -> Vector2:
	if chord_mm.size() < 4 or radius_m <= 0.0 or blades <= 0.0:
		return Vector2.ZERO
	var hub := clampf(chord_mm[0], 0.0, 1.0) * radius_m
	var dr := (radius_m - hub) / float(STATIONS)
	var int_p := 0.0
	var int_i := 0.0
	for k in STATIONS:
		var r := hub + (float(k) + 0.5) * dr
		var x := r / radius_m
		var c := _chord_m(chord_mm, x)
		if c <= 0.0:
			continue
		var re := RHO_REF * LOW_RE_TIP_MPS * maxf(x, 0.05) * c / AIR_MU_PAS
		var cd0 := C_D0 * (pow(LOW_RE_REF / re, LOW_RE_EXPONENT) if re > 0.0 and re < LOW_RE_REF else 1.0)
		int_p += c * cd0 * r * dr
		int_i += c * _theta(pitch_m, r, x, twist) * dr
	return Vector2(0.5 * blades * rho * int_p, 0.25 * blades * rho * A0_EFF * int_i)


## Total inflow velocity Lambda (m/s, positive down through the disc) for a rotor making `thrust_n` with an axial
## airspeed `v_axial` (positive when the rotor moves along its own thrust axis) and edgewise airspeed `v_edge`.
## Glauert: v_i = T / (2 rho A sqrt(v_edge^2 + (v_axial + v_i)^2)).
static func inflow_mps(thrust_n: float, v_axial: float, v_edge: float, rho: float, radius_m: float) -> float:
	var area := PI * radius_m * radius_m
	if thrust_n <= 0.0 or area <= 0.0:
		return v_axial
	var v_i := sqrt(thrust_n / (2.0 * rho * area))
	for _p in INFLOW_PASSES:
		var u := sqrt(v_edge * v_edge + (v_axial + v_i) * (v_axial + v_i))
		v_i = 0.5 * (v_i + thrust_n / (2.0 * rho * area * maxf(u, 0.5 * v_i)))
	return v_axial + v_i


## H-force magnitude per unit edgewise speed (N per m/s) for one rotor: Omega * P + Lambda * I.
static func per_mps(coeffs: Vector2, omega: float, inflow: float) -> float:
	return omega * coeffs.x + inflow * coeffs.y


static func _theta(pitch_m: float, r: float, x: float, twist: PackedFloat64Array) -> float:
	var n := twist.size() >> 1
	if n == 0:
		return atan(pitch_m / (TAU * r))
	if x <= twist[0]:
		return twist[1]
	var last := 2 * (n - 1)
	if x >= twist[last]:
		return twist[last + 1]
	for i in n - 1:
		var x0 := twist[2 * i]
		var x1 := twist[2 * i + 2]
		if x >= x0 and x <= x1:
			return twist[2 * i + 1] + (twist[2 * i + 3] - twist[2 * i + 1]) * (x - x0) / (x1 - x0)
	return twist[last + 1]


static func _chord_m(pts: PackedFloat64Array, x: float) -> float:
	var n := pts.size() >> 1
	if n < 2:
		return 0.0
	if x <= pts[0]:
		return pts[1] * 0.001
	var last := 2 * (n - 1)
	if x >= pts[last]:
		return pts[last + 1] * 0.001
	for i in n - 1:
		var x0 := pts[2 * i]
		var x1 := pts[2 * i + 2]
		if x >= x0 and x <= x1:
			return (pts[2 * i + 1] + (pts[2 * i + 3] - pts[2 * i + 1]) * (x - x0) / (x1 - x0)) * 0.001
	return 0.0
