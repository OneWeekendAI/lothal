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


## A starting design shaped like a catalog motor: the grid size nearest its stator, its KV, and the
## mount option that has its bolt pattern (a motor that does not fit the frame is no starting point).
## A start the builder changes, never a claim that the grid motor IS that motor.
static func like(rec: Dictionary, cfg: MotorConfigs) -> MotorDesign:
	var d := from_record(rec, cfg)
	var want := String(rec.get("mount_pattern", ""))
	for o in cfg.mount_options(d.size):
		if catalog_mount(String(o)) == want:
			d.mount = String(o)
			break
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
		"mount_pattern": catalog_mount(mount),
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
			"magnet": magnet,
			"magnet_max_c": f["magnet_max_c"],
			"shaft_mm": shaft_mm,
		},
	}


## A grid mount option ("16 x 16 mm, M3") in the spelling the catalog and the frames use ("16x16"),
## which is what Build's motor-fit warning compares. A whoop's single hole circle ("6.6 mm, M1.4")
## is the catalog's "6x6", the pattern the 0802 preset and the whoop frames carry.
static func catalog_mount(option: String) -> String:
	var head := option.split("mm")[0]
	var nums: Array = []
	for part in head.split("x"):
		if part.strip_edges().is_valid_float():
			nums.append(int(float(part.strip_edges())))
	if nums.size() == 2:
		return "%dx%d" % [nums[0], nums[1]]
	if nums.size() == 1:
		return "%dx%d" % [nums[0], nums[0]]
	return option


## The record a saved motor is stored and flown as: to_record() plus everything the drone needs
## (a thrust test, a max thrust), the choices that reopen it in the designer, and the derived
## figures as saved. {} off the grid or with no shelf preset to borrow a test prop from.
##
## THE THRUST TEST IS A MODEL FIGURE, NOT A BENCH ONE. The drone fits its thrust coefficient from
## "this motor, this prop, this voltage, flat out" (Build.fit_rated_point). A designed motor has no
## table, so it borrows the test prop and voltage of the nearest shelf preset (stator diameter, then
## height, then KV) and that prop's fitted k_t: the prop's aerodynamics do not depend on which
## motor turns it. Its max thrust is then that k_t at the rpm THIS motor reaches on that prop at that
## voltage (the DC operating point), so the drone's own fit lands back on the same k_t, and every
## figure the drone shows comes from this motor's Kv/Rm/Io. Labelled ideal / model, like the rest.
func drone_record(cfg: MotorConfigs, catalog: PartsCatalog) -> Dictionary:
	var rec := to_record(cfg)
	if rec.is_empty():
		return {}
	var f := derive(cfg)
	var ref := reference_preset(catalog, float(f.stator_diameter_mm), float(f.stator_height_mm), kv)
	if ref.is_empty():
		return {}
	var test: Dictionary = ref["thrust_test"]
	var test_prop := catalog.get_part(String(test["prop_id"]))
	if test_prop.is_empty():
		return {}
	var v := float(test["voltage_v"])
	var k_t := float(Build.fit_rated_point(ref, test_prop)["k_t"])
	var k_q := PropellerModel.fit_k_q(k_t, PropellerDocument.from_catalog_prop(test_prop).torque_to_thrust_m())
	var op := MotorModel.operating_point(v, kv, float(f.rm_ohm), float(f.io_a), float(f.io_voltage_v), k_q)
	var rpm := float(op["rpm"])
	if rpm <= 0.0:
		return {}
	var specs: Dictionary = rec["specs"]
	specs["max_thrust_g"] = k_t / PropellerModel.fit_k_t(1.0, rpm)
	rec["thrust_test"] = {"prop_id": String(test["prop_id"]), "voltage_v": v}
	rec["catalog"] = {
		"stator_class": CustomMotors.stator_class_for(float(f.stator_diameter_mm)),
		"kv_class": CustomMotors.kv_class_for(kv),
		"intended_use": "designed",
	}
	rec["source"] = "Motor Designer: %s, %s figures; thrust on the %s test prop at %s V (model)" % [
		default_name(), BASIS, String(test_prop.get("name", test["prop_id"])), str(v)]
	rec["design"] = {
		"size": size,
		"kv": kv,
		"poles": poles,
		"magnet": magnet,
		"shaft_mm": shaft_mm,
		"mount": mount,
		"basis": BASIS,
		"thrust_reference": String(ref["part_id"]),
	}
	rec["figures"] = f
	return rec


## The choices of a saved record, ready to edit. A designed record reopens exactly; a migrated
## hand-typed one opens on the nearest grid point (size by stator diameter then height, then the nearest KV sold for it).
static func from_record(rec: Dictionary, cfg: MotorConfigs) -> MotorDesign:
	var d := default_design(cfg)
	d.name = String(rec.get("name", ""))
	var block: Dictionary = rec.get("design", {}) if rec.get("design") is Dictionary else {}
	if not CustomMotors.is_legacy(rec) and not cfg.get_size(String(block.get("size", ""))).is_empty():
		d.size = String(block["size"])
		d.kv = float(block.get("kv", d.kv))
		d.poles = int(block.get("poles", d.poles))
		d.magnet = String(block.get("magnet", d.magnet))
		d.shaft_mm = float(block.get("shaft_mm", d.shaft_mm))
		d.mount = String(block.get("mount", d.mount))
		return d
	var sp: Dictionary = rec.get("specs", {})
	var want := Vector2(float(sp.get("stator_diameter_mm", 0.0)), float(sp.get("stator_height_mm", 0.0)))
	var best := ""
	var best_d := INF
	for n in cfg.size_names():
		var row := cfg.get_size(n)
		# Diameter first (it sets the bell and the mount), then height.
		var dist := absf(float(row.stator_diameter_mm) - want.x) * 1000.0 + absf(float(row.stator_height_mm) - want.y)
		if dist < best_d:
			best_d = dist
			best = n
	d.kv = float(sp.get("kv", d.kv))
	d.size = ""
	d.set_size(cfg, best)
	return d


## The shelf preset nearest a stator and KV: diameter first, then height, then KV (log distance).
## Custom parts never count: a designed motor's thrust must not rest on another typed figure.
static func reference_preset(catalog: PartsCatalog, diameter_mm: float, height_mm: float, p_kv: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for m in catalog.list_category("motor"):
		if PartsCatalog.is_custom(String(m.get("part_id", ""))) or not m.has("thrust_test"):
			continue
		var sp: Dictionary = m.get("specs", {})
		var score := absf(float(sp.get("stator_diameter_mm", 0.0)) - diameter_mm) * 1.0e6 \
			+ absf(float(sp.get("stator_height_mm", 0.0)) - height_mm) * 1.0e3 \
			+ absf(log(maxf(float(sp.get("kv", 1.0)), 1.0) / maxf(p_kv, 1.0)))
		if score < best_score:
			best_score = score
			best = m
	return best


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
