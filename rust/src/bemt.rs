//! BEMT core (P4) — propulsion.md §4.1–§4.2, pure, in Rust beside propeller.rs.
//!
//! Blade-element momentum theory for a fixed-geometry rotor. The disc is divided into annuli;
//! at each annulus the blade-element thrust and torque are closed against momentum theory
//! through a fixed-point iteration on the induced velocity v_i. Thrust, torque and the two
//! power components become quadratures along the radius, not fitted scalars — §0's inversion
//! of the propulsion chain.
//!
//! Forward flight and descent refusal (P6) live below `solve` as `solve_forward`,
//! `thrust_ratio_forward` and `power_ratio_forward`. The static path is unchanged: `solve`
//! remains hover-only and byte-identical to the P4/P5 solve, so nothing calibrated at the
//! anchor moves. The forward-flight ratios are anchored-at-exactly-1 at V=0 by a short
//! circuit (the same discipline test_calibration.gd's identity uses), and descent (V_ax < 0)
//! delegates to the static solve rather than extrapolating a fixed point that has no
//! contractivity there.
//!
//! `solve` returns [thrust_N, torque_N_m, induced_power_W, profile_power_W, max_residual].
//! max_residual is the relative mismatch between the blade-element and momentum thrusts on the
//! LAST fixed-point pass, maxed over annuli — the number §9's P4 convergence proof is written
//! against, and proven across the whole catalog in tests/test_bemt.gd.
//!
//! The iteration count is FIXED, with the same argument as `INFLOW_ITERATIONS` in propeller.rs:
//! the solve must cost the same every call, so the count is fixed and proven sufficient by the
//! catalog test rather than tuned per operating point.
//!
//! FINDING, proven by tests/test_bemt.gd: 12 iterations does NOT converge the whole catalog.
//! The fixed-point contracts at roughly λ ≈ 0.6 per iteration for the low-solidity large props
//! (7", 8", 10"), so 12 leaves a ~0.5% per-annulus residual there, while the 5" and smaller
//! props have already settled to 1e-7. This is a property of the dimensionless rotor (the
//! hover solution is self-similar in RPM, so the residual is RPM-independent), not of any one
//! operating point. The count was raised to 20, where the worst catalog residual is ~1e-4 — a
//! comfortable margin below the 1e-3 the convergence proof asserts — rather than leaving the
//! proof's bound moved to fit a 12 that failed it.
//!
//! The section polar (§4.2) is C_l = min(a0·α, C_l_max), C_d = C_d0 + k_polar·C_l². a0_eff and
//! C_d0 are the document's two free constants (P5 fits them); k_polar comes from lifting-line
//! theory, C_l_max is the stall cap.

use godot::prelude::*;

/// Sea-level standard air — the same default as propeller.rs's AIR_DENSITY_KGM3, and the same
/// fallback for a non-positive rho (air_density_or_default's second line).
const AIR_DENSITY_KGM3: f64 = 1.225;

/// The fixed induced-velocity iteration count. 20, not 12: see the FINDING in the module docs.
const BEMT_ITERATIONS: i64 = 20;
/// The forward-flight iteration count (P6). 40, not 20, and it is a SEPARATE constant rather
/// than a raise of the static one: the static path is P4/P5's anchor and nothing calibrated
/// against it may move, not even by the last bit. The forward closure is the slower iteration
/// of the two — Glauert's magnitude form is under-relaxed, and the axial branch still has to
/// chase dT's own dependence on the inflow — so at 20 the low-solidity large props (the 8x4.5
/// at 30 m/s axial) sit at a ~5e-3 residual, five times the 1e-3 the proof asserts. At 40 the
/// worst point in the catalog is ~1.5e-5. Same discipline as P4's raise: the count is fixed,
/// so the tick costs the same every tick.
const BEMT_FORWARD_ITERATIONS: i64 = 40;
/// Number of annuli the disc is divided into — §4.1's "~40 annuli".
const BEMT_ANNULLI: i64 = 40;

/// The GLOBAL section polar (§4.2, P5's fit) — the two free constants, fitted once across
/// the whole catalog, never per-prop. C_l = min(a0·α, C_l_max), C_d = C_d0 + k_polar·C_l².
/// a0_eff and C_d0 are the document's two free constants; k_polar comes from lifting-line
/// theory (1/(π·AR·e)), C_l_max is the stall cap.
///
/// P5's polar-fit finding: these values barely matter to the calibration band. A grid over
/// a0_eff ∈ {4.5, 5.5, 6.5} × C_d0 ∈ {0.01, 0.03, 0.06} moves the catalog calibration spread
/// from 4.33x only to 4.03x — the band is set by `chord_is_assumed` and the catalog's own
/// 1.79x motor-to-motor disagreement (motor_plausibility's finding), not by the polar. So the
/// production polar stays at the P4 placeholder values rather than chasing a 0.05x that is
/// catalog noise (§4.4: "if a global polar cannot get the calibration factors into a tight
/// band, that is a real result and it ships as one").
const POLAR_A0_EFF: f64 = 5.5;
const POLAR_C_D0: f64 = 0.03;
const POLAR_K: f64 = 0.02;
const POLAR_C_L_MAX: f64 = 1.0;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct BemtModel;

#[godot_api]
impl BemtModel {
    /// The momentum-theory ideal for a rotor with UNIFORM inflow: a disc carrying a constant
    /// induced velocity v_i makes T = 2ρA·v² at P = T·v, with no tip loss (F = 1) and no
    /// profile drag. Integrating §4.1's annulus closure dT = 4πρr·v²·F·dr over that uniform
    /// v_i must reproduce those closed forms exactly — midpoint rule on a constant integrand
    /// is exact, so the test asserts equality to 1e-9. This is the reference the figure of
    /// merit compares against (§4.5), and the exact statement of "reproduces the
    /// momentum-theory ideal for a uniform-inflow rotor" (P4's first proof obligation).
    ///
    /// Returns [thrust_N, induced_power_W].
    #[func]
    pub fn uniform_inflow_momentum(
        rho: f64,
        diameter_m: f64,
        v_i_mps: f64,
        annuli: i64,
    ) -> PackedFloat64Array {
        if diameter_m <= 0.0 || v_i_mps < 0.0 {
            return PackedFloat64Array::from([0.0, 0.0]);
        }
        let rho = if rho > 0.0 { rho } else { AIR_DENSITY_KGM3 };
        let radius = diameter_m * 0.5;
        let n = annuli.max(1) as usize;
        let dr = radius / n as f64;
        let mut thrust = 0.0;
        let mut power = 0.0;
        for i in 0..n {
            let r = (i as f64 + 0.5) * dr;
            let d_t = momentum_dt(rho, r, v_i_mps, 1.0, dr);
            thrust += d_t;
            power += d_t * v_i_mps;
        }
        PackedFloat64Array::from([thrust, power])
    }

    /// Prandtl's tip-loss factor, §4.1:
    ///
    ///     F = (2/π)·acos( exp( −N_b·(R−r) / (2·r·sin φ) ) )
    ///
    /// Dimensionless in r/R: (R−r)/(2·r·sinφ) = (1−r/R)/(2·(r/R)·sinφ). As N_b → ∞ the
    /// exponent → −∞ and F → 1 (the tip leak closes); at the tip itself F → 0; for finite
    /// N_b it is below 1 and monotone in N_b, saturating at exactly 1.0 once N_b is large
    /// enough that the exponential vanishes below double precision. All four properties are
    /// asserted in tests/test_bemt.gd, because a sign or scale slip breaks each silently.
    #[func]
    pub fn tip_loss_factor(blades: f64, r_over_r: f64, phi_rad: f64) -> f64 {
        if blades <= 0.0 {
            return 0.0;
        }
        // The blade has no element past the tip and the loss is total there.
        if r_over_r >= 1.0 {
            return 0.0;
        }
        // At the hub the exponent diverges and F → 1; φ ≤ 0 (reversed flow) is outside this
        // slice's domain and is not a tip leak that F should be removing.
        if r_over_r <= 0.0 {
            return 1.0;
        }
        let sin_phi = phi_rad.sin();
        if sin_phi <= 0.0 {
            return 1.0;
        }
        let exponent = -blades * (1.0 - r_over_r) / (2.0 * r_over_r * sin_phi);
        (2.0 / std::f64::consts::PI) * exponent.exp().acos()
    }

    /// One static (hover) BEMT solve. See the module docs for the input and return layout.
    ///
    /// `chord_points_mm` is the document's flat [r/R, chord_mm, …] planform; pitch is
    /// geometric (§3.2, β = atan(P / 2πr)), the ONE twist definition the mesh and the integral
    /// share.
    #[func]
    pub fn solve(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        a0_eff: f64,
        c_d0: f64,
        k_polar: f64,
        c_l_max: f64,
    ) -> PackedFloat64Array {
        // Delegates with guard_closure = 0.0 through the same code path — bit-identity is a
        // property of the code path, not a promise the wrapper repeats.
        solve_impl(rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, 0.0)
    }

    /// The P10b closure-aware form. `guard_closure ∈ [0, 1]` post-processes Prandtl's tip-loss
    /// factor F at every annulus:  F_effective = F + closure · (1 − F). At closure = 0.0 this
    /// is `solve` bit-identically (see `_the_closure_anchor_is_exact` in test_bemt_ratios.gd);
    /// at closure = 1.0 the tip leak is closed entirely.
    ///
    /// The scalar closure comes from `PropGuard::tip_loss_closure`, and reaches this solve
    /// through `Build.forward_ratios()` / the static-thrust scaling in `Build._recompute`.
    #[func]
    pub fn solve_with_guard(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        a0_eff: f64,
        c_d0: f64,
        k_polar: f64,
        c_l_max: f64,
        guard_closure: f64,
    ) -> PackedFloat64Array {
        solve_impl(rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, guard_closure)
    }

    /// The per-annulus thrust the static solve integrates — P10e's thrust-distribution overlay.
    ///
    /// Returns `[r_m, dT_N]` interleaved, one pair per annulus, from INSIDE `solve_impl`'s own
    /// loop. It is not a second quadrature and must never become one: `Σ dT` over the returned
    /// pairs equals `solve(...)[0]` bit-identically, because the pairs ARE the addends of that
    /// sum in the order they were added. An overlay that recomputed the integral in GDScript
    /// would be a second copy of a definition free to drift from the first, which is the exact
    /// defect P10d spent a slice deleting from `PropellerMesh`.
    ///
    /// `dT` is a per-ANNULUS thrust, not a density: the caller divides by the annulus width to
    /// plot dT/dr, and the width is `r[1] − r[0]` off the returned grid rather than a constant
    /// re-derived from the diameter. The polar is the global fitted one (§4.2) rather than four
    /// more arguments, because this is a view of the aircraft's own solve and there is no
    /// operating point at which a viewer should be choosing a different section polar than the
    /// physics uses.
    ///
    /// Refusals mirror `solve`'s: a rotor the solve declines returns an EMPTY array, so a caller
    /// cannot mistake a refusal for a blade that makes no thrust.
    #[func]
    pub fn thrust_distribution(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        guard_closure: f64,
    ) -> PackedFloat64Array {
        let mut dist: Vec<f64> = Vec::new();
        solve_impl_collecting(
            rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX, guard_closure, Some(&mut dist));
        PackedFloat64Array::from(dist.as_slice())
    }

    /// P6 — §4.1 with V_ax ≠ 0 and edgewise flow. Extends `solve` with an axial freestream
    /// and an edgewise freestream (the two aircraft velocities the rotor sees when it is
    /// tilted into forward flight: axial along the rotor's own thrust axis, edgewise across
    /// the disc). Descent (V_ax < 0) is DECLINED — the fixed point loses contractivity in the
    /// vortex-ring region and momentum theory has no standing there — and returns the static
    /// answer with a sentinel `max_residual = -1.0` so callers can spot the refusal.
    ///
    /// At each annulus, the momentum closure with total inflow magnitude is
    ///
    ///     dT_mom = 4πρr · v_i · |V_total| · F · dr,
    ///     |V_total| = √( (V_ax + v_i)² + V_edge² )     (the standard Glauert-BEMT hybrid:
    ///                                                    axisymmetric momentum, axial α)
    ///
    /// closed against the blade element dT = 0.5ρU²·N_b·c·(C_l·cosφ − C_d·sinφ)·dr by fixed
    /// point on v_i. `phi` uses ONLY the axial component (V_ax + v_i)/(Ω·r), because BEMT is
    /// axisymmetric and the azimuthal variation an edgewise wind introduces is outside this
    /// model's domain. V_edge enters two places: local dynamic pressure U² through the swirl
    /// term, and the momentum flow magnitude through |V_total|.
    ///
    /// At V_ax = V_edge = 0 this is `solve` by construction: the momentum closure reduces to
    /// 4πρrF·dr · v_i² = dT_blade, which is exactly the hover form. The `thrust_ratio_forward`
    /// and `power_ratio_forward` short-circuits below make that identity BIT-EXACT rather than
    /// arithmetic that happens to land on 1 (test_calibration.gd's discipline).
    ///
    /// Returns [thrust_N, torque_N_m, induced_power_W, profile_power_W, max_residual].
    /// max_residual is defined as in `solve` for V_ax ≥ 0, and is -1.0 for a declined descent.
    #[func]
    pub fn solve_forward(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        a0_eff: f64,
        c_d0: f64,
        k_polar: f64,
        c_l_max: f64,
        v_axial_mps: f64,
        v_edge_mps: f64,
    ) -> PackedFloat64Array {
        solve_forward_impl(rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, v_axial_mps, v_edge_mps, 0.0)
    }

    /// The P10b closure-aware forward solve. See `solve_with_guard` for what `guard_closure`
    /// means; the two share one path, guarding one property: at guard_closure = 0.0 the
    /// closure branch reduces to a no-op and the pre-P10b behaviour is bit-identical.
    #[func]
    pub fn solve_forward_with_guard(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        a0_eff: f64,
        c_d0: f64,
        k_polar: f64,
        c_l_max: f64,
        v_axial_mps: f64,
        v_edge_mps: f64,
        guard_closure: f64,
    ) -> PackedFloat64Array {
        solve_forward_impl(rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, v_axial_mps, v_edge_mps, guard_closure)
    }


    /// The BEMT-native replacement for PropellerModel::thrust_factor — the anchored-at-1
    /// ratio of forward-flight thrust to static thrust at the same RPM. The hover short
    /// circuit is LOAD-BEARING, not an optimisation: at V_ax = V_edge = 0 the function
    /// returns exactly 1.0 by construction (the anchor's discipline), so nothing calibrated
    /// against the static path can move by the millimetre of a rounding difference between
    /// two integrals that are analytically identical.
    ///
    /// Descent (V_ax < 0) also returns 1.0 — the static answer — mirroring the same refusal
    /// the propeller.rs guard uses. That answer is not a claim about descending flight, it is
    /// the model declining to answer outside its valid region.
    #[func]
    pub fn thrust_ratio_forward(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        v_axial_mps: f64,
        v_edge_mps: f64,
    ) -> f64 {
        Self::thrust_ratio_forward_with_guard(
            rho, diameter_m, pitch_m, blades, rpm, chord_points_mm,
            v_axial_mps, v_edge_mps, 0.0)
    }

    /// The P10b closure-aware form. Ratio of forward-flight thrust to STATIC thrust with the
    /// SAME closure applied to both — the tip-loss suppression multiplies both nearly the
    /// same way, so the ratio surface is nearly closure-invariant. That is a prediction
    /// test_bemt_ratios.gd's `[P10b]` block checks rather than an assumption to rely on: if
    /// it fails, the ratios need to move to a per-closure surface and the cache key already
    /// carries the closure bits to make that a mechanical change.
    #[func]
    pub fn thrust_ratio_forward_with_guard(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        v_axial_mps: f64,
        v_edge_mps: f64,
        guard_closure: f64,
    ) -> f64 {
        if (v_axial_mps == 0.0 && v_edge_mps == 0.0) || v_axial_mps < 0.0 {
            return 1.0;
        }
        let static_t = solve_impl(
            rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX, guard_closure)[0];
        if static_t <= 0.0 {
            return 1.0;
        }
        let flight_t = solve_forward_impl(
            rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX,
            v_axial_mps, v_edge_mps, guard_closure)[0];
        (flight_t / static_t).max(0.0).min(1.0)
    }

    /// The P10b static closure factors — what a fitted guard does to STATIC thrust and to
    /// STATIC torque, as a pair, from ONE pair of solves. Returns `[thrust_factor,
    /// torque_factor]`, each `solve(closure)/solve(0)` at reference conditions.
    ///
    /// **Why a pair and not just thrust.** `Build` scales `k_t` by the thrust factor so the
    /// hover throttle the panel quotes matches the flight tick. But `k_q` is fit FROM `k_t`
    /// (`PropellerModel::fit_k_q` is a fixed multiple), so a `k_t` scaled by the closure and a
    /// `k_q` derived from it would move torque in the SAME direction as thrust. The solve says
    /// the opposite: closing the tip leak enlarges the momentum sink, which drops the induced
    /// velocity, which drops induced drag. Measured on the reference 5x4.5x3 at closure
    /// 0.5615 (the cinewhoop duct's 1.5 mm gap): thrust x1.0017, torque x0.9829. Deriving
    /// `k_q` from the scaled `k_t` would report a duct COSTING 0.17% more current when the
    /// model says it SAVES 1.71% — the wrong sign on the one number a duct is fitted for.
    ///
    /// **Both factors are RPM- and rho-invariant**, which is what makes one scalar per
    /// (propeller, closure) enough: the static solve is scale-invariant in Omega (phi and
    /// therefore alpha, C_l, C_d and F are unchanged when V_i and Omega·r scale together) and
    /// linear in rho on both sides of the annulus closure. That is the same self-similarity
    /// `bemt_ratios.rs` rests on, and `test_bemt_ratios.gd`'s
    /// `_the_closure_factors_are_rpm_and_density_invariant` asserts it BIT-EXACTLY rather than
    /// leaving it as this paragraph's assertion.
    ///
    /// **Neither factor is clamped.** An earlier draft pinned the thrust factor to `>= 1.0` on
    /// the reasoning that a duct cannot reduce thrust; that would have hidden exactly the
    /// finding above, where the interesting motion is DOWNWARD and in the other channel. This
    /// file reports what the quadrature says, on `prop_guard.gd`'s own "reported, not clamped"
    /// posture for a negative clearance.
    ///
    /// Returns `[1.0, 1.0]` at closure <= 0.0 by short circuit, and for a degenerate propeller
    /// the solve refuses.
    #[func]
    pub fn static_closure_factors(
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        chord_points_mm: PackedFloat64Array,
        guard_closure: f64,
    ) -> PackedFloat64Array {
        let closure = sanitize_closure(guard_closure);
        if closure <= 0.0 {
            return PackedFloat64Array::from([1.0, 1.0]);
        }
        // The reference operating point. Both factors are invariant in it (see above), so it
        // is a scale for the arithmetic and not a modelling constant — the same posture, and
        // the same two numbers, `bemt_ratios.rs::build_table` already takes.
        let reference_rpm = 20_000.0;
        let reference_rho = AIR_DENSITY_KGM3;
        let base = solve_impl(
            reference_rho, diameter_m, pitch_m, blades, reference_rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX, 0.0);
        if base[0] <= 0.0 || base[1] <= 0.0 {
            return PackedFloat64Array::from([1.0, 1.0]);
        }
        let closed = solve_impl(
            reference_rho, diameter_m, pitch_m, blades, reference_rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX, closure);
        PackedFloat64Array::from([closed[0] / base[0], closed[1] / base[1]])
    }

    /// The thrust half of `static_closure_factors`, for a caller that wants one number. Kept
    /// as its own `#[func]` because `bemt_ratios.rs` caches it on the surface object.
    #[func]
    pub fn static_closure_factor(
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        chord_points_mm: PackedFloat64Array,
        guard_closure: f64,
    ) -> f64 {
        Self::static_closure_factors(diameter_m, pitch_m, blades, chord_points_mm, guard_closure)[0]
    }

    /// The BEMT-native replacement for PropellerModel::power_factor. The anchored-at-1 ratio
    /// of forward-flight shaft power (induced + profile) to the same at V = 0. Same short
    /// circuits as `thrust_ratio_forward`: hover returns 1.0 exactly, descent returns 1.0
    /// (declined).
    ///
    /// The U-shaped power curve — induced power falls with airspeed as the disc is handed
    /// mass flow, profile power rises as U² climbs — falls out of the two quadratures
    /// separately, without a `FIGURE_OF_MERIT` guess anywhere. That is P6's headline: FM
    /// becomes an OUTPUT (test_bemt.gd computes it from `solve`'s return), not an input.
    #[func]
    pub fn power_ratio_forward(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        v_axial_mps: f64,
        v_edge_mps: f64,
    ) -> f64 {
        Self::power_ratio_forward_with_guard(
            rho, diameter_m, pitch_m, blades, rpm, chord_points_mm,
            v_axial_mps, v_edge_mps, 0.0)
    }

    /// The P10b closure-aware form of `power_ratio_forward`. Same posture as
    /// `thrust_ratio_forward_with_guard`.
    #[func]
    pub fn power_ratio_forward_with_guard(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        v_axial_mps: f64,
        v_edge_mps: f64,
        guard_closure: f64,
    ) -> f64 {
        if (v_axial_mps == 0.0 && v_edge_mps == 0.0) || v_axial_mps < 0.0 {
            return 1.0;
        }
        let static_r = solve_impl(
            rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX, guard_closure);
        let static_p = static_r[2] + static_r[3];
        if static_p <= 0.0 {
            return 1.0;
        }
        let flight_r = solve_forward_impl(
            rho, diameter_m, pitch_m, blades, rpm, &chord_points_mm,
            POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX,
            v_axial_mps, v_edge_mps, guard_closure);
        // NO REGENERATION, AND NO DISCONTINUITY EITHER. Past the geometric advance the rotor
        // is unloaded and BEMT's INDUCED power term goes negative — the physically correct
        // statement that a windmilling rotor gives energy back, which this powertrain has no
        // way to receive (propeller.rs's deleted power_factor carried the same refusal, for
        // the same reason: a quad in a fast descent charged its own pack).
        //
        // The refusal used to be `flight_p <= 0 → return 1.0`, and THAT WAS A WORSE ANSWER THAN
        // THE REGIME IT GUARDED. Measured on the reference 5x4.5x3 at 20,000 RPM, the ratio
        // fell smoothly to 0.247 at mu_ax = 0.275 and then JUMPED TO 1.000 at 0.300 — the model
        // asserting that a prop flying past its own zero-thrust point costs exactly what it
        // costs in a hover. On the flight tick that is a step change in pack current at a
        // speed a fast build actually reaches, and it is what made the ratio surface
        // untabulatable: refining the grid made the interpolation error WORSE, which is the
        // signature of a discontinuity rather than of a steep function.
        //
        // The floor goes on the induced term where the sign problem actually is. Profile power
        // — the blades' own drag — is unconditionally real and stays. So an unloaded rotor
        // costs its blade drag and nothing less, the ratio is continuous through the crossing,
        // and no energy comes back.
        let flight_p = flight_r[2].max(0.0) + flight_r[3];
        if flight_p <= 0.0 {
            return 1.0;
        }
        flight_p / static_p
    }

    /// The production global polar (§4.2, P5's fit) as [a0_eff, C_d0, k_polar, C_l_max].
    /// Exposed so the app can report which polar a number was computed with, and so
    /// test_calibration.gd can run the same solve the production functions run.
    #[func]
    pub fn global_polar() -> PackedFloat64Array {
        PackedFloat64Array::from([POLAR_A0_EFF, POLAR_C_D0, POLAR_K, POLAR_C_L_MAX])
    }

    /// The per-prop calibration scalar (§4.4): the single number which, applied
    /// multiplicatively to the BEMT thrust at the measured RPM, reproduces the measured
    /// thrust exactly. Uses the production global polar (POLAR_*), not a caller-supplied one.
    ///
    /// Guarded: a solve that refuses (bad geometry) or produces non-positive thrust returns
    /// 0.0 rather than a division by a degenerate number — the same refusal the solve itself
    /// uses for invalid inputs.
    #[func]
    pub fn calibrate(
        rho: f64,
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        rpm: f64,
        chord_points_mm: PackedFloat64Array,
        measured_thrust_n: f64,
    ) -> f64 {
        if measured_thrust_n <= 0.0 {
            return 0.0;
        }
        let thrust = Self::solve(
            rho,
            diameter_m,
            pitch_m,
            blades,
            rpm,
            chord_points_mm,
            POLAR_A0_EFF,
            POLAR_C_D0,
            POLAR_K,
            POLAR_C_L_MAX,
        )[0];
        if thrust <= 0.0 {
            return 0.0;
        }
        measured_thrust_n / thrust
    }

    /// The cross-prop k_t move (§0), now a BEMT geometry ratio rather than the deleted
    /// `D⁴ · blades^0.8 · pitch^0.5`:
    ///
    ///     k_t_fitted = k_t_from × BEMT(to, rpm) / BEMT(from, rpm)
    ///
    /// Blade count and twist enter the integral where they physically act; the calibration
    /// scalar cancels in the ratio (it is `T_meas / BEMT(from)` on both sides), so no new
    /// fitted numbers are needed to move a fitted k_t to another prop.
    ///
    /// The IDENTITY SHORT-CIRCUIT is load-bearing, not an optimisation: when the target prop
    /// is the prop the k_t was fitted on (the reference build fits its motor on the same
    /// prop it flies), the function returns `k_t_from` untouched, to the bit. That is what
    /// keeps the 496 g / 11.69:1 / 29.6% oracles from moving — the anchor is a short circuit
    /// rather than arithmetic that happens to land on 1 (the same discipline the forward-
    /// flight slice used).
    #[func]
    pub fn scale_k_t_to_prop(
        k_t_from: f64,
        from_d: f64,
        from_pitch: f64,
        from_blades: f64,
        from_chord: PackedFloat64Array,
        to_d: f64,
        to_pitch: f64,
        to_blades: f64,
        to_chord: PackedFloat64Array,
        rpm: f64,
    ) -> f64 {
        // Identity: same geometry AND same planform. The chord comparison is what makes the
        // short-circuit honest — two props with the same diameter/pitch/blades but different
        // chords are different props and must go through the integral.
        if from_d == to_d
            && from_pitch == to_pitch
            && from_blades == to_blades
            && chords_equal(&from_chord, &to_chord)
        {
            return k_t_from;
        }
        let from_t = Self::solve(
            AIR_DENSITY_KGM3,
            from_d,
            from_pitch,
            from_blades,
            rpm,
            from_chord,
            POLAR_A0_EFF,
            POLAR_C_D0,
            POLAR_K,
            POLAR_C_L_MAX,
        )[0];
        if from_t <= 0.0 {
            return 0.0;
        }
        let to_t = Self::solve(
            AIR_DENSITY_KGM3,
            to_d,
            to_pitch,
            to_blades,
            rpm,
            to_chord,
            POLAR_A0_EFF,
            POLAR_C_D0,
            POLAR_K,
            POLAR_C_L_MAX,
        )[0];
        k_t_from * to_t / from_t
    }
}

/// dT = 4πρr·(V_ax + v)·v·F·dr — the momentum closure at one annulus (§4.1), hover form.
fn momentum_dt(rho: f64, r_m: f64, v_mps: f64, f: f64, dr: f64) -> f64 {
    4.0 * std::f64::consts::PI * rho * r_m * v_mps * v_mps * f * dr
}

/// Whether two planforms are the same shape: same length and equal [r/R, chord_mm] pairs,
/// element for element. Used by the identity short-circuit in scale_k_t_to_prop — a planform
/// is a list of pairs, so equality is a walk, not a single comparison.
fn chords_equal(a: &PackedFloat64Array, b: &PackedFloat64Array) -> bool {
    if a.len() != b.len() {
        return false;
    }
    for i in 0..a.len() {
        if a[i] != b[i] {
            return false;
        }
    }
    true
}

/// dT = 0.5ρU²·N_b·c·(C_l·cosφ − C_d·sinφ)·dr — the blade element at one annulus (§4.1).
fn blade_dt(rho: f64, u2: f64, blades: f64, chord_m: f64, cl: f64, cd: f64, phi: f64, dr: f64) -> f64 {
    0.5 * rho * u2 * blades * chord_m * (cl * phi.cos() - cd * phi.sin()) * dr
}

/// The closure, made safe to multiply by: NaN and the infinities become 0.0 (no claim), and
/// anything outside [0, 1] is clamped into it. The bound is the physics's own — a duct closes
/// the tip leak; it cannot make F exceed 1, and it cannot make the leak WORSE than an open
/// blade. `PropGuard.tip_loss_closure`'s rational form already lands inside [0, 1], so this
/// guards the FFI BOUNDARY rather than that caller: `solve_with_guard` is a public `#[func]`
/// and a number arriving from GDScript has had no such form imposed on it.
///
/// Applied ONCE per solve rather than per annulus, so the inner loop stays the two flops the
/// bit-identity argument below is about. At `guard_closure = 0.0` it returns 0.0, so the
/// identity `solve == solve_with_guard(.., 0.0)` survives the sanitiser.
#[inline]
fn sanitize_closure(guard_closure: f64) -> f64 {
    if !guard_closure.is_finite() {
        return 0.0;
    }
    guard_closure.clamp(0.0, 1.0)
}

/// F_effective = F + closure · (1 − F). The tip-loss suppression a duct's tip gap earns
/// through `PropGuard::tip_loss_closure`. At closure = 0.0 this returns f_base unchanged;
/// the expression IS f_base bit-identically in IEEE 754 for every finite f_base (0.0 · x is
/// 0.0 for any finite x, subnormals included), which is the property the P4/P5/P6 oracle
/// preservation rests on. The plan doc §7 walks the case explicitly — do not "optimise" this
/// into `if guard_closure == 0.0 { f_base } else { ... }` without checking the -0.0 case,
/// because a branch introduces a NEW way the equality could break rather than closing an
/// existing one.
#[inline]
fn tip_loss_with_closure(f_base: f64, guard_closure: f64) -> f64 {
    f_base + guard_closure * (1.0 - f_base)
}

/// The static (hover) solve, callable from both `#[func] BemtModel::solve` (closure = 0.0)
/// and `#[func] BemtModel::solve_with_guard` (closure passed through). Extracted so bit-
/// identity at closure = 0.0 is a property of ONE code path rather than two implementations
/// staying in step. `chord_points_mm` is borrowed by reference: the wrapper takes an owned
/// array so the FFI copy happens once at the boundary.
fn solve_impl(
    rho: f64,
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    rpm: f64,
    chord_points_mm: &PackedFloat64Array,
    a0_eff: f64,
    c_d0: f64,
    k_polar: f64,
    c_l_max: f64,
    guard_closure: f64,
) -> PackedFloat64Array {
    solve_impl_collecting(rho, diameter_m, pitch_m, blades, rpm, chord_points_mm,
        a0_eff, c_d0, k_polar, c_l_max, guard_closure, None)
}

/// `solve_impl` with an optional per-annulus tap (P10e's thrust-distribution overlay).
///
/// The tap exists so the overlay reads the addends of the SAME sum `solve` returns rather than a
/// second quadrature written beside it. Every annulus appends `[r_m, dT_N]` to `dist` — the
/// zero-chord ones too, with dT = 0.0, so the vector holds one pair per annulus and its stride-2
/// walk is the identical sequence of IEEE additions `thrust` accumulates. That is what makes the
/// overlay's total BIT-identical to `solve()[0]` rather than merely close, which is the property
/// tests/test_thrust_overlay.gd asserts with `==`.
///
/// `None` is the whole of the cost for every other caller: one branch per annulus, outside the
/// fixed-point loop, and not one line of the arithmetic moved to make room for it.
fn solve_impl_collecting(
    rho: f64,
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    rpm: f64,
    chord_points_mm: &PackedFloat64Array,
    a0_eff: f64,
    c_d0: f64,
    k_polar: f64,
    c_l_max: f64,
    guard_closure: f64,
    mut dist: Option<&mut Vec<f64>>,
) -> PackedFloat64Array {
    let guard_closure = sanitize_closure(guard_closure);
    if blades <= 0.0 || diameter_m <= 0.0 || rpm <= 0.0 || chord_points_mm.len() < 4 {
        return PackedFloat64Array::from([0.0, 0.0, 0.0, 0.0, 1.0]);
    }
    let rho = if rho > 0.0 { rho } else { AIR_DENSITY_KGM3 };
    let radius_m = diameter_m * 0.5;
    let omega = rpm * std::f64::consts::TAU / 60.0;
    let n = BEMT_ANNULLI.max(1) as usize;
    let iters = BEMT_ITERATIONS.max(1) as usize;

    let r_hub_frac = chord_points_mm[0].clamp(0.0, 1.0);
    let r_hub_m = r_hub_frac * radius_m;
    let dr = (radius_m - r_hub_m) / n as f64;

    let mut thrust = 0.0;
    let mut torque = 0.0;
    let mut power_ind = 0.0;
    let mut power_prof = 0.0;
    let mut max_residual = 0.0f64;

    for i in 0..n {
        let r = r_hub_m + (i as f64 + 0.5) * dr;
        let r_frac = r / radius_m;
        let chord_m = chord_at_m(chord_points_mm, r_frac);
        if chord_m <= 0.0 {
            if let Some(d) = dist.as_mut() {
                d.push(r);
                d.push(0.0);
            }
            continue;
        }
        let beta = (pitch_m / (std::f64::consts::TAU * r)).atan();

        let mut v_i = 0.0f64;
        for _ in 0..iters {
            let phi = (v_i / (omega * r)).atan();
            let f_base = BemtModel::tip_loss_factor(blades, r_frac, phi);
            let f = tip_loss_with_closure(f_base, guard_closure);
            let alpha = beta - phi;
            let cl = (a0_eff * alpha).min(c_l_max);
            let cd = c_d0 + k_polar * cl * cl;
            let u2 = v_i * v_i + (omega * r) * (omega * r);
            let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
            let a = 4.0 * std::f64::consts::PI * rho * r * f * dr;
            if a <= 0.0 {
                v_i = 0.0;
                break;
            }
            v_i = (d_t / a).max(0.0).sqrt();
        }

        let phi = (v_i / (omega * r)).atan();
        let f_base = BemtModel::tip_loss_factor(blades, r_frac, phi);
        let f = tip_loss_with_closure(f_base, guard_closure);
        let alpha = beta - phi;
        let cl = (a0_eff * alpha).min(c_l_max);
        let cd = c_d0 + k_polar * cl * cl;
        let u2 = v_i * v_i + (omega * r) * (omega * r);
        let cos_phi = phi.cos();
        let sin_phi = phi.sin();

        let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
        let d_q = 0.5 * rho * u2 * blades * chord_m * (cl * sin_phi + cd * cos_phi) * r * dr;
        let d_t_mom = momentum_dt(rho, r, v_i, f, dr);

        if let Some(d) = dist.as_mut() {
            d.push(r);
            d.push(d_t);
        }

        thrust += d_t;
        torque += d_q;
        power_ind += d_t * v_i;
        power_prof += omega * 0.5 * rho * u2 * blades * chord_m * cd * cos_phi * r * dr;

        let residual = (d_t - d_t_mom).abs() / d_t_mom.abs().max(1e-30);
        max_residual = max_residual.max(residual);
    }

    PackedFloat64Array::from([thrust, torque, power_ind, power_prof, max_residual])
}

/// The forward-flight solve, callable from both `#[func] BemtModel::solve_forward`
/// (closure = 0.0) and `#[func] BemtModel::solve_forward_with_guard`. Same "one code path,
/// two closures" story as `solve_impl`.
fn solve_forward_impl(
    rho: f64,
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    rpm: f64,
    chord_points_mm: &PackedFloat64Array,
    a0_eff: f64,
    c_d0: f64,
    k_polar: f64,
    c_l_max: f64,
    v_axial_mps: f64,
    v_edge_mps: f64,
    guard_closure: f64,
) -> PackedFloat64Array {
    let guard_closure = sanitize_closure(guard_closure);
    if v_axial_mps < 0.0 {
        let mut res = solve_impl(
            rho, diameter_m, pitch_m, blades, rpm, chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, guard_closure);
        if res.len() == 5 {
            res[4] = -1.0;
        }
        return res;
    }
    if v_axial_mps == 0.0 && v_edge_mps == 0.0 {
        return solve_impl(
            rho, diameter_m, pitch_m, blades, rpm, chord_points_mm,
            a0_eff, c_d0, k_polar, c_l_max, guard_closure);
    }

    if blades <= 0.0 || diameter_m <= 0.0 || rpm <= 0.0 || chord_points_mm.len() < 4 {
        return PackedFloat64Array::from([0.0, 0.0, 0.0, 0.0, 1.0]);
    }
    let rho = if rho > 0.0 { rho } else { AIR_DENSITY_KGM3 };
    let radius_m = diameter_m * 0.5;
    let omega = rpm * std::f64::consts::TAU / 60.0;
    let n = BEMT_ANNULLI.max(1) as usize;
    let iters = BEMT_FORWARD_ITERATIONS.max(1) as usize;

    let r_hub_frac = chord_points_mm[0].clamp(0.0, 1.0);
    let r_hub_m = r_hub_frac * radius_m;
    let dr = (radius_m - r_hub_m) / n as f64;

    let mut thrust = 0.0;
    let mut torque = 0.0;
    let mut power_ind = 0.0;
    let mut power_prof = 0.0;
    let mut max_residual = 0.0f64;
    let v_edge_sq = v_edge_mps * v_edge_mps;

    for i in 0..n {
        let r = r_hub_m + (i as f64 + 0.5) * dr;
        let r_frac = r / radius_m;
        let chord_m = chord_at_m(chord_points_mm, r_frac);
        if chord_m <= 0.0 {
            continue;
        }
        let beta = (pitch_m / (std::f64::consts::TAU * r)).atan();

        let mut v_i = 0.0f64;
        let a = 4.0 * std::f64::consts::PI * rho * r * dr;
        for pass in 0..iters {
            let axial = v_axial_mps + v_i;
            let phi = (axial / (omega * r)).atan();
            let f_base = BemtModel::tip_loss_factor(blades, r_frac, phi);
            let f = tip_loss_with_closure(f_base, guard_closure);
            let alpha = beta - phi;
            let cl = (a0_eff * alpha).min(c_l_max);
            let cd = c_d0 + k_polar * cl * cl;
            let u2 = axial * axial + v_edge_sq + (omega * r) * (omega * r);
            let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
            let a_f = a * f;
            if a_f <= 0.0 {
                v_i = 0.0;
                break;
            }
            let disc = v_axial_mps * v_axial_mps + 4.0 * d_t.max(0.0) / a_f;
            let quadratic_root = ((-v_axial_mps + disc.sqrt()) * 0.5).max(0.0);
            if v_edge_mps == 0.0 || pass == 0 {
                v_i = quadratic_root;
                continue;
            }
            let magnitude = (axial * axial + v_edge_sq).sqrt();
            let v_new = (d_t.max(0.0) / (a_f * magnitude)).max(0.0);
            v_i = 0.5 * v_i + 0.5 * v_new;
        }

        let axial = v_axial_mps + v_i;
        let phi = (axial / (omega * r)).atan();
        let f_base = BemtModel::tip_loss_factor(blades, r_frac, phi);
        let f = tip_loss_with_closure(f_base, guard_closure);
        let alpha = beta - phi;
        let cl = (a0_eff * alpha).min(c_l_max);
        let cd = c_d0 + k_polar * cl * cl;
        let u2 = axial * axial + v_edge_sq + (omega * r) * (omega * r);
        let cos_phi = phi.cos();
        let sin_phi = phi.sin();

        let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
        let d_q = 0.5 * rho * u2 * blades * chord_m * (cl * sin_phi + cd * cos_phi) * r * dr;
        let magnitude = (axial * axial + v_edge_sq).sqrt();
        let d_t_mom = 4.0 * std::f64::consts::PI * rho * r * v_i * magnitude * f * dr;

        thrust += d_t;
        torque += d_q;
        power_ind += d_t * axial;
        power_prof += omega * 0.5 * rho * u2 * blades * chord_m * cd * cos_phi * r * dr;

        let residual = (d_t - d_t_mom).abs() / d_t_mom.abs().max(1e-30);
        max_residual = max_residual.max(residual);
    }

    PackedFloat64Array::from([thrust, torque, power_ind, power_prof, max_residual])
}

/// c(r) at a stated fraction of radius, piecewise-linear over the planform, mm → m. Linear
/// interpolation is exactly what the integrals assume, so the mesh and the solve cannot
/// disagree about the blade shape (the §0 rule made true of propulsion).
fn chord_at_m(chord_points: &PackedFloat64Array, r_frac: f64) -> f64 {
    let n = chord_points.len() / 2;
    if n < 2 {
        return 0.0;
    }
    if r_frac <= chord_points[0] {
        return chord_points[1] * 0.001;
    }
    let last_idx = 2 * (n - 1);
    if r_frac >= chord_points[last_idx] {
        return chord_points[last_idx + 1] * 0.001;
    }
    for i in 0..(n - 1) {
        let x0 = chord_points[2 * i];
        let c0 = chord_points[2 * i + 1];
        let x1 = chord_points[2 * i + 2];
        let c1 = chord_points[2 * i + 3];
        if r_frac >= x0 && r_frac <= x1 {
            let t = (r_frac - x0) / (x1 - x0);
            return (c0 + (c1 - c0) * t) * 0.001;
        }
    }
    0.0
}
