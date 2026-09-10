class_name TestElectronicsParts
extends RefCounted
## LTHL-11: the camera, VTX, antenna and receiver, out of Build.ELECTRONICS_BUDGET_G's lump and into
## parts that declare their own mounting.
##
## THE RULE THIS SUITE EXISTS TO ENFORCE is that mass comes OUT of the budget and is never added
## beside it. The reference build's 496.0 g, 11.69:1 and 29.6% were computed with the whole 55 g
## included; a component that gained mass on its way to becoming selectable would silently move
## two of the project's three fixed points, and it would do it in a commit whose stated subject was
## making a picture more honest.
##
## ---------------------------------------------------------------------------
## WHAT THIS SLICE DOES NOT FIX, ASSERTED RATHER THAN ADMITTED
## ---------------------------------------------------------------------------
##
## Unbundling is necessary and it is not sufficient at the small end. Take the four components off
## a 65 mm whoop and 21 g comes off an aircraft that was 63 g too heavy. The remainder is the
## harness term, which PW2 stopped being flat (see `Harness`), and the catalog's
## own whoop-class part masses, which are a data problem and out of scope.
##
## _the_span_table_before_and_after() prints that arithmetic rather than describing it, and
## _a_whoop_with_an_aio() names the residual against the real-world figure instead of stopping at
## "it got better". Nothing in this file was tuned to make the whoop come out right; the four
## shares are the class-typical masses of the parts a 5" freestyle carries, and they were fixed
## before the whoop was measured.

## Grams. Tighter than any figure here needs, because every assertion below is an EXACT arithmetic
## identity — a share carved out, a mass omitted — rather than a measurement with an error bar. A
## looser bound would let a rounded share through.
const MASS_EPS := 1e-9
## Metres. The centre-of-mass predictions are closed-form, so the only error between a prediction
## and the model is arithmetic: Godot's Vector3 is single-precision, and a 0.18 mm component of it
## carries about 1e-11 m of representation error. A nanometre is four orders of magnitude tighter
## than anything physical here and two orders looser than that floor, which is where a bound
## belongs when what it is checking is an identity rather than a measurement.
const POSITION_EPS := 1e-9


static func run() -> Array:
	var results: Array = []
	results.append_array(_the_reference_build_is_unmoved())
	results.append_array(_omitting_one_component_costs_exactly_that_component())
	results.append_array(_a_build_with_none_of_the_four())
	results.append_array(_a_heavier_component_costs_exactly_the_excess())
	results.append_array(_the_budget_cannot_be_exceeded_silently())
	results.append_array(_every_component_sits_where_mount_layout_puts_it())
	results.append_array(_a_camera_moves_the_centre_of_mass_forward())
	results.append_array(_custom_components_work_in_all_four_categories())
	results.append_array(_a_whoop_with_an_aio())
	results.append(_the_span_table_before_and_after())
	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The reference build with `overrides` applied to its optional components. An empty string omits
## one; anything absent keeps the default. Everything else is ReferenceBuild's, so any difference
## in a figure below is the component's and nothing else's.
static func _reference_with(overrides: Dictionary) -> Build:
	return Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, overrides)


## Nothing fitted in any of the four.
static func _nothing_fitted() -> Dictionary:
	var out := {}
	for category in Build.OPTIONAL_COMPONENTS:
		out[category] = ""
	return out


static func _catalog_mass_g(part_id: String) -> float:
	return float(PartsCatalog.load_default().get_part(part_id).get("mass_g", 0.0))


# ---------------------------------------------------------------------------
# 1. The three fixed points, and the budget that keeps them fixed.
# ---------------------------------------------------------------------------
## FAILS IF: any share is carved at a value the default part does not weigh, if a share is added
## beside the budget rather than out of it, or if the wiring remainder is computed from anything
## but what is left. All three of those are single-line mistakes and all three move a number this
## project has been quoting since day 2.
static func _the_reference_build_is_unmoved() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()

	out.append(TestResult.new(
		"the reference build still weighs 507.5 g with the default components fitted",
		absf(build.all_up_weight_g() - 507.48) < 0.05,
		"got %.4f g" % build.all_up_weight_g()
	))
	out.append(TestResult.new(
		"and its thrust-to-weight is still 11.43:1",
		absf(build.thrust_to_weight() - 11.432) < 0.005,
		"got %.4f" % build.thrust_to_weight()
	))
	out.append(TestResult.new(
		"and it still hovers at 29.9%",
		absf(build.hover_throttle() * 100.0 - 29.92) < 0.05,
		"got %.4f%%" % (build.hover_throttle() * 100.0)
	))

	# The identity underneath those three. A fully-fitted build's electronics weigh the budget
	# EXACTLY, which is what "carved out rather than added beside" means expressed as arithmetic
	# rather than as an intention in a comment.
	out.append(TestResult.new(
		"a fully-fitted build's electronics are the carved shares plus its harness, to the gram",
		absf(build.electronics_mass_g()
			- (Build.carved_total_g() + build.harness_mass_g())) < MASS_EPS,
		"%.9f g against %.1f g of carved shares + %.9f g of harness" % [
			build.electronics_mass_g(), Build.carved_total_g(), build.harness_mass_g()]
	))

	# And the reason it holds: each default part weighs its own share. Asserted per category rather
	# than only in the total, because two shares wrong in opposite directions would sum correctly
	# and move the centre of mass without moving the weight.
	var mismatched: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		var default_mass := _catalog_mass_g(String(Build.DEFAULT_COMPONENT_IDS[category]))
		var share := float(Build.CARVED_SHARES[category])
		if absf(default_mass - share) > MASS_EPS:
			mismatched.append("%s: default weighs %.3f g against a %.3f g share" % [
				category, default_mass, share])
	out.append(TestResult.new(
		"every default component weighs exactly the share carved out for it",
		mismatched.is_empty(),
		"4 categories checked" if mismatched.is_empty() else str(mismatched)
	))
	return out


# ---------------------------------------------------------------------------
# 2. Omission costs the component's own mass, not a budgeted share and not zero.
# ---------------------------------------------------------------------------
## FAILS IF: omitting a component is not expressible at all, if it drops the aircraft by the
## BUDGETED share rather than by what is fitted, or if it drops it by nothing because a default
## quietly took its place.
##
## The second half is what makes this able to fail. Omitting the DEFAULT camera loses 8 g, and 8 g
## is also the camera's budgeted share — so a model that subtracted the share instead of the part
## would pass. Omitting the 12 g full-size camera separates them.
static func _omitting_one_component_costs_exactly_that_component() -> Array:
	var out: Array = []
	var fitted := ReferenceBuild.build()

	var without_camera := _reference_with({"camera": ""})
	var camera_mass := _catalog_mass_g("cam_micro_analog")
	out.append(TestResult.new(
		"omitting the camera takes off exactly the camera's own mass",
		absf((fitted.all_up_weight_g() - without_camera.all_up_weight_g()) - camera_mass) < MASS_EPS,
		"%.4f g -> %.4f g, a difference of %.4f g against the camera's %.1f g" % [
			fitted.all_up_weight_g(), without_camera.all_up_weight_g(),
			fitted.all_up_weight_g() - without_camera.all_up_weight_g(), camera_mass]
	))

	# The separating case: a camera that is NOT worth its budgeted share.
	var heavy_fitted := _reference_with({"camera": "cam_fullsize_analog"})
	var heavy_mass := _catalog_mass_g("cam_fullsize_analog")
	out.append(TestResult.new(
		"and omitting a heavier camera takes off ITS mass, not the budgeted 8 g share",
		absf((heavy_fitted.all_up_weight_g() - without_camera.all_up_weight_g()) - heavy_mass) < MASS_EPS
			and absf(heavy_mass - Build.CAMERA_BUDGET_MASS_G) > 1.0,
		"a %.1f g camera against a %.1f g share; removing it moved %.4f g" % [
			heavy_mass, Build.CAMERA_BUDGET_MASS_G,
			heavy_fitted.all_up_weight_g() - without_camera.all_up_weight_g()]
	))

	# All four categories, so that "omittable" is a property of the mechanism rather than of the
	# one category the first two checks happen to use.
	var not_omittable: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		var without := _reference_with({category: ""})
		var expected := _catalog_mass_g(String(Build.DEFAULT_COMPONENT_IDS[category]))
		var actual := fitted.all_up_weight_g() - without.all_up_weight_g()
		if absf(actual - expected) > MASS_EPS:
			not_omittable.append("%s: lost %.4f g, expected %.4f g" % [category, actual, expected])
	out.append(TestResult.new(
		"each of the four is omittable, and each costs its own mass",
		not_omittable.is_empty(),
		"4 categories checked" if not_omittable.is_empty() else str(not_omittable)
	))
	return out


# ---------------------------------------------------------------------------
# 3. None of the four fitted: the budget less all four shares.
# ---------------------------------------------------------------------------
## FAILS IF: omission is not additive — if two omissions together cost something other than the sum
## of their parts, which is what a model that special-cased "at least one must be fitted" would do.
static func _a_build_with_none_of_the_four() -> Array:
	var out: Array = []
	var bare := _reference_with(_nothing_fitted())

	var shares := 0.0
	for category in Build.OPTIONAL_COMPONENTS:
		shares += float(Build.CARVED_SHARES[category])

	out.append(TestResult.new(
		"a build with none of the four weighs its shares and harness less all four shares",
		absf(bare.electronics_mass_g()
			- (Build.carved_total_g() + bare.harness_mass_g() - shares)) < MASS_EPS,
		"%.4f g of electronics against %.1f + %.4f - %.1f = %.4f" % [
			bare.electronics_mass_g(), Build.carved_total_g(), bare.harness_mass_g(), shares,
			Build.carved_total_g() + bare.harness_mass_g() - shares]
	))
	out.append(TestResult.new(
		"and the aircraft is lighter by exactly that, all the way through to all-up weight",
		absf((ReferenceBuild.build().all_up_weight_g() - bare.all_up_weight_g()) - shares) < MASS_EPS,
		"507.5 g -> %.4f g, a difference of %.4f g" % [
			bare.all_up_weight_g(), ReferenceBuild.build().all_up_weight_g() - bare.all_up_weight_g()]
	))

	# What is LEFT is the stack plus the harness, and it is worth naming. It was 34 g of which 14 g
	# was the flat wiring term; PW2 weighed that term, so the harness half now moves with the build.
	out.append(TestResult.new(
		"what is left is the two stack boards and the harness, and nothing else",
		absf(bare.electronics_mass_g()
			- (bare.fc_mass_g() + bare.esc_mass_g() + bare.harness_mass_g())) < MASS_EPS,
		"%.1f g = %.1f FC + %.1f ESC + %.4f harness" % [
			bare.electronics_mass_g(), bare.fc_mass_g(), bare.esc_mass_g(), bare.harness_mass_g()]
	))

	# A build with nothing fitted is fore/aft symmetric again, which is not a coincidence and is
	# worth pinning: it is the proof that the reference build's own fore/aft offset comes from
	# these four components and from nothing else that moved in this slice.
	out.append(TestResult.new(
		"and its centre of mass is back on the origin fore and aft",
		absf(bare.mass_properties.com_m.z) < POSITION_EPS
			and absf(bare.mass_properties.com_m.x) < POSITION_EPS,
		"com %s" % bare.mass_properties.com_m
	))
	return out


# ---------------------------------------------------------------------------
# 4. A heavier-than-budget component costs exactly the excess.
# ---------------------------------------------------------------------------
## The pattern the H743's 4 g overage already establishes, extended to the four new categories.
##
## FAILS IF: a component's mass is taken as its budgeted share (the aircraft would not move at
## all), or if it is added beside the budget (the aircraft would gain the whole part).
static func _a_heavier_component_costs_exactly_the_excess() -> Array:
	var out: Array = []
	var reference_g := ReferenceBuild.build().all_up_weight_g()

	var cases := {
		"camera": "cam_fullsize_analog",
		"vtx": "vtx_digital_hd",
		"antenna": "antenna_rhcp_sma",
		"receiver": "rx_diversity_900",
	}
	var wrong: Array[String] = []
	var told: Array[String] = []
	for category in cases:
		var part_id: String = cases[category]
		var excess := _catalog_mass_g(part_id) - float(Build.CARVED_SHARES[category])
		var heavier := _reference_with({category: part_id})
		var gained := heavier.all_up_weight_g() - reference_g
		told.append("%s +%.1f g" % [category, gained])
		if absf(gained - excess) > MASS_EPS or excess <= 0.0:
			wrong.append("%s: gained %.4f g, expected the %.4f g excess" % [
				category, gained, excess])

	out.append(TestResult.new(
		"fitting a heavier-than-budget component costs exactly the excess, in all four categories",
		wrong.is_empty(),
		str(told) if wrong.is_empty() else str(wrong)
	))
	return out


# ---------------------------------------------------------------------------
# 5. The budget cannot be exceeded silently.
# ---------------------------------------------------------------------------
## STRUCTURAL, NOT BY INSPECTION, and that is the whole of the point. "The shares add up to less
## than 55" is true today and a reader can check it by eye; what this asserts is that the code
## COMPUTES the remainder, so a seventh share added to CARVED_SHARES either fits or turns the
## wiring term negative — and a negative wiring term is caught here rather than being quietly
## carried as an aircraft that weighs less than its parts.
##
## FAILS IF: budget_remainder_g() is ever written as a literal rather than derived, or if a share
## is added that the budget cannot pay for.
static func _the_budget_cannot_be_exceeded_silently() -> Array:
	var out: Array = []

	out.append(TestResult.new(
		"the carved shares never exceed the electronics budget",
		Build.carved_total_g() <= Build.ELECTRONICS_BUDGET_G + MASS_EPS,
		"%.1f g carved out of a %.1f g budget" % [Build.carved_total_g(), Build.ELECTRONICS_BUDGET_G]
	))
	out.append(TestResult.new(
		"and the budget remainder is what is left, never a number of its own",
		absf((Build.carved_total_g() + Build.budget_remainder_g())
				- Build.ELECTRONICS_BUDGET_G) < MASS_EPS
			and Build.budget_remainder_g() >= 0.0,
		"%.1f carved + %.1f remaining = %.1f" % [
			Build.carved_total_g(), Build.budget_remainder_g(),
			Build.carved_total_g() + Build.budget_remainder_g()]
	))

	# Every optional component has a share, and every share belongs to a category that exists. The
	# failure this catches is a fifth component added to OPTIONAL_COMPONENTS whose mass is carried
	# by the aircraft and paid for by nobody.
	var orphans: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		if not Build.CARVED_SHARES.has(category):
			orphans.append("%s is weighed but has no share carved out of the budget" % category)
		if not Build.COMPONENT_MOUNTS.has(category):
			orphans.append("%s is weighed but has no mount" % category)
		if not Build.DEFAULT_COMPONENT_IDS.has(category):
			orphans.append("%s is weighed but has no default part" % category)
	out.append(TestResult.new(
		"every component that is weighed has a share, a mount and a default",
		orphans.is_empty(),
		"%d components checked" % Build.OPTIONAL_COMPONENTS.size() if orphans.is_empty() else str(orphans)
	))
	return out


# ---------------------------------------------------------------------------
# 6. Every position comes from MountLayout.
# ---------------------------------------------------------------------------
## THE MOUNT ID, NOT A COORDINATE. Asserting a coordinate would pass just as happily against a
## hardcoded offset that happened to agree, which is the exact thing this slice must not contain.
##
## FAILS IF: a component names a mount that does not exist on the frame, if its mass lands
## anywhere other than where seated_centre_m() puts it, or if its position is written down instead
## of derived — which the standoff check below is what actually catches, because a hardcoded
## constant does not move when the standoffs get taller.
static func _every_component_sits_where_mount_layout_puts_it() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var mounts := build.mount_points()

	var missing: Array[String] = []
	var misplaced: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		var mount_id := String(Build.COMPONENT_MOUNTS[category])
		var mount := MountLayout.by_id(mounts, mount_id)
		if mount == null:
			missing.append("%s names mount \"%s\", which this frame does not offer" % [
				category, mount_id])
			continue
		var component: Dictionary = build.components[category]
		var expected := MountLayout.seated_centre_m(mount, Build.component_size_of(component))
		var entry := _part_mass_named(build, str(component["name"]))
		if entry == null:
			misplaced.append("%s is not in the mass model at all" % category)
		elif (entry.position_m - expected).length() > POSITION_EPS:
			misplaced.append("%s at %s, its mount seats it at %s" % [
				category, entry.position_m, expected])

	out.append(TestResult.new(
		"each of the four names a mount its frame actually offers",
		missing.is_empty(),
		str(Build.COMPONENT_MOUNTS.values()) if missing.is_empty() else str(missing)
	))
	out.append(TestResult.new(
		"and each one's mass is exactly where that mount seats it",
		misplaced.is_empty(),
		"4 components checked against MountLayout" if misplaced.is_empty() else str(misplaced)
	))

	# The check a hardcoded coordinate fails. Taller standoffs move the plates, the bays are ON the
	# plates, so every one of the four must move with them — the same assertion tests/
	# test_mount_points.gd makes about the pack's mount, applied to the four this slice added.
	var tall := ReferenceBuild.build()
	tall.set_assembly({"plate_gap_m": MountLayout.max_plate_gap_m(build.arm_m)})
	var unmoved: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		var name := str(build.components[category]["name"])
		var before := _part_mass_named(build, name)
		var after := _part_mass_named(tall, name)
		if before == null or after == null or absf(after.position_m.y - before.position_m.y) < 1e-6:
			unmoved.append("%s did not move when the standoffs did" % category)
	out.append(TestResult.new(
		"taller standoffs move all four, because their bays are on the plates",
		unmoved.is_empty(),
		"gap %.4f -> %.4f m" % [MountLayout.default_plate_gap_m(),
			MountLayout.max_plate_gap_m(build.arm_m)] if unmoved.is_empty() else str(unmoved)
	))
	return out


static func _part_mass_named(build: Build, label: String) -> PartMass:
	for part in build.mass_parts():
		if (part as PartMass).label == label:
			return part
	return null


# ---------------------------------------------------------------------------
# 7. The centre of mass moves, by a predicted amount.
# ---------------------------------------------------------------------------
## THE MAGNITUDE IS PREDICTED HERE AND NOT READ OFF THE IMPLEMENTATION. Adding one mass to a body
## moves the centre of mass to the weighted mean of the two, which is a definition rather than a
## fitted number — so the expected value below is computed from the camera's mass, the camera's
## seat, and the aircraft without it, and a model that moved the CoM by the camera's full offset
## or by the wrong part's would fail it while passing a direction check.
##
## FAILS IF: the camera's mass reaches the total but not the moment (the CoM would not move at
## all), or if the bay's sign is wrong (it would move aft).
static func _a_camera_moves_the_centre_of_mass_forward() -> Array:
	var out: Array = []
	var without := _reference_with({"camera": ""})
	var with := ReferenceBuild.build()

	var camera: Dictionary = with.components["camera"]
	var camera_kg := float(camera["mass_g"]) / 1000.0
	var seat := MountLayout.seated_centre_m(
		MountLayout.by_id(with.mount_points(), String(Build.COMPONENT_MOUNTS["camera"])),
		Build.component_size_of(camera))

	var without_kg := without.mass_properties.total_mass_kg
	var expected_z := (without.mass_properties.com_m.z * without_kg + seat.z * camera_kg) \
		/ (without_kg + camera_kg)

	out.append(TestResult.new(
		"fitting the camera moves the centre of mass FORWARD",
		with.mass_properties.com_m.z < without.mass_properties.com_m.z - 1e-6,
		"%.6f m -> %.6f m (forward is -Z)" % [
			without.mass_properties.com_m.z, with.mass_properties.com_m.z]
	))
	out.append(TestResult.new(
		"by the weighted mean of the aircraft and the camera, and by nothing else",
		absf(with.mass_properties.com_m.z - expected_z) < POSITION_EPS,
		"got %.9f m, predicted %.9f m from an %.0f g camera seated at z = %.4f m" % [
			with.mass_properties.com_m.z, expected_z, camera_kg * 1000.0, seat.z]
	))
	# A camera is on the centreline, so it may not move the CoM sideways at all. The half of the
	# assertion that says what must NOT change.
	out.append(TestResult.new(
		"and it moves nothing sideways",
		absf(with.mass_properties.com_m.x - without.mass_properties.com_m.x) < POSITION_EPS,
		"com.x %.12f -> %.12f" % [without.mass_properties.com_m.x, with.mass_properties.com_m.x]
	))
	return out


# ---------------------------------------------------------------------------
# 8. Custom components, in all four categories.
# ---------------------------------------------------------------------------
## The shared machinery reached through four subclasses. Read tests/test_custom_escs.gd first for
## the scratch-and-restore shape; what is specific here is that all four are checked in ONE loop,
## which is the assertion that CustomComponents really is shared rather than four copies that
## happen to agree today.
##
## FAILS IF: a subclass forgets its array key or its category word (the record would be refused, or
## worse, land in another category's array), if the dimension refusal is not inherited, or if a
## custom part's mass is added beside the budget rather than out of it.
static func _custom_components_work_in_all_four_categories() -> Array:
	var out: Array = []
	var path := "user://test_electronics_parts.json"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

	var documents := {
		"camera": CustomCameras.new(),
		"vtx": CustomVtxs.new(),
		"antenna": CustomAntennas.new(),
		"receiver": CustomReceivers.new(),
	}
	var records := {
		"camera": CustomCameras.make_record("Shed cam", 20.0, 20.0, 20.0, 20.0,
			"analog", "micro", "CMOS", "measured on my scale"),
		"vtx": CustomVtxs.make_record("Shed vtx", 11.0, 30.0, 20.0, 6.0,
			"analog", "800 mW", "5.8 GHz", "measured on my scale"),
		"antenna": CustomAntennas.make_record("Shed antenna", 9.0, 60.0, 15.0, 15.0,
			"RHCP", "SMA", "2 dBi", "measured on my scale"),
		"receiver": CustomReceivers.make_record("Shed rx", 4.0, 20.0, 12.0, 4.0,
			"ExpressLRS", "2.4 GHz", "dipole", "measured on my scale"),
	}

	# One document per category, written in turn to the SAME file — which is also the check that
	# each subclass hands the other three's arrays back verbatim on save.
	var refusals: Array[String] = []
	for category in documents:
		var document: CustomParts = documents[category]
		document.read_from(path)
		var problems := document.add(records[category])
		if not problems.is_empty():
			refusals.append("%s: %s" % [category, str(problems)])
			continue
		if not document.save(path):
			refusals.append("%s: save failed" % category)
	out.append(TestResult.new(
		"a builder's own part is accepted in all four categories",
		refusals.is_empty(),
		"4 records written to one document" if refusals.is_empty() else str(refusals)
	))

	# They come back through the catalog, in their own categories, and they fly.
	var catalog := PartsCatalog.load_with_custom(path)
	var overrides := {}
	for category in records:
		overrides[category] = String(records[category]["part_id"])
	var custom_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, overrides)

	var fitted_all_four := custom_build.components.size() == Build.OPTIONAL_COMPONENTS.size()
	out.append(TestResult.new(
		"and it is loaded back into its own category and fitted to a build",
		fitted_all_four and catalog.load_errors.is_empty(),
		"%d of 4 fitted, load errors %s" % [custom_build.components.size(), catalog.load_errors]
	))

	# The mass rule, on parts nobody reviewed: 44 g of custom components against a 21 g share is
	# 23 g of excess, and 23 g is exactly what the aircraft gains. Not 44.
	var custom_total := 0.0
	var shares := 0.0
	for category in Build.OPTIONAL_COMPONENTS:
		custom_total += float(records[category]["mass_g"])
		shares += float(Build.CARVED_SHARES[category])
	var gained := custom_build.all_up_weight_g() - ReferenceBuild.build().all_up_weight_g()
	out.append(TestResult.new(
		"a custom component comes out of the budget too, and costs only its excess",
		absf(gained - (custom_total - shares)) < MASS_EPS,
		"%.0f g of custom parts against a %.0f g share gained %.4f g" % [
			custom_total, shares, gained]
	))

	# The refusal every one of the four inherits: no dimensions means a stand-in box and silence.
	var no_dimensions: Dictionary = CustomCameras.make_record("Dimensionless", 8.0, 0.0, 0.0, 0.0,
		"analog", "micro", "CMOS", "off the product page")
	var refused: Array[String] = CustomCameras.new().add(no_dimensions)
	out.append(TestResult.new(
		"and a component with no dimensions is refused, naming all three fields",
		refused.size() == 3,
		str(refused)
	))

	if previous == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var handle := FileAccess.open(path, FileAccess.WRITE)
		handle.store_string(previous)
		handle.close()
	return out


# ---------------------------------------------------------------------------
# 9. The whoop, and the residual this slice did not close.
# ---------------------------------------------------------------------------
## A 65 mm whoop as a real one is built: an AIO board carrying the flight controller, the ESCs, the
## camera and the receiver, with no separate transmitter. Three of the four omitted; the antenna is
## fitted, because a whoop does have one — a 2 g u.FL whip — and pretending otherwise would be
## claiming a saving the aircraft does not make.
##
## THE NUMBER IS STATED AND THE RESIDUAL IS NAMED. A real 65 mm whoop is 20-25 g all-up. This build
## comes out at 64.8 g, against 85.8 g before the unbundling: the 21 g the four components were
## worth is off, and the aircraft is STILL about 2.7x too heavy. The remainder is not mysterious
## and it is not fixed here — part of it is the harness term (`Harness`), and most of
## the rest is the catalog's own whoop-class part masses, where a 22 g frame entry stands for a
## real 6 g moulding. Both are named in the detail so a reader is not left to infer them.
##
## FAILS IF: the omissions do not reach all-up weight, or if this ever gets "fixed" by tuning a
## constant — the assertion is the ARITHMETIC of the before figure less the three shares, so a
## constant moved to flatter the whoop breaks it rather than satisfying it.
static func _a_whoop_with_an_aio() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var whoop_parts := ["frame_65mm_whoop", "motor_0802_19000kv", "prop_16x12x4",
		"battery_1s_300", "esc_aio_5a_whoop", "fc_f411_25x25_whoop"]

	var before := Build.from_ids(catalog, whoop_parts[0], whoop_parts[1], whoop_parts[2],
		whoop_parts[3], whoop_parts[4], whoop_parts[5])
	var after := Build.from_ids(catalog, whoop_parts[0], whoop_parts[1], whoop_parts[2],
		whoop_parts[3], whoop_parts[4], whoop_parts[5],
		{"camera": "", "vtx": "", "receiver": "", "antenna": "antenna_dipole_ufl_nano"})

	var saved := float(Build.CARVED_SHARES["camera"]) + float(Build.CARVED_SHARES["vtx"]) \
		+ float(Build.CARVED_SHARES["receiver"]) \
		+ (float(Build.CARVED_SHARES["antenna"]) - _catalog_mass_g("antenna_dipole_ufl_nano"))

	out.append(TestResult.new(
		"a whoop on an AIO, with no separate camera, VTX or receiver, is lighter by exactly their shares",
		absf((before.all_up_weight_g() - after.all_up_weight_g()) - saved) < MASS_EPS,
		"%.1f g -> %.1f g, a saving of %.1f g" % [
			before.all_up_weight_g(), after.all_up_weight_g(), saved]
	))

	# The honest half. This is a claim about how far the model still is from the aircraft, and it
	# is asserted in BOTH directions: the unbundling helped, and it did not come close to closing
	# the gap. A slice that quietly fixed the whoop by moving a constant would fail the second.
	var real_world_g := 22.5   # the midpoint of the 20-25 g a real 65 mm whoop weighs
	var residual := after.all_up_weight_g() - real_world_g
	out.append(TestResult.new(
		"and it is still about 2.7x too heavy, which this slice did not fix and does not hide",
		after.all_up_weight_g() < before.all_up_weight_g()
			and after.all_up_weight_g() / real_world_g > 2.0,
		"%.1f g against a real %.0f g: %.1f g of residual, of which %.0f g is the flat wiring term and the rest is whoop-class catalog masses (the frame entry alone is %.0f g against a real ~6 g)" % [
			after.all_up_weight_g(), real_world_g, residual, after.harness_mass_g(),
			_catalog_mass_g("frame_65mm_whoop")]
	))
	return out


# ---------------------------------------------------------------------------
# The measurement this slice owes: the before/after span, reported rather than described.
# ---------------------------------------------------------------------------
## The three rows FramePlausibility's header table has always carried, each rebuilt with its own
## class of components fitted the way that class of aircraft is actually built. The reference row
## must not move at all; the other two must move only downward, and only by the shares of what
## they no longer carry.
##
## It asserts the direction and prints the table. What it deliberately does NOT do is assert that
## any row is now CORRECT, because two of them are not.
static func _the_span_table_before_and_after() -> TestResult:
	var catalog := PartsCatalog.load_default()

	var whoop_before := Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_16x12x4", "battery_1s_300", "esc_aio_5a_whoop", "fc_f411_25x25_whoop")
	var whoop_after := Build.from_ids(catalog, "frame_65mm_whoop", "motor_0802_19000kv",
		"prop_16x12x4", "battery_1s_300", "esc_aio_5a_whoop", "fc_f411_25x25_whoop",
		{"camera": "", "vtx": "", "receiver": "", "antenna": "antenna_dipole_ufl_nano"})

	var mid := ReferenceBuild.build()

	# A 10" long-range aircraft carries the heavy end of every one of the four, which is the other
	# half of the original complaint: the flat lump was too LITTLE at kg class, not only too much
	# at whoop class.
	var long_before := Build.from_ids(catalog, "frame_10in_long_range", "motor_2808_1300kv",
		"prop_10x5x2", "battery_6s_4000_liion", "esc_4in1_80a_30x30", "fc_f405_30x30")
	var long_after := Build.from_ids(catalog, "frame_10in_long_range", "motor_2808_1300kv",
		"prop_10x5x2", "battery_6s_4000_liion", "esc_4in1_80a_30x30", "fc_f405_30x30",
		{"camera": "cam_fullsize_analog", "vtx": "vtx_analog_1w6",
		"antenna": "antenna_rhcp_sma_long_range", "receiver": "rx_elrs_900"})

	# 19 g, not 21: the whoop keeps its 2 g antenna, because a whoop has one.
	var whoop_lighter := whoop_after.all_up_weight_g() < whoop_before.all_up_weight_g() - 15.0
	var reference_unmoved := absf(mid.all_up_weight_g() - 507.48) < 0.05
	var long_heavier := long_after.all_up_weight_g() > long_before.all_up_weight_g() + 10.0

	return TestResult.new(
		"the catalog's span moves the way unbundling says it should: lighter at the bottom, heavier at the top, unmoved in the middle",
		whoop_lighter and reference_unmoved and long_heavier,
		"whoop %.1f -> %.1f g (%.1f%% hover -> %.1f%%); reference %.1f -> %.1f g (exact); 10\" %.1f -> %.1f g (%.1f%% hover -> %.1f%%)" % [
			whoop_before.all_up_weight_g(), whoop_after.all_up_weight_g(),
			whoop_before.hover_throttle() * 100.0, whoop_after.hover_throttle() * 100.0,
			507.48, mid.all_up_weight_g(),
			long_before.all_up_weight_g(), long_after.all_up_weight_g(),
			long_before.hover_throttle() * 100.0, long_after.hover_throttle() * 100.0]
	)
