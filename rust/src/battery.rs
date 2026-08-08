//! Voltage sag, capacity drain, and how far the pack has fallen as it empties (physics.md §5).
//! Ported from src/sim/battery_model.gd, golden cross-checked before the GDScript was
//! deleted. This is the file where a transcription error is most likely and least visible —
//! a wrong discharge curve moves hover throttle by a few percent and nothing crashes — so the
//! curve tables below are a VERBATIM transcription, checked by the SoC-range cross-check.
//!
//! Two separate things pull the voltage down:
//!   resting_voltage_v()  — where the pack sits with nothing drawing from it, which falls as
//!                          the pack empties. Slow, and it never comes back on its own.
//!   I * internal_r_ohm   — the sag under load. Instant, and it recovers the moment the
//!                          throttle does.
//!
//! THE DATUM: nominal_v is an operating point, not full charge. A full pack rests ABOVE
//! nominal and an empty one below it. The state-of-charge term is displacement from the
//! chemistry's nominal cell voltage, so a contributor rounding 21.6 V to 22 V still gets a
//! curve hung off the figure the catalog actually states.

use godot::prelude::*;

const DEFAULT_CHEMISTRY: &str = "LiPo";

/// Per-cell open-circuit voltage against state of charge, ascending by SoC.
/// Verbatim from battery_model.gd (sources cited in physics.md §5; both are class-typical
/// published resting curves rather than a measurement of one specific cell).
const CURVES_LIPO: [(f64, f64); 12] = [
    (0.00, 3.27),
    (0.05, 3.40),
    (0.10, 3.50),
    (0.20, 3.63),
    (0.30, 3.70),
    (0.40, 3.75),
    (0.50, 3.79),
    (0.60, 3.83),
    (0.70, 3.87),
    (0.80, 3.97),
    (0.90, 4.08),
    (1.00, 4.20),
];
const CURVES_LIION: [(f64, f64); 12] = [
    (0.00, 2.80),
    (0.05, 3.05),
    (0.10, 3.22),
    (0.20, 3.40),
    (0.30, 3.50),
    (0.40, 3.57),
    (0.50, 3.63),
    (0.60, 3.70),
    (0.70, 3.78),
    (0.80, 3.88),
    (0.90, 4.03),
    (1.00, 4.20),
];

/// Where each chemistry's NOMINAL voltage sits on its own curve, per cell. The state-of-charge
/// term is displacement from here. Published figures (3.7 V LiPo, 3.6 V Li-ion 18650/21700),
/// not values read off the curve — the two must agree, which test_battery_model.gd asserts.
const NOMINAL_CELL_LIPO: f64 = 3.70;
const NOMINAL_CELL_LIION: f64 = 3.60;

fn curve(chemistry: &str) -> &'static [(f64, f64)] {
    match chemistry {
        "Li-ion" => &CURVES_LIION,
        _ => &CURVES_LIPO, // DEFAULT_CHEMISTRY, and the fallback for any unknown string
    }
}

fn nominal_cell(chemistry: &str) -> f64 {
    match chemistry {
        "Li-ion" => NOMINAL_CELL_LIION,
        _ => NOMINAL_CELL_LIPO,
    }
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct BatteryModel {
    #[var]
    pub nominal_v: f64,
    #[var]
    pub internal_r_ohm: f64,
    #[var]
    pub capacity_mah: f64,
    #[var]
    pub used_mah: f64,
    /// Cell count, which turns the per-cell curve into a pack curve.
    #[var]
    pub cells: i64,
    /// Selects the curve. See the original header for why chemistry is a spec, not metadata.
    #[var]
    pub chemistry: GString,
}

#[godot_api]
impl BatteryModel {
    /// GDScript's `BatteryModel.new(...)` — a static factory is the gdext idiom for
    /// constructor arguments. `p_cells` defaults to whatever the nominal voltage implies at
    /// 3.7 V per cell, so a pack constructed directly still gets the right curve shape.
    #[func]
    pub fn create(nominal_v: f64, internal_r_ohm: f64, capacity_mah: f64, cells: i64,
              chemistry: GString) -> Gd<Self> {
        let chem = chemistry.to_string();
        let cells = if cells > 0 {
            cells
        } else {
            (nominal_v / 3.7).round().max(1.0) as i64
        };
        // Unknown chemistry falls back to LiPo: batteries.json is contributor-editable and a
        // typo must not silently delete the model and leave a flat baseline.
        let chemistry = match chem.as_str() {
            "LiPo" | "Li-ion" => chemistry,
            _ => GString::from(DEFAULT_CHEMISTRY),
        };
        Gd::from_object(Self {
            nominal_v,
            internal_r_ohm,
            capacity_mah,
            used_mah: 0.0,
            cells,
            chemistry,
        })
    }

    /// Where the pack sits with nothing drawing from it. Falls as the pack empties, passing
    /// THROUGH nominal_v partway down rather than starting there.
    #[func]
    pub fn resting_voltage_v(&self) -> f64 {
        self.nominal_v + self.soc_offset_v()
    }

    /// The state-of-charge term itself, in volts at the pack. POSITIVE above the nominal
    /// point and negative below it — the whole content of the change of datum.
    #[func]
    pub fn soc_offset_v(&self) -> f64 {
        let cells = self.cells as f64;
        cells * (Self::cell_open_circuit_v(self.remaining_fraction(), self.chemistry.clone())
            - Self::nominal_cell_v(self.chemistry.clone()))
    }

    /// The nominal resting voltage of one cell of a chemistry. Falls back to LiPo's alongside
    /// the curve, so an unrecognised chemistry gets a consistent pair rather than one of each.
    #[func]
    pub fn nominal_cell_v(chemistry: GString) -> f64 {
        nominal_cell(&chemistry.to_string())
    }

    /// One cell's resting voltage at a state of charge, linearly interpolated between the knots.
    #[func]
    pub fn cell_open_circuit_v(soc: f64, chemistry: GString) -> f64 {
        let curve = curve(&chemistry.to_string());
        let clamped = soc.clamp(0.0, 1.0);

        for i in 1..curve.len() {
            let high = curve[i];
            if clamped <= high.0 {
                let low = curve[i - 1];
                let span = high.0 - low.0;
                // Guard against a duplicated knot rather than dividing by zero: two entries at
                // the same state of charge is a typo, and the sane reading of it is a step.
                if span <= 0.0 {
                    return high.1;
                }
                let t = (clamped - low.0) / span;
                return low.1 + (high.1 - low.1) * t;
            }
        }
        curve[curve.len() - 1].1
    }

    /// Puts this pack AT the nominal datum. This is the aircraft's reference operating point.
    #[func]
    pub fn set_to_nominal_datum(&mut self) {
        let soc = Self::soc_at_nominal(self.chemistry.clone());
        self.used_mah = self.capacity_mah * (1.0 - soc);
    }

    /// Where a chemistry's nominal voltage sits on its own discharge, as a state of charge.
    /// Bisected on the curve rather than written down: about 30% for a LiPo, about 45% for a
    /// Li-ion, and a fourth hand-entered number would be a fourth thing to keep in step.
    #[func]
    pub fn soc_at_nominal(chemistry: GString) -> f64 {
        let target = Self::nominal_cell_v(chemistry.clone());
        let mut low = 0.0;
        let mut high = 1.0;
        for _ in 0..200 {
            let mid = (low + high) * 0.5;
            if Self::cell_open_circuit_v(mid, chemistry.clone()) < target {
                low = mid;
            } else {
                high = mid;
            }
        }
        high
    }

    /// What one cell of this pack is resting at. Pack voltage means nothing without the cell
    /// count beside it.
    #[func]
    pub fn resting_cell_v(&self) -> f64 {
        if self.cells <= 0 {
            return self.resting_voltage_v();
        }
        self.resting_voltage_v() / self.cells as f64
    }

    #[func]
    pub fn voltage_live(&self, current_total_a: f64) -> f64 {
        self.resting_voltage_v() - current_total_a * self.internal_r_ohm
    }

    #[func]
    pub fn drain(&mut self, current_total_a: f64, dt: f64) {
        self.used_mah += current_total_a * (dt / 3600.0) * 1000.0;
    }

    #[func]
    pub fn remaining_fraction(&self) -> f64 {
        (1.0 - self.used_mah / self.capacity_mah).clamp(0.0, 1.0)
    }
}
