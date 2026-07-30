class_name Observables
extends RefCounted
## The published state of the simulation, filled once per physics tick by DroneCore and
## read-only for everything else (architecture.md, "DERIVED OBSERVABLES").
##
## This existed as a diagram before it existed as a file. The HUD was written against
## DroneCore's internal fields directly, which worked because it was the only consumer;
## audio is the second, and two consumers reaching into physics internals is exactly the
## drift the layer was drawn to prevent. The rule the diagram states and this file
## enforces: blade-pass frequency is computed in ONE place, and audio never derives its
## own RPM.
##
## Everything is stored per motor in MotorLayout.MOTOR_NAMES order, as packed floats
## rather than a Dictionary of names. The audio synthesiser reads these four values for
## every block it generates, and a string-keyed Dictionary lookup in that path is real
## measurable cost for no readability gain at four elements.

const MOTOR_COUNT := 4
const GRAVITY_MPS2 := 9.81
const SPEED_OF_SOUND_MPS := 343.0

# --- Per motor ---
var rpm := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var thrust_n := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## rpm/60 x blade count. The rate at which blades sweep past a fixed point in space, and
## the fundamental of the rotor's tonal noise.
var blade_pass_hz := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## rpm/60 x pole pairs. A 14-pole motor has 7 pole pairs, so this runs well above
## blade-pass: it is the thin whine on top, not the body of the sound.
var electrical_hz := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Blade-tip speed, m/s. Broadband (turbulent) rotor noise scales very steeply with this
## — far more steeply than with thrust — which is why it is published separately rather
## than left for a consumer to recover from RPM and prop diameter.
var tip_speed_mps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

# --- Whole aircraft ---
var total_thrust_n: float = 0.0
var weight_n: float = 0.0
var current_total_a: float = 0.0
var voltage_live_v: float = 0.0
var capacity_used_fraction: float = 0.0

var position_m := Vector3.ZERO
var velocity_mps := Vector3.ZERO
var orientation := Quaternion.IDENTITY
var angular_velocity_rad_s := Vector3.ZERO
## Specific force in the BODY frame — what an onboard accelerometer would read, i.e.
## excluding gravity. A drone in free fall reads zero here, which is the physically
## correct answer and the one a consumer wants.
var accel_body_mps2 := Vector3.ZERO
var airspeed_mps: float = 0.0
var g_force: float = 0.0

# --- Build constants, republished so consumers need no reference to Build ---
var prop_radius_m: float = 0.0
var blades: float = 3.0
var pole_pairs: float = 7.0

static func index_of(motor_name: String) -> int:
	return MotorLayout.MOTOR_NAMES.find(motor_name)

## Mean RPM across the four motors — used by anything that wants "how hard is it working"
## as a single number.
func mean_rpm() -> float:
	var total := 0.0
	for i in MOTOR_COUNT:
		total += rpm[i]
	return total / float(MOTOR_COUNT)

## The spread between the fastest and slowest motor. This is the number that produces
## audible beating: four rotors at identical RPM sum to one louder rotor, and it is the
## PID's continuous correction keeping them apart that makes a quad sound like a quad.
func rpm_spread() -> float:
	var lo: float = rpm[0]
	var hi: float = rpm[0]
	for i in MOTOR_COUNT:
		lo = minf(lo, rpm[i])
		hi = maxf(hi, rpm[i])
	return hi - lo
