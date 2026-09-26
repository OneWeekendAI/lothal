class_name ElectronicsDetails
extends PartDetails
## What the video payload costs — the three fitted components, the wiring remainder, and the total.
##
## THE RECEIVER LEFT THIS PANEL IN C6 and is reported by `LinkDetails` under Control, where it is
## now also chosen. It was here because `ElectronicsPicker` emitted all four bays as one payload
## and the panel followed the rail; C3 split the rail and this row followed it back. Video's
## `decided_by` never named the receiver, so no ring arithmetic moved with it.
##
## The other details panels each describe ONE part; this one describes a budget, and that is the
## only useful thing to say about these four. A camera has no physics-bearing spec: it has a mass
## and a box, both of which matter only as a contribution to the whole. So where FcDetails spends
## its rows turning a gyro's noise floor into a number at the motors, this panel spends its rows
## on the arithmetic that the flat 55 g lump used to hide.
##
## THE TOTAL IS THE MODEL'S, not a sum done here. Build.electronics_mass_g() is the answer, and a
## panel that added the rows up itself would be a second answer to a question the budget must have
## exactly one of — which is the same argument Build's own CARVED_SHARES table makes one level
## down. The rows above it are the terms; if they do not visibly add to it, that is a real
## disagreement and it should be on screen rather than papered over.
##
## The wiring row used to be 14 g of a flat 55 — the budget's remainder, the same on every
## aircraft, and at the small end the dominant term. PW2 replaced it with a real harness that is
## weighed off the build's own gauges and lengths, so this row now MOVES with the aircraft. The row
## itself is unchanged and so is its reason for being here: a builder looking at why a whoop
## reports what it reports has to be able to see the harness term. See `Harness`.

const SPEC_ROWS := [
	{"key": "camera", "label": "Camera"},
	{"key": "vtx", "label": "Video TX"},
	{"key": "vtx_output", "label": "— output"},
	{"key": "antenna", "label": "Antenna"},
	{"key": "antenna_type", "label": "— type"},
	{"key": "wiring", "label": "Wiring, solder, tape"},
	{"key": "total", "label": "Electronics total"},
]

## The rows the VTX & antenna page keeps (`set_dock_sheet("vtx")`): its own two parts and what the
## catalogue says of each. The camera is the Camera page's; the wiring and the total are the
## aircraft's, not this item's.
const VTX_SHEET_ROWS := ["vtx", "vtx_output", "antenna", "antenna_type"]

## What an empty bay reads as. Not "0 g", which is a component that weighs nothing, and not the
## em dash PartDetails uses for an unfilled field, which is a value nobody entered — neither of
## those is "you did not fit one", and the difference is the whole point of the rail next door.
const NOT_FITTED_TEXT := "not fitted"

## The build being reported. This panel's rows are all about the aircraft rather than about one
## part, so unlike its siblings it reads nothing at all out of the `part` argument.
var _build: Build = null


## "" for the whole sheet, or "vtx" for the VTX & antenna page's cut of it.
var _dock_sheet := ""


func _init() -> void:
	super(SPEC_ROWS)


## Cuts the sheet to one Lab dock page's rows (lab dock design §3: each page shows only its own
## item). "" puts every row back.
func set_dock_sheet(sheet: String) -> void:
	_dock_sheet = sheet
	for i in SPEC_ROWS.size():
		var shown := sheet == "" or (sheet == "vtx" and VTX_SHEET_ROWS.has(SPEC_ROWS[i]["key"]))
		for label in _row_labels[i]:
			(label as Control).visible = shown
	if sheet == "vtx":
		_title.text = "VTX & ANTENNA"


## The keys of the rows showing, in order, for tests.
func shown_keys() -> Array:
	var out: Array = []
	for i in SPEC_ROWS.size():
		if (_row_labels[i][0] as Control).visible:
			out.append(SPEC_ROWS[i]["key"])
	return out


## Renders the payload of one build. The odd shape — no part argument, where every other panel
## takes one — is honest about what this panel is: there is no "selected electronics part", there
## is a build with four bays. The synthetic part below exists only to give PartDetails.render()
## the title it goes looking for.
func render_components(build: Build) -> void:
	_build = build
	# PartDetails.render() unchanged, not a super() call: this method does not override anything,
	# so `super(...)` would go looking for a render_components() on the base that is not there.
	# The stash above happens FIRST, because render() is what drives the _read() below.
	render({"name": "Electronics"}, build)
	if _dock_sheet == "vtx":
		_title.text = "VTX & ANTENNA"


func _read(_part: Dictionary, key: String) -> String:
	if _build == null:
		return "—"

	match key:
		"vtx_output":
			# Catalogue metadata (vtxs.json): no radio model reads it.
			return _catalog_field("vtx", ["power_class", "band"])
		"antenna_type":
			return _catalog_field("antenna", ["polarisation", "connector", "gain_class"])
		"wiring":
			return "%.1f g" % _build.harness_mass_g()
		"total":
			return "%.1f g" % _build.electronics_mass_g()

	# Everything else is one of the four bays, named by its category.
	if not _build.components.has(key):
		return NOT_FITTED_TEXT
	var component: Dictionary = _build.components[key]
	# The part's NAME as well as its mass. A column of four masses tells a builder what the
	# payload weighs but not what it is, and "3.0 g" against "8.0 g" is only actionable once you
	# can see that the light one is the nano.
	return "%s   %.1f g" % [
		component.get("name", "?"), float(component.get("mass_g", 0.0))]


## A fitted part's catalogue fields joined with " · ", or not fitted. Copied from the catalogue as
## published, never derived.
func _catalog_field(category: String, keys: Array) -> String:
	if not _build.components.has(category):
		return NOT_FITTED_TEXT
	var catalog: Dictionary = (_build.components[category] as Dictionary).get("catalog", {})
	var parts: Array[String] = []
	for key in keys:
		if str(catalog.get(key, "")) != "":
			parts.append(str(catalog[key]))
	return " · ".join(parts) if not parts.is_empty() else "—"
