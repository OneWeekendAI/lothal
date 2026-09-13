class_name LinkDetails
extends PartDetails
## What the aircraft's connection to the outside costs — control-room design §5, slice C6.
## `ElectronicsDetails`' Control-side sibling, and it replaces the `LinkStub` C3 stood up to keep
## the new rail from reporting a wiring fault before its panel existed.
##
## Three bays: the receiver, where the pilot's intent arrives; the GPS, which talks to the flight
## controller; and the buzzer, which talks to the person walking towards the aircraft. Design §1's
## membership rule is what puts these three together — everything intent passes through, and
## everything that talks back.
##
## THE TOTAL IS THE MODEL'S, not a sum done here, and the argument is `ElectronicsDetails`' own one
## level down: a panel that added its rows up would be a second answer to a question the build must
## have exactly one of. If the rows do not visibly add to the total, that is a real disagreement
## and it belongs on screen rather than papered over.
##
## TWO ROWS ARE SUB-ROWS OF THE BAY ABOVE THEM, and both exist because their field is the reason
## the component is modelled at all rather than left as a number added to the harness remainder:
##
##   — mast height   a masted GPS puts several grams ABOVE THE TOP PLATE on a stalk, which moves
##                   the centre of mass vertically more than anything else fitted. It is the one
##                   bay whose height is read from the part. Editable, because it is a builder's
##                   choice and design §9 says the field IS the answer — there is nothing to
##                   sharpen it with.
##   — own power     whether the buzzer has its own cell, which is the difference between finding
##                   the aircraft in long grass and not. `ControlPlausibility` turns it into a
##                   warning; this row is where a builder sees it before they buy.

const SPEC_ROWS := [
	{"key": "receiver", "label": "Receiver"},
	{"key": "gps", "label": "GPS"},
	{"key": "mast", "label": "— mast height"},
	{"key": "buzzer", "label": "Buzzer"},
	{"key": "own_power", "label": "— own power"},
	{"key": "total", "label": "Link total"},
]

## What an empty bay reads as. Not "0 g", which is a component that weighs nothing, and not the em
## dash PartDetails uses for an unfilled field, which is a value nobody entered — neither of those
## is "you did not fit one", and that distinction is the entire reason the rail next door exists.
## Spelled the same way `ElectronicsDetails` spells it, deliberately: two panels describing bays
## must not describe an empty one in two different words.
const NOT_FITTED_TEXT := "not fitted"

## The categories this panel reports, in the order the mass model weighs them.
const BAYS := ["receiver", "gps", "buzzer"]

var _build: Build = null


func _init() -> void:
	super(SPEC_ROWS)


## Renders the link payload of one build. Same odd shape as `ElectronicsDetails.render_components`
## and for the same honest reason: there is no "selected link part", there is a build with three
## bays. The synthetic part exists only to give `PartDetails.render()` the title it looks for.
func render_components(build: Build) -> void:
	_build = build
	render({"name": "Link"}, build)


func _read(_part: Dictionary, key: String) -> String:
	if _build == null:
		return "—"

	match key:
		"total":
			return "%.1f g" % _link_total_g()
		"mast":
			return _mast_row()
		"own_power":
			return _own_power_row()

	if not _build.components.has(key):
		return NOT_FITTED_TEXT
	var component: Dictionary = _build.components[key]
	# The name as well as the mass, on `ElectronicsDetails`' argument: a column of masses says what
	# the payload weighs and not what it is, and the useful comparison is between the nano and the
	# diversity receiver rather than between 1 g and 5 g.
	return "%s   %.1f g" % [
		component.get("name", "?"), float(component.get("mass_g", 0.0))]


## The three bays' own masses, read off the build rather than off the catalog, so a panel row and
## the aircraft cannot disagree about what is fitted.
func _link_total_g() -> float:
	var total := 0.0
	for category in BAYS:
		if _build.components.has(category):
			total += float(_build.components[category].get("mass_g", 0.0))
	return total


## The fitted GPS's mast, in millimetres, as the build resolves it — the builder's typed value when
## there is one and the catalog entry's own figure otherwise. Read through `Build.rise_m_for`
## rather than off the part, so this row and the mass model quote the same number by construction.
func _mast_row() -> String:
	if not _build.components.has("gps"):
		return NOT_FITTED_TEXT
	var rise_mm := _build.rise_m_for(_build.components["gps"]) * 1000.0
	if rise_mm <= 0.0:
		return "flat on the plate"
	return "%.0f mm above the top plate" % rise_mm


## The buzzer's own cell, said in the words the warning uses. "no, dies with the pack" rather than
## a bare "no", because the consequence is the whole content of the field and a builder reading a
## spec sheet should not have to already know it.
func _own_power_row() -> String:
	if not _build.components.has("buzzer"):
		return NOT_FITTED_TEXT
	var specs: Dictionary = _build.components["buzzer"].get("specs", {})
	return "yes" if bool(specs.get("self_powered", false)) else "no, dies with the pack"
