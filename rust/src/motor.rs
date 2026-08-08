//! RPM response of a single motor. Pure and engine-independent (physics.md §3).
//! Ported from src/sim/motor_model.gd — the GDScript is the source of truth and was
//! golden cross-checked against this file before it was deleted.
//!
//! max_RPM = KV * live pack voltage — the same motor spins much faster on 6S than 4S,
//! which is most of why voltage choice feels dramatic to fly.

use godot::prelude::*;

/// First-order lag time constant; instant RPM makes it twitchy.
const SPIN_UP_TAU_S: f64 = 0.03;

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
}

#[godot_api]
impl MotorModel {
    /// GDScript's `MotorModel.new(kv, max_throttle)` — gdext has no constructor-argument
    /// `_init`, so a static factory is the idiom. Every `MotorModel.new(...)` call site was
    /// renamed to `MotorModel.create(...)` in the same commit.
    #[func]
    pub fn create(kv: f64, max_throttle: f64) -> Gd<Self> {
        Gd::from_object(Self {
            kv,
            max_throttle: max_throttle.clamp(0.0, 1.0),
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
        let alpha = 1.0 - (-dt / SPIN_UP_TAU_S).exp();
        current_rpm + (target - current_rpm) * alpha
    }
}
