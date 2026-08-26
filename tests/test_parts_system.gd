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
	results.append_array(_pack_dimensions_are_measured_rather_than_derived(catalog))
	results.append(_every_motor_thrust_test_names_a_real_prop(catalog))
	results.append_array(_reference_build_matches_the_documented_table(catalog))
	results.append_array(_four_s_to_six_s(catalog))
	results.append(_arm_length_dominates_roll_inertia(catalog))
	results.append(_blade_count_ab(catalog))
	results.append_array(_liion_tradeoff(catalog))
	results.append(_guard_mass_matches_the_physics(catalog))
	results.append(_guard_kind_agrees_with_its_geometry(catalog))
	return results


## P10a: `mass_g` at the top of every guards.json entry is DERIVED from `specs` — it exists so
## the browsing rail can print the number without instantiating a spec, and it must not drift
## away from what `PropGuard.mass_kg()` actually computes. The check runs against `specs` alone
## and never against `kind`, because the mass integral does not read the discriminator: a duct and
## a bumper of the same ring geometry weigh the same, and an authored number that differed between
## them would be describing something the physics does not model.
##
## Tolerance is 0.02 g — the two-decimal rounding the JSON authors, which is the smallest
## quantum a browsing rail displays. Any wider tolerance would let a real physics bug hide
## behind it; any tighter would fail on the last digit of an honest hand-typed value.
static func _guard_mass_matches_the_physics(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	for guard in catalog.list_category("guard"):
		checked += 1
		var authored_g := float(guard.get("mass_g", -1.0))
		var computed_kg := PropGuard.mass_kg(guard.get("specs", {}))
		var computed_g := computed_kg * 1000.0
		if computed_g <= 0.0:
			problems.append("%s: PropGuard.mass_kg refused the specs (returned %.4f g)" %
				[guard["part_id"], computed_g])
			continue
		if absf(authored_g - computed_g) > 0.02:
			problems.append("%s: mass_g=%.3f g but PropGuard computes %.3f g" %
				[guard["part_id"], authored_g, computed_g])
	# A category that loaded EMPTY would sail through the loop above with no problems and pass
	# vacuously — the failure mode where a renamed CATEGORY_FILES key silently deletes the
	# check rather than the catalog. So the count is part of the assertion, not just the detail.
	if checked == 0:
		problems.append("the guard category loaded no parts — this check would pass vacuously")
	return TestResult.new(
		"every guard's mass_g matches PropGuard's own geometry integral",
		problems.is_empty(),
		"%d guards checked, %s" % [checked,
			"all consistent" if problems.is_empty() else str(problems)])


## P10a: a shipped guard's declared `kind` must agree with what its own geometry says it is.
##
## prop_guard.gd's header names the two failures this catches, and calls both silent: "a bumper
## credited with duct thrust is a free lunch. A cinewhoop treated as a bumper reports a hover
## throttle that will not fly the aircraft." `clearance_check` already detects the disagreement —
## nothing in the catalog was asking it. This check does, for every entry, against the propeller
## its own `prop_class` says it wraps, so a ring authored 1.5 mm off a 5" tip and labelled
## `bumper` fails here rather than shipping a thrust claim of "unchanged" that a builder flies on.
##
## The tip radius comes from the NOMINAL class diameter, not from the widest propeller carried in
## that class: a 5.15" prop inside class 5" has a tip radius past the reference cinewhoop's inner
## wall, and a guard is not mislabelled because a builder can fit an oversized prop into it. The
## tip chord comes from `PropellerDocument.from_catalog_prop`, i.e. the generated planform — an
## assumption, flagged as one by `chord_is_assumed`, and the SAME length scale `tip_loss_closure`
## divides by, which is what makes the classification boundary here the model's own rather than a
## second one invented for a test.
static func _guard_kind_agrees_with_its_geometry(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var checked := 0
	for guard in catalog.list_category("guard"):
		var prop_class := String(guard.get("catalog", {}).get("prop_class", ""))
		var nominal_inches := float(prop_class.replace("\"", ""))
		if nominal_inches <= 0.0:
			problems.append("%s: prop_class '%s' names no diameter" % [guard["part_id"], prop_class])
			continue
		var reference_prop := {}
		for prop in catalog.list_category("propeller"):
			if absf(float(prop["specs"]["diameter_inches"]) - nominal_inches) < 1.0e-9:
				reference_prop = prop
				break
		if reference_prop.is_empty():
			problems.append("%s: no catalog propeller at the nominal %s" %
				[guard["part_id"], prop_class])
			continue
		var doc := PropellerDocument.from_catalog_prop(reference_prop)
		var check := PropGuard.clearance_check(guard.get("specs", {}), doc.radius_mm(),
			doc.chord_at(1.0))
		checked += 1
		if bool(check["kind_disagrees"]):
			problems.append("%s: declared %s, geometry says %s (clearance %.2f mm = %.2f tip chords against %s)" %
				[guard["part_id"], guard["specs"]["kind"], check["geometric_kind"],
					float(check["clearance_mm"]), float(check["gap_ratio"]), doc.id])
	# Same vacuity guard as the mass check above, and here it is doing slightly more work: this
	# loop `continue`s past an entry whose prop_class names no diameter, so a catalog where every
	# entry lost its prop_class would reach here with checked == 0 AND problems non-empty. The
	# count still belongs in the assertion for the case where the category itself is empty.
	if checked == 0 and problems.is_empty():
		problems.append("the guard category loaded no parts — this check would pass vacuously")
	return TestResult.new(
		"every shipped guard's declared kind agrees with its own geometry — no shroud labelled bumper",
		problems.is_empty(),
		"%d guards checked, %s" % [checked,
			"all agree" if problems.is_empty() else str(problems)])


## parts.md: "If a spec does not appear in the right column, it does not go in the JSON
## yet." The converse is what breaks a build — a contributor's PR missing a field the
## physics reads should fail here, not produce a drone with a silently-zero coefficient.
static func _every_part_has_the_specs_the_physics_reads(catalog: PartsCatalog) -> TestResult:
	var required := {
		"frame": ["arm_mm", "max_prop_inches", "motor_mount"],
		"motor": ["kv", "max_thrust_g", "max_amps", "poles", "stator_diameter_mm", "stator_height_mm"],
		"propeller": ["diameter_inches", "pitch_inches", "blades"],
		"battery": ["cells", "nominal_v", "mah", "internal_r_ohm",
			"length_mm", "width_mm", "height_mm"],
		# P10a (plans/2026-08-26-propulsion-room-design.md §3): the fields PropGuard.compute()
		# reads. A guard with `kind` missing or unknown is refused by compute() itself; a guard
		# with any of these five geometry fields non-positive is refused too. Listing them here
		# means a PR that removes `wall_mm` from an entry fails at load time rather than at
		# an as_part_mass() call that then returns null and a build that then quietly weighs
		# less than it should.
		"guard": ["kind", "outer_radius_mm", "wall_mm", "height_mm", "density_kg_m3",
			"mount_radius_mm"],
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
## The pack's published length, width and height, and the reason they are AUTHORED rather than
## estimated. Build used to size the pack from its mass — a fixed 70x30x35 box scaled by the cube
## root of mass — and that estimate has two signatures this test is built to reject, because a
## re-derived guess would sail past a "the fields are present" check.
##
## A mass-scaled box of fixed proportions has ONE aspect ratio for the whole catalog (2.0, every
## time) and orders the packs by volume exactly as it orders them by mass. Real packs do neither: a
## 1S whoop stick is six times as long as it is wide and a 6S 21700 brick is barely wider than it is
## long, and the 320 g Li-ion 18650 pack occupies LESS space than the 205 g 6S LiPo because a
## cylindrical cell is denser than a pouch. So both halves are asserted against the catalog as a
## whole, and either one failing means somebody has computed a dimension instead of reading one off
## a spec sheet.
static func _pack_dimensions_are_measured_rather_than_derived(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var by_mass: Array = catalog.list_category("battery").duplicate()
	by_mass.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["mass_g"]) < float(b["mass_g"]))

	var aspects: Array[float] = []
	var volumes_cm3: Array[float] = []
	var densities: Array[float] = []
	var inversions: Array[String] = []

	for part in by_mass:
		var specs: Dictionary = part.get("specs", {})
		var length: float = float(specs.get("length_mm", 0.0))
		var width: float = float(specs.get("width_mm", 0.0))
		var height: float = float(specs.get("height_mm", 0.0))
		if length <= 0.0 or width <= 0.0 or height <= 0.0:
			return [TestResult.new(
				"pack dimensions are measured rather than derived from mass",
				false,
				"%s has no usable dimensions (%.1f x %.1f x %.1f mm)" % [
					part["part_id"], length, width, height])]
		aspects.append(length / width)
		var volume_cm3 := length * width * height / 1000.0
		volumes_cm3.append(volume_cm3)
		densities.append(float(part["mass_g"]) / volume_cm3)

	for i in volumes_cm3.size() - 1:
		if volumes_cm3[i] > volumes_cm3[i + 1]:
			inversions.append("%s (%.0f cm3) is bigger than the heavier %s (%.0f cm3)" % [
				by_mass[i]["part_id"], volumes_cm3[i],
				by_mass[i + 1]["part_id"], volumes_cm3[i + 1]])

	var min_aspect: float = aspects.min()
	var max_aspect: float = aspects.max()
	results.append(TestResult.new(
		"packs have real, differing proportions, not one box scaled by mass",
		min_aspect < 2.0 and max_aspect > 4.0,
		"length:width runs %.2f to %.2f across %d packs (a mass-scaled box would be 2.00 for every one)" % [
			min_aspect, max_aspect, aspects.size()]
	))

	results.append(TestResult.new(
		"a heavier pack is not always a bigger one, which no cube-root-of-mass estimate can produce",
		inversions.size() >= 2,
		"%d mass/volume inversions: %s" % [inversions.size(), str(inversions)]
	))

	# The typo guard. A millimetre entered as a centimetre, or a transposed digit, changes the
	# volume by orders of magnitude and would otherwise show up only as an airframe with a shipping
	# crate strapped to it. Lithium cells sit in a narrow, well-known band: pouch LiPo around
	# 1.8-2.2 g/cm3, cylindrical 18650/21700 cells higher because they carry more metal.
	var loose: Array[String] = []
	for i in densities.size():
		if densities[i] < 1.5 or densities[i] > 3.5:
			loose.append("%s at %.2f g/cm3" % [by_mass[i]["part_id"], densities[i]])
	results.append(TestResult.new(
		"every pack's mass and volume agree on a believable cell density",
		loose.is_empty(),
		"%.2f-%.2f g/cm3 across %d packs%s" % [
			densities.min(), densities.max(), densities.size(),
			"" if loose.is_empty() else ", outside the band: " + str(loose)]
	))

	return results


static func _every_part_carries_browsing_metadata(catalog: PartsCatalog) -> TestResult:
	var required := {
		"frame": ["frame_type", "size_class", "material"],
		"motor": ["stator_class", "kv_class", "intended_use"],
		"propeller": ["blade_count", "diameter_class", "intended_use", "material"],
		"guard": ["prop_class", "intended_use", "material"],
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
static func _reference_build_matches_the_documented_table(_catalog: PartsCatalog) -> Array:
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
	# voltage never reaches the RPM calculation, these two climb rates come out the same and the
	# ratio below is 1.00 — that is the failure this defends against, and the margin to it is
	# what matters rather than the exact bound.
	#
	# The bound was 1.25 while a full pack rested at nominal voltage, where the measured ratio was
	# 1.292. Moving the datum to nominal (physics.md §5) means a full pack now rests above it, both
	# builds climb harder, and the ratio measured 1.246 — because drag goes as v^2, so a faster pair
	# is a compressed pair. The two builds did not become more alike; the yardstick did. 1.2 keeps
	# the same distance from the 1.00 that would mean voltage had stopped reaching the RPM ceiling.
	#
	# THE BOUND HAS NOT MOVED SINCE. The window has, from 2 s to 0.5 s, and the forward-flight prop
	# model (2026-08-14) is what exposed why it had to. There is no flight controller in this
	# fixture and the centre of mass is not at the frame's origin, so four equal thrusts are a
	# constant uncorrected pitch torque: by 2 s the aircraft is not climbing at all, it is tumbling
	# at over 4 rad/s, and `velocity_mps.y` is sampling a phase of that tumble. Both figures were
	# NEGATIVE, and `climb_6s > climb_4s * 1.2` on two negative numbers asserts the opposite of what
	# it reads as — it passed because 6S happened to be the less negative one. Changing the prop
	# model shifted the tumble's phase, the sign relationship inverted, and a test that had never
	# measured a climb rate finally said so.
	#
	# At 0.5 s both builds are genuinely climbing, and the ratio measures 1.344 against the same
	# 1.2. Note the direction: the window narrowed to make the test measure the quantity it names,
	# and the bound it is held to was not touched.
	var climb_4s := _climb_rate_at_throttle(four_s, 0.5)
	var climb_6s := _climb_rate_at_throttle(six_s, 0.5)
	results.append(TestResult.new(
		"4S -> 6S is different to FLY at the same stick position",
		climb_6s > climb_4s * 1.2,
		"at 50%% throttle: 4S climbs %.2f m/s, 6S climbs %.2f m/s" % [climb_4s, climb_6s]
	))
	return results


## Vertical speed after CLIMB_WINDOW_S at a fixed throttle, motors pre-spun so this measures the
## build and not the spin-up lag. Short enough that the aircraft is still climbing rather than
## tumbling — see the argument at the call site, which is the whole reason for the constant.
const CLIMB_WINDOW_S := 0.5

static func _climb_rate_at_throttle(build: Build, throttle: float) -> float:
	var core := build.build_drone_core()
	core.prime_motors(throttle)
	var cmds := {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}
	for i in int(CLIMB_WINDOW_S / DT):
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
