//! Motors, propellers and the pack — the electro-mechanical half of the simulation, with no
//! rigid body anywhere in it. Ported from src/sim/powertrain.gd, golden cross-checked before
//! the GDScript was deleted.
//!
//! The split exists because a bench and a flight need exactly the same electrical model and
//! share nothing else. DroneCore (GDScript, unported) adds the flight half to the SAME
//! Observables instance, so consumers never learn which half produced what.
//!
//! Observables stays GDScript (design §4.3): this class writes into it once per publish(),
//! once per step — never per consumer read. HUD, RotorSynth and FlightRecorder read pure
//! GDScript with zero FFI.
//!
//! Across FFI, `motor_rpm` (a Dictionary keyed "M1".."M4" in the original) is a
//! PackedFloat64Array indexed 0..3 in MotorLayout.MOTOR_NAMES order, and `step()` takes the
//! throttle commands as the same shape.

use godot::prelude::*;

use crate::battery::BatteryModel;
use crate::motor::MotorModel;
use crate::propeller::PropellerModel;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Powertrain {
    #[var]
    pub motor_model: Gd<MotorModel>,
    #[var]
    pub battery: Gd<BatteryModel>,
    #[var]
    pub k_t: f64,
    #[var]
    pub k_q: f64,
    #[var]
    pub motor_max_amps: f64,
    /// The RPM at which a motor draws motor_max_amps with the fitted prop — a FIXED reference
    /// (KV x the voltage the amp figure was measured at), never the live RPM ceiling.
    #[var]
    pub rated_rpm: f64,
    #[var]
    pub pole_pairs: f64,
    #[var]
    pub blades: f64,
    #[var]
    pub prop_radius_m: f64,
    /// MotorLayout.MOTOR_NAMES order (M1..M4). Was a Dictionary in the GDScript; the array is
    /// the same storage the cross-check verified against before the twin was deleted.
    #[var]
    pub motor_rpm: PackedFloat64Array,
    #[var]
    pub last_voltage_v: f64,
    #[var]
    pub last_current_total_a: f64,
    /// The published observables layer. Created here and shared with DroneCore when one wraps
    /// this — exactly one instance per simulation, bench or flight.
    #[var]
    pub observables: Gd<godot::classes::RefCounted>,
}

impl Powertrain {
    fn make_observables() -> Gd<godot::classes::RefCounted> {
        let mut loader = godot::classes::ResourceLoader::singleton();
        let resource = loader
            .load("res://src/sim/observables.gd")
            .expect("observables.gd should load");
        let mut script: Gd<godot::classes::GDScript> = resource
            .try_cast::<godot::classes::GDScript>()
            .expect("loaded resource should be a GDScript");
        script
            .instantiate(&[])
            .try_to::<Gd<godot::classes::RefCounted>>()
            .expect("instantiated script should be a RefCounted")
    }
}

#[godot_api]
impl Powertrain {
    #[func]
    fn create(motor_model: Gd<MotorModel>, k_t: f64, k_q: f64, battery: Gd<BatteryModel>,
              motor_max_amps: f64, rated_rpm: f64, pole_pairs: f64, blades: f64,
              prop_radius_m: f64) -> Gd<Self> {
        let last_voltage_v = battery.bind().nominal_v;
        let observables = Self::make_observables();
        let mut pt = Gd::from_object(Self {
            motor_model,
            battery,
            k_t,
            k_q,
            motor_max_amps,
            rated_rpm,
            pole_pairs,
            blades,
            prop_radius_m,
            motor_rpm: PackedFloat64Array::from([0.0, 0.0, 0.0, 0.0]),
            last_voltage_v,
            last_current_total_a: 0.0,
            observables,
        });
        pt.bind_mut().publish();
        pt
    }

    /// Current drawn by ONE motor at a given RPM. Current tracks shaft torque, and torque
    /// goes as RPM^2 just like thrust, so the reference point is a fixed RPM — the one the
    /// motor's amp rating was measured at — never the live RPM ceiling. Against the live
    /// ceiling, a high-resistance pack would run away to a total voltage collapse.
    #[func]
    fn current_at_rpm(&self, rpm: f64) -> f64 {
        if self.rated_rpm <= 0.0 {
            return 0.0;
        }
        let rpm_fraction = rpm / self.rated_rpm;
        self.motor_max_amps * rpm_fraction * rpm_fraction
    }

    /// Places all four motors at the steady-state RPM for a given throttle, and the pack at
    /// the voltage that draws. Motors otherwise start dead.
    #[func]
    fn prime(&mut self, throttle: f64) {
        let t = throttle.clamp(0.0, self.motor_model.bind().max_throttle);
        // rpm and the sag it causes are mutually dependent; converges quickly because the
        // current term is self-limiting.
        let mut voltage_v = self.battery.bind().nominal_v;
        let mut rpm = 0.0;
        for _ in 0..12 {
            rpm = t * self.motor_model.bind().max_rpm(voltage_v);
            voltage_v = self.battery.bind().voltage_live(4.0 * self.current_at_rpm(rpm));
        }
        self.last_current_total_a = 4.0 * self.current_at_rpm(rpm);
        self.last_voltage_v = voltage_v;
        for i in 0..4 {
            self.motor_rpm[i] = rpm;
        }
        self.publish();
    }

    /// Advances every motor one dt, drains the pack, and republishes.
    /// `motor_throttle_cmds` is MotorLayout.MOTOR_NAMES order (M1..M4), values 0..1.
    #[func]
    fn step(&mut self, motor_throttle_cmds: PackedFloat64Array, dt: f64) {
        let mut total_current_a = 0.0;
        let mut thrusts = [0.0f64; 4];

        for i in 0..4 {
            let rpm = self.motor_model.bind().step(
                self.motor_rpm[i],
                motor_throttle_cmds[i],
                self.last_voltage_v,
                dt,
            );
            self.motor_rpm[i] = rpm;
            let thrust = PropellerModel::thrust_n(self.k_t, rpm);
            thrusts[i] = thrust;
            total_current_a += self.current_at_rpm(rpm);
        }
        self.observables.set(
            "thrust_n",
            &PackedFloat32Array::from([thrusts[0] as f32, thrusts[1] as f32,
                thrusts[2] as f32, thrusts[3] as f32]).to_variant(),
        );

        // The simulation's own clock, here rather than in DroneCore because a BENCH runs a
        // powertrain with no rigid body and still has an elapsed time.
        let elapsed = self.observables.get("elapsed_s").try_to::<f64>().expect("elapsed_s should be a float");
        self.observables.set("elapsed_s", &(elapsed + dt).to_variant());

        self.battery.bind_mut().drain(total_current_a, dt);
        self.last_current_total_a = total_current_a;
        // The live voltage the NEXT step's RPM ceiling is taken against. This one line is the
        // difference between a bench and a spreadsheet.
        self.last_voltage_v = self.battery.bind().voltage_live(total_current_a);

        self.publish();
    }

    /// Fills the powertrain half of the observables layer. The ONLY place blade-pass and
    /// electrical frequency are computed. Called from step() and prime(), never from a
    /// consumer — a consumer that can trigger a republish can trigger it at a different rate
    /// than physics runs at.
    #[func]
    fn publish(&mut self) {
        let mut rpm_arr = Vec::with_capacity(4);
        let mut blade_pass = Vec::with_capacity(4);
        let mut electrical = Vec::with_capacity(4);
        let mut tip_speed = Vec::with_capacity(4);
        let mut reaction = Vec::with_capacity(4);
        let mut current = Vec::with_capacity(4);

        let mut total_thrust = 0.0;
        for i in 0..4 {
            let rpm = self.motor_rpm[i];
            let rev_per_s = rpm / 60.0;
            rpm_arr.push(rpm as f32);
            blade_pass.push((rev_per_s * self.blades) as f32);
            electrical.push((rev_per_s * self.pole_pairs) as f32);
            tip_speed.push((PropellerModel::rpm_to_rad_s(rpm) * self.prop_radius_m) as f32);
            let reaction_nm = PropellerModel::reaction_torque_n_m(self.k_q, rpm);
            reaction.push(reaction_nm);
            current.push(self.current_at_rpm(rpm));
            // Recomputed from stored rpm like everything else in this function, so a republish
            // is still idempotent — the value step() published this tick, read back the same.
            let thrust_arr: PackedFloat32Array = self.observables.get("thrust_n").to();
            total_thrust += thrust_arr[i] as f64;
        }

        self.observables.set("rpm", &PackedFloat32Array::from(rpm_arr).to_variant());
        self.observables.set("blade_pass_hz", &PackedFloat32Array::from(blade_pass).to_variant());
        self.observables.set("electrical_hz", &PackedFloat32Array::from(electrical).to_variant());
        self.observables.set("tip_speed_mps", &PackedFloat32Array::from(tip_speed).to_variant());
        self.observables.set("reaction_torque_n_m", &PackedFloat64Array::from(reaction).to_variant());
        self.observables.set("current_a", &PackedFloat64Array::from(current).to_variant());
        self.observables.set("total_thrust_n", &total_thrust.to_variant());
        self.observables.set("current_total_a", &self.last_current_total_a.to_variant());
        self.observables.set("voltage_live_v", &self.last_voltage_v.to_variant());
        self.observables
            .set("capacity_used_fraction", &(1.0 - self.battery.bind().remaining_fraction()).to_variant());
        self.observables.set("prop_radius_m", &self.prop_radius_m.to_variant());
        self.observables.set("blades", &self.blades.to_variant());
        self.observables.set("pole_pairs", &self.pole_pairs.to_variant());
    }

    /// Test/divergence seam for setting one motor's stored RPM directly. The GDScript used a
    /// Dictionary alias so `core.motor_rpm[name] = rpm` reached the powertrain's storage;
    /// PackedFloat64Array is copy-on-write, so the write must go through the class instead.
    #[func]
    fn set_motor_rpm_at(&mut self, index: i64, rpm: f64) {
        self.motor_rpm[index as usize] = rpm;
    }
}
