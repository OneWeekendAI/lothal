class_name MotorBench
extends RefCounted
## The bench behind the motor designer: pure, headless runs of a designed motor on a prop and a
## pack. It flies nothing of its own: it builds the real `Build` (same k_t fit, same DC law, same
## pack solve) with the designed motor standing in for the shelf one, and asks it for steady
## operating points through `Build.uncapped_point`. Heat is the lumped winding model in
## `MotorModel` (thermal mass against air cooling), shown beside the electrical run, never fed back.
## Every figure is ideal / model.
##
## THREE RUNS. "sweep": thrust, current and g/W against throttle. "soak": winding temperature
## holding the build's hover throttle. "punch": 100 % for PUNCH_S, temperature and the pack voltage
## sagging as the pack drains.
##
## Thrust and current are for the whole aircraft (every motor the frame carries); temperature is
## one motor's winding. Prop torque is the existing prop model's (k_q is fitted from k_t); the
## prop-torque chapter is separate, so current reads high until it lands.

const KINDS := ["sweep", "soak", "punch"]
## The air the winding starts in, C (the motor model's and the pack bench's 25).
const AMBIENT_C := 25.0
## The winding enamel's limit, C: IEC 60085 thermal class H, 180 C (polyimide / polyester-imide
## magnet-wire enamel is sold at 180-200 C). Past it the insulation fails and turns short, so a run
## stops there ("Burns out") and nothing is ever drawn beyond it.
const ENAMEL_LIMIT_C := 180.0
const SWEEP_STEPS := 40
## g/W is a ratio of two small numbers near zero throttle, so its curve starts at this step (10 %).
const GPW_FROM_STEP := 4
const SOAK_S := 300.0
const PUNCH_S := 15.0
const DT_S := 0.5
## A prop is "too big" when flat out the motor reaches under this share of its no-load rpm.
const PROP_LOADED_MIN := 0.6
const BENCH_MOTOR_ID := "bench_designed_motor"
const BENCH_PACK_ID := "bench_pack"
const DEFAULT_PARTS := {
	"frame": ReferenceBuild.FRAME_ID,
	"propeller": ReferenceBuild.PROPELLER_ID,
	"battery": ReferenceBuild.BATTERY_ID,
}

static var _shipped: PartsCatalog


## The whole bench: run `kind` for `design` on `parts` ({frame, propeller, battery} ids; missing
## keys take the reference build's). `pack_record` replaces the battery with an edited copy (the
## tests raise its resistance). Returns {} when the motor cannot be flown (off the grid).
static func run(kind: String, design: MotorDesign, cfg: MotorConfigs, parts: Dictionary = {},
		pack_record: Dictionary = {}, catalog: PartsCatalog = null) -> Dictionary:
	var b := make_build(design, cfg, parts, pack_record, catalog)
	if b == null:
		return {}
	var f := design.derive(cfg)
	var out: Dictionary
	match kind:
		"soak":
			out = _soak(b, f)
		"punch":
			out = _punch(b, f)
		_:
			kind = "sweep"
			out = _sweep(b)
	out["kind"] = kind
	out["warnings"] = warnings(out, b, f)
	return out


## The Build the bench reads: the real frame, prop and pack, with this design as the motor.
static func make_build(design: MotorDesign, cfg: MotorConfigs, parts: Dictionary = {},
		pack_record: Dictionary = {}, base: PartsCatalog = null) -> Build:
	if _shipped == null:
		_shipped = PartsCatalog.load_default()
	if base == null:
		base = _shipped
	var rec := design.drone_record(cfg, _shipped)
	if rec.is_empty():
		return null
	rec["part_id"] = BENCH_MOTOR_ID
	var catalog := PartsCatalog.new()
	catalog.by_id = base.by_id.duplicate()
	catalog.by_category = base.by_category.duplicate()
	catalog.by_id[BENCH_MOTOR_ID] = rec
	var battery_id := String(parts.get("battery", DEFAULT_PARTS.battery))
	if not pack_record.is_empty():
		var p := pack_record.duplicate(true)
		p["part_id"] = BENCH_PACK_ID
		catalog.by_id[BENCH_PACK_ID] = p
		battery_id = BENCH_PACK_ID
	return Build.from_ids(catalog, String(parts.get("frame", DEFAULT_PARTS.frame)), BENCH_MOTOR_ID,
		String(parts.get("propeller", DEFAULT_PARTS.propeller)), battery_id)


# ---------------------------------------------------------------------------
# The three runs
# ---------------------------------------------------------------------------

static func _sweep(b: Build) -> Dictionary:
	var pack_r := float(b.battery["specs"]["internal_r_ohm"])
	var voc := b.resolve_open_circuit_v(Build.AT_NOMINAL)
	var x := PackedFloat64Array()
	var thrust := PackedFloat64Array()
	var amps := PackedFloat64Array()
	var gpw := PackedFloat64Array()
	var rpm := PackedFloat64Array()
	var wind := PackedFloat64Array()
	for i in SWEEP_STEPS + 1:
		var t := float(i) / float(SWEEP_STEPS)
		var p := b.uncapped_point(t, voc)
		var g := float(p.thrust_n) / Build.GRAVITY_MPS2 * 1000.0
		var ia := float(p.pack_current_a)
		var watts := ia * (voc - ia * pack_r)
		x.append(t * 100.0)
		thrust.append(g)
		amps.append(ia)
		gpw.append(g / watts if watts > 1.0 else 0.0)
		rpm.append(float(p.rpm))
		wind.append(float(p.winding_current_a))
	var hover_t := hover_throttle(b)
	var hp := b.uncapped_point(hover_t, voc)
	var hw := float(hp.pack_current_a) * (voc - float(hp.pack_current_a) * pack_r)
	var hover_gpw := float(hp.thrust_n) / Build.GRAVITY_MPS2 * 1000.0 / maxf(hw, 1.0)
	var last := SWEEP_STEPS
	return {
		"x": x, "gpw_x": x.slice(GPW_FROM_STEP), "gpw_from": GPW_FROM_STEP, "thrust_g": thrust, "current_a": amps, "gpw": gpw, "rpm": rpm, "winding_a": wind,
		"max_thrust_g": thrust[last], "max_current_a": amps[last], "hover_gpw": hover_gpw,
		"hover_throttle": hover_t, "can_hover": b.can_hover(),
		"peak_winding_a": wind[last], "peak_temp_c": NAN, "end_rpm": rpm[last],
		"result": "Max %s g  ·  %.0f A  ·  %.1f g/W %s" % [_thousands(thrust[last]), amps[last],
			hover_gpw, "at hover" if b.can_hover() else "at its best throttle (cannot hover)"],
	}


static func _soak(b: Build, f: Dictionary) -> Dictionary:
	var voc := b.resolve_open_circuit_v(Build.AT_NOMINAL)
	var hover_t := hover_throttle(b)
	var p := b.uncapped_point(hover_t, voc)
	var temps := _heat(f, float(p.rpm), float(p.winding_current_a), SOAK_S)
	var end_c := float(temps.y[temps.y.size() - 1])
	var limit := float(f.magnet_max_c)
	var gap := limit - end_c
	var burn_s := float(temps.burn_s)
	var line := "Ends at %.0f °C after %s of hover  ·  %s" % [end_c, _duration(SOAK_S),
		("%.0f °C below the %.0f °C limit" % [gap, limit]) if gap >= 0.0
		else ("%.0f °C over the %.0f °C limit" % [-gap, limit])]
	if burn_s >= 0.0:
		line = "Burns out after %s of hover  ·  the winding reached %.0f °C" % [_burn_time(burn_s), ENAMEL_LIMIT_C]
	return {
		"x": temps.x, "temp_c": temps.y, "peak_temp_c": end_c, "end_temp_c": end_c,
		"burn_s": burn_s,
		"hover_throttle": hover_t, "can_hover": b.can_hover(),
		"peak_winding_a": float(p.winding_current_a), "end_rpm": float(p.rpm),
		"loss_w": float(temps.loss_w),
		"result": line,
	}


static func _punch(b: Build, f: Dictionary) -> Dictionary:
	var pack := b.battery_model()
	var lumps := Lumps.new(f)
	var t := PackedFloat64Array()
	var temp := PackedFloat64Array()
	var volts := PackedFloat64Array()
	var rpms := PackedFloat64Array()
	var clock := 0.0
	var peak_a := 0.0
	var peak_pack_a := 0.0
	var start_v := pack.voltage_live(0.0)
	var low_v := start_v
	var rpm := 0.0
	var burn_s := -1.0
	while clock <= PUNCH_S + 1e-9:
		var p := b.uncapped_point(1.0, pack.resting_voltage_v())
		rpm = float(p.rpm)
		var ia := float(p.pack_current_a)
		var live := pack.voltage_live(ia)
		t.append(clock)
		temp.append(lumps.winding_c)
		volts.append(live)
		rpms.append(rpm)
		low_v = minf(low_v, live)
		peak_a = maxf(peak_a, float(p.winding_current_a))
		peak_pack_a = maxf(peak_pack_a, ia)
		var loss := _loss_w(f, rpm, float(p.winding_current_a))
		var before := lumps.winding_c
		lumps.step(loss, rpm, DT_S)
		if lumps.winding_c >= ENAMEL_LIMIT_C:
			# Burnt out inside this step: the last point is where the line crosses the limit.
			burn_s = clock + DT_S * (ENAMEL_LIMIT_C - before) / maxf(lumps.winding_c - before, 1e-9)
			t.append(burn_s)
			temp.append(ENAMEL_LIMIT_C)
			volts.append(live)
			rpms.append(rpm)
			break
		pack.drain(ia, DT_S)
		clock += DT_S
	var end_c := temp[temp.size() - 1]
	var line := "100%% for %s  ·  %.0f °C  ·  pack sags from %.1f to %.1f V at %.0f A" % [
		_duration(PUNCH_S), end_c, start_v, low_v, peak_pack_a]
	if burn_s >= 0.0:
		line = "Burns out after %s at full throttle  ·  the winding reached %.0f °C" % [_burn_time(burn_s), ENAMEL_LIMIT_C]
	return {
		"x": t, "temp_c": temp, "v_live": volts, "rpm": rpms, "burn_s": burn_s,
		"peak_temp_c": end_c, "end_temp_c": end_c, "end_rpm": rpms[rpms.size() - 1],
		"start_rpm": rpms[0], "peak_winding_a": peak_a, "peak_pack_a": peak_pack_a,
		"start_v": start_v, "low_v": low_v, "can_hover": b.can_hover(),
		"result": line,
	}


## Winding temperature from ambient at a constant operating point.
static func _heat(f: Dictionary, rpm: float, winding_a: float, seconds: float) -> Dictionary:
	var lumps := Lumps.new(f)
	var loss := _loss_w(f, rpm, winding_a)
	var x := PackedFloat64Array()
	var y := PackedFloat64Array()
	var clock := 0.0
	var burn_s := -1.0
	while clock <= seconds + 1e-9:
		x.append(clock)
		y.append(lumps.winding_c)
		var before := lumps.winding_c
		lumps.step(loss, rpm, DT_S)
		if lumps.winding_c >= ENAMEL_LIMIT_C:
			burn_s = clock + DT_S * (ENAMEL_LIMIT_C - before) / maxf(lumps.winding_c - before, 1e-9)
			x.append(burn_s)
			y.append(ENAMEL_LIMIT_C)
			break
		clock += DT_S
	return {"x": x, "y": y, "loss_w": loss, "burn_s": burn_s}


## The two heat lumps of one motor: the stator + winding (iron + copper) holds the loss and
## conducts into the bell, and the bell sheds to the air, better the faster it spins (forced
## convection, `MotorModel.air_conductance_w_per_k`). `winding_c` is the figure the bench shows.
class Lumps extends RefCounted:
	var winding_c := AMBIENT_C
	var bell_c := AMBIENT_C
	var c_stator: float
	var c_bell: float
	var g_cond: float
	var mass_g: float

	func _init(f: Dictionary) -> void:
		mass_g = float(f.mass_g)
		c_stator = MotorModel.thermal_mass_j_per_k(float(f.copper_g), float(f.stator_g))
		c_bell = MotorModel.bell_thermal_mass_j_per_k(float(f.bell_g))
		g_cond = MotorModel.bell_conduction_w_per_k(mass_g)

	func step(loss_w: float, rpm: float, dt: float) -> void:
		var t := MotorModel.bell_temp_step_c(Vector2(winding_c, bell_c), loss_w, c_stator, c_bell,
			g_cond, MotorModel.air_conductance_w_per_k(mass_g, rpm), dt)
		winding_c = t.x
		bell_c = t.y


## Heat the winding and stator shed, W, for ONE motor: I^2 Rm plus the iron and friction loss
## Io(rpm) x back-EMF, the same split `MotorModel.loss_w` makes.
static func _loss_w(f: Dictionary, rpm: float, winding_a: float) -> float:
	var kv := float(f.kv)
	var io := MotorModel.io_at_rpm(float(f.io_a), float(f.io_voltage_v), kv, rpm)
	return winding_a * winding_a * float(f.rm_ohm) + io * rpm / kv


static func hover_throttle(b: Build) -> float:
	return b.hover_throttle()


# ---------------------------------------------------------------------------
# Warnings: one plain line each
# ---------------------------------------------------------------------------

static func warnings(run_: Dictionary, b: Build, f: Dictionary) -> Array[String]:
	# One short line each (8 words at most), most severe first: burn-out, then the magnets' heat
	# limit, then current over rating, then a prop that is too big.
	var out: Array[String] = []
	var burn_s := float(run_.get("burn_s", -1.0))
	if burn_s >= 0.0:
		out.append("Winding burns out after %s" % _burn_time(burn_s))
	var temp := float(run_.get("peak_temp_c", NAN))
	var limit := float(f.magnet_max_c)
	if not is_nan(temp) and temp > limit:
		out.append("Magnets overheat: %.0f °C vs %.0f °C" % [temp, limit])
	var rating := float(f.max_current_a)
	var amps := float(run_.get("peak_winding_a", 0.0))
	if amps > rating:
		out.append("Over current rating: %.0f A vs %.0f A" % [amps, rating])
	var share := loaded_share(b, f)
	if share < PROP_LOADED_MIN:
		out.append("Prop too big: %.0f%% of no-load rpm" % (share * 100.0))
	return out


## Which side of the motor + prop + pack combination gives out first, read from a full-throttle
## run: the pack against its continuous rating, the motor against its current rating and its
## magnets' heat limit, the prop against how far it drags the motor below its no-load speed. Each
## is a ratio to its own limit (1.0 = at the limit) and the largest names the limiter. Returns
## {key: "pack"|"motor"|"prop", ratios: {pack, motor, prop}, text: one sentence "Limited by: ..."}
## ({} if the motor cannot be flown).
static func limited_by(design: MotorDesign, cfg: MotorConfigs, parts: Dictionary = {},
		pack_record: Dictionary = {}, catalog: PartsCatalog = null) -> Dictionary:
	var b := make_build(design, cfg, parts, pack_record, catalog)
	if b == null:
		return {}
	var f := design.derive(cfg)
	return limited_from(b, f, _punch(b, f))


static func limited_from(b: Build, f: Dictionary, punch: Dictionary) -> Dictionary:
	var pack_max := maxf(b.pack_max_amps(), 0.001)
	var peak_pack := float(punch.peak_pack_a)
	var peak_wind := float(punch.peak_winding_a)
	var temp := float(punch.peak_temp_c)
	var limit_c := float(f.magnet_max_c)
	var share := loaded_share(b, f)
	var by_current := peak_wind / maxf(float(f.max_current_a), 0.001)
	var by_heat := (temp - AMBIENT_C) / maxf(limit_c - AMBIENT_C, 1.0)
	var ratios := {
		"pack": peak_pack / pack_max,
		"motor": maxf(by_current, by_heat),
		"prop": PROP_LOADED_MIN / maxf(share, 0.001),
	}
	var key := "pack"
	for k in ["motor", "prop"]:
		if float(ratios[k]) > float(ratios[key]):
			key = k
	var text := ""
	match key:
		"pack":
			text = "Limited by: pack current, %.0f A of %.0f A." % [peak_pack, pack_max]
		"motor":
			if float(punch.get("burn_s", -1.0)) >= 0.0:
				text = "Limited by: motor heat, burns out in %s." % _burn_time(float(punch.burn_s))
			elif by_heat >= by_current:
				text = "Limited by: motor heat, %.0f °C of %.0f °C." % [temp, limit_c]
			else:
				text = "Limited by: motor current, %.0f A of %.0f A." % [peak_wind, float(f.max_current_a)]
		_:
			text = "Limited by: prop load, %.0f%% of no-load rpm." % (share * 100.0)
	return {"key": key, "ratios": ratios, "text": text}


## Flat-out rpm over the no-load rpm (Kv x pack voltage) on this prop and pack.
static func loaded_share(b: Build, f: Dictionary) -> float:
	var voc := b.resolve_open_circuit_v(Build.AT_NOMINAL)
	var p := b.uncapped_point(1.0, voc)
	return float(p.rpm) / maxf(float(f.kv) * voc, 1.0)


static func _thousands(v: float) -> String:
	var n := int(round(v))
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _burn_time(s: float) -> String:
	return "%.1f s" % s if s < 120.0 else _duration(s)


static func _duration(s: float) -> String:
	return "%.0f min" % (s / 60.0) if s >= 120.0 else "%.0f s" % s
