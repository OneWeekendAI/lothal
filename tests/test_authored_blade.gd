class_name TestAuthoredBlade
extends RefCounted
## An authored blade is a real propeller (plans/2026-09-01-authored-blade-design.md).
##
## Before this slice, `PropellerDocument.from_catalog_prop` GENERATED a planform from the catalog
## record's diameter, pitch and blade count, and every physics reader funnelled through it —
## `Build.blade_chord`, the guard's tip-chord length scale, `MotorSpinUp`'s blade inertia,
## `ThrustValidation`'s k_t fit. A blade a builder authored in the Propulsion room was saved to
## `user://blades` and read back by nothing. The room was a drawing program attached to nothing.
##
## Measured on the pre-slice code, and this is the number the headline check below exists for: a
## record carrying a planform scaled to 0.6 of the reference blade's chord produced a hover throttle
## of 0.295714000144 and a chord sum of 416.467705201470 mm — BIT-IDENTICAL to the unscaled
## reference, because the authored planform was discarded and the arch regenerated. The check is
## red without the resolver with no mutation needed.
##
## The two halves are a pair and neither is sufficient alone. The authored planform must REACH the
## physics (§5 obligation 1), and every shipped catalog prop must be untouched by the mechanism that
## carries it (§5 obligation 2) — a resolver that normalised or re-sampled the generated arch "on
## the way through" would move P6's anchor, ReferenceBuild's oracle and every thrust-validation fit
## at once.


## Pre-slice oracle, measured 2026-09-01 on the reference build. See the header: these are the
## numbers a catalog prop must still produce once the resolver stands between it and the physics.
const REF_HOVER_THROTTLE := 0.295714000144
const REF_CHORD_SUM_MM := 416.467705201470
const REF_TIP_CHORD_MM := 1.920962440934
const REF_THRUST_RATIO_AXIAL_12 := 0.837473619

## Bit-identity is asserted to the printed precision of the measurement, not to an eyeballed
## tolerance: the claim is that nothing moved, and a loose bound would let a re-sampled arch
## through.
const IDENTITY_EPS := 1e-9


static func run() -> Array:
	var results: Array = []
	results.append(_test_an_authored_planform_reaches_the_physics())
	results.append(_test_the_authored_chord_is_the_authored_chord())
	results.append(_test_a_catalog_prop_is_untouched())
	results.append(_test_every_catalog_prop_still_generates_its_arch())
	results.append(_test_an_unreadable_blade_warns_rather_than_lies())
	results.append(_test_a_record_with_no_blade_raises_no_such_warning())
	results.append(_test_the_published_mass_is_the_geometrys())
	results.append(_test_the_whole_model_moves_together_on_one_edit())
	results.append(_test_publishing_round_trips())
	return results


# ---------------------------------------------------------------------------
# Obligation 3 — the mass is derived, so the geometry is not cosmetic
# ---------------------------------------------------------------------------

## Two blades identical but for a 0.6 chord scale must publish two different masses, and the lighter
## one must be lighter in the proportion the geometry gives.
##
## THE PROPORTION IS 0.36, NOT 0.6, and the reason is worth stating because a first cut of this
## check asserted 0.6 and was wrong about the model rather than about the code. `blade_mass_g`
## integrates ∫c² dr, not ∫c dr: a document carries `thickness_ratio` as a fraction OF CHORD, so a
## blade narrowed at every station gets thinner in the same proportion. Mass goes as chord × depth
## and both halves scale, which is 0.6² = 0.36. Pinning 0.6 here would have been this test asserting
## a constant-thickness blade nobody models.
##
## Mutation that turns this red: publish with a class-typical default mass, or copy the source
## preset's `mass_g`. Either produces two identical records, and the ratio lands at 1.0.
static func _test_the_published_mass_is_the_geometrys() -> TestResult:
	var materials := PropellerDetails.materials()
	var full := CustomPropellers.record_from_document(_scaled_document(1.0), materials, "authored")
	var narrow := CustomPropellers.record_from_document(_scaled_document(0.6), materials, "authored")
	var full_g := float(full.get("mass_g", 0.0))
	var narrow_g := float(narrow.get("mass_g", 0.0))
	var ratio: float = narrow_g / full_g if full_g > 0.0 else 0.0
	# The document's own published_mass_g must agree with the record's: §3.1's round-trip, and the
	# invariant MotorSpinUp's two inertia paths rest on.
	var doc_agrees: bool = absf(float((narrow[PropellerDocument.AUTHORED_BLADE_KEY]
		as Dictionary).get("published_mass_g", 0.0)) - narrow_g) < 1e-9
	return TestResult.new(
		"a blade narrowed to 0.6 chord publishes at 0.36 of the mass (c-squared), and the document agrees",
		full_g > 0.0 and absf(ratio - 0.36) < 1e-6 and doc_agrees,
		"full %.4f g, narrow %.4f g, ratio %.6f, document agrees %s" % [
			full_g, narrow_g, ratio, str(doc_agrees)])


# ---------------------------------------------------------------------------
# Obligation 4 — one edit moves the WHOLE model, not half of it
# ---------------------------------------------------------------------------

## Thrust, mass, blade inertia and spin-up τ must all follow the same edit. §3.1's named failure is
## a publish path that derives aerodynamics from the new geometry and mass from the old one: half
## the model follows the blade and half does not, and nothing in the app says which half.
##
## Mutation that turns this red: derive mass but leave τ reading the source preset's document. Red
## on τ alone, which is why all four are one check.
static func _test_the_whole_model_moves_together_on_one_edit() -> TestResult:
	var materials := PropellerDetails.materials()
	var catalog_blade := _build_from_record(CustomPropellers.record_from_document(
		_scaled_document(1.0), materials, "authored"))
	var narrow := _build_from_record(CustomPropellers.record_from_document(
		_scaled_document(0.6), materials, "authored"))

	var thrust_moved: bool = narrow.hover_throttle() > catalog_blade.hover_throttle() + 1e-4
	var mass_moved: bool = float(narrow.propeller.get("mass_g", 0.0)) \
		< float(catalog_blade.propeller.get("mass_g", 0.0)) - 1e-6
	var ref_doc := PropellerDocument.from_catalog_prop(catalog_blade.propeller)
	var narrow_doc := PropellerDocument.from_catalog_prop(narrow.propeller)
	var inertia_moved: bool = BladeGeometry.blade_inertia_from_published_kg_m2(narrow_doc) \
		< BladeGeometry.blade_inertia_from_published_kg_m2(ref_doc)
	# The build's OWN tau, not a reconstruction of it: `_tau_s()` is the number the motor model is
	# created with, so a check that rebuilt the six arguments here could agree with itself while the
	# aircraft flew something else.
	var tau_moved: bool = narrow._tau_s() < catalog_blade._tau_s()
	return TestResult.new(
		"one planform edit moves thrust, mass, blade inertia and spin-up tau together",
		thrust_moved and mass_moved and inertia_moved and tau_moved,
		"thrust %s, mass %s, inertia %s, tau %s (%.5f s vs %.5f s)" % [
			str(thrust_moved), str(mass_moved), str(inertia_moved), str(tau_moved),
			narrow._tau_s(), catalog_blade._tau_s()])


# ---------------------------------------------------------------------------
# Obligation 8 — the round trip, including the fields nobody remembers
# ---------------------------------------------------------------------------

## Publish, write to a store, read it back, resolve: the document that comes out must equal the one
## that went in — including `thickness_ratio` and `twist`, which are exactly the fields a publish
## path that wrote only `chord` would drop. P10d found the mesh silently substituting a constant for
## `thickness_ratio`; this is the same field, one store over.
##
## Mutation that turns this red: publish `chord` alone. Red on thickness_ratio.
static func _test_publishing_round_trips() -> TestResult:
	var authored := _scaled_document(0.6)
	# An unmistakable, non-default value in each field a lazy publish would drop.
	authored.thickness_ratio = 0.073
	authored.twist_mode = PropellerDocument.TWIST_MODE_AUTHORED
	authored.twist = PackedFloat64Array([0.1, 0.42, 1.0, 0.11])
	var record := CustomPropellers.record_from_document(
		authored, PropellerDetails.materials(), "authored")

	# THROUGH THE REAL STORE, not through a bare JSON.stringify beside it. The first cut of this
	# check did the latter and failed, and the failure was worth having: `JSON.stringify`'s
	# `full_precision` argument defaults to FALSE, so a document written without it comes back at
	# about six significant digits. `JsonStore.write_document_atomic` was making exactly that call,
	# which meant every saved planform and every saved airframe outline was quietly rounded on the
	# way to disk. A test that serialises the document itself cannot see that; a test that uses the
	# store the app uses is red until the store is fixed.
	var scratch := "user://test_authored_blade_roundtrip.json"
	var wrote := JsonStore.write_document_atomic(scratch, record)
	var reread: Dictionary = JsonStore.read_document(scratch)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	var resolved := PropellerDocument.from_catalog_prop(reread)

	# NOT bit-equality, and the bound is measured rather than picked.
	#
	# Measured 2026-09-01, because a first cut of this check asserted `==` and a first attempt at
	# explaining the failure was wrong twice over. Godot's `JSON.stringify` emits about FOURTEEN
	# significant digits, and its `full_precision` argument produces byte-identical text for these
	# values — so the tempting "the store forgot full_precision" fix is a no-op, and was reverted
	# rather than shipped with a comment claiming otherwise. Fourteen digits round-trips most
	# doubles exactly and leaves the occasional ONE-ULP difference (seen: 9.75602948784759860 in,
	# 9.75602948784760038 out, 1.8e-15 — one ulp at that magnitude).
	#
	# So `PropellerDocument`'s header claim that doubles round-trip through JSON *exactly* is very
	# slightly optimistic, and this check states the truth rather than asserting a property the
	# format does not have. 1e-14 is a real floor and not a shrug: it is the store's own precision,
	# and it goes red the moment a planform is written through anything narrower — verified against
	# a publish path rounding chord to four decimals, which is what a well-meant "tidy the numbers"
	# would look like.
	var chord_worst_rel := 0.0
	var chord_sized: bool = resolved.chord.size() == authored.chord.size()
	if chord_sized:
		for i in authored.chord.size():
			var scale: float = maxf(absf(authored.chord[i]), 1e-9)
			chord_worst_rel = maxf(chord_worst_rel,
				absf(resolved.chord[i] - authored.chord[i]) / scale)
	var chord_ok: bool = chord_sized and chord_worst_rel < 1e-14
	var thickness_ok: bool = absf(resolved.thickness_ratio - 0.073) < 1e-12
	var twist_ok: bool = resolved.twist == authored.twist \
		and resolved.twist_mode == PropellerDocument.TWIST_MODE_AUTHORED
	var assumed_ok: bool = resolved.chord_is_assumed == false
	return TestResult.new(
		"a published blade survives JSON and resolves with its thickness, twist and chord intact",
		wrote and chord_ok and thickness_ok and twist_ok and assumed_ok,
		"wrote %s, chord %s (worst rel %s), thickness %.6f, twist %s, assumed %s" % [
			str(wrote), str(chord_ok), str(chord_worst_rel), resolved.thickness_ratio,
			str(twist_ok), str(resolved.chord_is_assumed)])


# ---------------------------------------------------------------------------
# Obligation 7 — §2.2's posture. A fallback nobody is told about is the defect.
# ---------------------------------------------------------------------------

## A truncated blade block falls back to the generated arch, says the chord is assumed again, and
## the BUILD CARRIES A WARNING that it did. All three, because the first two alone are exactly the
## silent-substitution defect this slice exists to delete, one layer down.
##
## Mutation that turns this red: drop the warning and keep the fallback. Red on the third clause
## only, which is why the clauses are asserted together rather than in three checks.
static func _test_an_unreadable_blade_warns_rather_than_lies() -> TestResult:
	var build := _build_with_blade_block({"chord": [0.1], "diameter_mm": 127.0, "blades": 3})
	var doc := PropellerDocument.from_catalog_prop(build.propeller)
	var generated := PropellerDocument.generate_chord(doc.diameter_mm, doc.blades)
	var fell_back: bool = doc.chord == generated
	var warnings := PropPlausibility.warnings_for(build)
	var warned := false
	for w in warnings:
		if w.id == &"unreadable_blade":
			warned = true
	return TestResult.new(
		"a record whose authored blade cannot be read falls back to the arch AND says so",
		fell_back and doc.chord_is_assumed and warned,
		"fell back %s, chord assumed %s, warned %s (%d warnings)" % [
			str(fell_back), str(doc.chord_is_assumed), str(warned), warnings.size()])


## The other polarity, and the reason `has_unreadable_blade` is a separate question from
## `authored_blade_of` returning null: every propeller Lothal ships resolves to null there, and a
## warning that fired on all of them would be noise on every build in the app.
static func _test_a_record_with_no_blade_raises_no_such_warning() -> TestResult:
	var warnings := PropPlausibility.warnings_for(ReferenceBuild.build())
	var warned := false
	for w in warnings:
		if w.id == &"unreadable_blade":
			warned = true
	var readable := _build_with_scaled_blade(0.6)
	var warned_on_good := false
	for w in PropPlausibility.warnings_for(readable):
		if w.id == &"unreadable_blade":
			warned_on_good = true
	return TestResult.new(
		"a catalog prop and a readable authored blade both raise no unreadable-blade warning",
		not warned and not warned_on_good,
		"catalog warned %s, authored warned %s" % [str(warned), str(warned_on_good)])


# ---------------------------------------------------------------------------
# Obligation 1 — the headline. Red on the pre-slice code with no mutation.
# ---------------------------------------------------------------------------

## A blade narrowed to 0.6 chord must fly differently. Less blade area at every station is less
## thrust per revolution, so the aircraft must hold itself up at a HIGHER throttle — the direction
## is asserted as well as the movement, because a resolver that handed the physics some other
## planform entirely would also "move" the number.
##
## The bound is deliberately one-sided and loose. What is under test is that the authored geometry
## arrives at all; the exact throttle is the BEMT's answer and pinning it here would be this file
## asserting the propulsion model, which `test_bemt.gd` already owns.
static func _test_an_authored_planform_reaches_the_physics() -> TestResult:
	var narrow := _build_with_scaled_blade(0.6)
	var throttle := narrow.hover_throttle()
	var moved: bool = absf(throttle - REF_HOVER_THROTTLE) > 1e-4
	return TestResult.new(
		"a blade authored at 0.6 chord flies at a higher throttle than the catalog blade",
		moved and throttle > REF_HOVER_THROTTLE,
		"authored %.9f vs catalog %.9f (moved %s)" % [throttle, REF_HOVER_THROTTLE, str(moved)])


## The planform the physics reads IS the one on the record, station for station — not merely a
## different one. Without this, obligation 1 passes for a resolver that reached for any other
## document, and the chord sum alone would pass for a planform with the right total area and the
## wrong distribution.
static func _test_the_authored_chord_is_the_authored_chord() -> TestResult:
	var authored := _scaled_document(0.6)
	var narrow := _build_with_scaled_blade(0.6)
	var got := narrow.blade_chord()
	var worst := 0.0
	var same_size: bool = got.size() == authored.chord.size()
	if same_size:
		for i in got.size():
			worst = maxf(worst, absf(got[i] - authored.chord[i]))
	return TestResult.new(
		"the build's planform is the authored one station for station, not a same-area substitute",
		same_size and worst == 0.0,
		"%d vs %d values, worst deviation %s mm" % [got.size(), authored.chord.size(), str(worst)])


# ---------------------------------------------------------------------------
# Obligation 2 — the anchor. Every existing oracle rides on this.
# ---------------------------------------------------------------------------

## The reference build, with no blade block anywhere, must produce the pre-slice numbers exactly.
## Mutation that turns this red: have the resolver re-sample or normalise the generated arch.
static func _test_a_catalog_prop_is_untouched() -> TestResult:
	var b := ReferenceBuild.build()
	var chord := b.blade_chord()
	var sum := 0.0
	for i in range(1, chord.size(), 2):
		sum += chord[i]
	var tip := PropellerDocument.from_catalog_prop(b.propeller).chord_at(1.0)
	var ratio := b.forward_ratios().thrust_ratio(20000.0, 12.0, 0.0)

	var throttle_ok: bool = absf(b.hover_throttle() - REF_HOVER_THROTTLE) < IDENTITY_EPS
	var sum_ok: bool = absf(sum - REF_CHORD_SUM_MM) < IDENTITY_EPS
	var tip_ok: bool = absf(tip - REF_TIP_CHORD_MM) < IDENTITY_EPS
	var ratio_ok: bool = absf(ratio - REF_THRUST_RATIO_AXIAL_12) < 1e-8
	return TestResult.new(
		"a catalog prop with no authored blade is bit-identical to the pre-slice build",
		throttle_ok and sum_ok and tip_ok and ratio_ok,
		"throttle %.12f, chord sum %.9f mm, tip %.9f mm, ratio %.9f" % [
			b.hover_throttle(), sum, tip, ratio])


## The whole shipped catalog, not just the reference prop: the arch is diameter- and
## blade-count-dependent, so a resolver that broke the generated path for 3" props only would pass
## the check above. Compared against `generate_chord` directly, which is the generator the resolver
## must still delegate to unchanged.
static func _test_every_catalog_prop_still_generates_its_arch() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var props := catalog.list_category("propeller")
	var checked := 0
	var worst := 0.0
	var assumed_everywhere := true
	for prop in props:
		var doc := PropellerDocument.from_catalog_prop(prop)
		var expected := PropellerDocument.generate_chord(doc.diameter_mm, doc.blades)
		if doc.chord.size() != expected.size():
			worst = INF
			continue
		for i in expected.size():
			worst = maxf(worst, absf(doc.chord[i] - expected[i]))
		if not doc.chord_is_assumed:
			assumed_everywhere = false
		checked += 1
	# The count is asserted because a scan that read nothing would otherwise pass — the catalog
	# ships well over a dozen propellers, and a zero here means the category name changed.
	return TestResult.new(
		"every shipped propeller still generates its arch, and still says the chord is assumed",
		checked == props.size() and checked > 10 and worst == 0.0 and assumed_everywhere,
		"%d/%d props, worst deviation %s mm, all flagged assumed %s" % [
			checked, props.size(), str(worst), str(assumed_everywhere)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The reference propeller's document with every chord scaled — the same blade, narrower, which is
## what a builder does in the room when they decide the catalog blade is too much for their motor.
static func _scaled_document(scale: float) -> PropellerDocument:
	var catalog := PartsCatalog.load_default()
	var doc := PropellerDocument.from_catalog_prop(catalog.get_part(ReferenceBuild.PROPELLER_ID))
	var scaled := doc.chord.duplicate()
	# Stride 2 and offset 1: the flat array is (r/R, chord_mm) pairs, and scaling the radii would
	# be authoring a different blade rather than a narrower one.
	for i in range(1, scaled.size(), 2):
		scaled[i] = scaled[i] * scale
	doc.chord = scaled
	# An authored planform is not an assumption any more — §3.1's flag, flipped by the act of
	# authoring, the same way the room's drag flips it.
	doc.chord_is_assumed = false
	return doc


## The reference aircraft flying one published record — the fixture the publish checks need, since
## what they are testing is a record `record_from_document` produced rather than one hand-built.
static func _build_from_record(record: Dictionary) -> Build:
	var catalog := PartsCatalog.load_default()
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		str(record["part_id"]), ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)


## The reference aircraft carrying an arbitrary blade block — the fixture the unreadable cases need,
## since `_scaled_document` can only produce blades that ARE readable.
static func _build_with_blade_block(block: Dictionary) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	record["part_id"] = "custom_propeller_broken_fixture"
	record["name"] = "Broken blade fixture"
	record["source"] = "a test fixture"
	record[PropellerDocument.AUTHORED_BLADE_KEY] = block
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		record["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)


## The reference aircraft with a custom propeller record carrying the scaled blade inline. Built
## through `Build.from_ids` on a catalog the record was merged into, which is the path a fitted
## custom part actually takes (tests/test_custom_propellers.gd uses the same arrangement).
static func _build_with_scaled_blade(scale: float) -> Build:
	var catalog := PartsCatalog.load_default()
	var record: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	record["part_id"] = "custom_propeller_narrow_fixture"
	record["name"] = "Narrow fixture blade"
	record["blade"] = _scaled_document(scale).to_dictionary()
	catalog.by_id[record["part_id"]] = record
	catalog.by_category["propeller"].append(record)
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		record["part_id"], ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
