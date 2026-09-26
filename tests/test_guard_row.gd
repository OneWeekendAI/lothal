class_name TestGuardRow
extends RefCounted
## The guard's inspector row, and the wiring behind it — P10f.
##
## ## What this suite is actually about
##
## `Build.guard_id` has existed since P10b and no builder could reach it. The physics was proved
## (P10a), the ring was drawn (P10c), the BEMT tip-loss closure was wired end to end (P10b), and
## the only caller of any of it was a test. Both of those slices ended by naming the gap. So the
## checks here are not "a dropdown exists" — they are the four links between a dropdown and an
## aircraft, each of which can be broken on its own:
##
##   1. The row reports what is fitted (`guard_id`).
##   2. `LabScreen.current_build()` puts it on the Build — asserted through MASS, because a
##      `guard_id` that reaches `Build` and changes no number is the failure that looks like
##      success.
##   3. `LabScreen.selection()` carries it to the project file, and `apply_selection` puts it back.
##   4. `Project.to_build` hands it to `Build.from_ids` as the trailing argument rather than
##      leaving it in the components dictionary, where `Build` would never look at it.
##
## ## The two checks that would have passed while proving nothing
##
## **"Fitting a guard changes the build."** Asserting `build.guard_id != ""` passes against a Build
## that stored the id and weighed nothing — which is precisely the state P10a shipped in and P10b
## found. So the assertion is on `all_up_weight_g()`, and against a bound computed from
## `PropGuard.mass_kg` times four motors rather than against a recorded number, so the check knows
## what it is expecting and not merely that something moved.
##
## **"A saved guard comes back."** A round trip through a Project whose `to_build` dropped the
## guard on the floor would still return a valid Build, with the right frame and motor and prop,
## four grams-per-motor lighter and — for a duct — drawing more current than the aircraft that was
## saved. So the round trip is asserted on the REBUILT BUILD's guard, not on the parts dictionary
## the file happens to carry.
##
## The unfitted case is asserted positively in both directions, because the reference build's
## 496 g / 11.69:1 / 29.6% oracle is bit-identical only while "no guard" stays exactly that.

const CINEWHOOP_GUARD := "guard_duct_5in_cinewhoop"
const BUMPER_GUARD := "guard_bumper_5in_abs"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_the_row_opens_on_nothing_fitted(catalog))
	results.append(_the_export_button_is_dead_until_a_guard_is_fitted(catalog))
	results.append(_selecting_a_guard_announces_it(catalog))
	results.append(_the_tip_radius_comes_from_the_document(catalog))
	results.append(_a_fitted_guard_reaches_the_build_and_weighs_something())
	results.append(_no_guard_leaves_the_reference_oracle_where_it_was())
	results.append(_the_selection_carries_the_guard())
	results.append(_a_saved_guard_comes_back_on_the_rebuilt_build(catalog))
	results.append(_a_guard_that_left_the_catalog_is_reported_not_substituted())
	return results


# ---------------------------------------------------------------------------
# The row itself
# ---------------------------------------------------------------------------

static func _panel(catalog: PartsCatalog) -> PropellerDetails:
	var panel := PropellerDetails.new(catalog)
	panel.render(catalog.get_part(ReferenceBuild.PROPELLER_ID), ReferenceBuild.build())
	return panel


static func _the_row_opens_on_nothing_fitted(catalog: PartsCatalog) -> TestResult:
	var panel := _panel(catalog)
	var fitted := panel.guard_id()
	panel.free()
	return TestResult.new(
		"the guard row opens on nothing fitted, which is the aircraft the reference build is",
		fitted == "",
		"guard_id = \"%s\"" % fitted)


## A button that emits a request nobody can satisfy is indistinguishable from a broken one.
static func _the_export_button_is_dead_until_a_guard_is_fitted(catalog: PartsCatalog) -> TestResult:
	var panel := _panel(catalog)
	var dead_at_first := panel._guard_export.disabled
	panel.select_guard(CINEWHOOP_GUARD)
	var live_with_a_guard := not panel._guard_export.disabled
	panel.select_guard("")
	var dead_again := panel._guard_export.disabled
	panel.free()
	return TestResult.new(
		"the STL export is disabled with nothing fitted, live with a guard, and dead again after",
		dead_at_first and live_with_a_guard and dead_again,
		"disabled: start=%s fitted=%s back=%s" % [dead_at_first, not live_with_a_guard, dead_again])


static func _selecting_a_guard_announces_it(catalog: PartsCatalog) -> TestResult:
	var panel := _panel(catalog)
	var heard: Array = []
	panel.guard_changed.connect(func(guard_id: String) -> void: heard.append(guard_id))
	# Driven through the selector's own signal, not through `select_guard` — `select_guard` is the
	# restore path (opening a saved drone must not re-announce a change) and a check that drove it
	# would prove nothing about what a click does.
	panel._guard_selector.select(panel._guard_ids.find(BUMPER_GUARD))
	panel._on_guard_selected(panel._guard_selector.selected)
	var reported := panel.guard_id()
	panel.free()
	return TestResult.new(
		"choosing a guard announces exactly that guard, and the row reports it back",
		heard == [BUMPER_GUARD] and reported == BUMPER_GUARD,
		"heard %s, row reports \"%s\"" % [heard, reported])


## The tip radius the ring is fitted around must come from the SAME document the mesh, the mass
## integral and the BEMT closure read. A `diameter_inches / 2` computed on the panel would be a
## second definition of a propeller's radius, and the guard's whole inner wall hangs off it — so
## the check is against `PropellerDocument`, which is where the one definition lives.
static func _the_tip_radius_comes_from_the_document(catalog: PartsCatalog) -> TestResult:
	var prop := catalog.get_part(ReferenceBuild.PROPELLER_ID)
	var panel := _panel(catalog)
	var from_panel := panel._tip_radius_m()
	panel.free()
	var expected := PropellerDetails.document_for(prop).diameter_mm * 0.0005
	return TestResult.new(
		"the tip radius the guard is fitted around is the document's, not a second definition",
		absf(from_panel - expected) < 1e-12 and from_panel > 0.0,
		"%.9f m against PropellerDocument's %.9f m" % [from_panel, expected])


# ---------------------------------------------------------------------------
# The wiring behind it
# ---------------------------------------------------------------------------

## Asserted through MASS. A `guard_id` that reaches Build and weighs nothing is the exact state
## P10a shipped in, and it passes any check that reads the id back.
static func _a_fitted_guard_reaches_the_build_and_weighs_something() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var bare := ReferenceBuild.build()
	var guarded := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, BUMPER_GUARD)

	var guard := catalog.get_part(BUMPER_GUARD)
	var expected_g := PropGuard.mass_kg(guard["specs"]) * 1000.0 * MotorLayout.MOTOR_NAMES.size()
	var delta_g := guarded.all_up_weight_g() - bare.all_up_weight_g()

	return TestResult.new(
		"a fitted guard reaches the aircraft as four rings of real mass, not as a stored id",
		absf(delta_g - expected_g) < 0.01 and guarded.guard.get("part_id", "") == BUMPER_GUARD,
		"%.3f g against 4 × PropGuard.mass_kg = %.3f g" % [delta_g, expected_g])


## The other direction, positively. "No guard" has to be exactly no guard, or the oracle every
## other suite is pinned to moves underneath them.
static func _no_guard_leaves_the_reference_oracle_where_it_was() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var bare := ReferenceBuild.build()
	var explicitly_none := Build.from_ids(catalog, ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, null, "")
	return TestResult.new(
		"fitting no guard leaves the reference build's mass and TWR bit-identical",
		explicitly_none.all_up_weight_g() == bare.all_up_weight_g()
			and explicitly_none.thrust_to_weight() == bare.thrust_to_weight()
			and explicitly_none.guard.is_empty(),
		"%.6f g / %.6f:1 against %.6f g / %.6f:1" % [explicitly_none.all_up_weight_g(),
			explicitly_none.thrust_to_weight(), bare.all_up_weight_g(), bare.thrust_to_weight()])


static func _the_selection_carries_the_guard() -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default())
	lab.propeller_details.select_guard(CINEWHOOP_GUARD)
	var carried := String(lab.selection().get("guard", "<absent>"))
	var on_build := String(lab.current_build().guard.get("part_id", ""))
	lab.free()
	return TestResult.new(
		"LabScreen's selection carries the guard, and current_build() fits it",
		carried == CINEWHOOP_GUARD and on_build == CINEWHOOP_GUARD,
		"selection says \"%s\", the build fits \"%s\"" % [carried, on_build])


## The round trip, asserted on the REBUILT BUILD rather than on the parts dictionary: a `to_build`
## that left the guard in the components block would write it to the file correctly, read it back
## correctly, and hand `Build.from_ids` a dictionary it never looks at.
static func _a_saved_guard_comes_back_on_the_rebuilt_build(catalog: PartsCatalog) -> TestResult:
	var project := Project.create("guard round trip")
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	project.parts["guard"] = CINEWHOOP_GUARD

	var written := project.to_dict()
	var reopened := Project.from_dict(written)
	var missing: Array = []
	var build := reopened.to_build(catalog, missing)

	var fitted := "" if build == null else String(build.guard.get("part_id", ""))
	# A duct also carries a closure, and it is the number that would be silently zero if the guard
	# arrived as a record without reaching `_recompute`.
	var closure := 0.0 if build == null else build.guard_closure
	return TestResult.new(
		"a guard saved to a project comes back fitted on the rebuilt aircraft, closure and all",
		fitted == CINEWHOOP_GUARD and closure > 0.0 and missing.is_empty(),
		"rebuilt with \"%s\", closure %.4f, missing %s" % [fitted, closure, missing])


## `LabScreen.apply_selection`'s own rule, extended to the guard: nothing is silently substituted.
## A guard quietly dropped to "none" reopens a saved drone lighter, with more roll authority, and
## — if it was a duct — drawing more current than the one that was saved.
static func _a_guard_that_left_the_catalog_is_reported_not_substituted() -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default())
	lab.propeller_details.select_guard(BUMPER_GUARD)
	var failed := lab.apply_selection({"guard": "guard_that_was_deleted"})
	var still_fitted := lab.propeller_details.guard_id()
	lab.free()

	var reported := false
	for entry in failed:
		if String(entry["category"]) == "guard" \
				and String(entry["part_id"]) == "guard_that_was_deleted":
			reported = true
	return TestResult.new(
		"a guard id the catalog no longer knows is reported, and the row is left where it was",
		reported and still_fitted == BUMPER_GUARD,
		"reported=%s, row still fits \"%s\"" % [reported, still_fitted])
