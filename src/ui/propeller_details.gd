class_name PropellerDetails
extends PartDetails
## The propeller panel. All the machinery is PartDetails' — read its header.
##
## Diameter is listed first because thrust goes as D^4 and diameter therefore dominates every
## other number here (physics.md §4). Pitch is shown both in inches, as the catalog and the
## real world quote it, and as the blade angle it implies at the tip — which is the same figure
## PropellerMesh draws, so the twist on screen and the number in the panel are one thing.
##
## ## The blade-geometry block, and why it is on this panel rather than in a room
##
## propulsion.md §9 sequences the Propulsion room as P10, last of ten, behind the whole BEMT chain.
## P0–P2 are built and produce three things a builder can act on today — what the blades weigh, how
## that compares to the vendor's figure, and the radius of gyration that will set spin-up — and
## until those reach a screen they are a test log. So they land here, in the inspector that already
## owns "everything known about this propeller", rather than waiting for a destination.
##
## Two rules govern the block, both from §3.1, and both are the reason it is worth the rows:
##
##   - **Every figure derived from a generated planform says so.** Nobody publishes a chord
##     distribution — not HQProp, not Gemfan, not T-Motor — so a preset's planform is generated and
##     carries `chord_is_assumed`. A number that looks measured and is not is the one failure this
##     whole method exists to prevent (airframe.md §9b), and the caveat travels ON the number rather
##     than sitting in a legend.
##   - **Inertia is built from the PUBLISHED mass, never the computed one.** §3.1: "the spin-up
##     number that matters is built from the published mass times the shape-only k²". The computed
##     blade mass runs 0.17–1.18× published because the hub is absent from every integral; using it
##     for inertia would stack that error on top of the shape error and look entirely plausible
##     doing it. `test_propulsion_panel.gd` fails if this panel takes that shortcut.
##
## What is deliberately NOT here: thrust, torque, spin-up τ and transmissibility. All four need
## P4–P8, none of them exist, and a row that renders "—" for them would invite someone to fill it in
## with the coefficients this document is removing.

const SPEC_ROWS := [
	{"key": "diameter_class", "label": "Diameter class"},
	{"key": "blade_count", "label": "Blades"},
	{"key": "intended_use", "label": "Intended for"},
	{"key": "material", "label": "Material"},
	{"key": "mass_g", "label": "Prop mass (each)"},
	{"key": "diameter_inches", "label": "Diameter"},
	{"key": "pitch_inches", "label": "Pitch"},
	{"key": "tip_angle", "label": "Blade angle at tip"},
	# ---- THE BLADE AS GEOMETRY (propulsion.md §3.1, §3.3) ----
	{"key": "planform", "label": "Planform"},
	{"key": "blade_mass", "label": "Blade mass"},
	{"key": "mass_gap", "label": "vs published"},
	{"key": "k2", "label": "Gyration k²"},
	{"key": "blade_inertia", "label": "Blade inertia"},
]

## The blade rows, so the caveat logic and the tests share one list rather than two that drift.
const BLADE_KEYS := ["planform", "blade_mass", "mass_gap", "k2", "blade_inertia"]

## The material table, loaded once for the whole app. Small, immutable, and read on every repaint;
## reloading it per row would be pure waste. Same arrangement as `AirframePanel._materials_shared`.
static var _materials_shared: FrameMaterials

## The last part turned into a document, keyed by part_id. Five rows ask for the same document on
## every repaint and the planform is forty stations of trigonometry; generating it five times per
## frame would be five identical answers at five times the cost.
static var _doc_cache_id := ""
static var _doc_cache: PropellerDocument

## The wrapping footnote under the blade rows. See `blade_note_text`.
var _blade_note: Label


func _init() -> void:
	super(SPEC_ROWS)


static func materials() -> FrameMaterials:
	if _materials_shared == null:
		_materials_shared = FrameMaterials.load_default()
	return _materials_shared


## The PropellerDocument for a catalog part. The migration §3.1 specifies, cached by part_id.
static func document_for(prop: Dictionary) -> PropellerDocument:
	var part_id := str(prop.get("part_id", ""))
	if part_id != "" and part_id == _doc_cache_id and _doc_cache != null:
		return _doc_cache
	var doc := PropellerDocument.from_catalog_prop(prop)
	_doc_cache_id = part_id
	_doc_cache = doc
	return doc


## A blade row's text for an arbitrary document — the ONE place these five rows are formatted.
##
## Static and document-taking rather than a `_read` branch, because a blade a builder DREW has no
## catalog dictionary to be read out of, and the authored case is exactly the case the caveat logic
## exists to distinguish. Both paths land here, so what a test asserts is what a preset renders.
static func blade_row_text(key: String, doc: PropellerDocument, mats: FrameMaterials) -> String:
	if doc == null or doc.diameter_mm <= 0.0:
		return "—"

	match key:
		"planform":
			# The station count says how finely the shape is resolved; the peak says WHERE the area
			# sits, which is the only property of the shape that k² depends on. Quoting k² without
			# it would make the "below the band" verdict below unattributable to anything.
			var stations := doc.chord_points().size()
			if stations < 2:
				return "—"
			var origin := "generated" if doc.chord_is_assumed else "drawn"
			return "%s · %.2f R" % [origin, BladeGeometry.peak_chord_station(doc)]

		"blade_mass":
			var mass := BladeGeometry.blade_mass_g(doc, mats)
			if mass <= 0.0:
				return "—"
			# "blades only" is not a hedge, it is the diagnosis of the gap on the next row: the hub
			# is real mass and is absent from every integral in BladeGeometry (§3.1).
			return _with_caveat("%.2f g" % mass, doc)

		"mass_gap":
			# A blade somebody drew has no vendor to disagree with. That is not a missing value, and
			# rendering it as a gap against zero would report −100% for a perfectly good planform.
			if doc.published_mass_g <= 0.0:
				return "— (no vendor figure — this blade is yours)"
			var computed := BladeGeometry.blade_mass_g(doc, mats)
			if computed <= 0.0:
				return "—"
			var delta := (computed - doc.published_mass_g) / doc.published_mass_g * 100.0
			# §9a's precedent: the disagreement is REPORTED with its diagnosis attached, and nothing
			# is tuned to close it. P1 measured the whole band at 0.17–1.18× and found the shape of
			# it — the hub is the largest share of a small prop, which is why the whoops are worst.
			return "%+.0f%%" % delta

		"k2":
			var k2 := BladeGeometry.radius_of_gyration_sq(doc)
			if k2 <= 0.0:
				return "—"
			# The band is the error bar (§3.3, published by P2), so the value is never quoted alone.
			return _with_caveat("%.3f" % k2, doc)

		"blade_inertia":
			# m_published · k² · R². See this file's header: NOT the computed-mass form, which would
			# carry the hub gap into the one number spin-up is built from.
			if doc.published_mass_g <= 0.0:
				return "— (no vendor mass)"
			var j := BladeGeometry.blade_inertia_from_published_kg_m2(doc)
			if j <= 0.0:
				return "—"
			return _with_caveat("%.1f g·cm²" % (j * 1.0e7), doc)

	return "—"


## The honesty tier, folded onto the number rather than kept in a legend — §8's requirement and
## arms_details.gd's `_beam_tier` pattern.
##
## A GENERATED planform is characteristic, not engineering-grade, and the distinction is earned: the
## generator's arch peaks at ≈0.46 R and lands k² ≈ 0.278, outside the band §3.3 calls plausible, so
## a figure built on it is wrong by a factor nobody can bound. A planform the builder drew has
## exactly the chord they drew and needs no caveat at all.
##
## The marker in the cell is a bare "(assumed)" rather than the full "characteristic; blade chord
## assumed" the Airframe tabs use, and the reason is measured rather than stylistic: the long form
## on five rows pushed this inspector past the right edge of the window at 1600 AND 1920 wide, with
## every value — including the eight that were already there — off screen. SpecPanel's horizontal
## scroll is the escape hatch, not the plan. So the cell keeps the marker and `blade_note_text`
## carries the sentence, in the wrapping note directly under the rows, where §8's tier and §3.1's
## diagnosis are still attached to the numbers rather than filed in a legend elsewhere.
static func _with_caveat(text: String, doc: PropellerDocument) -> String:
	if not doc.chord_is_assumed:
		return text
	return "%s  (assumed)" % text


## The prose the grid cells cannot hold: the honesty tier, the band k² is being read against, and
## the diagnosis of the mass gap. Directly under the blade rows, so it reads as their footnote.
##
## This is NOT a legend. §8 requires the tier to travel with the number, and it does — the cell says
## "(assumed)" and this says what assumed costs. What would breach the rule is a caveat parked on
## another screen, which is exactly what a Propulsion room would have become if these rows waited
## for P10.
static func blade_note_text(doc: PropellerDocument, mats: FrameMaterials) -> String:
	if doc == null or doc.diameter_mm <= 0.0:
		return ""
	var lines: Array[String] = []

	var k2 := BladeGeometry.radius_of_gyration_sq(doc)
	if k2 > 0.0:
		var band := "%.3f–%.3f" % [BladeGeometry.PLAUSIBLE_K2_MIN, BladeGeometry.PLAUSIBLE_K2_MAX]
		if k2 < BladeGeometry.PLAUSIBLE_K2_MIN:
			# §3.3's finding, stated where a builder meets it: the generator's arch peaks inboard of
			# any real FPV planform, so spin-up built on it is low by that factor.
			lines.append(("k² %.3f is below the %s band real planforms fall in — this shape peaks "
				+ "at %.2f R, too far inboard, so spin-up from it reads low.")
				% [k2, band, BladeGeometry.peak_chord_station(doc)])
		elif k2 > BladeGeometry.PLAUSIBLE_K2_MAX:
			lines.append("k² %.3f is above the %s band real planforms fall in." % [k2, band])
		else:
			lines.append("k² %.3f is inside the %s band real planforms fall in." % [k2, band])

	if doc.published_mass_g > 0.0:
		var computed := BladeGeometry.blade_mass_g(doc, mats)
		if computed > 0.0:
			var delta := (computed - doc.published_mass_g) / doc.published_mass_g * 100.0
			# §9a's precedent: the disagreement is reported WITH its diagnosis, and nothing is tuned
			# to close it. P1 measured the whole catalog at 0.17–1.18× and found the shape of it.
			if delta < -10.0:
				lines.append(("Mass is %+.0f%% vs the vendor's %.1f g: the hub is not modelled, and "
					+ "it is the largest share of a small prop.") % [delta, doc.published_mass_g])
			elif delta > 10.0:
				lines.append(("Mass is %+.0f%% vs the vendor's %.1f g: the modelled planform is "
					+ "fatter than the real blade.") % [delta, doc.published_mass_g])
	else:
		lines.append("No vendor mass, so nothing checks the geometry.")

	if doc.chord_is_assumed:
		# The sentence the "(assumed)" markers point at. Nobody publishes a chord distribution, so a
		# preset's planform is generated — §3.1's wall, said in the builder's words.
		lines.append(("(assumed) = generated chord — no vendor publishes one. Ranking only."))

	return " ".join(lines)


## The blade note, then PartDetails' own footer. Order matters: the note is a footnote to the rows
## above it, and putting it under the aircraft's stat block would orphan it from the numbers it
## explains.
func _build_footer(root: VBoxContainer) -> void:
	_blade_note = Label.new()
	_blade_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blade_note.custom_minimum_size = Vector2(280, 0)
	_blade_note.theme_type_variation = &"MutedLabel"
	root.add_child(_blade_note)
	super(root)


func render(part: Dictionary, build: Build) -> void:
	super(part, build)
	_blade_note.text = blade_note_text(document_for(part), materials())


func _read(prop: Dictionary, key: String) -> String:
	var specs: Dictionary = prop.get("specs", {})

	if BLADE_KEYS.has(key):
		return blade_row_text(key, document_for(prop), materials())

	match key:
		"mass_g":
			return "%.1f g" % float(prop.get("mass_g", 0.0))
		"diameter_inches":
			return "%.1f\"" % float(specs.get("diameter_inches", 0.0))
		"pitch_inches":
			return "%.1f\"" % float(specs.get("pitch_inches", 0.0))
		"tip_angle":
			var radius_m: float = float(specs.get("diameter_inches", 0.0)) * PropellerMesh.INCH_M * 0.5
			if radius_m <= 0.0:
				return "—"
			var pitch_m: float = float(specs.get("pitch_inches", 0.0)) * PropellerMesh.INCH_M
			return "%.1f°" % rad_to_deg(PropellerMesh.twist_angle_rad(pitch_m, radius_m))
	return super(prop, key)
