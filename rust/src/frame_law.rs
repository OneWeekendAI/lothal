//! The airframe's structural arithmetic, ported from GDScript (native core 2, Tier 2a):
//! ArmBeam's varying-section Euler-Bernoulli cantilever: width interpolation, the
//! compliance integral by Simpson over the profile's breakpoints, tip stiffness with root
//! fixity, Rayleigh-mass resonance, the characteristic torsion estimate, and the three stress
//! checks.
//!
//! Same rules as flight_law.rs: receiver-less `#[func]`s (GDScript statics), inputs are the
//! beam's plain numbers, operation order is the original's, and the cross-check
//! (tools/crosscheck/run_crosscheck_frame.gd) holds the port to EXACT equality against the
//! verbatim GDScript. ArmBeam keeps validation, the material lookups and the Dictionaries.

use godot::prelude::*;

const ROOT_FIXITY_BOLTED: f64 = 0.85;
const ROOT_FIXITY_UNIBODY: f64 = 1.0;
const CHARACTERISTIC_SHEAR_FRACTION: f64 = 0.065;
const RAYLEIGH_MASS_FRACTION: f64 = 33.0 / 140.0;
const STATIONS_PER_SEGMENT: i64 = 120;
const GD_TAU: f64 = 6.283_185_307_179_586;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct FrameLaw;

#[godot_api]
impl FrameLaw {
    /// Piecewise-linear width at station `s` along the arm, clamped at both ends.
    #[func]
    fn beam_width_at(stations: PackedFloat64Array, widths: PackedFloat64Array, s: f64) -> f64 {
        width_at(stations.as_slice(), widths.as_slice(), s)
    }

    /// I(s) = b(s) t^3 / 12.
    #[func]
    fn beam_second_moment_at(stations: PackedFloat64Array, widths: PackedFloat64Array,
                             thickness_m: f64, s: f64) -> f64 {
        second_moment_at(stations.as_slice(), widths.as_slice(), thickness_m, s)
    }

    /// Integral of (L - s)^2 / I(s) ds over the arm: tip deflection per unit force is this over E.
    /// Simpson on each profile segment, so a kink in the width profile never sits inside a panel.
    #[func]
    fn beam_compliance_integral(stations: PackedFloat64Array, widths: PackedFloat64Array,
                                thickness_m: f64, length_m: f64) -> f64 {
        let s = stations.as_slice();
        let b = widths.as_slice();
        let mut breakpoints: Vec<f64> = vec![0.0];
        for &station in s {
            if station > breakpoints[breakpoints.len() - 1] + 1.0e-12 && station < length_m - 1.0e-12 {
                breakpoints.push(station);
            }
        }
        breakpoints.push(length_m);
        let mut total = 0.0;
        for i in 0..breakpoints.len() - 1 {
            total += simpson(s, b, thickness_m, length_m, breakpoints[i], breakpoints[i + 1],
                             STATIONS_PER_SEGMENT);
        }
        total
    }

    /// Trapezoid plan area of the width profile.
    #[func]
    fn beam_plan_area(stations: PackedFloat64Array, widths: PackedFloat64Array, length_m: f64) -> f64 {
        let s = stations.as_slice();
        let b = widths.as_slice();
        if b.len() < 2 {
            return width_at(s, b, 0.0) * length_m;
        }
        let mut area = 0.0;
        for i in 0..b.len() - 1 {
            area += 0.5 * (b[i] + b[i + 1]) * (s[i + 1] - s[i]);
        }
        area
    }

    #[func]
    fn beam_root_fixity(unibody: bool) -> f64 {
        if unibody { ROOT_FIXITY_UNIBODY } else { ROOT_FIXITY_BOLTED }
    }

    /// Tip stiffness: fixity * E / compliance integral, or 0 when either is not positive.
    #[func]
    fn beam_k_tip(compliance: f64, modulus_pa: f64, unibody: bool) -> f64 {
        if compliance <= 0.0 || modulus_pa <= 0.0 {
            return 0.0;
        }
        Self::beam_root_fixity(unibody) * modulus_pa / compliance
    }

    /// First bending mode with the arm's own mass lumped at the tip by Rayleigh's 33/140.
    #[func]
    fn beam_resonance_hz(stiffness: f64, tip_mass_kg: f64, arm_mass_kg: f64) -> f64 {
        let effective_mass = tip_mass_kg + RAYLEIGH_MASS_FRACTION * arm_mass_kg;
        if stiffness <= 0.0 || effective_mass <= 0.0 {
            return 0.0;
        }
        (stiffness / effective_mass).sqrt() / GD_TAU
    }

    /// Characteristic torsion: [twist_rad, torsion_constant_m4, shear_modulus_pa].
    #[func]
    fn beam_torsion(torque_nm: f64, modulus_pa: f64, plan_area_m2: f64, length_m: f64,
                    thickness_m: f64) -> PackedFloat64Array {
        let shear_modulus = modulus_pa * CHARACTERISTIC_SHEAR_FRACTION;
        let mean_width = if length_m > 0.0 { plan_area_m2 / length_m } else { 0.0 };
        let torsion_constant = mean_width * thickness_m.powf(3.0) / 3.0;
        let mut twist_rad = 0.0;
        if shear_modulus > 0.0 && torsion_constant > 0.0 {
            twist_rad = torque_nm * length_m / (shear_modulus * torsion_constant);
        }
        PackedFloat64Array::from(&[twist_rad, torsion_constant, shear_modulus][..])
    }

    /// Root-bending stress at station `s` for a tip force: 6 M / (b t^2).
    #[func]
    fn beam_bending_stress(stations: PackedFloat64Array, widths: PackedFloat64Array,
                           thickness_m: f64, length_m: f64, force_n: f64, s: f64) -> f64 {
        bending_stress(stations.as_slice(), widths.as_slice(), thickness_m, length_m, force_n, s)
    }

    /// Bending stress on the net section left beside a hole of diameter `hole_d_m`.
    #[func]
    fn beam_net_section_stress(stations: PackedFloat64Array, widths: PackedFloat64Array,
                               thickness_m: f64, length_m: f64, force_n: f64, s: f64,
                               hole_d_m: f64) -> f64 {
        let st = stations.as_slice();
        let wd = widths.as_slice();
        let b = width_at(st, wd, s);
        if b <= 0.0 || hole_d_m >= b {
            return 0.0;
        }
        bending_stress(st, wd, thickness_m, length_m, force_n, s) * b / (b - hole_d_m)
    }

    #[func]
    fn beam_bearing_stress(force_n: f64, hole_d_m: f64, thickness_m: f64) -> f64 {
        if hole_d_m <= 0.0 || thickness_m <= 0.0 {
            return 0.0;
        }
        force_n / (hole_d_m * thickness_m)
    }
}

fn width_at(s_m: &[f64], b_m: &[f64], s: f64) -> f64 {
    let n = b_m.len();
    if n == 0 {
        return 0.0;
    }
    // GDScript indexes profile_s_m by the WIDTH array's length; a shorter station array would
    // have been an out-of-bounds error there. validate() rejects that mismatch, so here it reads 0.
    let st = |i: usize| s_m.get(i).copied().unwrap_or(0.0);
    if n == 1 || s <= st(0) {
        return b_m[0];
    }
    if s >= st(n - 1) {
        return b_m[n - 1];
    }
    for i in 0..n - 1 {
        if s <= st(i + 1) {
            let span = st(i + 1) - st(i);
            if span <= 0.0 {
                return b_m[i + 1];
            }
            return b_m[i] + (b_m[i + 1] - b_m[i]) * (s - st(i)) / span;
        }
    }
    b_m[n - 1]
}

fn second_moment_at(s_m: &[f64], b_m: &[f64], thickness_m: f64, s: f64) -> f64 {
    width_at(s_m, b_m, s) * thickness_m.powf(3.0) / 12.0
}

fn integrand(s_m: &[f64], b_m: &[f64], thickness_m: f64, length_m: f64, s: f64) -> f64 {
    let inertia = second_moment_at(s_m, b_m, thickness_m, s);
    if inertia <= 0.0 {
        return 0.0;
    }
    let lever = length_m - s;
    lever * lever / inertia
}

fn simpson(s_m: &[f64], b_m: &[f64], t: f64, l: f64, a: f64, b: f64, intervals: i64) -> f64 {
    let n = if intervals % 2 == 0 { intervals } else { intervals + 1 };
    let h = (b - a) / n as f64;
    let mut total = integrand(s_m, b_m, t, l, a) + integrand(s_m, b_m, t, l, b);
    for i in 1..n {
        total += integrand(s_m, b_m, t, l, a + h * i as f64) * (if i % 2 == 1 { 4.0 } else { 2.0 });
    }
    total * h / 3.0
}

fn bending_stress(s_m: &[f64], b_m: &[f64], thickness_m: f64, length_m: f64, force_n: f64, s: f64) -> f64 {
    let b = width_at(s_m, b_m, s);
    if b <= 0.0 || thickness_m <= 0.0 {
        return 0.0;
    }
    let moment = force_n * (length_m - s);
    6.0 * moment / (b * thickness_m * thickness_m)
}
