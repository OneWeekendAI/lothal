//! The sim + fc moat, ported from GDScript (native core 2, Tier 1): the PID anti-windup step,
//! airmode's three-step mixer saturation, the self-levelling outer loop, the vibration model's
//! forcing laws, the gyro/wind coefficients, and RateTune's plant-scaling law.
//!
//! Every `#[func]` is receiver-less, so a GDScript static function. State (integrators, phases,
//! RNG streams, f32 Vector filter state) stays in the GDScript objects and is passed through, so
//! GDScript APIs are unchanged and the RNG stream is Godot's own.
//!
//! BIT-FOR-BIT RULE. GDScript does scalar maths in f64 and Vector3 maths in f32. Each function
//! below repeats the original's operation order and the precise points where an f64 became an
//! f32, and uses Godot's own CLAMP/MIN/MAX/SIGN semantics rather than Rust's (f64::clamp panics
//! on min > max and treats NaN differently; f64::signum(0.0) is 1.0 where Godot's SIGN is 0).
//! The cross-check (tools/crosscheck/run_crosscheck_tier3.gd) holds these to exact equality.

use godot::prelude::*;

// Godot's Math:: macros, verbatim semantics.
#[inline]
fn gd_clamp(a: f64, lo: f64, hi: f64) -> f64 {
    if a < lo { lo } else if a > hi { hi } else { a }
}
#[inline]
fn gd_min(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}
#[inline]
fn gd_max(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}
#[inline]
fn gd_sign(x: f64) -> f64 {
    if x > 0.0 { 1.0 } else if x < 0.0 { -1.0 } else { 0.0 }
}

const GD_TAU: f64 = 6.283_185_307_179_586;

/// RateModeController.MAX_RATE_RAD_S (800 deg/s). The GDScript constant is kept for its readers;
/// the cross-check compares against references that read the GDScript one, so the two cannot
/// drift apart silently.
const MAX_RATE_RAD_S: f64 = 13.962634;
const MAX_ANGLE_RAD: f64 = 0.5235988;
const LEVEL_P: f64 = 10.0;
const MAX_LEVEL_RATE_RAD_S: f64 = 6.981317;

const MIX_GAIN: f64 = 0.2;
// MotorLayout.MOTOR_NAMES order: M1 rear-right, M2 front-right, M3 rear-left, M4 front-left.
const IS_FRONT: [bool; 4] = [false, true, false, true];
const IS_RIGHT: [bool; 4] = [true, true, false, false];

const ARM_LENGTH_EXPONENT: f64 = 1.5;
const REFERENCE_RESONANCE_HZ: f64 = 180.0;
const REFERENCE_ARM_M: f64 = 0.110;
const REFERENCE_TIP_MASS_KG: f64 = 0.0365;
const SENSOR_RESPONSE_RAD_S_PER_N: f64 = 0.003;
const YAW_COUPLING: f64 = 0.15;
const PHASE_OFFSETS: [f64; 4] = [0.0, 3.883222, 7.766444, 11.649666];

const D_NOISE_BUDGET: f64 = 0.02;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct FlightLaw;

#[godot_api]
impl FlightLaw {
    // -------------------------------------------------------------------------------------
    // PIDController
    // -------------------------------------------------------------------------------------

    /// One PID step with conditional-integration anti-windup and derivative on measurement.
    /// Returns [output, integral, last_measured]; the caller's has_last becomes true.
    #[func]
    fn pid_step(kp: f64, ki: f64, kd: f64, integral_limit: f64, output_limit: f64,
                integral: f64, last_measured: f64, has_last: bool,
                target: f64, measured: f64, dt: f64) -> PackedFloat64Array {
        let error = target - measured;
        let mut derivative = 0.0;
        if has_last && dt > 0.0 {
            derivative = -(measured - last_measured) / dt;
        }
        let mut new_integral = integral;
        let candidate = gd_clamp(integral + error * dt, -integral_limit, integral_limit);
        let mut output = kp * error + ki * candidate + kd * derivative;
        if output.abs() > output_limit && gd_sign(error) == gd_sign(output) {
            output = kp * error + ki * integral + kd * derivative;
        } else {
            new_integral = candidate;
        }
        let out = gd_clamp(output, -output_limit, output_limit);
        PackedFloat64Array::from(&[out, new_integral, measured][..])
    }

    // -------------------------------------------------------------------------------------
    // MotorMixer
    // -------------------------------------------------------------------------------------

    /// Airmode mix. `spin` is MotorLayout.spin_map() in MOTOR_NAMES order; the result is the
    /// four motor commands in the same order.
    #[func]
    fn mix(throttle: f64, roll_cmd: f64, pitch_cmd: f64, yaw_cmd: f64,
           spin: PackedFloat64Array) -> PackedFloat64Array {
        let mut delta = [0.0f64; 4];
        let mut lo = f64::INFINITY;
        let mut hi = f64::NEG_INFINITY;
        for i in 0..4 {
            let mut d = pitch_cmd * MIX_GAIN * (if IS_FRONT[i] { 1.0 } else { -1.0 });
            d += roll_cmd * MIX_GAIN * (if IS_RIGHT[i] { -1.0 } else { 1.0 });
            d += yaw_cmd * MIX_GAIN * spin.get(i).unwrap_or(0.0);
            delta[i] = d;
            lo = gd_min(lo, d);
            hi = gd_max(hi, d);
        }
        let spread = hi - lo;
        if spread > 1.0 {
            let scale = 1.0 / spread;
            for d in delta.iter_mut() {
                *d *= scale;
            }
            lo *= scale;
            hi *= scale;
        }
        let collective = gd_clamp(throttle, -lo, 1.0 - hi);
        let mut out = [0.0f64; 4];
        for i in 0..4 {
            out[i] = gd_clamp(collective + delta[i], 0.0, 1.0);
        }
        PackedFloat64Array::from(&out[..])
    }

    // -------------------------------------------------------------------------------------
    // AngleModeController
    // -------------------------------------------------------------------------------------

    /// The self-levelling outer loop. pitch/roll_current are the contract angles the caller
    /// extracted with Godot's own get_euler (kept in Godot so its f32 maths is untouched).
    #[func]
    fn level_rate_setpoint(pitch_current: f64, roll_current: f64,
                           rc_roll: f64, rc_pitch: f64, rc_yaw: f64) -> Vector3 {
        let pitch_error = (rc_pitch * MAX_ANGLE_RAD) - pitch_current;
        let roll_error = (rc_roll * MAX_ANGLE_RAD) - roll_current;
        let pitch_sp = gd_clamp(LEVEL_P * pitch_error, -MAX_LEVEL_RATE_RAD_S, MAX_LEVEL_RATE_RAD_S);
        let roll_sp = gd_clamp(LEVEL_P * roll_error, -MAX_LEVEL_RATE_RAD_S, MAX_LEVEL_RATE_RAD_S);
        Vector3::new((roll_sp / MAX_RATE_RAD_S) as f32, (pitch_sp / MAX_RATE_RAD_S) as f32,
                     rc_yaw as f32)
    }

    // -------------------------------------------------------------------------------------
    // VibrationModel
    // -------------------------------------------------------------------------------------

    /// The arm/tip-mass resonance law: 180 Hz on the reference arm, arm^-1.5, tip^-0.5.
    #[func]
    fn resonance_hz_for(arm_m: f64, tip_kg: f64) -> f64 {
        if arm_m <= 0.0 || tip_kg <= 0.0 {
            return REFERENCE_RESONANCE_HZ;
        }
        REFERENCE_RESONANCE_HZ
            * (REFERENCE_ARM_M / arm_m).powf(ARM_LENGTH_EXPONENT)
            * (REFERENCE_TIP_MASS_KG / tip_kg).sqrt()
    }

    #[func]
    fn modal_gain(hz: f64, res_hz: f64, zeta: f64) -> f64 {
        modal_gain_impl(hz, res_hz, zeta)
    }

    /// Soft-mount transmissibility at `hz` for a mount of natural frequency `f_n`.
    #[func]
    fn mount_transmissibility(hz: f64, f_n: f64, zeta: f64) -> f64 {
        transmissibility_impl(hz, f_n, zeta)
    }

    /// One call of VibrationModel.angular_rate_at's forcing loop. `phase` is the four motors'
    /// accumulated phase; returns [x, y, z, phase0..phase3] — the rate as f32-exact values and
    /// the advanced phases.
    #[func]
    fn vibration_rate(dt: f64, rpm: PackedFloat64Array, phase: PackedFloat64Array,
                      axis: PackedVector3Array, yaw_sign: PackedFloat64Array,
                      params: PackedFloat64Array) -> PackedFloat64Array {
        // params: prop_radius_m, blades, imbalance_kg, blade_pass_kg, resonance_hz,
        //         damping_ratio, mount_f_n, mount_zeta
        let p = |i: usize| params.get(i).unwrap_or(0.0);
        let (prop_radius_m, blades, imbalance_kg, blade_pass_kg) = (p(0), p(1), p(2), p(3));
        let (resonance_hz, damping_ratio, f_n, zeta) = (p(4), p(5), p(6), p(7));
        let mut ph = [0.0f64; 4];
        for (i, v) in ph.iter_mut().enumerate() {
            *v = phase.get(i).unwrap_or(0.0);
        }
        let (mut ox, mut oy, mut oz) = (0.0f32, 0.0f32, 0.0f32);
        for i in 0..4 {
            let hz = rpm.get(i).unwrap_or(0.0) / 60.0;
            if hz <= 0.0 {
                continue;
            }
            ph[i] += GD_TAU * hz * dt;
            let omega = GD_TAU * hz;
            let per_kg_n = prop_radius_m * omega * omega;
            let bp_hz = blades * hz;
            let imbalance_n = imbalance_kg * per_kg_n
                * modal_gain_impl(hz, resonance_hz, damping_ratio)
                * transmissibility_impl(hz, f_n, zeta);
            let blade_n = blade_pass_kg * per_kg_n
                * modal_gain_impl(bp_hz, resonance_hz, damping_ratio)
                * transmissibility_impl(bp_hz, f_n, zeta);
            let theta = ph[i] + PHASE_OFFSETS[i];
            let bending = imbalance_n * theta.sin() + blade_n * (blades * theta).sin();
            let torsion = imbalance_n * theta.cos() + blade_n * (blades * theta).cos();
            // out += _axis[i] * (bending * K): Vector3 * float is f32.
            let a = axis.get(i).unwrap_or(Vector3::ZERO);
            let s = (bending * SENSOR_RESPONSE_RAD_S_PER_N) as f32;
            ox += a.x * s;
            oy += a.y * s;
            oz += a.z * s;
            // out.y += f64 expression: read as f64, add in f64, store back to f32.
            let yaw = torsion * SENSOR_RESPONSE_RAD_S_PER_N * YAW_COUPLING
                * yaw_sign.get(i).unwrap_or(0.0);
            oy = ((oy as f64) + yaw) as f32;
        }
        PackedFloat64Array::from(&[ox as f64, oy as f64, oz as f64, ph[0], ph[1], ph[2], ph[3]][..])
    }

    // -------------------------------------------------------------------------------------
    // Gyro
    // -------------------------------------------------------------------------------------

    /// The one-pole low-pass coefficient for one sample period at `cutoff_hz`.
    #[func]
    fn lowpass_alpha(period: f64, cutoff_hz: f64) -> f64 {
        let rc = 1.0 / (GD_TAU * cutoff_hz);
        period / (rc + period)
    }

    /// RMS sample-to-sample change of the filtered white noise: the closed form behind
    /// Gyro.sample_step_noise_rad_s.
    #[func]
    fn gyro_step_noise(noise_rad_s: f64, sample_rate_hz: f64, cutoff_hz: f64) -> f64 {
        let period = 1.0 / sample_rate_hz;
        let rc = 1.0 / (GD_TAU * cutoff_hz);
        let a = period / (rc + period);
        noise_rad_s * (2.0 * a * a / (2.0 - a)).sqrt()
    }

    // -------------------------------------------------------------------------------------
    // Wind
    // -------------------------------------------------------------------------------------

    #[func]
    fn wind_steady_vector(speed_mps: f64, from_deg: f64) -> Vector3 {
        let towards_rad = (from_deg + 180.0) * (std::f64::consts::PI / 180.0);
        Vector3::new((speed_mps * towards_rad.sin()) as f32, 0.0,
                     (-speed_mps * towards_rad.cos()) as f32)
    }

    /// The gust process's per-step coefficients: [a, sigma] for a first-order Gauss-Markov
    /// gust of time constant `tau_s` whose stationary spread is `gustiness_mps`.
    #[func]
    fn gust_coefficients(dt: f64, tau_s: f64, gustiness_mps: f64) -> PackedFloat64Array {
        let a = dt / (tau_s + dt);
        let sigma = gustiness_mps * ((2.0 - a) / a).sqrt();
        PackedFloat64Array::from(&[a, sigma][..])
    }

    // -------------------------------------------------------------------------------------
    // RateTune
    // -------------------------------------------------------------------------------------

    /// The plant-scaling law. Returns [scale, kp, ki, kd, limited] where limited has 1.0 on
    /// each axis whose D was clamped to `kd_ceiling`.
    #[func]
    fn derive_gains(anchor: Vector3, alpha: Vector3, ref_kp: Vector3, ref_ki: Vector3,
                    ref_kd: Vector3, kd_ceiling: f64) -> PackedVector3Array {
        let mut scale = Vector3::ONE;
        for axis in 0..3 {
            let al = axis_of(alpha, axis) as f64;
            let v = if al > 0.0 { axis_of(anchor, axis) as f64 / al } else { 1.0 };
            set_axis(&mut scale, axis, v as f32);
        }
        let kp = Vector3::new(ref_kp.x * scale.x, ref_kp.y * scale.y, ref_kp.z * scale.z);
        let ki = Vector3::new(ref_ki.x * scale.x, ref_ki.y * scale.y, ref_ki.z * scale.z);
        let mut kd = Vector3::new(ref_kd.x * scale.x, ref_kd.y * scale.y, ref_kd.z * scale.z);
        let mut limited = Vector3::ZERO;
        for axis in 0..3 {
            if (axis_of(kd, axis) as f64) > kd_ceiling {
                set_axis(&mut kd, axis, kd_ceiling as f32);
                set_axis(&mut limited, axis, 1.0);
            }
        }
        PackedVector3Array::from(&[scale, kp, ki, kd, limited][..])
    }

    /// Fraction of full command the D term spends on gyro noise (no sample-rate guard: the
    /// d_noise_fraction form).
    #[func]
    fn d_noise_fraction(kd: f64, step_noise_rad_s: f64, sample_rate_hz: f64) -> f64 {
        let period = 1.0 / sample_rate_hz;
        kd * step_noise_rad_s / (period * MAX_RATE_RAD_S)
    }

    /// The same with the sample-rate guard (the noise_fraction_for form).
    #[func]
    fn noise_fraction_for(step_noise_rad_s: f64, sample_rate_hz: f64, kd: f64) -> f64 {
        if sample_rate_hz <= 0.0 {
            return 0.0;
        }
        let period = 1.0 / sample_rate_hz;
        kd * step_noise_rad_s / (period * MAX_RATE_RAD_S)
    }

    /// The D gain at which the noise budget is exactly spent, from the per-unit-kd fraction.
    #[func]
    fn kd_ceiling(per_unit_kd: f64) -> f64 {
        if per_unit_kd <= 0.0 {
            return f64::INFINITY;
        }
        D_NOISE_BUDGET / per_unit_kd
    }

    /// Closed-loop rate time constant per axis.
    #[func]
    fn time_constants(plant_alpha: Vector3, kp: Vector3) -> Vector3 {
        let mut out = Vector3::ZERO;
        for axis in 0..3 {
            let loop_gain = axis_of(plant_alpha, axis) as f64 * axis_of(kp, axis) as f64;
            let v = if loop_gain > 0.0 { MAX_RATE_RAD_S / loop_gain } else { f64::INFINITY };
            set_axis(&mut out, axis, v as f32);
        }
        out
    }
}

fn axis_of(v: Vector3, axis: usize) -> f32 {
    match axis { 0 => v.x, 1 => v.y, _ => v.z }
}
fn set_axis(v: &mut Vector3, axis: usize, value: f32) {
    match axis { 0 => v.x = value, 1 => v.y = value, _ => v.z = value }
}

fn modal_gain_impl(hz: f64, res_hz: f64, zeta: f64) -> f64 {
    if res_hz <= 0.0 {
        return 1.0;
    }
    let r = hz / res_hz;
    let real = 1.0 - r * r;
    let imag = 2.0 * zeta * r;
    1.0 / (real * real + imag * imag).sqrt()
}

fn transmissibility_impl(hz: f64, f_n: f64, zeta: f64) -> f64 {
    if f_n.is_infinite() {
        return 1.0;
    }
    let r = hz / f_n;
    let damped = 2.0 * zeta * r;
    let real = 1.0 - r * r;
    ((1.0 + damped * damped) / (real * real + damped * damped)).sqrt()
}
