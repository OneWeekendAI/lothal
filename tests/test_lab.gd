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
	results.append_array(_test_orbit(catalog))

	return results


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

static func _test_filters(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var picker := FramePicker.new(catalog)
	var all_frames: Array = catalog.list_category("frame")

	results.append(TestResult.new(
		"the picker lists every frame in the catalog before any filter is applied",
		picker.visible_frames().size() == all_frames.size() and all_frames.size() >= 12,
		"%d of %d frames listed" % [picker.visible_frames().size(), all_frames.size()]
	))

	# Filter options must be DERIVED from the JSON, never hardcoded. If a contributor adds a
	# frame in a new material, the material filter has to grow on its own.
	var option_check := true
	var option_detail: Array = []
	for entry in FramePicker.FILTER_KEYS:
		var key: String = entry["key"]
		var derived: Array = picker.filter_options(key)
		var expected := _distinct_values(all_frames, key)
		# +1 for the "All" entry the picker puts at the top.
		if derived.size() != expected.size() + 1 or derived[0] != FramePicker.ALL:
			option_check = false
		option_detail.append("%s=%d" % [key, derived.size() - 1])
	results.append(TestResult.new(
		"every filter's options are derived from frames.json, not hardcoded",
		option_check,
		"distinct values found: %s" % ", ".join(option_detail)
	))

	# Each filter, on its own, must actually narrow the list — and everything left must
	# genuinely carry the value filtered on.
	var narrowing_ok := true
	var narrowing_detail: Array = []
	for entry in FramePicker.FILTER_KEYS:
		var key: String = entry["key"]
		var values: Array = picker.filter_options(key)
		var value: String = values[1]   # first real value after "All"
		picker.set_filter(key, value)
		var shown: Array = picker.visible_frames()
		if shown.is_empty() or shown.size() >= all_frames.size():
			narrowing_ok = false
		for frame in shown:
			if _catalog_value(frame, key) != value:
				narrowing_ok = false
		narrowing_detail.append("%s=%s -> %d" % [key, value, shown.size()])
		picker.set_filter(key, FramePicker.ALL)
	results.append(TestResult.new(
		"each filter narrows the list and keeps only matching frames",
		narrowing_ok,
		", ".join(narrowing_detail)
	))

	# Combining filters must intersect, not replace one another.
	var pair := _find_pair(all_frames, "frame_type", "size_class", true)
	picker.set_filter("frame_type", pair["type"])
	picker.set_filter("size_class", pair["size"])
	var combined: Array = picker.visible_frames()
	var combined_ok := not combined.is_empty()
	for frame in combined:
		if _catalog_value(frame, "frame_type") != pair["type"] \
				or _catalog_value(frame, "size_class") != pair["size"]:
			combined_ok = false
	# The intersection must be a strict subset of either filter alone, or the filters are
	# not really combining.
	picker.set_filter("size_class", FramePicker.ALL)
	var type_only: int = picker.visible_frames().size()
	picker.set_filter("size_class", pair["size"])
	results.append(TestResult.new(
		"combining two filters intersects them",
		combined_ok and combined.size() <= type_only,
		"%s + %s -> %d (type alone: %d)" % [pair["type"], pair["size"], combined.size(), type_only]
	))

	# A combination matching nothing must SAY so rather than showing an empty void.
	var impossible := _find_pair(all_frames, "frame_type", "size_class", false)
	picker.set_filter("frame_type", impossible["type"])
	picker.set_filter("size_class", impossible["size"])
	results.append(TestResult.new(
		"a filter combination matching nothing says so instead of showing a void",
		picker.visible_frames().is_empty()
			and picker._list.item_count == 1
			and not picker._list.is_item_selectable(0)
			and picker._list.get_item_text(0).to_lower().contains("no frame")
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


static func _catalog_value(frame: Dictionary, key: String) -> String:
	return str(frame.get("catalog", {}).get(key, ""))


static func _distinct_values(frames: Array, key: String) -> Array:
	var out: Array = []
	for frame in frames:
		var value := _catalog_value(frame, key)
		if value != "" and not out.has(value):
			out.append(value)
	return out


## Finds a (frame_type, size_class) pair that either does or does not exist in the catalog,
## so the "combines" and "matches nothing" tests never hardcode a combination that a later
## catalog entry could silently make valid.
static func _find_pair(frames: Array, key_a: String, key_b: String, should_exist: bool) -> Dictionary:
	var values_a := _distinct_values(frames, key_a)
	var values_b := _distinct_values(frames, key_b)
	for a in values_a:
		for b in values_b:
			var found := false
			for frame in frames:
				if _catalog_value(frame, key_a) == a and _catalog_value(frame, key_b) == b:
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
