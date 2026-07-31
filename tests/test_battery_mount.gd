class_name TestBatteryMount
extends RefCounted
## Where the pack goes, and what happens to the fit check when it goes somewhere else.
##
## The pack was strapped to the top plate by one hardcoded line, which is why "I want it
## underneath" had no answer. The fix is not a second hardcoded line — it is that the pack attaches
## to a MOUNT POINT like everything else, and top and bottom are two of the frame's mounts rather
## than two branches in the assembler.
##
## The two rules of labs-and-sim.md §2.5 are what these tests are really checking:
##
## - **Limits come from the parts.** The fore/aft range is the frame's own forward reach less half
##   the pack's own length, so choosing a longer pack narrows it while you watch. A constant range
##   passes nothing here.
## - **Geometry-bearing, not physics-bearing.** Sliding the pack moves what clears what and moves
##   no flight number at all — asserted at both ends of the travel.
##
## The overhang and prop-clearance warnings have to FOLLOW the pack. A fit check measured against
## the pack's old home is worse than no fit check: it would keep saying the build is fine while the
## picture shows a pack buried in the front props.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_the_pack_can_hang_under_the_bottom_plate(catalog))
	results.append(_test_the_pack_slides_fore_and_aft(catalog))
	results.append(_test_a_longer_pack_has_less_travel(catalog))
	results.append(_test_the_prop_warning_follows_the_pack(catalog))
	results.append(_test_a_frame_without_a_bottom_mount_falls_back(catalog))
	results.append(_test_sliding_the_pack_moves_no_flight_number(catalog))
	results.append(_test_the_mount_choice_survives_a_restart(catalog))
	results.append(_test_the_panel_offers_the_mounts_the_frame_has(catalog))

	return results


## The pack's mount is configuration, and configuration that does not survive closing the app is
## not configuration. Written and read back through the same file the shims already use — extended,
## not duplicated — and stored as the mount's own id rather than as an index into a list, because
## an index means something different the day a frame gains a mount.
static func _test_the_mount_choice_survives_a_restart(catalog: PartsCatalog) -> TestResult:
	var path := "user://test_battery_mount.json"
	var build := ReferenceBuild.build()

	var written := AssemblyTweaks.new()
	written.set_choice(AssemblyTweaks.BATTERY_MOUNT, "strap_bottom")
	written.set_mm(AssemblyTweaks.BATTERY_OFFSET, -12.0)
	written.set_mm(AssemblyTweaks.PROP_SPACER, 1.0)
	var saved := written.save(path)

	var reloaded := AssemblyTweaks.load_from(path)
	var mount := reloaded.value_choice(AssemblyTweaks.BATTERY_MOUNT, build)
	var offset := reloaded.value_mm(AssemblyTweaks.BATTERY_OFFSET, build)
	var spacer := reloaded.value_mm(AssemblyTweaks.PROP_SPACER, build)

	# A name this version has never heard of resolves to the default rather than being obeyed or
	# crashing — the frame decides which mount names are real, and it is not consulted until now.
	JsonStore.write_document(path, {"schema": 1, "tweaks": {"battery_mount": "strap_sideways"}})
	var nonsense := AssemblyTweaks.load_from(path).value_choice(AssemblyTweaks.BATTERY_MOUNT, build)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	return TestResult.new(
		"the pack's mount and offset survive a restart, alongside the shims",
		saved and mount == "strap_bottom" and absf(offset - -12.0) < 0.001 \
			and absf(spacer - 1.0) < 0.001 and nonsense == "strap_top",
		"reloaded %s at %.1f mm (spacer %.1f mm); an unknown mount name reads as %s" % [
			mount, offset, spacer, nonsense])


## The panel offers what the FRAME offers and nothing more: two places to strap a pack on a 5"
## freestyle, one on a 3" toothpick. A dropdown with a fixed pair of entries would be a second
## opinion about what the hardware allows, which is the §2.5 rule the sliders already obey.
static func _test_the_panel_offers_the_mounts_the_frame_has(catalog: PartsCatalog) -> TestResult:
	var freestyle := ReferenceBuild.build()
	var toothpick := Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", ReferenceBuild.BATTERY_ID)

	var tweaks := AssemblyTweaks.new()
	var panel := AssemblyPanel.new(tweaks)

	var big_airframe := AirframeModel.new()
	big_airframe.rebuild(freestyle, tweaks)
	panel.render(freestyle, big_airframe)
	var big_options: Array[String] = panel.mount_options(AssemblyTweaks.BATTERY_MOUNT)

	# Choosing the underside must actually move the pack, through the panel rather than around it.
	panel.set_mount(AssemblyTweaks.BATTERY_MOUNT, "strap_bottom")
	big_airframe.rebuild(freestyle, tweaks)
	var went_under: bool = _in_airframe(big_airframe.battery_mesh, big_airframe).y < 0.0

	var small_airframe := AirframeModel.new()
	small_airframe.rebuild(toothpick, tweaks)
	panel.render(toothpick, small_airframe)
	var small_options: Array[String] = panel.mount_options(AssemblyTweaks.BATTERY_MOUNT)

	var passed: bool = big_options.size() == 2 and small_options.size() == 1 \
		and big_options.has("strap_top") and big_options.has("strap_bottom") \
		and small_options == ["strap_top"] and went_under

	panel.free()
	big_airframe.free()
	small_airframe.free()
	return TestResult.new(
		"the mount dropdown offers exactly the mounts the fitted frame has",
		passed,
		"5\" freestyle offers %s, 3\" toothpick offers %s; choosing the underside moved the pack: %s" % [
			big_options, small_options, went_under])


## Bottom-mounted, the pack hangs BELOW the bottom plate rather than sinking into it: its upper
## face lands on the plate's underside, which is the mount's seat, and the whole pack is under it.
static func _test_the_pack_can_hang_under_the_bottom_plate(catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()
	var airframe := AirframeModel.new()
	airframe.rebuild(build, _tweaks_with(build, "strap_bottom", 0.0))

	var mount := airframe.mount_point("strap_bottom")
	var detail := ""
	var passed := true

	if mount == null:
		passed = false
		detail = "the 5\" freestyle offers no bottom mount"
	else:
		var pack_y: float = _in_airframe(airframe.battery_mesh, airframe).y
		var top_of_pack: float = pack_y + airframe.battery_mesh.size_m.y * 0.5
		if absf(top_of_pack - mount.position.y) > EPS:
			passed = false
			detail += "the pack's top face is at y=%.4f, the mount seat at y=%.4f; " % [
				top_of_pack, mount.position.y]
		if pack_y >= 0.0:
			passed = false
			detail += "the pack is not below the airframe (centre y=%.4f); " % pack_y
		if passed:
			detail = "pack centre at y=%.4f, hanging under a plate at y=%.4f" % [
				pack_y, mount.position.y]

	# And the top mount still works, or "it moved" would be indistinguishable from "it broke".
	var top_airframe := AirframeModel.new()
	top_airframe.rebuild(build, _tweaks_with(build, "strap_top", 0.0))
	var top_pack_y: float = _in_airframe(top_airframe.battery_mesh, top_airframe).y
	if top_pack_y <= 0.0:
		passed = false
		detail += "top-mounted, the pack is not above the airframe (y=%.4f); " % top_pack_y

	airframe.free()
	top_airframe.free()
	return TestResult.new("the pack mounts under the bottom plate as well as over the top", passed, detail)


## Nose is -Z (physics.md §1), so sliding the pack FORWARD moves it toward negative Z. Measured off
## the drawn pack, in the airframe's own space.
static func _test_the_pack_slides_fore_and_aft(catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()

	var forward := AirframeModel.new()
	forward.rebuild(build, _tweaks_with(build, "strap_top", 30.0))
	var aft := AirframeModel.new()
	aft.rebuild(build, _tweaks_with(build, "strap_top", -30.0))
	var centred := AirframeModel.new()
	centred.rebuild(build, _tweaks_with(build, "strap_top", 0.0))

	var forward_z: float = _in_airframe(forward.battery_mesh, forward).z
	var aft_z: float = _in_airframe(aft.battery_mesh, aft).z
	var centred_z: float = _in_airframe(centred.battery_mesh, centred).z

	var passed := absf(centred_z) < EPS \
		and absf(forward_z - -0.030) < EPS \
		and absf(aft_z - 0.030) < EPS

	forward.free()
	aft.free()
	centred.free()
	return TestResult.new(
		"a fore/aft offset slides the pack along the aircraft's forward axis",
		passed,
		"centred z=%.4f, +30 mm forward z=%.4f (want -0.030), -30 mm aft z=%.4f (want +0.030)" % [
			centred_z, forward_z, aft_z])


## Limits come from the parts. A 2S 300 is 45 mm long and a 6S 4000 Li-ion is 78 mm, on the same
## frame, so the long one has a third less room to move. A range typed into the panel would be the
## same for both.
static func _test_a_longer_pack_has_less_travel(catalog: PartsCatalog) -> TestResult:
	var short_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "battery_2s_300")
	var long_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "battery_6s_4000_liion")

	var short_max: float = AssemblyTweaks.limits(short_build)[AssemblyTweaks.BATTERY_OFFSET]["max"]
	var long_max: float = AssemblyTweaks.limits(long_build)[AssemblyTweaks.BATTERY_OFFSET]["max"]

	# The frame reaches 77.8 mm forward; half of a 45 mm pack is 22.5 and half of a 78 mm pack is
	# 39. Both worked out on paper from frames.json and batteries.json before this ran.
	var passed := absf(short_max - 55.3) < 0.5 and absf(long_max - 38.8) < 0.5 \
		and long_max < short_max

	return TestResult.new(
		"choosing a longer pack narrows its own fore/aft range",
		passed,
		"45 mm pack travels +/-%.1f mm (want 55.3), 78 mm pack +/-%.1f mm (want 38.8)" % [
			short_max, long_max])


## The warning follows the pack. The reference 4S 1500 on the reference frame clears the front
## discs by 9 mm sitting centred, and reaches into them once it is slid all the way forward — so
## the same build must be silent at one offset and warned about at the other. A fit check still
## measuring the pack's old home would be silent at both.
static func _test_the_prop_warning_follows_the_pack(catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()
	var travel: float = AssemblyTweaks.limits(build)[AssemblyTweaks.BATTERY_OFFSET]["max"]

	var centred := AirframeModel.new()
	centred.rebuild(build, _tweaks_with(build, "strap_top", 0.0))
	var forward := AirframeModel.new()
	forward.rebuild(build, _tweaks_with(build, "strap_top", travel))

	var centred_clearance := centred.battery_prop_clearance_m()
	var forward_clearance := forward.battery_prop_clearance_m()

	var forward_says_so := false
	for warning in forward.battery_fit_warnings():
		if warning.contains("propeller discs"):
			forward_says_so = true

	var passed := centred_clearance > 0.0 \
		and forward_clearance < 0.0 \
		and centred.battery_fit_warnings().is_empty() \
		and forward_says_so

	centred.free()
	forward.free()
	return TestResult.new(
		"the propeller-clearance warning follows the pack forward",
		passed,
		"centred: %.1f mm clear, no warnings; slid %.1f mm forward: %.1f mm clear, warned: %s" % [
			centred_clearance * 1000.0, travel, forward_clearance * 1000.0, forward_says_so])


## A 3" toothpick has no room under its plate for a strap slot, so it offers no bottom mount. A
## configuration that asks for one anyway is not an error and is not silently rewritten — it
## resolves to what this frame does have, and comes back the moment a frame that has it is fitted.
static func _test_a_frame_without_a_bottom_mount_falls_back(catalog: PartsCatalog) -> TestResult:
	var toothpick := Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", ReferenceBuild.BATTERY_ID)
	var freestyle := ReferenceBuild.build()

	var tweaks := AssemblyTweaks.new()
	tweaks.set_choice(AssemblyTweaks.BATTERY_MOUNT, "strap_bottom")

	var on_toothpick := tweaks.value_choice(AssemblyTweaks.BATTERY_MOUNT, toothpick)
	var on_freestyle := tweaks.value_choice(AssemblyTweaks.BATTERY_MOUNT, freestyle)

	return TestResult.new(
		"a bottom mount asked of a frame that has none resolves to the top, and comes back",
		on_toothpick == "strap_top" and on_freestyle == "strap_bottom",
		"3\" toothpick resolves to %s, 5\" freestyle to %s" % [on_toothpick, on_freestyle])


## Geometry-bearing, not physics-bearing. The pack is the heaviest single component on most builds,
## and sliding it 40 mm forward would obviously move a real aircraft's centre of gravity — and
## moves nothing in this model, because this model has no centre-of-gravity term to move. Asserted
## rather than assumed, because the day someone wires a mount position into mass_parts() the
## reference build's oracles stop being reproducible from a parts list alone.
static func _test_sliding_the_pack_moves_no_flight_number(catalog: PartsCatalog) -> TestResult:
	var build := ReferenceBuild.build()
	var travel: float = AssemblyTweaks.limits(build)[AssemblyTweaks.BATTERY_OFFSET]["max"]

	var baseline := [build.all_up_weight_g(), build.thrust_to_weight(), build.hover_throttle()]

	# The Build is what the physics reads, and it is rebuilt from the same parts with the tweaks
	# applied — if a mount offset had a way in, this is where it would arrive.
	var moved := ReferenceBuild.build()
	var tweaks := _tweaks_with(moved, "strap_bottom", travel)
	var airframe := AirframeModel.new()
	airframe.rebuild(moved, tweaks)
	var after := [moved.all_up_weight_g(), moved.thrust_to_weight(), moved.hover_throttle()]
	airframe.free()

	var passed := absf(after[0] - baseline[0]) < 0.001 \
		and absf(after[1] - baseline[1]) < 0.0001 \
		and absf(after[2] - baseline[2]) < 0.0001

	return TestResult.new(
		"moving the pack to the underside and sliding it forward moves no flight number",
		passed,
		"before %.3f g / %.4f:1 / %.4f hover; after %.3f g / %.4f:1 / %.4f hover" % [
			baseline[0], baseline[1], baseline[2], after[0], after[1], after[2]])


## Where a node sits in the airframe's own space, composed by walking up to it. global_position is
## not usable here: these airframes are built for the test and never parented into a SceneTree, so
## it reports nothing. Walking the chain also means the test does not care WHICH node the pack ends
## up hanging off, only where it lands.
static func _in_airframe(node: Node3D, airframe: AirframeModel) -> Vector3:
	var out := Vector3.ZERO
	var walker: Node = node
	while walker != null and walker != airframe:
		out += (walker as Node3D).position
		walker = walker.get_parent()
	return out


static func _tweaks_with(build: Build, mount_id: String, offset_mm: float) -> AssemblyTweaks:
	var tweaks := AssemblyTweaks.new()
	tweaks.set_choice(AssemblyTweaks.BATTERY_MOUNT, mount_id)
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, offset_mm)
	# Referenced so the signature stays honest about needing a build; the values are resolved
	# against one at read time, not here.
	assert(build != null)
	return tweaks
