class_name TestComponentMesh
extends RefCounted
## The camera, VTX, antenna and receiver as geometry on the airframe.
##
## THE ASSERTION THAT MATTERS MOST IS THE ANTI-DIVERGENCE ONE. The mass model has placed all four of
## these at specific points since LTHL-11 — the centre of mass and the inertia tensor move when one
## is fitted — and until this slice there was no picture of any of it. So the check worth having is
## not "the camera is 12 mm forward", it is "the camera is drawn at the point Build.mass_parts()
## weighs it at", tested by comparing against the mass model's own PartMass rather than against a
## literal. A hardcoded coordinate would pass while both sides drifted together, which is the exact
## failure this project has been bitten by before (main.tscn's 0.0778 against MotorLayout's arm).
##
## Every check below fails without its fix, and most of them fail in the flattest possible way,
## because before this slice AirframeModel had no loop over Build.OPTIONAL_COMPONENTS at all: there
## was no node to measure.
##
## The reference build's 496 g, 11.7:1 and 4.1 min are NOT re-asserted here. They are already
## asserted in test_mass_properties, test_hover and test_build_panel, and this slice draws mass that
## was already there rather than adding any — so those suites moving is the signal that this class
## is wrong, and a fourth copy of the same three numbers here would only be a fourth place to update.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_a_fitted_component_is_drawn_and_an_omitted_one_is_not(catalog))
	results.append(_the_drawn_centre_is_where_the_mass_model_weighs_it(catalog))
	results.append(_the_antenna_reaches_its_published_length(catalog))
	results.append(_a_frame_change_takes_the_components_with_it(catalog))
	results.append(_the_shared_clearance_still_gives_the_pack_its_own_number(catalog))
	results.append(_a_component_in_the_prop_discs_says_so(catalog))
	results.append(_a_component_bigger_than_its_plate_says_so(catalog))
	results.append(_lab_reports_the_components_it_just_fitted(catalog))

	return results


## Fitted draws a node, omitted draws nothing — and omitted is not a special case, it is the absence
## of one. A whoop on an AIO carries none of the four and the empty frame IS the picture.
##
## Fails today in both directions: with no loop over OPTIONAL_COMPONENTS there is no node either way,
## so the fitted half fails outright and the omitted half passes for the wrong reason. Both are
## asserted so the pair can only pass for the right one.
static func _a_fitted_component_is_drawn_and_an_omitted_one_is_not(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	var fitted := airframe.component_meshes.keys().size()
	var camera_drawn: bool = airframe.component_meshes.has("camera")
	var camera_node := airframe.frame_model.get_node_or_null("Component_camera") != null

	# Nothing fitted: a whoop on an AIO board.
	airframe.rebuild(Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_25x25x4", "battery_1s_550", Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID,
		Build.no_components()))
	var bare := airframe.component_meshes.keys().size()
	var bare_node := airframe.frame_model.get_node_or_null("Component_camera") != null

	airframe.free()

	return TestResult.new(
		"a fitted component is drawn and an omitted one leaves nothing behind",
		fitted == 4 and camera_drawn and camera_node and bare == 0 and not bare_node,
		"reference build draws %d of 4 (camera node: %s); nothing fitted draws %d (camera node: %s)" % [
			fitted, camera_node, bare, bare_node])


## THE ANTI-DIVERGENCE TEST. Each component is drawn at the point the mass model weighs it at,
## checked against Build.mass_parts()'s own PartMass rather than against a coordinate written here.
##
## Fails today: there is nothing drawn to compare. It would also fail the day somebody gives
## ComponentMesh a seat of its own, or gives the mass model a second copy of the mount arithmetic —
## which is the whole reason it compares two live answers instead of one answer and a literal.
static func _the_drawn_centre_is_where_the_mass_model_weighs_it(catalog: PartsCatalog) -> TestResult:
	var build := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500")
	var airframe := AirframeModel.new()
	airframe.rebuild(build)

	var worst := 0.0
	var checked := 0
	var detail := ""
	for category in Build.OPTIONAL_COMPONENTS:
		var part: Dictionary = build.components[category]
		var weighed := Vector3.INF
		for entry in build.mass_parts():
			if entry.label == String(part.get("name", "")):
				weighed = entry.position_m
		var drawn: Vector3 = (airframe.component_meshes[category] as ComponentMesh).position
		worst = maxf(worst, drawn.distance_to(weighed))
		checked += 1
		detail += "%s drawn %.4f/%.4f/%.4f vs weighed %.4f/%.4f/%.4f; " % [
			category, drawn.x, drawn.y, drawn.z, weighed.x, weighed.y, weighed.z]

	airframe.free()

	return TestResult.new(
		"each component is drawn exactly where the mass model weighs it",
		checked == 4 and worst < 1e-6,
		"%d categories, worst disagreement %.6f mm — %s" % [checked, worst * 1000.0, detail])


## The antenna's silhouette is allowed to differ from its inertia box; its SIZE is not. A 95 mm whip
## drawn as a 22 mm slab would be the least honest of the four, and a 95 mm whip drawn 60 mm long
## would be a different failure of the same kind.
##
## Fails today (no antenna is drawn), and fails again for any future change that leans the whip
## further without lengthening it — the extent is measured along the whip's OWN axis, so the lean
## angle cannot move this number.
static func _the_antenna_reaches_its_published_length(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	var passed := true
	var detail := ""

	for antenna_id in ["antenna_dipole_ufl_nano", "antenna_rhcp_ufl", "antenna_rhcp_sma_long_range"]:
		airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
			"prop_5x43x3", "battery_4s_1500", Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID,
			{"antenna": antenna_id}))
		var mesh: ComponentMesh = airframe.component_meshes["antenna"]
		var published: float = float(catalog.get_part(antenna_id).get("specs", {}).get("length_mm", 0.0)) / 1000.0
		var drawn := mesh.axis_extent_m()
		if absf(drawn - published) > 1e-6:
			passed = false
		detail += "%s: drawn %.1f mm vs published %.1f mm; " % [
			antenna_id, drawn * 1000.0, published * 1000.0]

	airframe.free()

	return TestResult.new(
		"the antenna reaches its published length along its own axis", passed, detail)


## A frame change carries the components with it. They are parented onto frame_model, whose rebuild
## frees everything hanging off it, so this is free — and it is the reason to parent them there
## rather than onto the airframe root, where a stale camera could survive a frame change and sit at
## the previous frame's plate edge.
##
## Fails today. It would also fail for a component parented to the root, which is the version of
## this code that looks equally correct on screen for exactly one build.
static func _a_frame_change_takes_the_components_with_it(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_25x25x4", "battery_1s_550"))
	var small: Vector3 = (airframe.component_meshes["camera"] as ComponentMesh).position
	var small_nodes := _count_named(airframe.frame_model, "Component_")

	airframe.rebuild(Build.from_ids(catalog, "frame_10in_long_range", "motor_2807_1300kv",
		"prop_10x5x2", "battery_6s_4000_liion"))
	var large: Vector3 = (airframe.component_meshes["camera"] as ComponentMesh).position
	var large_nodes := _count_named(airframe.frame_model, "Component_")

	airframe.free()

	return TestResult.new(
		"a frame change moves the components and leaves none of the old ones behind",
		large.z < small.z - 0.020 and small_nodes == 4 and large_nodes == 4,
		"camera nose-ward %.1f mm -> %.1f mm; nodes %d then %d (4 expected, not 8)" % [
			small.z * 1000.0, large.z * 1000.0, small_nodes, large_nodes])


## Refactoring the pack's clearance check into a shared one is exactly where the pack's behaviour
## quietly changes, so the pack's number is asserted to be unmoved — against the same two builds
## test_airframe_model uses, one that clears and one that does not.
##
## The literals are the OLD implementation's answers, captured before the generalisation. That is
## what makes this able to fail: comparing the new call against itself would pass whatever it
## returned.
static func _the_shared_clearance_still_gives_the_pack_its_own_number(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	var baseline := airframe.battery_prop_clearance_m()
	# The same rectangle, handed to the general form by hand: if the pack's own call has stopped
	# routing through it, these two stop agreeing.
	var pack: Vector3 = airframe.battery_mesh.size_m
	var direct := airframe.footprint_prop_clearance_m(
		Rect2(-pack.x * 0.5, -pack.z * 0.5, pack.x, pack.z))

	airframe.rebuild(Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion"))
	var absurd := airframe.battery_prop_clearance_m()

	airframe.free()

	return TestResult.new(
		"generalising the clearance left the pack's own number unchanged",
		absf(baseline - 0.00900) < 5e-5 and absf(direct - baseline) < 1e-9 and absurd < 0.0,
		"reference %.5f m (0.00900 expected), direct %.5f m, 6S on a 3\" toothpick %.5f m" % [
			baseline, direct, absurd])


## A component in a propeller disc is warned about, and the reference build is not. The antenna is
## the case worth naming: it is the furthest-out mass on the aircraft and it stands up and aft into
## exactly the airspace a rotor sweeps, so a small frame is where this bites.
##
## THE DESIGN NOTE'S WORKED CASE WAS A NEAR MISS, AND THE MEASUREMENT IS ASSERTED HERE RATHER THAN
## THE GUESS. The 95 mm long-range whip on a 3" toothpick was written up as "either a genuine strike
## warning or a near miss — measure it, do not assert it from this document". Measured, on its own
## 3" props, it CLEARS by 4.5 mm. It strikes only once the props are oversized for the frame
## (3.5" on the same toothpick: 1.9 mm in), which is a build that is already warned about elsewhere.
## The honest strike case is the small end: a whoop's own default antenna on its own 2.5" props is
## 16 mm inside the discs, because a 65 mm frame's plate ends 8 mm behind the origin and every
## antenna in the catalog is longer than the aircraft is wide.
##
## Both halves are asserted, so this cannot pass by warning about everything, and the near-miss
## figure is carried in the detail so a change that quietly moves it is visible in the log.
static func _a_component_in_the_prop_discs_says_so(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	var baseline := _keys(airframe.component_fit_warnings())

	# The design note's worked case, measured rather than asserted: it clears.
	airframe.rebuild(Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_4s_1500", Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID,
		{"antenna": "antenna_rhcp_sma_long_range"}))
	var near_miss := airframe.footprint_prop_clearance_m(airframe.component_bounds_m("antenna"))
	var toothpick := _keys(airframe.component_fit_warnings())

	# The whoop, with nothing unusual fitted at all: its own default components on its own props.
	airframe.rebuild(Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_25x25x4", "battery_1s_550"))
	var whoop := _keys(airframe.component_fit_warnings())
	var intrusion := airframe.footprint_prop_clearance_m(airframe.component_bounds_m("antenna"))

	airframe.free()

	return TestResult.new(
		"a component reaching into the propeller discs is warned about, and a clear one is not",
		not baseline.has("component_in_prop_disc")
			and not toothpick.has("component_in_prop_disc") and near_miss > 0.0
			and whoop.has("component_in_prop_disc") and intrusion < 0.0,
		"reference: %s; 95 mm whip on a 3\" toothpick clears by %.1f mm: %s; 65 mm whoop's antenna is %.1f mm inside the discs: %s" % [
			baseline, near_miss * 1000.0, toothpick, -intrusion * 1000.0, whoop])


## A full-size camera on a 65 mm whoop, whose centre plate is 17.6 mm square. Nothing is wrong with
## building it and Lothal never blocks — but it should be obviously absurd, in words as well as on
## screen. Fails today: no warning exists.
static func _a_component_bigger_than_its_plate_says_so(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()

	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	var baseline := _keys(airframe.component_fit_warnings())

	airframe.rebuild(Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_25x25x4", "battery_1s_550"))
	var whoop := _keys(airframe.component_fit_warnings())

	airframe.free()

	return TestResult.new(
		"a component bigger than the plate it sits on is warned about",
		not baseline.has("component_larger_than_plate")
			and whoop.has("component_larger_than_plate"),
		"reference: %s; full-size electronics on a 65 mm whoop: %s" % [baseline, whoop])


## The measurement reaches the screen. Everything above proves AirframeModel can measure the fit of
## a component; this proves Lab SHOWS it, through the same single handler that redraws the geometry
## — so a panel describing the previous build would fail here rather than in front of a builder.
##
## Driven through the rails, because the rail is how a frame is really chosen and the wiring between
## the two is the only thing left to get wrong.
static func _lab_reports_the_components_it_just_fitted(catalog: PartsCatalog) -> TestResult:
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	var baseline := lab.assembly_panel.fit_warning_text()

	lab.picker.select_id("frame_65mm_whoop")
	lab.propeller_picker.select_id("prop_25x25x4")
	var whoop := lab.assembly_panel.fit_warning_text()

	lab.free()

	return TestResult.new(
		"Lab reports the fit of the components it has just fitted",
		not baseline.contains("plate it sits on") and whoop.contains("plate it sits on"),
		"reference build: \"%s\"; 65 mm whoop: \"%s\"" % [baseline, whoop])


static func _keys(warnings: Array[BuildWarning]) -> Array:
	var out: Array = []
	for warning in warnings:
		out.append(String(warning.id))
	return out


static func _count_named(node: Node, prefix: String) -> int:
	var count := 0
	for child in node.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count
