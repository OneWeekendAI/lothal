class_name FlightRig
extends RefCounted
## Headless flight rig for the SR4 navigation core: Build -> DroneCore -> FlightController (tuned exactly as
## src/scenes/main.gd does) -> NavPilot, with a seeded Wind and a seeded Gyro. ONE seed drives every noise
## stream (gust process and gyro noise), so the same (build, conditions, seed) flies the same flight.
##
## step(dt) = nav.command(dt) (which calls fc.update) then core.step(motor_cmds, dt).

const DEFAULT_DT := 1.0 / 500.0

var build: Build
var core: DroneCore
var fc: FlightController
var wind: Wind
var nav: NavPilot
var conditions: Conditions
var seed_value: int
var dt := DEFAULT_DT
var time_s := 0.0


## `start_pos` is the take-off point in world metres (the aircraft starts there, level, at rest).
func _init(p_build: Build, p_conditions: Conditions, p_seed: int = 1, start_pos: Vector3 = Vector3(0, 10, 0),
		p_dt: float = DEFAULT_DT, field_opts: Dictionary = {}) -> void:
	build = p_build
	conditions = p_conditions
	seed_value = p_seed
	dt = p_dt
	core = build.build_drone_core(field_opts)
	wind = Wind.new(conditions, conditions.gust_tau_s, seed_value)
	core.wind = wind
	build.field_wind_mps = wind.speed_mps
	# the seed reaches the sensor too (Gyro keeps its seed for reset(); re-seed it now)
	core.gyro._seed = seed_value * 7919 + 13
	core.gyro.reset()
	fc = FlightController.new()
	fc.rate_loop.adopt_tune(PidTunes.new().tune_for(build))
	fc.rate_loop.config = build.config
	core.rigid_body.position_m = start_pos
	core.prime_motors(build.hover_throttle_for(core.powertrain.battery))
	nav = NavPilot.new(build, core, fc)


## A rig for a Design Space class id (five_inch, seven_lr, cinelifter, ...), its starting-project parts.
static func from_class(class_id: String, p_conditions: Conditions, p_seed: int = 1,
		start_pos: Vector3 = Vector3(0, 10, 0), p_dt: float = DEFAULT_DT, catalog: PartsCatalog = null) -> FlightRig:
	var cat := catalog if catalog != null else PartsCatalog.load_default()
	var b := DesignSession.default_for_class(class_id).build(cat)
	return FlightRig.new(b, p_conditions, p_seed, start_pos, p_dt)


func step(step_dt: float = -1.0) -> void:
	var d := step_dt if step_dt > 0.0 else dt
	var cmds := nav.command(d)
	core.step(cmds, d)
	time_s += d


func run_for(seconds: float) -> void:
	for _i in int(round(seconds / dt)):
		step()


func position() -> Vector3:
	return core.rigid_body.position_m


static func conditions_with_wind(speed_mps: float, from_deg: float, gust_mps: float = 0.0) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed_mps
	c.wind_from_deg = from_deg
	c.gustiness_mps = gust_mps
	return c
