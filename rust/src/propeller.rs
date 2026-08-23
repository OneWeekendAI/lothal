//! Thrust and reaction torque from motor RPM (physics.md §4): T = k_t * omega^2,
//! Q = k_q * omega^2. Ported from src/sim/propeller_model.gd, golden cross-checked before
//! the GDScript was deleted.
//!
//! Since 2026-08-14 the model also knows about AIRSPEED — see the block comment above j_zero for
//! the sign convention, the two competing effects, and why the forward-flight terms enter as
//! ratios anchored at 1.0 rather than as replacement laws.
//!
//! k_q has no equivalent published-and-fit figure in v1, so it uses a documented
//! rule-of-thumb ratio to k_t. Only the sign of reaction torque is load-bearing; the
//! magnitude ratio can be replaced once torque-test tables are authored into the catalog.
//!
//! Every `#[func]` here is receiver-less, which gdext 0.5 registers as a GDScript STATIC
//! function — so GDScript calls `PropellerModel.fit_k_t(...)` etc. class-level, exactly as
//! the original `static func`s were called. (gdext 0.5 does NOT expose receiver-ful #[func]
//! statically, but receiver-less ones are the design's exact pattern.)

use godot::prelude::*;

/// The ratio is not a constant across prop sizes: Q = C_Q*rho*n^2*D^5 and
/// T = C_T*rho*n^2*D^4, so Q/T scales with diameter. Anchored at 0.02 for a 5" prop.
const K_Q_TO_K_T_RATIO_AT_5IN: f64 = 0.02;
const K_Q_REFERENCE_DIAMETER_M: f64 = 0.127; // 5 inches

/// Sea-level standard air. The SAME number as Build.AIR_DENSITY_KGM3, and tests/test_rust_constants.gd
/// pins them together — a rotor disc and an airframe's drag area must not be told two different
/// things about the air they are both moving through.
///
/// Since the air-density slice this is no longer "the density". It is the DEFAULT and the ORACLE's
/// value: every function below takes rho as a runtime parameter, because a builder in Bangalore
/// flies in 16% less air than this, and a non-positive or unsupplied rho falls back here. That
/// demotion changed what the pin can prove — inverting Glauert now recovers whatever the caller
/// passed in — so the pin was split, and this const is guarded by the half that calls the DEFAULT
/// path rather than by one that hands a value in. See tests/test_rust_constants.gd.
pub const AIR_DENSITY_KGM3: f64 = 1.225;

/// Guards every rho that enters the model. Zero or negative air is not a thin atmosphere, it is a
/// division by zero followed by NaN or a negative induced velocity propagating into thrust,
/// current and the flight-time countdown. GDScript clamps elevation and temperature to a physical
/// domain before it ever gets here (air_density.gd), so this is the second line rather than the
/// first — but a #[func] is callable from any GDScript, and one that returns NaN for an input it
/// could have refused is a landmine for whoever calls it next.
fn air_density_or_default(rho: f64) -> f64 {
    if rho > 0.0 { rho } else { AIR_DENSITY_KGM3 }
}

/// FIGURE OF MERIT, AND IT IS A GUESS. No source. There is no source: nobody publishes a figure of
/// merit for an FPV propeller, and the manufacturer tables the rest of this file is fitted from are
/// thrust and current at a stand, from which FM cannot be separated out.
///
/// 0.70 is the conventional band for a small rotor. It sets how much of the static shaft power is
/// PROFILE power — the power the blades cost to drag through the air making no thrust — via
/// P_profile = T*v_h*(1/FM - 1). That term is what stops the forward-flight power factor collapsing
/// to zero as the prop unloads.
///
/// It is a SOFT guess, which is the only reason it is tolerable: it enters power_factor() as a ratio
/// of two powers that both contain it, so 0.65 and 0.75 move the factor by a couple of percent
/// rather than moving the sign of the answer. Nothing here may quote an error bar (validation.md).
pub const FIGURE_OF_MERIT: f64 = 0.70;

/// Fixed-point iterations for Glauert's inflow equation. It converges geometrically and is seeded at
/// the hover answer, so this is generous rather than tuned; the count is fixed so the flight tick
/// costs the same every tick.
const INFLOW_ITERATIONS: i32 = 12;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct PropellerModel;

#[godot_api]
impl PropellerModel {
    /// k_t from a manufacturer's headline figure: max thrust at max RPM on the prop the
    /// figure was measured with.
    #[func]
    pub fn fit_k_t(max_thrust_g: f64, max_rpm: f64) -> f64 {
        let max_thrust_n = (max_thrust_g / 1000.0) * 9.81;
        let max_omega = Self::rpm_to_rad_s(max_rpm);
        max_thrust_n / (max_omega * max_omega)
    }

    #[func]
    pub fn fit_k_q(k_t: f64, diameter_m: f64) -> f64 {
        k_t * K_Q_TO_K_T_RATIO_AT_5IN * (diameter_m / K_Q_REFERENCE_DIAMETER_M)
    }

    #[func]
    pub fn rpm_to_rad_s(rpm: f64) -> f64 {
        rpm * std::f64::consts::TAU / 60.0
    }

    #[func]
    pub fn thrust_n(k_t: f64, rpm: f64) -> f64 {
        let omega = Self::rpm_to_rad_s(rpm);
        k_t * omega * omega
    }

    #[func]
    pub fn reaction_torque_n_m(k_q: f64, rpm: f64) -> f64 {
        let omega = Self::rpm_to_rad_s(rpm);
        k_q * omega * omega
    }

    // -----------------------------------------------------------------------
    // Forward flight. Everything below is a DIMENSIONLESS RATIO anchored at exactly 1.0 when the
    // aircraft is not moving, multiplying the static results above rather than replacing them.
    //
    // The shape is the design. k_t is FITTED from a real thrust row and the current law is fitted
    // from a real amp rating; a first-principles forward-flight law would throw that measurement
    // away and would move 496.0 g / 11.69:1 / 29.6% on day one. Anchored ratios cannot: at zero
    // airspeed the multiplier is literally 1, by a short circuit rather than by arithmetic that
    // happens to land there.
    //
    // TWO EFFECTS, OPPOSITE SIGNS, and a model with only the first is worse than no model:
    //   (a) axial inflow UNLOADS the rotor  -> thrust_factor, below 1
    //   (b) edgewise flow makes the rotor CHEAPER (translational lift) -> power_factor, below 1
    // Implement (a) alone and forward flight costs MORE current and predicts SHORTER flight times,
    // which is backwards. tests/test_forward_flight.gd fails loudly if (b) goes missing.
    //
    // SIGN CONVENTION, once, here: `v_axial_mps` is the aircraft's velocity along BODY +Y — the
    // rotor's own thrust axis. Climbing, or leaning into forward flight, makes it POSITIVE, and
    // positive is the direction that unloads the prop and adds to induced power. Descent is
    // negative and is out of domain; see power_factor().
    //
    // This model is CHARACTERISTIC, not predictive (validation.md). No published C_T(J) exists for
    // any FPV propeller — every thrust table in the catalog is a stand run at zero airspeed — so
    // nothing built on these functions may quote an error bar.
    // -----------------------------------------------------------------------

    /// The advance ratio at which a propeller stops making thrust, taken as its GEOMETRIC advance,
    /// pitch/diameter. Both figures are already in the catalog, so per the derived-not-typed rule
    /// in parts.md no `j_zero` field is added to propellers.json.
    ///
    /// A RULE OF THUMB, in the same voice as the deleted BLADE_COUNT_EXPONENT. Real props reach zero thrust
    /// somewhat BELOW their geometric advance — typically 0.8-0.9 of it — because the blade has a
    /// zero-lift angle and is not at its nominal pitch across the whole radius. Using the geometric
    /// figure therefore UNDER-predicts unloading: this model is optimistic in this term, and it is
    /// optimistic in the profile-power term too (see power_factor), so the two biases compound
    /// rather than cancel.
    #[func]
    pub fn j_zero(diameter_m: f64, pitch_m: f64) -> f64 {
        if diameter_m <= 0.0 {
            return 0.0;
        }
        pitch_m / diameter_m
    }

    /// J = V_axial / (n*D), the distance the aircraft advances per revolution against the distance
    /// the prop would screw itself forward through solid air.
    #[func]
    pub fn advance_ratio(rpm: f64, diameter_m: f64, v_axial_mps: f64) -> f64 {
        let rev_per_s = rpm / 60.0;
        if rev_per_s <= 0.0 || diameter_m <= 0.0 {
            return 0.0;
        }
        v_axial_mps / (rev_per_s * diameter_m)
    }

    /// EFFECT (a). The fraction of static thrust a prop still makes at this airspeed. C_T for a
    /// fixed-pitch prop is close to linear in J over the useful range, reaching zero at j_zero.
    ///
    /// Clamped to [0, 1] at both ends, and each end is load-bearing:
    /// - the FLOOR, because past j_zero a real prop makes NEGATIVE thrust and then windmills. That
    ///   regime is not modelled, and returning zero is this function declining to answer rather
    ///   than confidently pulling the aircraft backwards at speed.
    /// - the CEILING, because a descending prop loads up (J < 0 gives 1 - J/J0 > 1) and that is the
    ///   vortex-ring regime, where the linear fit has no standing. Static thrust stays the maximum.
    ///
    /// TAKES NO AIR DENSITY, DELIBERATELY. Everything else in this file gained a rho parameter and
    /// a reader who has just watched that happen will assume this one was missed. It was not, for
    /// two independent reasons. J = V/(nD) is pure kinematics — an airspeed, a rotation rate and a
    /// length, with no mass flow anywhere in it. And this is a RATIO anchored at 1.0 rather than a
    /// thrust: whatever density scales the static thrust scales the airspeed thrust identically,
    /// so rho appears in both halves and cancels exactly. Air reaches thrust through k_t, which is
    /// where the density belongs, and reaches power through power_factor above.
    #[func]
    pub fn thrust_factor(rpm: f64, diameter_m: f64, pitch_m: f64, v_axial_mps: f64) -> f64 {
        if v_axial_mps == 0.0 {
            return 1.0;
        }
        let j0 = Self::j_zero(diameter_m, pitch_m);
        if j0 <= 0.0 {
            return 1.0;
        }
        let j = Self::advance_ratio(rpm, diameter_m, v_axial_mps);
        (1.0 - j / j0).clamp(0.0, 1.0)
    }

    /// Thrust with the airspeed term folded in. `thrust_n` remains the static form under its own
    /// name, and the callers that legitimately want static behaviour — ThrustValidation's held-out
    /// points, Build.max_total_thrust_n() — keep calling it and keep getting it.
    #[func]
    pub fn thrust_n_in_flight(
        k_t: f64,
        rpm: f64,
        diameter_m: f64,
        pitch_m: f64,
        v_axial_mps: f64,
    ) -> f64 {
        Self::thrust_n(k_t, rpm)
            * Self::thrust_factor(rpm, diameter_m, pitch_m, v_axial_mps)
    }

    /// Glauert's forward-flight inflow, by fixed point seeded at the hover answer:
    ///
    ///     v_i = v_h^2 / sqrt( V_edge^2 + (V_axial + v_i)^2 ),   v_h = sqrt( T / (2*rho*A) )
    ///
    /// At V = 0 the fixed point IS v_h and the seed is already there, so hover is reproduced
    /// exactly. As speed rises v_i falls, which is effect (b): the disc is handed more mass flow
    /// than it has to accelerate itself, so the same thrust costs less induced power.
    #[func]
    pub fn induced_velocity_mps(
        thrust_n: f64,
        diameter_m: f64,
        v_axial_mps: f64,
        v_edge_mps: f64,
        air_density_kgm3: f64,
    ) -> f64 {
        let area = Self::disc_area_m2(diameter_m);
        if thrust_n <= 0.0 || area <= 0.0 {
            return 0.0;
        }
        let rho = air_density_or_default(air_density_kgm3);
        let v_h_squared = thrust_n / (2.0 * rho * area);
        let mut v_i = v_h_squared.sqrt();
        for _ in 0..INFLOW_ITERATIONS {
            let axial = v_axial_mps + v_i;
            let magnitude = (v_edge_mps * v_edge_mps + axial * axial).sqrt();
            if magnitude <= 0.0 {
                break;
            }
            v_i = v_h_squared / magnitude;
        }
        v_i
    }

    /// EFFECT (b), and the whole reason forward flight gets CHEAPER before it gets dearer.
    ///
    /// The ratio of shaft power at this airspeed to shaft power at the same RPM standing still:
    ///
    ///     P = T*(V_axial + v_i) + P_profile
    ///     P_profile = T_static * v_h_static * (1/FM - 1)      anchored once, at the static point
    ///
    /// The first term is induced power plus the power of driving the rotor along its own axis —
    /// which is where parasite drag enters, since the lean that balances drag is what puts the
    /// freestream on the axis in the first place. The second is the blades' own drag; it is held
    /// CONSTANT with airspeed, deliberately. Real profile power rises with edgewise flow, but the
    /// classical correction needs a blade solidity figure no manufacturer publishes, and inventing
    /// one would make the model look more rigorous while being strictly less honest. The omission
    /// biases this optimistic at high speed, in the same direction as j_zero's.
    ///
    /// DESCENT IS OUT OF DOMAIN — ANY descent — and says so rather than guessing. Two regimes sit
    /// under a negative axial inflow and this model has neither: the vortex-ring state, where
    /// Glauert's forward-flight branch is simply invalid and where a quad descending vertically at
    /// a few metres per second actually is; and beyond it the windmill brake, where the rotor
    /// extracts energy from the air. So a negative axial inflow returns the static answer.
    ///
    /// The first version of this guard admitted descents past the windmill-brake threshold, on the
    /// grounds that momentum theory is valid again out there. It is — and the term it then produces
    /// is `T*(V_axial + v_i)` with V_axial large and negative, which is NEGATIVE shaft power. That
    /// is not a rounding problem, it is the physically correct statement that a windmilling rotor
    /// gives energy back, and this powertrain has no way to receive it: the factor went negative,
    /// the current went negative, and a quad in a 30 m/s descent CHARGED ITS OWN PACK. Regenerative
    /// braking is out of scope (the design doc says so); a guard that lets the regime in anyway is
    /// how "out of scope" turns into a wrong number instead of no number.
    #[func]
    pub fn power_factor(
        k_t: f64,
        rpm: f64,
        diameter_m: f64,
        pitch_m: f64,
        v_axial_mps: f64,
        v_edge_mps: f64,
        air_density_kgm3: f64,
    ) -> f64 {
        if (v_axial_mps == 0.0 && v_edge_mps == 0.0) || v_axial_mps < 0.0 {
            return 1.0;
        }
        let rho = air_density_or_default(air_density_kgm3);
        let area = Self::disc_area_m2(diameter_m);
        let thrust_static = Self::thrust_n(k_t, rpm);
        if area <= 0.0 || thrust_static <= 0.0 {
            return 1.0;
        }

        let v_h_static = (thrust_static / (2.0 * rho * area)).sqrt();
        let power_profile = thrust_static * v_h_static * (1.0 / FIGURE_OF_MERIT - 1.0);
        let power_static = thrust_static * v_h_static + power_profile;
        if power_static <= 0.0 {
            return 1.0;
        }

        let thrust = thrust_static
            * Self::thrust_factor(rpm, diameter_m, pitch_m, v_axial_mps);
        let v_i = Self::induced_velocity_mps(thrust, diameter_m, v_axial_mps, v_edge_mps, rho);
        let power = thrust * (v_axial_mps + v_i) + power_profile;

        power / power_static
    }

    #[func]
    pub fn disc_area_m2(diameter_m: f64) -> f64 {
        if diameter_m <= 0.0 {
            return 0.0;
        }
        let radius = diameter_m * 0.5;
        std::f64::consts::PI * radius * radius
    }
}
