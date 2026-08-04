class_name TestLab
extends RefCounted
## Lab's shell, its frame picker and the live reaction between them — the first vertical
## slice of Lothal Labs (labs-and-sim.md).
##
## Two things here are worth more than the rest. First, that Lab costs nothing: the whole
## point of the Lab/Sim split is that choosing a frame does not run a 1 kHz integrator, a
## renderer and a real-time audio synthesiser, and the honest way to check that is an
## ABSENCE — the sim scene must not exist as a node while Lab is showing, rather than
## existing with a flag turned off. Second, that one selection change moves the geometry,
## the details panel and the derived stats TOGETHER; the failure this project has already
## been bitten by is a panel that quietly keeps a stale value while everything else moves.
##
## Filter assertions are written data-driven on purpose. They read the filter options the
## picker derived from frames.json rather than naming "long-range" or "5\"" in the test, so
## the suite keeps testing the real behaviour as the catalog grows instead of pinning it to
## today's twelve entries.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_shell_lifecycle())
	results.append_array(_test_filters(catalog))
	results.append_array(_test_live_reaction(catalog))
	results.append_array(_test_powertrain_rails(catalog))
	results.append_array(_test_the_build_crosses_into_sim(catalog))
	results.append_array(_test_orbit(catalog))

	return results


# ---------------------------------------------------------------------------
# The boundary: Lab decides how the drone looks in the field
# ---------------------------------------------------------------------------

## labs-and-sim.md §3: "Everything you saw in Lab is what you fly." Before this, main.tscn
## hardcoded the drone as a box plus four cylinders with the 5" arm's motor positions baked in
## as 0.0778 and no propellers at all — so choosing the 7" frame put the physics on a 150 mm arm
## while the visual stayed a 5" prop-less box.
##
## The end-to-end claim is checked in three synchronous pieces rather than by booting the flight
## scene, because Sim builds its airframe in _ready and _ready needs a processed frame, which
## this runner deliberately does not have (it does all its work from _init so a hung suite names
## itself). So: the selection crosses the door; the scene file authors no airframe for a stale
## one to hide in; and AirframeModel renders that selection correctly — the third being what
## tests/test_airframe_model.gd covers in full. The composed result is then looked at with
## tests/capture_frame.gd, which does boot the scene.
static func _test_the_build_crosses_into_sim(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.lab.picker.select_id("frame_7in_long_range")
	shell.lab.motor_picker.select_id("motor_2807_1300kv")
	shell.lab.propeller_picker.select_id("prop_7x35x2")
	shell.show_sim()

	var handed: Dictionary = shell.sim.initial_selection
	results.append(TestResult.new(
		"the parts chosen in Lab are handed to Sim on the way through the door",
		handed.get("frame", "") == "frame_7in_long_range"
			and handed.get("motor", "") == "motor_2807_1300kv"
			and handed.get("propeller", "") == "prop_7x35x2",
		"Sim was handed %s" % handed
	))

	# ...and it must be handed over BEFORE the scene is in the tree, or the flight scene spends
	# its first frame on a different aircraft and then rebuilds.
	results.append(TestResult.new(
		"the hand-over lands before Sim is ever in the tree",
		not shell.sim.is_inside_tree() and not handed.is_empty(),
		"sim inside tree at hand-over: %s" % shell.sim.is_inside_tree()
	))

	# Walking back to the garage, choosing a 5" and going out again must hand over the 5".
	shell.show_lab()
	shell.lab.picker.select_id("frame_5in_freestyle")
	shell.lab.propeller_picker.select_id("prop_5x43x3")
	shell.show_sim()
	var second: Dictionary = shell.sim.initial_selection
	results.append(TestResult.new(
		"a second trip out hands over the build as it stands then, not the first one",
		second.get("frame", "") == "frame_5in_freestyle"
			and second.get("propeller", "") == "prop_5x43x3"
			and second.get("motor", "") == "motor_2807_1300kv",
		"second trip handed %s" % second
	))
	shell.free()

	# The scene file must author NO airframe. This is the structural half of "the visual cannot
	# disagree with the physics": if there is no box and no cylinders in main.tscn, there is
	# nothing for a stale 110 mm arm to be baked into. Before this slice, Drone had five
	# authored children — a frame box and four motor cylinders at +/-0.0778.
	var scene: Node = load(AppShell.SIM_SCENE).instantiate()
	var drone: Node = scene.get_node("Drone")
	var authored_meshes := 0
	for child in drone.get_children():
		if child is MeshInstance3D:
			authored_meshes += 1
	var authored_children := drone.get_child_count()
	scene.free()

	results.append(TestResult.new(
		"main.tscn authors no airframe, so there is nothing for a baked arm to hide in",
		authored_children == 0 and authored_meshes == 0,
		"Drone has %d authored children (%d of them meshes); it used to have 5" % [
			authored_children, authored_meshes]
	))

	# And the geometry that Sim will generate from that hand-over is the 7" one. Built here from
	# the ids that crossed, so this fails if the door hands over something the airframe cannot
	# render as asked.
	var flown := Build.from_ids(catalog, "frame_7in_long_range", "motor_2807_1300kv",
		"prop_7x35x2", ReferenceBuild.BATTERY_ID)
	var airframe := AirframeModel.new()
	airframe.rebuild(flown)
	var reach := _airframe_reach(airframe)
	var prop_radius: float = (airframe.propeller_meshes["M1"] as PropellerMesh).radius_m
	var prop_count: int = airframe.propeller_meshes.size()
	airframe.free()

	# The old scene's baked figure, named so a regression to it is recognisable rather than
	# merely being some number that is wrong.
	var baked_in := 0.0778 * sqrt(2.0)
	results.append(TestResult.new(
		"the handed-over build renders a 7\" airframe with its four propellers",
		absf(reach - 0.150) < 0.001 and prop_count == 4
			and absf(prop_radius - 0.0889) < 0.001 and absf(reach - baked_in) > 0.01,
		"arm %.3f m (baked was %.3f m), %d props of radius %.4f m" % [
			reach, baked_in, prop_count, prop_radius]
	))

	return results


## Arm length as measured from generated geometry: the horizontal distance from the drone's
## centre to a motor, read through the transform chain rather than from any field.
static func _airframe_reach(airframe: AirframeModel) -> float:
	var motor: Node3D = airframe.motor_meshes["M1"]
	var origin: Vector3 = TestAirframeModel._chain_to(airframe, motor).origin
	return Vector2(origin.x, origin.z).length()


# ---------------------------------------------------------------------------
# The inspection orbit
# ---------------------------------------------------------------------------

## Lab has to be able to show the underside of a build, not just spin it about the vertical.
## A battery tray, a payload mount and the bottom plate all live under the frame, and a
## yaw-only turntable can never point the camera at any of them.
##
## The invariant guarded hardest here is the ORBIT DISTANCE. Lab deliberately never zooms —
## the camera sits at one distance chosen from the largest frame in the catalog so that a
## 65 mm whoop looks tiny beside a 10", which is the whole reason the size comparison is
## trustworthy. An orbit that let the radius drift would quietly destroy that, and it would
## do it invisibly, because the picture would still look fine.
static func _test_orbit(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog)
	var radius := lab.camera_world_transform().origin.length()

	lab.set_orbit(0.0, deg_to_rad(60.0))
	var above := lab.camera_world_transform().origin
	lab.set_orbit(0.0, deg_to_rad(-60.0))
	var below := lab.camera_world_transform().origin

	results.append(TestResult.new(
		"elevating the orbit looks down at the top plate; dropping it looks up at the underside",
		above.y > radius * 0.5 and below.y < -radius * 0.5,
		"camera y at +60 deg = %.3f, at -60 deg = %.3f (radius %.3f)" % [above.y, below.y, radius]
	))

	lab.set_orbit(deg_to_rad(90.0), 0.0)
	var side := lab.camera_world_transform().origin
	results.append(TestResult.new(
		"swinging the azimuth moves the camera around the airframe",
		absf(side.x) > radius * 0.9 and absf(side.z) < radius * 0.1,
		"camera at 90 deg azimuth = (%.3f, %.3f, %.3f)" % [side.x, side.y, side.z]
	))

	# Past the poles the rig must stop rather than flip over, which is where a naive orbit
	# turns the airframe upside down and loses which way is up.
	lab.set_orbit(0.0, deg_to_rad(200.0))
	var over_the_top := lab.elevation_deg()
	lab.set_orbit(0.0, deg_to_rad(-200.0))
	var under_the_bottom := lab.elevation_deg()
	results.append(TestResult.new(
		"elevation is clamped short of the poles instead of flipping the airframe over",
		absf(over_the_top) <= LabScreen.ELEVATION_LIMIT_DEG + 0.01
			and absf(under_the_bottom) <= LabScreen.ELEVATION_LIMIT_DEG + 0.01
			and over_the_top > 0.0 and under_the_bottom < 0.0,
		"asking for +200/-200 deg gave %.1f / %.1f (limit %.1f)" % [
			over_the_top, under_the_bottom, LabScreen.ELEVATION_LIMIT_DEG]
	))

	# Sweep the whole rig and require the two things that make the view honest at every angle:
	# the distance never changes, and the camera never stops pointing at the airframe.
	var distance_held := true
	var stays_aimed := true
	var worst_distance := 0.0
	var worst_aim := 0.0
	for azimuth_step in 12:
		for elevation_step in 9:
			var azimuth := deg_to_rad(azimuth_step * 30.0)
			var elevation := deg_to_rad(-80.0 + elevation_step * 20.0)
			lab.set_orbit(azimuth, elevation)
			var transform := lab.camera_world_transform()

			worst_distance = maxf(worst_distance, absf(transform.origin.length() - radius))
			if absf(transform.origin.length() - radius) > 0.0001:
				distance_held = false

			# The camera's own forward is -Z; from `origin` it must point back at the airframe.
			var to_origin := (-transform.origin).normalized()
			var forward := -transform.basis.z.normalized()
			worst_aim = maxf(worst_aim, forward.angle_to(to_origin))
			if forward.angle_to(to_origin) > 0.001:
				stays_aimed = false

	results.append(TestResult.new(
		"the orbit never zooms, so frames stay comparable at every angle",
		distance_held,
		"worst radius drift over 108 angles = %.6f m (radius %.3f)" % [worst_distance, radius]
	))

	results.append(TestResult.new(
		"the camera stays aimed at the airframe through the whole orbit",
		stays_aimed,
		"worst aim error over 108 angles = %.4f deg" % rad_to_deg(worst_aim)
	))

	# Taking hold of the view has to stick. The idle orbit originally kept running after a
	# drag and overwrote the chosen angle on the very next frame, which made it impossible to
	# sit and look at one thing — the exact job an underside view exists for.
	lab.orbit_by(deg_to_rad(40.0), deg_to_rad(-50.0))
	var chosen_azimuth := lab.azimuth_deg()
	var chosen_elevation := lab.elevation_deg()
	for _frame in 30:
		lab._process(1.0 / 60.0)
	results.append(TestResult.new(
		"an angle chosen by hand survives the frames that follow it",
		not lab.auto_orbit
			and is_equal_approx(lab.azimuth_deg(), chosen_azimuth)
			and is_equal_approx(lab.elevation_deg(), chosen_elevation),
		"held %.1f/%.1f deg -> %.1f/%.1f after half a second (auto_orbit=%s)" % [
			chosen_azimuth, chosen_elevation, lab.azimuth_deg(), lab.elevation_deg(), lab.auto_orbit]
	))

	# ...while an untouched Lab still drifts, which is what makes the airframe read as solid.
	var idle := LabScreen.new(catalog)
	var idle_azimuth := idle.azimuth_deg()
	var idle_elevation := idle.elevation_deg()
	for _frame in 30:
		idle._process(1.0 / 60.0)
	results.append(TestResult.new(
		"an untouched Lab keeps drifting on both angles",
		absf(idle.azimuth_deg() - idle_azimuth) > 0.5
			and absf(idle.elevation_deg() - idle_elevation) > 0.5,
		"drifted %.1f deg azimuth and %.1f deg elevation in half a second" % [
			idle.azimuth_deg() - idle_azimuth, idle.elevation_deg() - idle_elevation]
	))
	idle.free()

	lab.free()
	return results


# ---------------------------------------------------------------------------
# Deliverable 1 — the Lab | Sim shell
# ---------------------------------------------------------------------------

static func _test_shell_lifecycle() -> Array:
	var results: Array = []
	var shell := AppShell.new()

	results.append(TestResult.new(
		"the app opens on Lab, with no sim instantiated at all",
		shell.lab != null and shell.sim == null and shell.showing_lab(),
		"lab=%s sim=%s showing_lab=%s" % [shell.lab != null, shell.sim, shell.showing_lab()]
	))

	shell.show_sim()
	var sim_ref := shell.sim

	results.append(TestResult.new(
		"entering the Sim tab instantiates the existing flight scene",
		sim_ref != null and not shell.showing_lab() and not shell.lab.visible,
		"sim=%s showing_lab=%s lab.visible=%s" % [
			sim_ref, shell.showing_lab(), shell.lab.visible]
	))

	var lab_before: int = shell.lab.get_instance_id()
	shell.show_lab()

	# The strong form of "leaving Sim stops the flight loop": the node is gone, so there is
	# no integrator, no DroneAudio and no chase camera left to run. A boolean could lie
	# about this; a freed instance cannot.
	results.append(TestResult.new(
		"leaving Sim frees it, so no flight loop survives into Lab",
		shell.sim == null and not is_instance_valid(sim_ref) and shell.showing_lab(),
		"sim=%s still_valid=%s" % [shell.sim, is_instance_valid(sim_ref)]
	))

	results.append(TestResult.new(
		"Lab itself persists across a round trip, so the chosen frame is still chosen",
		shell.lab != null and shell.lab.get_instance_id() == lab_before and shell.lab.visible,
		"lab instance %d -> %d" % [lab_before, shell.lab.get_instance_id() if shell.lab else -1]
	))

	shell.free()
	return results


# ---------------------------------------------------------------------------
# Deliverable 3 — the filters
# ---------------------------------------------------------------------------

## Every rail gets the same suite. Frames, motors and propellers browse different fields but
## must behave identically, and running one set of assertions over all three is what keeps them
## that way — a rail that quietly stopped intersecting its filters would otherwise only be
## caught if somebody thought to write the test again for that category.
static func _test_filters(catalog: PartsCatalog) -> Array:
	var results: Array = []
	results.append_array(_filter_suite(FramePicker.new(catalog), catalog, "frame",
		FramePicker.FILTER_KEYS, 12))
	results.append_array(_filter_suite(MotorPicker.new(catalog), catalog, "motor",
		MotorPicker.FILTER_KEYS, 12))
	results.append_array(_filter_suite(PropellerPicker.new(catalog), catalog, "propeller",
		PropellerPicker.FILTER_KEYS, 14))
	results.append_array(_filter_suite(BatteryPicker.new(catalog), catalog, "battery",
		BatteryPicker.FILTER_KEYS, 12))
	return results


## Public because the battery rail's own suite runs it too — one set of assertions over every
## rail is what keeps four rails behaving identically, and a second copy would decay on its own.
static func _filter_suite(picker: PartPicker, catalog: PartsCatalog, category: String,
		filter_keys: Array, minimum: int) -> Array:
	var results: Array = []
	var all_frames: Array = catalog.list_category(category)

	results.append(TestResult.new(
		"the %s rail lists every %s in the catalog before any filter is applied" % [category, category],
		picker.visible_parts().size() == all_frames.size() and all_frames.size() >= minimum,
		"%d of %d %ss listed" % [picker.visible_parts().size(), all_frames.size(), category]
	))

	# Filter options must be DERIVED from the JSON, never hardcoded. If a contributor adds a
	# part in a new material, the material filter has to grow on its own.
	var option_check := true
	var option_detail: Array = []
	for entry in filter_keys:
		var key: String = entry["key"]
		var derived: Array = picker.filter_options(key)
		var expected := _distinct_values(all_frames, entry)
		# +1 for the "All" entry the picker puts at the top.
		if derived.size() != expected.size() + 1 or derived[0] != PartPicker.ALL:
			option_check = false
		option_detail.append("%s=%d" % [key, derived.size() - 1])
	results.append(TestResult.new(
		"every %s filter's options are derived from the JSON, not hardcoded" % category,
		option_check,
		"distinct values found: %s" % ", ".join(option_detail)
	))

	# Each filter, on its own, must actually narrow the list — and everything left must
	# genuinely carry the value filtered on.
	var narrowing_ok := true
	var narrowing_detail: Array = []
	for entry in filter_keys:
		var key: String = entry["key"]
		var values: Array = picker.filter_options(key)
		var value: String = values[1]   # first real value after "All"
		picker.set_filter(key, value)
		var shown: Array = picker.visible_parts()
		if shown.is_empty() or shown.size() >= all_frames.size():
			narrowing_ok = false
		for frame in shown:
			if _filter_value(frame, entry) != value:
				narrowing_ok = false
		narrowing_detail.append("%s=%s -> %d" % [key, value, shown.size()])
		picker.set_filter(key, PartPicker.ALL)
	results.append(TestResult.new(
		"each %s filter narrows the list and keeps only matching parts" % category,
		narrowing_ok,
		", ".join(narrowing_detail)
	))

	# Combining filters must intersect, not replace one another. The two axes are taken from
	# whatever the rail actually filters on, so this reads the same for every category.
	var entry_a: Dictionary = filter_keys[0]
	var entry_b: Dictionary = filter_keys[1]
	var key_a: String = entry_a["key"]
	var key_b: String = entry_b["key"]
	var pair := _find_pair(all_frames, entry_a, entry_b, true)
	picker.set_filter(key_a, pair["type"])
	picker.set_filter(key_b, pair["size"])
	var combined: Array = picker.visible_parts()
	var combined_ok := not combined.is_empty()
	for frame in combined:
		if _filter_value(frame, entry_a) != pair["type"] \
				or _filter_value(frame, entry_b) != pair["size"]:
			combined_ok = false
	# The intersection must be a strict subset of either filter alone, or the filters are
	# not really combining.
	picker.set_filter(key_b, PartPicker.ALL)
	var type_only: int = picker.visible_parts().size()
	picker.set_filter(key_b, pair["size"])
	results.append(TestResult.new(
		"combining two %s filters intersects them" % category,
		combined_ok and combined.size() <= type_only,
		"%s + %s -> %d (%s alone: %d)" % [pair["type"], pair["size"], combined.size(), key_a, type_only]
	))

	# A combination matching nothing must SAY so rather than showing an empty void.
	var impossible := _find_pair(all_frames, entry_a, entry_b, false)
	picker.set_filter(key_a, impossible["type"])
	picker.set_filter(key_b, impossible["size"])
	results.append(TestResult.new(
		"a %s filter combination matching nothing says so instead of showing a void" % category,
		picker.visible_parts().is_empty()
			and picker._list.item_count == 1
			and not picker._list.is_item_selectable(0)
			and picker._list.get_item_text(0).to_lower().contains("no %s" % picker.noun)
			and picker.empty_state_visible(),
		"%s + %s -> %d rows, row 0 = \"%s\"" % [
			impossible["type"], impossible["size"], picker._list.item_count,
			picker._list.get_item_text(0) if picker._list.item_count > 0 else "<none>"]
	))

	picker.free()
	return results


# ---------------------------------------------------------------------------
# Deliverables 4 and 5 — geometry, details and stats move together
# ---------------------------------------------------------------------------

static func _test_live_reaction(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog)

	var small := _index_of(catalog.list_category("frame"), "frame_3in_toothpick")
	var large := _index_of(catalog.list_category("frame"), "frame_7in_long_range")

	lab.picker.select_index(small)
	var small_arm := _measured_arm_span(lab.frame_model)
	var small_mass: String = lab.details._detail_values["mass_g"].text
	var small_weight: String = lab.details._stat_values["weight"].text

	lab.picker.select_index(large)
	var large_arm := _measured_arm_span(lab.frame_model)
	var large_mass: String = lab.details._detail_values["mass_g"].text
	var large_weight: String = lab.details._stat_values["weight"].text

	# Geometry, details and stats — all three, from one selection change, with no apply
	# button anywhere in the path.
	results.append(TestResult.new(
		"one frame change moves the geometry, the details and the derived stats together",
		large_arm > small_arm + 0.05 and large_mass != small_mass and large_weight != small_weight,
		"arm span %.3f -> %.3f m, mass %s -> %s, weight %s -> %s" % [
			small_arm, large_arm, small_mass, large_mass, small_weight, large_weight]
	))

	# Every value on the details panel must trace back to frames.json rather than being
	# spelled out in code.
	var frame: Dictionary = catalog.get_part("frame_7in_long_range")
	var traced := true
	var expectations := {
		"mass_g": "%.0f" % float(frame["mass_g"]),
		"arm_mm": "%.0f" % float(frame["specs"]["arm_mm"]),
		"max_prop_inches": "%.1f" % float(frame["specs"]["max_prop_inches"]),
		"motor_mount": str(frame["specs"]["motor_mount"]),
		"material": str(frame.get("catalog", {}).get("material", "")),
		"frame_type": str(frame.get("catalog", {}).get("frame_type", "")),
		"size_class": str(frame.get("catalog", {}).get("size_class", "")),
	}
	var missing: Array = []
	for key in expectations:
		var shown: String = lab.details._detail_values[key].text
		if not shown.contains(expectations[key]):
			traced = false
			missing.append("%s: \"%s\" lacks \"%s\"" % [key, shown, expectations[key]])
	results.append(TestResult.new(
		"every value on the details panel traces back to frames.json",
		traced,
		"all 7 fields match the JSON" if traced else "; ".join(missing)
	))

	lab.free()
	return results


# ---------------------------------------------------------------------------
# The motor and propeller rails, live
# ---------------------------------------------------------------------------

## The frame rail already proved that one change moves geometry, details and stats together.
## These do the same for the two new rails, and add the thing that only becomes possible with
## three of them: a change on ANY rail has to move ALL the panels, because the five derived
## stats belong to the aircraft rather than to the component you happen to be looking at. A
## motor swap that updated the motor panel and left the frame panel quoting the old
## thrust-to-weight would look completely fine on screen.
static func _test_powertrain_rails(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog)

	# Lab must open on the reference build, not on whatever sorts first in each JSON file.
	results.append(TestResult.new(
		"Lab opens on the reference build across all three rails",
		lab.picker.selected_part()["part_id"] == ReferenceBuild.FRAME_ID
			and lab.motor_picker.selected_part()["part_id"] == ReferenceBuild.MOTOR_ID
			and lab.propeller_picker.selected_part()["part_id"] == ReferenceBuild.PROPELLER_ID,
		"%s / %s / %s" % [lab.picker.selected_part()["part_id"],
			lab.motor_picker.selected_part()["part_id"],
			lab.propeller_picker.selected_part()["part_id"]]
	))

	# --- the motor rail ---
	lab.motor_picker.select_id("motor_1404_3800kv")
	var small_bell: float = (lab.airframe.motor_meshes["M1"] as MotorMesh).bell_radius_m
	var small_kv: String = lab.motor_details._detail_values["kv"].text
	var small_twr: String = lab.details._stat_values["twr"].text

	lab.motor_picker.select_id("motor_2807_1300kv")
	var large_bell: float = (lab.airframe.motor_meshes["M1"] as MotorMesh).bell_radius_m
	var large_kv: String = lab.motor_details._detail_values["kv"].text
	var large_twr: String = lab.details._stat_values["twr"].text

	results.append(TestResult.new(
		"one motor change moves the geometry, the motor panel and the whole build's stats",
		large_bell > small_bell + 0.001 and large_kv != small_kv and large_twr != small_twr,
		"bell %.4f -> %.4f m, KV %s -> %s, thrust:weight %s -> %s (on the FRAME panel)" % [
			small_bell, large_bell, small_kv, large_kv, small_twr, large_twr]
	))

	# --- the propeller rail ---
	lab.motor_picker.select_id(ReferenceBuild.MOTOR_ID)
	lab.propeller_picker.select_id("prop_5x43x3")
	var five_radius: float = (lab.airframe.propeller_meshes["M1"] as PropellerMesh).radius_m
	var five_blades: int = (lab.airframe.propeller_meshes["M1"] as PropellerMesh).blade_count
	var five_pitch: String = lab.propeller_details._detail_values["pitch_inches"].text
	var five_weight: String = lab.motor_details._stat_values["weight"].text

	lab.propeller_picker.select_id("prop_7x35x2")
	var seven_radius: float = (lab.airframe.propeller_meshes["M1"] as PropellerMesh).radius_m
	var seven_blades: int = (lab.airframe.propeller_meshes["M1"] as PropellerMesh).blade_count
	var seven_pitch: String = lab.propeller_details._detail_values["pitch_inches"].text
	var seven_weight: String = lab.motor_details._stat_values["weight"].text

	results.append(TestResult.new(
		"one propeller change moves the blades, the prop panel and the whole build's stats",
		seven_radius > five_radius * 1.3 and five_blades == 3 and seven_blades == 2
			and seven_pitch != five_pitch and seven_weight != five_weight,
		"r %.4f -> %.4f m, %d -> %d blades, pitch %s -> %s, weight %s -> %s (on the MOTOR panel)" % [
			five_radius, seven_radius, five_blades, seven_blades,
			five_pitch, seven_pitch, five_weight, seven_weight]
	))

	# Every value on the two new panels must trace back to the JSON rather than be spelled out
	# in code — the same guarantee the frame panel is held to.
	var motor: Dictionary = catalog.get_part("motor_2506_1500kv")
	var prop: Dictionary = catalog.get_part("prop_6x45x3")
	lab.motor_picker.select_id(motor["part_id"])
	lab.propeller_picker.select_id(prop["part_id"])

	var expectations := {
		lab.motor_details: {
			"stator_class": str(motor["catalog"]["stator_class"]),
			"kv_class": str(motor["catalog"]["kv_class"]),
			"intended_use": str(motor["catalog"]["intended_use"]),
			"kv": "%.0f" % float(motor["specs"]["kv"]),
			"max_thrust_g": "%.0f" % float(motor["specs"]["max_thrust_g"]),
			"max_amps": "%.0f" % float(motor["specs"]["max_amps"]),
			"poles": "%.0f" % float(motor["specs"]["poles"]),
			"mount_pattern": str(motor["mount_pattern"]),
			# The provenance row: the prop the headline thrust was measured on, by name.
			"thrust_test": str(catalog.get_part(motor["thrust_test"]["prop_id"])["name"]),
		},
		lab.propeller_details: {
			"blade_count": str(prop["catalog"]["blade_count"]),
			"diameter_class": str(prop["catalog"]["diameter_class"]),
			"material": str(prop["catalog"]["material"]),
			"diameter_inches": "%.1f" % float(prop["specs"]["diameter_inches"]),
			"pitch_inches": "%.1f" % float(prop["specs"]["pitch_inches"]),
		},
	}
	var missing: Array = []
	var checked := 0
	for panel in expectations:
		for key in expectations[panel]:
			checked += 1
			var shown: String = panel._detail_values[key].text
			if not shown.contains(expectations[panel][key]):
				missing.append("%s: \"%s\" lacks \"%s\"" % [key, shown, expectations[panel][key]])
	results.append(TestResult.new(
		"every value on the motor and propeller panels traces back to the JSON",
		missing.is_empty(),
		"all %d fields match the JSON" % checked if missing.is_empty() else "; ".join(missing)
	))

	# Warn, never block: an over-propped build stays selectable and says what would happen.
	lab.picker.select_id("frame_3in_toothpick")
	lab.propeller_picker.select_id("prop_7x4x3")
	var warning_text: String = lab.details._warnings.ordered_text()
	results.append(TestResult.new(
		"a 7\" prop on a 3\" frame stays selectable, warns in words, and intersects on screen",
		lab.propeller_picker.selected_part()["part_id"] == "prop_7x4x3"
			and lab.details._warnings.visible
			and warning_text.contains("strike the frame")
			and lab.airframe.adjacent_prop_gap_m() < 0.0,
		"clearance %+.4f m, warning: \"%s\"" % [
			lab.airframe.adjacent_prop_gap_m(), warning_text.split("\n")[0]]
	))

	lab.free()
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Measures the arm span from the GENERATED geometry rather than re-reading arm_mm out of
## the catalog — re-reading the JSON would pass even if the mesh never changed, which is
## exactly the bug this is here to catch.
## Walks the whole generated subtree rather than only its top level, so it does not care
## how the model chooses to group arms, plates and mounting pads.
static func _measured_arm_span(model: FrameModel) -> float:
	return _furthest_node(model, Transform3D.IDENTITY) * 2.0

static func _furthest_node(node: Node, parent_transform: Transform3D) -> float:
	var furthest := 0.0
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null:
			continue
		var world := parent_transform * spatial.transform
		furthest = maxf(furthest, world.origin.length())
		furthest = maxf(furthest, _furthest_node(spatial, world))
	return furthest


## One filter entry's value for one part, through the picker's OWN lookup rather than a second
## copy of it. That matters since a filter entry may name the block it reads from: the battery
## rail filters chemistry out of `specs`, and a test that hardcoded `catalog` here would report
## the rail broken while the rail was right.
static func _filter_value(part: Dictionary, entry: Dictionary) -> String:
	return PartPicker.value_of(part, entry)


static func _distinct_values(parts: Array, entry: Dictionary) -> Array:
	var out: Array = []
	for part in parts:
		var value := _filter_value(part, entry)
		if value != "" and not out.has(value):
			out.append(value)
	return out


## Finds a pair of filter values that either does or does not exist in the catalog, so the
## "combines" and "matches nothing" tests never hardcode a combination that a later catalog
## entry could silently make valid.
static func _find_pair(parts: Array, entry_a: Dictionary, entry_b: Dictionary, should_exist: bool) -> Dictionary:
	var values_a := _distinct_values(parts, entry_a)
	var values_b := _distinct_values(parts, entry_b)
	for a in values_a:
		for b in values_b:
			var found := false
			for part in parts:
				if _filter_value(part, entry_a) == a and _filter_value(part, entry_b) == b:
					found = true
					break
			if found == should_exist:
				return {"type": a, "size": b}
	return {"type": "", "size": ""}


static func _index_of(parts: Array, part_id: String) -> int:
	for i in parts.size():
		if parts[i]["part_id"] == part_id:
			return i
	return -1
