//! Thrust and reaction torque from motor RPM (physics.md §4): T = k_t * omega^2,
//! Q = k_q * omega^2. Ported from src/sim/propeller_model.gd, golden cross-checked before
//! the GDScript was deleted.
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

/// Exponents for moving a fitted k_t from the prop it was measured on to another prop.
/// Diameter's D^4 is dimensional and exact. Blade count and pitch have no clean law and are
/// documented rules of thumb. THESE REMAIN UNVALIDATED and the shipped catalog cannot
/// validate them — see the original's header for the full reasoning. They are deliberately
/// public (the app prints "the blades^0.8 rule of thumb" to users), so GDScript files that
/// referenced them keep the values as module consts pointing here.
pub const BLADE_COUNT_EXPONENT: f64 = 0.8;
pub const PITCH_EXPONENT: f64 = 0.5;

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

    /// Moves a k_t fitted on `from_prop` onto `to_prop`. Geometry is unpacked (three f64
    /// per side) rather than Dictionaries, per design §4.3.
    #[func]
    pub fn scale_k_t_to_prop(
        k_t_from: f64,
        from_d: f64,
        from_pitch: f64,
        from_blades: f64,
        to_d: f64,
        to_pitch: f64,
        to_blades: f64,
    ) -> f64 {
        let diameter_ratio = to_d / from_d;
        let blade_ratio = to_blades / from_blades;
        let pitch_ratio = to_pitch / from_pitch;
        k_t_from * diameter_ratio.powi(4) * blade_ratio.powf(BLADE_COUNT_EXPONENT)
            * pitch_ratio.powf(PITCH_EXPONENT)
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
}
