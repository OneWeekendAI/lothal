class_name SpecPanel
extends PanelContainer
## A titled inspector: a name, a grid of labelled rows, and whatever a subclass puts underneath.
##
## ## Why this exists as its own class
##
## `PartDetails` used to be both this and the aircraft's stat block — the five derived build figures
## (all-up weight, thrust:weight, hover throttle, flight time, top speed), the build warnings, and
## the "stats for frame / motor / prop / pack / esc / fc" note. That pairing is right for a catalog
## panel, where the whole question is *what does choosing this part do to my aircraft*.
##
## It is wrong for Airframe. airframe.md's subject is A FRAME, not an aircraft: there is no motor, no
## propeller and no pack, and a panel that answered "all-up weight 496 g, hover 29%" while you were
## drawing an arm would be answering about a machine nobody has designed yet. Those five rows were
## the single largest piece of drone context in the Airframe room, and the way to remove them is to
## stop inheriting them rather than to blank them out — a blanked row is still a row, and it invites
## someone to fill it back in.
##
## So the shared half — the chrome, the row grid, the formatting, the `rendered_text()` test seam —
## lives here, and each family supplies its own footer:
##
##   - `PartDetails` adds the build stats, the warning list and the build note.
##   - `AirframePanel` adds the frame's own summary: mass, CG and inertia, computed from geometry.
##
## Both keep the same test seam, so a test that asserts what is on screen goes through one door for
## either family.

var spec_rows: Array = []

var _title: Label
var _detail_values: Dictionary = {}   # spec key -> Label
## The column of rows, kept so the panel can be asked how wide its CONTENT wants to be. See
## `content_width`.
var _content: VBoxContainer


func _init(p_spec_rows: Array) -> void:
	spec_rows = p_spec_rows

	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	# HORIZONTAL SCROLL IS THE ESCAPE HATCH, NOT THE PLAN.
	#
	# A ScrollContainer does not claim its child's width once it can scroll it, and that is the
	# property that matters here: without it, a value longer than the panel — "centred (<0.1 mm of
	# the origin)" is one — pushed the whole tab wider than the window it was anchored inside, and
	# the last characters of every row were cut off by the window edge with no way to reach them.
	# The shell still sizes this panel to its content (`content_width`); this is what happens when
	# the content wants more room than the window has to give.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_padded(scroll).add_child(root)
	_content = root

	_title = Label.new()
	_title.text = "—"
	_title.theme_type_variation = &"TitleLabel"
	root.add_child(_title)

	root.add_child(HSeparator.new())

	var specs := GridContainer.new()
	specs.columns = 2
	root.add_child(specs)

	for row in spec_rows:
		_detail_values[row["key"]] = _add_row(specs, row["label"])

	_build_footer(root)


## What goes below the spec grid. The base panel has nothing there — a subclass that adds no footer
## is a legitimate panel, not an unfinished one.
func _build_footer(_root: VBoxContainer) -> void:
	pass


## Sets the title and repaints every spec row. A subclass renders by calling this once its own
## subject is in place.
func render_rows(title_text: String) -> void:
	_title.text = title_text.to_upper()
	for row in spec_rows:
		var key: String = row["key"]
		_detail_values[key].text = row_text(key)


## One row's text, resolved against whatever this panel's subject currently is.
##
## THE SUBJECT IS NOT A PARAMETER, deliberately. The two families hold entirely different subjects —
## a part dictionary out of the catalog, and an `AirframeDocument` — and threading either through a
## shared signature would either force one family to pretend to be the other or push both through an
## untyped `Variant`. Each family stores what it is showing and answers about that, which also means
## a caller can never ask a panel about a subject it is not currently displaying.
##
## Units are applied in the overrides and only there — physics.md §1's coordinate contract keeps
## everything SI right up to the UI boundary. Unknown or absent values render as an em dash rather
## than "0" or "": a value nobody has filled in should read as missing, not as a measurement of zero.
func row_text(_key: String) -> String:
	return "—"


## Every rendered row as one string, label and value, for tests.
##
## A TEST SEAM and nothing else: a panel's job is to put numbers on screen, and the only way to
## check that it put the RIGHT numbers there is to read back what it rendered. Asserting against the
## source data instead would test that data twice and the panel not at all.
func rendered_text() -> String:
	var lines: Array[String] = []
	for row in spec_rows:
		var key: String = row["key"]
		lines.append("%s: %s" % [row["label"], _detail_values[key].text])
	return "\n".join(lines)


## How wide this panel would like to be, in pixels, for its current contents to fit without
## scrolling — the rows plus the padding around them.
##
## Asked rather than inferred, because the rows are rendered AFTER the panel is first laid out: a
## shell that measured the tab once at startup sized itself to eleven dashes and was too narrow the
## moment real values arrived. The number changes with the text, so it has to be re-asked when the
## text does.
func content_width() -> float:
	if _content == null:
		return custom_minimum_size.x
	return _content.get_combined_minimum_size().x + LothalTheme.SPACE_2 * 2


## Inset the panel's contents so right-aligned values do not sit flush against the window edge,
## which reads as clipped text even when nothing is actually cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	# Exception: Programmatic margin container insets using spacing scale
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	parent.add_child(margin)
	return margin


func _add_row(grid: GridContainer, label_text: String) -> Label:
	var name_label := Label.new()
	name_label.text = label_text
	grid.add_child(name_label)

	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)
	return value_label


static func _or_dash(value: String) -> String:
	return value if value != "" else "—"
