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

/// (diameter, pitch, blades, guard_closure, chord[]). The closure is a full u64 bit-pattern,
/// same discipline as the geometry fields: two closures that differ in the last bit are two
/// different tables, so the cache cannot silently hand the second one the first one's surface.
type CacheKey = (u64, u64, u64, u64, Vec<u64>, Vec<u64>);

fn cache() -> &'static Mutex<HashMap<CacheKey, Arc<RatioTable>>> {
    static CACHE: OnceLock<Mutex<HashMap<CacheKey, Arc<RatioTable>>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// The geometry PLUS the guard closure IS the key. Bit patterns rather than rounded values,
/// because two propellers that differ in the last bit of a chord station are two different
/// planforms and a rounded key would quietly hand the second one the first one's surface —
/// and same for two guards that differ in the last bit of `tip_loss_closure`'s output.
fn key_of(diameter_m: f64, pitch_m: f64, blades: f64, guard_closure: f64,
        chord: &PackedFloat64Array, twist: &PackedFloat64Array) -> CacheKey {
    (
        diameter_m.to_bits(),
        pitch_m.to_bits(),
        blades.to_bits(),
        guard_closure.to_bits(),
        chord.as_slice().iter().map(|v| v.to_bits()).collect(),
        twist.as_slice().iter().map(|v| v.to_bits()).collect(),
    )
}

fn build_table(
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    chord: &PackedFloat64Array,
    guard_closure: f64,
    twist: &PackedFloat64Array,
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
            thrust[idx] = BemtModel::thrust_ratio_forward_with_guard(
                reference_rho, diameter_m, pitch_m, blades, reference_rpm,
                chord.clone(), v_ax, v_ed, guard_closure, twist.clone());
            power[idx] = BemtModel::power_ratio_forward_with_guard(
                reference_rho, diameter_m, pitch_m, blades, reference_rpm,
                chord.clone(), v_ax, v_ed, guard_closure, twist.clone());
        }
    }
    Arc::new(RatioTable { thrust, power })
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct BemtRatios {
    table: Arc<RatioTable>,
    radius_m: f64,
    /// The guard closure this surface was BUILT with — carried so `static_closure_factor()`
    /// can answer without a second key lookup, and so the "changing the guard invalidates the
    /// build's cached surface" test can assert on it directly. 0.0 for an unfitted guard.
    guard_closure: f64,
    /// Cached at construction to avoid a fresh solve every time the panel or a warning asks.
    /// Recomputed only when `for_prop_with_guard` builds a new object. Thrust and torque are
    /// cached as a PAIR because the closure moves them in OPPOSITE directions and a caller
    /// that took only the thrust half would derive torque from it — see
    /// `BemtModel::static_closure_factors` for the measured numbers and what that costs.
    static_closure_factor_cached: f64,
    static_closure_torque_factor_cached: f64,
    /// The geometry, kept so `static_closure_factor` can re-solve if asked about a different
    /// closure — but not the primary reason: the primary reason is that a test that CHECKS
    /// the factor should be able to do so from just the surface object.
    diameter_m: f64,
    pitch_m: f64,
    blades: f64,
    chord_points_mm: PackedFloat64Array,
    /// SR1: rear-rotor thrust loss fraction in forward flight (rotor-rotor interference). 0 = off.
    /// PUBLISHED: 11% thrust loss on the rear rotors of an X quadcopter at 5-15 m/s, negligible in
    /// hover and at 25 m/s (CFD, Aerospace 8(11):349, 2021), expressed as wake skew. The Build sets it for aircraft with four
    /// or more rotors. See `interference_power_factor`.
    #[var]
    pub interference_loss: f64,
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
        // Delegates with guard_closure = 0.0 through the SAME cache lookup — bit-identity is
        // a property of the cache key plus the build path, not a promise the wrapper repeats.
        Self::for_prop_with_guard(diameter_m, pitch_m, blades, chord_points_mm, 0.0, PackedFloat64Array::new())
    }

    /// The P10b closure-aware surface (plans/2026-08-26-propulsion-room-design.md §4). Two
    /// propellers that differ only in their fitted guard are two different cacheable surfaces
    /// because `guard_closure` sits in the cache key; a `Build` that changes its `guard_id`
    /// invalidates its own `_forward_ratios` handle and calls this again to get the new one
    /// (the Rust-side key alone would not save a build that cached the old surface — the
    /// invalidation obligation lives on the caller). `guard_closure = 0.0` reaches the SAME
    /// cache entry that `for_prop` populates, since both bit-key the same u64.
    #[func]
    pub fn for_prop_with_guard(
        diameter_m: f64,
        pitch_m: f64,
        blades: f64,
        chord_points_mm: PackedFloat64Array,
        guard_closure: f64,
        #[opt(default = &PackedFloat64Array::new())] twist_points: PackedFloat64Array,
    ) -> Gd<Self> {
        let radius_m = diameter_m * 0.5;
        if radius_m <= 0.0 || blades <= 0.0 || chord_points_mm.len() < 4 {
            return Gd::from_object(Self {
                table: Arc::new(RatioTable { thrust: vec![], power: vec![] }),
                radius_m: 0.0,
                guard_closure: 0.0,
                static_closure_factor_cached: 1.0,
                static_closure_torque_factor_cached: 1.0,
                diameter_m: 0.0,
                pitch_m: 0.0,
                blades: 0.0,
                chord_points_mm: PackedFloat64Array::new(),
                interference_loss: 0.0,
            });
        }
        let closure = guard_closure.clamp(0.0, 1.0);
        let key = key_of(diameter_m, pitch_m, blades, closure, &chord_points_mm, &twist_points);
        let table = {
            let mut guard = cache().lock().expect("bemt ratio cache should not be poisoned");
            if let Some(hit) = guard.get(&key) {
                hit.clone()
            } else {
                // Built OUTSIDE the guard would be tidier, but the lock is uncontended in
                // practice (one thread builds, the flight tick only reads a built table) and
                // holding it means two callers asking for the same new prop in the same frame
                // solve it once rather than twice.
                let built = build_table(diameter_m, pitch_m, blades, &chord_points_mm, closure, &twist_points);
                guard.insert(key, built.clone());
                built
            }
        };
        let static_factors = BemtModel::static_closure_factors(
            diameter_m, pitch_m, blades, chord_points_mm.clone(), closure, twist_points.clone());
        Gd::from_object(Self {
            table,
            radius_m,
            guard_closure: closure,
            static_closure_factor_cached: static_factors[0],
            static_closure_torque_factor_cached: static_factors[1],
            diameter_m,
            pitch_m,
            blades,
            chord_points_mm,
            interference_loss: 0.0,
        })
    }

    /// The closure this surface was built with. Exposed so `Build`'s test can assert that a
    /// change to `guard_id` produced a different surface (identity is not enough — a stale
    /// cache read would return a new-object handle with the OLD closure) rather than a mere
    /// object-identity check that a `null` reset would satisfy.
    #[func]
    pub fn guard_closure(&self) -> f64 {
        self.guard_closure
    }

    /// The static thrust multiplier a fitted guard earns — cached in the object. `Build`
    /// scales `k_t` by this so the panel's hover throttle reflects the closure the flight
    /// tick sees through the ratio surface (plan §4.0 "the closure reaches both").
    #[func]
    pub fn static_closure_factor(&self) -> f64 {
        self.static_closure_factor_cached
    }

    /// The static TORQUE multiplier the same guard earns — below 1 for a real duct, because
    /// closing the tip leak drops the induced velocity and with it the induced drag. Exposed
    /// alongside the thrust factor so no caller has to derive one from the other; deriving
    /// torque from a closure-scaled `k_t` is the defect `BemtModel::static_closure_factors`
    /// documents by measurement.
    #[func]
    pub fn static_closure_torque_factor(&self) -> f64 {
        self.static_closure_torque_factor_cached
    }

    /// The propeller geometry this surface was built on — exposed so a test can prove the
    /// stored chord is what the closure was computed with, not a copy that could drift.
    #[func]
    pub fn chord_points_mm(&self) -> PackedFloat64Array {
        self.chord_points_mm.clone()
    }
    #[func]
    pub fn diameter_m(&self) -> f64 { self.diameter_m }
    #[func]
    pub fn pitch_m(&self) -> f64 { self.pitch_m }
    #[func]
    pub fn blades(&self) -> f64 { self.blades }

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
        self.read(&self.table.thrust, rpm, v_axial_mps, v_edge_mps, false)
    }

    /// The shaft-power ratio — the BEMT-native replacement for the deleted
    /// `PropellerModel::power_factor`, and therefore the factor pack current and reaction
    /// torque both carry. Same three short circuits as `thrust_ratio`.
    #[func]
    pub fn power_ratio(&self, rpm: f64, v_axial_mps: f64, v_edge_mps: f64) -> f64 {
        let base = self.read(&self.table.power, rpm, v_axial_mps, v_edge_mps, true);
        base * Self::interference_power_factor(self.interference_loss, v_axial_mps, v_edge_mps, rpm, self.radius_m)
    }

    /// The wake-skew window of the rear-rotor interference, 0 to 1 (see `interference_power_factor` for the
    /// derivation and the ESTIMATED shapes). Shared by the power factor and the thrust factor so the two cannot
    /// drift apart.
    #[func]
    pub fn interference_weight(v_axial_mps: f64, v_edge_mps: f64, rpm: f64, radius_m: f64) -> f64 {
        let v = (v_axial_mps * v_axial_mps + v_edge_mps * v_edge_mps).sqrt();
        let omega_r = rpm * std::f64::consts::TAU / 60.0 * radius_m;
        if omega_r <= 0.0 {
            return 0.0;
        }
        let x = v / (0.08 * omega_r);
        let t = ((x - 0.5) / 0.5).clamp(0.0, 1.0);
        if x <= 1.0 { t * t * (3.0 - 2.0 * t) } else if x <= 3.0 { 1.0 } else if x < 5.0 { (5.0 - x) / 2.0 } else { 0.0 }
    }

    /// Thrust factor of a REAR rotor at equal rpm: 1 - loss * window. 1.0 in hover and at 25 m/s, 1 - loss at
    /// 5-15 m/s (PUBLISHED: 11 percent, CFD, Aerospace 8(11):349, 2021). Front rotors are not touched.
    #[func]
    pub fn interference_thrust_factor(loss: f64, v_axial_mps: f64, v_edge_mps: f64, rpm: f64, radius_m: f64) -> f64 {
        if loss <= 0.0 {
            return 1.0;
        }
        1.0 - loss.clamp(0.0, 0.5) * Self::interference_weight(v_axial_mps, v_edge_mps, rpm, radius_m)
    }

    /// Mean shaft-power factor for rotor-rotor interference. Half the rotors (the rear pair of an
    /// X quad) lose `loss` of their thrust, so they must make 1/(1-loss) times the thrust, and shaft
    /// power goes as thrust^1.5 (momentum theory), so the four-rotor mean is
    /// 1 + 0.5 * ((1-loss)^-1.5 - 1).
    ///
    /// The window is in WAKE-SKEW terms, not metres per second, because what decides whether the front
    /// wake lands on the rear rotor is how far it is swept back, i.e. airspeed against the rotor's own
    /// induced velocity. x = V / (0.08 omega R), 0.08 being the typical hover inflow ratio
    /// (ESTIMATED; CT 0.013 gives 0.081 on the Mavic prop). The published sampling (CFD, X quad:
    /// negligible in hover, 11% at 5-15 m/s, negligible at 25 m/s) maps to x of about 1 to 3 and 5 for a
    /// 1.2 kg quad whose v_h is about 5 m/s. Window: zero below x = 0.5 (the wake is still
    /// falling past the rear rotors: a rotor spacing near 1.5 D with the wake dropping about 1 D
    /// puts the onset near a 30 degree skew; ESTIMATED geometry), smoothstep to full at x = 1, full to 3,
    /// linear down to zero at 5 (shapes ESTIMATED). A first version with a plain quadratic from x = 0 made
    /// a 3 m/s breeze cost the 5 inch freestyle quad 3.7 percent more hover current than calm; the
    /// translational-lift ruling test caught it, and this onset is the geometry argument, not a fit.
    #[func]
    pub fn interference_power_factor(loss: f64, v_axial_mps: f64, v_edge_mps: f64, rpm: f64, radius_m: f64) -> f64 {
        if loss <= 0.0 {
            return 1.0;
        }
        let w = Self::interference_weight(v_axial_mps, v_edge_mps, rpm, radius_m);
        1.0 + w * 0.5 * ((1.0 - loss.clamp(0.0, 0.5)).powf(-1.5) - 1.0)
    }

    /// R1.5 — the induced velocity ratio vi/vh for a descent of `x` hover-inflows (x = descent speed / vh, >= 0).
    /// See `descent_inflow` for the branches and sources.
    #[func]
    pub fn descent_inflow_ratio(x: f64) -> f64 {
        descent_inflow(x)
    }

    /// R1.5 — the thrust ratio the inflow alone gives at fixed rpm (no flow-breakdown deficit). A GAIN in descent.
    #[func]
    pub fn descent_thrust_ratio_inflow_only(x: f64) -> f64 {
        thrust_from_inflow(x)
    }

    /// R1.5 — the pure-vertical-descent thrust ratio with the VRS mean deficit applied.
    #[func]
    pub fn descent_thrust_ratio_pure(x: f64) -> f64 {
        descent_thrust_ratio(x)
    }

    /// R1.5 — the pure-vertical-descent shaft-power ratio.
    #[func]
    pub fn descent_power_ratio_pure(x: f64) -> f64 {
        descent_power_ratio(x)
    }

    /// R1.5 — 0..1 bell over the VRS band (zero at and outside 0.25 and 1.5 vh, one at 1.0 vh).
    #[func]
    pub fn vrs_band_weight(x: f64) -> f64 {
        vrs_band(x)
    }

    /// R1.5 — 1 for a near-vertical descent, 0 once the in-plane speed sweeps the wake away.
    #[func]
    pub fn vrs_clearing(descent_mps: f64, v_edge_mps: f64) -> f64 {
        vrs_forward_clear(descent_mps, v_edge_mps)
    }

    /// R1.5 — what scales the thrust deficit AND the fluctuation at this state: band bell times forward clearing.
    /// Zero for climb, hover, forward flight and fast descent.
    #[func]
    pub fn vrs_weight(&self, rpm: f64, v_axial_mps: f64, v_edge_mps: f64) -> f64 {
        let omega_r = rpm * std::f64::consts::TAU / 60.0 * self.radius_m;
        if v_axial_mps >= 0.0 || omega_r <= 0.0 {
            return 0.0;
        }
        let x = -v_axial_mps / (VH_OVER_OMEGA_R * omega_r);
        vrs_band(x) * vrs_forward_clear(-v_axial_mps, v_edge_mps)
    }

    #[func]
    pub fn vrs_mean_deficit() -> f64 {
        VRS_MEAN_DEFICIT
    }

    #[func]
    pub fn vrs_fluct_rms() -> f64 {
        VRS_FLUCT_RMS
    }

    #[func]
    pub fn vrs_fluct_hz() -> f64 {
        VRS_FLUCT_HZ
    }

    /// Descent speed of one hover inflow (vh = 0.08 omega R, the same ESTIMATED figure used throughout this file).
    #[func]
    pub fn hover_inflow_mps(&self, rpm: f64) -> f64 {
        VH_OVER_OMEGA_R * rpm * std::f64::consts::TAU / 60.0 * self.radius_m
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

    fn read(&self, values: &[f64], rpm: f64, v_axial_mps: f64, v_edge_mps: f64, is_power: bool) -> f64 {
        if values.is_empty() {
            return 1.0;
        }
        if v_axial_mps == 0.0 && v_edge_mps == 0.0 {
            return 1.0;
        }
        let omega_r = (rpm * std::f64::consts::TAU / 60.0) * self.radius_m;
        if omega_r <= 0.0 {
            return 1.0;
        }
        let mu_ed = (v_edge_mps.abs() / omega_r).clamp(0.0, MU_MAX);
        if v_axial_mps < 0.0 {
            // DESCENT. Vortex ring and windmill brake are out of domain and read the static 1.0, but they need a descent
            // speed comparable to the hover inflow. A descent component of 0.1 m/s in 18 m/s of edgewise flow is the same
            // flow as a climb of 0.1 m/s, and returning 1.0 for it made the thrust ratio step from ~1.8 to 1.0 as the body
            // axial velocity of a fast-flying aircraft crossed zero (the CropMerge mapper flip, 2026-11-11). So the edgewise
            // answer at zero axial flow fades out linearly to 1.0 as the descent speed rises to the hover inflow
            // 0.08 omega R (ESTIMATED; the figure the rotor-rotor interference window uses). Pure descent stays exactly 1.0.
            let x = -v_axial_mps / (VH_OVER_OMEGA_R * omega_r);
            let w = (1.0 - x).clamp(0.0, 1.0);
            let old = if w == 0.0 {
                1.0
            } else {
                let edge = RatioTable::sample(values, 0.0, mu_ed);
                1.0 + w * (edge - 1.0)
            };
            // R1.5: vortex ring and windmill brake. Gated by the inflow angle so that anything but a near-vertical
            // descent reads exactly what it read before (see `vrs_forward_clear`).
            let wf = vrs_forward_clear(-v_axial_mps, v_edge_mps);
            if wf == 0.0 {
                return old;
            }
            let pure = if is_power { descent_power_ratio(x) } else { descent_thrust_ratio(x) };
            return old * (1.0 + wf * (pure - 1.0));
        }
        let mu_ax = (v_axial_mps / omega_r).clamp(0.0, MU_MAX);
        RatioTable::sample(values, mu_ax, mu_ed)
    }
}

// ---------------------------------------------------------------------------------------------------------------
// R1.5 — vortex ring state and windmill braking
// ---------------------------------------------------------------------------------------------------------------
//
// x = descent speed / vh, vh = hover induced velocity. Inflow branches, continuous at every edge:
//   x < 0.25        momentum theory continued into slow descent, eased onto the fit by 0.25;
//   0.25 .. 1.5     the Johnson (1980) empirical fit as printed in Leishman, Principles of Helicopter Aerodynamics:
//                   vi/vh = k + k1 x' + k2 x'^2 + k3 x'^3 + k4 x'^4, x' = Vc/vh = -x, k = 1 (hover = 1, because every
//                   ratio in this file is relative to the static solve), k1..k4 = -1.125, -1.372, -1.718, -0.655;
//   1.5 .. 2        eased onto the windmill branch (the fit and the momentum curve differ by 0.03 at 2);
//   x >= 2          momentum windmill brake: vi/vh = x/2 - sqrt(x^2/4 - 1).
//
// THE FIT ALONE IS WRONG ABOUT THRUST. At fixed rpm the net through-disc flow (vi - descent) falls in descent, the blades
// see a higher angle of attack and the thrust rises: the fit predicts a GAIN. Real vortex ring loses thrust because the
// flow breaks down, which an inflow fit cannot carry. So, by OWNER DECISION (2026-11-16), two LABELLED ESTIMATES sit on
// top, both bell-shaped over the band and zero at its edges: a mean thrust deficit (net thrust 15 percent below static at
// the peak) and a seeded fluctuation of 10 percent RMS band-limited to 3 Hz (Powertrain draws it, one stream per rotor).
// The constants marked ESTIMATED below are estimates, not measurements, and are the only place they live.

/// ESTIMATED hover inflow ratio vh / (omega R); the figure the rotor-rotor interference window already uses.
pub const VH_OVER_OMEGA_R: f64 = 0.08;
/// Band edges and peak, in vh (PUBLISHED: the VRS band of the Johnson fit, 0.25 to 1.5 vh of descent).
pub const VRS_X_LO: f64 = 0.25;
pub const VRS_X_PEAK: f64 = 1.0;
pub const VRS_X_HI: f64 = 1.5;
/// Windmill branch starts here (the momentum root needs x >= 2).
pub const WINDMILL_X: f64 = 2.0;
/// ESTIMATED: peak mean thrust loss against static thrust at the same rpm (owner decision).
pub const VRS_MEAN_DEFICIT: f64 = 0.15;
/// ESTIMATED: RMS of the thrust fluctuation at the band peak, as a fraction of thrust (owner decision).
pub const VRS_FLUCT_RMS: f64 = 0.10;
/// ESTIMATED: corner of the fluctuation low-pass, Hz.
pub const VRS_FLUCT_HZ: f64 = 3.0;
/// ESTIMATED: the wake is swept away between these descent angles measured from the disc plane (degrees): full VRS at
/// or above the upper, none at or below the lower. A 3 m/s drift against a 6 m/s descent is 63 degrees and clears it.
pub const VRS_CLEAR_DEG_LO: f64 = 70.0;
pub const VRS_CLEAR_DEG_HI: f64 = 85.0;
/// ESTIMATED thrust gain per unit of through-disc-flow change, in vh: dT/T = (vh - through) * this. From blade-element
/// theory with solidity 0.1, lift slope 5.7 and CT 0.013 (hover inflow ratio 0.08): 0.08 / (2 * 0.045) = 0.89.
const THRUST_PER_INFLOW: f64 = 0.8889;
/// ESTIMATED soft ceiling on the thrust GAIN (blade stall): ratio = 1 + CAP * tanh(gain / CAP).
const THRUST_GAIN_CAP: f64 = 1.0;
/// ESTIMATED profile (non-induced) share of hover shaft power for the power ratio in descent.
const PROFILE_SHARE: f64 = 0.35;
/// ESTIMATED floor under the descent power ratio: this powertrain cannot receive regeneration.
const DESCENT_POWER_FLOOR: f64 = 0.10;

fn smooth01(t: f64) -> f64 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn johnson_fit(x: f64) -> f64 {
    let y = -x;
    1.0 + y * (-1.125 + y * (-1.372 + y * (-1.718 + y * -0.655)))
}

fn momentum_descent(x: f64) -> f64 {
    x * 0.5 + (x * x * 0.25 + 1.0).sqrt()
}

fn momentum_windmill(x: f64) -> f64 {
    let r = x * x * 0.25 - 1.0;
    x * 0.5 - r.max(0.0).sqrt()
}

/// vi/vh at descent x (hover inflows), continuous on x >= 0.
pub fn descent_inflow(x: f64) -> f64 {
    let x = x.max(0.0);
    if x < VRS_X_LO {
        let off = johnson_fit(VRS_X_LO) - momentum_descent(VRS_X_LO);
        momentum_descent(x) + off * smooth01(x / VRS_X_LO)
    } else if x <= VRS_X_HI {
        johnson_fit(x)
    } else if x < WINDMILL_X {
        let s = smooth01((x - VRS_X_HI) / (WINDMILL_X - VRS_X_HI));
        johnson_fit(x) * (1.0 - s) + momentum_windmill(WINDMILL_X) * s
    } else {
        momentum_windmill(x)
    }
}

/// The thrust ratio the inflow alone gives at fixed rpm.
fn thrust_from_inflow(x: f64) -> f64 {
    let through = descent_inflow(x) - x;
    let gain = 1.0 + THRUST_PER_INFLOW * (1.0 - through);
    if gain > 1.0 { 1.0 + THRUST_GAIN_CAP * ((gain - 1.0) / THRUST_GAIN_CAP).tanh() } else { gain }
}

/// 0 outside the band, 1 at the peak.
fn vrs_band(x: f64) -> f64 {
    if x <= VRS_X_LO || x >= VRS_X_HI {
        0.0
    } else if x <= VRS_X_PEAK {
        smooth01((x - VRS_X_LO) / (VRS_X_PEAK - VRS_X_LO))
    } else {
        smooth01((VRS_X_HI - x) / (VRS_X_HI - VRS_X_PEAK))
    }
}

/// Pure-vertical thrust ratio: the inflow answer, drawn down to (1 - deficit) at the band peak.
fn descent_thrust_ratio(x: f64) -> f64 {
    let b = vrs_band(x);
    (1.0 - b) * thrust_from_inflow(x) + b * (1.0 - VRS_MEAN_DEFICIT)
}

/// Pure-vertical shaft-power ratio: profile share plus induced power from the inflow alone (the breakdown loses
/// thrust, not torque), floored at a positive value.
fn descent_power_ratio(x: f64) -> f64 {
    let through = descent_inflow(x) - x;
    let p = PROFILE_SHARE + (1.0 - PROFILE_SHARE) * thrust_from_inflow(x) * through;
    p.max(DESCENT_POWER_FLOOR)
}

/// The standard inflow-angle criterion: VRS needs a near-vertical descent. The angle is that of the relative flow
/// above the disc plane, atan2(descent, in-plane speed).
fn vrs_forward_clear(descent_mps: f64, v_edge_mps: f64) -> f64 {
    if descent_mps <= 0.0 {
        return 0.0;
    }
    let deg = descent_mps.atan2(v_edge_mps.abs()).to_degrees();
    smooth01((deg - VRS_CLEAR_DEG_LO) / (VRS_CLEAR_DEG_HI - VRS_CLEAR_DEG_LO))
}

#[cfg(test)]
mod interference_tests {
    use super::BemtRatios;

    // SR1.5. Mapper-like prop: 0.119 m radius, 4430 rpm. Red-run was done on the Godot side (thrust factor skipped in powertrain.rs, tests/test_sr1_flight.gd); this unit test pins the factor.
    #[test]
    fn rear_thrust_loss_is_eleven_percent_in_the_published_window_and_zero_elsewhere() {
        let r = 0.119;
        let rpm = 4430.0;
        let mid = BemtRatios::interference_thrust_factor(0.11, 0.0, 11.5, rpm, r);
        assert!((mid - 0.89).abs() < 1e-9, "11.5 m/s factor {mid}");
        assert_eq!(BemtRatios::interference_thrust_factor(0.11, 0.0, 0.0, rpm, r), 1.0);
        assert_eq!(BemtRatios::interference_thrust_factor(0.11, 0.0, 25.0, rpm, r), 1.0);
        assert_eq!(BemtRatios::interference_thrust_factor(0.0, 0.0, 11.5, rpm, r), 1.0);
    }
}
