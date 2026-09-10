class_name TestHarness
extends RefCounted
## The harness on the build — plans/2026-09-10-power-room-plan.md slice PW2.
##
## Two of these checks are a PAIR and neither is sufficient alone, which is the whole reason this
## suite is written the way it is.
##
## `MassProperties.compute` applies the parallel-axis shift `m·(|d|²E − d⊗d)` to every part, using
## the part's position and the composite centre of mass. So a `PartMass` must carry its LOCAL
## tensor — its own inertia about its own centre — and nothing else. Hand the local diagonal a term
## that already contains the offset (the pre-shifted scalar P10a's guard row nearly shipped) and
## the R² bite lands twice. Four leads at the arm ends is exactly the geometry where that would
## happen and stay plausible.
##
## P10b's review finding is why one check cannot cover it: **roll is I_ZZ**. A double-count wired
## into the X entry of a local diagonal lands in PITCH, and a roll assertion looks straight past it
## while the aircraft rolls correctly and pitches wrong forever. So:
##
##   - `_a_symmetric_harness_moves_the_centre_of_mass_nowhere` pins the POSITIONS, on every axis;
##   - `_four_motor_leads_raise_roll_inertia_by_parallel_axis_once` pins the TENSOR, on every axis,
##     against a diagonal this suite computes itself rather than reading back out of the build.
##
## Both mutations named in the plan's PW2 table were inserted in `src/assembly/build.gd` and both
## were confirmed red before either check was kept.

const MASS_EPS := 1.0e-9
## Inertia is order 1e-3 kg·m² on this aircraft, so a band at 1e-12 is eleven orders under the
## quantity and cannot be met by anything but the same arithmetic.
const INERTIA_EPS := 1.0e-12

# ---------------------------------------------------------------------------
# THE RE-BASELINE (design §4.4)
# ---------------------------------------------------------------------------
#
# The reference build was 496.0 g / 11.69 : 1 / 29.6% hover for the whole life of the project,
# with a flat 14 g wiring lump at the origin standing for the harness. PW2 replaced that lump with
# a real XT60 plug, a real 120 mm 14 AWG main lead, four real motor-lead segments, a real 470 µF
# capacitor and an honest straps-and-tape remainder — 25.5 g, and NONE of it tuned to land back on
# 496. The figure follows the model.
#
# What moved, and it is recorded here because "record what they are" is the point of the slice:
#
#     all-up weight     496.0 g   ->  507.5 g   (+11.5 g, the harness costing what it costs)
#     thrust-to-weight  11.69 : 1 ->  11.43 : 1
#     hover throttle    29.6 %    ->  29.9 %
#
# The old lump was LOW at the 5" end and HIGH at the small end: a 65 mm whoop's harness comes out
# at about half the flat 14 g, because its motor leads are shorter than the leads its motors
# already ship with and its plug is a third of a gram of BT2.0 rather than three grams of XT60.
const REFERENCE_AUW_G := 507.48
const REFERENCE_TWR := 11.43
const REFERENCE_HOVER := 0.2992
## The old figures, carried so the diff and the failure message both say what moved from what.
const PREVIOUS_AUW_G := 496.0


static func run() -> Array:
	var results: Array = []

	results.append(_test_defaults_derive_from_the_build())
	results.append(_test_an_authored_value_wins_and_the_default_stays_visible())
	results.append(_test_a_symmetric_harness_moves_the_centre_of_mass_nowhere())
	results.append(_test_four_motor_leads_raise_roll_inertia_by_parallel_axis_once())
	results.append(_test_harness_mass_is_exactly_the_sum_of_its_parts())
	results.append(_test_shortening_the_main_lead_lightens_and_moves_the_com_to_the_stack())
	results.append(_test_the_reference_build_matches_its_recorded_figures())
	results.append(_test_only_the_aircrafts_half_of_the_connector_is_weighed())
	results.append(_test_a_pigtail_is_not_counted_twice())
	results.append(_test_a_whoop_adds_no_motor_lead_its_motors_already_carry())

	return results


# ---------------------------------------------------------------------------
# Derived defaults, authored overrides
# ---------------------------------------------------------------------------

## Every default comes off the build, and the two that are joins come off the PACK. A default table
## that ignored the pack would put an XT60 on a 1S whoop and a 16 V capacitor on a 6S bus.
##
## FAILS IF: a band table is keyed on something the frame does not publish, or the connector default
## stops following `batteries.json`'s own `catalog.connector` — which is the join PW1's schema block
## exists to keep spelled one way.
static func _test_defaults_derive_from_the_build() -> TestResult:
	var five_inch := ReferenceBuild.build()
	var derived := Harness.defaults(five_inch)

	# The 5" freestyle: XT60 because the 4S 1500 terminates in one, 14 AWG to the stack, 20 AWG out.
	var passed: bool = String(derived[Harness.CONNECTOR]) == "connector_xt60"
	passed = passed and String(derived[Harness.CAPACITOR]) == "cap_470uf_35v"
	passed = passed and int(derived[Harness.MAIN_LEAD_AWG]) == 14
	# The motor lead is the ONE default derived from a measured number: the frame's own arm.
	passed = passed and is_equal_approx(float(derived[Harness.MOTOR_LEAD_LENGTH_MM]),
		five_inch.arm_m * 1000.0 + Harness.MOTOR_LEAD_ROUTING_ALLOWANCE_MM)

	# And it must actually MOVE with the parts, or every clause above is a constant with a
	# ceremony. A 1S whoop is a different plug, a different can and thinner wire in both runs.
	var whoop := _whoop()
	var whoop_defaults := Harness.defaults(whoop)
	passed = passed and String(whoop_defaults[Harness.CONNECTOR]) == "connector_bt20"
	passed = passed and String(whoop_defaults[Harness.CAPACITOR]) == "cap_220uf_16v"
	passed = passed and int(whoop_defaults[Harness.MAIN_LEAD_AWG]) > 14
	passed = passed and float(whoop_defaults[Harness.MOTOR_LEAD_LENGTH_MM]) \
		< float(derived[Harness.MOTOR_LEAD_LENGTH_MM])

	return TestResult.new(
		"harness defaults derive from the frame and the pack, and move when either does",
		passed,
		"5\": %s / %s / %d AWG / %.0f mm     whoop: %s / %s / %d AWG / %.0f mm" % [
			derived[Harness.CONNECTOR], derived[Harness.CAPACITOR],
			derived[Harness.MAIN_LEAD_AWG], derived[Harness.MOTOR_LEAD_LENGTH_MM],
			whoop_defaults[Harness.CONNECTOR], whoop_defaults[Harness.CAPACITOR],
			whoop_defaults[Harness.MAIN_LEAD_AWG], whoop_defaults[Harness.MOTOR_LEAD_LENGTH_MM]]
	)


## `AssemblyTweaks`'s contract, on a different table: an authored value wins, the derived default
## stays visible beside it, and clearing goes back to the parts. The middle clause is the one worth
## a check — PW4's inspector has to show a builder what they overrode, and a `defaults()` that
## returned the override would leave them with nothing to compare against.
##
## FAILS IF: the override table stops being sparse (a default frozen at write time), or `defaults()`
## learns to consult the overrides.
static func _test_an_authored_value_wins_and_the_default_stays_visible() -> TestResult:
	var build := ReferenceBuild.build()
	var derived := float(Harness.defaults(build)[Harness.MAIN_LEAD_LENGTH_MM])

	build.harness.set_value(Harness.MAIN_LEAD_LENGTH_MM, 75.0)
	var passed: bool = is_equal_approx(
		float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build)), 75.0)
	passed = passed and build.harness.has_override(Harness.MAIN_LEAD_LENGTH_MM)
	# The default is still what the parts imply, which is what a panel puts beside the field.
	passed = passed and is_equal_approx(
		float(Harness.defaults(build)[Harness.MAIN_LEAD_LENGTH_MM]), derived)
	passed = passed and derived != 75.0

	build.harness.clear(Harness.MAIN_LEAD_LENGTH_MM)
	passed = passed and is_equal_approx(
		float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build)), derived)

	return TestResult.new(
		"an authored lead length wins, and the derived default is still readable beside it",
		passed,
		"derived %.1f mm, authored 75.0 mm, cleared back to %.1f mm" % [
			derived, float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build))]
	)


# ---------------------------------------------------------------------------
# THE PAIR
# ---------------------------------------------------------------------------

## HALF ONE OF THE PAIR: the positions.
##
## Four leads at four symmetric arm ends have a mass-weighted centroid at the origin, exactly, on
## every axis. Not approximately — the positions are `MotorLayout`'s own and the four masses are
## the same float, so the sum is zero to the bit.
##
## MUTATION CONFIRMED RED: one motor lead's position shifted by a millimetre in `mass_parts()`.
## Note the "on every axis" part carefully: a millimetre in Y is invisible to any roll or pitch
## figure and shows up here.
static func _test_a_symmetric_harness_moves_the_centre_of_mass_nowhere() -> TestResult:
	var build := ReferenceBuild.build()
	var leads := _entries_labelled(build, "Motor lead")

	var moment := Vector3.ZERO
	var mass := 0.0
	for lead in leads:
		moment += lead.mass_kg * lead.position_m
		mass += lead.mass_kg

	var passed: bool = leads.size() == MotorLayout.MOTOR_NAMES.size()
	passed = passed and mass > 0.0
	passed = passed and moment.length() < MASS_EPS

	# And the harness AS A WHOLE puts nothing off the centreline: the connector is at a centred
	# pack, the trunk runs down the spine and the cap stands on the stack. X is the axis where that
	# has to hold exactly, because everything on this aircraft is mirrored about it.
	var harness_moment_x := 0.0
	for entry in _harness_entries(build):
		harness_moment_x += entry.mass_kg * entry.position_m.x
	passed = passed and absf(harness_moment_x) < MASS_EPS

	return TestResult.new(
		"a symmetric harness contributes zero net centre-of-mass offset",
		passed,
		"%d leads, %.4f g, first moment %.12f kg·m; whole-harness X moment %.12f kg·m" % [
			leads.size(), mass * 1000.0, moment.length(), harness_moment_x]
	)


## HALF TWO OF THE PAIR: the tensor, on every axis, and ROLL IS I_ZZ.
##
## The four leads are rebuilt here from scratch — mass, position and a thin-rod diagonal this suite
## computes — and `MassProperties` is run over the result. If `mass_parts()` handed a lead a
## pre-shifted scalar instead of a local diagonal, the build's tensor exceeds this one by the
## double-counted `m·R²` and every diagonal entry is compared, so it does not matter which axis the
## mistake was filed under.
##
## The second half is the one that stops this passing on a stub: the leads must actually RAISE roll
## inertia, by the parallel-axis amount, against a build whose motor leads weigh nothing. Four
## masses at the arm ends that changed no inertia would satisfy an equality check perfectly.
##
## MUTATION CONFIRMED RED: `PropGuard`-style scalar `mass * R²` handed to the local diagonal in
## `mass_parts()` — the exact double-count, inserted in the code.
static func _test_four_motor_leads_raise_roll_inertia_by_parallel_axis_once() -> TestResult:
	var build := ReferenceBuild.build()
	var lead_length_m := float(
		build.harness.value(Harness.MOTOR_LEAD_LENGTH_MM, build)) / 1000.0

	# The same parts list, with every motor lead replaced by one this suite built itself.
	var independent: Array = []
	for entry in build.mass_parts():
		if not entry.label.begins_with("Motor lead"):
			independent.append(entry)
			continue
		independent.append(PartMass.new(entry.mass_kg, entry.position_m,
			Harness.rod_diag_kg_m2(entry.mass_kg, lead_length_m, entry.position_m), entry.label))
	var expected := MassProperties.compute(independent)
	var actual := build.mass_properties

	var passed: bool = absf(actual.inertia.z.z - expected.inertia.z.z) < INERTIA_EPS
	passed = passed and absf(actual.inertia.x.x - expected.inertia.x.x) < INERTIA_EPS
	passed = passed and absf(actual.inertia.y.y - expected.inertia.y.y) < INERTIA_EPS

	# Against an aircraft carrying no motor lead at all. The delta must be positive and must be
	# the parallel-axis size — four masses at 0.078 m out on each axis.
	var bare := ReferenceBuild.build()
	bare.harness.set_value(Harness.MOTOR_LEAD_LENGTH_MM,
		Harness.motor_supplied_lead_mm(bare))
	bare.set_assembly(bare.assembly)
	var lead_mass_kg := build.harness.motor_lead_mass_g(build) / 1000.0
	var measured_delta := actual.inertia.z.z - bare.mass_properties.inertia.z.z

	# What four leads at the arm ends OUGHT to add to roll, written out here rather than read off
	# anything the build produced: each lead's own thin-rod term about Z, plus the parallel-axis
	# term `m·(|d|² − d_z²)` measured from the composite centre of mass — which is the reference
	# point `MassProperties` uses and the origin is not (physics.md §2).
	var expected_delta := 0.0
	var parallel_axis_only := 0.0
	for motor_name in MotorLayout.MOTOR_NAMES:
		var p := MotorLayout.motor_position(motor_name, build.arm_m)
		var d := p - actual.com_m
		var shift: float = lead_mass_kg * (d.length_squared() - d.z * d.z)
		parallel_axis_only += shift
		expected_delta += Harness.rod_diag_kg_m2(lead_mass_kg, lead_length_m, p).z + shift

	passed = passed and lead_mass_kg > 0.0
	passed = passed and measured_delta > 0.0
	# 2% band: removing four masses moves the composite centre of mass a little, so the two builds'
	# parallel-axis arms are not bit-identical. Far tighter than the term itself, which is what lets
	# it see a factor of two — which is exactly the size of the double-count it is here for.
	passed = passed and absf(measured_delta - expected_delta) / expected_delta < 0.02
	# And the R² term must be what dominates it, or this would be a check about a rod's own inertia
	# wearing a parallel-axis name.
	passed = passed and parallel_axis_only > 0.8 * expected_delta

	return TestResult.new(
		"four motor leads raise I_ZZ (roll) by the parallel-axis amount, applied exactly once",
		passed,
		"I_ZZ %.9f vs independent %.9f (I_XX %.9f vs %.9f); delta %.9f vs independent %.9f" % [
			actual.inertia.z.z, expected.inertia.z.z, actual.inertia.x.x, expected.inertia.x.x,
			measured_delta, expected_delta]
	)


# ---------------------------------------------------------------------------
# The mass, the length, and the recorded figures
# ---------------------------------------------------------------------------

## What `mass_parts()` appends and what `harness_mass_g()` reports are the SAME claim, and this is
## the check that makes a disagreement between them visible instead of leaving two functions to
## drift. Both are compared against a third sum written out term by term here.
##
## MUTATION CONFIRMED RED: one lead dropped from `Harness.total_mass_g`'s sum.
static func _test_harness_mass_is_exactly_the_sum_of_its_parts() -> TestResult:
	var build := ReferenceBuild.build()

	var appended := 0.0
	for entry in _harness_entries(build):
		appended += entry.mass_kg * 1000.0

	var term_by_term := build.harness.connector_mass_g(build) \
		+ build.harness.main_lead_mass_g(build) \
		+ 4.0 * build.harness.motor_lead_mass_g(build) \
		+ build.harness.capacitor_mass_g(build) \
		+ Harness.REMAINDER_MASS_G

	var passed: bool = absf(build.harness_mass_g() - term_by_term) < 1.0e-9
	passed = passed and absf(appended - term_by_term) < 1.0e-9
	# Every term must be non-zero, or an equality between two sums of nothing would hold.
	passed = passed and build.harness.connector_mass_g(build) > 0.0
	passed = passed and build.harness.main_lead_mass_g(build) > 0.0
	passed = passed and build.harness.motor_lead_mass_g(build) > 0.0
	passed = passed and build.harness.capacitor_mass_g(build) > 0.0

	return TestResult.new(
		"harness mass is exactly connector + main lead + four motor leads + capacitor + remainder",
		passed,
		"appended %.6f g, term-by-term %.6f g, reported %.6f g (%.2f + %.2f + 4x%.2f + %.2f + %.2f)" % [
			appended, term_by_term, build.harness_mass_g(),
			build.harness.connector_mass_g(build), build.harness.main_lead_mass_g(build),
			build.harness.motor_lead_mass_g(build), build.harness.capacitor_mass_g(build),
			Harness.REMAINDER_MASS_G]
	)


## The length field has to reach BOTH halves of the model — the mass AND the place. A shorter main
## lead is less copper, and it is less copper lying in the plane of the frame BELOW the aircraft's
## centre of mass, so the aircraft gets lighter and its centre of mass rises.
##
## THE DIRECTION IS UP, AND THAT IS WORTH SAYING RATHER THAN ASSERTING A NICER ONE. The lead is
## dressed on the plate, at the stack's own height; the aircraft's centre of mass sits about 12 mm
## above that because the pack is strapped over it. Take copper away from below a centre of mass
## and the centre of mass moves up — away from the stack, not towards it. The plan's PW2 row
## predicted "towards the stack", which was written against a lead that reached out along its own
## length; that geometry lifted eight grams of copper into the air and was replaced (see
## `Build.mass_parts()`). What the row is actually protecting is that length reaches the position
## and not only the scales, and that is what this asserts.
##
## Two clauses rather than one because the mass half alone would pass on a lead pinned at the
## origin, which is the model this slice replaced.
##
## MUTATION CONFIRMED RED: length made a no-op in the mass path.
static func _test_shortening_the_main_lead_lightens_and_moves_the_com_to_the_stack() -> TestResult:
	var long_lead := ReferenceBuild.build()
	var seat := MountLayout.by_id(long_lead.mount_points(), "stack")
	var stack: Vector3 = seat.position if seat != null else Vector3.ZERO

	var short_lead := ReferenceBuild.build()
	short_lead.harness.set_value(Harness.MAIN_LEAD_LENGTH_MM,
		float(long_lead.harness.value(Harness.MAIN_LEAD_LENGTH_MM, long_lead)) * 0.5)
	short_lead.set_assembly(short_lead.assembly)

	var long_distance := (long_lead.mass_properties.com_m - stack).length()
	var short_distance := (short_lead.mass_properties.com_m - stack).length()

	var passed: bool = short_lead.all_up_weight_g() < long_lead.all_up_weight_g() - 1.0e-6
	# UP, and by more than a rounding error: the lead is below the centre of mass, so removing it
	# raises it. Asserted as a signed move rather than as "changed", because a model that moved the
	# centre of mass the wrong way would satisfy an inequality on the magnitude.
	passed = passed and short_lead.mass_properties.com_m.y \
		> long_lead.mass_properties.com_m.y + 1.0e-7
	passed = passed and short_distance > long_distance

	return TestResult.new(
		"halving the main lead lightens the aircraft and lifts its centre of mass off the plate",
		passed,
		"%.4f g -> %.4f g; centre of mass %.6f m up -> %.6f m up (%.6f m from the stack -> %.6f m)" % [
			long_lead.all_up_weight_g(), short_lead.all_up_weight_g(),
			long_lead.mass_properties.com_m.y, short_lead.mass_properties.com_m.y,
			long_distance, short_distance]
	)


## THE RE-BASELINE, ASSERTED. See the constants at the top for what moved and why nothing was tuned
## to keep it where it was.
##
## This is the check that would catch a default quietly edited to protect a published figure, which
## design §4.4 forbids by name: the numbers here are what the model produces, and if a default lead
## length changes then this suite says so in the same commit rather than the aircraft changing
## weight in silence.
##
## MUTATION CONFIRMED RED: the 5" row's main lead length changed in `Harness.CLASS_ROWS`.
static func _test_the_reference_build_matches_its_recorded_figures() -> TestResult:
	var build := ReferenceBuild.build()

	var passed: bool = absf(build.all_up_weight_g() - REFERENCE_AUW_G) < 0.01
	passed = passed and absf(build.thrust_to_weight() - REFERENCE_TWR) < 0.01
	passed = passed and absf(build.hover_throttle() - REFERENCE_HOVER) < 0.001
	# And the aircraft really did get heavier than the lump it replaced, or "re-baseline" would be
	# a word for a number that did not move.
	passed = passed and build.all_up_weight_g() > PREVIOUS_AUW_G

	return TestResult.new(
		"the reference build weighs 507.5 g at 11.43 : 1 and hovers at 29.9%, and the harness is why",
		passed,
		"%.2f g (was %.1f), %.3f : 1, %.2f%% hover; harness %.2f g against the old 14.0 g lump" % [
			build.all_up_weight_g(), PREVIOUS_AUW_G, build.thrust_to_weight(),
			build.hover_throttle() * 100.0, build.harness_mass_g()]
	)


# ---------------------------------------------------------------------------
# The two double-counts
# ---------------------------------------------------------------------------

## THE THIRD DOUBLE-COUNT, and the one PW1 did not see coming. `connectors.json` publishes `mass_g`
## as the mass of the PAIR and its schema block says that is "what a build actually carries". Wiring
## it up showed that it is not: the female half is soldered to the PACK, and `batteries.json`'s
## masses are published pack weights, measured by a manufacturer with the lead and plug already on.
##
## So the aircraft carries half a pair, and the check is that it carries exactly half — not "less
## than a pair", which a model that subtracted an invented gram would also satisfy.
##
## FAILS IF: the whole pair is weighed on the aircraft, putting the pack's own plug on it twice.
static func _test_only_the_aircrafts_half_of_the_connector_is_weighed() -> TestResult:
	var build := ReferenceBuild.build()
	var row: Dictionary = build.catalog.get_part("connector_xt60")
	var pair := float(row.get("mass_g", 0.0))

	var passed: bool = pair > 0.0
	passed = passed and absf(build.harness.connector_mass_g(build) - pair * 0.5) < MASS_EPS
	# And the pack it plugs into really does carry a published mass with a plug on it, which is the
	# claim the halving rests on — a pack with no mass would make this arithmetic about nothing.
	passed = passed and float(build.battery.get("mass_g", 0.0)) > 0.0

	return TestResult.new(
		"the aircraft carries its half of the connector pair, not the pack's half as well",
		passed,
		"XT60 pair %.1f g published, %.2f g on the aircraft, against a %.0f g pack that was weighed with its own half on" % [
			pair, build.harness.connector_mass_g(build), float(build.battery.get("mass_g", 0.0))]
	)


## `connectors.json`'s schema block names `pigtail_mass_g` as a double-count waiting to happen: the
## XT60H ships pre-soldered to a lead pair, and `WireGauge` models that stretch of wire too. PW2
## counts the modelled lead and not the row's figure — see `Harness.connector_mass_g` for why that
## way round — so a housed connector must cost exactly the pair mass and not a gram more.
##
## FAILS IF: `pigtail_mass_g` is ever added to the harness beside the main lead.
static func _test_a_pigtail_is_not_counted_twice() -> TestResult:
	var build := ReferenceBuild.build()
	build.harness.set_value(Harness.CONNECTOR, "connector_xt60h")
	build.set_assembly(build.assembly)

	var row: Dictionary = build.catalog.get_part("connector_xt60h")
	var pigtail := float((row.get("specs", {}) as Dictionary).get("pigtail_mass_g", 0.0))

	var passed: bool = pigtail > 0.0
	passed = passed and absf(build.harness.connector_mass_g(build)
		- float(row.get("mass_g", 0.0)) * Harness.AIRCRAFT_SIDE_SHARE) < MASS_EPS
	# And the whole harness must be the pair plus the modelled lead, with the pigtail nowhere in it.
	var without_pigtail := build.harness.total_mass_g(build)
	passed = passed and absf(without_pigtail
		- (float(row["mass_g"]) * Harness.AIRCRAFT_SIDE_SHARE
			+ build.harness.main_lead_mass_g(build)
			+ 4.0 * build.harness.motor_lead_mass_g(build)
			+ build.harness.capacitor_mass_g(build) + Harness.REMAINDER_MASS_G)) < MASS_EPS

	return TestResult.new(
		"a connector's shipped pigtail is not weighed on top of the lead the model already draws",
		passed,
		"XT60H pair %.1f g (half of it on the aircraft), published pigtail %.1f g not counted; harness %.2f g" % [
			float(row.get("mass_g", 0.0)), pigtail, without_pigtail]
	)


## The other direction of the same rule, and the reason `Harness.motor_supplied_lead_mm` exists: a
## motor is sold with its phase wires on, and `motors.json` masses include them. So the harness may
## only weigh the run BEYOND them — and a 65 mm whoop, whose entire ESC-to-motor run is 62 mm, adds
## a fraction of a gram of wire across all four arms while its whole harness comes out at well under
## the flat 14 g lump this slice replaced. That small-end overweight is an error the old model was
## known to carry and this is where it is visible.
##
## FAILS IF: the supplied stub stops being subtracted, which would put a motor's own leads on the
## aircraft twice on every build in the catalog.
static func _test_a_whoop_adds_no_motor_lead_its_motors_already_carry() -> TestResult:
	var whoop := _whoop()

	var run_mm := float(whoop.harness.value(Harness.MOTOR_LEAD_LENGTH_MM, whoop))
	var supplied_mm := Harness.motor_supplied_lead_mm(whoop)
	var reference_supplied := Harness.motor_supplied_lead_mm(ReferenceBuild.build())

	# The stub is class-typical, not flat: a whoop motor's pigtail is a fraction of a 2207's, and a
	# flat one would have made this check pass for the wrong reason.
	var passed: bool = supplied_mm < reference_supplied
	# What the harness adds out at the arms is the run less what came on the motor, and on a whoop
	# that is a fraction of a gram across all four.
	passed = passed and whoop.harness.motor_lead_mass_g(whoop) * 4.0 < 2.0
	var five_inch := ReferenceBuild.build()
	passed = passed and whoop.harness.motor_lead_mass_g(whoop) \
		< five_inch.harness.motor_lead_mass_g(five_inch)
	# The harness still exists — plug, lead, cap, straps — and it is lighter than the lump it
	# replaced, which the 5" build is not.
	passed = passed and whoop.harness_mass_g() > 0.0
	passed = passed and whoop.harness_mass_g() < Build.budget_remainder_g()

	return TestResult.new(
		"a whoop's arms are shorter than its motors' own leads, so the harness adds none",
		passed,
		"%.0f mm run against a %.0f mm supplied stub (%.0f mm on the 5\"); %.3f g of added lead per motor; harness %.2f g against the old %.1f g lump" % [
			run_mm, supplied_mm, reference_supplied,
			whoop.harness.motor_lead_mass_g(whoop), whoop.harness_mass_g(),
			Build.budget_remainder_g()]
	)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A 1S whoop with nothing optional fitted — the other end of the catalog, and the build where the
## small-end behaviour of every table in `Harness` is visible.
static func _whoop() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), "frame_65mm_whoop",
		"motor_0802_19000kv", "prop_16x12x4", "battery_1s_300",
		Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID, Build.no_components())


## The mass entries this slice appends, by the labels `mass_parts()` gives them. Reading by label is
## exactly what `PartMass.label` was carried for, and it is inert to the physics — a mislabelled
## entry is a wrong caption here, never a wrong number in the aircraft.
static func _harness_entries(build: Build) -> Array:
	var out: Array = []
	for entry in build.mass_parts():
		for prefix in ["Connector", "Main lead", "Motor lead", "Capacitor", "Harness remainder"]:
			if entry.label.begins_with(prefix):
				out.append(entry)
				break
	return out


static func _entries_labelled(build: Build, prefix: String) -> Array:
	var out: Array = []
	for entry in build.mass_parts():
		if entry.label.begins_with(prefix):
			out.append(entry)
	return out
