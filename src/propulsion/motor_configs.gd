class_name MotorConfigs
extends RefCounted
## The standard motor configuration grid (data/motors/standard_configs.json) and the formulas
## that turn one grid point (size, KV) into Rm, Io, Kt, mass, thermal masses and current limits.
## Every coefficient is an estimate and labelled so in the file; every figure here is an
## ideal / model figure, never a measurement. The electrical model that consumes them is
## MotorModel (Rust).

const DEFAULT_PATH := "res://data/motors/standard_configs.json"

var _sizes: Array = []
var _coef: Dictionary = {}


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


## Every derived figure for one grid point. Returns {} for a size not on the grid or a KV <= 0.
## All of rm/io/mass/limits carry basis "est." (the key `basis`).
func derive(size: String, kv: float) -> Dictionary:
	var s := get_size(size)
	if s.is_empty() or kv <= 0.0:
		return {}
	var vol := stator_volume_cm3(float(s.stator_diameter_mm), float(s.stator_height_mm))
	var rm := coefficient("rm_c") / (pow(vol, 5.0 / 3.0) * kv * kv)
	var io_v := float(s.io_voltage_v)
	var io := coefficient("io_k") * vol * (kv * io_v / 10000.0)
	var mass := coefficient("mass_base_g") + coefficient("mass_per_cm3_g") * vol
	var loss_w := coefficient("loss_w_per_g23") * pow(mass, 2.0 / 3.0)
	var i_max := sqrt(loss_w / rm)
	var cells := int(s.max_cells)
	return {
		"size": size,
		"kv": kv,
		"config": String(s.config),
		"poles": int(s.poles),
		"stator_volume_cm3": vol,
		"kt": MotorModel.kt(kv),
		"rm_ohm": rm,
		"io_a": io,
		"io_voltage_v": io_v,
		"mass_g": mass,
		"copper_g": mass * coefficient("copper_mass_fraction"),
		"stator_g": mass * coefficient("stator_mass_fraction"),
		"max_continuous_loss_w": loss_w,
		"max_current_a": i_max,
		"max_cells": cells,
		"max_power_w": i_max * cells * coefficient("nominal_cell_v"),
		"basis": "est.",
	}
