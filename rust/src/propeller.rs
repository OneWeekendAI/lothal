//! Thrust and reaction torque from motor RPM (physics.md §4): T = k_t * omega^2,
//! Q = k_q * omega^2. Ported from src/sim/propeller_model.gd, golden cross-checked before
//! the GDScript was deleted.
//!
//! FORWARD FLIGHT NO LONGER LIVES HERE. `thrust_factor`, `thrust_n_in_flight`,
//! `induced_velocity_mps`, `power_factor` and the `FIGURE_OF_MERIT` guess they rested on were
//! deleted when P6's closure landed (propulsion.md §9's P6 row). They were a linear C_T(J) rule of
//! thumb and a Glauert construction anchored on a figure of merit nobody publishes; the ratios the
//! powertrain reads now come from blade-element theory on the blade's own planform, tabulated in
//! `bemt_ratios.rs`. What stays here is `j_zero` and `advance_ratio` — pure kinematics, still what
//! the prop-unloading warning quotes to a builder, and never a claim about how much thrust is
//! lost.
//!
//! k_q has no equivalent published-and-fit figure in v1, so it uses a documented
//! rule-of-thumb ratio to k_t. Only the sign of reaction torque is load-bearing; the
//! magnitude ratio can be replaced once torque-test tables are authored into the catalog.
//!
//! Every `#[func]` here is receiver-less, which gdext 0.5 registers as a GDScript STATIC
//! function — so GDScript calls `PropellerModel.fit_k_t(...)` etc. class-level, exactly as
//! the original `static func`s were called. (gdext 0.5 does NOT expose receiver-ful #[func]
//! statically, but receiver-less ones are the design's exact pattern.)

use godot::prelude::*;

/// The ratio is not a constant across prop sizes: Q = C_Q*rho*n^2*D^5 and
/// T = C_T*rho*n^2*D^4, so Q/T scales with diameter. Anchored at 0.02 for a 5" prop.
const K_Q_TO_K_T_RATIO_AT_5IN: f64 = 0.02;
const K_Q_REFERENCE_DIAMETER_M: f64 = 0.127; // 5 inches

/// AIR DENSITY IS NOT THIS FILE'S ANY MORE. `propeller.rs` used to carry its own
/// `AIR_DENSITY_KGM3` and an `air_density_or_default` guard, because `power_factor` and
/// `induced_velocity_mps` took a rho. P6's closure deleted all four functions that read them, so
/// the constant went with them rather than sitting here as a second copy nothing consults —
/// which is how two numbers that must agree start disagreeing.
///
/// The copy that IS load-bearing is `bemt.rs`'s, and `tests/test_rust_constants.gd` pins THAT one
/// to `Build.AIR_DENSITY_KGM3` now, by inverting a solve rather than by reading an accessor. What
/// remains here — `thrust_n`, `reaction_torque_n_m`, `j_zero`, `advance_ratio` — is density-free:
/// air reaches thrust through `k_t`, which `build.gd` scales by the field's density directly.

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct PropellerModel;

#[godot_api]
impl PropellerModel {
    /// k_t from a manufacturer's headline figure: max thrust at max RPM on the prop the
    /// figure was measured with.
    #[func]
    pub fn fit_k_t(max_thrust_g: f64, max_rpm: f64) -> f64 {
        let max_thrust_n = (max_thrust_g / 1000.0) * 9.81;
        let max_omega = Self::rpm_to_rad_s(max_rpm);
        max_thrust_n / (max_omega * max_omega)
    }

    #[func]
    pub fn fit_k_q(k_t: f64, diameter_m: f64) -> f64 {
        k_t * K_Q_TO_K_T_RATIO_AT_5IN * (diameter_m / K_Q_REFERENCE_DIAMETER_M)
    }

    #[func]
    pub fn rpm_to_rad_s(rpm: f64) -> f64 {
        rpm * std::f64::consts::TAU / 60.0
    }

    #[func]
    pub fn thrust_n(k_t: f64, rpm: f64) -> f64 {
        let omega = Self::rpm_to_rad_s(rpm);
        k_t * omega * omega
    }

    #[func]
    pub fn reaction_torque_n_m(k_q: f64, rpm: f64) -> f64 {
        let omega = Self::rpm_to_rad_s(rpm);
        k_q * omega * omega
    }

    // -----------------------------------------------------------------------
    // The two AIRSPEED KINEMATICS that survived P6's closure. Neither is a force model: they are
    // the advance ratio and the advance ratio at which a prop stops pulling, which is what the
    // prop-unloading warning quotes to a builder in words they can act on ("you are flying at 62%
    // of the speed the blade would screw itself forward at").
    //
    // SIGN CONVENTION, once, here: `v_axial_mps` is the aircraft's velocity along BODY +Y — the
    // rotor's own thrust axis. Climbing, or leaning into forward flight, makes it POSITIVE.
    // Descent is negative and is out of domain — `BemtRatios` declines it rather than answering.
    //
    // How much thrust is actually left at a given advance ratio is `BemtRatios::thrust_ratio`'s
    // question, not this file's, and the deleted `thrust_factor` answering it with a straight line
    // to `j_zero` is what P6 replaced.
    // -----------------------------------------------------------------------

    /// The advance ratio at which a propeller stops making thrust, taken as its GEOMETRIC advance,
    /// pitch/diameter. Both figures are already in the catalog, so per the derived-not-typed rule
    /// in parts.md no `j_zero` field is added to propellers.json.
    ///
    /// A RULE OF THUMB, in the same voice as the deleted BLADE_COUNT_EXPONENT, and since P6's
    /// closure it is quoted rather than computed WITH: BEMT decides where thrust actually reaches
    /// zero (on the reference 5x4.5x3 that is mu_axial ≈ 0.29, close to but not equal to this
    /// figure over pi), and this number appears only in the sentence the warning shows a builder.
    /// Real props reach zero thrust somewhat BELOW their geometric advance — typically 0.8-0.9 of
    /// it — because the blade has a zero-lift angle and is not at its nominal pitch across the
    /// whole radius, so a warning keyed on it is conservative about how early unloading starts.
    #[func]
    pub fn j_zero(diameter_m: f64, pitch_m: f64) -> f64 {
        if diameter_m <= 0.0 {
            return 0.0;
        }
        pitch_m / diameter_m
    }

    /// J = V_axial / (n*D), the distance the aircraft advances per revolution against the distance
    /// the prop would screw itself forward through solid air.
    #[func]
    pub fn advance_ratio(rpm: f64, diameter_m: f64, v_axial_mps: f64) -> f64 {
        let rev_per_s = rpm / 60.0;
        if rev_per_s <= 0.0 || diameter_m <= 0.0 {
            return 0.0;
        }
        v_axial_mps / (rev_per_s * diameter_m)
    }

    #[func]
    pub fn disc_area_m2(diameter_m: f64) -> f64 {
        if diameter_m <= 0.0 {
            return 0.0;
        }
        let radius = diameter_m * 0.5;
        std::f64::consts::PI * radius * radius
    }
}
