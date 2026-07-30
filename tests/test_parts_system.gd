class_name TestPartsSystem
extends RefCounted
## Day 5's gate (week1.md): "switching 4S -> 6S drops hover throttle in the HUD *and* is
## unmistakably different to fly. Numbers changing but feel unchanged means voltage is not
## reaching the RPM calculation."
##
## That warning is the reason this file flies the drone instead of only reading stats. A
## test that just compares two hover_throttle() numbers would pass just as happily with a
## stat panel wired to a completely inert flight model — which is exactly the failure
## week1.md names. So the 4S/6S check does both halves: the readout must change, and the
## same throttle command must produce measurably different flight.

const DT := 0.001

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(TestResult.new(
		"parts catalog loads with no errors",
		catalog.is_valid(),
		"errors=%s" % [catalog.load_errors] if not catalog.load_errors.is_empty() else "4 categories loaded"
	))
	results.append(_every_part_has_the_specs_the_physics_reads(catalog))
	results.append(_catalog_is_deep_enough_to_browse(catalog))
	results.append(_every_part_carries_browsing_metadata(catalog))
	results.append(_every_motor_thrust_test_names_a_real_prop(catalog))
	results.append_array(_reference_build_matches_the_documented_table(catalog))
	results.append_array(_four_s_to_six_s(catalog))
	results.append(_arm_length_dominates_roll_inertia(catalog))
	results.append(_blade_count_ab(catalog))
	results.append_array(_liion_tradeoff(catalog))
	return results


## parts.md: "If a spec does not appear in the right column, it does not go in the JSON
## yet." The converse is what breaks a build — a contributor's PR missing a field the
## physics reads should fail here, not produce a drone with a silently-zero coefficient.
static func _every_part_has_the_specs_the_physics_reads(catalog: PartsCatalog) -> TestResult:
	var required := {
		"frame": ["arm_mm", "max_prop_inches", "motor_mount"],
		"motor": ["kv", "max_thrust_g", "max_amps", "poles", "stator_diameter_mm", "stator_height_mm"],
		"propeller": ["diameter_inches", "pitch_inches", "blades"],
		"battery": ["cells", "nominal_v", "mah", "internal_r_ohm"],
	}
	var missing: Array[String] = []
	var count := 0
	for category in required:
		for part in catalog.list_category(category):
			count += 1
			if not part.has("source"):
				missing.append("%s: no source field" % part["part_id"])
			for field in required[category]:
				if not part.get("specs", {}).has(field):
					missing.append("%s: missing specs.%s" % [part["part_id"], field])
			if category == "motor" and not part.get("thrust_test", {}).has("prop_id"):
				missing.append("%s: missing thrust_test.prop_id" % part["part_id"])

	return TestResult.new(
		"every catalog part carries the specs the physics reads",
		missing.is_empty(),
		"%d parts checked, %s" % [count, "all complete" if missing.is_empty() else str(missing)]
	)


## A filter is only worth having if it has work to do. Three motors and five props can be
## read off a single unfiltered list, so a picker over them proves nothing — the filters
## would pass their tests while being decoration. These floors are what makes the motor and
## propeller rails answer the same question the frame rail does.
static func _catalog_is_deep_enough_to_browse(catalog: PartsCatalog) -> TestResult:
	var counts := {
		"frame": catalog.list_category("frame").size(),
		"motor": catalog.list_category("motor").size(),
		"propeller": catalog.list_category("propeller").size(),
	}
	return TestResult.new(
		"the catalog is deep enough for its filters to mean anything",
		counts["frame"] >= 12 and counts["motor"] >= 12 and counts["propeller"] >= 14,
		"%d frames, %d motors, %d propellers" % [counts["frame"], counts["motor"], counts["propeller"]]
	)


## The two-tier schema, enforced. `catalog` is browsing metadata and every part must carry
## the axes its picker filters on, or a filter silently drops that part out of every list
## but "All" — which looks like a missing product rather than a missing field.
##
## The banned-field half is the more important one. frames.json's _schema bans colour, price
## and vendor links BY NAME from both blocks, and a ban stated only in prose is a ban that
## erodes: the first PR to add a price is a small, reasonable-looking diff. This is the check
## that makes the diff fail instead.
static func _every_part_carries_browsing_metadata(catalog: PartsCatalog) -> TestResult:
	var required := {
		"frame": ["frame_type", "size_class", "material"],
		"motor": ["stator_class", "kv_class", "intended_use"],
		"propeller": ["blade_count", "diameter_class", "intended_use", "material"],
	}
	# Substrings, not exact keys, so "vendor_url", "price_usd" and "colour" are all caught.
	var banned := ["colour", "color", "price", "cost", "vendor", "url", "link", "buy", "shop", "sku"]

	var problems: Array[String] = []
	var checked := 0
	for category in required:
		for part in catalog.list_category(category):
			checked += 1
			var meta: Dictionary = part.get("catalog", {})
			for field in required[category]:
				if String(meta.get(field, "")) == "":
					problems.append("%s: missing catalog.%s" % [part["part_id"], field])
			for block_name in ["specs", "catalog"]:
				for key in part.get(block_name, {}):
					for word in banned:
						if String(key).to_lower().contains(word):
							problems.append("%s: %s.%s is a banned field" % [part["part_id"], block_name, key])

	return TestResult.new(
		"every part carries its browsing metadata, and no banned field",
		problems.is_empty(),
		"%d parts checked, %s" % [checked, "all clean" if problems.is_empty() else str(problems)]
	)


## Build fits k_t from the motor's published thrust figure and the exact prop and pack it was
## measured on (physics.md §4: do not guess C_T). A thrust_test naming a prop_id that does
## not exist therefore does not produce a slightly-wrong drone — it produces a k_t fitted
## against an empty dictionary, and the failure surfaces far away from the typo that caused
## it. Catch it here, at the JSON.
static func _every_motor_thrust_test_names_a_real_prop(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	for motor in catalog.list_category("motor"):
		var test: Dictionary = motor.get("thrust_test", {})
		var prop_id := String(test.get("prop_id", ""))
		var prop: Dictionary = catalog.get_part(prop_id)
		if prop.is_empty():
			problems.append("%s: thrust_test names %s, which is not in the catalog" % [motor["part_id"], prop_id])
		elif prop.get("category", "") != "propeller":
			problems.append("%s: thrust_test names %s, which is a %s" % [motor["part_id"], prop_id, prop["category"]])
		if float(test.get("voltage_v", 0.0)) <= 0.0:
			problems.append("%s: thrust_test has no voltage_v" % motor["part_id"])

	return TestResult.new(
		"every motor's thrust test names a propeller that exists, at a real voltage",
		problems.is_empty(),
		"%d motors checked, %s" % [catalog.list_category("motor").size(),
			"all resolve" if problems.is_empty() else str(problems)]
	)


## The catalog must reproduce parts.md's hand-verified reference table. This is what ties
## the JSON to the day 2 oracle: if someone edits the 2207's thrust figure, this fails.
static func _reference_build_matches_the_documented_table(catalog: PartsCatalog) -> Array:
	var b := ReferenceBuild.build()
	var results: Array = []

	results.append(TestResult.new(
		"reference build from JSON: 496 g all-up",
		absf(b.all_up_weight_g() - 496.0) < 1.0,
		"got %.1f g" % b.all_up_weight_g()
	))
	results.append(TestResult.new(
		"reference build from JSON: 11.7:1 thrust-to-weight",
		absf(b.thrust_to_weight() - 11.7) / 11.7 < 0.03,
		"got %.2f : 1" % b.thrust_to_weight()
	))
	# physics.md §8's reality-check oracle, all five stats at once.
	results.append(TestResult.new(
		"reference build stats all land in physics.md's real-world bands",
		b.all_up_weight_g() >= 500.0 - 50.0 and b.all_up_weight_g() <= 650.0
			and b.thrust_to_weight() >= 9.0 and b.thrust_to_weight() <= 12.0
			and b.hover_throttle() >= 0.28 and b.hover_throttle() <= 0.32
			and b.flight_time_min() >= 4.0 and b.flight_time_min() <= 6.0
			and b.top_speed_kmh() >= 100.0 and b.top_speed_kmh() <= 130.0,
		"%.0f g, %.1f:1, %.1f%% hover, %.1f min, %.0f km/h" % [
			b.all_up_weight_g(), b.thrust_to_weight(), b.hover_throttle() * 100.0,
			b.flight_time_min(), b.top_speed_kmh()]
	))
	return results


static func _four_s_to_six_s(catalog: PartsCatalog) -> Array:
	var results: Array = []
	# Same airframe, same prop; only the motor's KV and the pack change, as a real 4S->6S
	# conversion does.
	var four_s := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1500")
	var six_s := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1750kv", "prop_5x43x3", "battery_6s_1300")

	results.append(TestResult.new(
		"4S -> 6S drops the hover throttle readout",
		six_s.hover_throttle() < four_s.hover_throttle() - 0.01,
		"4S %.1f%% -> 6S %.1f%%" % [four_s.hover_throttle() * 100.0, six_s.hover_throttle() * 100.0]
	))

	# The half that matters: fly both at an IDENTICAL throttle command and compare. If
	# voltage never reaches the RPM calculation, these two climb rates come out the same.
	var climb_4s := _climb_rate_at_throttle(four_s, 0.5)
	var climb_6s := _climb_rate_at_throttle(six_s, 0.5)
	results.append(TestResult.new(
		"4S -> 6S is different to FLY at the same stick position",
		climb_6s > climb_4s * 1.25,
		"at 50%% throttle: 4S climbs %.2f m/s, 6S climbs %.2f m/s" % [climb_4s, climb_6s]
	))
	return results


## Vertical speed after 2 s at a fixed throttle, motors pre-spun so this measures the
## build and not the spin-up lag.
static func _climb_rate_at_throttle(build: Build, throttle: float) -> float:
	var core := build.build_drone_core()
	core.prime_motors(throttle)
	var cmds := {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}
	for i in int(2.0 / DT):
		core.step(cmds, DT)
	return core.rigid_body.velocity_mps.y


## parts.md: arm length is "the sleeper spec — it is squared in the parallel axis theorem".
static func _arm_length_dominates_roll_inertia(catalog: PartsCatalog) -> TestResult:
	var small := Build.from_ids(catalog, "frame_3in_toothpick", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1500")
	var large := Build.from_ids(catalog, "frame_7in_long_range", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1500")
	# Same motors, same prop, same pack: only the arm moves. 75 mm -> 150 mm is 2x the arm,
	# so the motors' parallel-axis contribution alone should rise about 4x.
	var ratio := large.mass_properties.inertia.x.x / small.mass_properties.inertia.x.x
	return TestResult.new(
		"doubling arm length multiplies roll inertia (parallel axis is squared)",
		ratio > 3.0,
		"3\" -> 7\" frame raises I_xx %.1fx (arm 75 -> 150 mm)" % ratio
	)


## parts.md wants the 2-blade/3-blade pair at identical 5x4.3 to be a clean A/B.
static func _blade_count_ab(catalog: PartsCatalog) -> TestResult:
	var bi := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x2", "battery_4s_1500")
	var tri := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1500")
	return TestResult.new(
		"bi-blade vs tri-blade: less thrust, less mass, higher hover throttle",
		bi.thrust_to_weight() < tri.thrust_to_weight()
			and bi.all_up_weight_g() < tri.all_up_weight_g()
			and bi.hover_throttle() > tri.hover_throttle(),
		"2-blade %.1f:1 @ %.1f%% vs 3-blade %.1f:1 @ %.1f%%" % [
			bi.thrust_to_weight(), bi.hover_throttle() * 100.0,
			tri.thrust_to_weight(), tri.hover_throttle() * 100.0]
	)


## parts.md: the Li-ion is in the catalog to make an engineering tradeoff feel real —
## heavier and sagging badly, in exchange for substantially longer flight.
static func _liion_tradeoff(catalog: PartsCatalog) -> Array:
	var lipo := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1500")
	var liion := Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv", "prop_5x43x3", "battery_4s_3000_liion")

	var results: Array = []
	results.append(TestResult.new(
		"Li-ion: heavier and lazier, but flies substantially longer",
		liion.all_up_weight_g() > lipo.all_up_weight_g()
			and liion.hover_throttle() > lipo.hover_throttle()
			and liion.flight_time_min() > lipo.flight_time_min() * 1.4,
		"LiPo %.0f g / %.1f%% / %.1f min  vs  Li-ion %.0f g / %.1f%% / %.1f min" % [
			lipo.all_up_weight_g(), lipo.hover_throttle() * 100.0, lipo.flight_time_min(),
			liion.all_up_weight_g(), liion.hover_throttle() * 100.0, liion.flight_time_min()]
	))
	# It must still actually fly. An earlier current model made sag run away and turned
	# this pack into a paperweight, which is not the lesson it is here to teach.
	results.append(TestResult.new(
		"Li-ion still flies, and says out loud that it is sagging",
		liion.can_hover() and not liion.warnings().is_empty(),
		"can_hover=%s, warnings=%d" % [liion.can_hover(), liion.warnings().size()]
	))
	return results
