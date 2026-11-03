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
        dc_current_impl(rpm, self.kv, self.dc_io_a, self.dc_io_v, self.dc_k_q)
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
// est.: handbook specific heats, J/(g.K). Copper 0.385, silicon-steel laminations ~0.45.
const CU_J_PER_G_K: f64 = 0.385;
const FE_J_PER_G_K: f64 = 0.45;
// est.: outer surface of a bell motor, m^2 per g^(2/3) (a 30 g 2207 is ~2e-3 m^2).
const AREA_M2_PER_G23: f64 = 2.07e-4;
// est.: film coefficient W/(m^2.K), still air plus a term per m/s of prop wash.
const H_STILL_W_M2K: f64 = 25.0;
const H_FLOW_W_M2K_PER_MPS: f64 = 8.0;

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

/// Current of one motor at `rpm` driving a prop of torque k_q * omega^2: Io(rpm) + torque / Kt.
pub fn dc_current_impl(rpm: f64, kv: f64, io: f64, io_v: f64, k_q: f64) -> f64 {
    let w = rpm * std::f64::consts::TAU / 60.0;
    io_impl(io, io_v, kv, rpm) + k_q * w * w / kt_impl(kv).max(1e-12)
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
        return (n * p.current_a, p.rpm);
    }
    let (mut lo, mut hi) = (0.0, rest_v / r_pack);
    for _ in 0..60 {
        let mid = 0.5 * (lo + hi);
        if n * at(mid).current_a > mid { lo = mid } else { hi = mid }
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
    let f = |rpm: f64| {
        let i = current_impl(v, rpm, kv, rm + r_s);
        let w = rpm * std::f64::consts::TAU / 60.0;
        (i - io_impl(io, io_v, kv, rpm)) * kt - k_q * w * w
    };
    let (mut lo, mut hi) = (0.0, kv * v);
    for _ in 0..80 {
        let mid = 0.5 * (lo + hi);
        if f(mid) > 0.0 { lo = mid } else { hi = mid }
    }
    let rpm = 0.5 * (lo + hi);
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
                             dc_io_v: 0.0, dc_k_q: 0.0 };
        assert!(!m.uses_dc());
        assert!((m.target_rpm(1.0, 20.0) - 0.9 * KV * 20.0).abs() < 1e-9);
    }
}
