class_name PropPresetFigures
extends RefCounted
## The flight and aero figures of every shelf propeller, computed live, for the Prop Designer's pin
## (tests/test_prop_pin.gd compares them with tests/fixtures/prop_preset_figures.json, which was
## snapshotted from `dev` at d5cc617, before any prop-designer code existed).
##
## Regenerate only when a slice's tracker entry says figures may move, and log it there:
##   godot --headless --script res://tools/snapshot_prop_pin.gd
##
## Values are stored twice: readable, and as the hex of the IEEE double. The hex is what a macOS run
## compares, because PD2's promise is "bit-identical", and 15 printed digits cannot see one ulp.

const FIXTURE := "res://tests/fixtures/prop_preset_figures.json"

## Each prop on the drone class it belongs to. A class's own seed prop flies on that seed; the others
## take the class of their size. A table, not a nearest-diameter rule, so that adding a class later
## cannot silently move a prop to a different aircraft and read as a physics change.
const REFERENCE_CLASS := {
	"prop_16x12x4": "tiny_whoop",
	"prop_25x25x4": "toothpick",
	"prop_3x3x3": "cinewhoop_3",
	"prop_35x28x3": "sub250_35",
	"prop_4x25x3": "four_inch",
	"prop_5x43x2": "five_inch",
	"prop_5x43x3": "five_inch",
	"prop_5x45x3": "five_inch",
	"prop_5x46x3": "five_inch",
	"prop_5x48x3": "five_inch",
	"prop_5x5x2": "five_inch",
	"prop_nazgul_f5_51x35x3": "five_inch",
	"prop_hq_ethix_s5_5x4x3": "five_inch",
	"prop_gemfan_vannystyle_5136x3": "five_inch",
	"prop_6x4x2": "six_inch",
	"prop_6x45x3": "six_inch",
	"prop_7x35x2": "seven_lr",
	"prop_7x4x3": "seven_lr",
	"prop_8x45x3": "cinelifter",
	"prop_10x5x2": "x_class",
}

## Where on the forward surface the ratios are read: [mu_axial, mu_edge]. Axial-only points are where
## twist shows; the mixed one covers the edgewise branch of the closure.
const MU_POINTS := [[0.05, 0.0], [0.1, 0.0], [0.2, 0.0], [0.3, 0.0], [0.1, 0.1], [0.0, 0.2]]
const RATIO_RPM := 20000.0
## The direct forward solve, read at one axial and one edgewise point, so a change on the solve path
## that the bilinear table would smooth over is still seen.
const DIRECT_MU_AXIAL := 0.15
const DIRECT_MU_EDGE := 0.15


static func figures_of(prop_id: String, catalog: PartsCatalog) -> Dictionary:
	var p := DroneClass.parts_for(String(REFERENCE_CLASS[prop_id]))
	var b := Build.from_ids(catalog, String(p["frame"]), String(p["motor"]), prop_id,
		String(p["battery"]), String(p["esc"]), String(p["flight_controller"]))
	var doc := PropellerDocument.from_catalog_prop(catalog.get_part(prop_id))
	var g := b.prop_geometry()
	var omega_r: float = RATIO_RPM * TAU / 60.0 * g.diameter_m * 0.5
	var out := {
		"k_t": b.k_t,
		"k_q": b.k_q,
		"static_k_t": doc.static_k_t(),
		"figure_of_merit": doc.static_figure_of_merit(),
		"torque_to_thrust_m": doc.torque_to_thrust_m(),
		"auw_g": b.all_up_weight_g(),
		"thrust_to_weight": b.thrust_to_weight(),
		"hover_throttle": b.hover_throttle(),
		"flight_time_min": b.flight_time_min(),
		"top_speed_kmh": b.top_speed_kmh(),
	}
	var ratios := b.forward_ratios()
	for mu in MU_POINTS:
		var tag := "%.2f_%.2f" % [mu[0], mu[1]]
		out["thrust_ratio_" + tag] = ratios.thrust_ratio(RATIO_RPM, mu[0] * omega_r, mu[1] * omega_r)
		out["power_ratio_" + tag] = ratios.power_ratio(RATIO_RPM, mu[0] * omega_r, mu[1] * omega_r)
	var polar := BemtModel.global_polar()
	var ax := BemtModel.solve_forward(1.225, g.diameter_m, g.pitch_m, g.blades, RATIO_RPM, doc.chord,
		polar[0], polar[1], polar[2], polar[3], DIRECT_MU_AXIAL * omega_r, 0.0)
	var ed := BemtModel.solve_forward(1.225, g.diameter_m, g.pitch_m, g.blades, RATIO_RPM, doc.chord,
		polar[0], polar[1], polar[2], polar[3], 0.0, DIRECT_MU_EDGE * omega_r)
	out["direct_axial_thrust_n"] = ax[0]
	out["direct_axial_torque_nm"] = ax[1]
	out["direct_edge_thrust_n"] = ed[0]
	out["direct_edge_torque_nm"] = ed[1]
	return out


static func bits_of(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()


## Shelf ids from the file on disk rather than the table above, so a prop added to the shelf and not
## to the pin is a failure and not a gap.
static func shelf_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw in JsonStore.read_document("res://data/parts/propellers.json").get("parts", []):
		ids.append(String(raw["part_id"]))
	return ids


static func snapshot() -> Dictionary:
	var catalog := PartsCatalog.load_default()
	var out := {}
	for id in shelf_ids():
		var figures := figures_of(id, catalog)
		var bits := {}
		for k in figures:
			bits[k] = bits_of(float(figures[k]))
		out[id] = {"class": REFERENCE_CLASS[id], "figures": figures, "bits": bits}
	return out
