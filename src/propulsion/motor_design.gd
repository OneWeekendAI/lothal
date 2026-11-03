class_name MotorDesign
extends RefCounted
## One motor in the Motor Designer: a point on the standard configuration grid (MotorConfigs)
## plus its Bell & shaft choices. Holds choices only; every figure comes from derive(), which
## reads MotorConfigs, so the designer and the shelf presets share one set of laws.
##
## CHOICES ARE LIMITED TO THE GRID. set_kv() takes only a KV sold for the current size, and
## set_size() moves the KV to the nearest option of the new size (and the shaft and mount to
## that size's own options), so no combination can exist that the grid does not list.

## The label the figures column carries: nothing here was measured.
const BASIS := "ideal / model"
const DEFAULT_SIZE := "2207"
const DEFAULT_KV := 1960.0

var name := ""
var size := DEFAULT_SIZE
var kv := DEFAULT_KV
var poles := 14
var magnet := "N52"
var shaft_mm := 4.0
var mount := ""


static func default_design(cfg: MotorConfigs) -> MotorDesign:
	var d := MotorDesign.new()
	d.size = ""
	d.kv = DEFAULT_KV
	d.set_size(cfg, DEFAULT_SIZE)
	var mags := cfg.magnets()
	if not mags.is_empty():
		d.magnet = String(mags[0].get("grade", "N52"))
	return d


## The KV values this size is sold in: the only values set_kv() accepts.
func kv_choices(cfg: MotorConfigs) -> Array:
	return cfg.kv_options(size)


## Moves to another grid size. KV goes to the nearest option of the new size; the pole count,
## shaft and mount go to the new size's usual ones. False (and no change) for a size not on the grid.
func set_size(cfg: MotorConfigs, p_size: String) -> bool:
	var row := cfg.get_size(p_size)
	if row.is_empty():
		return false
	size = p_size
	kv = _nearest(cfg.kv_options(size), kv)
	poles = int(row.get("poles", poles))
	var shafts := cfg.shaft_options(size)
	if not shafts.is_empty():
		shaft_mm = float(shafts[0])
	var mounts := cfg.mount_options(size)
	if not mounts.is_empty():
		mount = String(mounts[0])
	return true


## One size up or down the grid (dir +1 / -1); stops at the ends.
func step_size(cfg: MotorConfigs, dir: int) -> bool:
	var names := cfg.size_names()
	var i := names.find(size)
	var j := clampi(i + dir, 0, names.size() - 1)
	if i < 0 or j == i:
		return false
	return set_size(cfg, names[j])


func set_kv(cfg: MotorConfigs, p_kv: float) -> bool:
	for o in cfg.kv_options(size):
		if is_equal_approx(float(o), p_kv):
			kv = float(o)
			return true
	return false


func set_poles(p_poles: int) -> bool:
	if not MotorConfigs.POLE_CONFIGS.has(p_poles):
		return false
	poles = p_poles
	return true


func set_magnet(cfg: MotorConfigs, grade: String) -> bool:
	if is_nan(cfg.magnet_max_c(grade)):
		return false
	magnet = grade
	return true


func set_shaft(cfg: MotorConfigs, mm: float) -> bool:
	for o in cfg.shaft_options(size):
		if is_equal_approx(float(o), mm):
			shaft_mm = float(o)
			return true
	return false


func set_mount(cfg: MotorConfigs, pattern: String) -> bool:
	if not cfg.mount_options(size).has(pattern):
		return false
	mount = pattern
	return true


func config() -> String:
	return String(MotorConfigs.POLE_CONFIGS.get(poles, ""))


## "2207 1960KV": the name a motor gets until the builder types one.
func default_name() -> String:
	return "%s %dKV" % [size, int(kv)]


func display_name() -> String:
	return name if name.strip_edges() != "" else default_name()


## Every figure the designer shows, from the grid laws. Keys: kv, kt, rm_ohm, io_a, io_voltage_v,
## mass_g, max_current_a, max_power_w, max_cells, magnet_max_c, poles, config, size, and the
## stator dimensions. {} if the size is not on the grid.
func derive(cfg: MotorConfigs) -> Dictionary:
	var f := cfg.derive(size, kv, poles)
	if f.is_empty():
		return {}
	var row := cfg.get_size(size)
	f["mass_g"] = float(f["mass_g"]) + cfg.shaft_mass_delta_g(size, shaft_mm)
	f["magnet"] = magnet
	f["magnet_max_c"] = cfg.magnet_max_c(magnet)
	f["shaft_mm"] = shaft_mm
	f["mount"] = mount
	f["stator_diameter_mm"] = float(row.stator_diameter_mm)
	f["stator_height_mm"] = float(row.stator_height_mm)
	return f


## How each figure was arrived at: "set" (the builder chose it), "model" (follows exactly from a
## set figure), "est." (a class formula), "grade rating" (the magnet grade's published limit).
static func figure_tags() -> Dictionary:
	return {
		"kv": "set",
		"kt": "model",
		"rm_ohm": "est.",
		"io_a": "est.",
		"mass_g": "est.",
		"max_current_a": "est.",
		"max_power_w": "est.",
		"magnet_max_c": "grade rating",
	}


## A catalog-shaped record (the shape data/parts/motors.json uses), so MotorMesh and, later, the
## shelf and the drone read the designed motor exactly as they read a preset.
func to_record(cfg: MotorConfigs) -> Dictionary:
	var f := derive(cfg)
	if f.is_empty():
		return {}
	return {
		"part_id": "",
		"name": display_name(),
		"category": "motor",
		"mass_g": f["mass_g"],
		"mount_pattern": mount,
		"specs": {
			"kv": kv,
			"stator_diameter_mm": f["stator_diameter_mm"],
			"stator_height_mm": f["stator_height_mm"],
			"poles": poles,
			"config": config(),
			"max_amps": f["max_current_a"],
			"rm_ohm": f["rm_ohm"],
			"io_a": f["io_a"],
			"io_voltage_v": f["io_voltage_v"],
			"rm_io_basis": "est.",
			"current_model": "dc",
			"magnet": magnet,
			"magnet_max_c": f["magnet_max_c"],
			"shaft_mm": shaft_mm,
		},
	}


## The prop diameter (inches) a motor of this stator diameter usually turns: what the 3D view
## puts on the shaft until the Prop picker exists. Class-typical, for the picture only.
static func usual_prop_inches(stator_diameter_mm: float) -> float:
	if stator_diameter_mm <= 9.0:
		return 1.6
	if stator_diameter_mm <= 12.0:
		return 2.5
	if stator_diameter_mm <= 14.0:
		return 3.0
	if stator_diameter_mm <= 16.0:
		return 3.5
	if stator_diameter_mm <= 20.0:
		return 4.0
	if stator_diameter_mm <= 25.0:
		return 5.0
	if stator_diameter_mm <= 28.0:
		return 7.0
	return 10.0


static func _nearest(options: Array, value: float) -> float:
	if options.is_empty():
		return value
	var best := float(options[0])
	for o in options:
		if absf(float(o) - value) < absf(best - value):
			best = float(o)
	return best
