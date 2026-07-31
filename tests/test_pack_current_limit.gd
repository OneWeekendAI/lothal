class_name TestPackCurrentLimit
extends RefCounted
## The pack's C-rating as a current limit, and which component is doing the limiting.
##
## `c_rating` sat in batteries.json's `catalog` block, read by nothing, so a 300 mAh whoop pack
## would happily deliver 100 A. It is physics-bearing — capacity times C is the pack's maximum
## continuous discharge — so it moved to `specs`, and this file is why.
##
## ---------------------------------------------------------------------------
## THE BINDING CONSTRAINT IS THE POINT, NOT THE LIMIT
## ---------------------------------------------------------------------------
##
## Current is limited by whichever of the pack and the motors gives out first. Knowing that you
## are limited is worth much less than knowing WHICH component is limiting you, because that is
## the one worth spending money on. So the model reports the binding constraint by name, and these
## tests check the attribution rather than only the number — a build that were limited by the
## right amount for the wrong reason would send a builder to buy the wrong part.
##
## ---------------------------------------------------------------------------
## WHY THE BENCH THRUST FIGURE DOES NOT MOVE
## ---------------------------------------------------------------------------
##
## max_total_thrust_n() — the 11.7:1 oracle — is a SPEC-SHEET figure and stays quoted the way a
## spec sheet quotes it: at nominal voltage, at the motor's own current limit, with no pack sag.
## The project already draws that line, deliberately, for sag; the pack's C-rating sits on the
## same side of it for the same reason.
##
## The pack limit is not being ignored. It binds everywhere the aircraft is actually flown —
## peak thrust, hover, top speed, and the throttle the motors can be commanded to — and
## Build.warnings() says out loud when the reachable thrust is far below the bench figure. A
## builder gets the honest number in the air and a comparable number on the sheet, which is what
## "a spec sheet number and a flying number are different things" already means here.

## The reference build's pack: 1500 mAh at 75C. Its 112.5 A is genuinely below what four 2207s
## ask for flat out, so the reference build is mildly pack-limited — which is true of most real
## 5" builds on a 1500, and is the reason this constant is worth stating rather than hiding.
const REFERENCE_PACK_AMPS := 112.5


static func run() -> Array:
	var results: Array = []

	var catalog := PartsCatalog.load_default()

	results.append_array(_test_the_rating_reaches_the_model(catalog))
	results.append_array(_test_a_small_pack_on_big_motors_is_pack_limited(catalog))
	results.append_array(_test_a_big_pack_on_small_motors_is_motor_limited(catalog))
	results.append_array(_test_the_limit_actually_costs_thrust(catalog))
	results.append_array(_test_the_bench_figure_is_untouched(catalog))

	return results


static func _build(catalog: PartsCatalog, motor_id: String, prop_id: String, battery_id: String) -> Build:
	return Build.from_ids(catalog, "frame_5in_freestyle", motor_id, prop_id, battery_id)


# ---------------------------------------------------------------------------
# The rating is read at all
# ---------------------------------------------------------------------------

static func _test_the_rating_reaches_the_model(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# Capacity times C, in amps. Stated here as arithmetic on the catalog's own two numbers so
	# that this fails if the model ever starts reading something else and calling it the same
	# thing.
	var mismatched: Array = []
	for pack in catalog.list_category("battery"):
		var build := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", pack["part_id"])
		var expected: float = float(pack["specs"]["mah"]) / 1000.0 * float(pack["specs"]["c_rating"])
		if not is_equal_approx(build.pack_max_amps(), expected):
			mismatched.append("%s: %.1f A vs %.1f A" % [pack["part_id"], build.pack_max_amps(), expected])

	results.append(TestResult.new(
		"every pack's continuous current limit is its capacity times its C-rating",
		mismatched.is_empty(),
		"checked %d packs; %s" % [catalog.list_category("battery").size(),
			"all agree" if mismatched.is_empty() else ", ".join(mismatched)]
	))

	# The one that would have caught the original defect. A 300 mAh 30C whoop pack can supply
	# 9 A, and before this slice nothing in the project knew that.
	var whoop := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_1s_300")
	results.append(TestResult.new(
		"a 300 mAh 30C whoop pack is a 9 A pack, not a 100 A one",
		absf(whoop.pack_max_amps() - 9.0) < 0.01,
		"%.1f A continuous" % whoop.pack_max_amps()
	))

	return results


# ---------------------------------------------------------------------------
# Which component binds
# ---------------------------------------------------------------------------

## A tiny pack on the reference build's motors. Four 2207s ask for about 128 A flat out; this
## pack can give 9 A. The throttle has to be cut hard, and the pack has to be named as the reason.
static func _test_a_small_pack_on_big_motors_is_pack_limited(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_1s_300")

	results.append(TestResult.new(
		"a whoop pack on 2207s is throttle-limited by the PACK, and says so",
		build.limiting_component()["name"] == "battery"
			and build.pack_throttle_limit() < build.motor_throttle_limit(),
		"limited by %s at %.0f%% throttle (pack %.0f%%, motors %.0f%%)" % [
			build.limiting_component()["name"], build.max_throttle_fraction() * 100.0,
			build.pack_throttle_limit() * 100.0, build.motor_throttle_limit() * 100.0]
	))

	# The Li-ion is the catalog's other deliberate lesson: 3000 mAh at 10C is 30 A, so an enormous
	# pack is a weak one. Capacity and current are different things, and this is where that lands.
	var liion := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_4s_3000_liion")
	results.append(TestResult.new(
		"a 3000 mAh Li-ion is a 30 A pack: the biggest battery here is among the most limiting",
		liion.limiting_component()["name"] == "battery" and liion.pack_max_amps() < 31.0,
		"%.0f A continuous, limited to %.0f%% throttle" % [
			liion.pack_max_amps(), liion.max_throttle_fraction() * 100.0]
	))

	return results


## The other direction, so the attribution is a real decision rather than a constant. Small motors
## on a big pack must name the MOTORS — otherwise "which component is limiting you" is answered
## the same way for every build and tells nobody anything.
static func _test_a_big_pack_on_small_motors_is_motor_limited(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := _build(catalog, "motor_1404_3800kv", "prop_3x3x3", "battery_6s_1300")

	results.append(TestResult.new(
		"small motors on a 130 A pack are limited by the MOTORS, and say so",
		build.limiting_component()["name"] == "motors"
			and build.motor_throttle_limit() <= build.pack_throttle_limit(),
		"limited by %s (pack %.0f A / %.0f%%, motors %.0f%%)" % [
			build.limiting_component()["name"], build.pack_max_amps(),
			build.pack_throttle_limit() * 100.0, build.motor_throttle_limit() * 100.0]
	))

	return results


## A limit nothing can feel is not a limit. The same airframe and motors on a pack that can
## supply them must out-thrust one on a pack that cannot, in the air.
static func _test_the_limit_actually_costs_thrust(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var strong := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_6s_1300")
	var weak := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_4s_3000_liion")

	var strong_peak: float = strong.peak_thrust()["thrust_n"]
	var weak_peak: float = weak.peak_thrust()["thrust_n"]

	results.append(TestResult.new(
		"a pack that cannot supply the motors reaches less thrust than one that can",
		weak_peak < strong_peak * 0.6,
		"%.1f N on a %.0f A pack against %.1f N on a %.0f A one" % [
			weak_peak, weak.pack_max_amps(), strong_peak, strong.pack_max_amps()]
	))

	# ...and it has to be the RATING doing it rather than the Li-ion's internal resistance, which
	# would produce a similar-looking answer for an entirely different reason. Same pack, same
	# resistance, C-rating alone raised: the throttle ceiling has to move.
	var relabelled := _build(catalog, "motor_2207_1960kv", "prop_5x43x3", "battery_4s_3000_liion")
	relabelled.battery = relabelled.battery.duplicate(true)
	relabelled.battery["specs"] = (relabelled.battery["specs"] as Dictionary).duplicate(true)
	relabelled.battery["specs"]["c_rating"] = 100.0
	results.append(TestResult.new(
		"raising only the C-rating raises the throttle ceiling, so it is the rating doing the work",
		relabelled.max_throttle_fraction() > weak.max_throttle_fraction() + 0.05,
		"%.0f%% at 10C -> %.0f%% at 100C, same cells and same %.0f mOhm" % [
			weak.max_throttle_fraction() * 100.0, relabelled.max_throttle_fraction() * 100.0,
			float(weak.battery["specs"]["internal_r_ohm"]) * 1000.0]
	))

	return results


# ---------------------------------------------------------------------------
# The oracle
# ---------------------------------------------------------------------------

static func _test_the_bench_figure_is_untouched(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()

	results.append(TestResult.new(
		"the reference build IS mildly pack-limited, which is true of a real 5\" on a 1500",
		absf(build.pack_max_amps() - REFERENCE_PACK_AMPS) < 0.1
			and build.limiting_component()["name"] == "battery"
			and build.max_throttle_fraction() < 0.99,
		"%.1f A pack, limited by %s to %.1f%% throttle" % [
			build.pack_max_amps(), build.limiting_component()["name"],
			build.max_throttle_fraction() * 100.0]
	))

	# ...and the spec-sheet figure is quoted at the motor's limit regardless, so the oracle holds.
	results.append(TestResult.new(
		"the 11.7:1 bench figure is quoted at the motor limit and does not move with the pack",
		absf(build.thrust_to_weight() - 11.7) / 11.7 < 0.03,
		"%.2f:1 at the motor's %.0f%% ceiling, while the pack caps flight at %.1f%%" % [
			build.thrust_to_weight(), build.motor_throttle_limit() * 100.0,
			build.max_throttle_fraction() * 100.0]
	))

	# The hover oracle is untouched for a different and stronger reason: hover draws about 11 A
	# on this build, nowhere near the pack's 112 A, so no current limit is anywhere near binding
	# on the rising branch the hover throttle is bisected on.
	results.append(TestResult.new(
		"hover is nowhere near any current limit, so the 29% oracle cannot be moved by one",
		build.hover_current_a(build.hover_throttle()) < build.pack_max_amps() * 0.2
			and absf(build.hover_throttle() - 0.29) < 0.02,
		"%.1f A at a %.1f%% hover, against a %.0f A pack" % [
			build.hover_current_a(build.hover_throttle()), build.hover_throttle() * 100.0,
			build.pack_max_amps()]
	))

	return results
