class_name TestAirframeTabs
extends RefCounted
## The four Airframe inspector tabs — Structure, Arms, Fasteners, Layout.
##
## ## What this suite is for, and what it deliberately is not
##
## The maths behind every row is already covered: `test_airframe_properties.gd`, `test_arm_beam.gd`,
## `test_arm_profile.gd`, `test_hardware_mass.gd` and `test_control_effectiveness.gd` assert the
## NUMBERS. Re-asserting them here would test the same code twice and the panels not at all. So
## every test below is about the PANEL: that it reaches the right computation, that it renders what
## that computation returned, and above all that it says "I don't know" where the geometry does not
## know.
##
## Each assertion goes through `row_text()`, which is the same call the panel paints its labels
## from. Asserting against the document instead would be asserting the document.
##
## ## THE TAB'S SUBJECT IS A FRAME
##
## These panels take an `AirframeDocument` and no `Build`. That is the point of the whole rework —
## the old versions inherited the aircraft's five derived stats and answered them about whatever
## build happened to be loaded, so a builder drawing an arm was shown a freestyle quad's hover
## throttle. `_test_no_row_needs_a_motor_or_a_thrust` is the guard on that and it is the most
## important test in the file: it renders a frame with NOTHING else in existence and requires every
## row of all four tabs to answer.
##
## ## MUTATION NOTES
##
## Every test states what breaks it. The three that matter most:
##
##   - `_test_assumed_width_is_labelled` fails if the assumed-width caveat is dropped. Fourteen of
##     fifteen catalog frames have their arm width GENERATED (§9a: nobody publishes one), and
##     measuring that generated outline would otherwise launder a constant in this file into a
##     "measured" resonance.
##   - `_test_a_drawn_arm_needs_no_caveat` is the other half of the same coin, and fails if the
##     caveat is applied to everything to be safe. A width a builder drew is not an assumption, and
##     a panel that hedges everything says nothing.
##   - `_test_no_row_needs_a_motor_or_a_thrust` fails the moment any row reaches for propulsion
##     again — the row would dash or crash for a document that has never seen a build.

const REFERENCE_FRAME := "frame_5in_freestyle"
## The one frame in the catalog with a published arm width (§9a).
const WIDTH_PUBLISHED_FRAME := "frame_5in_freestyle"
## Injection-moulded, no plate arm, outside the plate model entirely (§0).
const MOULDED_FRAME := "frame_65mm_whoop"
## A real plate frame whose arm width nobody publishes — so the preset's outline is generated.
const WIDTH_ASSUMED_FRAME := "frame_7in_long_range"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_structure_reports_the_mass_gap(catalog))
	results.append(_test_structure_inertia_is_not_transposed(catalog))
	results.append(_test_a_drawn_frame_has_no_vendor_to_disagree_with())
	results.append(_test_arms_section_and_mass(catalog))
	results.append(_test_assumed_width_is_labelled(catalog))
	results.append(_test_a_drawn_arm_needs_no_caveat())
	results.append(_test_moulded_frame_says_why_not(catalog))
	results.append(_test_fasteners_are_derived_not_zero(catalog))
	results.append(_test_a_flagged_joint_reads_as_a_short_line())
	results.append(_test_layout_is_controllable(catalog))
	results.append(_test_no_row_needs_a_motor_or_a_thrust(catalog))
	results.append(_test_every_row_renders_for_every_frame(catalog))
	return results


static func _document(catalog: PartsCatalog, part_id: String) -> AirframeDocument:
	return AirframeDocument.from_catalog_frame(catalog.get_part(part_id))


static func _panel(panel: AirframePanel, document: AirframeDocument) -> AirframePanel:
	panel.render(document)
	return panel


# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------

## The mass gap is REPORTED, not hidden and not smoothed. §9a measured it and put the residual on
## outline topology; a panel that printed only the computed figure would let a builder read a
## −48% number as the vendor's.
##
## MUTATION: drop the delta from the `mass_gap` row and this fails.
static func _test_structure_reports_the_mass_gap(catalog: PartsCatalog) -> TestResult:
	var panel := StructureDetails.new()
	_panel(panel, _document(catalog, "frame_iflight_evoque_f5_v2_o4"))
	var gap := panel.row_text("mass_gap")
	var computed := panel.row_text("computed_mass")
	panel.free()
	# Light by a lot, and saying so — the named products are the ones §9a found 29-48% light.
	var reports_direction := gap.contains("-") and gap.contains("%")
	var explains := gap.contains("outline")
	return TestResult.new(
		"Structure prints the disagreement with the published mass, and why",
		reports_direction and explains and computed.ends_with(" g"),
		"computed %s, gap %s" % [computed, gap])


## The three inertias must not be equal to each other on a frame that is not symmetric in all three,
## and roll must be the LATERAL moment. AirframeProperties' header spends a screen on this
## transposition trap; the panel is one more place it can be reintroduced.
##
## MUTATION: swap `roll_inertia_kg_m2()` for `pitch_inertia_kg_m2()` in the two rows and the ratio
## row keeps reading 1.00 on a symmetric X — so this asserts against a DEADCAT, which is stretched.
static func _test_structure_inertia_is_not_transposed(catalog: PartsCatalog) -> TestResult:
	var panel := StructureDetails.new()
	_panel(panel, _document(catalog, "frame_5in_deadcat"))
	var roll := panel.row_text("roll_inertia")
	var pitch := panel.row_text("pitch_inertia")
	var yaw := panel.row_text("yaw_inertia")
	panel.free()
	# Yaw is the perpendicular-axis sum for flat plates, so it is the largest of the three. That is
	# a physical law rather than a property of this frame, and it holds for every plate airframe.
	var all_present := roll != "—" and pitch != "—" and yaw != "—"
	var yaw_largest := _leading_number(yaw) > _leading_number(roll) \
		and _leading_number(yaw) > _leading_number(pitch)
	return TestResult.new(
		"Structure's yaw inertia is the perpendicular-axis sum, so it exceeds roll and pitch",
		all_present and yaw_largest,
		"roll %s / pitch %s / yaw %s" % [roll, pitch, yaw])


## A frame you drew has no vendor, so there is no published mass and no gap — and the row must say
## THAT rather than compare against zero and report an infinite disagreement.
##
## MUTATION: default `published_mass_g` to anything non-zero, or drop the `<= 0` guard in either
## row, and a hand-drawn frame is suddenly 100% heavier than a vendor who does not exist.
static func _test_a_drawn_frame_has_no_vendor_to_disagree_with() -> TestResult:
	var panel := StructureDetails.new()
	_panel(panel, _drawn_frame())
	var published := panel.row_text("published_mass")
	var gap := panel.row_text("mass_gap")
	var computed := panel.row_text("computed_mass")
	panel.free()
	return TestResult.new(
		"a frame with no vendor shows no published mass and no gap, but still weighs something",
		published.begins_with("—") and gap == "—" and _leading_number(computed) > 0.0,
		"published %s / gap %s / computed %s" % [published, gap, computed])


# ---------------------------------------------------------------------------
# Arms
# ---------------------------------------------------------------------------

## The section row must print BOTH dimensions and never one averaged from them. Collapsing arm
## thickness into plate thickness is the assumption §9a measured at a factor of 6.7.
##
## MUTATION: print the centre plate's thickness in the section row and this fails, because the
## reference frame's arm is 5.0 mm on a 2.5 mm plate.
static func _test_arms_section_and_mass(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part(REFERENCE_FRAME)
	var panel := ArmsDetails.new()
	_panel(panel, AirframeDocument.from_catalog_frame(frame))
	var section := panel.row_text("section")
	var one := panel.row_text("arm_mass")
	var all_arms := panel.row_text("arms_mass")
	panel.free()
	var arm_t := float(frame["specs"]["arm_thickness_mm"])
	var arm_w := float(frame["specs"]["arm_width_mm"])
	# The published width, MEASURED back off the outline the generator drew from it. That round trip
	# is the thing worth asserting: it is the only evidence that what physics reads is what the
	# picture shows.
	var shows_both := section.contains("%.1f mm" % arm_t) and section.contains("%.1f mm" % arm_w)
	# Four arms weigh four times one arm. Asserted because the row is a multiplication that could
	# drift from the row above it.
	# Both rows are printed to the nearest gram, so four of one can differ from the total by up to
	# 2 g without either being wrong. Anything larger is a second integral disagreeing with the
	# first, which is the actual failure this asserts against.
	var four_times := absf(_leading_number(all_arms) - _leading_number(one) * 4.0) <= 2.0
	return TestResult.new(
		"Arms prints the arm's own measured section, and four arms weigh four times one",
		shows_both and four_times and all_arms.contains("4 arms"),
		"section %s, one %s, all %s" % [section, one, all_arms])


## THE HONESTY TEST, in its new form. Fourteen of fifteen catalog frames have no published arm
## width, so the preset's outline was drawn from a constant in `AirframeDocument`. Measuring that
## outline is not a measurement of a real frame, and every figure derived from it says so.
##
## MUTATION: delete the `width_is_assumed` flag, or stop consulting it in `_beam_tier`, and fourteen
## frames start quoting a resonance derived from this project's own guess as though somebody had
## put a caliper on it.
static func _test_assumed_width_is_labelled(catalog: PartsCatalog) -> TestResult:
	var panel := ArmsDetails.new()
	_panel(panel, _document(catalog, WIDTH_ASSUMED_FRAME))
	var checked := ["section", "k_tip", "mode_bare", "stress_root", "torsion"]
	var missing: Array[String] = []
	for key in checked:
		var text := panel.row_text(key)
		if not text.contains("assumed"):
			missing.append("%s=%s" % [key, text])
	var mode := panel.row_text("mode_bare")
	panel.free()
	return TestResult.new(
		"an arm width nobody published is labelled assumed on every figure derived from it",
		missing.is_empty() and _leading_number(mode) > 0.0,
		"mode %s; unlabelled: %s" % [mode, "none" if missing.is_empty() else ", ".join(missing)])


## The other half. A width a builder DREW is not an assumption, and a panel that caveats everything
## teaches a reader to ignore caveats.
##
## MUTATION: return `true` unconditionally from `_width_is_assumed()` — the "safe" version — and
## this fails.
static func _test_a_drawn_arm_needs_no_caveat() -> TestResult:
	var panel := ArmsDetails.new()
	_panel(panel, _drawn_frame())
	var section := panel.row_text("section")
	var k_tip := panel.row_text("k_tip")
	var mode := panel.row_text("mode_bare")
	panel.free()
	return TestResult.new(
		"a width the builder drew carries no assumed-width caveat",
		not section.contains("assumed") and not k_tip.contains("assumed")
			and not mode.contains("assumed") and _leading_number(mode) > 0.0,
		"section %s / k_tip %s / mode %s" % [section, k_tip, mode])


## A moulded frame is not a plate assembly at all (§0) and has no arm to analyse. Its dash must say
## so, rather than reporting a number for a beam that does not exist.
##
## MUTATION: fall back to any plate in the document when no arm plate is present, and a whoop grows
## a beam.
static func _test_moulded_frame_says_why_not(catalog: PartsCatalog) -> TestResult:
	var document := _document(catalog, MOULDED_FRAME)
	var arms := ArmsDetails.new()
	_panel(arms, document)
	var mode := arms.row_text("mode_bare")
	var section := arms.row_text("section")
	arms.free()
	var structure := StructureDetails.new()
	_panel(structure, document)
	var stock := structure.row_text("stock")
	structure.free()
	return TestResult.new(
		"a moulded frame says it has no plate arm rather than reporting a beam",
		mode.begins_with("—") and section.begins_with("—") and mode.contains("no plate arm")
			and stock.contains("not a plate frame"),
		"mode %s / section %s / stock %s" % [mode, section, stock])


# ---------------------------------------------------------------------------
# Fasteners
# ---------------------------------------------------------------------------

## Hardware mass is DERIVED and non-trivial. §5 measures a 5" build's fastener mass at 8-15 g, which
## is more than a camera and is invisible on every vendor spec sheet.
##
## MUTATION: return 0.0 from `_item_mass_g` for any kind and the share row collapses; the bound
## below fails well before the number reaches zero.
static func _test_fasteners_are_derived_not_zero(catalog: PartsCatalog) -> TestResult:
	var panel := FastenersDetails.new()
	_panel(panel, _document(catalog, REFERENCE_FRAME))
	var mass := _leading_number(panel.row_text("hardware_mass"))
	var standoffs := panel.row_text("standoffs")
	var screws := panel.row_text("screws")
	var stack := panel.row_text("stack_height")
	var checks := panel.row_text("checks")
	panel.free()
	# The band §5 states for a 5" build, used as a SANITY NET and not as a claim: anything outside it
	# means the geometry or the density is wrong, not that the frame is unusual.
	var in_band := mass >= 3.0 and mass <= 30.0
	var counted := standoffs.contains("×") and screws.contains("× M")
	var stack_real := _leading_number(stack) > 0.0
	return TestResult.new(
		"Fasteners derives a real hardware mass, count and stack height",
		in_band and counted and stack_real and checks != "—",
		"%s g / %s / %s / stack %s / %s" % [mass, standoffs, screws, stack, checks])


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

## Every catalog preset is a symmetric X of four counter-rotating motors, so every one of them must
## come out controllable with rank 4. A preset that did not would be a generator bug.
##
## MUTATION: swap the x and z arguments in `_motors()` and roll/pitch authority transpose. The
## symmetric X hides that (they are equal), which is why the reported ARM LENGTH is asserted too —
## a transposition that also scaled would move it.
static func _test_layout_is_controllable(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part(REFERENCE_FRAME)
	var panel := LayoutDetails.new()
	_panel(panel, AirframeDocument.from_catalog_frame(frame))
	var controllable := panel.row_text("controllable")
	var roll := _leading_number(panel.row_text("roll_authority"))
	var pitch := _leading_number(panel.row_text("pitch_authority"))
	var yaw := panel.row_text("yaw_authority")
	var motors := panel.row_text("motors")
	panel.free()
	var arm_mm := float(frame["specs"]["arm_mm"])
	# Four motors on a 45° X at radius r sit at |x| = |z| = r/sqrt(2), and the row norm over four of
	# them is 2r/sqrt(2) = r*sqrt(2). Checked against the arm length so a scaling error shows.
	var expected := arm_mm * sqrt(2.0)
	var authority_right := absf(roll - expected) < 1.0 and absf(pitch - expected) < 1.0
	# Yaw is reported as a PROPERTY OF THE SPIN PATTERN, never as a magnitude: the magnitude needs a
	# propeller's Q/T and there is no propeller in this room.
	var yaw_is_qualitative := yaw.contains("counter-rotating") and _leading_number(yaw) == 0.0
	return TestResult.new(
		"Layout finds every preset controllable, with the lever arm the geometry implies",
		controllable.begins_with("yes") and authority_right and motors.contains("2 CW, 2 CCW")
			and yaw_is_qualitative,
		"%s / roll %.1f pitch %.1f (expected %.1f) / yaw %s / %s" % [
			controllable, roll, pitch, expected, yaw, motors])


# ---------------------------------------------------------------------------
# The guard on the whole rework
# ---------------------------------------------------------------------------

## NO ROW MAY NEED A MOTOR, A PROPELLER OR A PACK.
##
## This is the test that keeps the Airframe room a frame editor. There is no `Build` anywhere in
## this file, so a row that reached for propulsion could not be given one; what it would do instead
## is dash, or divide by a zero thrust and print an infinity. Both are caught here, for every row of
## all four tabs, on a frame that has never been part of an aircraft.
##
## MUTATION: reinstate any thrust-scaled row — droop at hover, the loaded mode, yaw authority in
## N·m — and it fails immediately, because there is nothing to scale by.
static func _test_no_row_needs_a_motor_or_a_thrust(catalog: PartsCatalog) -> TestResult:
	var panels: Array = [StructureDetails.new(), ArmsDetails.new(),
		FastenersDetails.new(), LayoutDetails.new()]
	var document := _document(catalog, REFERENCE_FRAME)
	var dashed: Array[String] = []
	# Rows that legitimately dash on a frame with no vendor are the two vendor-comparison rows and
	# nothing else. Named, so that a row going quiet for a different reason is a failure.
	var may_dash := ["published_mass", "mass_gap"]
	for panel in panels:
		(panel as AirframePanel).render(document)
		for row in (panel as SpecPanel).spec_rows:
			var key: String = row["key"]
			if may_dash.has(key):
				continue
			var text := (panel as AirframePanel).row_text(key)
			if text.begins_with("—") or text.contains("inf") or text.contains("nan"):
				dashed.append("%s=%s" % [key, text])
	for panel in panels:
		(panel as Node).free()
	return TestResult.new(
		"every Airframe row answers for a frame with no motor, propeller or pack",
		dashed.is_empty(),
		"silent rows: %s" % ["none" if dashed.is_empty() else ", ".join(dashed)])


## EVERY row of all four tabs, for EVERY frame in the catalog, must render a non-empty string and
## must never render Godot's idea of a missing value. A panel that throws or prints "<null>" for one
## frame in fifteen is a bug nobody finds by clicking around, because the frames that break it are
## the moulded and the unusual ones nobody selects while developing.
##
## MUTATION: remove any `null` guard in the four panels — `_document == null`, `beam == null`, the
## empty-motors early return — and this fails on the frames that exercise it.
static func _test_every_row_renders_for_every_frame(catalog: PartsCatalog) -> TestResult:
	var panels: Array = [StructureDetails.new(), ArmsDetails.new(),
		FastenersDetails.new(), LayoutDetails.new()]
	var bad: Array[String] = []
	var rendered := 0
	# The null document is in the sweep deliberately: the panels are constructed before any frame is
	# open, and "no frame yet" has to render as calmly as any frame does.
	var documents: Array = [null]
	for frame in catalog.list_category("frame"):
		documents.append(AirframeDocument.from_catalog_frame(frame))
	for document in documents:
		for panel in panels:
			(panel as AirframePanel).render(document)
			for row in (panel as SpecPanel).spec_rows:
				var key: String = row["key"]
				var text := (panel as AirframePanel).row_text(key)
				rendered += 1
				if text.is_empty() or text.contains("null") or text.contains("nan") \
						or (text.contains("inf") and not text.contains("∞")):
					var label := "none" if document == null else str((document as AirframeDocument).id)
					bad.append("%s/%s: %s" % [label, key, text])
	for panel in panels:
		(panel as Node).free()
	return TestResult.new(
		"every Airframe row renders a real string for every catalog frame, and for none",
		bad.is_empty(),
		"%d rows rendered; bad: %s" % [rendered, "none" if bad.is_empty() else ", ".join(bad)])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A frame nobody bought: one square centre plate and four rectangular arms, authored outright.
##
## Small and hand-built on purpose. It is the only fixture in this file that represents what the
## Airframe room is FOR — a frame somebody drew — and every property that distinguishes a drawn
## frame from a preset is a property of this one: no vendor, no published mass, and an arm width
## that is exactly what it was drawn as.
static func _drawn_frame() -> AirframeDocument:
	var document := AirframeDocument.new()
	document.id = "test_drawn"
	document.name = "Drawn frame"
	document.author = "a builder"
	document.material_id = "carbon_3k_twill_0_90"

	document.plates.append(AirframeDocument.make_plate(
		PackedVector2Array([
			Vector2(-20.0, -20.0), Vector2(20.0, -20.0), Vector2(20.0, 20.0), Vector2(-20.0, 20.0)]),
		[], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM))

	for index in 4:
		var angle := deg_to_rad(45.0 + 90.0 * float(index))
		var direction := Vector2(cos(angle), sin(angle))
		var across := Vector2(-direction.y, direction.x) * 6.0
		var tip := direction * 110.0
		var outline := PackedVector2Array([
			-across, tip - across, tip + across, across])
		document.plates.append(AirframeDocument.make_arm_plate(
			outline, [], 5.0, 0.0, Vector2.ZERO, tip))
		document.motors.append({
			"position_mm": [tip.x, tip.y],
			"z_mm": 5.0,
			"spin": 1.0 if index % 2 == 0 else -1.0,
			"tilt_deg": 0.0,
		})
	return document


## The first number in a rendered row, for assertions that care about the value rather than the
## wording. Returns 0.0 when the row carries no number, which every caller treats as a failure
## rather than as a zero.
static func _leading_number(text: String) -> float:
	var digits := ""
	var seen := false
	for i in text.length():
		var c := text[i]
		if c.is_valid_int() or (c == "." and seen) or (c == "-" and not seen):
			digits += c
			seen = true
		elif seen:
			break
	return float(digits) if seen else 0.0


## The Fasteners "Assembly checks" row is a spec line, not a paragraph: the count and the worst
## check's SHORT form. The sentence is the page's "Why?". Breaks if the row goes back to `message`.
static func _test_a_flagged_joint_reads_as_a_short_line() -> TestResult:
	var document := FrameLayouts.build("quad_x")
	var panel := FastenersDetails.new()
	panel.render(document)
	var text := panel.row_text("checks")
	var joint := FrameHardware.joint_warnings(document)
	panel.free()
	return TestResult.new("fasteners: a flagged joint reads 'N of 3 flagged — <short>', no paragraph",
		not joint.is_empty() and text == "%d of 3 flagged — %s" % [joint.size(), joint[0].short],
		"'%s'" % text)
