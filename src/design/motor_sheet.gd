class_name MotorSheet
extends RefCounted
## The buy-and-build sheet for a designed motor: what to buy or to spec (stator, KV, poles, magnet,
## shaft, mount), the figures to expect on the chosen prop and pack, and a note on mounting screws.
## Plain text, to copy or to save, in the spirit of the Airframe build sheet (BuildSheet) and the
## pack's sheet (PackSheet).
##
## A pure function of the design, the prop and the pack. Every number is read from
## MotorDesign.derive() or from the MotorBench runs, so the sheet cannot disagree with the screen.
## The only words typed here are instructions. Every figure is ideal / model (MotorDesign.BASIS):
## none of it is a measurement of a real motor. Expected figures are PER MOTOR; the whole aircraft's
## total is given on one line.


## The sheet as data. Keys: name, label, motor {size, stator_mm, kv, poles, config, magnet,
## magnet_max_c, shaft_mm, mount, thread, mass_g, rm_ohm, io_a, io_voltage_v, max_current_a},
## setup {prop, pack, motors}, expected {max_thrust_g, current_a, hover_gpw, can_hover, hover_throttle,
## soak_winding_c, soak_bell_c, punch_winding_c, punch_bell_c, burn_s, total_thrust_g, total_current_a},
## warnings (the bench's lines at full throttle), screw_note. {} when the motor cannot be flown.
static func compose(design: MotorDesign, cfg: MotorConfigs, parts: Dictionary = {},
		catalog: PartsCatalog = null) -> Dictionary:
	var f := design.derive(cfg)
	if f.is_empty():
		return {}
	var sweep := MotorBench.run("sweep", design, cfg, parts, {}, catalog)
	if sweep.is_empty():
		return {}
	var soak := MotorBench.run("soak", design, cfg, parts, {}, catalog)
	var punch := MotorBench.run("punch", design, cfg, parts, {}, catalog)
	var ids := MotorBench.resolve_parts(parts)
	var cat: PartsCatalog = catalog if catalog != null else PartsCatalog.load_default()
	var thread := thread_of(design.mount)
	return {
		"name": design.display_name(),
		"label": MotorDesign.BASIS,
		"motor": {
			"size": design.size,
			"stator_mm": "%.0f x %.0f" % [float(f.stator_diameter_mm), float(f.stator_height_mm)],
			"kv": design.kv,
			"poles": design.poles,
			"config": design.config(),
			"magnet": design.magnet,
			"magnet_max_c": float(f.magnet_max_c),
			"shaft_mm": design.shaft_mm,
			"mount": design.mount,
			"thread": thread,
			"mass_g": float(f.mass_g),
			"rm_ohm": float(f.rm_ohm),
			"io_a": float(f.io_a),
			"io_voltage_v": float(f.io_voltage_v),
			"max_current_a": float(f.max_current_a),
		},
		"setup": {
			"prop": String(cat.get_part(String(ids.propeller)).get("name", ids.propeller)),
			"pack": String(cat.get_part(String(ids.battery)).get("name", ids.battery)),
			"motors": int(sweep.motors),
		},
		"expected": {
			"max_thrust_g": float(sweep.motor_thrust_g),
			"current_a": float(sweep.motor_current_a),
			"hover_gpw": float(sweep.hover_gpw),
			"can_hover": bool(sweep.can_hover),
			"hover_throttle": float(sweep.hover_throttle),
			"soak_winding_c": float(soak.end_temp_c),
			"soak_bell_c": float(soak.peak_bell_c),
			"punch_winding_c": float(punch.end_temp_c),
			"punch_bell_c": float(punch.peak_bell_c),
			"burn_s": float(punch.burn_s),
			"total_thrust_g": float(sweep.max_thrust_g),
			"total_current_a": float(sweep.max_current_a),
		},
		"warnings": punch.warnings,
		"screw_note": screw_note(thread),
	}


## "M3" from a mount option ("16 x 16 mm, M3"); "" when the option names no thread.
static func thread_of(mount: String) -> String:
	for part in mount.split(","):
		var t := part.strip_edges()
		if t.length() >= 2 and t[0] == "M" and t.substr(1).is_valid_float():
			return t
	return ""


## The one-line safety note. It states the rule and names no length: the arm and base thicknesses
## are the builder's own parts.
static func screw_note(thread: String) -> String:
	var screw := "%s screws" % thread if thread != "" else "Mounting screws"
	return "%s: measure before fitting. The screw must be no longer than the arm plus the motor base's thread depth; a longer one reaches the windings, shorts the coils and kills the motor." % screw


static func to_text(design: MotorDesign, cfg: MotorConfigs, parts: Dictionary = {},
		catalog: PartsCatalog = null) -> String:
	var d := compose(design, cfg, parts, catalog)
	if d.is_empty():
		return "MOTOR BUILD SHEET: %s\nThis motor cannot be flown on the chosen prop and pack.\n" % design.display_name()
	var m: Dictionary = d["motor"]
	var s: Dictionary = d["setup"]
	var e: Dictionary = d["expected"]
	var lines: PackedStringArray = []
	lines.append("MOTOR BUILD SHEET: %s" % String(d["name"]))
	lines.append("Figures are %s, not measured." % String(d["label"]))
	lines.append("")
	lines.append("MOTOR TO BUY OR SPEC")
	lines.append("  Stator: %s (%s mm)" % [String(m["size"]), String(m["stator_mm"])])
	lines.append("  KV: %d" % int(m["kv"]))
	lines.append("  Poles: %d (%s)" % [int(m["poles"]), String(m["config"])])
	lines.append("  Magnets: %s (heat limit %.0f °C)" % [String(m["magnet"]), float(m["magnet_max_c"])])
	lines.append("  Shaft: %s mm" % _trim(float(m["shaft_mm"])))
	lines.append("  Mount: %s" % String(m["mount"]))
	lines.append("  Mass: about %.1f g (est.)" % float(m["mass_g"]))
	lines.append("  Winding resistance about %.1f mOhm; no-load current about %.2f A at %.0f V (est.)" % [
		float(m["rm_ohm"]) * 1000.0, float(m["io_a"]), float(m["io_voltage_v"])])
	lines.append("  Rated current about %.0f A (est.)" % float(m["max_current_a"]))
	lines.append("")
	lines.append("EXPECTED FIGURES PER MOTOR (%s)" % String(d["label"]))
	lines.append("  On: %s, %s, %d motors" % [String(s["prop"]), String(s["pack"]), int(s["motors"])])
	lines.append("  Full throttle: %s g thrust, %.0f A" % [MotorBench._thousands(float(e["max_thrust_g"])), float(e["current_a"])])
	lines.append("  Efficiency: %.1f g/W %s" % [float(e["hover_gpw"]), "at hover" if bool(e["can_hover"]) else "at its best throttle (cannot hover)"])
	if bool(e["can_hover"]):
		lines.append("  Hover throttle: %.0f %%" % (float(e["hover_throttle"]) * 100.0))
	lines.append("  Hover for %s: winding %.0f °C, bell %.0f °C" % [MotorBench._duration(MotorBench.SOAK_S),
		float(e["soak_winding_c"]), float(e["soak_bell_c"])])
	if float(e["burn_s"]) >= 0.0:
		lines.append("  Full throttle: the winding burns out after %s" % MotorBench._burn_time(float(e["burn_s"])))
	else:
		lines.append("  Full throttle for %s: winding %.0f °C, bell %.0f °C" % [MotorBench._duration(MotorBench.PUNCH_S),
			float(e["punch_winding_c"]), float(e["punch_bell_c"])])
	lines.append("  All %d motors together: %s g, %.0f A" % [int(s["motors"]),
		MotorBench._thousands(float(e["total_thrust_g"])), float(e["total_current_a"])])
	var warns: Array = d["warnings"]
	if not warns.is_empty():
		lines.append("")
		lines.append("WARNINGS")
		for w in warns:
			lines.append("  - %s" % String(w))
	lines.append("")
	lines.append("SAFETY")
	lines.append("  - %s" % String(d["screw_note"]))
	return "\n".join(lines) + "\n"


static func _trim(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v
