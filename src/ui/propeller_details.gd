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

## Emitted when the builder asks to open the Propulsion room on this propeller, with the catalog
## record it is showing. The panel opens nothing itself — see `_build_footer`.
signal design_blade_requested(prop: Dictionary)

## THE GUARD'S INSPECTOR ROW — P10f, and the row is on THIS panel rather than the Motor's for a
## geometric reason: a guard wraps the propeller disc. The CLEARANCE is read from
## `PropGuard.tip_clearance_mm` against the tip radius of the prop these rows describe, so the gap a
## builder is choosing between is a fact about the part on this panel. The ring itself is NOT derived
## from the prop: its inner wall is the spec's `outer_radius - wall` whatever prop it wraps (found in
## printed-room PR12; deriving it is a deferred Propulsion item). The motor only decides where it rides.
##
## **This is also the row P10a and P10b both ended by naming as missing.** `Build.guard_id` has
## been reachable from `Build.from_ids` and from nowhere else: the physics was proved, the ring was
## drawn, the BEMT closure was wired end to end, and no builder could fit a guard. The dropdown is
## what makes all of that reachable, and the project schema line beside it is what makes it
## survive a save.
##
## "Not fitted" is the first row and the default, on `ElectronicsPicker`'s own argument and for a
## stronger reason here: the reference build fits no guard, and its 496 g / 11.69:1 / 29.6% oracle
## is bit-identical only while that stays true.
signal guard_changed(guard_id: String)

## Emitted with the guard id alone: the annulus is a function of the guard's spec, not of the prop
## (printed-room PR14 removed a tip radius that changed nothing). The shell owns the file dialog for
## the same reason it owns the rooms.
signal guard_stl_requested(guard_id: String)

var _design_button: Button

var _catalog: PartsCatalog
var _guard_selector: OptionButton
## Selector index -> guard part id, "" first. An index into THIS and never into
## `catalog.list_category("guard")` — the two lists differ by the "Not fitted" row, and reading a
## part out of the catalog by a selector index is off by one for the whole of the list.
var _guard_ids: Array = [""]
var _guard_export: Button

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

## What the guard row's empty selection reads as. One constant rather than a literal, on
## ElectronicsPicker's own argument.
const NOT_FITTED := "Not fitted"

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


## The catalog is REQUIRED rather than defaulted to null, and that is deliberate. A null-catalog
## branch that quietly built the panel without its guard row would be the exact silent failure
## P10a and P10b each ended by reporting: physics that is proved and unreachable. If a caller has
## no catalog, the panel should fail to construct where the caller is, not on a screen weeks later
## with a dropdown missing.
func _init(p_catalog: PartsCatalog) -> void:
	_catalog = p_catalog
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


## The blade note, the way into the room, then PartDetails' own footer. Order matters: the note is a
## footnote to the rows above it, and putting it under the aircraft's stat block would orphan it
## from the numbers it explains.
func _build_footer(root: VBoxContainer) -> void:
	_blade_note = Label.new()
	_blade_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blade_note.custom_minimum_size = Vector2(280, 0)
	_blade_note.theme_type_variation = &"MutedLabel"
	root.add_child(_blade_note)

	# THE DOOR TO THE PROPULSION ROOM, and it is on this panel for the reason `room_menu.gd`'s own
	# header states: a workspace belongs to the system it works on, reached from that system's
	# inspector, rather than from a list of destinations. The room edits the planform these rows
	# describe, and the caveat two lines up — "blade chord assumed" — is exactly what going in
	# there is for, so the button sits directly under the sentence that motivates it.
	#
	# The room is NOT this panel's to open. The button says what happened and the shell decides
	# what to do about it, on the same rule every other control in this UI follows.
	_design_button = Button.new()
	_design_button.text = "Design this blade…"
	_design_button.tooltip_text = ("Open the planform editor: the blade's chord distribution, its "
		+ "section at any radius, and the mount stack it turns on.")
	_design_button.pressed.connect(func() -> void: design_blade_requested.emit(_rendered_part))
	root.add_child(_design_button)

	_build_guard_row(root)

	super(root)


## The guard row — see `guard_changed` for why it is on this panel and what it unblocks.
func _build_guard_row(root: VBoxContainer) -> void:
	root.add_child(HSeparator.new())

	var title := Label.new()
	title.text = "Prop guard"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	_guard_selector = OptionButton.new()
	_guard_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Clipped for the reason ElectronicsPicker's selectors are: "5\" cinewhoop shroud (ABS, 1.5 mm
	# gap)" would otherwise set this column's width from its longest string.
	_guard_selector.clip_text = true
	_guard_selector.custom_minimum_size = Vector2(280, 0)
	_guard_selector.add_item(NOT_FITTED)
	_guard_ids = [""]
	for guard in _catalog.list_category("guard"):
		_guard_selector.add_item("%s   %s g" % [
			PartPicker.display_name(guard), PartPicker._format_mass(guard)])
		_guard_ids.append(str(guard["part_id"]))
	_guard_selector.select(0)
	_guard_selector.item_selected.connect(_on_guard_selected)
	root.add_child(_guard_selector)

	_guard_export = Button.new()
	_guard_export.text = "Export guard (STL)…"
	_guard_export.tooltip_text = ("The ring as a printable solid, in millimetres — the same "
		+ "annulus the aircraft is drawn with.")
	# DISABLED WITH NOTHING FITTED, rather than emitting a request the shell would have to refuse.
	# A button that does nothing when pressed is indistinguishable from a broken one.
	_guard_export.disabled = true
	_guard_export.pressed.connect(func() -> void:
		guard_stl_requested.emit(guard_id()))
	root.add_child(_guard_export)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	note.text = ("A bumper claims mass, inertia and clearance. A duct claims those and the tip-loss "
		+ "suppression as well — which on this model saves current rather than adding thrust. "
		+ "Either one bites into roll inertia harder than the motor it rides on.")
	root.add_child(note)


func _on_guard_selected(index: int) -> void:
	_guard_export.disabled = _guard_ids[index] == ""
	guard_changed.emit(String(_guard_ids[index]))


## The fitted guard, "" for none. What LabScreen reads to assemble a Build and what the project
## file records.
func guard_id() -> String:
	if _guard_selector == null:
		return ""
	return String(_guard_ids[_guard_selector.selected])


## Fits a guard by id, as opening a saved drone does. Returns whether the id was one this catalog
## knows — a guard that has left the catalog leaves the row where it was and is reported, on
## `LabScreen.apply_selection`'s own rule that nothing is silently substituted.
func select_guard(p_guard_id: String) -> bool:
	if _guard_selector == null:
		return p_guard_id == ""
	var index := _guard_ids.find(p_guard_id)
	if index < 0:
		return false
	_guard_selector.select(index)
	_guard_export.disabled = p_guard_id == ""
	return true


## The tip radius of the propeller these rows describe, read through the SAME document the mesh,
## the mass integral and the BEMT closure read. Not `diameter_inches / 2` computed here: that
## would be the second definition of a prop's radius, and the tip clearance hangs off it.


func _tip_radius_m() -> float:
	var doc := document_for(_rendered_part)
	if doc == null:
		return 0.0
	return doc.diameter_mm * 0.0005


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
			var doc := document_for(prop)
			if doc == null or doc.diameter_mm <= 0.0:
				return "—"
			# The blade angle at the tip, read from the SAME beta(r) the mesh draws and the BEMT
			# integral will read (propulsion.md §3.2) — one definition, three readers.
			return "%.1f°" % rad_to_deg(doc.beta_rad(1.0))
	return super(prop, key)
