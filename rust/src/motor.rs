//! RPM response of a single motor. Pure and engine-independent (physics.md §3).
//! Ported from src/sim/motor_model.gd — the GDScript is the source of truth and was
//! golden cross-checked against this file before it was deleted.
//!
//! max_RPM = KV * live pack voltage — the same motor spins much faster on 6S than 4S,
//! which is most of why voltage choice feels dramatic to fly.
//!
//! P7 (propulsion.md §3.4): the first-order lag time constant is no longer a global
//! 0.03 s. Every MotorModel now carries its own `tau_s`, computed from the mechanical
//! sum of J_rotor + N_b · J_blade divided by the sum of the motor's electrical
//! back-EMF slope and the propeller's aerodynamic damping slope at the operating point.
//! A 0802 whoop with a 0.5 g prop and a 2808 cinelifter with a 12 g prop can no longer
//! share a spin-up. See `motor_spin_up.gd` for the derivation.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct MotorModel {
    #[var]
    pub kv: f64,
    /// Fraction of the KV*voltage RPM ceiling this motor can reach with the prop fitted,
    /// before it hits its own current limit. 1.0 whenever the prop is at or below what the
    /// motor's amp rating was measured against. See battery_model-less note in the original:
    /// without it a motor is a free lunch — the D^4 thrust law alone would report a ~44:1
    /// thrust-to-weight for a 7" prop on a 2207, because nothing objects to spinning a much
    /// larger prop at the same RPM. Reality objects through current (torque, and so amps,
    /// climb as D^5), and this term is what caps it.
    #[var]
    pub max_throttle: f64,
    /// First-order lag time constant, seconds. Per-motor since P7. Caller computes it from
    /// §3.4's formula; if the caller cannot (a stub build, a probe), the fallback is 0.03 s
    /// which matches the constant this replaced — a deliberate identity so a call site that
    /// forgot to pass tau_s produces the same numbers the old code did, not silently wrong ones.
    #[var]
    pub tau_s: f64,
}

#[godot_api]
impl MotorModel {
    /// Legacy factory kept as an EXPLICIT bench convenience: probes, custom-motor previews
    /// and tests that only want a `step()` don't need to build a whole powertrain to derive
    /// tau. Everything on the flight path uses `create_with_tau` and hands in the value
    /// `MotorSpinUp` computed at hover.
    #[func]
    pub fn create(kv: f64, max_throttle: f64) -> Gd<Self> {
        Self::create_with_tau(kv, max_throttle, DEFAULT_TAU_S)
    }

    /// The flight-path factory: caller passes the tau_s it computed from motor + prop
    /// geometry at the linearisation point. `Build.motor_model()` and the ESC bench pass
    /// their own; both route through `Build.spin_up()`, which calls `MotorSpinUp.compute()`.
    #[func]
    pub fn create_with_tau(kv: f64, max_throttle: f64, tau_s: f64) -> Gd<Self> {
        Gd::from_object(Self {
            kv,
            max_throttle: max_throttle.clamp(0.0, 1.0),
            tau_s: if tau_s > 0.0 { tau_s } else { DEFAULT_TAU_S },
        })
    }

    #[func]
    pub fn max_rpm(&self, voltage_v: f64) -> f64 {
        self.kv * voltage_v
    }

    /// Advances current RPM one dt toward the throttle-commanded target, via first-order lag.
    #[func]
    pub fn step(&self, current_rpm: f64, throttle_cmd: f64, voltage_v: f64, dt: f64) -> f64 {
        let target = throttle_cmd.clamp(0.0, self.max_throttle) * self.max_rpm(voltage_v);
        let alpha = 1.0 - (-dt / self.tau_s).exp();
        current_rpm + (target - current_rpm) * alpha
    }
}

/// The value the deleted `SPIN_UP_TAU_S` constant carried. Kept here — and ONLY here — as the
/// fallback for `create()`, so a bench probe that does not want to derive tau produces the same
/// numbers the pre-P7 code did instead of a silent zero.
const DEFAULT_TAU_S: f64 = 0.03;
