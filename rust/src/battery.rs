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
const NOMINAL_CELL_LIPO_HV: f64 = 3.85;
const NOMINAL_CELL_LIFEPO4: f64 = 3.20;

/// LiPo HV (4.35 V full) resting curve, class-typical published figures for high-voltage
/// pouch cells. Sits above the plain LiPo curve through the middle.
const CURVES_LIPO_HV: [(f64, f64); 12] = [
    (0.00, 3.30),
    (0.05, 3.45),
    (0.10, 3.55),
    (0.20, 3.68),
    (0.30, 3.76),
    (0.40, 3.82),
    (0.50, 3.87),
    (0.60, 3.93),
    (0.70, 4.00),
    (0.80, 4.10),
    (0.90, 4.22),
    (1.00, 4.35),
];

/// LiFePO4 (2.5-3.65 V) resting curve, class-typical (A123 26650-style cells): a very flat
/// plateau around 3.2-3.3 V between the knee and the top.
const CURVES_LIFEPO4: [(f64, f64); 12] = [
    (0.00, 2.80),
    (0.05, 3.00),
    (0.10, 3.15),
    (0.20, 3.22),
    (0.30, 3.25),
    (0.40, 3.27),
    (0.50, 3.28),
    (0.60, 3.30),
    (0.70, 3.32),
    (0.80, 3.33),
    (0.90, 3.40),
    (1.00, 3.65),
];

/// Ambient air temperature for the display-only thermal model, degrees C.
pub const AMBIENT_C: f64 = 25.0;
/// Specific heat of a lithium cell, J/(kg*K). Class-typical figure (about 900), an ideal value.
const CELL_CP_J_PER_KG_K: f64 = 900.0;
/// Cooling conductance h*A per gram of cell, W/K/g. A LABELLED GUESS for a pack in still-ish air,
/// not a measurement: ideal, display-only. It never feeds voltage, resistance or Build.
pub const COOLING_W_PER_K_PER_G: f64 = 0.002;

/// One explicit-Euler step of dT = (I^2 R - hA (T - ambient)) / (m cp) * dt for one cell.
/// Mass in grams. Substeps keep it stable if a caller passes a large dt.
fn cell_temp_step_impl(temp_c: f64, current_cell_a: f64, r_cell_ohm: f64, mass_g: f64, dt_s: f64) -> f64 {
    if mass_g <= 0.0 || dt_s <= 0.0 {
        return temp_c;
    }
    let heat_cap = mass_g / 1000.0 * CELL_CP_J_PER_KG_K; // J/K
    let h_a = COOLING_W_PER_K_PER_G * mass_g; // W/K
    let tau = heat_cap / h_a;
    let n = (dt_s / (tau * 0.1)).ceil().max(1.0) as u32;
    let h = dt_s / n as f64;
    let mut t = temp_c;
    for _ in 0..n {
        let p_in = current_cell_a * current_cell_a * r_cell_ohm;
        t += (p_in - h_a * (t - AMBIENT_C)) / heat_cap * h;
    }
    t
}

/// The four chemistries the model knows, in display order.
pub const KNOWN_CHEMISTRIES: [&str; 4] = ["LiPo", "LiPo HV", "Li-ion", "LiFePO4"];

fn known_chemistry(chemistry: &str) -> bool {
    KNOWN_CHEMISTRIES.contains(&chemistry)
}

/// Lowest per-cell voltage the chemistry should be discharged to under load (cutoff).
fn min_cell_v(chemistry: &str) -> f64 {
    match chemistry {
        "Li-ion" | "LiFePO4" => 2.5,
        _ => 3.0,
    }
}

/// Full-charge per-cell voltage; equals the top knot of the curve.
fn max_cell_v(chemistry: &str) -> f64 {
    match chemistry {
        "LiPo HV" => 4.35,
        "LiFePO4" => 3.65,
        _ => 4.2,
    }
}

/// Class-typical maximum charge rate, in C. Conservative, label as ideal.
fn max_charge_c(chemistry: &str) -> f64 {
    match chemistry {
        "Li-ion" => 0.5,
        _ => 1.0,
    }
}

/// Class-typical maximum cell temperature in degrees C.
fn max_temp_c(_chemistry: &str) -> f64 {
    60.0
}

/// Class-typical gravimetric energy density, Wh/kg, at cell level.
fn typical_wh_per_kg(chemistry: &str) -> f64 {
    match chemistry {
        "LiPo HV" => 170.0,
        "Li-ion" => 250.0,
        "LiFePO4" => 110.0,
        _ => 150.0,
    }
}

fn curve(chemistry: &str) -> &'static [(f64, f64)] {
    match chemistry {
        "Li-ion" => &CURVES_LIION,
        "LiPo HV" => &CURVES_LIPO_HV,
        "LiFePO4" => &CURVES_LIFEPO4,
        _ => &CURVES_LIPO, // DEFAULT_CHEMISTRY, and the fallback for any unknown string
    }
}

fn nominal_cell(chemistry: &str) -> f64 {
    match chemistry {
        "Li-ion" => NOMINAL_CELL_LIION,
        "LiPo HV" => NOMINAL_CELL_LIPO_HV,
        "LiFePO4" => NOMINAL_CELL_LIFEPO4,
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
        let chemistry = if known_chemistry(chem.as_str()) {
            chemistry
        } else {
            GString::from(DEFAULT_CHEMISTRY)
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

    #[func]
    pub fn is_known_chemistry(chemistry: GString) -> bool {
        known_chemistry(&chemistry.to_string())
    }

    #[func]
    pub fn known_chemistries() -> PackedStringArray {
        KNOWN_CHEMISTRIES.iter().map(|c| GString::from(*c)).collect()
    }

    /// Display-only lumped thermal step for one cell. Never feeds back into the electrical model.
    #[func]
    pub fn cell_temp_step(temp_c: f64, current_cell_a: f64, r_cell_ohm: f64, mass_g: f64, dt_s: f64) -> f64 {
        cell_temp_step_impl(temp_c, current_cell_a, r_cell_ohm, mass_g, dt_s)
    }

    #[func]
    pub fn min_cell_v(chemistry: GString) -> f64 {
        min_cell_v(&chemistry.to_string())
    }

    #[func]
    pub fn max_cell_v(chemistry: GString) -> f64 {
        max_cell_v(&chemistry.to_string())
    }

    #[func]
    pub fn max_charge_c(chemistry: GString) -> f64 {
        max_charge_c(&chemistry.to_string())
    }

    #[func]
    pub fn max_temp_c(chemistry: GString) -> f64 {
        max_temp_c(&chemistry.to_string())
    }

    #[func]
    pub fn typical_wh_per_kg(chemistry: GString) -> f64 {
        typical_wh_per_kg(&chemistry.to_string())
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

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: [&str; 4] = ["LiPo", "LiPo HV", "Li-ion", "LiFePO4"];

    #[test]
    fn curves_monotonic_and_end_at_limits() {
        for chem in ALL {
            assert!(known_chemistry(chem), "{chem} should be known");
            let c = curve(chem);
            for w in c.windows(2) {
                assert!(w[1].0 > w[0].0, "{chem}: soc knots must ascend");
                assert!(w[1].1 >= w[0].1, "{chem}: voltage must not fall as soc rises");
            }
            assert_eq!(c[c.len() - 1].0, 1.0);
            assert_eq!(c[c.len() - 1].1, max_cell_v(chem), "{chem}: full cell sits at its max");
            assert!(c[0].1 >= min_cell_v(chem) - 0.3, "{chem}: empty knot near min");
            let n = nominal_cell(chem);
            assert!(n > c[0].1 && n < c[c.len() - 1].1, "{chem}: nominal on its curve");
        }
        assert!(!known_chemistry("Unobtainium"));
    }

    #[test]
    fn no_current_stays_ambient() {
        assert_eq!(cell_temp_step_impl(AMBIENT_C, 0.0, 0.02, 40.0, 1.0), AMBIENT_C);
    }

    #[test]
    fn heats_with_current_and_cools_back_to_ambient() {
        let mut t = AMBIENT_C;
        for _ in 0..120 {
            t = cell_temp_step_impl(t, 20.0, 0.02, 40.0, 1.0);
        }
        assert!(t > AMBIENT_C + 1.0, "heated to {t}");
        let hot = t;
        for _ in 0..6000 {
            t = cell_temp_step_impl(t, 0.0, 0.02, 40.0, 1.0);
        }
        assert!(t < hot && (t - AMBIENT_C).abs() < 0.5, "cooled to {t}");
    }

    #[test]
    fn steady_state_matches_analytic() {
        let (i, r, m) = (10.0, 0.02, 40.0);
        let mut t = AMBIENT_C;
        for _ in 0..20000 {
            t = cell_temp_step_impl(t, i, r, m, 1.0);
        }
        let expect = AMBIENT_C + i * i * r / (COOLING_W_PER_K_PER_G * m);
        assert!(((t - expect) / (expect - AMBIENT_C)).abs() < 0.01, "got {t} want {expect}");
    }

    #[test]
    fn match_arms_cover_all() {
        assert_ne!(nominal_cell("LiFePO4"), nominal_cell("LiPo"));
        assert_ne!(nominal_cell("LiPo HV"), nominal_cell("LiPo"));
        assert_ne!(curve("LiFePO4")[5].1, curve("LiPo")[5].1);
    }
}
