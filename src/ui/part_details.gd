class_name PartDetails
extends SpecPanel
## Everything known about the highlighted part, plus what choosing it does to the build.
##
## Every value here is read out of the part dictionary at render time. Nothing about any
## specific part is written into this file or its subclasses — if a number on screen cannot be
## traced back to the JSON, that is a bug, and tests/test_lab.gd asserts exactly that
## traceability.
##
## Each panel deliberately mixes two kinds of row. The SPEC rows are the part's own published
## figures, and each subclass supplies its own set; the chrome that renders them lives in
## `SpecPanel`. The BUILD rows are the five derived stats (parts.md) recomputed for the whole
## current build — because "32 g" means little on its own, and "all-up weight 496 g, hover 29%" is
## the thing a builder is actually deciding between.
##
## The build rows are identical on all three panels on purpose. They are not the frame's stats
## or the motor's stats; they are the aircraft's, and whichever rail you are working on you are
## working on the same aircraft. Giving each panel its own copy of the numbers would invite
## three renderers and eventually three answers.
##
## THEY ARE ALSO WHY THIS CLASS AND `AirframePanel` ARE SIBLINGS RATHER THAN PARENT AND CHILD.
## Airframe's subject is a frame, which has no all-up weight and no hover throttle because it has no
## motor and no pack; it used to inherit these five rows and answer them about whatever build
## happened to be loaded, which is how a frame editor came to display a freestyle quad's flight
## time. Both families now extend `SpecPanel` and each supplies its own footer.

const STAT_ROWS := [
	{"key": "weight", "label": "All-up weight"},
	{"key": "twr", "label": "Thrust : weight"},
	{"key": "hover", "label": "Hover throttle"},
	{"key": "time", "label": "Flight time"},
	{"key": "current", "label": "Flight current"},
	{"key": "speed", "label": "Top speed"},
]

## The part currently on screen. `row_text` answers about this and nothing else.
##
## Named `_rendered_part` rather than `_part` because `_part` is what several subclasses call the
## parameter of their own `_read` override, and a member of that name shadows all of them.
var _rendered_part: Dictionary = {}

var _stat_values: Dictionary = {}     # stat key -> Label
var _warnings: WarningList
var _build_note: Label
## The whole-build numbers' rows, held so the Lab dock can take them off the page (lab dock design
## §2: "Dry mass, AUW, T:W and flight time move to the top bar ... never repeated inside a
## section"). Hidden rather than deleted: `stat_text` still answers, and the old shell and Sim's
## build panel still show them.
var _stats_block: Array[Control] = []


## Shows or hides the whole-build stat rows and the "Stats for …" note. The warnings stay: they are
## this page's "Why?".
func set_build_stats_visible(shown: bool) -> void:
	for control in _stats_block:
		control.visible = shown


func build_stats_visible() -> bool:
	return _stats_block.is_empty() or _stats_block[0].visible


## The aircraft's five derived stats, its warnings, and what they were computed from.
func _build_footer(root: VBoxContainer) -> void:
	var rule := HSeparator.new()
	root.add_child(rule)

	var stats := GridContainer.new()
	stats.columns = 2
	root.add_child(stats)
	_stats_block = [rule, stats]

	for row in STAT_ROWS:
		_stat_values[row["key"]] = _add_row(stats, row["label"])

	_warnings = WarningList.new(280)
	root.add_child(_warnings)

	_build_note = Label.new()
	_build_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_note.custom_minimum_size = Vector2(280, 0)
	_build_note.theme_type_variation = &"MutedLabel"
	root.add_child(_build_note)
	_stats_block.append(_build_note)


## Renders one part against the whole current build, so the five derived stats move with every
## selection — the feedback loop parts.md calls the product.
func render(part: Dictionary, build: Build) -> void:
	_rendered_part = part
	render_rows(String(part.get("name", "—")))

	_stat_values["weight"].text = "%.0f g" % build.all_up_weight_g()
	_stat_values["twr"].text = "%.1f : 1" % build.thrust_to_weight()
	if build.can_hover():
		_stat_values["hover"].text = "%.1f %%" % (build.hover_throttle() * 100.0)
		# Flight time and current are the two numbers this build answers UNDER THE SELECTED
		# CONDITIONS (F8, design §4.3/§3.3) — a headwind moves both, so both name the conditions
		# they were quoted at (check 7). AUW above does not: it is the one row the design calls
		# unconditional, and labelling it would be noise (check 8).
		# No wind argument: since F8's fix round both functions default to the Build's OWN
		# `field_wind_mps` (review finding 6), so the number and the label beside it cannot come
		# apart — a panel that passed the wind explicitly could one day forget to.
		_stat_values["time"].text = "%.1f min (%s)" % [
			build.flight_time_min(), build.field_conditions_name]
		_stat_values["current"].text = "%.1f A (%s)" % [
			build.average_flight_current_a(), build.field_conditions_name]
	else:
		_stat_values["hover"].text = "won't hover"
		_stat_values["time"].text = "—"
		_stat_values["current"].text = "—"
	_stat_values["speed"].text = "%.0f km/h" % build.top_speed_kmh()

	# Warn, never block (parts.md). A 3" frame under a 7" prop is a legitimate thing to look at;
	# the consequence is the lesson, and the choice stays selectable.
	_warnings.show_warnings(build.warnings())

	_build_note.text = "Stats for %s / %s / %s / %s / %s / %s." % [
		build.frame.get("name", "?"), build.motor.get("name", "?"),
		build.propeller.get("name", "?"), build.battery.get("name", "?"),
		build.esc.get("name", "?"), build.fc.get("name", "?")]


func row_text(key: String) -> String:
	return _read(_rendered_part, key)


## One rendered stat row, for tests — the counterpart of `rendered_text()` for the footer block.
func stat_text(key: String) -> String:
	return _stat_values[key].text if _stat_values.has(key) else "(missing)"


## Resolves a row key against the part dictionary and formats it for display. The default reads the
## `catalog` block, which covers every browsing field; subclasses override to add their own unit
## formatting for `specs` fields.
func _read(part: Dictionary, key: String) -> String:
	return _or_dash(str(part.get("catalog", {}).get(key, "")))


## One spec row's rendered text for an arbitrary part, without painting the panel. The renderer goes
## through the same `_read()`, so a test asserting here is asserting what is on screen and not a
## second formatting path.
func detail_text(part: Dictionary, key: String) -> String:
	return _read(part, key)
