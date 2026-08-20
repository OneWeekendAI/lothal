//! BEMT core (P4) — propulsion.md §4.1–§4.2, pure, in Rust beside propeller.rs.
//!
//! Blade-element momentum theory for a fixed-geometry rotor. The disc is divided into annuli;
//! at each annulus the blade-element thrust and torque are closed against momentum theory
//! through a fixed-point iteration on the induced velocity v_i. Thrust, torque and the two
//! power components become quadratures along the radius, not fitted scalars — §0's inversion
//! of the propulsion chain.
//!
//! This slice is STATIC (hover, V_ax = 0). Forward flight (V_ax ≠ 0) and the descent refusal
//! are P6; the V_ax terms are written into the momentum closure comment so nothing is
//! re-derived later, but they are not computed here.
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
/// Number of annuli the disc is divided into — §4.1's "~40 annuli".
const BEMT_ANNULLI: i64 = 40;

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
        if blades <= 0.0 || diameter_m <= 0.0 || rpm <= 0.0 || chord_points_mm.len() < 4 {
            return PackedFloat64Array::from([0.0, 0.0, 0.0, 0.0, 1.0]);
        }
        let rho = if rho > 0.0 { rho } else { AIR_DENSITY_KGM3 };
        let radius_m = diameter_m * 0.5;
        let omega = rpm * std::f64::consts::TAU / 60.0;
        let n = BEMT_ANNULLI.max(1) as usize;
        let iters = BEMT_ITERATIONS.max(1) as usize;

        // The blade spans [hub, tip]; the hub is where the planform begins (the generator's
        // HUB_RADIUS_TO_RADIUS, an authored blade's own first station).
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
            let chord_m = chord_at_m(&chord_points_mm, r_frac);
            if chord_m <= 0.0 {
                continue;
            }
            // Geometric pitch, §3.2: the blade angle at this radius.
            let beta = (pitch_m / (std::f64::consts::TAU * r)).atan();

            // Fixed point on the induced velocity, seeded at 0 (hover: no inflow yet).
            let mut v_i = 0.0f64;
            for _ in 0..iters {
                let phi = (v_i / (omega * r)).atan();
                let f = Self::tip_loss_factor(blades, r_frac, phi);
                let alpha = beta - phi;
                let cl = (a0_eff * alpha).min(c_l_max);
                let cd = c_d0 + k_polar * cl * cl;
                let u2 = v_i * v_i + (omega * r) * (omega * r);
                let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
                // Momentum closure, hover: 4πρr·v_i²·F·dr = dT → v_i = √(dT / (4πρr·F·dr)).
                // (V_ax ≠ 0 becomes the quadratic v² + V_ax·v − dT/(4πρrF·dr) = 0 in P6.)
                let a = 4.0 * std::f64::consts::PI * rho * r * f * dr;
                if a <= 0.0 {
                    v_i = 0.0;
                    break;
                }
                v_i = (d_t / a).max(0.0).sqrt();
            }

            // Final pass: report from the converged v_i.
            let phi = (v_i / (omega * r)).atan();
            let f = Self::tip_loss_factor(blades, r_frac, phi);
            let alpha = beta - phi;
            let cl = (a0_eff * alpha).min(c_l_max);
            let cd = c_d0 + k_polar * cl * cl;
            let u2 = v_i * v_i + (omega * r) * (omega * r);
            let cos_phi = phi.cos();
            let sin_phi = phi.sin();

            let d_t = blade_dt(rho, u2, blades, chord_m, cl, cd, phi, dr);
            let d_q = 0.5 * rho * u2 * blades * chord_m * (cl * sin_phi + cd * cos_phi) * r * dr;
            let d_t_mom = momentum_dt(rho, r, v_i, f, dr);

            thrust += d_t;
            torque += d_q;
            // Induced power is thrust × local induced velocity (§4.5's FM denominator, part 1).
            power_ind += d_t * v_i;
            // Profile power is the drag part of shaft power: Ω·(0.5ρU²N_b c·C_d·cosφ·r·dr).
            power_prof += omega * 0.5 * rho * u2 * blades * chord_m * cd * cos_phi * r * dr;

            let residual = (d_t - d_t_mom).abs() / d_t_mom.abs().max(1e-30);
            max_residual = max_residual.max(residual);
        }

        PackedFloat64Array::from([thrust, torque, power_ind, power_prof, max_residual])
    }
}

/// dT = 4πρr·(V_ax + v)·v·F·dr — the momentum closure at one annulus (§4.1), hover form.
fn momentum_dt(rho: f64, r_m: f64, v_mps: f64, f: f64, dr: f64) -> f64 {
    4.0 * std::f64::consts::PI * rho * r_m * v_mps * v_mps * f * dr
}

/// dT = 0.5ρU²·N_b·c·(C_l·cosφ − C_d·sinφ)·dr — the blade element at one annulus (§4.1).
fn blade_dt(rho: f64, u2: f64, blades: f64, chord_m: f64, cl: f64, cd: f64, phi: f64, dr: f64) -> f64 {
    0.5 * rho * u2 * blades * chord_m * (cl * phi.cos() - cd * phi.sin()) * dr
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
