class_name TestKeyboardThrottle
extends RefCounted
## Keyboard throttle authority, checked against the physics rather than against a constant.
##
## This exists because of a real failure found on ship day: with a fixed +0.12 absolute
## trim, holding the climb key on the reference build produced roughly 1 g of climb, and
## the drone crossed gate 1's plane 5.8 m off-centre through a 1.5 m ring — it flew over
## every gate instead of through them. Keyboard input is bang-bang, so whatever the key
## does when held IS the control authority; it has to be a flyable amount on every build in
## the catalog, not just on the one that happened to be selected.

## main.gd is a scene root and deliberately carries no class_name, so it is preloaded here
## rather than adding a global class just for the test.
const Main := preload("res://src/scenes/main.gd")

## Holding the key should climb, but gently enough to still hit a gate.
const MIN_CLIMB_G := 0.10
const MAX_CLIMB_G := 0.45

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	var worst_name := ""
	var worst_climb_g := Main.KEYBOARD_CLIMB_G
	var checked := 0
	var all_in_band := true

	# Every battery in the catalog against the reference airframe: pack choice is what moves
	# hover throttle most, which is exactly what an absolute trim gets wrong.
	for battery in catalog.list_category("battery"):
		var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, battery["part_id"])
		if not build.can_hover():
			continue

		var hover := build.hover_throttle()
		var climb_g := _climb_g_at(build, Main.keyboard_throttle(hover, 1.0))
		checked += 1
		if climb_g < MIN_CLIMB_G or climb_g > MAX_CLIMB_G:
			all_in_band = false
		if absf(climb_g - Main.KEYBOARD_CLIMB_G) > absf(worst_climb_g - Main.KEYBOARD_CLIMB_G):
			worst_climb_g = climb_g
			worst_name = battery["name"]

	results.append(TestResult.new(
		"holding the keyboard climb key gives a flyable climb on every pack in the catalog",
		all_in_band and checked >= 4,
		"%d packs checked, furthest from target was %s at %.2f g" % [checked, worst_name, worst_climb_g]
	))

	var reference := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)
	var hover := reference.hover_throttle()

	results.append(TestResult.new(
		"a centred throttle key holds hover exactly",
		is_equal_approx(Main.keyboard_throttle(hover, 0.0), hover),
		"axis 0 -> %.4f (hover = %.4f)" % [Main.keyboard_throttle(hover, 0.0), hover]
	))

	results.append(TestResult.new(
		"the descend key reduces thrust below weight without cutting the motors",
		Main.keyboard_throttle(hover, -1.0) < hover and Main.keyboard_throttle(hover, -1.0) > hover * 0.5,
		"axis -1 -> %.1f %% (hover = %.1f %%)" % [Main.keyboard_throttle(hover, -1.0) * 100.0, hover * 100.0]
	))

	# The regression that started all this, stated the way it was actually observed: from the
	# start line, holding the climb key must not put the drone above gate 1's ring by the
	# time it reaches the gate's plane. Measured over the real approach distance at the
	# rise-from-rest the model gives, which is what the failing run did.
	#
	# Note this is NOT a claim that the drone cannot out-climb a gate — an 11.7:1 airframe
	# absolutely can, and so can the real thing. It is a claim about the *first second* off
	# the start line, which is the part a new pilot has no chance to correct.
	var climb_g := _climb_g_at(reference, Main.keyboard_throttle(hover, 1.0))
	var rise_after_1s := 0.5 * climb_g * 9.81 * 1.0
	results.append(TestResult.new(
		"one second of held climb key does not put the drone above gate 1's ring",
		rise_after_1s < GateCourse.GATE_INNER_RADIUS_M,
		"rises %.2f m in the first second (ring radius %.1f m, %.2f g)" % [
			rise_after_1s, GateCourse.GATE_INNER_RADIUS_M, climb_g]
	))

	return results

## Net vertical acceleration in g at a given throttle, hovering level.
static func _climb_g_at(build: Build, throttle: float) -> float:
	return (build.thrust_at_throttle_n(throttle) - build.weight_n()) / build.weight_n()
