class_name TestControlComponents
extends RefCounted
## The GPS and the buzzer as fitted components — C2.
## plans/2026-09-12-control-room-plan.md, slice C2. Design: §2.3, §2.4, §3, §0.
##
## THE ONE PROPERTY THIS FILE EXISTS FOR is stated in design §3 and it is a NEGATIVE about the rest
## of the project: GPS and buzzer are ADDED mass, never carved out of ELECTRONICS_BUDGET_G, and
## neither has a default. Two categories joined `Build.OPTIONAL_COMPONENTS` — a constant eleven
## files iterate — and every oracle in the project must come out bit-identical anyway. The first
## four checks below assert those numbers POSITIVELY, as named values, rather than trusting that
## some other suite would have noticed. An absence of failures elsewhere is not an assertion: a
## default quietly fitted to every build in the app would move a dozen suites at once, and the
## person reading a dozen red lines would not know which one was the cause.
##
## THE ORACLE NUMBERS BELOW ARE MEASURED AT `6e1de24`, THE COMMIT BEFORE THIS SLICE. They are not
## re-derived here and they are not this file's to choose — five other suites assert the same
## aircraft and this one is the statement that C2 did not touch it.
##
## WHAT IS NOT ASSERTED HERE, and the reason is a finding rather than an omission. C2's plan asks
## for "the derived tune" among the bit-identical oracles. `RateTune.derive(ReferenceBuild.build())`
## CANNOT MOVE: `reference_alpha()` is `plant_alpha_for(ReferenceBuild.build())`, so the reference
## build's scale is `anchor / its own alpha` — identically 1.0 — and its derived gains are
## identically `RateModeController.REFERENCE_KP/KI/KD` whatever the aircraft weighs. Asserting them
## would have been a check that cannot fail, on the one row of the table that most needed to. What
## IS asserted instead is the number the tune is DERIVED FROM: the reference build's own
## `plant_alpha`, in rad/s², which moves the moment its mass or its inertia does, and which every
## other build in the app is scaled against.
##
## THE MAST'S MECHANISM, because a reader will look for it here. `MountLayout._component_bays` is a
## pure function of frame geometry and `gps_mount` is the top plate's upper face, with no mast in
## it; the mast is the fitted MODULE's published `mast_height_mm` and reaches the seat as
## `seated_centre_m`'s `rise_m`, beside `size_m`, which is the same kind of quantity read from the
## same block of the same file. See that function's comment for why neither the bay nor the caller
## was the right place.

## What counts as "unchanged" for each oracle. These are JUDGEMENT CONSTANTS and each is set at the
## scale of the defect it is watching for rather than at float epsilon: the lightest GPS in the
## catalog is 4 g and the lightest buzzer 1.5 g, so any tolerance below a milligram separates
## "unchanged" from "something got fitted" by three orders of magnitude. They are tight rather than
## generous on purpose — a loose tolerance on a bit-identical check is the same failure as no check.
const MASS_EPS_G := 1.0e-3
const TWR_EPS := 1.0e-4
const THROTTLE_EPS := 1.0e-5
const POSITION_EPS_M := 1.0e-8
## Wider than the others in absolute terms because it is a tolerance on a number near 400 rad/s²
## held in a float32 Vector3, where the representable spacing is already ~3e-5. A 14 g GPS moves
## the reference build's alpha by two to three percent — ten rad/s² — so this still separates
## "unchanged" from "something got fitted" by four orders of magnitude.
const ALPHA_EPS := 1.0e-3

## The reference build at `6e1de24`, measured. See the header for why the derived gains are not
## among them and `plant_alpha` is.
const REFERENCE_AUW_G := 507.480708
const REFERENCE_TWR := 11.429006
const REFERENCE_HOVER := 0.299194
const REFERENCE_COM_Y_M := 0.01183166
const REFERENCE_COM_Z_M := 0.00017882
const REFERENCE_PLANT_ALPHA := Vector3(396.628113, 369.980194, 54.708401)

## The equal-mass pair. The shipped catalog HAS NO SUCH PAIR — C1 authored flats at 4.0/6.5/9.0 g
## and masts at 11.0/14.0 g, and no flat and masted entry share a mass — so "a masted GPS raises the
## centre of mass by more than a flat one of EQUAL MASS" cannot be run against it. Comparing
## `gps_masted_long_range` against `gps_micro_flat` would pass on the 10 g mass difference alone and
## would prove nothing about the mast, which is the exact shape of a green-but-meaningless check.
##
## So the pair is constructed: identical mass, identical box, one field different. Injected into a
## real catalog through `by_id` (the house pattern — test_authored_blade.gd and four others) and
## fitted through `Build.from_ids`, so the whole production path runs. A fixture is the honest way
## to hold one variable still when the catalog cannot.
const PAIR_MASS_G := 10.0
const PAIR_MAST_MM := 45.0


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_the_reference_build_is_bit_identical())
	results.append_array(_added_mass_is_added(catalog))
	results.append(_the_budget_remainder_is_untouched())
	results.append_array(_the_mast_raises_the_centre_of_mass(catalog))
	results.append_array(_the_bays_are_where_the_design_says(catalog))
	results.append(_the_identity_holds_with_both_fitted(catalog))
	results.append_array(_the_six_categories_are_one_partition())

	return results


# ---------------------------------------------------------------------------
# ROW 1. The bit-identical oracle. The most important check in the wave.
# ---------------------------------------------------------------------------
## FAILS IF: either new category acquires a default, a carved share, or any other route onto a
## build nobody asked to put it on. Split into four results rather than one, so the failure says
## WHICH property moved — a mass that moved without the centre of mass moving is a different bug
## from both moving together.
static func _the_reference_build_is_bit_identical() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()

	# The statement itself, first and in its simplest form. Every number below is a consequence of
	# this one, and a reader looking for "why is nothing else different" should find it stated
	# rather than inferred from three tolerances.
	var fitted_added: Array[String] = []
	for category in Build.added_components():
		if build.components.has(category):
			fitted_added.append("%s (%s)" % [category,
				str((build.components[category] as Dictionary).get("name", "?"))])
	out.append(TestResult.new(
		"the reference build fits neither of the added components, because neither has a default",
		fitted_added.is_empty() and not Build.added_components().is_empty(),
		"%s not fitted; %d components on the aircraft" % [
			", ".join(Build.added_components()), build.components.size()]
			if fitted_added.is_empty() else "FITTED: %s" % ", ".join(fitted_added)
	))

	out.append(TestResult.new(
		"and therefore still weighs 507.480708 g at 11.429 : 1, hovering at 29.92%",
		absf(build.all_up_weight_g() - REFERENCE_AUW_G) < MASS_EPS_G
			and absf(build.thrust_to_weight() - REFERENCE_TWR) < TWR_EPS
			and absf(build.hover_throttle() - REFERENCE_HOVER) < THROTTLE_EPS,
		"%.6f g (%+.6f), %.6f : 1 (%+.6f), %.6f throttle (%+.6f)" % [
			build.all_up_weight_g(), build.all_up_weight_g() - REFERENCE_AUW_G,
			build.thrust_to_weight(), build.thrust_to_weight() - REFERENCE_TWR,
			build.hover_throttle(), build.hover_throttle() - REFERENCE_HOVER]
	))

	# The centre of mass, which is the oracle a MASTED default would move hardest and the weight
	# would barely register: 14 g of GPS 70 mm up moves the CoM vertically by 1.9 mm against an
	# all-up weight change of under 3%.
	var com := build.mass_properties.com_m
	out.append(TestResult.new(
		"and its centre of mass is still 0.18 mm aft and 11.83 mm up, on the centreline",
		absf(com.x) < POSITION_EPS_M
			and absf(com.y - REFERENCE_COM_Y_M) < POSITION_EPS_M
			and absf(com.z - REFERENCE_COM_Z_M) < POSITION_EPS_M,
		"(%.9f, %.9f, %.9f) m, expected (0, %.8f, %.8f)" % [
			com.x, com.y, com.z, REFERENCE_COM_Y_M, REFERENCE_COM_Z_M]
	))

	# The tune, asserted where it can actually move. See the header.
	var alpha := RateTune.plant_alpha_for(build)
	out.append(TestResult.new(
		"and the plant the tune is derived from is unmoved, so every build's gains are unmoved",
		(alpha - REFERENCE_PLANT_ALPHA).length() < ALPHA_EPS,
		"alpha (%.6f, %.6f, %.6f) rad/s², expected (%.6f, %.6f, %.6f)" % [
			alpha.x, alpha.y, alpha.z, REFERENCE_PLANT_ALPHA.x, REFERENCE_PLANT_ALPHA.y,
			REFERENCE_PLANT_ALPHA.z]
	))
	return out


# ---------------------------------------------------------------------------
# ROWS 2 AND 3. Added, not carved.
# ---------------------------------------------------------------------------
## Fitting one makes the aircraft HEAVIER, by exactly its own mass and by nothing else. This is the
## half of design §3 that a carved share would have made a lie: taking a 10 g GPS out of a 14 g
## remainder leaves the all-up weight unchanged, and with navigation unmodelled "it makes the
## aircraft heavier" is the single most useful thing Lothal can say about a GPS.
##
## One result per component rather than a loop over both: feedback_loop_tests_hide_coverage. A loop
## fails once whichever one broke, and these two are wired through different mounts on different
## faces of the aircraft.
static func _added_mass_is_added(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var bare := _reference_with(catalog, {})

	for category in Build.added_components():
		var rows := catalog.list_category(category)
		if rows.is_empty():
			out.append(TestResult.new(
				"fitting a %s makes the aircraft heavier by exactly its own mass" % category,
				false, "the %s category is empty, so nothing was tested" % category))
			continue
		# The HEAVIEST row in the category, so the difference is as far from zero as the catalog
		# can make it.
		var part: Dictionary = rows[rows.size() - 1]
		var fitted := _reference_with(catalog, {category: str(part["part_id"])})
		var gained := fitted.all_up_weight_g() - bare.all_up_weight_g()
		var expected := float(part["mass_g"])
		out.append(TestResult.new(
			"fitting a %s makes the aircraft heavier by exactly its own mass" % category,
			absf(gained - expected) < MASS_EPS_G and expected > 0.0,
			"%s: %.4f g -> %.4f g, gained %.4f g against a %.1f g part" % [
				str(part["name"]), bare.all_up_weight_g(), fitted.all_up_weight_g(),
				gained, expected]
		))
	return out


## And the budget is where it was. `budget_remainder_g()`'s job is to catch a share that outgrew
## what the budget has left; two components that were never in the budget consuming almost all of
## it would destroy that check while leaving it green (design §3.3).
static func _the_budget_remainder_is_untouched() -> TestResult:
	var offenders: Array[String] = []
	for category in Build.added_components():
		if Build.CARVED_SHARES.has(category):
			offenders.append(category)
	return TestResult.new(
		"the budget still has 14 g left, because neither added component carved a share",
		absf(Build.budget_remainder_g() - 14.0) < MASS_EPS_G and offenders.is_empty()
			and not Build.added_components().is_empty(),
		"%.3f g left of %.1f g after %.1f g of shares; added: %s" % [
			Build.budget_remainder_g(), Build.ELECTRONICS_BUDGET_G, Build.carved_total_g(),
			"none carve" if offenders.is_empty() else "CARVED: %s" % ", ".join(offenders)]
	)


# ---------------------------------------------------------------------------
# ROW 4. The mast, against a pair the catalog cannot supply.
# ---------------------------------------------------------------------------
## FAILS IF: `mast_height_mm` does not reach the seat, or reaches it with the wrong sign, or reaches
## it scaled. The magnitude is PREDICTED from the mass and the mast rather than read off the
## implementation: adding one mass to a body moves the centre of mass to the weighted mean, so
## raising that mass by `rise` with everything else held still moves the CoM up by
## `m * rise / M` exactly. A model that applied the mast twice, or halved it along with the box,
## passes a direction check and fails this one.
static func _the_mast_raises_the_centre_of_mass(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var flat := _inject_gps(catalog, "gps_fixture_flat", "Fixture flat", 0.0)
	var masted := _inject_gps(catalog, "gps_fixture_masted", "Fixture masted", PAIR_MAST_MM)

	var flat_build := _reference_with(catalog, {"gps": str(flat["part_id"])})
	var masted_build := _reference_with(catalog, {"gps": str(masted["part_id"])})

	# THE GUARD THAT KEEPS THIS FROM BEING A MASS COMPARISON. If the two builds ever stop weighing
	# the same, the comparison below is measuring mass and not the mast, and it must fail rather
	# than pass for the wrong reason.
	var equal_mass: bool = absf(masted_build.all_up_weight_g() - flat_build.all_up_weight_g()) \
		< MASS_EPS_G
	var mass_kg := PAIR_MASS_G / 1000.0
	var predicted: float = mass_kg * (PAIR_MAST_MM / 1000.0) \
		/ masted_build.mass_properties.total_mass_kg
	var measured: float = masted_build.mass_properties.com_m.y - flat_build.mass_properties.com_m.y

	out.append(TestResult.new(
		"a masted GPS raises the centre of mass above a flat one of exactly equal mass",
		equal_mass and measured > POSITION_EPS_M,
		"%.1f g both, %.1f mm of mast: CoM %.9f m -> %.9f m (+%.9f), aircraft %.4f g vs %.4f g" % [
			PAIR_MASS_G, PAIR_MAST_MM, flat_build.mass_properties.com_m.y,
			masted_build.mass_properties.com_m.y, measured,
			flat_build.all_up_weight_g(), masted_build.all_up_weight_g()]
	))
	out.append(TestResult.new(
		"and by the weighted mean of the mast and the aircraft, not by some multiple of it",
		equal_mass and absf(measured - predicted) < POSITION_EPS_M,
		"raised %.9f m, predicted %.9f m from %.1f g on a %.1f mm mast on a %.4f kg aircraft" % [
			measured, predicted, PAIR_MASS_G, PAIR_MAST_MM,
			masted_build.mass_properties.total_mass_kg]
	))

	# And the catalog can express it, on a SHIPPED row rather than a fixture: the masted entries
	# C1 authored sit their own mast height above the plate face they mount to, which is the claim
	# design §2.3 makes about the real parts.
	var shipped: Array[String] = []
	var checked := 0
	for row in catalog.list_category("gps"):
		var part: Dictionary = row
		if Build.component_rise_m(part) <= 0.0:
			continue
		checked += 1
		var build := _reference_with(catalog, {"gps": str(part["part_id"])})
		var mount := MountLayout.by_id(build.mount_points(), String(Build.COMPONENT_MOUNTS["gps"]))
		var entry := _part_mass_named(build, str(part["name"]))
		var expected: float = mount.position.y + Build.component_rise_m(part) \
			+ Build.component_size_of(part).y * 0.5
		if entry == null:
			shipped.append("%s is not in the mass model" % part["part_id"])
		elif absf(entry.position_m.y - expected) > POSITION_EPS_M:
			shipped.append("%s weighed at y = %.6f m, the plate face plus its mast is %.6f m" % [
				part["part_id"], entry.position_m.y, expected])
	out.append(TestResult.new(
		"and a shipped masted module is weighed its own mast height above the top plate",
		shipped.is_empty() and checked > 0,
		"%d masted catalog rows, each on its own stalk" % checked if shipped.is_empty()
			else str(shipped)
	))
	return out


# ---------------------------------------------------------------------------
# ROWS 5 AND 6. The two new bays, on the faces the design names.
# ---------------------------------------------------------------------------
static func _the_bays_are_where_the_design_says(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var mounts := build.mount_points()
	var gps_mount := MountLayout.by_id(mounts, String(Build.COMPONENT_MOUNTS["gps"]))
	var buzzer_mount := MountLayout.by_id(mounts, String(Build.COMPONENT_MOUNTS["buzzer"]))

	out.append(TestResult.new(
		"the frame offers both new bays, under the ids COMPONENT_MOUNTS names",
		gps_mount != null and buzzer_mount != null,
		"gps_mount %s, buzzer_mount %s" % [
			"present" if gps_mount != null else "MISSING",
			"present" if buzzer_mount != null else "MISSING"]
	))
	if gps_mount == null or buzzer_mount == null:
		return out

	# ROW 5. The GPS is on the CENTRELINE, so it contributes nothing fore or aft however heavy it
	# is and whichever module is fitted — rx_bay's property, for rx_bay's reason (design §2.3:
	# there is no edge a GPS belongs to across every frame, and inventing a fore/aft offset would
	# be inventing a coordinate). Asserted on the heaviest masted module in the catalog, where a
	# rear offset would show up most.
	#
	# THE INVARIANT IS THE MOMENT, NOT THE COORDINATE, and getting that wrong is a real trap this
	# check walked into on the way to being written. Fitting a 14 g GPS at zero fore/aft offset
	# moves the aircraft's CoM z from 0.000179 m to 0.000174 m — not because the GPS contributed
	# anything aft, but because the aft moment the OTHER components carry is now divided by a
	# heavier aircraft. The claim design §2.3 makes is that the GPS adds no moment, so that is what
	# is asserted: `com.z * total_mass` to the gram-millimetre, unchanged. A coordinate comparison
	# here would have had to be given a tolerance loose enough to swallow the dilution, which is a
	# tolerance loose enough to swallow a real rear offset on a light GPS as well.
	var heavy_gps: Dictionary = catalog.list_category("gps")[catalog.list_category("gps").size() - 1]
	var with_gps := _reference_with(catalog, {"gps": str(heavy_gps["part_id"])})
	var gps_entry := _part_mass_named(with_gps, str(heavy_gps["name"]))
	var bare_moment: float = ReferenceBuild.build().mass_properties.com_m.z \
		* ReferenceBuild.build().mass_properties.total_mass_kg
	var gps_moment: float = with_gps.mass_properties.com_m.z \
		* with_gps.mass_properties.total_mass_kg
	out.append(TestResult.new(
		"a GPS adds no fore/aft moment: its bay and its mass are both on the centreline",
		absf(gps_mount.position.z) < POSITION_EPS_M and gps_entry != null
			and absf(gps_entry.position_m.z) < POSITION_EPS_M
			and absf(gps_moment - bare_moment) < POSITION_EPS_M,
		"bay z = %.9f m, the %s weighed at z = %.9f m, aft moment %.9f -> %.9f kg m (CoM z %.9f -> %.9f m, diluted by a heavier aircraft)" % [
			gps_mount.position.z, str(heavy_gps["name"]),
			gps_entry.position_m.z if gps_entry != null else NAN,
			bare_moment, gps_moment,
			ReferenceBuild.build().mass_properties.com_m.z, with_gps.mass_properties.com_m.z]
	))

	# The buzzer's opposite number, and it is here to stop the check above being satisfied by a
	# model that puts EVERYTHING on the centreline. The buzzer is at the rear edge on purpose
	# (design §2.4: the front of the bottom plate is the camera bay), so it must move the centre of
	# mass AFT.
	var heavy_buzzer: Dictionary = catalog.list_category("buzzer")[
		catalog.list_category("buzzer").size() - 1]
	var with_buzzer := _reference_with(catalog, {"buzzer": str(heavy_buzzer["part_id"])})
	out.append(TestResult.new(
		"and a buzzer does move it aft, so the centreline above is a placement and not a coincidence",
		buzzer_mount.position.z > POSITION_EPS_M
			and with_buzzer.mass_properties.com_m.z
				> ReferenceBuild.build().mass_properties.com_m.z + POSITION_EPS_M,
		"bay z = %+.6f m (aft is +Z), aircraft CoM z %.9f -> %.9f m" % [
			buzzer_mount.position.z, ReferenceBuild.build().mass_properties.com_m.z,
			with_buzzer.mass_properties.com_m.z]
	))

	# ROW 6. UNDER the bottom plate, not between the plates. The two faces differ by one plate
	# thickness and both are named in `_component_bays`; seating the buzzer on the inner one would
	# put it inside the shell where design §2.4 says the sound is muffled, and nothing about the
	# number would look wrong. Compared against `strap_bottom` — the mount that is already defined
	# as the bottom plate's outer face — rather than against a literal, so a frame with different
	# plate geometry still states the same property.
	var strap_bottom := MountLayout.by_id(mounts, "strap_bottom")
	var camera_bay := MountLayout.by_id(mounts, String(Build.COMPONENT_MOUNTS["camera"]))
	var buzzer_entry := _part_mass_named(with_buzzer, str(heavy_buzzer["name"]))
	var buzzer_size := Build.component_size_of(heavy_buzzer)
	out.append(TestResult.new(
		"the buzzer's bay is the bottom plate's OUTER face, one plate thickness below the camera bay",
		strap_bottom != null and camera_bay != null
			and absf(buzzer_mount.position.y - strap_bottom.position.y) < POSITION_EPS_M
			and absf(camera_bay.position.y - buzzer_mount.position.y - Build.FRAME_PLATE_THICKNESS_M)
				< POSITION_EPS_M,
		"buzzer bay y = %.6f m, strap_bottom %.6f m, camera bay %.6f m (plate %.3f m)" % [
			buzzer_mount.position.y,
			strap_bottom.position.y if strap_bottom != null else NAN,
			camera_bay.position.y if camera_bay != null else NAN,
			Build.FRAME_PLATE_THICKNESS_M]
	))
	# ...and the buzzer itself hangs BELOW that face rather than growing up through the plate,
	# which is what the mount's normal is for.
	out.append(TestResult.new(
		"and the buzzer's whole box hangs below it, because that bay faces down",
		buzzer_entry != null and buzzer_mount.normal == -1
			and buzzer_entry.position_m.y
				< buzzer_mount.position.y - buzzer_size.y * 0.5 + POSITION_EPS_M,
		"normal %d, %s weighed at y = %.6f m against a face at %.6f m and a %.1f mm box" % [
			buzzer_mount.normal, str(heavy_buzzer["name"]),
			buzzer_entry.position_m.y if buzzer_entry != null else NAN,
			buzzer_mount.position.y, buzzer_size.y * 1000.0]
	))
	return out


# ---------------------------------------------------------------------------
# ROW 7. The identity, in its second form.
# ---------------------------------------------------------------------------
## THIS MIRRORS test_esc.gd's new check DELIBERATELY, and the duplication is disclosed rather than
## hidden. test_esc.gd owns the identity because it owns the budget; this file owns the statement
## that C2's two components are the term that made it need a second form, and it asserts the split
## as well as the sum — that `added_components_mass_g()` is exactly the two parts' own masses and
## not, say, the whole payload's.
static func _the_identity_holds_with_both_fitted(catalog: PartsCatalog) -> TestResult:
	var ids := {}
	var hand_summed := 0.0
	for category in Build.added_components():
		var rows := catalog.list_category(category)
		if rows.is_empty():
			continue
		ids[category] = str(rows[rows.size() - 1]["part_id"])
		hand_summed += float(rows[rows.size() - 1]["mass_g"])
	var build := _reference_with(catalog, ids)

	return TestResult.new(
		"electronics = carved shares + harness + added, on a build that fits both added components",
		ids.size() == Build.added_components().size() and hand_summed > 0.0
			and is_equal_approx(build.added_components_mass_g(), hand_summed)
			and absf(build.electronics_mass_g() - (Build.carved_total_g()
				+ build.harness_mass_g() + build.added_components_mass_g())) < MASS_EPS_G,
		"%.3f g electronics = %.1f carved + %.3f harness + %.3f added (hand-summed %.3f over %s)" % [
			build.electronics_mass_g(), Build.carved_total_g(), build.harness_mass_g(),
			build.added_components_mass_g(), hand_summed, ", ".join(ids.keys())]
	)


# ---------------------------------------------------------------------------
# ROW 8. Six categories, one partition.
# ---------------------------------------------------------------------------
## `no_components()` is what two suites pass to get a FORE/AFT SYMMETRIC aircraft, and it is
## generated from OPTIONAL_COMPONENTS rather than written down. The mutation the plan names —
## hand-write the four-name list — is the realistic one: it is what a reader would "tidy" it into,
## and the symmetric fixtures would then quietly carry a GPS the moment one acquired a default.
static func _the_six_categories_are_one_partition() -> Array:
	var out: Array = []
	var none := Build.no_components()

	var wrong: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		if not none.has(category):
			wrong.append("%s is missing" % category)
		elif str(none[category]) != "":
			wrong.append("%s = \"%s\"" % [category, str(none[category])])
	for key in none:
		if not Build.OPTIONAL_COMPONENTS.has(key):
			wrong.append("%s is named and is not an optional component" % key)
	out.append(TestResult.new(
		"no_components() names all six categories and fits none of them",
		wrong.is_empty() and none.size() == 6 and Build.OPTIONAL_COMPONENTS.size() == 6,
		"%d categories, all empty: %s" % [none.size(), ", ".join(PackedStringArray(none.keys()))]
			if wrong.is_empty() else str(wrong)
	))

	# The partition itself: carved and added are derived from CARVED_SHARES and must between them
	# be exactly OPTIONAL_COMPONENTS, once each. This is the P10f finding as a check — the two
	# lists were never the same list — and it is what makes `added_components()` safe to derive
	# the identity's third term from.
	var both := Build.carved_components().duplicate()
	both.append_array(Build.added_components())
	both.sort()
	var expected := Build.OPTIONAL_COMPONENTS.duplicate()
	expected.sort()
	out.append(TestResult.new(
		"and the carved and added lists partition those six exactly, with no category in both",
		both == expected and not Build.carved_components().is_empty()
			and not Build.added_components().is_empty(),
		"%d carved (%s) + %d added (%s) = %d optional" % [
			Build.carved_components().size(), ", ".join(Build.carved_components()),
			Build.added_components().size(), ", ".join(Build.added_components()),
			Build.OPTIONAL_COMPONENTS.size()]
	))
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
## The reference aircraft with these component ids overridden. Every other category falls to its
## default, which is what makes this the REFERENCE build rather than some other one — and which is
## how an override of `{}` reproduces `ReferenceBuild.build()` exactly.
static func _reference_with(catalog: PartsCatalog, overrides: Dictionary) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, overrides)


## One half of the equal-mass pair, in the shape `gps.json` publishes and injected the way five
## other suites inject a synthesised part. Only `mast_height_mm` differs between the two calls.
static func _inject_gps(catalog: PartsCatalog, part_id: String, name: String,
		mast_mm: float) -> Dictionary:
	var record := {
		"part_id": part_id,
		"name": name,
		"category": "gps",
		"mass_g": PAIR_MASS_G,
		"source": "a test fixture; the shipped catalog has no flat/masted pair of equal mass",
		"specs": {
			"length_mm": 22.0,
			"width_mm": 22.0,
			"height_mm": 7.0,
			"mast_height_mm": mast_mm,
		},
		"catalog": {
			"constellations": "GPS + GLONASS",
			"compass": true,
			"protocol": "UBX",
		},
	}
	catalog.by_id[part_id] = record
	return record


static func _part_mass_named(build: Build, label: String) -> PartMass:
	for part in build.mass_parts():
		if (part as PartMass).label == label:
			return part
	return null
