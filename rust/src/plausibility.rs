//! The plausibility arithmetic, ported from src/assembly/{motor_plausibility,prop_plausibility,
//! prop_extrapolation}.gd (Tier 2). These are the bands that reject a bad fit — the part of the
//! fitting pipeline the design calls the moat.
//!
//! GDScript keeps the catalog iteration, the Dictionary plumbing and BuildWarning construction;
//! the arithmetic (log-log regressions, the k_t band, the extrapolation factors and the
//! dominant-term ranking) is here, a pure function of typed inputs.

use godot::prelude::*;

use crate::bemt::BemtModel;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Plausibility;

#[godot_api]
impl Plausibility {
    /// The log-log linear regression behind kv_law, mass_law and thrust_density_band — the same
    /// mean/covariance/variance shape in three files, given one home. Returns
    /// [exponent, coefficient, residual_high, count]; zeros (and the real count) for fewer than
    /// three points, matching each original's guard.
    #[func]
    fn log_log_fit(xs: PackedFloat64Array, ys: PackedFloat64Array) -> PackedFloat64Array {
        let n = xs.len();
        if n < 3 || ys.len() != n {
            return PackedFloat64Array::from([0.0, 0.0, 0.0, n as f64]);
        }
        let mut mean_x = 0.0;
        let mut mean_y = 0.0;
        for i in 0..n {
            mean_x += xs[i];
            mean_y += ys[i];
        }
        mean_x /= n as f64;
        mean_y /= n as f64;

        let mut covariance = 0.0;
        let mut variance = 0.0;
        for i in 0..n {
            covariance += (xs[i] - mean_x) * (ys[i] - mean_y);
            variance += (xs[i] - mean_x) * (xs[i] - mean_x);
        }
        if variance <= 0.0 {
            return PackedFloat64Array::from([0.0, 0.0, 0.0, n as f64]);
        }

        let exponent = covariance / variance;
        let intercept = mean_y - exponent * mean_x;

        let mut residual_high = 1.0f64;
        for i in 0..n {
            residual_high = residual_high.max((ys[i] - (intercept + exponent * xs[i])).abs().exp());
        }

        PackedFloat64Array::from([exponent, intercept.exp(), residual_high, n as f64])
    }

    /// The plausibility band drawn around a population of implied k_t values (one per shipped
    /// motor, moved onto the prop asked about). Returns
    /// [low, high, observed_low, observed_high, count]; a widened band around the observed
    /// spread, and the empty-case returns the same "no band" shape the GDScript did.
    #[func]
    fn band_around(values: PackedFloat64Array, band_widening: f64) -> PackedFloat64Array {
        let n = values.len();
        let mut lowest = f64::INFINITY;
        let mut highest = -f64::INFINITY;
        let mut count = 0usize;
        for i in 0..n {
            let k = values[i];
            if k <= 0.0 {
                continue;
            }
            lowest = lowest.min(k);
            highest = highest.max(k);
            count += 1;
        }
        if count == 0 {
            return PackedFloat64Array::from([0.0, f64::INFINITY, 0.0, 0.0, 0.0]);
        }
        PackedFloat64Array::from([
            lowest / band_widening,
            highest * band_widening,
            lowest,
            highest,
            count as f64,
        ])
    }

    /// The distance between two props in THRUST terms, and its magnitude from 1.0. Since P5
    /// the cross-prop k_t move is the BEMT geometry ratio (§0) — blade count and twist enter
    /// the integral where they act — so this is no longer a separable D⁴/blades^0.8/pitch^0.5
    /// decomposition with a dominant term; it is the single ratio, applied at the test RPM.
    /// Returns [ratio, magnitude] where magnitude = max(ratio, 1/ratio) (symmetric around 1.0:
    /// a prop that HALVES k_t is extrapolating just as far as one that DOUBLES it).
    #[func]
    fn extrapolation_factors(
        from_d: f64, from_pitch: f64, from_blades: f64, from_chord: PackedFloat64Array,
        to_d: f64, to_pitch: f64, to_blades: f64, to_chord: PackedFloat64Array,
        rpm: f64,
    ) -> PackedFloat64Array {
        let ratio = BemtModel::scale_k_t_to_prop(
            1.0,
            from_d, from_pitch, from_blades, from_chord,
            to_d, to_pitch, to_blades, to_chord,
            rpm,
        );
        let magnitude = ratio.max(1.0 / ratio);
        PackedFloat64Array::from([ratio, magnitude])
    }
}
