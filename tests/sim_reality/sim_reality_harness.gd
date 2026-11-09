class_name SimRealityHarness
extends RefCounted
## SR0: a validation harness that flies published aircraft through the REAL sim path
## (Build -> DroneCore -> Rust powertrain) and compares the time to battery cutoff with the
## published figure. It is a reality check, not a calibration: nothing here may be tuned to make a
## reference land in band.
##
## ---------------------------------------------------------------------------
## TEST-ONLY CONTROLLER (there is no autopilot in the sim yet; SR4 builds one)
## ---------------------------------------------------------------------------
## `_Pilot` below is a minimal hover / steady-cruise controller that exists ONLY for this harness.
## It writes the four motor commands directly (no FlightController, no MotorMixer), because the
## stock FC is tuned per FPV class and a harness that depended on it would measure the tuning.
## It holds a height, a ground speed and a level attitude; nothing more. SR4 replaces it.
##
## ---------------------------------------------------------------------------
## WHAT "CUTOFF" MEANS HERE
## ---------------------------------------------------------------------------
## The sim has no battery-cutoff event, so one is defined here and stated in the table: the flight
## ends when the LOADED per-cell voltage sits below the chemistry's minimum cell voltage
## (BatteryModel.min_cell_v) for CUTOFF_HOLD_S, or the pack's capacity is fully used, whichever
## comes first. The 80 % "usable" convention the analytic flight time uses is reported beside it
## (`t80_min`) but is not what is compared with the published figure, because the published
## figures are mostly "to 0 %".
##
## Reference data lives in references.json BESIDE THIS FILE (harness-owned, injected into an
## in-memory catalog), never in data/parts/.

const REFERENCES_PATH := "res://tests/sim_reality/references.json"
const DT := 1.0 / 500.0
const CUTOFF_HOLD_S := 0.5
const MAX_FLIGHT_MIN := 120.0

static var _flight_cache: Dictionary = {}
## SR1: which field-physics items the harness flies with (Build.apply_field_physics keys). Default all
## on. `--field=none` flies the pre-SR1 aircraft; `--field=avionics,esc` turns on only those.
static var field_opts: Dictionary = {}


static func load_references(path: String = REFERENCES_PATH) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "references.json did not parse")
	return parsed["aircraft"]


static func find_reference(id: String) -> Dictionary:
	for r in load_references():
		if String(r["id"]) == id:
			return r
	return {}


## The shipped catalog plus this reference's own parts, in memory only. Parts are deep-copied so
## a test copy (capacity cut) can never leak into the next caller.
static func catalog_for(ref: Dictionary, capacity_scale: float = 1.0, frame_mass_g: float = -1.0) -> PartsCatalog:
	var catalog := PartsCatalog.load_default()
	for part in ref.get("parts", []):
		var copy: Dictionary = (part as Dictionary).duplicate(true)
		var category := String(copy["category"])
		if category == "battery":
			copy["specs"]["mah"] = float(copy["specs"]["mah"]) * capacity_scale
		if category == "frame" and frame_mass_g >= 0.0:
			copy["mass_g"] = frame_mass_g
		catalog.by_category[category].append(copy)
		catalog.by_id[copy["part_id"]] = copy
	return catalog


static func _build_with(ref: Dictionary, catalog: PartsCatalog) -> Build:
	var b: Dictionary = ref["build"]
	var built := Build.from_ids(catalog, b["frame"], b["motor"], b["propeller"], b["battery"],
		b.get("esc", Build.DEFAULT_ESC_ID), b.get("fc", Build.DEFAULT_FC_ID), b.get("components", {}))
	if ref.has("payload_w"):
		built.payload_w = float(ref["payload_w"]["w"])
	return built


## The Build for a reference. When the entry has `solve_frame_mass_to_g`, the (lumped) frame mass
## is the balancing item, solved so the whole aircraft weighs the published all-up mass. The solve
## ignores `capacity_scale`, so a capacity-cut test copy is the same aircraft with a smaller pack
## rating and not a lighter one.
static func build_for(ref: Dictionary, capacity_scale: float = 1.0) -> Build:
	if not ref.has("solve_frame_mass_to_g"):
		return _build_with(ref, catalog_for(ref, capacity_scale))
	var target := float(ref["solve_frame_mass_to_g"])
	var mass := 0.0
	for _i in 3:
		var probe := _build_with(ref, catalog_for(ref, 1.0, mass))
		mass += target - probe.all_up_weight_g()
	return _build_with(ref, catalog_for(ref, capacity_scale, mass))


## Flies one case ("hover" or "cruise") and returns the result dictionary. Memoised on
## (id, case, capacity_scale) so the table and the per-aircraft tests never fly twice.
static func fly(ref: Dictionary, case_name: String, capacity_scale: float = 1.0) -> Dictionary:
	var key := "%s|%s|%.4f|%s" % [ref["id"], case_name, capacity_scale, JSON.stringify(field_opts)]
	if _flight_cache.has(key):
		return _flight_cache[key]
	var result := _fly_uncached(ref, case_name, capacity_scale)
	_flight_cache[key] = result
	return result


static func _fly_uncached(ref: Dictionary, case_name: String, capacity_scale: float) -> Dictionary:
	var build := build_for(ref, capacity_scale)
	var core := build.build_drone_core(field_opts)
	var capacity_mah: float = core.powertrain.battery.capacity_mah

	var speed := float(ref["cases"][case_name].get("speed_mps", 0.0)) if case_name == "cruise" else 0.0
	var pilot := _Pilot.new(build, core, speed)
	var started := Time.get_ticks_msec()

	var t := 0.0
	var low_for := 0.0
	var t80 := -1.0
	var energy_wh := 0.0
	var ended_by := "time cap"
	var max_steps := int(MAX_FLIGHT_MIN * 60.0 / DT)
	var worst_tilt_deg := 0.0
	for _i in max_steps:
		core.step(pilot.commands(DT), DT)
		t += DT
		var o := core.observables
		energy_wh += o.voltage_live_v * o.current_total_a * DT / 3600.0
		if t80 < 0.0 and core.powertrain.battery.used_mah >= 0.8 * capacity_mah:
			t80 = t
		var tilt := rad_to_deg(acos(clampf((core.rigid_body.orientation * Vector3.UP).y, -1.0, 1.0)))
		worst_tilt_deg = maxf(worst_tilt_deg, tilt)
		if tilt > 75.0 or absf(core.rigid_body.position_m.y) > 50.0:
			ended_by = "LOST CONTROL (tilt %.0f deg, height %.1f m)" % [tilt, core.rigid_body.position_m.y]
			break
		if core.powertrain.battery.below_cutoff(o.current_total_a) and core.powertrain.battery.remaining_fraction() > 0.0:
			low_for += DT
		else:
			low_for = 0.0
		if low_for >= CUTOFF_HOLD_S:
			ended_by = "cell voltage cutoff"
			break
		if core.powertrain.battery.used_mah >= capacity_mah:
			ended_by = "capacity exhausted"
			break
	return {
		"time_min": t / 60.0,
		"t80_min": (t80 / 60.0) if t80 >= 0.0 else t / 60.0,
		"ended_by": ended_by,
		"valid": ended_by == "cell voltage cutoff" or ended_by == "capacity exhausted",
		"mean_power_w": energy_wh / maxf(t / 3600.0, 1e-9),
		"mean_current_a": (core.powertrain.battery.used_mah / 1000.0) / maxf(t / 3600.0, 1e-9),
		"auw_g": build.all_up_weight_g(),
		"max_tilt_deg": worst_tilt_deg,
		"wall_s": (Time.get_ticks_msec() - started) / 1000.0,
	}


## One table row for a (reference, case).
static func row(ref: Dictionary, case_name: String, capacity_scale: float = 1.0) -> Dictionary:
	var c: Dictionary = ref["cases"][case_name]
	var res := fly(ref, case_name, capacity_scale)
	var published := float(c["published_min"])
	var err_pct := (float(res["time_min"]) - published) / published * 100.0
	var band := float(ref.get("band_pct", 10.0))
	return {
		"id": ref["id"], "name": ref["name"], "case": case_name,
		"published_min": published, "sim_min": res["time_min"], "err_pct": err_pct,
		"band_pct": band, "in_band": bool(res["valid"]) and absf(err_pct) <= band,
		"tag": c.get("published_tag", c.get("tag", "published")), "result": res,
		"real_world": c.get("real_world", null),
		"fitted": ref.get("fitted_vs_heldout", ""),
		"published_auw_g": float(ref.get("published", {}).get("all_up_mass_g", 0.0)),
	}


static func all_rows(capacity_scale: float = 1.0) -> Array:
	var rows: Array = []
	for ref in load_references():
		for case_name in ref["cases"]:
			rows.append(row(ref, case_name, capacity_scale))
	return rows


static func format_table(rows: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("%-26s %-6s %9s %8s %8s %6s %-8s %-9s %6s %6s  %s" % [
		"aircraft", "case", "published", "sim_min", "err_%", "band", "verdict", "src_tag", "AUW_g", "pubAUW", "ended_by / note"])
	for r in rows:
		var res: Dictionary = r["result"]
		lines.append("%-26s %-6s %9.1f %8.1f %+8.1f %5.0f%% %-8s %-9s %6.0f %6.0f  %s" % [
			String(r["id"]), r["case"], r["published_min"], r["sim_min"], r["err_pct"], r["band_pct"],
			"IN BAND" if r["in_band"] else "OUT", r["tag"], res["auw_g"], r["published_auw_g"], res["ended_by"]])
		lines.append("    mean %.0f W / %.1f A, 80%%-used at %.1f min, wall %.0f s. fitted-vs-held-out: %s" % [
			res["mean_power_w"], res["mean_current_a"], res["t80_min"], res["wall_s"], r["fitted"]])
		var rw: Variant = r.get("real_world", null)
		if rw is Dictionary:
			var m := float(r["sim_min"])
			var inside := m >= float(rw["min_low"]) and m <= float(rw["min_high"])
			lines.append("    real-world (%s): %.0f-%.0f min -> sim %.1f min is %s" % [
				rw["tag"], rw["min_low"], rw["min_high"], m, "INSIDE" if inside else "outside"])
	return "\n".join(lines)


# ---------------------------------------------------------------------------------------------
# The test-only pilot.
# ---------------------------------------------------------------------------------------------
class _Pilot extends RefCounted:
	const WN := 8.0            # attitude loop natural frequency, rad/s (motor lag is ~30 ms)
	const ZETA := 0.9
	var build: Build
	var core: DroneCore
	var speed_ref: float
	var thr_ff: float
	var thr_i := 0.0
	var lean_i := 0.0
	var ixx: float
	var izz: float
	var arm_a: float
	var weight_n: float

	func _init(p_build: Build, p_core: DroneCore, p_speed: float) -> void:
		build = p_build
		core = p_core
		speed_ref = p_speed
		thr_ff = build.hover_throttle_for(core.powertrain.battery)
		var inertia: Basis = core.mass_properties.inertia
		ixx = inertia.x.x
		izz = inertia.z.z
		arm_a = build.arm_m * cos(deg_to_rad(45.0))
		weight_n = core.mass_properties.total_mass_kg * 9.81
		core.prime_motors(thr_ff)
		if speed_ref > 0.0:
			# Start AT cruise speed, with the lean that holds it, so the measured time is cruise
			# and not the first seconds of acceleration.
			core.rigid_body.velocity_mps = Vector3(0, 0, -speed_ref)
			var drag := build.drag_coefficient * speed_ref * speed_ref
			lean_i = atan2(drag, weight_n)
			core.rigid_body.orientation = Quaternion(Vector3.RIGHT, -lean_i)

	func commands(dt: float) -> Dictionary:
		var rb := core.rigid_body
		var up := rb.orientation * Vector3.UP
		var w := rb.angular_velocity_rad_s
		var cos_t := maxf(up.y, 0.5)

		# Height: P on height into a vertical-speed target, PI on vertical speed -> collective.
		var vz_cmd := clampf(1.5 * (0.0 - rb.position_m.y), -1.5, 1.5)
		var vz_err := vz_cmd - rb.velocity_mps.y
		thr_i = clampf(thr_i + thr_ff * 0.05 * vz_err * dt, -0.3, 0.3)
		var thr_c := (thr_ff + thr_i) / cos_t + thr_ff * 0.15 * vz_err

		# Speed: PI on ground speed -> lean angle (forward is -Z; nose-down is a negative rotation
		# about X, so the wanted X-angle is -lean).
		var lean_cmd := 0.0
		if speed_ref > 0.0:
			var v_fwd := -rb.velocity_mps.z
			var err := speed_ref - v_fwd
			lean_i = clampf(lean_i + 0.01 * err * dt, 0.0, 0.7)
			lean_cmd = clampf(lean_i + 0.05 * err, 0.0, 0.7)
		# HOVER MEANS HOVER (SR1): with forward-flight lift now uncapped, a pilot that only holds LEVEL lets the
		# 5-inch drift at 3 m/s and turns the drift into free translational lift. So in the hover case the pilot also
		# damps horizontal velocity (lean against it). Cruise is unchanged.
		var lateral_target := 0.0
		if speed_ref <= 0.0:
			lean_cmd = clampf(0.06 * rb.velocity_mps.z, -0.3, 0.3)   # moving -Z (forward) -> lean back (negative)
			lateral_target = clampf(0.06 * rb.velocity_mps.x, -0.3, 0.3)
		var theta_x := asin(clampf(up.z, -1.0, 1.0))
		var phi_z := -asin(clampf(up.x, -1.0, 1.0))
		var tau_x := ixx * (-WN * WN * (theta_x - (-lean_cmd)) - 2.0 * ZETA * WN * w.x)
		var tau_z := izz * (-WN * WN * (phi_z - lateral_target) - 2.0 * ZETA * WN * w.z)

		# Mix: thrust change per motor from the two torques, then to throttle through T ~ thr^2.
		var scale := 2.0 * thr_c / maxf(weight_n, 1e-6)    # d(throttle)/d(thrust) per N for one motor
		var out := {}
		for name in MotorLayout.MOTOR_NAMES:
			var p := MotorLayout.motor_position(name, build.arm_m)
			var d_thrust := (-p.z * tau_x + p.x * tau_z) / (4.0 * arm_a * arm_a)
			# each motor carries W/4, so d(thr)/dT = thr / (2 * W/4) = 2 thr / W (= scale).
			out[name] = clampf(thr_c + d_thrust * scale, 0.0, 1.0)
		return out
