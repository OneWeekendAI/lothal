class_name ElectronicsDetails
extends PartDetails
## What the payload costs — the four fitted components, the wiring remainder, and the total.
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
## The wiring row is here for a reason beyond completeness: it is 14 g of the 55, it is flat, and
## at the small end it is the dominant term — more than the whole of a real whoop's harness. A
## builder looking at why a whoop reports 67 g against a real 20–25 g has to be able to see that.
## See Build.wiring_mass_g() for why it is flat and what would change it.

const SPEC_ROWS := [
	{"key": "camera", "label": "Camera"},
	{"key": "vtx", "label": "Video TX"},
	{"key": "antenna", "label": "Antenna"},
	{"key": "receiver", "label": "Receiver"},
	{"key": "wiring", "label": "Wiring, solder, tape"},
	{"key": "total", "label": "Electronics total"},
]

## What an empty bay reads as. Not "0 g", which is a component that weighs nothing, and not the
## em dash PartDetails uses for an unfilled field, which is a value nobody entered — neither of
## those is "you did not fit one", and the difference is the whole point of the rail next door.
const NOT_FITTED_TEXT := "not fitted"

## The build being reported. This panel's rows are all about the aircraft rather than about one
## part, so unlike its siblings it reads nothing at all out of the `part` argument.
var _build: Build = null


func _init() -> void:
	super(SPEC_ROWS)


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


func _read(_part: Dictionary, key: String) -> String:
	if _build == null:
		return "—"

	match key:
		"wiring":
			return "%.1f g" % Build.wiring_mass_g()
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
