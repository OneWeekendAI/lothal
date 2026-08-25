//! P6's closure — the forward-flight ratios as a PRECOMPUTED SURFACE, so the flight tick can
//! read BEMT instead of the anchored rules of thumb `propeller.rs` carried.
//!
//! ## Why a table exists at all
//!
//! `propulsion.md` §9's P6 row records that the BEMT-native ratios superseded
//! `PropellerModel::thrust_factor` / `power_factor`, and that the retirement was "the plumbing
//! swap that lands once callers pass chord through the powertrain". It is not a plumbing swap.
//! Measured on this machine, one thrust+power ratio pair costs **232 µs**, because each ratio
//! is two 40-annulus × 40-iteration solves. The flight tick evaluates twelve of them (four
//! motors in `step_in_flight`, eight more in `publish`), so a direct swap costs **~1.9 ms of
//! the 8.3 ms budget at 120 Hz — 22% of the tick, for one subsystem.**
//!
//! `bemt.rs`'s own rule is that "the solve must cost the same every call", and `propeller.rs`
//! said the same about its inflow iteration: *"the count is fixed so the flight tick costs the
//! same every tick."* A 1.9 ms per-tick BEMT solve honours the letter of that and breaks its
//! purpose. So the solve moves to build time and the tick reads an interpolant.
//!
//! ## What makes tabulating legitimate rather than a shortcut
//!
//! **The ratios are exactly self-similar.** Both are functions of the two dimensionless
//! inflow ratios
//!
//!     mu_axial = V_axial / (Omega·R),      mu_edge = V_edge / (Omega·R)
//!
//! and of NOTHING else — not RPM, not air density. The reason is structural rather than
//! empirical: phi = atan((V_ax + v_i)/(Omega·r)) is invariant when V and v_i both scale with
//! Omega, so alpha, C_l, C_d and the tip-loss factor are invariant too; and the blade-element
//! and momentum sides of the closure are BOTH linear in rho, so rho cancels out of the fixed
//! point and out of the ratio of two thrusts. `tests/test_bemt_ratios.gd` asserts this to the
//! BIT across a 3x RPM range and a 1.6x density range — it is not a tolerance, the numbers are
//! identical — which is what licenses a two-dimensional table to stand in for a five-argument
//! solve. If that assertion ever fails, this whole file is invalid and the test says so.
//!
//! ## The grid, and the error it costs
//!
//! 49 nodes in mu_axial × 13 in mu_edge over [0, 0.6]², bilinear. The anisotropy is measured,
//! not assumed: all of the surface's structure runs along mu_axial (the thrust ratio falls to
//! zero at roughly j_zero/pi ≈ 0.29 and the power ratio has its minimum just past there),
//! while the mu_edge direction is gentle. Refining mu_edge past 13 nodes stops helping — the
//! measured worst error saturates at ~0.031 — so the extra solves buy nothing.
//!
//! **Worst interpolation error, measured at grid midpoints on the reference 5x4.5x3: 0.031
//! absolute on the thrust ratio and 0.034 on the power ratio.** That is reported rather than
//! hidden, and `tests/test_bemt_ratios.gd` bounds it at 0.05 across the catalog. It is a real
//! cost and it is worth stating against what it sits inside: the catalog's own motor-to-motor
//! disagreement is 1.79x (labs-and-sim.md §1), and the polar under these ratios is
//! characteristic. A 3% interpolation error on a ratio is a twentieth of the uncertainty the
//! model already concedes — and unlike that uncertainty, this one is bounded and asserted.
//!
//! The surface is only piecewise smooth (the thrust clamp at 0 and the induced-power floor
//! both put kinks in it), so the convergence is linear in h, not quadratic. That is why
//! refining does not pay, and it is why the error is quoted as a measured bound rather than
//! extrapolated from an order.
//!
//! ## Beyond the grid
//!
//! mu is CLAMPED to [0, 0.6] rather than extrapolated. mu_axial = 0.6 is 80 m/s of axial
//! inflow at 20,000 RPM on a 5" prop — past it the thrust ratio has been zero for a factor of
//! two and the current the motor draws (which goes as RPM²) is negligible, so freezing the
//! ratio there costs nothing real. Extrapolating a bilinear fit off the end of a kinked
//! surface would not.
//!
//! ## Cost, and the cache
//!
//! Building one table is 637 nodes × one ratio pair ≈ 150 ms. The nodes call
//! `BemtModel::thrust_ratio_forward` and `power_ratio_forward` THEMSELVES rather than a
//! hoisted inner loop — which doubles the build cost, because each recomputes the static solve
//! — and that is deliberate. It makes "the table reproduces the direct solve at every node"
//! true by construction rather than by a second implementation staying in step with the first.
//! 150 ms once per distinct propeller is a price worth paying for not having two copies of the
//! short circuits.
//!
//! The cache is keyed on the propeller geometry itself, so a build that reconstructs (every
//! panel refresh does) pays once per session per prop, and a bench that never flies forward
//! pays nothing at all.

use godot::prelude::*;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::bemt::BemtModel;

/// The tabulated domain in both inflow ratios. See "Beyond the grid" above.
const MU_MAX: f64 = 0.6;
/// Nodes along mu_axial — where all of the structure is.
const MU_AXIAL_NODES: usize = 49;
/// Nodes along mu_edge. 13, because 17 measured no better (the error saturates at ~0.031).
const MU_EDGE_NODES: usize = 13;

struct RatioTable {
    thrust: Vec<f64>,
    power: Vec<f64>,
}

impl RatioTable {
    fn index(i: usize, j: usize) -> usize {
        i * MU_EDGE_NODES + j
    }

    /// Bilinear read at (mu_axial, mu_edge), both already clamped into the domain.
    fn sample(values: &[f64], mu_ax: f64, mu_ed: f64) -> f64 {
        let ha = MU_MAX / (MU_AXIAL_NODES - 1) as f64;
        let he = MU_MAX / (MU_EDGE_NODES - 1) as f64;
        let fa = (mu_ax / ha).clamp(0.0, (MU_AXIAL_NODES - 1) as f64);
        let fe = (mu_ed / he).clamp(0.0, (MU_EDGE_NODES - 1) as f64);
        let i0 = (fa.floor() as usize).min(MU_AXIAL_NODES - 2);
        let j0 = (fe.floor() as usize).min(MU_EDGE_NODES - 2);
        let ta = fa - i0 as f64;
        let te = fe - j0 as f64;
        let v00 = values[Self::index(i0, j0)];
        let v10 = values[Self::index(i0 + 1, j0)];
        let v01 = values[Self::index(i0, j0 + 1)];
        let v11 = values[Self::index(i0 + 1, j0 + 1)];
        v00 * (1.0 - ta) * (1.0 - te)
            + v10 * ta * (1.0 - te)
            + v01 * (1.0 - ta) * te
            + v11 * ta * te
    }
}

type CacheKey = (u64, u64, u64, Vec<u64>);

fn cache() -> &'static Mutex<HashMap<CacheKey, Arc<RatioTable>>> {
    static CACHE: OnceLock<Mutex<HashMap<CacheKey, Arc<RatioTable>>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// The geometry IS the key. Bit patterns rather than rounded values, because two propellers
/// that differ in the last bit of a chord station are two different planforms and a rounded
/// key would quietly hand the second one the first one's surface.
fn key_of(diameter_m: f64, pitch_m: f64, blades: f64, chord: &PackedFloat64Array) -> CacheKey {
    (
        diameter_m.to_bits(),
        pitch_m.to_bits(),
        blades.to_bits(),
        chord.as_slice().iter().map(|v| v.to_bits()).collect(),
    )
}

fn build_table(
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    chord: &PackedFloat64Array,
) -> Arc<RatioTable> {
    let n = MU_AXIAL_NODES * MU_EDGE_NODES;
    let mut thrust = vec![0.0; n];
    let mut power = vec![0.0; n];

    // The node solves are run at a REFERENCE RPM and a REFERENCE density, and the velocities
    // are derived back from mu. Which reference is used cannot matter — that is precisely the
    // self-similarity the module docs claim and the test asserts — so the values are the
    // ordinary ones rather than anything chosen.
    let reference_rpm = 20_000.0;
    let reference_rho = 1.225;
    let omega_r = (reference_rpm * std::f64::consts::TAU / 60.0) * (diameter_m * 0.5);

    let ha = MU_MAX / (MU_AXIAL_NODES - 1) as f64;
    let he = MU_MAX / (MU_EDGE_NODES - 1) as f64;
    for i in 0..MU_AXIAL_NODES {
        for j in 0..MU_EDGE_NODES {
            let v_ax = (i as f64 * ha) * omega_r;
            let v_ed = (j as f64 * he) * omega_r;
            let idx = RatioTable::index(i, j);
            thrust[idx] = BemtModel::thrust_ratio_forward(
                reference_rho, diameter_m, pitch_m, blades, reference_rpm,
                chord.clone(), v_ax, v_ed);
            power[idx] = BemtModel::power_ratio_forward(
                reference_rho, diameter_m, pitch_m, blades, reference_rpm,
                chord.clone(), v_ax, v_ed);
        }
    }
    Arc::new(RatioTable { thrust, power })
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct BemtRatios {
    table: Arc<RatioTable>,
    radius_m: f64,
}

#[godot_api]
impl BemtRatios {
    /// The ratio surface for one propeller, from the cache or freshly solved. Geometry only —
    /// no RPM and no air density, because the surface depends on neither (see module docs).
    ///
    /// A propeller with no radius has no surface: `for_prop` still returns an object, and every
    /// query on it returns 1.0, which is the "no forward-flight effect" answer rather than a
    /// division by zero. A caller that has no propeller is not flying.
    #[func]
    pub fn for_prop(
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        chord_points_mm: PackedFloat64Array,
    ) -> Gd<Self> {
        let radius_m = diameter_m * 0.5;
        if radius_m <= 0.0 || blades <= 0.0 || chord_points_mm.len() < 4 {
            return Gd::from_object(Self {
                table: Arc::new(RatioTable { thrust: vec![], power: vec![] }),
                radius_m: 0.0,
            });
        }
        let key = key_of(diameter_m, pitch_m, blades, &chord_points_mm);
        let table = {
            let mut guard = cache().lock().expect("bemt ratio cache should not be poisoned");
            if let Some(hit) = guard.get(&key) {
                hit.clone()
            } else {
                // Built OUTSIDE the guard would be tidier, but the lock is uncontended in
                // practice (one thread builds, the flight tick only reads a built table) and
                // holding it means two callers asking for the same new prop in the same frame
                // solve it once rather than twice.
                let built = build_table(diameter_m, pitch_m, blades, &chord_points_mm);
                guard.insert(key, built.clone());
                built
            }
        };
        Gd::from_object(Self { table, radius_m })
    }

    /// The fraction of static thrust this prop still makes at this airspeed and RPM — the
    /// BEMT-native replacement for the deleted `PropellerModel::thrust_factor`.
    ///
    /// Three short circuits, and the first is LOAD-BEARING: standing still returns exactly 1.0,
    /// by construction rather than by an interpolation that happens to land there, so the
    /// static path P5's calibration is anchored on cannot move by a rounding difference.
    /// Descent returns 1.0 as the model DECLINING to answer (§8: momentum theory has no
    /// standing in the vortex-ring state), which is the same refusal `solve_forward` makes.
    /// A stopped rotor returns 1.0 because a ratio of zero thrusts is not a number — and the
    /// thrust it multiplies is zero anyway.
    #[func]
    pub fn thrust_ratio(&self, rpm: f64, v_axial_mps: f64, v_edge_mps: f64) -> f64 {
        self.read(&self.table.thrust, rpm, v_axial_mps, v_edge_mps)
    }

    /// The shaft-power ratio — the BEMT-native replacement for the deleted
    /// `PropellerModel::power_factor`, and therefore the factor pack current and reaction
    /// torque both carry. Same three short circuits as `thrust_ratio`.
    #[func]
    pub fn power_ratio(&self, rpm: f64, v_axial_mps: f64, v_edge_mps: f64) -> f64 {
        self.read(&self.table.power, rpm, v_axial_mps, v_edge_mps)
    }

    /// The tabulated domain, for a test that wants to prove the flight envelope stays inside it
    /// and for a panel that wants to say when it did not.
    #[func]
    pub fn domain_mu_max() -> f64 {
        MU_MAX
    }

    /// [mu_axial_nodes, mu_edge_nodes], so the interpolation-error proof can put its sample
    /// points at grid MIDPOINTS — where bilinear error is worst — rather than near nodes,
    /// where it would flatter itself.
    #[func]
    pub fn node_counts() -> PackedFloat64Array {
        PackedFloat64Array::from([MU_AXIAL_NODES as f64, MU_EDGE_NODES as f64])
    }

    /// The inflow ratio a given RPM and airspeed lands at, exposed so a caller can ask whether
    /// it is inside `domain_mu_max()` before trusting the answer.
    #[func]
    pub fn mu_for(&self, rpm: f64, v_mps: f64) -> f64 {
        let omega_r = (rpm * std::f64::consts::TAU / 60.0) * self.radius_m;
        if omega_r <= 0.0 {
            return 0.0;
        }
        v_mps / omega_r
    }

    fn read(&self, values: &[f64], rpm: f64, v_axial_mps: f64, v_edge_mps: f64) -> f64 {
        if values.is_empty() {
            return 1.0;
        }
        if (v_axial_mps == 0.0 && v_edge_mps == 0.0) || v_axial_mps < 0.0 {
            return 1.0;
        }
        let omega_r = (rpm * std::f64::consts::TAU / 60.0) * self.radius_m;
        if omega_r <= 0.0 {
            return 1.0;
        }
        let mu_ax = (v_axial_mps / omega_r).clamp(0.0, MU_MAX);
        let mu_ed = (v_edge_mps.abs() / omega_r).clamp(0.0, MU_MAX);
        RatioTable::sample(values, mu_ax, mu_ed)
    }
}
