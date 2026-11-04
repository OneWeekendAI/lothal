class_name MotorConfigs
extends RefCounted
## The standard motor configuration grid (data/motors/standard_configs.json) and the formulas
## that turn one grid point (size, KV) into Rm, Io, Kt, mass, thermal masses and current limits.
## Every coefficient is an estimate and labelled so in the file; every figure here is an
## ideal / model figure, never a measurement. The electrical model that consumes them is
## MotorModel (Rust).

const DEFAULT_PATH := "res://data/motors/standard_configs.json"
## The two slot/pole configurations in the grid, by magnet pole count.
const POLE_CONFIGS := {12: "9N12P", 14: "12N14P"}

var _sizes: Array = []
var _coef: Dictionary = {}
var _magnets: Array = []


static func load_default() -> MotorConfigs:
	var cfg := MotorConfigs.new()
	var doc := JsonStore.read_document(DEFAULT_PATH)
	var raw: Variant = doc.get("sizes", [])
	if raw is Array:
		for s in (raw as Array):
			if s is Dictionary:
				cfg._sizes.append(s)
	var c: Variant = doc.get("coefficients", {})
	if c is Dictionary:
		cfg._coef = c
	var mags: Variant = doc.get("magnets", [])
	if mags is Array:
		cfg._magnets = mags
	return cfg


func sizes() -> Array:
	return _sizes


func size_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _sizes:
		out.append(String(s.get("size", "")))
	return out


func get_size(size: String) -> Dictionary:
	for s in _sizes:
		if String(s.get("size", "")) == size:
			return s
	return {}


func kv_options(size: String) -> Array:
	return get_size(size).get("kv_options", [])


func coefficient(name: String) -> float:
	return float(_coef.get(name, {}).get("value", 0.0))


## Stator volume in cm3: pi/4 * D^2 * H (mm -> cm3).
static func stator_volume_cm3(diameter_mm: float, height_mm: float) -> float:
	return PI / 4.0 * diameter_mm * diameter_mm * height_mm / 1000.0


## Winding resistance (ohm) from stator volume and KV. The one place the law lives: the grid, and
## the shelf presets in data/parts/motors.json (M3), both read it.
func rm_for(volume_cm3: float, kv: float) -> float:
	return coefficient("rm_c") / (pow(volume_cm3, 5.0 / 3.0) * kv * kv)


## No-load current (A) at `io_voltage_v` from stator volume and KV.
func io_for(volume_cm3: float, kv: float, io_voltage_v: float) -> float:
	return coefficient("io_k") * volume_cm3 * (kv * io_voltage_v / 10000.0)


## Rm and Io for a stator that need not be on the grid (a shelf 2506, 2807, 1507...): the same
## laws, taken from the stator's own dimensions. est. like everything here.
func derive_stator(diameter_mm: float, height_mm: float, kv: float, io_voltage_v: float) -> Dictionary:
	if diameter_mm <= 0.0 or height_mm <= 0.0 or kv <= 0.0 or io_voltage_v <= 0.0:
		return {}
	var vol := stator_volume_cm3(diameter_mm, height_mm)
	return {
		"stator_volume_cm3": vol,
		"rm_ohm": rm_for(vol, kv),
		"io_a": io_for(vol, kv, io_voltage_v),
		"io_voltage_v": io_voltage_v,
		"basis": "est.",
	}


## The shaft diameters (mm) offered for a size; the first is the size's usual one.
func shaft_options(size: String) -> Array:
	return get_size(size).get("shaft_mm_options", [])


## The mount patterns offered for a size; the first is the size's usual one.
func mount_options(size: String) -> Array:
	return get_size(size).get("mount_options", [])


## The magnet grades on offer: [{grade, max_c, basis, note}].
func magnets() -> Array:
	return _magnets


## The highest working temperature (C) of a magnet grade; NAN for an unknown grade.
func magnet_max_c(grade: String) -> float:
	for m in _magnets:
		if String(m.get("grade", "")) == grade:
			return float(m.get("max_c", NAN))
	return NAN


## Grams a shaft of `shaft_mm` adds over the size's usual shaft (negative when thinner): steel,
## running the bell's height plus 8 mm. est. The usual shaft is already inside mass_base_g.
func shaft_mass_delta_g(size: String, shaft_mm: float) -> float:
	var opts := shaft_options(size)
	var s := get_size(size)
	if opts.is_empty() or s.is_empty() or shaft_mm <= 0.0:
		return 0.0
	var d0 := float(opts[0])
	var length_mm := float(s.stator_height_mm) * MotorMesh.bell_height_ratio({}) + 8.0
	var vol_cm3 := PI / 4.0 * (shaft_mm * shaft_mm - d0 * d0) * length_mm / 1000.0
	return coefficient("shaft_density_g_cm3") * vol_cm3


## Every derived figure for one grid point. Returns {} for a size not on the grid or a KV <= 0.
## All of rm/io/mass/limits carry basis "est." (the key `basis`). `poles` other than the size's
## usual count scales Io by (poles / usual)^io_pole_exponent (iron loss follows electrical
## frequency); 0 means the size's usual poles.
func derive(size: String, kv: float, poles: int = 0) -> Dictionary:
	var s := get_size(size)
	if s.is_empty() or kv <= 0.0:
		return {}
	var vol := stator_volume_cm3(float(s.stator_diameter_mm), float(s.stator_height_mm))
	var io_v := float(s.io_voltage_v)
	var rm := rm_for(vol, kv)
	var usual_poles := int(s.poles)
	var p := poles if poles > 0 else usual_poles
	var io := io_for(vol, kv, io_v) * pow(float(p) / float(usual_poles), coefficient("io_pole_exponent"))
	var mass := coefficient("mass_base_g") + coefficient("mass_per_cm3_g") * vol
	var loss_w := coefficient("loss_w_per_g23") * pow(mass, 2.0 / 3.0)
	var i_max := sqrt(loss_w / rm)
	var cells := int(s.max_cells)
	return {
		"size": size,
		"kv": kv,
		"config": String(s.config) if p == usual_poles else String(POLE_CONFIGS.get(p, s.config)),
		"poles": p,
		"stator_volume_cm3": vol,
		"kt": MotorModel.kt(kv),
		"rm_ohm": rm,
		"io_a": io,
		"io_voltage_v": io_v,
		"mass_g": mass,
		"copper_g": mass * coefficient("copper_mass_fraction"),
		"stator_g": mass * coefficient("stator_mass_fraction"),
		"bell_g": mass * coefficient("bell_mass_fraction"),
		"max_continuous_loss_w": loss_w,
		"max_current_a": i_max,
		"max_cells": cells,
		"max_power_w": i_max * cells * coefficient("nominal_cell_v"),
		"basis": "est.",
	}
