class_name AirframePanel
extends SpecPanel
## The shared base of the four Airframe inspector tabs — Structure, Arms, Fasteners, Layout.
##
## ## The subject here is a FRAME, and nothing else
##
## This used to descend from `PartDetails` and render against a `Build`. That was wrong in a way
## that showed on screen: the panels carried the aircraft's five derived stats — all-up weight,
## thrust-to-weight, hover throttle, flight time, top speed — plus the build warnings and a note
## naming the fitted motor, propeller, pack, ESC and flight controller. A builder who opened
## Airframe to draw a frame was shown the performance of a freestyle quad they had not designed.
##
## airframe.md's subject is the frame ALONE. There is no motor, no propeller and no pack in this
## room, and every number below is a property of the geometry: mass and inertia are integrals over
## the plates, stiffness and stress are integrals along the arms, the mixer is the motor positions.
## The rest of the aircraft is a different room's problem, and a frame you draw here will still be
## the same frame whatever gets bolted to it later.
##
## Concretely, that means two things this class enforces by construction:
##
##   - **No `Build` is reachable from here.** Not stored, not passed, not imported. A row that
##     wanted one could not be written without changing this file, which is the point.
##   - **No row may need a tip mass or a thrust figure.** Both are properties of the propulsion
##     you have not chosen, so tip-loaded resonance and deflection-under-thrust are NOT shown here.
##     What replaces them is load-independent and just as diagnostic: tip stiffness in N/m, the bare
##     first mode, stress per newton, twist per newton-metre. Multiply by a load when you have one.
##
## ## One document, four tabs
##
## §1 names four things the Airframe system contains — the frame, the arms, the bolted joint, the
## soft mounts — and each tab answers one of them. All four read the SAME two objects: the
## `AirframeDocument` being edited, and the `AirframeProperties` computed off it. Building that pair
## once, here, is what stops four panels from each generating their own and drifting apart: the mass
## on Structure and the arm mass on Arms are summed from one set of plates, or they are two answers
## to one question.

## The material table, loaded once for every Airframe tab in the app. Small, immutable, and read on
## every repaint of four panels; reloading it per repaint would be pure waste.
static var _materials_shared: FrameMaterials

## The frame being inspected. Null before the first render, which is a real state — the panels are
## constructed before any frame is open — so every reader must tolerate it.
var _document: AirframeDocument
var _props: AirframeProperties

var _footer_note: Label
var _warnings: WarningList


func _init(p_spec_rows: Array) -> void:
	super(p_spec_rows)
	if _materials_shared == null:
		_materials_shared = FrameMaterials.load_default()


## The shared material table. A function rather than the bare static so a test can reach it through
## the same door the panels use.
static func materials() -> FrameMaterials:
	if _materials_shared == null:
		_materials_shared = FrameMaterials.load_default()
	return _materials_shared


## Below the rows: what this frame is, and what is wrong with it.
##
## The warning list is the one thing kept from the old build-stats footer, because the WARNINGS are
## about the frame and always were — an arm whose centreline leaves its own plate, a screw too short
## to bite, a layout that cannot be mixed. `FrameWarnings` derives them from the document, so they
## survive the removal of the build that used to supply them.
func _build_footer(root: VBoxContainer) -> void:
	root.add_child(HSeparator.new())

	_warnings = WarningList.new(280)
	root.add_child(_warnings)

	_footer_note = Label.new()
	_footer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_note.custom_minimum_size = Vector2(280, 0)
	_footer_note.theme_type_variation = &"MutedLabel"
	root.add_child(_footer_note)


## Paints the tab for one frame. A null document is a real state — no frame open yet — and every row
## falls through to its own missing-data path rather than the panel inventing a frame to show.
func render(document: AirframeDocument) -> void:
	_document = document
	_props = null
	if document != null:
		_props = AirframeProperties.compute(document, materials())

	render_rows(document.name if document != null else "—")

	if document == null:
		_warnings.show_warnings([])
		_footer_note.text = "No frame open."
		return

	_warnings.show_warnings(FrameWarnings.of(document, _props))
	var record := materials().get_material(document.material_id)
	var material_name := str(record.get("name", document.material_id)) if not record.is_empty() \
		else document.material_id
	_footer_note.text = "%s · %d plates · %s%s" % [
		document.name if document.name != "" else "Untitled frame",
		document.plates.size(),
		material_name,
		"" if document.author == "" else " · %s" % document.author]


# ---------------------------------------------------------------------------
# The arm, as the four tabs need it
# ---------------------------------------------------------------------------

## Every plate the document calls an arm, in document order.
func arm_plates() -> Array:
	if _document == null:
		return []
	var out: Array = []
	for plate in _document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			out.append(plate)
	return out


## The first arm as a beam, measured off its own outline, or null when the document has no arm that
## can be measured.
##
## MEASURED, NOT LOOKED UP. This is the change that makes the editor possible: the old version read
## `arm_width_mm` out of the catalog, a field present on one frame in fifteen because no vendor
## publishes it (§9a), so fourteen catalog frames and EVERY frame a builder drew showed dashes here.
## `ArmProfile` takes the width from the polygon, so an arm you drew has a width because you drew
## one, and the same door serves a preset and a sketch.
##
## Tip mass is deliberately absent from the signature. §4.3's loaded mode is a real and important
## number, and it belongs to the room that knows what motor is fitted.
func arm_beam() -> ArmBeam:
	var plates := arm_plates()
	if plates.is_empty() or _document == null:
		return null
	var plate: Dictionary = plates[0]
	if not plate.has("root_point") or not plate.has("tip_point"):
		return null
	var root := AirframeDocument.point_of(plate["root_point"])
	var tip := AirframeDocument.point_of(plate["tip_point"])
	var outline: PackedFloat64Array = plate.get("outline", PackedFloat64Array())
	return ArmProfile.beam_flat(
		outline,
		root.x, root.y, tip.x, tip.y,
		AirframeDocument.plate_thickness_mm(plate),
		_document.plate_material_id(plate),
		materials())


## Why a frame has no analysable arm, in the builder's terms.
##
## The two reasons are completely different and flattening them to one dash loses the more
## interesting one: a moulded whoop HAS no plate arm and never will (§0), while a plate frame whose
## arm centreline wanders off its own outline is a drawing mistake somebody can fix in ten seconds.
func no_beam_reason() -> String:
	if arm_plates().is_empty():
		return "— (no plate arm)"
	return "— (the arm's centreline leaves its plate)"


# ---------------------------------------------------------------------------
# Formatting shared by the four
# ---------------------------------------------------------------------------

## A figure with its honesty tier attached, for a row whose value may not be claimed flatly.
## §8 requires the tier to travel WITH the number rather than sitting in a legend somewhere else,
## and a row is the smallest place both can be said at once.
static func with_tier(text: String, tier: String) -> String:
	return "%s  (%s)" % [text, tier]


## Millimetres from metres, one decimal.
static func mm(metres: float) -> String:
	return "%.1f mm" % (metres * 1000.0)


## Grams from kilograms, no decimals — a scale a builder owns reads to about a gram.
static func grams(kilograms: float) -> String:
	return "%.0f g" % (kilograms * 1000.0)
