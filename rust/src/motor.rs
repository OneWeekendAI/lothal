//! RPM response of a single motor. Pure and engine-independent (physics.md §3).
//! Ported from src/sim/motor_model.gd — the GDScript is the source of truth and was
//! golden cross-checked against this file before it was deleted.
//!
//! max_RPM = KV * live pack voltage — the same motor spins much faster on 6S than 4S,
//! which is most of why voltage choice feels dramatic to fly.
//!
//! P7 (propulsion.md §3.4): the first-order lag time constant is no longer a global
//! 0.03 s. Every MotorModel now carries its own `tau_s`, computed from the mechanical
//! sum of J_rotor + N_b · J_blade divided by the sum of the motor's electrical
//! back-EMF slope and the propeller's aerodynamic damping slope at the operating point.
//! A 0802 whoop with a 0.5 g prop and a 2808 cinelifter with a 12 g prop can no longer
//! share a spin-up. See `motor_spin_up.gd` for the derivation.

use godot::prelude::*;

use crate::battery::BatteryModel;

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
    /// First-order lag time constant, seconds. Per-motor since P7. Caller computes it from
    /// §3.4's formula; if the caller cannot (a stub build, a probe), the fallback is 0.03 s
    /// which matches the constant this replaced — a deliberate identity so a call site that
    /// forgot to pass tau_s produces the same numbers the old code did, not silently wrong ones.
    #[var]
    pub tau_s: f64,
    /// Motor Designer M4. The DC model's winding resistance (ohm); 0 means "legacy": the drone
    /// keeps the quadratic rated-amps current law and rpm = throttle * KV * V. A motor whose
    /// record says `current_model: "dc"` gets Rm, Io, the voltage Io is stated at and the prop's
    /// k_q handed in through `set_dc`, and then target rpm and current both come from the same
    /// operating-point solve the designer's bench uses, so there is one model.
    #[var]
    pub dc_rm_ohm: f64,
    #[var]
    pub dc_io_a: f64,
    #[var]
    pub dc_io_v: f64,
    #[var]
    pub dc_k_q: f64,
    /// How many identical motors one powertrain thruster stands for: 1 for every plan position
    /// except a coaxial pair lumped into one thruster (2). Scales the CURRENT only -- each motor
    /// in the pair still turns the rpm one motor solves to.
    pub dc_count: f64,
}

#[godot_api]
impl MotorModel {
    /// Legacy factory kept as an EXPLICIT bench convenience: probes, custom-motor previews
    /// and tests that only want a `step()` don't need to build a whole powertrain to derive
    /// tau. Everything on the flight path uses `create_with_tau` and hands in the value
    /// `MotorSpinUp` computed at hover.
    #[func]
    pub fn create(kv: f64, max_throttle: f64) -> Gd<Self> {
        Self::create_with_tau(kv, max_throttle, DEFAULT_TAU_S)
    }

    /// The flight-path factory: caller passes the tau_s it computed from motor + prop
    /// geometry at the linearisation point. `Build.motor_model()` and the ESC bench pass
    /// their own; both route through `Build.spin_up()`, which calls `MotorSpinUp.compute()`.
    #[func]
    pub fn create_with_tau(kv: f64, max_throttle: f64, tau_s: f64) -> Gd<Self> {
        Gd::from_object(Self {
            kv,
            max_throttle: max_throttle.clamp(0.0, 1.0),
            tau_s: if tau_s > 0.0 { tau_s } else { DEFAULT_TAU_S },
            dc_rm_ohm: 0.0,
            dc_io_a: 0.0,
            dc_io_v: 0.0,
            dc_k_q: 0.0,
            dc_count: 1.0,
        })
    }

    /// Switches this motor to the DC (Kv, Rm, Io) model for the drone. `rm_ohm <= 0` switches it
    /// back to the legacy law.
    #[func]
    pub fn set_dc(&mut self, rm_ohm: f64, io_a: f64, io_voltage_v: f64, k_q: f64) {
        self.dc_rm_ohm = rm_ohm;
        self.dc_io_a = io_a;
        self.dc_io_v = io_voltage_v;
        self.dc_k_q = k_q;
    }

    /// A thruster that stands for `n` identical motors (a lumped coaxial pair) draws `n` times one
    /// motor's current at the same rpm.
    #[func]
    pub fn set_dc_count(&mut self, n: f64) {
        self.dc_count = n.max(1.0);
    }

    #[func]
    pub fn uses_dc(&self) -> bool {
        self.dc_rm_ohm > 0.0 && self.dc_k_q > 0.0
    }

    /// Steady rpm for a throttle command at the pack's live terminal voltage. Legacy: the
    /// command (capped at max_throttle) times KV times voltage. DC: the throttle scales the
    /// applied voltage and the winding drops I*Rm of it, so the same command spins slower under
    /// load, exactly the operating-point solve.
    #[func]
    pub fn target_rpm(&self, throttle_cmd: f64, voltage_v: f64) -> f64 {
        let t = throttle_cmd.clamp(0.0, self.max_throttle);
        if self.uses_dc() {
            solve_point(t * voltage_v, self.kv, self.dc_rm_ohm, self.dc_io_a, self.dc_io_v,
                self.dc_k_q).rpm
        } else {
            t * self.max_rpm(voltage_v)
        }
    }

    /// Current of ONE motor at `rpm` under the DC model: the no-load current at that rpm plus the
    /// prop's torque over Kt. Only meaningful when `uses_dc`.
    #[func]
    pub fn dc_current_at_rpm(&self, rpm: f64) -> f64 {
        self.dc_count * dc_current_impl(rpm, self.kv, self.dc_io_a, self.dc_io_v, self.dc_k_q)
    }

    /// PACK-side current of this thruster at `rpm` on a supply of `v_supply` volts (duty times the
    /// winding current; see `dc_pack_current_impl`). What a battery drains by.
    #[func]
    pub fn dc_pack_current_at_rpm(&self, rpm: f64, v_supply: f64) -> f64 {
        self.dc_count * dc_pack_current_impl(rpm, v_supply, self.kv, self.dc_rm_ohm, self.dc_io_a,
            self.dc_io_v, self.dc_k_q)
    }

    #[func]
    pub fn max_rpm(&self, voltage_v: f64) -> f64 {
        self.kv * voltage_v
    }

    /// Advances current RPM one dt toward the throttle-commanded target, via first-order lag.
    #[func]
    pub fn step(&self, current_rpm: f64, throttle_cmd: f64, voltage_v: f64, dt: f64) -> f64 {
        let target = self.target_rpm(throttle_cmd, voltage_v);
        let alpha = 1.0 - (-dt / self.tau_s).exp();
        current_rpm + (target - current_rpm) * alpha
    }

    // ---------------------------------------------------------------------------------------
    // Motor Designer M1: the three-constant DC model (Kv, Rm, Io). Same class, no second model;
    // `create`/`step` above are untouched and still the flight path. Everything below is an
    // ideal / model figure: a function of the configuration, the load and the applied voltage.
    // ---------------------------------------------------------------------------------------

    /// Torque constant Kt = 60 / (2 pi Kv), N.m per amp.
    #[func]
    pub fn kt(kv: f64) -> f64 {
        kt_impl(kv)
    }

    /// Winding current I = (V - rpm/Kv) / Rm. Negative when the shaft is driven faster than the
    /// back-EMF allows (regeneration); callers that cannot regenerate clamp it.
    #[func]
    pub fn current_a(voltage_v: f64, rpm: f64, kv: f64, rm_ohm: f64) -> f64 {
        current_impl(voltage_v, rpm, kv, rm_ohm)
    }

    /// No-load current at a given rpm. Io is stated at the rpm the motor reaches unloaded on
    /// `io_voltage_v` (Kv * io_voltage_v) and scales linearly with rpm (iron and friction loss).
    #[func]
    pub fn io_at_rpm(io_a: f64, io_voltage_v: f64, kv: f64, rpm: f64) -> f64 {
        io_impl(io_a, io_voltage_v, kv, rpm)
    }

    /// Shaft torque (I - Io) * Kt, N.m.
    #[func]
    pub fn shaft_torque_nm(current_a: f64, io_a: f64, kv: f64) -> f64 {
        (current_a - io_a) * kt_impl(kv)
    }

    /// The operating point of a motor driving a prop whose load torque is k_q * omega^2 (the
    /// same law `PropellerModel.reaction_torque_n_m` uses, so pass its k_q). Voltage is the
    /// voltage applied after throttle. Returns rpm, current_a, torque_nm, shaft_w, electrical_w,
    /// loss_w, efficiency (0 at standstill) and io_a (the no-load current at that rpm).
    #[func]
    pub fn operating_point(voltage_v: f64, kv: f64, rm_ohm: f64, io_a: f64, io_voltage_v: f64,
                           k_q: f64) -> VarDictionary {
        let p = solve_point(voltage_v, kv, rm_ohm, io_a, io_voltage_v, k_q);
        let mut d = VarDictionary::new();
        d.set("rpm", p.rpm);
        d.set("current_a", p.current_a);
        d.set("torque_nm", p.torque_nm);
        d.set("shaft_w", p.shaft_w);
        d.set("electrical_w", p.electrical_w);
        d.set("loss_w", p.electrical_w - p.shaft_w);
        d.set("efficiency", p.efficiency);
        d.set("io_a", p.io_a);
        d
    }

    /// Operating point on a real pack (the pack designer's `BatteryModel`): open-circuit voltage
    /// at its current state of charge behind its internal resistance, so the solved current
    /// sags the terminal voltage. `throttle` is the duty applied to the pack (no ESC model: the
    /// motor is driven straight from the pack, so duty just scales both voltage and the
    /// series resistance seen by the motor). Adds to operating_point: terminal_v, pack_current_a
    /// (= throttle * motor current), sag_v, pack_loss_w (I_pack^2 R) and voc_v.
    #[func]
    pub fn operating_point_on_pack(pack: Gd<BatteryModel>, throttle: f64, kv: f64, rm_ohm: f64,
                                   io_a: f64, io_voltage_v: f64, k_q: f64) -> VarDictionary {
        let (voc, r_pack) = {
            let b = pack.bind();
            (b.resting_voltage_v(), b.internal_r_ohm)
        };
        let t = throttle.clamp(0.0, 1.0);
        let p = solve_point_series(t * voc, t * t * r_pack, kv, rm_ohm, io_a, io_voltage_v, k_q);
        // Duty t on a source voc/r_pack: motor sees t*voc behind t^2*r_pack seen from the
        // motor side; the pack itself carries t * motor current.
        let i_pack = t * p.current_a;
        let mut d = VarDictionary::new();
        d.set("rpm", p.rpm);
        d.set("current_a", p.current_a);
        d.set("torque_nm", p.torque_nm);
        d.set("shaft_w", p.shaft_w);
        d.set("electrical_w", p.electrical_w);
        d.set("loss_w", p.electrical_w - p.shaft_w);
        d.set("efficiency", p.efficiency);
        d.set("io_a", p.io_a);
        d.set("voc_v", voc);
        d.set("pack_current_a", i_pack);
        d.set("sag_v", i_pack * r_pack);
        d.set("terminal_v", voc - i_pack * r_pack);
        d.set("pack_loss_w", i_pack * i_pack * r_pack);
        d
    }

    /// Heat the winding and stator must shed, W: electrical in minus shaft out, which is
    /// I^2 Rm plus the iron/friction loss Io(rpm) * back-EMF.
    #[func]
    pub fn loss_w(voltage_v: f64, kv: f64, rm_ohm: f64, io_a: f64, io_voltage_v: f64, k_q: f64) -> f64 {
        let p = solve_point(voltage_v, kv, rm_ohm, io_a, io_voltage_v, k_q);
        p.electrical_w - p.shaft_w
    }

    /// Heat capacity of the winding + stator, J/K, from copper and stator-iron masses (grams).
    #[func]
    pub fn thermal_mass_j_per_k(copper_g: f64, stator_g: f64) -> f64 {
        (copper_g.max(0.0) * CU_J_PER_G_K) + (stator_g.max(0.0) * FE_J_PER_G_K)
    }

    /// Convective conductance to air, W/K. Surface scales as mass^(2/3); the film coefficient
    /// rises with airflow (prop wash). est.: coefficients are class-typical, not measured.
    #[func]
    pub fn cooling_w_per_k(motor_mass_g: f64, airflow_mps: f64) -> f64 {
        let area_m2 = AREA_M2_PER_G23 * motor_mass_g.max(0.0).powf(2.0 / 3.0);
        area_m2 * (H_STILL_W_M2K + H_FLOW_W_M2K_PER_MPS * airflow_mps.max(0.0))
    }

    /// Heat capacity of the bell (rotor shell + magnets), J/K, from its mass in grams.
    #[func]
    pub fn bell_thermal_mass_j_per_k(bell_g: f64) -> f64 {
        bell_g.max(0.0) * BELL_J_PER_G_K
    }

    /// Conductance from the stator and winding to the bell, W/K (airgap, bearings, shaft). The
    /// path scales with the motor's surface, mass^(2/3). est.: class-typical, not measured.
    #[func]
    pub fn bell_conduction_w_per_k(motor_mass_g: f64) -> f64 {
        BELL_COND_W_PER_K_PER_G23 * motor_mass_g.max(0.0).powf(2.0 / 3.0)
    }

    /// Conductance from the bell's outer surface to the air, W/K, at `rpm`: a rotating cylinder
    /// in free air, Nu_D = 0.133 Re_w^(2/3) Pr^(1/3) with Re_w = w D^2 / nu (Etemad 1955; Kays &
    /// Crawford), on top of a still-air natural convection + radiation film. Surface scales as
    /// mass^(2/3) and the bell diameter as mass^(1/3). Prop wash over the bell is not counted.
    #[func]
    pub fn air_conductance_w_per_k(motor_mass_g: f64, rpm: f64) -> f64 {
        let m = motor_mass_g.max(0.0);
        if m <= 0.0 { return 0.0; }
        let area_m2 = AREA_M2_PER_G23 * m.powf(2.0 / 3.0);
        let d_m = 2.0 * BELL_RADIUS_M_PER_G13 * m.powf(1.0 / 3.0);
        let w = rpm.abs() * std::f64::consts::TAU / 60.0;
        let re = w * d_m * d_m / AIR_NU_M2_S;
        let nu = ROT_CYL_COEFF * re.powf(2.0 / 3.0) * AIR_PR.powf(1.0 / 3.0);
        area_m2 * (H_NATURAL_W_M2K + nu * AIR_K_W_MK / d_m)
    }

    /// One step of the two-lump model: the stator + winding (x = temperature, C) takes the
    /// `loss_w`; it conducts to the bell (y), which sheds to the air. Backward Euler in small
    /// sub-steps, so it is stable at any `dt` and never overshoots the steady state.
    /// Returns (winding C, bell C).
    #[func]
    pub fn bell_temp_step_c(temps: Vector2, loss_w: f64, c_stator: f64, c_bell: f64, g_cond: f64, g_air: f64, dt: f64) -> Vector2 {
        let (a, b) = two_lump_step(temps.x as f64, temps.y as f64, loss_w, c_stator, c_bell, g_cond, g_air, dt);
        Vector2::new(a as f32, b as f32)
    }

    /// One step of the lumped winding temperature (C). Exact for a constant loss over `dt`,
    /// so it is stable at any step size and never overshoots the steady state.
    #[func]
    pub fn temp_step_c(temp_c: f64, loss_w: f64, thermal_mass_j_per_k: f64, cooling_w_per_k: f64, dt: f64) -> f64 {
        temp_step_impl(temp_c, loss_w, thermal_mass_j_per_k, cooling_w_per_k, dt)
    }

    /// Steady-state winding temperature for a constant loss.
    #[func]
    pub fn steady_temp_c(loss_w: f64, cooling_w_per_k: f64) -> f64 {
        if cooling_w_per_k <= 0.0 { return f64::INFINITY; }
        AMBIENT_C + loss_w / cooling_w_per_k
    }
}

/// The value the deleted `SPIN_UP_TAU_S` constant carried. Kept here — and ONLY here — as the
/// fallback for `create()`, so a bench probe that does not want to derive tau produces the same
/// numbers the pre-P7 code did instead of a silent zero.
const DEFAULT_TAU_S: f64 = 0.03;

/// Ambient for the winding model, C.
pub const AMBIENT_C: f64 = 25.0;
// Thermal constants, each from a source (refit 2026-11-04, after the prop k_q fix).
// Specific heats, J/(g.K): Incropera, Fundamentals of Heat and Mass Transfer, Table A.1 (300 K):
// copper 385 J/(kg.K), pure iron 447 J/(kg.K) (stator laminations are 3% Si steel, within ~3%).
const CU_J_PER_G_K: f64 = 0.385;
const FE_J_PER_G_K: f64 = 0.447;
// Outer surface of a bell motor, m^2 per g^(2/3): a 31.8 g 2207 has a 28.6 mm x 17 mm bell, so the
// cylinder (1.5e-3 m^2) plus the top disc (0.64e-3 m^2) is 2.1e-3 m^2 = 2.07e-4 * 31.8^(2/3).
const AREA_M2_PER_G23: f64 = 2.07e-4;
// One-lump cooling (cooling_w_per_k, kept for the older probes, not the bench): film coefficient
// W/(m^2.K), still air plus a term per m/s of prop wash.
const H_STILL_W_M2K: f64 = 25.0;
const H_FLOW_W_M2K_PER_MPS: f64 = 8.0;
// Bell heat capacity J/(g.K): mass-weighted mix of a 7075 aluminium shell (960 J/kg.K, 45 %), NdFeB
// magnets (~500, 35 %) and the steel shaft (~470, 20 %): 0.45*0.96 + 0.35*0.50 + 0.20*0.47 = 0.70.
// Densities and cp: Incropera Table A.1; magnet grade cp from supplier data sheets (~420-500).
const BELL_J_PER_G_K: f64 = 0.70;
// Stator-to-bell conduction, W/K per g^(2/3). Two parallel paths, both computed for a 2207
// (31.8 g, g^(2/3) = 10.0): (1) the 0.4 mm airgap, Couette/Taylor-Couette conduction through air,
// G = Nu k A / gap with k = 0.0263 W/(m.K), A = pi * 22 mm * 7 mm = 4.8e-4 m^2 and, at the bell
// speeds here (Taylor number ~140), Nu ~ 1.3 from Becker & Kaye 1962 (J. Heat Transfer 84:97),
// Nu = 0.409 Ta^0.241 for 100 < Ta < 1e7: G = 0.043 W/K. (2) The solid 4 mm steel shaft, k = 52,
// 12 mm long, ignoring the bearings' own contact resistance (so an upper bound): 0.055 W/K.
// Total 0.098 W/K / 10.0 = 0.0098, rounded to 0.01. Far lower than the 0.6 this replaced.
const BELL_COND_W_PER_K_PER_G23: f64 = 0.01;
// Bell radius per g^(1/3), m (a 31.8 g 2207 bell is 14.3 mm in radius).
const BELL_RADIUS_M_PER_G13: f64 = 4.5e-3;
// Natural convection + radiation from an anodised bell in still air, W/(m^2.K): free convection
// from a 17 mm cylinder at dT ~ 40 K is ~5 (Incropera ch. 9), radiation 4 eps sigma T^3 with
// eps ~ 0.8 is ~6; rounded to 10.
const H_NATURAL_W_M2K: f64 = 10.0;
// Air at 300 K, Incropera Table A.4: kinematic viscosity 15.89e-6 m^2/s, k 0.0263 W/(m.K), Pr 0.707.
const AIR_NU_M2_S: f64 = 15.89e-6;
const AIR_K_W_MK: f64 = 0.0263;
const AIR_PR: f64 = 0.707;
// Rotating cylinder in free air (Etemad 1955; Kays & Crawford; Boglietti et al. 2009 review of
// electrical-machine thermal analysis): Nu_D = 0.133 Re_w^(2/3) Pr^(1/3), Re_w = w D^2 / nu,
// valid to Re_w ~ 4.3e5 (a 2207 flat out is ~1.4e5).
const ROT_CYL_COEFF: f64 = 0.133;

fn kt_impl(kv: f64) -> f64 {
    if kv <= 0.0 { return 0.0; }
    60.0 / (std::f64::consts::TAU * kv)
}

fn current_impl(v: f64, rpm: f64, kv: f64, rm: f64) -> f64 {
    if kv <= 0.0 || rm <= 0.0 { return 0.0; }
    (v - rpm / kv) / rm
}

fn io_impl(io: f64, io_v: f64, kv: f64, rpm: f64) -> f64 {
    let ref_rpm = kv * io_v;
    if ref_rpm <= 0.0 { return io; }
    io * (rpm / ref_rpm)
}

fn temp_step_impl(t: f64, loss: f64, c: f64, h: f64, dt: f64) -> f64 {
    if c <= 0.0 || h <= 0.0 { return t + if c > 0.0 { loss * dt / c } else { 0.0 }; }
    let t_inf = AMBIENT_C + loss / h;
    t_inf + (t - t_inf) * (-dt * h / c).exp()
}

#[allow(clippy::too_many_arguments)]
fn two_lump_step(mut tw: f64, mut tb: f64, loss: f64, c1: f64, c2: f64, g: f64, ga: f64, dt: f64) -> (f64, f64) {
    if c1 <= 0.0 || c2 <= 0.0 { return (tw, tb); }
    let n = (dt / 0.02).ceil().max(1.0) as usize;
    let h = dt / n as f64;
    for _ in 0..n {
        // (c1/h + g) tw' - g tb' = c1/h tw + loss ;  -g tw' + (c2/h + g + ga) tb' = c2/h tb + ga ambient
        let (a11, a12, b1) = (c1 / h + g, -g, c1 / h * tw + loss);
        let (a21, a22, b2) = (-g, c2 / h + g + ga, c2 / h * tb + ga * AMBIENT_C);
        let det = a11 * a22 - a12 * a21;
        tw = (b1 * a22 - a12 * b2) / det;
        tb = (a11 * b2 - a21 * b1) / det;
    }
    (tw, tb)
}

/// Current of one motor at `rpm` driving a prop of torque k_q * omega^2: Io(rpm) + torque / Kt.
pub fn dc_current_impl(rpm: f64, kv: f64, io: f64, io_v: f64, k_q: f64) -> f64 {
    let w = rpm * std::f64::consts::TAU / 60.0;
    io_impl(io, io_v, kv, rpm) + k_q * w * w / kt_impl(kv).max(1e-12)
}

/// PACK-side current of one motor at `rpm` fed from a supply of `v_supply` volts through an ideal
/// ESC. The ESC chops the supply at duty d = V_motor / V_supply, where V_motor = rpm/Kv + I*Rm is
/// what the winding needs, so the supply sees d * I (power in = power out). Without this a
/// motor at 30% duty charged the pack its full winding current, three times what it takes.
pub fn dc_pack_current_impl(rpm: f64, v_supply: f64, kv: f64, rm: f64, io: f64, io_v: f64,
                            k_q: f64) -> f64 {
    let i = dc_current_impl(rpm, kv, io, io_v, k_q);
    if v_supply <= 0.0 || kv <= 0.0 { return i; }
    let v_motor = rpm / kv + i * rm.max(0.0);
    i * (v_motor / v_supply).clamp(0.0, 1.0)
}

/// Pack current and rpm per motor for `n` identical DC motors at duty `t` on a pack of open-circuit
/// `rest_v` behind `r_pack`. The pack carries the motors' summed current (no ESC model, as in the
/// legacy law), so terminal V = rest_v - I_total*r_pack. Demand falls as amps rise, so one root,
/// found by bisection (the fixed-point iteration oscillates on a high-resistance pack).
pub fn dc_pack_state(t: f64, rest_v: f64, r_pack: f64, n: f64, kv: f64, rm: f64, io: f64,
                     io_v: f64, k_q: f64) -> (f64, f64) {
    if t <= 0.0 || rest_v <= 0.0 { return (0.0, 0.0); }
    let at = |amps: f64| solve_point(t * (rest_v - amps * r_pack).max(0.0), kv, rm, io, io_v, k_q);
    if r_pack <= 0.0 {
        let p = at(0.0);
        return (n * t * p.current_a, p.rpm);
    }
    // The winding sees t * V_terminal, so the PACK carries t times the winding current (an ideal
    // ESC conserves power); summing winding currents is the duty-cycle error that tripled hover draw.
    let (mut lo, mut hi) = (0.0, rest_v / r_pack);
    for _ in 0..60 {
        let mid = 0.5 * (lo + hi);
        if n * t * at(mid).current_a > mid { lo = mid } else { hi = mid }
    }
    let amps = 0.5 * (lo + hi);
    (amps, at(amps).rpm)
}

pub struct Point { pub rpm: f64, pub current_a: f64, pub torque_nm: f64, pub shaft_w: f64,
                   pub electrical_w: f64, pub efficiency: f64, pub io_a: f64 }

/// Bisection on rpm in [0, Kv*V]: motor torque falls monotonically with rpm and load torque
/// k_q*omega^2 rises, so there is exactly one crossing.
pub fn solve_point(v: f64, kv: f64, rm: f64, io: f64, io_v: f64, k_q: f64) -> Point {
    solve_point_series(v, 0.0, kv, rm, io, io_v, k_q)
}

/// The same solve with a source of open-circuit voltage `v` behind a series resistance `r_s`
/// (pack internal resistance times duty). The terminal voltage is v - I*r_s, so a hard load
/// sags it; `electrical_w` is power at the motor terminals.
pub fn solve_point_series(v: f64, r_s: f64, kv: f64, rm: f64, io: f64, io_v: f64, k_q: f64) -> Point {
    let zero = Point { rpm: 0.0, current_a: 0.0, torque_nm: 0.0, shaft_w: 0.0, electrical_w: 0.0, efficiency: 0.0, io_a: 0.0 };
    if v <= 0.0 || kv <= 0.0 || rm <= 0.0 { return zero; }
    let kt = kt_impl(kv);
    // Closed form. The balance (i - Io(rpm)) * Kt = k_q * w^2 with i = (v - rpm/Kv) / R and Io
    // linear in rpm (or constant when io_v is unset) is a quadratic in rpm:
    //   a rpm^2 + b rpm - c = 0,  a = k_q (2pi/60)^2,  b = Kt (1/(Kv R) + io/(Kv io_v)),
    //   c = Kt (v/R - io_const).
    // Its one non-negative root is the crossing the 80-step bisection on [0, Kv*v] used to find.
    // Since 2026-11-03 every motor is on this law, and the bisection nested inside the pack-sag
    // bisection (60 x 80 solves per throttle) made hover and peak-thrust 17x slower and pushed the
    // full suite past its watchdog. The root form 2c / (b + sqrt(b^2 + 4ac)) has no cancellation.
    let r = rm + r_s;
    let ref_rpm = kv * io_v;
    let (io_slope, io_const) = if ref_rpm > 0.0 { (io / ref_rpm, 0.0) } else { (0.0, io) };
    let rad = std::f64::consts::TAU / 60.0;
    let a = k_q.max(0.0) * rad * rad;
    let b = kt * (1.0 / (kv * r) + io_slope);
    let c = kt * (v / r - io_const);
    let rpm = if c <= 0.0 {
        0.0
    } else {
        (2.0 * c / (b + (b * b + 4.0 * a * c).sqrt())).min(kv * v)
    };
    let i = current_impl(v, rpm, kv, rm + r_s);
    let io_now = io_impl(io, io_v, kv, rpm);
    let torque = (i - io_now) * kt;
    let shaft = torque * rpm * std::f64::consts::TAU / 60.0;
    let elec = (v - i * r_s) * i;
    Point { rpm, current_a: i, torque_nm: torque, shaft_w: shaft, electrical_w: elec,
            efficiency: if elec > 1e-9 { (shaft / elec).clamp(0.0, 1.0) } else { 0.0 }, io_a: io_now }
}

#[cfg(test)]
mod tests {
    use super::*;
    // 2207 1960KV-ish on 6S: Rm 0.065 ohm, Io 1.2 A at 24 V. Prop k_q from a 5in load.
    const KV: f64 = 1960.0; const RM: f64 = 0.065; const IO: f64 = 1.2; const IOV: f64 = 24.0;
    const KQ: f64 = 4.0e-8; // N.m per (rad/s)^2

    #[test]
    fn kt_is_60_over_two_pi_kv() {
        assert!((kt_impl(1000.0) - 60.0 / (std::f64::consts::TAU * 1000.0)).abs() < 1e-12);
        assert!((kt_impl(2000.0) * 2.0 - kt_impl(1000.0)).abs() < 1e-12);
    }

    #[test]
    fn current_is_zero_at_back_emf_and_ohmic_at_stall() {
        assert!(current_impl(24.0, 24.0 * KV, KV, RM).abs() < 1e-9);
        assert!((current_impl(24.0, 0.0, KV, RM) - 24.0 / RM).abs() < 1e-9);
    }

    #[test]
    fn io_hits_its_stated_value_at_the_stated_voltage() {
        assert!((io_impl(IO, IOV, KV, KV * IOV) - IO).abs() < 1e-12);
        assert!((io_impl(IO, IOV, KV, 0.5 * KV * IOV) - 0.5 * IO).abs() < 1e-12);
    }

    #[test]
    fn operating_point_balances_motor_and_load_torque() {
        let p = solve_point(24.0, KV, RM, IO, IOV, KQ);
        let w = p.rpm * std::f64::consts::TAU / 60.0;
        assert!((p.torque_nm - KQ * w * w).abs() < 1e-9, "torque {} vs load {}", p.torque_nm, KQ * w * w);
        assert!(p.rpm > 0.0 && p.rpm < KV * 24.0);
    }

    #[test]
    fn energy_balance_and_efficiency() {
        let p = solve_point(24.0, KV, RM, IO, IOV, KQ);
        let loss = p.electrical_w - p.shaft_w;
        let expect = p.current_a * p.current_a * RM + p.io_a * (24.0 - p.current_a * RM);
        assert!((loss - expect).abs() < 1e-6, "loss {loss} vs I2R+iron {expect}");
        assert!((p.efficiency - p.shaft_w / p.electrical_w).abs() < 1e-12);
        assert!(p.efficiency > 0.5 && p.efficiency < 1.0);
    }

    #[test]
    fn higher_resistance_pack_gives_lower_rpm_and_current() {
        let low = solve_point_series(24.0, 0.01, KV, RM, IO, IOV, KQ);
        let high = solve_point_series(24.0, 0.08, KV, RM, IO, IOV, KQ);
        assert!(high.rpm < low.rpm && high.current_a < low.current_a);
        // and zero series resistance is exactly the stiff-voltage solve
        let stiff = solve_point(24.0, KV, RM, IO, IOV, KQ);
        let zero = solve_point_series(24.0, 0.0, KV, RM, IO, IOV, KQ);
        assert_eq!(stiff.rpm, zero.rpm);
    }

    #[test]
    fn series_resistance_sags_the_terminal_and_balances_power() {
        let p = solve_point_series(25.2, 0.05, KV, RM, IO, IOV, KQ);
        let term = 25.2 - p.current_a * 0.05;
        assert!((p.electrical_w - term * p.current_a).abs() < 1e-9);
        assert!(term < 25.2);
    }

    #[test]
    fn more_voltage_means_more_rpm_and_current() {
        let a = solve_point(12.0, KV, RM, IO, IOV, KQ);
        let b = solve_point(24.0, KV, RM, IO, IOV, KQ);
        assert!(b.rpm > a.rpm && b.current_a > a.current_a);
    }

    #[test]
    fn no_load_runs_near_kv_v_and_draws_about_io() {
        let p = solve_point(24.0, KV, RM, IO, IOV, 1e-14);
        assert!(p.rpm > 0.97 * KV * 24.0, "{}", p.rpm);
        assert!((p.current_a - IO).abs() < 0.1 * IO, "{}", p.current_a);
        assert!(p.efficiency < 0.01);
    }

    #[test]
    fn temperature_converges_to_steady_and_never_overshoots() {
        let c = thermal_mass(8.0, 14.0);
        let h = cooling(30.0, 5.0);
        let mut t = AMBIENT_C;
        for _ in 0..4000 { t = temp_step_impl(t, 10.0, c, h, 0.5); assert!(t <= AMBIENT_C + 10.0 / h + 1e-9); }
        assert!((t - (AMBIENT_C + 10.0 / h)).abs() < 1e-6);
        assert_eq!(temp_step_impl(AMBIENT_C, 0.0, c, h, 1.0), AMBIENT_C);
    }

    #[test]
    fn thermal_mass_and_cooling_scale_sensibly() {
        assert!(thermal_mass(8.0, 14.0) > thermal_mass(4.0, 7.0));
        assert!(cooling(30.0, 8.0) > cooling(30.0, 0.0));
        assert!(cooling(60.0, 0.0) > cooling(30.0, 0.0));
    }

    #[test]
    fn two_lump_settles_on_the_series_steady_state_and_the_bell_stays_cooler() {
        let (c1, c2, g, ga, loss) = (10.0, 6.0, 0.5, 0.3, 12.0);
        let (mut tw, mut tb) = (AMBIENT_C, AMBIENT_C);
        for _ in 0..4000 {
            let (a, b) = two_lump_step(tw, tb, loss, c1, c2, g, ga, 0.5);
            assert!(a >= tw - 1e-9 && b >= tb - 1e-9 && b <= a + 1e-9);
            tw = a; tb = b;
        }
        assert!((tb - (AMBIENT_C + loss / ga)).abs() < 1e-3, "{tb}");
        assert!((tw - (AMBIENT_C + loss / ga + loss / g)).abs() < 1e-3, "{tw}");
        // No loss: stays at ambient.
        assert_eq!(two_lump_step(AMBIENT_C, AMBIENT_C, 0.0, c1, c2, g, ga, 3.0), (AMBIENT_C, AMBIENT_C));
    }

    #[test]
    fn air_conductance_rises_with_rpm_as_a_sublinear_power() {
        let g = |r: f64| MotorModel::air_conductance_w_per_k(30.0, r);
        assert!(g(20000.0) > g(10000.0) && g(10000.0) > g(0.0));
        // Forced-convection part ~ rpm^0.8: doubling rpm less than doubles the gain.
        assert!((g(20000.0) - g(0.0)) < 2.0 * (g(10000.0) - g(0.0)));
        assert!((g(20000.0) - g(0.0)) > 1.5 * (g(10000.0) - g(0.0)));
    }

    #[test]
    fn thermal_constants_match_the_hand_worked_2207() {
        // 31.77 g 2207 (copper 6.35 g, stator 11.12 g, bell 12.71 g); worked by hand from the sources
        // cited at the constants: Incropera A.1 specific heats, Becker-Kaye airgap + shaft conduction,
        // and the rotating-cylinder correlation Nu = 0.133 Re^(2/3) Pr^(1/3).
        let m = 31.77;
        assert!((MotorModel::thermal_mass_j_per_k(6.35, 11.12) - 7.42).abs() < 0.05);
        assert!((MotorModel::bell_thermal_mass_j_per_k(12.71) - 8.90).abs() < 0.05);
        assert!((MotorModel::bell_conduction_w_per_k(m) - 0.100).abs() < 0.005);
        let still = MotorModel::air_conductance_w_per_k(m, 0.0);
        let flat_out = MotorModel::air_conductance_w_per_k(m, 25000.0);
        assert!((still - 0.0208).abs() < 0.001, "{still}");
        assert!((flat_out - 0.614).abs() < 0.02, "{flat_out}");
    }

    fn thermal_mass(cu: f64, fe: f64) -> f64 { cu * CU_J_PER_G_K + fe * FE_J_PER_G_K }
    fn cooling(m: f64, v: f64) -> f64 { AREA_M2_PER_G23 * m.powf(2.0 / 3.0) * (H_STILL_W_M2K + H_FLOW_W_M2K_PER_MPS * v) }

    #[test]
    fn dc_pack_state_is_the_series_operating_point() {
        // One motor, duty 1: the pack solve must agree with solve_point_series.
        let (amps, rpm) = dc_pack_state(1.0, 22.2, 0.02, 1.0, KV, RM, IO, IOV, KQ);
        let p = solve_point_series(22.2, 0.02, KV, RM, IO, IOV, KQ);
        assert!((amps - p.current_a).abs() < 1e-6, "{} vs {}", amps, p.current_a);
        assert!((rpm - p.rpm).abs() < 1e-3 * p.rpm);
    }

    #[test]
    fn dc_current_is_io_plus_torque_over_kt_and_matches_the_solve() {
        let p = solve_point(20.0, KV, RM, IO, IOV, KQ);
        let i = dc_current_impl(p.rpm, KV, IO, IOV, KQ);
        assert!((i - p.current_a).abs() < 1e-6, "{} vs {}", i, p.current_a);
    }

    #[test]
    fn a_lumped_coaxial_thruster_draws_every_motors_current_at_the_same_rpm() {
        let mut m = MotorModel { kv: KV, max_throttle: 1.0, tau_s: 0.03, dc_rm_ohm: RM, dc_io_a: IO,
                                 dc_io_v: IOV, dc_k_q: KQ, dc_count: 1.0 };
        let one = m.dc_current_at_rpm(15000.0);
        let rpm_one = m.target_rpm(0.6, 22.2);
        m.set_dc_count(2.0);
        assert!((m.dc_current_at_rpm(15000.0) - 2.0 * one).abs() < 1e-12);
        assert!((m.target_rpm(0.6, 22.2) - rpm_one).abs() < 1e-12, "count scales current, not rpm");
        m.set_dc_count(0.0);
        assert!((m.dc_current_at_rpm(15000.0) - one).abs() < 1e-12, "never below one motor");
    }

    #[test]
    fn rm_and_io_move_the_drones_current_and_rpm() {
        let (a0, r0) = dc_pack_state(0.8, 22.2, 0.02, 4.0, KV, RM, IO, IOV, KQ);
        let (a1, r1) = dc_pack_state(0.8, 22.2, 0.02, 4.0, KV, 2.0 * RM, IO, IOV, KQ);
        let (a2, _) = dc_pack_state(0.8, 22.2, 0.02, 4.0, KV, RM, 3.0 * IO, IOV, KQ);
        assert!(r1 < r0, "more Rm, less rpm");
        assert!(a1 < a0, "more Rm, less current");
        assert!(a2 > a0, "more Io, more current: {} vs {}", a2, a0);
    }

    #[test]
    fn legacy_motor_target_is_throttle_kv_voltage() {
        let m = MotorModel { kv: KV, max_throttle: 0.9, tau_s: 0.03, dc_rm_ohm: 0.0, dc_io_a: 0.0,
                             dc_io_v: 0.0, dc_k_q: 0.0, dc_count: 1.0 };
        assert!(!m.uses_dc());
        assert!((m.target_rpm(1.0, 20.0) - 0.9 * KV * 20.0).abs() < 1e-9);
    }
}
