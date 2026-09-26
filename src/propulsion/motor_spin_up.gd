class_name MotorSpinUp
extends RefCounted
## The mechanical time constant of a motor + prop pair, computed rather than assumed —
## propulsion.md §3.4 and slice P7.
##
## ## What this replaces
##
## Before P7, `motor.rs` carried `const SPIN_UP_TAU_S = 0.03`, shared across every motor in
## the catalog. That number is the difference between a 0802 whoop responding in about a
## millisecond and a 2808 cinelifter responding in tens. Sharing it made throttle response
## look the same on hardware that behaves nothing alike.
##
## ## The physics, in the same shape the doc states
##
##     tau = J_total / ( K_e² / R + 2 · k_q · Omega_ref )
##
##     J_total   = J_rotor  +  J_blade         (blade term already sums over N_b)
##     K_e       = 60 / (2·pi·KV)              back-EMF constant, V per rad/s
##     R         = R_winding, ohms             recovered from the thrust_test row
##     k_q       = torque coefficient, Nm/(rad/s)²   from BEMT for the fitted prop
##     Omega_ref = linearisation point, rad/s        used at the test-row loaded RPM
##
## The two slopes in the denominator are `d(motor torque)/d(Omega)` (electrical back-EMF
## resisting an Omega perturbation) and `d(prop torque)/d(Omega)` (aerodynamic damping),
## both evaluated at the operating point. Their sum is the restoring stiffness that
## divides into J_total to give a first-order lag.
##
## ## Where R_winding comes from — and the honest limit
##
## Vendors publish milliohm figures for some named-product motors; the class-typical rows
## in `motors.json` have no such source, so this file RECOVERS R from the thrust_test row
## the catalog already carries. At full-throttle steady state the motor equation gives:
##
##     Q_load(Omega_loaded) = K_t · (V - K_e · Omega_loaded) / R      (motor)
##     Q_load(Omega_loaded) = k_q · Omega_loaded²                     (prop)
##
## Torque balance in current form: Q = K_t · I_max = k_q · Omega_loaded².
## So Omega_loaded = sqrt(K_t · I_max / k_q), and then:
##
##     R = ( V - K_e · Omega_loaded ) / I_max
##
## `k_q` is the same BEMT-derived `Build.k_q` the flight physics uses on the fitted prop, so
## no new fit is invented. If the recovery yields `R <= 0` (the motor is running so close to
## no-load that back-EMF equals voltage, which happens at very light loading of a highly
## rated motor) the fallback is a class-typical R scaled from stator diameter, and the tier
## flag on the return dictionary says so. Never a silent zero.
##
## ## What the pre-P7 constant carried, and why deleting it matters
##
## `SPIN_UP_TAU_S = 0.03` lived in `rust/src/motor.rs`. It was the same value the pre-BEMT
## bench had used in 2025, before the catalog even had 16 motors, and it never moved when
## the spread of stator sizes widened from one to five. Deleting it and replacing the read
## with `self.tau_s` — populated per motor by this file — is the whole point of P7.
##
## ## Doubles, deliberately
##
## Same rule as `BladeGeometry`: every sum is in GDScript `float` (a double). k_q is small
## (order 1e-8 N·m·s²), R is small (tens of mohms), and their product with Omega² spans many
## orders of magnitude — a single-precision path would round Omega_loaded² into the noise on
## small motors and quietly report zero R.

const _DEFAULT_BELL_DIAMETER_RATIO := 1.27
const _DEFAULT_BELL_HEIGHT_RATIO := 2.6
## What fraction of a motor's published mass rotates. Real FPV motors publish a total mass;
## bench teardowns of 2207-class motors put the rotating half (bell + magnets + shaft + nut)
## at 0.38-0.44 of that total, and small stator motors (0802) trend higher because their
## stator is proportionally lighter. 0.40 is the class-typical starting point; a `specs`
## override may replace it per motor as bench data lands.
const _DEFAULT_BELL_MASS_FRACTION := 0.40

## The fallback the deleted constant carried, kept as an explicit safety net so a caller
## that CANNOT compute tau (a bench probe, a stub) produces the pre-P7 numbers instead of a
## silent zero. Every flight-path caller SHOULD compute; this is here so the failure mode is
## "identity with old code" rather than "instant motor".
const FALLBACK_TAU_S := 0.03


## The full computation. Returns a dictionary with the tau plus its components, so callers
## that want to render "why is my tau what it is" (the propulsion panel, the ESC bench)
## have every intermediate without recomputing:
##
##     {
##         "tau_s":                float,     seconds — hand this to MotorModel.create_with_tau
##         "j_rotor_kg_m2":        float,
##         "j_blade_kg_m2":        float,     already summed over N_b
##         "j_total_kg_m2":        float,
##         "r_winding_ohm":        float,
##         "omega_loaded_rad_s":   float,     the linearisation point
##         "k_e_v_per_rad_s":      float,
##         "d_q_motor_d_omega":    float,     negative — motor torque falls as omega rises
##         "d_q_load_d_omega":     float,     positive — aero damping
##         "tier":                 String,    "recovered" | "fallback_r" | "fallback_all"
##     }
##
## `motor` is the raw catalog dictionary (same shape callers already pass to MotorMesh).
## `fitted_prop_doc` is the propeller the motor is CURRENTLY driving — its k² and mass
## are what J_blade sees. `test_prop_doc` is the propeller the thrust_test row was measured
## with; k_q comes from THIS prop (that's what the R recovery uses). `k_q_at_test_prop` and
## `k_q_at_fit_prop` are the BEMT figures Build already computed — passing them in rather
## than recomputing keeps this file scale-free.
static func compute(motor: Dictionary,
		fitted_prop_doc: PropellerDocument,
		materials: FrameMaterials,
		k_q_at_fit_prop: float,
		k_q_at_test_prop: float,
		omega_hover_rad_s: float) -> Dictionary:
	var specs: Dictionary = motor.get("specs", {})
	var kv: float = float(specs.get("kv", 0.0))
	if kv <= 0.0:
		return _fallback_all("KV missing")

	var k_e: float = 60.0 / (TAU * kv)  # V per rad/s = Nm per amp in SI (K_t == K_e)

	# --- Rotor inertia from bell geometry ---
	var stator_diameter_m := float(specs.get("stator_diameter_mm", 0.0)) / 1000.0
	var bell_diameter_ratio := float(specs.get("bell_diameter_ratio", _DEFAULT_BELL_DIAMETER_RATIO))
	var bell_mass_fraction := float(specs.get("bell_mass_fraction", _DEFAULT_BELL_MASS_FRACTION))
	var motor_mass_g := float(motor.get("mass_g", 0.0))
	var bell_mass_kg := (motor_mass_g * bell_mass_fraction) / 1000.0
	var bell_radius_m := stator_diameter_m * bell_diameter_ratio * 0.5
	# Thin-shell approximation: J = m · r². Bells are a cylindrical wall (~1 mm steel) with
	# a magnet ring on the inner face and a thin top plate; the wall carries almost all the
	# radius so a solid-cylinder 0.5·m·r² would understate J by roughly the same fraction as
	# the top-plate correction would trim it. `r²` is the honest first cut for a bench-class
	# figure; a per-motor moment-of-inertia measurement would replace this term without
	# touching any of the rest.
	var j_rotor: float = bell_mass_kg * bell_radius_m * bell_radius_m

	# --- Blade inertia from the fitted prop ---
	# BladeGeometry.blade_inertia_from_published_kg_m2 is the honest form (m_published · k² · R²).
	# It already sums over N_b via the volume integral. Zero on a drawn planform with no
	# published mass — the panel handles that; here we fall back to the density-integral form.
	var j_blade: float = BladeGeometry.blade_inertia_from_published_kg_m2(fitted_prop_doc)
	if j_blade <= 0.0:
		j_blade = BladeGeometry.blade_inertia_kg_m2(fitted_prop_doc, materials)

	var j_total: float = j_rotor + j_blade
	if j_total <= 0.0:
		return _fallback_all("J_total non-positive")

	# --- R_winding from the thrust_test row ---
	var test: Dictionary = motor.get("thrust_test", {})
	var test_voltage_v: float = float(test.get("voltage_v", 0.0))
	var max_amps: float = float(specs.get("max_amps", 0.0))
	var recovery := _recover_r_winding(k_e, test_voltage_v, max_amps, k_q_at_test_prop)
	var r_winding: float = recovery["r_ohm"]
	var omega_loaded: float = recovery["omega_loaded_rad_s"]
	var tier: String = recovery["tier"]

	if r_winding <= 0.0:
		# Never a silent zero. The fallback here scales R from stator diameter following the
		# same rule of thumb bench measurements broadly follow (R falls with stator size): a
		# 22 mm stator is roughly 40 mΩ, an 8 mm stator roughly 165 mΩ, a 28 mm stator
		# roughly 29 mΩ. Report the fallback tier so the panel does not claim recovery it
		# does not have.
		r_winding = _fallback_r_winding(stator_diameter_m)
		tier = "fallback_r"

	# --- Denominator: motor slope + load slope, both evaluated at the linearisation point ---
	# Use hover Omega as the linearisation point for k_q · omega if provided; otherwise the
	# loaded RPM the recovery landed at. Neither is exactly "the" operating point of a real
	# flight (throttle varies), and picking hover gives the tau a builder feels when a stick
	# input asks for a small correction — the case P7's acceptance is written about.
	var omega_ref: float = omega_hover_rad_s if omega_hover_rad_s > 0.0 else omega_loaded

	var d_q_motor_d_omega: float = -(k_e * k_e) / r_winding
	var d_q_load_d_omega: float = 2.0 * k_q_at_fit_prop * omega_ref
	var denom: float = -d_q_motor_d_omega + d_q_load_d_omega  # both restoring, add
	if denom <= 0.0:
		return _fallback_all("denominator non-positive")

	var tau: float = j_total / denom

	return {
		"tau_s": tau,
		"j_rotor_kg_m2": j_rotor,
		"j_blade_kg_m2": j_blade,
		"j_total_kg_m2": j_total,
		"r_winding_ohm": r_winding,
		"omega_loaded_rad_s": omega_loaded,
		"omega_ref_rad_s": omega_ref,
		"k_e_v_per_rad_s": k_e,
		"d_q_motor_d_omega": d_q_motor_d_omega,
		"d_q_load_d_omega": d_q_load_d_omega,
		"tier": tier,
	}


## Just the number, for the common case where the caller only wants to pass tau to MotorModel.
## Wraps compute() and returns the fallback on any failure so the flight path never sees zero.
static func tau_s(motor: Dictionary,
		fitted_prop_doc: PropellerDocument,
		materials: FrameMaterials,
		k_q_at_fit_prop: float,
		k_q_at_test_prop: float,
		omega_hover_rad_s: float) -> float:
	var result := compute(motor, fitted_prop_doc, materials, k_q_at_fit_prop, k_q_at_test_prop,
		omega_hover_rad_s)
	var value: float = float(result.get("tau_s", 0.0))
	return value if value > 0.0 else FALLBACK_TAU_S


## `Q = K_t · I_max = k_q · Omega²`, so Omega_loaded is set by the current-torque balance
## with no assumption about how close to no-load the motor is running.
##   Omega_loaded = sqrt(K_t · I_max / k_q)
##   R            = (V - K_e · Omega_loaded) / I_max
##
## Guards against every degenerate input: missing amps, missing voltage, a k_q so small that
## Omega_loaded exceeds no-load Omega, and a resulting R that would be non-positive. Each
## returns the same shape with an explicit tier the caller reports rather than a masked zero.
static func _recover_r_winding(k_e: float, voltage_v: float, max_amps: float,
		k_q_test: float) -> Dictionary:
	if voltage_v <= 0.0 or max_amps <= 0.0 or k_q_test <= 0.0:
		return {"r_ohm": 0.0, "omega_loaded_rad_s": 0.0, "tier": "insufficient_data"}
	# K_t == K_e in SI units. Naming both here for readability of the physics.
	var k_t := k_e
	var omega_loaded_sq: float = k_t * max_amps / k_q_test
	if omega_loaded_sq <= 0.0:
		return {"r_ohm": 0.0, "omega_loaded_rad_s": 0.0, "tier": "insufficient_data"}
	var omega_loaded: float = sqrt(omega_loaded_sq)
	var back_emf: float = k_e * omega_loaded
	if back_emf >= voltage_v:
		# Torque balance says the motor should be spinning faster than no-load Omega, which
		# means k_q at the test prop is under-estimated (BEMT low) or the row is inconsistent.
		# Report insufficient data rather than a negative R — the fallback R kicks in above.
		return {"r_ohm": 0.0, "omega_loaded_rad_s": omega_loaded, "tier": "insufficient_data"}
	var r: float = (voltage_v - back_emf) / max_amps
	return {"r_ohm": r, "omega_loaded_rad_s": omega_loaded, "tier": "recovered"}


## The stator-size fallback for R_winding when the test row cannot recover one. Bench data
## from published motor teardowns (mainly BLHeli/BetaFlight tuning threads, aggregated) puts
## small-stator motors in the high tens-to-hundreds of mΩ and large-stator motors in the tens;
## the fit `R = 40 mΩ · (22 mm / D_stator_mm)^1.4` is class-typical, not a spec — the tier flag on
## the compute() return says so.
static func _fallback_r_winding(stator_diameter_m: float) -> float:
	if stator_diameter_m <= 0.0:
		return 0.05  # 50 mohm, mid-catalog default
	var d_mm: float = stator_diameter_m * 1000.0
	var reference_mohm := 40.0  # 22 mm stator ≈ 40 mΩ, class-typical
	var mohm: float = reference_mohm * pow(22.0 / d_mm, 1.4)
	return mohm / 1000.0


static func _fallback_all(reason: String) -> Dictionary:
	return {
		"tau_s": FALLBACK_TAU_S,
		"j_rotor_kg_m2": 0.0,
		"j_blade_kg_m2": 0.0,
		"j_total_kg_m2": 0.0,
		"r_winding_ohm": 0.0,
		"omega_loaded_rad_s": 0.0,
		"omega_ref_rad_s": 0.0,
		"k_e_v_per_rad_s": 0.0,
		"d_q_motor_d_omega": 0.0,
		"d_q_load_d_omega": 0.0,
		"tier": "fallback_all:" + reason,
	}
