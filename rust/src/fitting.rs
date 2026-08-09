//! The fitting pipeline's pure arithmetic, ported from src/assembly/build.gd (Tier 2).
//! This is the actual moat (design §1.1): which prop/voltage a headline figure was measured
//! on, the plausibility bands that reject a bad fit, and the three current limits with the
//! tie-break deciding which one binds.
//!
//! Every `#[func]` is receiver-less and therefore a GDScript static function (the pattern
//! established in propeller.rs). GDScript keeps the catalog Dictionary plumbing and the
//! BuildWarning construction; the arithmetic here is a pure function of its typed inputs.
//!
//! The cross-check (tests/rust_crosscheck_tier2.gd) compared each function against a
//! verbatim transcription of the GDScript it replaced, before the call sites were rewired.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Fitting;

#[godot_api]
impl Fitting {
    /// The throttle at which the four motors together draw `total_amps` (build.gd:460).
    /// Current tracks shaft torque and torque goes as RPM^2, so current at a throttle is
    /// quadratic in it — a square root, not a ratio. One expression, used by every limit, so
    /// the pack limit cannot end up meaning something subtly different from the motor limit.
    #[func]
    fn throttle_limit_for(total_amps: f64, full_throttle_amps: f64) -> f64 {
        if full_throttle_amps <= 0.0 || total_amps <= 0.0 {
            return 1.0;
        }
        (total_amps / full_throttle_amps).sqrt().clamp(0.0, 1.0)
    }

    /// The RPM at which a motor draws its rated amps with the prop actually fitted: KV times
    /// the pack voltage the manufacturer's amp figure was measured at (build.gd:607).
    #[func]
    fn rated_rpm(kv: f64, test_voltage_v: f64) -> f64 {
        kv * test_voltage_v
    }

    /// Current drawn by one motor at a given RPM (build.gd:601). Must agree with the
    /// powertrain's own current_at_rpm, or the HUD's numbers and the flight model's diverge.
    #[func]
    fn current_at_rpm(rpm: f64, max_amps: f64, rated_rpm: f64) -> f64 {
        if rated_rpm <= 0.0 {
            return 0.0;
        }
        let fraction = rpm / rated_rpm;
        max_amps * fraction * fraction
    }

    /// Steady-state RPM at a throttle command (build.gd:586). RPM and pack sag depend on each
    /// other, but the loop converges quickly: more sag means less RPM means less current means
    /// less sag. The 12-iteration fixed point is the same shape Build used; Powertrain reaches
    /// the same number dynamically by integrating the lag.
    #[func]
    fn rpm_at_throttle(throttle: f64, cap: f64, kv: f64, rest_v: f64, internal_r: f64,
                       max_amps: f64, rated_rpm: f64) -> f64 {
        let t = throttle.clamp(0.0, cap);
        let mut voltage_v = rest_v;
        let mut rpm = 0.0;
        for _ in 0..12 {
            rpm = t * kv * voltage_v;
            voltage_v = (rest_v - Self::current_at_rpm(rpm, max_amps, rated_rpm) * 4.0 * internal_r)
                .max(0.0);
        }
        rpm
    }

    /// WHICH component is holding a build back, by index into [motors, battery, esc]
    /// (build.gd:476). Ties go to the motors, then the pack, then the ESC — the pre-existing
    /// behaviour: an unrated part yields a zero limit that throttle_limit_for reads as "no
    /// limit stated", and it must not then be reported as the thing holding the build back.
    #[func]
    fn limiting_index(motor_lim: f64, pack_lim: f64, esc_lim: f64) -> i64 {
        if pack_lim < motor_lim {
            if esc_lim < pack_lim {
                2
            } else {
                1
            }
        } else if esc_lim < motor_lim {
            2
        } else {
            0
        }
    }
}
