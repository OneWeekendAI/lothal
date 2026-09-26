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
## Both labels of every row, as [name, value] pairs, kept so the panel can measure the width its
## text WANTS. See `content_width`: the value labels wrap, and a wrapping Label reports a minimum
## width of one pixel, so the container can no longer answer that question on its own.
var _row_labels: Array = []
## The column of rows, kept so the panel can be asked how wide its CONTENT wants to be. See
## `content_width`.
var _content: VBoxContainer
## The scroll around those rows, kept ONLY so `fit_to_content()` can turn it off. Nothing else
## touches it, and a panel that never calls that method behaves exactly as it always did.
var _scroll: ScrollContainer


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
	_scroll = scroll

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_padded(scroll).add_child(root)
	_content = root

	_title = Label.new()
	_title.text = "—"
	_title.theme_type_variation = &"TitleLabel"
	# One step down the published scale, matching the finder's title. The inspector is a column of
	# readouts beside a picker, not a page with a heading.
	_title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SUBTITLE)
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


## MAKES THIS PANEL AS TALL AS ITS OWN ROWS, instead of as tall as whatever it is given.
##
## Opt-in, and every panel that does not call it is unchanged — the default is right for Lab, where
## one panel fills a tall column and scrolling is the honest answer to an inspector with more rows
## than height.
##
## It is wrong for a column of THREE panels, which is what the Field room has, and the screenshot
## is what settled it. A `ScrollContainer` whose vertical scrolling is enabled reports almost no
## minimum height, so three panels sharing a 588 px column each get an equal 190 px share whatever
## they have to say — and the rows past that share are scrolled out of sight. That is not a
## survivable state in THIS theme: its scrollbars report zero width and paint nothing (see
## `_add_row`), so a row you could in principle drag into view is a row that simply looks cut off.
## Photographed at 1280x720: the Course panel's warning list was sliced in half and the Conditions
## panel's Temperature row was not on screen at all — two rows design §5.2 names explicitly.
##
## Turning the vertical scroll OFF is what makes the minimum real: a `ScrollContainer` that cannot
## scroll an axis claims its child's full size on that axis, so the panel's own minimum becomes its
## content's and a `SIZE_FILL` panel in a `VBoxContainer` is sized to its rows.
##
## **The horizontal escape hatch is deliberately left alone.** That one exists for a different
## failure — a single over-long value running off the window — and it is still the right answer to
## it. This method is about height.
##
## The consequence to know about: a panel that is taller than the space it is given no longer
## scrolls, it DRAWS PAST ITS OWN EDGE. That is a louder failure than a silent clip and it is meant
## to be — `tests/test_shell_layout.gd` asserts that every row a panel declares is drawn inside
## that panel's rect, which is the check that can see it.
func fit_to_content() -> void:
	if _scroll == null:
		return
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_FILL


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
	# MEASURED OFF THE TEXT, not only off the container, and the reason is the wrap added in
	# `_add_row`. `Label.get_minimum_size()` returns a width of 1 for an autowrapping label — that
	# is what makes wrapping possible — so a panel that asked its container how wide it wanted to be
	# would have answered "as narrow as you like" and then wrapped every row of every inspector to
	# the 316 px floor. The container is still consulted for the title and the footer, which do not
	# wrap; the rows are measured directly.
	return maxf(_content.get_combined_minimum_size().x, _rows_natural_width()) \
		+ LothalTheme.SPACE_2 * 2


## How wide the spec grid would be if nothing wrapped: the widest name plus the widest value, plus
## the separation between the two columns.
func _rows_natural_width() -> float:
	var names := 0.0
	var values := 0.0
	for pair in _row_labels:
		names = maxf(names, _label_width(pair[0] as Label))
		values = maxf(values, _label_width(pair[1] as Label))
	if _row_labels.is_empty():
		return 0.0
	var separation := 0.0
	if _content != null and _content.is_inside_tree():
		separation = float(_content.get_theme_constant("h_separation", "GridContainer"))
	return names + values + maxf(separation, float(LothalTheme.SPACE_4))


static func _label_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x


## Inset the panel's contents so right-aligned values do not sit flush against the window edge,
## which reads as clipped text even when nothing is actually cut off.
static func _padded(parent: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	# Exception: Programmatic margin container insets using spacing scale
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	# FILL THE SCROLL'S WIDTH. A ScrollContainer stretches its child only when the child asks to
	# expand; without it the content sat at its own minimum — which, once a footer with a 280 px
	# floor was hidden (a Lab dock page), was the one-character minimum of an autowrapping value, and
	# every value wrapped a letter per line in a 500 px column.
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(margin)
	return margin


func _add_row(grid: GridContainer, label_text: String) -> Label:
	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	grid.add_child(name_label)

	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	# WRAP RATHER THAN RUN OFF THE EDGE.
	#
	# The shell clamps this panel at `MAX_INSPECTOR_FRACTION` of the window (45%), and a clamp is
	# only half an answer: a Label that is not allowed to wrap keeps its full minimum width, the
	# grid keeps it, and the row draws past the panel and past the window with it. The screenshot
	# that prompted this shows `8 kHz (not modelled`, `0.16 °/s RM`, `109 km/` and `11.3 :` — four
	# rows of the FC inspector ending mid-word at the right-hand edge of the screen. The horizontal
	# scroll below is the escape hatch for that and it was not reachable: the theme's scrollbars
	# report zero width, so the bar that would have let you drag the rest into view painted nothing.
	#
	# With this on, an over-long value takes a second line inside the panel instead. `content_width`
	# below is what stops that happening on every row of every panel — it keeps asking for the width
	# the text would like, and wrapping is what happens when the window refuses.
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(value_label)
	_row_labels.append([name_label, value_label])
	return value_label


static func _or_dash(value: String) -> String:
	return value if value != "" else "—"
