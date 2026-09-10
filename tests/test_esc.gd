class_name TestEsc
extends RefCounted
## The ESC as a part: what it passes, what it weighs, and when it is the thing stopping you.
##
## ---------------------------------------------------------------------------
## RATINGS ARE PER MOTOR
## ---------------------------------------------------------------------------
##
## A "45A 4-in-1" is four 45 A channels, so it passes 180 A in total. Reading it as 45 A for the
## whole aircraft would make every board in the catalog the binding constraint on every build —
## which is a failure that looks exactly like a working feature, because the ESC would always be
## named and the number would always be plausible. It is asserted here first and directly.
##
## ---------------------------------------------------------------------------
## THREE LIMITS, AND THE POINT IS WHICH ONE BINDS
## ---------------------------------------------------------------------------
##
## Current is limited by whichever of the ESC, the motors and the pack gives out first. A builder
## who knows they are capped learns nothing; a builder who knows WHICH part caps them knows what
## to buy. So these tests check the attribution, and they check it in all three directions — a
## model that named the same component every time would satisfy any single-case check.
##
## ---------------------------------------------------------------------------
## THE BUDGET DOES NOT GROW
## ---------------------------------------------------------------------------
##
## The ESC's mass comes OUT of Build.ELECTRONICS_BUDGET_G, exactly as the flight controller's did.
## The reference build must still weigh 496 g to the gram, and a heavier board must still make the
## aircraft heavier — both, or the unbundling has either moved a fixed point or achieved nothing.

const REFERENCE_ESC := "esc_4in1_45a_30x30"
const SMALL_ESC := "esc_4in1_20a_20x20"
const BIG_ESC := "esc_4in1_80a_30x30"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_the_catalog_loads_and_is_two_tier(catalog))
	results.append_array(_test_ratings_are_per_motor(catalog))
	results.append_array(_test_the_binding_constraint_is_reported(catalog))
	results.append_array(_test_the_esc_can_be_the_limit(catalog))
	results.append_array(_test_the_mass_came_out_of_the_lump(catalog))
	results.append_array(_test_it_has_to_bolt_on(catalog))

	return results


static func _build(catalog: PartsCatalog, motor_id: String, battery_id: String, esc_id: String) -> Build:
	return Build.from_ids(catalog, "frame_5in_freestyle", motor_id, "prop_5x43x3", battery_id, esc_id)


# ---------------------------------------------------------------------------
# The catalog
# ---------------------------------------------------------------------------

static func _test_the_catalog_loads_and_is_two_tier(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var escs := catalog.list_category("esc")

	results.append(TestResult.new(
		"the ESC catalog loads as a category alongside the other four",
		escs.size() >= 4 and catalog.is_valid(),
		"%d boards; catalog errors: %s" % [escs.size(),
			"none" if catalog.load_errors.is_empty() else ", ".join(catalog.load_errors)]
	))

	# Every board carries the physics-bearing fields, a bolt pattern, a real mass, and a source.
	# The source string is the project's whole defence against a plausible invented number.
	var incomplete: Array = []
	for board in escs:
		var board_specs: Dictionary = board.get("specs", {})
		var mounting: Dictionary = board.get("mounting", {})
		if not (board_specs.has("continuous_a") and board_specs.has("burst_a") and board_specs.has("channels")):
			incomplete.append("%s: specs" % board["part_id"])
		elif float(board.get("mass_g", 0.0)) <= 0.0:
			incomplete.append("%s: mass" % board["part_id"])
		elif str(mounting.get("pattern", "")) == "":
			incomplete.append("%s: mount pattern" % board["part_id"])
		elif str(board.get("source", "")).length() < 20:
			incomplete.append("%s: source" % board["part_id"])
	results.append(TestResult.new(
		"every board states its ratings, its mass, its bolt pattern and where the numbers came from",
		incomplete.is_empty(),
		"checked %d boards; %s" % [escs.size(),
			"all complete" if incomplete.is_empty() else ", ".join(incomplete)]
	))

	# Burst is carried and must be above continuous, or it is not a burst rating. It is
	# deliberately NOT used as a limit — see escs.json's _schema — and this asserts that too, by
	# checking that the throttle ceiling is the continuous figure's and not the burst figure's.
	var build := _build(catalog, "motor_2207_1960kv", "battery_6s_1300", SMALL_ESC)
	var specs: Dictionary = build.esc["specs"]
	results.append(TestResult.new(
		"burst is above continuous and is NOT what the limit is taken from",
		float(specs["burst_a"]) > float(specs["continuous_a"])
			and is_equal_approx(build.esc_max_amps(),
				float(specs["continuous_a"]) * float(specs["channels"])),
		"%.0f A continuous / %.0f A burst per channel; limit uses %.0f A total" % [
			float(specs["continuous_a"]), float(specs["burst_a"]), build.esc_max_amps()]
	))

	return results


## The one that would catch the expensive misreading. A 45 A 4-in-1 passes 180 A, not 45 A.
static func _test_ratings_are_per_motor(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, "motor_2207_1960kv", "battery_4s_1500", REFERENCE_ESC)

	results.append(TestResult.new(
		"a 45 A 4-in-1 passes 180 A in total, because the rating is per channel",
		absf(build.esc_max_amps() - 180.0) < 0.01,
		"%.0f A across %d channels" % [
			build.esc_max_amps(), int(build.esc["specs"]["channels"])]
	))

	# ...and therefore the reference build's board is NOT its limit. If ratings were read per
	# board this would be a 45 A ESC against a 112 A pack, the ESC would bind, and the reference
	# build's ceiling would be wrong in a way that looked entirely reasonable on screen.
	results.append(TestResult.new(
		"the reference build's board has headroom over both its pack and its motors",
		build.esc_max_amps() > build.pack_max_amps()
			and build.esc_max_amps() > 4.0 * float(build.motor["specs"]["max_amps"])
			and build.limiting_component()["name"] != "esc",
		"ESC %.0f A vs pack %.0f A vs motors %.0f A; limited by %s" % [
			build.esc_max_amps(), build.pack_max_amps(),
			4.0 * float(build.motor["specs"]["max_amps"]), build.limiting_component()["name"]]
	))

	return results


# ---------------------------------------------------------------------------
# Which of the three binds
# ---------------------------------------------------------------------------

## All three directions, because an attribution that is always the same answer is not an
## attribution. Each build below is contrived so exactly one component is the weak link.
static func _test_the_binding_constraint_is_reported(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# Small board, strong pack, strong motors -> the ESC. 20 A x 4 = 80 A against 130 A of pack.
	var esc_bound := _build(catalog, "motor_2207_1960kv", "battery_6s_1300", SMALL_ESC)
	# Weak pack, big board -> the battery. 3000 mAh at 10C is 30 A against 320 A of ESC.
	var pack_bound := _build(catalog, "motor_2207_1960kv", "battery_4s_3000_liion", BIG_ESC)
	# Small motors, big board, big pack -> the motors.
	var motor_bound := Build.from_ids(catalog, "frame_5in_freestyle", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_1300", BIG_ESC)

	var expectations := [
		{"build": esc_bound, "want": "esc"},
		{"build": pack_bound, "want": "battery"},
		{"build": motor_bound, "want": "motors"},
	]
	var wrong: Array = []
	var described: Array = []
	for expectation in expectations:
		var build: Build = expectation["build"]
		var limit := build.limiting_component()
		described.append("%s (%.0f A, %.0f%%)" % [
			limit["name"], limit["amps"], limit["throttle"] * 100.0])
		if limit["name"] != expectation["want"]:
			wrong.append("wanted %s, got %s" % [expectation["want"], limit["name"]])

	results.append(TestResult.new(
		"the binding constraint is named correctly in all three directions",
		wrong.is_empty(),
		"; ".join(described) if wrong.is_empty() else "; ".join(wrong)
	))

	# The reported ceiling has to be the one actually applied, or the number on screen and the
	# number the aircraft flies at are two different things.
	var mismatched: Array = []
	for expectation in expectations:
		var build: Build = expectation["build"]
		if not is_equal_approx(build.limiting_component()["throttle"], build.max_throttle_fraction()):
			mismatched.append(str(expectation["want"]))
	results.append(TestResult.new(
		"the ceiling the binding component reports is the ceiling the build is actually flown at",
		mismatched.is_empty(),
		"all three agree" if mismatched.is_empty() else "disagree: %s" % ", ".join(mismatched)
	))

	# ...and the warning says so in words, naming the board rather than blaming the prop.
	var said_it := false
	for warning in esc_bound.warnings():
		if warning.message.contains(str(esc_bound.esc["name"])) and warning.message.contains("current first"):
			said_it = true
	results.append(TestResult.new(
		"an ESC-limited build is TOLD it is the board, not the prop or the pack",
		said_it,
		"warnings: %s" % " | ".join(BuildWarning.messages(esc_bound.warnings()))
	))

	return results


## A limit nothing can feel is not a limit. Same airframe, same pack, same motors: only the board
## changes, and the aircraft has to reach less thrust on the small one.
static func _test_the_esc_can_be_the_limit(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var small := _build(catalog, "motor_2207_1960kv", "battery_6s_1300", SMALL_ESC)
	var big := _build(catalog, "motor_2207_1960kv", "battery_6s_1300", BIG_ESC)

	results.append(TestResult.new(
		"swapping only the ESC changes what the same motors on the same pack can reach",
		small.peak_thrust()["thrust_n"] < big.peak_thrust()["thrust_n"] * 0.8
			and small.max_throttle_fraction() < big.max_throttle_fraction() - 0.05,
		"%.1f N at %.0f%% on the %.0f A board vs %.1f N at %.0f%% on the %.0f A one" % [
			small.peak_thrust()["thrust_n"], small.max_throttle_fraction() * 100.0, small.esc_max_amps(),
			big.peak_thrust()["thrust_n"], big.max_throttle_fraction() * 100.0, big.esc_max_amps()]
	))

	return results


# ---------------------------------------------------------------------------
# The mass budget
# ---------------------------------------------------------------------------

static func _test_the_mass_came_out_of_the_lump(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var built := ReferenceBuild.build()

	results.append(TestResult.new(
		"the reference build still weighs its re-baselined 507.5 g with the ESC unbundled",
		absf(built.all_up_weight_g() - 507.48) < 0.5,
		"%.1f g (FC %.0f g + ESC %.0f g + %.0f g of camera, VTX, antenna and receiver + %.1f g of harness = %.1f g of electronics)" % [
			built.all_up_weight_g(), Build.FC_BUDGET_MASS_G, built.esc_mass_g(),
			built.electronics_mass_g() - built.fc_mass_g() - built.esc_mass_g()
				- built.harness_mass_g(),
			built.harness_mass_g(), built.electronics_mass_g()]
	))

	# The SHARES are spent, not exceeded: the six carved categories still weigh exactly what they
	# were budgeted, for the boards the budget was sized around. What is no longer asserted is that
	# the electronics total lands on 55 g — PW2 stopped the harness being the budget's remainder, so
	# the total is the shares plus a weighed harness and the constant bounds only the shares.
	results.append(TestResult.new(
		"the carved shares are still spent exactly, with the harness weighed beside them",
		is_equal_approx(built.electronics_mass_g(),
				Build.carved_total_g() + built.harness_mass_g())
			and is_equal_approx(built.esc_mass_g(), Build.ESC_BUDGET_MASS_G),
		"%.1f g of fitted electronics = %.1f g of carved shares + %.1f g of harness, ESC at its %.0f g share" % [
			built.electronics_mass_g(), Build.carved_total_g(), built.harness_mass_g(),
			Build.ESC_BUDGET_MASS_G]
	))

	# ...and a heavier board makes a heavier aircraft. Without this the unbundling would be
	# bookkeeping: the mass would be "selectable" and selecting it would do nothing.
	var heavy := _build(catalog, "motor_2207_1960kv", "battery_4s_1500", BIG_ESC)
	var light := _build(catalog, "motor_2207_1960kv", "battery_4s_1500", REFERENCE_ESC)
	results.append(TestResult.new(
		"fitting a bigger board makes the aircraft heavier by exactly the difference between them",
		is_equal_approx(heavy.all_up_weight_g() - light.all_up_weight_g(),
			heavy.esc_mass_g() - light.esc_mass_g())
			and heavy.all_up_weight_g() > light.all_up_weight_g(),
		"%.1f g vs %.1f g, a %.0f g board against a %.0f g one" % [
			heavy.all_up_weight_g(), light.all_up_weight_g(),
			heavy.esc_mass_g(), light.esc_mass_g()]
	))

	return results


## The board has to bolt to the frame, which is the same check the motors already get.
static func _test_it_has_to_bolt_on(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var mismatched := _build(catalog, "motor_2207_1960kv", "battery_4s_1500", SMALL_ESC)
	var complained := false
	for warning in mismatched.warnings():
		if warning.message.contains("drilled") and warning.message.contains(str(mismatched.esc["name"])):
			complained = true
	results.append(TestResult.new(
		"a 20x20 board on a 30.5x30.5 frame is warned about rather than silently fitted",
		complained,
		"warnings: %s" % " | ".join(BuildWarning.messages(mismatched.warnings()))
	))

	# ...and the right board raises no complaint, or the warning is noise rather than information.
	var fitting := ReferenceBuild.build()
	var spurious: Array = []
	for warning in fitting.warnings():
		if warning.message.contains("drilled"):
			spurious.append(warning.message)
	results.append(TestResult.new(
		"the reference board bolts to the reference frame without complaint",
		spurious.is_empty(),
		"no fit warnings" if spurious.is_empty() else "; ".join(spurious)
	))

	return results
