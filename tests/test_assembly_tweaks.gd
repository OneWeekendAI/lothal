class_name TestAssemblyTweaks
extends RefCounted
## The builder's assembly tweaks — shim washers under a prop, a soft-mount pad under a motor,
## taller or shorter standoffs between the centre plates — and the first persisted CONFIGURATION in
## the project (LapTimer already keeps a best lap in user://, but it is one scalar with no schema).
##
## Three things are being pinned here, in ascending order of how expensive they would be to get
## wrong.
##
## 1. THE LIMITS ARE DERIVED. A slider whose range is authored is a slider that lets you shim a
##    0802 by eight millimetres, which is more thread than that motor has. So the range comes out
##    of the same geometry that draws the hardware, and the checks below compare a big motor's
##    range against a small one's rather than against a number written down twice.
##
## 2. THE TWEAKS DO NOT MOVE THE COLLECTIVE FIGURES, and that is asserted rather than assumed.
##    Winding every tweak to its limit must not move all-up weight, thrust-to-weight or hover
##    throttle by so much as a milligram. If it ever does, the reference build's oracles have
##    quietly become a function of a user setting, which would make every number this project
##    reports unreproducible.
##
##    THIS USED TO SAY "geometry-bearing and not physics-bearing", full stop, and that is no longer
##    the whole truth. Where the pack is strapped and how far it is slid now reach the mass model,
##    so they move the centre of mass and the inertia tensor — deliberately, since a mount system
##    that moved the picture and not the physics was the gap that slice closed. What survives
##    untouched is the COLLECTIVE half: mass is mass wherever it sits, and thrust-to-weight and
##    hover throttle are figures about the whole aircraft against gravity. So the invariant is
##    narrowed to what it is actually protecting, and the test below now asserts the other half
##    too — that the inertia DOES move — because an invariant with no counterpart is an invariant
##    that would still pass if the tweaks had been disconnected entirely.
##
## 3. THE FILE SURVIVES BEING WRONG. It is written by an earlier version of the app, hand-edited,
##    truncated by a full disk, or produced by a future version that knows fields this one does
##    not. None of those may crash Lab on startup, and the last of them must not silently destroy
##    the field it does not understand.

const SAVE_PATH := "user://test_assembly_tweaks.json"

static func run() -> Array:
	var results: Array = []
	# THE HOLD ON THE BUILDER'S OWN FILES. Taken here and released below, because a section that
	# aborts mid-way never reaches its own restore — measured, and it is what left a 3500 m
	# elevation and an invented weather row on this developer's disk. `run()` is the only frame
	# GDScript guarantees will resume after an abort inside a section, so the hold lives here and
	# `run()` does nothing else but call sections and append results. See tests/real_files.gd.
	var held := RealFiles.hold([AssemblyTweaks.SAVE_PATH])
	var catalog := PartsCatalog.load_default()

	results.append(_test_defaults_are_the_derived_geometry(catalog))
	results.append(_test_limits_come_from_the_hardware(catalog))
	results.append(_test_values_clamp_and_reset(catalog))
	results.append(_test_the_tweaks_move_the_geometry(catalog))
	results.append(_test_the_tweaks_do_not_move_the_physics(catalog))
	results.append(_test_a_round_trip_through_disk(catalog))
	results.append(_test_a_file_from_the_future_is_tolerated(catalog))
	results.append(_test_a_broken_file_falls_back_to_defaults(catalog))
	results.append(_test_the_panel_moves_the_airframe_and_resets(catalog))
	results.append(_test_the_configuration_survives_a_restart(catalog))

	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))

	return results


# ---------------------------------------------------------------------------
# The panel, and a restart
# ---------------------------------------------------------------------------

## Dragging a slider has to reach the airframe on screen, and the reset has to put it back. Driven
## through the panel rather than the model, because "the three tweaks adjust the geometry live" is a
## statement about the screen and a model-only test would pass with the panel unwired.
static func _test_the_panel_moves_the_airframe_and_resets(catalog: PartsCatalog) -> TestResult:
	var lab := LabScreen.new(catalog, AssemblyTweaks.new())
	var build := lab.current_build()
	var limits := AssemblyTweaks.limits(build)

	var before: float = (lab.airframe.propeller_meshes["M1"] as Node3D).position.y
	# The slider snaps to its own step, so the amount the geometry must move by is what the panel
	# reports it applied — not what was asked for.
	var shim_mm: float = lab.assembly_panel.set_tweak_mm(
		AssemblyTweaks.PROP_SPACER, limits[AssemblyTweaks.PROP_SPACER]["max"])
	var after: float = (lab.airframe.propeller_meshes["M1"] as Node3D).position.y

	var problems: Array[String] = []
	if absf((after - before) - shim_mm / 1000.0) > 1e-6:
		problems.append("the prop moved %.4f m for a %.2f mm shim" % [after - before, shim_mm])
	# The panel must be showing the same number the geometry moved by.
	if absf(lab.tweaks.value_mm(AssemblyTweaks.PROP_SPACER, build) - shim_mm) > 1e-6:
		problems.append("the panel and the model disagree about the shim")

	lab.assembly_panel.reset()
	var reset_to: float = (lab.airframe.propeller_meshes["M1"] as Node3D).position.y
	if absf(reset_to - before) > 1e-9:
		problems.append("reset left the prop at %.4f m, not back at %.4f m" % [reset_to, before])

	lab.free()

	return TestResult.new(
		"a slider moves the airframe live, and reset puts it back",
		problems.is_empty(),
		"prop %.4f -> %.4f -> %.4f m for a %.2f mm shim%s" % [
			before, after, reset_to, shim_mm,
			"" if problems.is_empty() else " — " + str(problems)]
	)


## The acceptance criterion: the configuration survives closing the app. A restart is modelled the
## way it actually happens — a second LabScreen constructed with no tweaks handed to it, so it loads
## from disk exactly as the real startup path does.
static func _test_the_configuration_survives_a_restart(catalog: PartsCatalog) -> TestResult:
	var previous := ""
	if FileAccess.file_exists(AssemblyTweaks.SAVE_PATH):
		previous = FileAccess.get_file_as_string(AssemblyTweaks.SAVE_PATH)

	var first := LabScreen.new(catalog, AssemblyTweaks.new())
	var limits := AssemblyTweaks.limits(first.current_build())
	var shim_mm: float = first.assembly_panel.set_tweak_mm(
		AssemblyTweaks.PROP_SPACER, limits[AssemblyTweaks.PROP_SPACER]["max"])
	var shimmed: float = (first.airframe.propeller_meshes["M1"] as Node3D).position.y
	first.free()

	# No tweaks argument: this is the startup path, and it must find the file the first Lab wrote.
	var second := LabScreen.new(catalog)
	var restarted: float = (second.airframe.propeller_meshes["M1"] as Node3D).position.y
	var reloaded_mm := second.tweaks.value_mm(AssemblyTweaks.PROP_SPACER, second.current_build())
	second.free()

	if previous == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AssemblyTweaks.SAVE_PATH))
	else:
		var handle := FileAccess.open(AssemblyTweaks.SAVE_PATH, FileAccess.WRITE)
		handle.store_string(previous)
		handle.close()

	var passed := absf(restarted - shimmed) < 1e-9 and absf(reloaded_mm - shim_mm) < 1e-6

	return TestResult.new(
		"the fit configuration survives closing and reopening the app",
		passed,
		"a %.2f mm shim came back as %.2f mm; prop at %.4f m before, %.4f m after the restart" % [
			shim_mm, reloaded_mm, shimmed, restarted]
	)


static func _build(catalog: PartsCatalog, frame_id := ReferenceBuild.FRAME_ID,
		motor_id := ReferenceBuild.MOTOR_ID) -> Build:
	return Build.from_ids(catalog, frame_id, motor_id, ReferenceBuild.PROPELLER_ID,
		ReferenceBuild.BATTERY_ID)


# ---------------------------------------------------------------------------
# Values, limits, reset
# ---------------------------------------------------------------------------

## An untouched configuration must describe exactly the build the previous slice drew: no shims,
## no pad, and the standoff height FrameModel derives for this frame. "Default" is not zero for
## all three, and a tweak system whose neutral position changes the airframe would make every
## screenshot in the repo unreproducible.
static func _test_defaults_are_the_derived_geometry(catalog: PartsCatalog) -> TestResult:
	var tweaks := AssemblyTweaks.new()
	var build := _build(catalog)
	var resolved := tweaks.resolved_m(build)

	var expected_gap := FrameModel.default_plate_gap_m()
	var problems: Array[String] = []
	if resolved["prop_spacer_m"] != 0.0:
		problems.append("default prop spacer is %.4f m, not zero" % resolved["prop_spacer_m"])
	if resolved["soft_mount_m"] != 0.0:
		problems.append("default soft mount is %.4f m, not zero" % resolved["soft_mount_m"])
	if absf(resolved["plate_gap_m"] - expected_gap) > 1e-9:
		problems.append("default plate gap is %.4f m, FrameModel derives %.4f m" % [
			resolved["plate_gap_m"], expected_gap])
	for key in AssemblyTweaks.KEYS:
		if tweaks.has_override(key):
			problems.append("%s reads as overridden before anything was set" % key)

	return TestResult.new(
		"an untouched configuration is exactly the geometry the parts already imply",
		problems.is_empty(),
		"spacer %.4f m, pad %.4f m, plate gap %.4f m%s" % [
			resolved["prop_spacer_m"], resolved["soft_mount_m"], resolved["plate_gap_m"],
			"" if problems.is_empty() else " — " + str(problems)]
	)


## The ranges have to be consequences of the chosen parts. A 2807 has more spare thread and a
## taller mounting boss than an 0802, and a 7" frame has room for a taller stack than a 3" one —
## so all three ranges must differ between those builds, in the direction the hardware implies.
static func _test_limits_come_from_the_hardware(catalog: PartsCatalog) -> TestResult:
	var small := AssemblyTweaks.limits(_build(catalog, "frame_3in_toothpick", "motor_0802_19000kv"))
	var large := AssemblyTweaks.limits(_build(catalog, "frame_7in_long_range", "motor_2807_1300kv"))

	var problems: Array[String] = []
	if large[AssemblyTweaks.PROP_SPACER]["max"] <= small[AssemblyTweaks.PROP_SPACER]["max"]:
		problems.append("a 2807 is allowed no more shim than an 0802")
	if large[AssemblyTweaks.SOFT_MOUNT]["max"] <= small[AssemblyTweaks.SOFT_MOUNT]["max"]:
		problems.append("a 2807 is allowed no thicker a pad than an 0802")
	if large[AssemblyTweaks.PLATE_GAP]["max"] <= small[AssemblyTweaks.PLATE_GAP]["max"]:
		problems.append("a 7\" frame is allowed no taller a stack than a 3\" one")

	# Every range has to contain its own default, or the neutral position is unreachable.
	for limits in [small, large]:
		for key in AssemblyTweaks.KEYS:
			var row: Dictionary = limits[key]
			if row["default"] < row["min"] or row["default"] > row["max"]:
				problems.append("%s's default %.2f is outside [%.2f, %.2f]" % [
					key, row["default"], row["min"], row["max"]])
	# And the spacer limit must be the motor's own spare thread, not a number of its own.
	var expected: float = MotorMesh.max_prop_spacer_m(catalog.get_part("motor_2807_1300kv")) * 1000.0
	if absf(large[AssemblyTweaks.PROP_SPACER]["max"] - expected) > 1e-6:
		problems.append("the 2807's shim limit is %.3f mm, its spare thread is %.3f mm" % [
			large[AssemblyTweaks.PROP_SPACER]["max"], expected])

	return TestResult.new(
		"every tweak's range is derived from the parts chosen, not authored",
		problems.is_empty(),
		"0802/3\": shim<=%.2f pad<=%.2f gap<=%.2f mm   2807/7\": shim<=%.2f pad<=%.2f gap<=%.2f mm%s" % [
			small[AssemblyTweaks.PROP_SPACER]["max"], small[AssemblyTweaks.SOFT_MOUNT]["max"],
			small[AssemblyTweaks.PLATE_GAP]["max"], large[AssemblyTweaks.PROP_SPACER]["max"],
			large[AssemblyTweaks.SOFT_MOUNT]["max"], large[AssemblyTweaks.PLATE_GAP]["max"],
			"" if problems.is_empty() else " — " + str(problems)]
	)


## Asking for more than the hardware allows gives you what it allows, not an error and not the
## number you asked for. The stored value is deliberately NOT clamped on the way in — a shim that
## is legal on a 2807 and illegal on an 0802 must come back when you put the 2807 back on, which
## is the same reasoning as Lab never blocking a part choice.
static func _test_values_clamp_and_reset(catalog: PartsCatalog) -> TestResult:
	var build_small := _build(catalog, ReferenceBuild.FRAME_ID, "motor_0802_19000kv")
	var build_large := _build(catalog, ReferenceBuild.FRAME_ID, "motor_2807_1300kv")
	var limits_small: Dictionary = AssemblyTweaks.limits(build_small)[AssemblyTweaks.PROP_SPACER]
	var limits_large: Dictionary = AssemblyTweaks.limits(build_large)[AssemblyTweaks.PROP_SPACER]

	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.PROP_SPACER, limits_large["max"])

	var problems: Array[String] = []
	var on_large := tweaks.value_mm(AssemblyTweaks.PROP_SPACER, build_large)
	var on_small := tweaks.value_mm(AssemblyTweaks.PROP_SPACER, build_small)
	if absf(on_large - limits_large["max"]) > 1e-6:
		problems.append("a legal shim was not kept (%.3f vs %.3f)" % [on_large, limits_large["max"]])
	if absf(on_small - limits_small["max"]) > 1e-6:
		problems.append("the same shim was not clamped on an 0802 (%.3f, limit %.3f)" % [
			on_small, limits_small["max"]])
	if absf(tweaks.value_mm(AssemblyTweaks.PROP_SPACER, build_large) - on_large) > 1e-6:
		problems.append("clamping for a small motor destroyed the stored value")

	tweaks.set_mm(AssemblyTweaks.PLATE_GAP, -50.0)
	var gap_limits: Dictionary = AssemblyTweaks.limits(build_large)[AssemblyTweaks.PLATE_GAP]
	if absf(tweaks.value_mm(AssemblyTweaks.PLATE_GAP, build_large) - gap_limits["min"]) > 1e-6:
		problems.append("a negative plate gap was not clamped up to the minimum")

	tweaks.reset()
	for key in AssemblyTweaks.KEYS:
		if tweaks.has_override(key):
			problems.append("%s survived a reset" % key)
	if absf(tweaks.value_mm(AssemblyTweaks.PLATE_GAP, build_large) - gap_limits["default"]) > 1e-6:
		problems.append("reset did not return the plate gap to its derived default")

	return TestResult.new(
		"values clamp to the current build's limits, keep what was asked for, and reset",
		problems.is_empty(),
		"0802 clamp %.2f mm (asked %.2f), reset to %.2f mm%s" % [
			on_small, limits_large["max"], tweaks.value_mm(AssemblyTweaks.PLATE_GAP, build_large),
			"" if problems.is_empty() else " — " + str(problems)]
	)


# ---------------------------------------------------------------------------
# What they do, and what they must not do
# ---------------------------------------------------------------------------

## Each tweak has to move the thing it names, by the amount it says, measured off the assembled
## geometry rather than off the setting.
static func _test_the_tweaks_move_the_geometry(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var limits := AssemblyTweaks.limits(build)

	var plain := AirframeModel.new()
	plain.rebuild(build)
	var base_prop_y: float = (plain.propeller_meshes["M1"] as Node3D).position.y
	var base_motor := plain.motor_meshes["M1"] as MotorMesh
	var base_bell_y: float = (base_motor.get_node("Bell") as MeshInstance3D).position.y
	var base_gap := _plate_gap_m(plain.frame_model)

	var shim_mm: float = limits[AssemblyTweaks.PROP_SPACER]["max"]
	var pad_mm: float = limits[AssemblyTweaks.SOFT_MOUNT]["max"]
	var gap_mm: float = limits[AssemblyTweaks.PLATE_GAP]["max"]

	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.PROP_SPACER, shim_mm)
	tweaks.set_mm(AssemblyTweaks.SOFT_MOUNT, pad_mm)
	tweaks.set_mm(AssemblyTweaks.PLATE_GAP, gap_mm)

	var shimmed := AirframeModel.new()
	shimmed.rebuild(build, tweaks)
	var new_prop_y: float = (shimmed.propeller_meshes["M1"] as Node3D).position.y
	var new_motor := shimmed.motor_meshes["M1"] as MotorMesh
	var new_bell_y: float = (new_motor.get_node("Bell") as MeshInstance3D).position.y
	var new_gap := _plate_gap_m(shimmed.frame_model)

	var problems: Array[String] = []
	# The prop rises by the shim AND the pad, because the pad lifts the whole motor under it.
	var expected_prop_rise := (shim_mm + pad_mm) / 1000.0
	if absf((new_prop_y - base_prop_y) - expected_prop_rise) > 1e-6:
		problems.append("the prop rose %.4f m, the shim and pad add %.4f m" % [
			new_prop_y - base_prop_y, expected_prop_rise])
	if absf((new_bell_y - base_bell_y) - pad_mm / 1000.0) > 1e-6:
		problems.append("the bell rose %.4f m, the pad is %.4f m" % [
			new_bell_y - base_bell_y, pad_mm / 1000.0])
	if new_motor.get_node_or_null("SoftMount") == null:
		problems.append("no soft-mount pad was drawn")
	if new_motor.get_node_or_null("Spacer") == null:
		problems.append("no shim washers were drawn")
	if absf(new_gap - gap_mm / 1000.0) > 1e-6:
		problems.append("the plates stand %.4f m apart, %.4f m was asked for" % [
			new_gap, gap_mm / 1000.0])
	# And the blade roots must STILL clear the bell — a shim can only ever help, but the pad
	# lifting the motor is the case where a wrong sign would bury them again.
	var bell := new_motor.get_node("Bell") as MeshInstance3D
	var bell_top: float = bell.position.y + (bell.mesh as CylinderMesh).height * 0.5
	var prop: PropellerMesh = shimmed.propeller_meshes["M1"]
	if new_prop_y - prop.underside_m <= bell_top:
		problems.append("the shimmed prop is back inside the bell")

	plain.free()
	shimmed.free()

	return TestResult.new(
		"each tweak moves the geometry it names, by the amount it names",
		problems.is_empty(),
		"prop +%.4f m, bell +%.4f m, plate gap %.4f -> %.4f m%s" % [
			new_prop_y - base_prop_y, new_bell_y - base_bell_y, base_gap, new_gap,
			"" if problems.is_empty() else " — " + str(problems)]
	)


## The decision, as a test. These are fit adjustments: they change what clears what, and they do
## not change the aircraft's mass properties or its performance.
##
## The test is written against the SAVED FILE at its real path rather than against an object passed
## in, because that is the shape the mistake would actually take: not somebody handing tweaks to
## MassProperties on purpose, but a later slice reaching for AssemblyTweaks.load_from() inside
## Build to "account for the shim", at which point the reference oracles quietly become a function
## of one user's settings and nobody can reproduce anybody else's numbers again. A freshly
## constructed Build, with a file on disk holding all three tweaks at their limits, has to produce
## exactly the figures a Build produced before that file existed.
##
## The comparison is proved sensitive in the same breath: the same five figures are read from a
## build that differs only by its pack, and those MUST differ. Otherwise this is a test that
## compares two things that were never going to disagree.
static func _test_the_tweaks_do_not_move_the_physics(catalog: PartsCatalog) -> TestResult:
	var stats := func(build: Build) -> Array:
		return [build.all_up_weight_g(), build.thrust_to_weight(), build.hover_throttle(),
			build.flight_time_min(), build.top_speed_kmh()]

	var before: Array = stats.call(_build(catalog))

	# Save and restore whatever the developer running the suite actually has configured.
	var previous := ""
	if FileAccess.file_exists(AssemblyTweaks.SAVE_PATH):
		previous = FileAccess.get_file_as_string(AssemblyTweaks.SAVE_PATH)

	var limits := AssemblyTweaks.limits(_build(catalog))
	var tweaks := AssemblyTweaks.new()
	for key in AssemblyTweaks.KEYS:
		tweaks.set_mm(key, limits[key]["max"])
	tweaks.save()

	var after: Array = stats.call(_build(catalog))

	if previous == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AssemblyTweaks.SAVE_PATH))
	else:
		var handle := FileAccess.open(AssemblyTweaks.SAVE_PATH, FileAccess.WRITE)
		handle.store_string(previous)
		handle.close()

	var unchanged := true
	for i in before.size():
		if before[i] != after[i]:
			unchanged = false

	# The control: something that IS physics-bearing must move these numbers, or the comparison
	# above is vacuous.
	var other_pack: Array = stats.call(Build.from_ids(catalog, ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, "battery_6s_1300"))
	var comparison_works := false
	for i in before.size():
		if before[i] != other_pack[i]:
			comparison_works = true

	# The other half, and the one that makes the invariant above mean something. Reading the five
	# collective figures off a build that was never handed an assembly would pass this test with the
	# tweaks disconnected at the wall. So the same wound-to-the-limit configuration is applied
	# through the path Lab uses, and the ROTATIONAL properties are required to move: a pack slid to
	# the end of its travel is mass at a distance, and pitch inertia has to hear about it.
	var wound := _build(catalog)
	var centred_pitch := wound.mass_properties.inertia.x.x
	var centred_com := wound.mass_properties.com_m
	var at_limits := AssemblyTweaks.new()
	for key in AssemblyTweaks.KEYS:
		at_limits.set_mm(key, limits[key]["max"])
	wound.set_assembly(at_limits.resolved_m(wound))
	var moved: bool = wound.mass_properties.inertia.x.x > centred_pitch * 1.001 \
		and (wound.mass_properties.com_m - centred_com).length() > 1e-4

	return TestResult.new(
		"the tweaks move the rotational figures and not the collective ones",
		unchanged and comparison_works and moved,
		("%.1f g / %.2f:1 / %.4f hover, unchanged by a saved file at every limit; a 6S pack does "
			+ "move it (%.4f hover); pitch inertia %.8f -> %.8f and the CoM %.1f mm with the pack "
			+ "slid to its stop") % [
			before[0], before[1], before[2], other_pack[2],
			centred_pitch, wound.mass_properties.inertia.x.x,
			(wound.mass_properties.com_m - centred_com).length() * 1000.0]
	)


static func _plate_gap_m(frame: FrameModel) -> float:
	var top := frame.get_node("PlateTop") as MeshInstance3D
	var bottom := frame.get_node("PlateBottom") as MeshInstance3D
	return top.position.y - bottom.position.y


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## The point of the whole exercise: close the app, open it, and your shims are still there.
static func _test_a_round_trip_through_disk(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var limits := AssemblyTweaks.limits(build)

	var written := AssemblyTweaks.new()
	written.set_mm(AssemblyTweaks.PROP_SPACER, 1.25)
	written.set_mm(AssemblyTweaks.PLATE_GAP, limits[AssemblyTweaks.PLATE_GAP]["max"])
	var saved := written.save(SAVE_PATH)

	var reloaded := AssemblyTweaks.load_from(SAVE_PATH)

	var problems: Array[String] = []
	if not saved:
		problems.append("save reported failure")
	if absf(reloaded.value_mm(AssemblyTweaks.PROP_SPACER, build) - 1.25) > 1e-6:
		problems.append("the shim came back as %.4f mm" % reloaded.value_mm(AssemblyTweaks.PROP_SPACER, build))
	if absf(reloaded.value_mm(AssemblyTweaks.PLATE_GAP, build)
			- written.value_mm(AssemblyTweaks.PLATE_GAP, build)) > 1e-6:
		problems.append("the plate gap did not survive the trip")
	# What was never set must still be unset, not zero-filled by the file.
	if reloaded.has_override(AssemblyTweaks.SOFT_MOUNT):
		problems.append("the untouched pad came back as an override")

	# And an absent file is the first-run case: defaults, no error.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var fresh := AssemblyTweaks.load_from(SAVE_PATH)
	for key in AssemblyTweaks.KEYS:
		if fresh.has_override(key):
			problems.append("%s came back from a file that does not exist" % key)

	return TestResult.new(
		"a saved configuration reloads unchanged, and a missing file means defaults",
		problems.is_empty(),
		"shim 1.25 mm and a plate gap round-tripped, first run is clean%s" % (
			"" if problems.is_empty() else " — " + str(problems))
	)


## A file written by a later version of Lothal, containing a tweak this version has never heard
## of. It must read the fields it knows, ignore the one it does not — and PRESERVE it on the way
## back out, because destroying a newer version's setting the moment an older build touches the
## file is the kind of data loss the user never sees until they go back.
static func _test_a_file_from_the_future_is_tolerated(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var path := "user://test_assembly_tweaks_future.json"
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(JSON.stringify({
		"schema": AssemblyTweaks.SCHEMA_VERSION,
		"tweaks": {
			AssemblyTweaks.PROP_SPACER: 0.8,
			"esc_standoff_mm": 4.5,           # from a later slice
			AssemblyTweaks.SOFT_MOUNT: "thick",  # and a field of the wrong type
		},
		"pack_charge_fraction": 0.42,          # a whole block from a later slice
	}))
	handle.close()

	var loaded := AssemblyTweaks.load_from(path)
	var problems: Array[String] = []
	if absf(loaded.value_mm(AssemblyTweaks.PROP_SPACER, build) - 0.8) > 1e-6:
		problems.append("the known field was not read (%.3f)" % loaded.value_mm(AssemblyTweaks.PROP_SPACER, build))
	if loaded.has_override(AssemblyTweaks.SOFT_MOUNT):
		problems.append("a non-numeric value was accepted as an override")

	loaded.save(path)
	var round_tripped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not round_tripped.get("tweaks", {}).has("esc_standoff_mm"):
		problems.append("the unknown tweak was destroyed on save")
	if not round_tripped.has("pack_charge_fraction"):
		problems.append("the unknown top-level block was destroyed on save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	return TestResult.new(
		"a file from a later version keeps its unknown fields and does not break this one",
		problems.is_empty(),
		"read the shim, ignored esc_standoff_mm and a string pad, kept both on save%s" % (
			"" if problems.is_empty() else " — " + str(problems))
	)


## Truncated, or hand-edited into invalid JSON, or the right JSON of the wrong shape. Lab has to
## open. A workbench that will not start because a settings file is half-written is a workbench
## that has made a preference more important than the product.
static func _test_a_broken_file_falls_back_to_defaults(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var path := "user://test_assembly_tweaks_broken.json"
	var problems: Array[String] = []

	for contents in ["{\"schema\": 1, \"tweaks\": {\"prop_spa", "not json at all", "[1, 2, 3]", ""]:
		var handle := FileAccess.open(path, FileAccess.WRITE)
		handle.store_string(contents)
		handle.close()

		var loaded := AssemblyTweaks.load_from(path)
		if loaded == null:
			problems.append("loading %s returned null" % contents.substr(0, 12))
			continue
		var resolved := loaded.resolved_m(build)
		if resolved["prop_spacer_m"] != 0.0 or resolved["soft_mount_m"] != 0.0:
			problems.append("%s produced non-default tweaks" % contents.substr(0, 12))
		if absf(resolved["plate_gap_m"] - FrameModel.default_plate_gap_m()) > 1e-9:
			problems.append("%s produced a non-default plate gap" % contents.substr(0, 12))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	return TestResult.new(
		"a truncated or invalid file loads as defaults instead of stopping Lab",
		problems.is_empty(),
		"4 broken files, %s" % ("all opened as defaults" if problems.is_empty() else str(problems))
	)
