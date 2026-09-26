class_name FieldSystem
extends Control
## THE FIELD ROOM, as a system on the dock (design §5.1-§5.3, slice F10).
##
## ---------------------------------------------------------------------------
## WHAT IS DIFFERENT ABOUT THIS SYSTEM, IN ONE LINE
## ---------------------------------------------------------------------------
##
## Every other system on the dock is a way of looking at THE AIRCRAFT. This one is a way of looking
## at THE PLACE. So selecting it does what no other system does: the viewport stops showing the
## drone and shows the site.
##
## That is a real departure and it is not asserted, it is inherited. `glass_shell.gd`'s
## `_on_room_changed` already says "EVERY room retracts the chrome, not only Sim" — the shell has a
## shape for a destination whose subject is not the aircraft, and Field is that shape promoted from
## the Rooms menu to the dock. The Airframe room is the other one: it owns the window, hides Lab's
## viewport, and brings its own columns. This room is built to that pattern deliberately, so the
## shell has two instances of one rule rather than one rule and one exception.
##
## **The two camera laws never meet.** Lab's distance is FIXED across the whole catalog, so that a
## whoop looks small beside a 10" (see `LabScreen._camera_distance_m`). Field's camera FRAMES THE
## SITE, so a 30 m park and a 400 m field both fill the window. Those two rules would fight in one
## viewport; they are in two, and each one keeps its reason.
##
## ---------------------------------------------------------------------------
## THE RAIL IS TWO-LEVEL, WHICH IS THE ONE SHAPE THE OTHER SYSTEMS DO NOT HAVE
## ---------------------------------------------------------------------------
##
## A system's rail is normally that system's parts — one flat shelf. Field's is the SITES, and
## within the selected site, ITS COURSES. One level deeper, because a course without the place it
## is laid out in has no elevation, no ground and no obstacles, and F1 through F5 spent five slices
## making that relationship real. Selecting a site selects its first course, so the second list is
## never showing a route that belongs somewhere else.
##
## ---------------------------------------------------------------------------
## THE DRONE SILHOUETTE IS BEHIND A FLAG THAT DEFAULTS ON (§11 Q1)
## ---------------------------------------------------------------------------
##
## It is the one element here that could read as clutter rather than as information, and the design
## marks it open. It is built ON so the question can be answered by LOOKING at it — see the F10
## report for what the screenshot showed.
##
## **It is a footprint and not a body, and that is a refusal rather than an omission.** `Build`
## publishes `airframe_span_m()` — a real, derived width — and publishes no overall HEIGHT for an
## assembled aircraft. Drawing a box "about so tall" would be inventing a spec to unlock a feature,
## which §0.1 forbids. So the silhouette is the span, drawn flat on the ground at the start gate,
## and the thing it makes visible is exactly the thing the aircraft contributes to the field: how
## big it is next to a ring.

## The two levels of the rail, and the three panels of §5.2, named ONCE.
##
## `GlassShell.SYSTEMS`' Field entry points at these constants rather than repeating the words.
## P10f's finding was two lists that had to be the same list and were never checked to be; a
## reference is the version of that which cannot drift.
const RAIL_TITLES := ["Sites", "Courses"]
const PANEL_TITLES := ["Site", "Course", "Conditions"]

## Horizontal field of view, matching the field editor's. The camera is KEEP_WIDTH for
## `LabScreen`'s reason: this room is a viewport between two columns, so its aspect is decided by
## the window, and under Godot's default KEEP_HEIGHT the horizontal angle would move with it.
const CAMERA_FOV := 50.0

## How much of the view the site's widest dimension takes. Below 1.0 so the ground has an edge you
## can see — a field drawn exactly to the frame reads as an infinite plane, which is the one thing
## a bounded site is not.
const SITE_SCREEN_FRACTION := 0.82

## Looking down at the field from a third of the way up the sky. Steeper reads as a map and loses
## gate height entirely; shallower hides the far half of the course behind the near half.
const CAMERA_ELEVATION_DEG := 34.0

## How thick the footprint plate is drawn. A DRAWING THICKNESS, in the sense a line width is one,
## and not a claim about any aircraft: the width of the plate is `Build.airframe_span_m()` and is
## real, and nothing here says how tall a drone is. See the header.
const PLATE_THICKNESS_M := 0.02

## ---------------------------------------------------------------------------
## THE AUTHORING CONTROLS (F11), AND WHY THEY ARE THE SHAPE THEY ARE
## ---------------------------------------------------------------------------
##
## §2.4's rule came across whole: a gate is placed BY DRAGGING IT, and the only controls are the
## three things a drag cannot express — how high it is, which way it faces, how big its ring is.
## Everything else on this room's rail is a number a builder LOOKS UP rather than judges (an
## elevation, a temperature, the size of their field), and parts.md's rule decides that: ask for
## what can be looked up, and hunting for 920 on a slider turns an exact known fact into a gesture.
##
## **HEIGHT IS NOW HEIGHT ABOVE THE GROUND, and that is the one semantic the old screen did not
## have.** It could not have it: it drew a flat plane and had no `height_at` to ask. Here a gate
## dragged across a slope keeps the clearance it was given rather than keeping a y that was only
## ever measured from a datum nobody flies at. On a flat site at zero the two readings are the
## same number, which is why every behaviour `test_field_editor.gd` pinned still holds.
##
## The ranges are the extent of the CONTROL, not a claim about what is allowed — the warnings, not
## the slider, are what say a ring is in the ground or smaller than the aircraft. Warn, never block.
const MIN_HEIGHT_M := 0.1
const MAX_HEIGHT_M := 40.0
const MIN_RADIUS_M := 0.25
const MAX_RADIUS_M := 6.0
const HEIGHT_STEP_M := 0.1
const RADIUS_STEP_M := 0.05
const HEADING_STEP_DEG := 1.0

const ELEVATION_STEP_M := 1.0
const TEMPERATURE_STEP_C := 1.0

## `Wind.gust_tau_s`'s own field range. Its shipped value (`Wind.DEFAULT_GUST_TAU_S`) is a labelled
## GUESS (`wind.gd`'s header), so §0.1's "a guess ships with an editable field beside it" is what
## puts this control here — not a belief that a builder can state a true settling time.
## Ruling 78's local workaround, in pixels — see `_scroller()`. Same figure `part_finder.gd`
## uses, because it is the same grabber.
const SCROLLBAR_WIDTH := 8.0

## THE WIND'S OWN THREE FIELDS (§4.3): steady speed, the bearing it comes FROM, and the gust
## amplitude. Every one was on `Conditions`, saved, and flown by Sim since F7 — and none had a
## control, so every preset anyone made was calm. The ranges are the controls' extent, not a rule
## about what is flyable: 30 m/s is past anything a 5" machine can hold station in, and saying so
## is Lab's job (reported, never judged), not this field's.
const MAX_WIND_SPEED_MPS := 30.0
const WIND_SPEED_STEP_MPS := 0.5
const WIND_FROM_STEP_DEG := 5.0
const MAX_GUSTINESS_MPS := 15.0
const GUSTINESS_STEP_MPS := 0.5

const MIN_GUST_TAU_S := 0.5
const MAX_GUST_TAU_S := 10.0
const GUST_TAU_STEP_S := 0.1

## THE SITE'S OWN DIMENSIONS, WHICH WERE A CHOSEN NUMBER WITH NO FIELD BESIDE IT UNTIL NOW.
## `Site.DEFAULT_WIDTH_M` / `DEFAULT_LENGTH_M` are 120 m because 120 m is comfortably bigger than
## the default circuit and small enough to see the edge of — a chosen number, which F5 deferred and
## which this room, being the first authoring surface the field ever had, owes a control.
##
## The range is the control's extent again: 5 m is smaller than any ring and 1000 m is past the
## camera's own far plane usefulness, and neither is a rule about where anyone may fly.
const MIN_SITE_DIM_M := 5.0
const MAX_SITE_DIM_M := 1000.0
const SITE_DIM_STEP_M := 5.0

## How far the pointer may travel while a gate is under it before the drag is treated as an orbit.
const DRAG_DEG_PER_PIXEL := 0.4
const ELEVATION_LIMIT_DEG := 85.0

## THE WIDTH THE THREE PANELS' ROW GRIDS ARE HELD OPEN AT, and it is a repair rather than a
## decoration — the screenshot is what found it.
##
## `SpecPanel._add_row` makes every VALUE label autowrap, and an autowrapping `Label` reports a
## minimum width of ONE PIXEL (that is what makes wrapping possible — `content_width`'s own
## comment says so). A `ScrollContainer` hands its child the child's minimum width, so a panel
## whose footer asks for nothing collapses its value column to a few pixels and renders every
## value one letter per line. Photographed at 1280x720: the Site panel read "F / i / e / l / d"
## down the right-hand edge, in a 316 px panel with 200 px of room to spare, and the five rows
## below it were pushed out of sight by that one 100 px tall row.
##
## Lab does not show this because `PartDetails` carries a footer — build stats and a warning list —
## whose own minimum holds the column open. The Course panel here has a `WarningList` and rendered
## correctly in the same shot; the two without a footer did not. So the floor is stated rather than
## inherited from whatever a panel happens to put underneath its rows.
##
## **268 IS CHOSEN BY EYE, and it is chosen against one thing:** the 316 px the panels are wide,
## less the `PanelContainer`'s own stylebox and the `SPACE_2` inset `SpecPanel._padded` adds on each
## side — read off the 1280x720 screenshot that found the defect, not computed. It is a DRAWING
## DIMENSION, in the sense a margin is one: nothing about the aircraft, the field or the weather
## depends on it, so §0.1's "a guess ships with an editable field beside it" does not bite. What it
## has to be is big enough that the widest value on these three panels ("120 × 120 m",
## "1.2250 kg/m³") does not wrap, and small enough to fit the panel. If the panels are ever
## resized, this moves with them.
const PANEL_CONTENT_WIDTH := 268.0

## How wide the rail is. 216 px until F11, widened because the rail now carries five labelled
## numeric fields as well as two lists, and a SpinBox with a three-digit value and a "°C" suffix
## does not fit beside its own label in 216. Measured against the same 1280x720 photograph the
## panel width above was: the viewport still keeps well over half the window, which is the thing
## this room exists to show and which `test_shell_layout` holds a floor under.
const RAIL_WIDTH := 252.0

## HOW MUCH OF EACH COLUMN IS VISIBLE WITHOUT SCROLLING, AND IT IS THE FLOOR THIS ROOM REFUSES TO
## GO BELOW rather than the height it wants to be.
##
## **This room used to have no such floor, and that is the defect these two constants close.** Both
## of its columns are `VBoxContainer`s of fixed-height controls, so each one's combined minimum is a
## SUM — 488 px for the rail, 579 px for the panels, both measured — and an `HBoxContainer` expands
## to its children's combined minimum WHATEVER its offsets say (the fact `test_shell_layout`'s
## header names three times). `project.godot` lets a builder make the window 1024x600, which leaves
## this room 468 px: measured at that size, the row stood 579 px tall, 111 px of it inside the strip
## the dock stands in and 35 px below the bottom of the window itself.
##
## Putting each column in a `ScrollContainer` is what unbinds the sum from the window — a scroller's
## own minimum height is nothing, so the row can be as short as the room is. These constants put
## back the only part of the sum that should NOT be negotiable.
##
## **240 IS CHOSEN BY EYE**, against the measurements above and against one thing each column has to
## be able to show without a scroll: for the rail, its two lists with their titles, the course name
## field and the button row under them (17 + 44 + 17 + 44 + 28 + 36 = 186 px of controls plus their
## separations) — choosing a site and a course is the one thing you came to the rail for. For the
## panels, the Site panel whole (144 px measured) and the top of the Course panel under it. Neither
## number is derived from anything about the field, the aircraft or the weather, so §0.1's "a guess
## ships with an editable field beside it" does not apply: they are drawing dimensions, like a
## margin. If the rail's controls are ever re-laid-out, these move with them.
const RAIL_VISIBLE_FLOOR := 240.0
const PANELS_VISIBLE_FLOOR := 240.0

## The node names the world uses, spelled once so the room and its tests agree without either
## reading the other's spelling out of the implementation.
const SILHOUETTE_NAME := "DroneSilhouette"
const TERRAIN_NAME := "Terrain"

## The places, the routes and the weather. Handed in by the shell, which holds the one instance of
## each for the session — a second copy here is how the garage and the field come to disagree about
## where the builder is (see `RoomHost`).
var sites: SiteLibrary
var courses: CourseLibrary
var conditions: ConditionsLibrary

## The aircraft, for the one number the aircraft contributes to a field: how wide it is. Null is a
## legitimate state — the empty shell has no drone — and the silhouette simply is not drawn.
var build: Build = null

## §11 Q1, built ON. See the header.
var show_drone_silhouette := true

## WHERE THE EDITS LAND. This room is the only writer of `user://courses.json` and of the
## elevation on `user://sites.json`, and it writes on every change rather than on exit — there is
## no exit. Lothal is closed by closing the window, and a configuration that only persists when you
## quit politely is a configuration that does not persist.
var save_path := CourseLibrary.SAVE_PATH
var sites_path := SiteLibrary.path_beside(CourseLibrary.SAVE_PATH)
var conditions_path := ConditionsLibrary.path_beside(CourseLibrary.SAVE_PATH)

## Which gate the sliders and the drag are about.
var selected_gate := 0

## The gust process's one free constant, held here so the labelled guess has an editable field
## beside it. Nothing persists it yet — there is still no per-course or per-conditions slot for a
## settling time — so this moves the in-memory guess a builder is trying, and says so on screen.
## READ THROUGH TO THE SELECTED CONDITIONS, never mirrored on this object. It used to be a plain
## member, and that member was the whole bug: the SpinBox set it, `_changed` never persisted it,
## and `main.gd` never read it — so "Gust settle" was a dial with no wire and the check covering it
## asserted that a setter sets. A getter over the record cannot go stale and cannot be set without
## going through `set_field_gust_tau_s`, which is the one path that saves.
var gust_tau_s: float:
	get:
		var now := conditions.selected()
		return now.gust_tau_s if now != null else Conditions.DEFAULT_GUST_TAU_S

var site_list: ItemList
var course_list: ItemList
var name_field: LineEdit
var elevation_field: SpinBox
var temperature_field: SpinBox
var width_field: SpinBox
var length_field: SpinBox
var gust_tau_field: SpinBox
var wind_speed_field: SpinBox
var wind_from_field: SpinBox
var gustiness_field: SpinBox
## The label a check reads the word "guess" off. The LIVE control's text, not the source file — a
## grep for "guess" would also match this file's own comments, which is a check that cannot fail.
var gust_tau_label: Label
var viewport_container: SubViewportContainer
var renderer: CourseRenderer

var _viewport: SubViewport

## The rail and the two scrollers that keep this room inside the smallest window the app allows.
## Held so `rail()`, `rail_scroll()` and `panels_scroll()` can hand them to a check by name — a
## check that walks `site_list.get_parent().get_parent()` to find the rail silently starts
## measuring something else the day a container is inserted, which is exactly what just happened.
var _rail: PanelContainer
var _rail_scroll: ScrollContainer
var _panels_scroll: ScrollContainer
var _orbit: Node3D
var _camera: Camera3D
var _terrain: MeshInstance3D
var _silhouette: MeshInstance3D
var _panels: Dictionary = {}
var _warnings: WarningList
## True while a list is being repopulated, so `item_selected` firing as a side effect of `clear()`
## and `add_item()` does not read as a builder clicking a row.
var _filling := false
## Set while the room writes its OWN controls from the model, so a programmatic slider or spinbox
## move does not read back as the builder having dragged something.
var _updating := false
var _delete_button: Button
var _azimuth_rad := 0.0
var _elevation_rad := deg_to_rad(CAMERA_ELEVATION_DEG)
var _orbiting := false
var _dragging_gate := false

## The Lab dock page this room is showing — "site", "course" or "conditions" (SectionRows' `sheet`)
## — or "" for the whole room. See `set_dock_page`.
var dock_page := ""
## The head over the site view on a dock page: that row's two numbers and its own warnings.
var page_view: ItemPageView
## The rail's controls by the dock page they belong to (`_collect_rail_groups`); "all" is what only
## the whole room shows.
var _rail_groups: Dictionary = {}

## Emitted after every edit, so the shell can put the garage's air and weather in step. The old
## screen's signal, carried across under its own name.
signal course_changed

## Emitted when the builder picked a different site or course, so the shell can put the garage's
## air in step — the whole of §5.3's "every quoted number names its conditions" depends on the
## garage hearing about it.
signal selection_changed


func _init(p_sites: SiteLibrary, p_courses: CourseLibrary, p_conditions: ConditionsLibrary,
		p_build: Build = null, p_save_path: String = CourseLibrary.SAVE_PATH) -> void:
	sites = p_sites
	courses = p_courses
	conditions = p_conditions
	build = p_build
	save_path = p_save_path
	# The files that pair with this courses file, so a caller handing over a scratch library cannot
	# overwrite the builder's own fields. The libraries own that pairing; this room only asks.
	sites_path = SiteLibrary.path_beside(p_save_path)
	conditions_path = ConditionsLibrary.path_beside(p_save_path)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	row.add_child(_build_rail())

	viewport_container = SubViewportContainer.new()
	viewport_container.name = "SiteView"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# THE DRAG LIVES HERE (§2.4). A ring is placed by moving it on the ground at the scale it will
	# be flown at; dragging anywhere else turns the view.
	viewport_container.gui_input.connect(_on_viewport_input)
	# THE SITE VIEW IS THE BODY OF A LAB DOCK PAGE: the page's two numbers and its row's own
	# warnings (short + Why?) stand above it, as they stand above every other section's drawing.
	# The head is hidden until a dock page is set (`set_dock_page`).
	page_view = ItemPageView.new()
	page_view.name = "Page"
	page_view.set_body(viewport_container)
	row.add_child(page_view)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	# Its own World3D, for the reason Lab's and the field editor's both have one: Sim is a separate
	# scene with its own cameras, and a shared world is how two rooms render into each other.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.add_child(_viewport)

	_build_world()

	row.add_child(_build_panels())
	_collect_rail_groups()
	set_dock_page("")

	refresh()


# ---------------------------------------------------------------------------
# The rail — two levels
# ---------------------------------------------------------------------------

## ONE COLUMN'S SCROLLER. Vertical only, and with a stated floor under what stays visible.
##
## Horizontal scrolling is DISABLED rather than automatic, and that is the half that makes the
## width behave: with it disabled the scroller hands its child exactly the width it has, so the
## rail's fields and the panels' rows keep being laid out against the column width they were
## measured at instead of sliding sideways behind a bar nobody would find.
##
## `custom_minimum_size.y` is the floor, not a height: a `ScrollContainer` asks for nothing
## vertically, which is what lets the room fit a short window, and with nothing to stop it the same
## property lets the room be squeezed to a sliver of a column in a window a little shorter still.
## The floor is the point past which this room would rather overflow the window than pretend.
func _scroller(node_name: String, visible_floor: float) -> ScrollContainer:
	var scroller := ScrollContainer.new()
	scroller.name = node_name
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.custom_minimum_size = Vector2(0, visible_floor)
	# `SIZE_FILL` AND NOT `SIZE_EXPAND_FILL`, and the difference is the viewport's. Expanding, the
	# panel column took every spare pixel of the row and the site view fell from 866 px to 479 in
	# a 1280 px window — caught by `test_shell_layout`'s own floor under how much of the window the
	# site keeps, which is the thing this room exists to show.
	scroller.size_flags_horizontal = Control.SIZE_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A SCROLLBAR YOU CAN SEE (Ruling 78), and this is `part_finder.gd:276-287`'s workaround with
	# `part_finder.gd`'s named cause: `LothalTheme` styles a `VScrollBar` as a translucent grabber
	# over a `StyleBoxEmpty` track, and NEITHER stylebox carries a content margin. A `ScrollBar`'s
	# minimum size IS its styleboxes' minimum size, so every scrollbar in this app reports a width
	# of zero — live, wheel-scrollable, painting nothing.
	#
	# It matters more here than on a shelf of parts. A list that stops at row 13 still reads as a
	# list; a PANEL COLUMN that ends mid-row reads as "that is all there is", and what it hides is
	# the three panels §5.2 mandates. F11 is what put two whole columns inside scrollers, so F11 is
	# where the symptom got worse.
	#
	# FIXED LOCALLY, NOT IN THE THEME, deliberately and with the cost written down: a content
	# margin on the grabber changes the minimum width of every `ScrollContainer` in the app, which
	# needs re-measuring against this room's own floors and `test_shell_layout.gd`'s 1024x600
	# assertions. That measurement is not made here. Two columns are.
	scroller.get_v_scroll_bar().custom_minimum_size.x = SCROLLBAR_WIDTH
	# AND A GUTTER SO THE BAR IS NOT STANDING ON THE WORDS. Widening the bar gives it pixels; it
	# does not move the rows out from under it. A `ScrollContainer` lays its child out inside its
	# own `panel` stylebox's margins, and the theme's is empty, so this is a stylebox rather than a
	# property — the property does not exist.
	var gutter := StyleBoxEmpty.new()
	gutter.content_margin_right = SCROLLBAR_WIDTH
	scroller.add_theme_stylebox_override("panel", gutter)
	return scroller


## The rail itself, and the two scrollers, by name. See `_rail`.
func rail_panel() -> PanelContainer:
	return _rail


func rail_scroll() -> ScrollContainer:
	return _rail_scroll


func panels_scroll() -> ScrollContainer:
	return _panels_scroll


func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.name = "Rail"
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_rail_scroll = _scroller("RailScroll", RAIL_VISIBLE_FLOOR)
	rail.add_child(_rail_scroll)

	var column := VBoxContainer.new()
	column.name = "RailColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# TIGHTER THAN THE THEME'S DEFAULT, and it is a budget. This column holds fourteen controls in
	# 588 px of room; at the theme's own separation it needs 591 and an `HBoxContainer` expands to
	# its combined minimum whatever its offsets say, so those three pixels are drawn over the dock
	# rather than dropped. One pixel off each gap buys thirteen back.
	#
	# The scroller above is what keeps that budget from being a cliff (see `_scroller`): the tight
	# separation still means fewer builders ever have to scroll, which is worth three pixels.
	column.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	_rail_scroll.add_child(column)
	_rail = rail

	site_list = _titled_list(column, RAIL_TITLES[0])
	site_list.item_selected.connect(choose_site)
	course_list = _titled_list(column, RAIL_TITLES[1])
	course_list.item_selected.connect(choose_course)

	# NAMING, ADDING AND DELETING A COURSE, under the list they are about. The old screen's three
	# controls, carried across unchanged in behaviour.
	name_field = LineEdit.new()
	name_field.name = "CourseName"
	name_field.placeholder_text = "Course name"
	name_field.text_submitted.connect(func(text: String) -> void: rename_course(text))
	column.add_child(name_field)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var new_button := Button.new()
	new_button.name = "NewCourse"
	new_button.text = "New"
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(func() -> void: new_course(_next_course_name()))
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.name = "DeleteCourse"
	_delete_button.text = "Delete"
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(func() -> void: delete_course())
	buttons.add_child(_delete_button)

	_build_gate_buttons(column)
	_build_field_section(column)
	return rail


## ADDING, REMOVING AND RE-ORDERING A GATE.
##
## **IN THE RAIL AND NOT ON THE COURSE PANEL, AND THAT IS A BUDGET RATHER THAN AN ARGUMENT.** They
## belong with the three sliders — they are about the selected gate, which is the Course panel's
## whole subject — and they were built there first. The panel column ships with 26 px of vertical
## slack at 1280x720 and this row costs about 31, which put the Conditions panel 39 px into the
## strip the dock stands in: measured, by `test_shell_layout`, not guessed. The rail has the room
## because its two lists give it back, so the row lives there and the reason is written down rather
## than left to look like a choice about where gate controls go.
##
## The running order IS part of the authored world — the same rings taken in a different sequence
## is a different course to fly, and the fingerprint says so — so it needs a control and not only
## a method.
func _build_gate_buttons(column: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "GATE"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	column.add_child(title)

	var buttons := HBoxContainer.new()
	buttons.name = "GateButtons"
	for spec in [["Add", 0], ["Remove", 1], ["Earlier", 2], ["Later", 3]]:
		var button := Button.new()
		button.name = "Gate%d" % int(spec[1])
		button.text = str(spec[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var which := int(spec[1])
		button.pressed.connect(func() -> void: _on_gate_button(which))
		buttons.add_child(button)
	column.add_child(buttons)


func _on_gate_button(which: int) -> void:
	match which:
		0: add_gate()
		1: remove_gate()
		2: reorder_gate(-1)
		3: reorder_gate(1)


## THE FIELD ITSELF — the numbers a builder LOOKS UP rather than judges by eye.
##
## Typed rather than dragged, which is a deliberate departure from §2.4's "the only controls are
## the three things a drag cannot express". That rule is about a GATE, whose height and heading are
## judged: you move them until the line looks right. An elevation is not judged, it is looked up.
##
## **THREE OF THESE FIVE ARE HERE BECAUSE OF §0.1 RATHER THAN BECAUSE OF §5.2.** The width, the
## length and the gust settling time are all shipped GUESSES — 120 m by 120 m is a chosen number
## and 2.5 s is a labelled one — and the global constraint says a guess ships with an editable
## field beside it. This room is the first authoring surface the field has ever had, so it is the
## first place that debt can be paid.
func _build_field_section(column: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "THE FIELD"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	column.add_child(title)

	elevation_field = _add_field(column, "Elevation", "m",
		AirDensity.MIN_ELEVATION_M, AirDensity.MAX_ELEVATION_M, ELEVATION_STEP_M,
		func(v: float) -> void: set_field_elevation_m(v))
	temperature_field = _add_field(column, "Temperature", "°C",
		AirDensity.MIN_TEMPERATURE_C, AirDensity.MAX_TEMPERATURE_C, TEMPERATURE_STEP_C,
		func(v: float) -> void: set_field_temperature_c(v))
	width_field = _add_field(column, "Width", "m",
		MIN_SITE_DIM_M, MAX_SITE_DIM_M, SITE_DIM_STEP_M,
		func(v: float) -> void: set_site_width_m(v))
	length_field = _add_field(column, "Length", "m",
		MIN_SITE_DIM_M, MAX_SITE_DIM_M, SITE_DIM_STEP_M,
		func(v: float) -> void: set_site_length_m(v))

	# The weather's moving half, beside the gust settle time it shares a process with.
	wind_speed_field = _add_field(column, "Wind", "m/s",
		0.0, MAX_WIND_SPEED_MPS, WIND_SPEED_STEP_MPS,
		func(v: float) -> void: set_field_wind_speed_mps(v))
	# 360 rather than 359 as the top, so the arrows can reach north from either side; the setter
	# wraps it back to 0 and the control re-reads the wrapped value.
	wind_from_field = _add_field(column, "Wind from", "°",
		0.0, 360.0, WIND_FROM_STEP_DEG,
		func(v: float) -> void: set_field_wind_from_deg(v))
	gustiness_field = _add_field(column, "Gustiness", "m/s",
		0.0, MAX_GUSTINESS_MPS, GUSTINESS_STEP_MPS,
		func(v: float) -> void: set_field_gustiness_mps(v))

	gust_tau_label = Label.new()
	gust_tau_label.name = "GustGuess"
	# The literal string a check reads: labelled a guess, not measured. SHORT ENOUGH TO SET ON ONE
	# LINE at this rail width, which is not a style preference — the second line it wrapped onto
	# was the last 3 px that put the rail in the dock's strip.
	gust_tau_label.text = "A guess, not measured."
	gust_tau_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gust_tau_label.custom_minimum_size = Vector2(RAIL_WIDTH - 24.0, 0)
	gust_tau_label.theme_type_variation = &"MutedLabel"
	column.add_child(gust_tau_label)

	gust_tau_field = _add_field(column, "Gust settle", "s",
		MIN_GUST_TAU_S, MAX_GUST_TAU_S, GUST_TAU_STEP_S,
		func(v: float) -> void: set_field_gust_tau_s(v))
	# Written under the same guard `_render_controls()` uses: this is the room writing its OWN
	# shipped default, not a builder having typed one.
	_updating = true
	gust_tau_field.value = gust_tau_s
	_updating = false


## A labelled numeric entry. A SpinBox is for a number you KNOW; the sliders on the Course panel
## are for one you are choosing by eye, and the split is the whole of §2.4 read literally.
func _add_field(column: VBoxContainer, label_text: String, suffix: String,
		minimum: float, maximum: float, step: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var field := SpinBox.new()
	field.name = label_text.replace(" ", "")
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.suffix = suffix
	field.custom_minimum_size = Vector2(96, 0)
	field.select_all_on_focus = true
	# A SpinBox is a Range, so `value_changed` does not fire for a value set from code — but the
	# guard is still what stops the room writing its own controls from reading back as an edit.
	field.value_changed.connect(func(v: float) -> void:
		if not _updating:
			on_change.call(v))
	row.add_child(field)
	column.add_child(row)
	return field


func _titled_list(column: VBoxContainer, title_text: String) -> ItemList:
	var title := Label.new()
	title.text = title_text.to_upper()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	column.add_child(title)

	var list := ItemList.new()
	list.name = title_text
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.auto_height = false
	# A FLOOR RATHER THAN A SHARE: the rail's fixed controls below take what they need first, and
	# an `ItemList` with no floor collapses to nothing when they do.
	#
	# 44 px, not 76, and the difference is measured rather than chosen. The rail carries two lists,
	# a name field, four gate buttons, five numeric fields and a wrapped label, and an
	# `HBoxContainer` expands to its combined minimum whatever its offsets say — at 76 the rail ran
	# 43 px into the strip the dock stands in. Found by LOOKING at the 1280x720 photograph, and
	# held by `test_shell_layout._the_rail_itself_stays_out_of_the_bottom_keepout` since — which is
	# also what said 52 was still 3 px short.
	list.custom_minimum_size = Vector2(0, 44)
	column.add_child(list)
	return list


## A site chosen: SELECT ITS FIRST COURSE TOO.
##
## Not a convenience. The second list is the courses of the selected site, and the panels below
## describe "the selected course" — so a site change that left the previous site's course selected
## would put a route from somewhere else under a Site panel describing here, with no click in
## between to blame it on.
## PUBLIC, and named for what it does rather than for the signal it happens to be wired to. A check
## about "selecting a site selects its first course" has to CALL the function that does it —
## asserting the outcome and trusting that the right function produced it is how a check passes a
## defect it was written to catch (the F8 finding).
func choose_site(index: int) -> void:
	if _filling:
		return
	var ids := sites.ids()
	if index < 0 or index >= ids.size():
		return
	sites.select(str(ids[index]))
	var here := courses_of_selected_site()
	if not here.is_empty():
		courses.select(str(here[0]))
	refresh()
	selection_changed.emit()


## `choose_site`'s twin, public for its reason.
func choose_course(index: int) -> void:
	if _filling:
		return
	var here := courses_of_selected_site()
	if index < 0 or index >= here.size():
		return
	courses.select(str(here[index]))
	refresh()
	selection_changed.emit()


## The ids of the courses laid out at the SELECTED site, in the library's order.
##
## The whole of the two-level rail is this function: a flat list of every course in the file is
## what the second level must NOT be, because a course belongs to one place and the panels beneath
## describe that place.
func courses_of_selected_site() -> Array[String]:
	var out: Array[String] = []
	# RULING 19, RESTORED. A library with no selected site answers `null`, and `.site_id` written
	# inline here aborts this function. Nowhere to fly means no courses here, which is the same
	# reading `_refresh_world()` gives a null site two hundred lines down.
	#
	# WHAT THIS GUARD DOES *NOT* FIX, measured rather than reasoned, because the final review said
	# otherwise and a mutation disproved it: the abort does NOT latch `_filling`. A GDScript
	# runtime error aborts only the function it is raised in and hands the CALLER this function's
	# return-type default — `[]` for `Array[String]` — so `_fill_lists_body()` carries straight on
	# and `_fill_lists()` clears the latch as usual. The rail keeps working. Removing this guard
	# and running the full suite produces the SCRIPT ERROR and no behavioural difference at all,
	# which is exactly why the only honest check for it is the source scan in
	# `test_ground_authority.gd` and not a behavioural one: an aborted call and a guarded call
	# return the same value to the same caller, and nothing downstream can tell them apart.
	#
	# The latch hazard is real, but it belongs to aborts raised INSIDE `_fill_lists_body()` itself
	# (`site_list.clear()` on a null list, say). That is what the two-function split below fixes,
	# and it has its own check.
	var selected_site := sites.selected()
	if selected_site == null:
		return out
	var here := selected_site.site_id
	for id in courses.ids():
		if courses.course(id).site_id == here:
			out.append(id)
	return out


# ---------------------------------------------------------------------------
# The three panels (§5.2)
# ---------------------------------------------------------------------------

func _build_panels() -> Control:
	var column := VBoxContainer.new()
	column.name = "Panels"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# TIGHTER THAN THE THEME'S DEFAULT, and it is the same three pixels the rail's own separation
	# comment names. The three panels end at y=639 against a 644 floor — comfortably inside it —
	# but the COLUMN that holds them asks for 591 px in 588, and both columns sit in one
	# `HBoxContainer`, which expands to the larger of the two whatever its offsets say. So the
	# overflow was the panel column's and it was drawn on the rail's side of the window. Two gaps,
	# and what they buy is the last row of the rail standing clear of the dock.
	column.add_theme_constant_override("separation", LothalTheme.SPACE_1)

	# EACH PANEL IS AS TALL AS ITS OWN ROWS, and the slack goes to a spacer underneath.
	#
	# TWO ARRANGEMENTS WERE TRIED FIRST AND BOTH ARE ON RECORD, because the second one looked
	# right and shipped a defect:
	#
	# 1. `SIZE_FILL` alone collapsed all three panels into 24 px bars with no text in them. A
	#    `SpecPanel`'s rows sit inside a vertically-expanding `ScrollContainer` whose minimum
	#    height is nearly nothing, so "as tall as your content" evaluated to "as tall as nothing".
	# 2. `SIZE_EXPAND_FILL` split the column into three equal 190 px shares whatever each panel
	#    had to say, and the rows past that share scrolled out of sight. It photographed as three
	#    tidy panels, which is why it survived a round: what was missing was the Course panel's
	#    warning list (sliced in half) and the Conditions panel's Temperature row (absent) — two
	#    things design §5.2 mandates. In this theme the scrollbars report zero width and paint
	#    nothing, so there was no affordance saying those rows existed.
	#
	# `fit_to_content()` is what makes (1) work: it turns the vertical scroll off, so the scroll
	# claims its child's full height and the panel's minimum becomes its content's. Called here
	# rather than inside each panel's `_init`, so the decision is visible in the one place that
	# decides how this column is divided.
	var site_panel := SitePanel.new()
	site_panel.name = PANEL_TITLES[0]
	column.add_child(site_panel)

	var course_panel := CoursePanel.new()
	course_panel.name = PANEL_TITLES[1]
	_warnings = course_panel.warnings
	column.add_child(course_panel)

	var conditions_panel := ConditionsPanel.new()
	conditions_panel.name = PANEL_TITLES[2]
	column.add_child(conditions_panel)

	for each in [site_panel, course_panel, conditions_panel]:
		(each as SpecPanel).fit_to_content()
		(each as Control).size_flags_vertical = Control.SIZE_FILL

	# The slack, so three content-sized panels sit at the top of the column instead of being
	# stretched to fill it. It is the ONLY thing in this column that expands.
	var slack := Control.new()
	slack.name = "Slack"
	slack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(slack)

	for each in [site_panel, course_panel, conditions_panel]:
		_panels[str(each.name)] = each

	# AND THE COLUMN SCROLLS, for `RAIL_VISIBLE_FLOOR`'s reason and measured on this very column:
	# the three content-sized panels sum to 579 px, which is 9 px inside the 588 the shipping
	# window leaves and 111 px outside the 468 the smallest one does. The `Slack` control above is
	# what keeps them at the top of the column when there is room to spare; this is what happens
	# when there is not.
	_panels_scroll = _scroller("PanelsScroll", PANELS_VISIBLE_FLOOR)
	_panels_scroll.add_child(column)
	return _panels_scroll


## One panel by its §5.2 name. The seam a test reads through, so a check asks for "Conditions"
## rather than walking a container and taking the third child — which would keep passing if the
## three were reordered into nonsense.
func panel(title: String) -> SpecPanel:
	return _panels.get(title, null) as SpecPanel


# ---------------------------------------------------------------------------
# The world — the SITE, not the drone
# ---------------------------------------------------------------------------

## The room's own 3D world, its camera and the plate at the start gate — the three things a check
## about the viewport swap and about the silhouette has to be able to look at. Accessors rather
## than public members so the room still owns when they are rebuilt.
func world() -> SubViewport:
	return _viewport


func camera() -> Camera3D:
	return _camera


func silhouette() -> MeshInstance3D:
	return _silhouette


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	# The ground, generated from the site's typed dimensions by F3's mesh builder. Never sculpted
	# and never imported (§0.1) — and never a bare PlaneMesh either, which is what the old field
	# editor drew and which cannot show a slope, a bowl or a wall.
	_terrain = MeshInstance3D.new()
	_terrain.name = TERRAIN_NAME
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.24, 0.27, 0.24)
	# Both faces, because a bowl and an enclosure are seen from inside as well as from above and a
	# back-face-culled wall vanishes exactly when you are standing in the field it encloses.
	ground.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain.material_override = ground
	_viewport.add_child(_terrain)

	renderer = CourseRenderer.new(course())
	_viewport.add_child(renderer)

	# THE AIRCRAFT, AT THE START GATE, AS A FOOTPRINT. See the header for why there is no body.
	_silhouette = MeshInstance3D.new()
	_silhouette.name = SILHOUETTE_NAME
	var plate := StandardMaterial3D.new()
	plate.albedo_color = LothalTheme.ACCENT
	plate.emission_enabled = true
	plate.emission = LothalTheme.ACCENT
	plate.emission_energy_multiplier = 0.8
	_silhouette.material_override = plate
	_viewport.add_child(_silhouette)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)

	_orbit = Node3D.new()
	_orbit.name = "Orbit"
	_viewport.add_child(_orbit)

	_camera = Camera3D.new()
	_camera.name = "SiteCamera"
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.1
	# Far enough for the biggest field the camera can be pulled back from. A 400 m site puts the
	# camera about 430 m out, and the far corner of the ground is further than the camera is.
	_camera.far = 6000.0
	_orbit.add_child(_camera)


## THE ONE PLACE THE SITE'S OWN SIZE DECIDES THE FRAMING (§5.1).
##
## Lab's camera distance is computed once from the catalog's largest frame and then held for every
## build, so that a whoop looks like a whoop beside a 10". That rule is exactly wrong here: a 30 m
## park and a 400 m field are the same picture at a fixed distance, one of them a dot. So this
## asks the SITE, every time, and a site whose extent changes reframes.
##
## Derived and not authored: the widest dimension of the site has to span
## `SITE_SCREEN_FRACTION` of a `CAMERA_FOV`-wide view, which is one line of trigonometry and no
## constant anybody picked. A GATE MOVING CANNOT CHANGE IT — nothing here asks the course anything,
## which is what stops the field jumping every time a ring is dragged.
func camera_distance_m() -> float:
	var terrain := site_terrain()
	var extent := terrain.extent() if terrain != null else Vector2.ZERO
	var widest := maxf(extent.x, extent.y)
	if widest <= 0.0:
		widest = Terrain.DEFAULT_WIDTH_M
	var required_width_m := widest / SITE_SCREEN_FRACTION
	return (required_width_m * 0.5) / tan(deg_to_rad(CAMERA_FOV) * 0.5)


# ---------------------------------------------------------------------------
# What is selected
# ---------------------------------------------------------------------------

## The place the selected course is laid out in — `RoomHost.site_of_selected_course()`'s rule,
## asked of the libraries this room was handed. A course pointing at a site that is not there falls
## back to the selected site: the builder is somewhere, and the nearest true answer to where is
## where they are.
func site() -> Site:
	var id := course().site_id
	return sites.site(id) if sites.has(id) else sites.selected()


func course() -> GateCourse:
	return courses.selected()


## The ground under the open course, or null for flat at zero.
##
## `site()` CAN ANSWER NULL — `SiteLibrary.selected()` reads an id out of a dictionary, and a
## library built in code has no id to read. `.terrain` on that null aborts whatever function it is
## written in, and every line after it silently does not happen, which is how a room stops drawing
## rather than opening somewhere flyable. One guard, in one place, named.
func site_terrain() -> Terrain:
	var here := site()
	return here.terrain if here != null else null


## How high above the ground under it this gate hangs.
##
## THE NUMBER THE SLIDER MOVES AND THE NUMBER THE PANEL QUOTES. A gate's stored y is a world
## height; what a builder authored is a clearance, and on a slope those are different facts. On a
## flat site at zero they are the same number, which is why nothing the old screen pinned moved.
func gate_height_above_ground_m(index: int) -> float:
	var gates := course().gates
	if gates.is_empty():
		return 0.0
	var gate: Dictionary = gates[clampi(index, 0, gates.size() - 1)]
	var at: Vector3 = gate["position"]
	return float(at.y) - ground_height_at(at.x, at.z)


## The height of the ground at a world x/z, or zero where there is no ground described. `height_at`
## takes WORLD coordinates and `Terrain` owns the halving rule — nothing here re-derives either.
func ground_height_at(x: float, z: float) -> float:
	var terrain := site_terrain()
	return terrain.height_at(x, z) if terrain != null else 0.0


# ---------------------------------------------------------------------------
# Editing the course (F11) — §2.4 moved into the room
# ---------------------------------------------------------------------------

func select_gate(index: int) -> void:
	selected_gate = clampi(index, 0, maxi(course().gates.size() - 1, 0))
	refresh()


## A new gate halfway along the leg from the selected gate to the next one, at the clearance and
## ring size of the gate it follows, facing the way that leg runs. On the route rather than at the
## origin: an editor that drops a gate in a corner of the map turns authoring back into data entry.
func add_gate() -> void:
	var gates := course().gates
	if gates.is_empty():
		gates.append(GateCourse.make_gate(Vector3(0.0, GateCourse.GATE_LOW_M, 0.0), 0.0,
			GateCourse.GATE_INNER_RADIUS_M))
		selected_gate = 0
		_changed()
		return

	var here: Dictionary = gates[selected_gate]
	var next: Dictionary = gates[(selected_gate + 1) % gates.size()]
	var midpoint: Vector3 = (here["position"] + next["position"]) * 0.5
	var along: Vector3 = next["position"] - here["position"]
	var heading := GateCourse.gate_heading_rad(here) if along.length() < 0.01 \
		else atan2(along.x, -along.z)

	gates.insert(selected_gate + 1, GateCourse.make_gate(midpoint, heading, float(here["radius"])))
	selected_gate += 1
	_changed()


## Removes the gate being edited. Refuses to remove the last one: a course with no gates is not a
## course, it is an empty field with a start line pointing at nothing.
func remove_gate() -> bool:
	if course().gates.size() <= 1:
		return false
	course().gates.remove_at(selected_gate)
	selected_gate = clampi(selected_gate, 0, course().gates.size() - 1)
	_changed()
	return true


## Moves the gate being edited earlier or later in the running order, and the selection follows it.
## The order IS part of the authored world — the same rings taken in a different sequence is a
## different course to fly, and the fingerprint says so.
func reorder_gate(delta: int) -> bool:
	var target := selected_gate + delta
	if target < 0 or target >= course().gates.size():
		return false
	var gate: Dictionary = course().gates[selected_gate]
	course().gates.remove_at(selected_gate)
	course().gates.insert(target, gate)
	selected_gate = target
	_changed()
	return true


## WHERE ON THE GROUND THE GATE STANDS — and it LANDS ON THE TERRAIN.
##
## The y of the argument is ignored: height is the slider's business, so dragging a gate across the
## field cannot quietly change how high it is. What it keeps is the CLEARANCE, not the world y —
## the gate arrives at `height_at` under the new spot plus the height it was authored at. Keeping a
## world y instead would make a ring dragged up a slope sink into it with nothing on screen or in
## the panel saying so, which is the failure a room that draws real ground has and a flat plane
## could not.
##
## **NOTHING IS CLAMPED TO THE SITE.** A ring dragged off the edge of the field stays where it was
## put and the course's own warnings say `OUTSIDE_SITE_EXTENT` — warn, never block. A silent clamp
## would move a gate the builder placed and tell them nothing, and the extent is a stated size
## rather than a rule about where anyone may fly.
func set_gate_ground_position(p_position: Vector3) -> void:
	var gates := course().gates
	if gates.is_empty():
		return
	var gate: Dictionary = gates[selected_gate]
	var above := gate_height_above_ground_m(selected_gate)
	gate["position"] = Vector3(
		p_position.x, ground_height_at(p_position.x, p_position.z) + above, p_position.z)
	_changed()


## How high above the ground this gate hangs. The ONE property this touches — see the twin note on
## `set_gate_radius_m`.
func set_gate_height_m(height_m: float) -> void:
	var gate: Dictionary = course().gates[selected_gate]
	var at: Vector3 = gate["position"]
	gate["position"] = Vector3(at.x, ground_height_at(at.x, at.z) + height_m, at.z)
	_changed()


func set_gate_heading_deg(heading_deg: float) -> void:
	var gate: Dictionary = course().gates[selected_gate]
	gate["normal"] = GateCourse.make_gate(
		gate["position"], deg_to_rad(heading_deg), float(gate["radius"]))["normal"]
	_changed()


## The ring's size. Each of the three setters writes its own key and no other — a slider that also
## nudged the radius would be a control that lies about what it is, and it is the kind of defect
## nothing on screen shows: the ring simply is not the size the number beside it says.
func set_gate_radius_m(radius_m: float) -> void:
	course().gates[selected_gate]["radius"] = radius_m
	_changed()


func warnings() -> Array[BuildWarning]:
	return CourseWarnings.evaluate(course(), build, site())


# ---------------------------------------------------------------------------
# The library, and the field itself
# ---------------------------------------------------------------------------

## A new course, AND A NEW PLACE TO PUT IT. One site per course, the migration's own rule: a course
## dropped into the last one's site would inherit an elevation nobody typed for it.
func new_course(p_name: String) -> void:
	var created := courses.create(p_name)
	created.site_id = sites.create(p_name).site_id
	courses.select(created.course_id)
	sites.select(created.site_id)
	selected_gate = 0
	_changed()


## Renames without changing the id, so nothing that pointed at the course — a saved selection, a
## best lap — is orphaned by a typo being fixed.
func rename_course(p_name: String) -> void:
	if p_name.strip_edges() == "":
		return
	courses.rename(course().course_id, p_name.strip_edges())
	_changed()


func delete_course() -> bool:
	if not courses.remove(course().course_id):
		return false
	selected_gate = 0
	_changed()
	return true


## By id rather than by row. `choose_course(int)` above is the rail's click; this is the one a
## caller with an id in hand uses, and the two are separate so neither has to guess which it got.
func open_course(id: String) -> bool:
	if not courses.select(id):
		return false
	var where := course().site_id
	if sites.has(where):
		sites.select(where)
	selected_gate = 0
	_changed()
	return true


func _next_course_name() -> String:
	return "Course %d" % (courses.ids().size() + 1)


## Where this course is, in metres above sea level. A NEW `AirDensity` rather than a mutated one:
## `AirDensity` clamps in its constructor, so building a fresh one is what applies the domain
## guard, and assigning straight to `elevation_m` would let a hand-driven caller put 10^9 m into
## the barometric formula — NaN, and then "nan g" on the stats panel.
func set_field_elevation_m(elevation_m: float) -> void:
	var here := site()
	if here == null:
		return
	here.elevation_m = AirDensity.new(elevation_m, 0.0).elevation_m
	_changed()


## How warm it is — NOT where the course is. The temperature is what you switch while holding the
## place and the route still (§3.1), so this selects the calm conditions set at the temperature
## typed; `at_temperature()` finds one before it makes one.
func set_field_temperature_c(temperature_c: float) -> void:
	var chosen := conditions.at_temperature(AirDensity.new(0.0, temperature_c).temperature_c)
	conditions.select(chosen.conditions_id)
	_changed(true)


## The gust process's settling time, onto the SELECTED conditions and then to disk — the same
## shape `set_field_temperature_c` above has, and for the same reason: it is weather, so it is
## saved under `_changed(true)` and nothing else rewrites `conditions.json`.
##
## Clamped to the field's own range here rather than trusted, because a headless caller drives
## this function directly and `Wind.update()` divides by `gust_tau_s + dt` — a zero or negative
## settling time is a filter coefficient greater than one, which is a gust process that diverges.
func set_field_gust_tau_s(p_gust_tau_s: float) -> void:
	var now := conditions.selected()
	if now == null:
		return
	now.gust_tau_s = clampf(p_gust_tau_s, MIN_GUST_TAU_S, MAX_GUST_TAU_S)
	_changed(true)


## The steady wind, onto the SELECTED conditions and then to disk — `set_field_gust_tau_s`'s shape
## and its reason. It edits the set in place rather than switching sets the way temperature does:
## temperature is how presets are FOUND (`at_temperature`), wind is a property OF the one you are on.
##
## Clamped here, not trusted, for the headless callers. A negative speed would be a wind blowing
## from the opposite bearing under the wrong label.
func set_field_wind_speed_mps(speed_mps: float) -> void:
	var now := conditions.selected()
	if now == null:
		return
	now.wind_speed_mps = clampf(speed_mps, 0.0, MAX_WIND_SPEED_MPS)
	_changed(true)


## The bearing the wind comes FROM, 0 = north, clockwise (conditions.gd). Wrapped into [0, 360), so
## a typed 360 or -90 is the bearing it names rather than a second spelling of it — two spellings
## of one bearing would be two lap fingerprints for one day's wind.
func set_field_wind_from_deg(from_deg: float) -> void:
	var now := conditions.selected()
	if now == null:
		return
	now.wind_from_deg = fposmod(from_deg, 360.0)
	_changed(true)


## The gust amplitude — the figure §4.3 says matters more than the steady wind. Not hashed into the
## lap fingerprint (gate_course.gd), so typing one never retires a best lap.
func set_field_gustiness_mps(gustiness_mps: float) -> void:
	var now := conditions.selected()
	if now == null:
		return
	now.gustiness_mps = clampf(gustiness_mps, 0.0, MAX_GUSTINESS_MPS)
	_changed(true)


## HOW WIDE THE FIELD IS, and the preview redraws from the same description `height_at` answers
## over. `Terrain.shaped` rebuilds the block rather than assigning a member, so the shape's own
## dims come with it and nothing here has to know which keys a bowl has.
func set_site_width_m(width_m: float) -> void:
	_resize_site(clampf(width_m, MIN_SITE_DIM_M, MAX_SITE_DIM_M), -1.0)


func set_site_length_m(length_m: float) -> void:
	_resize_site(-1.0, clampf(length_m, MIN_SITE_DIM_M, MAX_SITE_DIM_M))


func _resize_site(width_m: float, length_m: float) -> void:
	var here := site()
	if here == null:
		return
	var was := here.terrain
	var next := Terrain.shaped(was.shape,
		was.width_m if width_m < 0.0 else width_m,
		was.length_m if length_m < 0.0 else length_m,
		was.dims.duplicate(true), was.center_x_m, was.center_z_m)
	here.terrain = next
	_changed()


## The air the field is flown in: the site's elevation and the selected conditions' temperature,
## composed by the one function that knows which two typed facts the density comes from (F2).
func air() -> AirDensity:
	return AirDensity.compose(site(), conditions.selected())


# ---------------------------------------------------------------------------
# Repaint
# ---------------------------------------------------------------------------

## Everything on screen, from whatever the libraries now say. One function rather than five, for
## `LabScreen.set_air`'s reason: a repaint that updated the panels and not the world would leave a
## picture of one field under a description of another.
func refresh() -> void:
	selected_gate = clampi(selected_gate, 0, maxi(course().gates.size() - 1, 0))
	_fill_lists()
	_refresh_world()
	_refresh_panels()
	_render_controls()


## EVERY EDIT LANDS HERE: the world back to disk, then everything on screen re-read from it.
##
## `p_weather_changed` IS NOT A CONVENIENCE FLAG. The conditions file is written only by the one
## edit that touches the weather. Without it, dragging a gate rewrites a file that edit never
## looked at — and on a fresh install the FIRST gate drag materialises a `conditions.json` holding
## a `Standard` row nobody authored. `RoomHost._init` refuses exactly this, and a room doing the
## reverse one door over would be the same rule broken from the other side.
func _changed(p_weather_changed := false) -> void:
	courses.put(course())
	courses.save(save_path)
	sites.save(sites_path)
	if p_weather_changed:
		conditions.save(conditions_path)
	refresh()
	course_changed.emit()


## The room writing its own controls from the model. Under `_updating`, so a programmatic move of a
## Range does not come back as the builder having typed something.
func _render_controls() -> void:
	if name_field == null:
		return
	name_field.text = course().course_name
	# The last course cannot be deleted — there has to be somewhere to fly — so the button says so
	# by being unavailable rather than by refusing after the fact.
	_delete_button.disabled = courses.ids().size() <= 1

	var here := site()
	var now := air()
	_updating = true
	elevation_field.value = now.elevation_m
	temperature_field.value = now.temperature_c
	if here != null:
		width_field.value = clampf(here.extent().x, MIN_SITE_DIM_M, MAX_SITE_DIM_M)
		length_field.value = clampf(here.extent().y, MIN_SITE_DIM_M, MAX_SITE_DIM_M)
	# The settling time is a field of the SELECTED conditions now, so switching temperature
	# switches which record this control is showing — it has to be re-read here like the rest, or
	# the SpinBox would keep displaying the previous set's number.
	if gust_tau_field != null:
		gust_tau_field.value = clampf(gust_tau_s, MIN_GUST_TAU_S, MAX_GUST_TAU_S)
	# The same re-read, for the same reason: switching temperature can switch which set these show.
	var weather := conditions.selected()
	if wind_speed_field != null and weather != null:
		wind_speed_field.value = weather.wind_speed_mps
		wind_from_field.value = weather.wind_from_deg
		gustiness_field.value = weather.gustiness_mps
	_updating = false


## THE LATCH IS CLEARED BY THE CALLER, NOT BY THE BODY, and that split is the whole point of this
## two-function shape. A GDScript runtime error aborts only the function it is raised in and lets
## the CALLER resume — the same fact `tools/run_one_suite.gd`'s `_call_run` is built on. With the
## `_filling = false` inside the body, an abort raised IN THE BODY left the latch stuck `true` for
## the life of the room, and `choose_site`/`choose_course` early-return on it, so the rail stopped
## responding to clicks. Nothing raised that a check could see, and nothing logged but a
## SCRIPT ERROR in a green run.
##
## BE PRECISE ABOUT WHICH ABORT, because the final review was not and it matters: an abort inside
## a function the body CALLS — `courses_of_selected_site()`, the null-site case — never latched
## anything, since the callee absorbs its own abort and the body resumes. Measured, by mutation.
## The ones that latch are the ones raised in the body's own frame. This split covers those, and
## it covers the ones nobody has thought of yet, which is the point of doing it structurally
## rather than guarding each dereference. Do not move `_filling = false` back into
## `_fill_lists_body()`.
func _fill_lists() -> void:
	_filling = true
	_fill_lists_body()
	_filling = false


func _fill_lists_body() -> void:
	site_list.clear()
	# Ruling 19 again, on both halves: `selected()` answers null for a library that has none, and
	# the id is only ever compared, never needed. An empty string matches nothing, so a library
	# with no selection fills the list and highlights no row — which is the truth.
	var selected_site := sites.selected()
	var selected_site_id := selected_site.site_id if selected_site != null else ""
	var site_ids := sites.ids()
	for i in site_ids.size():
		var id := str(site_ids[i])
		site_list.add_item(sites.site(id).site_name)
		if id == selected_site_id:
			site_list.select(i)

	course_list.clear()
	var selected_course := courses.selected()
	var selected_course_id := selected_course.course_id if selected_course != null else ""
	var here := courses_of_selected_site()
	for i in here.size():
		var id := str(here[i])
		course_list.add_item(courses.course(id).course_name)
		if id == selected_course_id:
			course_list.select(i)


func _refresh_world() -> void:
	# A SITE THAT IS NOT THERE IS FLAT AT ZERO, not a dereference. A library built in code has no
	# selected id, and `here.terrain` written inline would abort this function — leaving every line
	# after it silently undone, which is a room that stopped drawing rather than one that opened
	# somewhere flyable. `site_terrain()` is the one guard; nothing below re-states it.
	var here := site()
	var terrain := site_terrain()
	var obstacles: Array[Obstacle] = here.obstacles if here != null else ([] as Array[Obstacle])
	# THE PREVIEW IS DRAWN THROUGH `TerrainMesh`, WHICH IS LOAD-BEARING NOW RATHER THAN TIDY.
	# The moment a builder can type a dimension, this screen is the one place a "see one thing, fly
	# another" divergence would show — while they are sculpting the very thing it would lie about.
	# F5's rule is that the mesh and `height_at` come from ONE description, and this is that rule's
	# only enforcement: never a PlaneMesh, never a second grid.
	_terrain.mesh = TerrainMesh.build_mesh(terrain, obstacles)

	renderer.course = course()
	renderer.highlight_index = selected_gate
	renderer.rebuild()

	_place_silhouette()

	# The pivot sits on the middle of the ground, so the camera swings around the SITE and not
	# around the world origin — which is metres away for any site the migration sized around a
	# course that was laid out off-centre (F1).
	var centre := terrain.center() if terrain != null else Vector2.ZERO
	_orbit.position = Vector3(centre.x, ground_height_at(centre.x, centre.y), centre.y)
	_orbit.rotation = Vector3(-_elevation_rad, _azimuth_rad, 0.0)
	# Parked out along the pivot's +Z with no rotation of its own, `LabScreen`'s arrangement and
	# for its reason: a camera looks down its own -Z, so from there it already points back at the
	# pivot, for every rotation, with no look_at that could drift.
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, camera_distance_m()))


## The footprint, at the start line, at the size the fitted aircraft actually is.
##
## `Build.airframe_span_m()` is the same number `CourseWarnings.RING_SMALLER_THAN_AIRCRAFT` compares
## a ring against, so what this draws and what that warns about cannot come apart. `start_position`
## is asked WITH the terrain, so the plate sits on a slope rather than through it.
func _place_silhouette() -> void:
	var span := footprint_m()
	_silhouette.visible = show_drone_silhouette and span > 0.0
	if not _silhouette.visible:
		return
	var box := BoxMesh.new()
	box.size = Vector3(span, PLATE_THICKNESS_M, span)
	_silhouette.mesh = box
	_silhouette.position = course().start_position(site_terrain())


## How wide the silhouette is, in metres — zero when there is no drone to draw.
##
## A function rather than a mesh read, because it is what the §11 question is ABOUT: whether the
## thing on screen is the real aircraft at real scale, or a marker at a convenient size.
func footprint_m() -> float:
	return 0.0 if build == null else build.airframe_span_m()


func _refresh_panels() -> void:
	(panel(PANEL_TITLES[0]) as SitePanel).show_site(site())
	(panel(PANEL_TITLES[1]) as CoursePanel).show_course(course(), self)
	# RE-EVALUATED ON EVERY EDIT, not computed once at open. `_changed()` comes through `refresh()`
	# and lands here, so a gate dragged into the hillside says so before the hand comes off it.
	_warnings.show_warnings(warnings())
	# On a dock page the head lists them, short + Why?; `show_warnings` shows the list again.
	_warnings.visible = _warnings.visible and dock_page == ""
	(panel(PANEL_TITLES[2]) as ConditionsPanel).show_conditions(conditions.selected(), air())


# ---------------------------------------------------------------------------
# Dragging a gate on the field (§2.4, moved here in F11)
# ---------------------------------------------------------------------------

func _on_viewport_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			var hit := gate_at(button.position)
			if hit >= 0:
				select_gate(hit)
				_dragging_gate = true
			else:
				_orbiting = true
		else:
			_dragging_gate = false
			_orbiting = false
		return

	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _dragging_gate:
		var ground: Variant = ground_point(motion.position)
		if ground != null:
			set_gate_ground_position(ground)
	elif _orbiting:
		set_orbit(
			_azimuth_rad + deg_to_rad(motion.relative.x * DRAG_DEG_PER_PIXEL),
			_elevation_rad + deg_to_rad(-motion.relative.y * DRAG_DEG_PER_PIXEL))


func set_orbit(azimuth_rad: float, elevation_rad: float) -> void:
	var limit := deg_to_rad(ELEVATION_LIMIT_DEG)
	_azimuth_rad = azimuth_rad
	_elevation_rad = clampf(elevation_rad, -limit, limit)
	if _orbit != null:
		_orbit.rotation = Vector3(-_elevation_rad, _azimuth_rad, 0.0)


## Composed by hand rather than read off the `Camera3D`, for `LabScreen.camera_world_transform`'s
## reason: this room is constructed before it is parented, and in the headless tests it is never
## parented at all, so the camera's own projection helpers have no viewport to answer about.
func camera_world_transform() -> Transform3D:
	return _orbit.transform * _camera.transform


## Which gate is under a point on the viewport, or -1. Picked by projecting each gate's centre back
## to the screen and taking the nearest within its own drawn radius, rather than by a physics
## query: there are no collision shapes in this room and adding some would mean a second geometry
## describing where the gates are.
func gate_at(local_position: Vector2) -> int:
	var point := _to_viewport(local_position)
	var camera_transform := camera_world_transform()
	var best := -1
	var best_distance := INF
	for i in course().gates.size():
		var gate: Dictionary = course().gates[i]
		var centre: Vector3 = gate["position"]
		# Behind the camera: unprojectable, and not something you can click on.
		if (camera_transform.affine_inverse() * centre).z > -_camera.near:
			continue
		var screen := _unproject(camera_transform, centre)
		var edge := _unproject(camera_transform,
			centre + camera_transform.basis.x * float(gate["radius"]))
		var distance := point.distance_to(screen)
		if distance <= screen.distance_to(edge) and distance < best_distance:
			best_distance = distance
			best = i
	return best


## Where a point on the viewport lands on the horizontal plane the selected gate stands on. Null
## when the ray never meets that plane — looking up at the sky from below the gate, which is a
## legitimate camera angle and not a place to drop a gate.
##
## THE PLANE IS THE GATE'S OWN WORLD HEIGHT, not y = 0 and not the ground: dragging across a plane
## at the gate's height is what keeps a ring 6 m up under the cursor instead of sliding away from
## it by however far the camera is tilted. Where it LANDS is then re-seated on the terrain by
## `set_gate_ground_position`, which is the one place that decides what a drop means.
func ground_point(local_position: Vector2) -> Variant:
	var gates := course().gates
	if gates.is_empty():
		return null
	var point := _to_viewport(local_position)
	var camera_transform := camera_world_transform()
	var origin := camera_transform.origin
	var direction := (_project_ray(camera_transform, point)).normalized()
	var plane := Plane(Vector3.UP, float(gates[selected_gate]["position"].y))
	var hit: Variant = plane.intersects_ray(origin, direction)
	return hit


## Control-local pixels to viewport pixels. The container stretches its `SubViewport` to whatever
## width the middle column has, so a click at the container's half-width is at the viewport's
## half-width and not at the same pixel.
func _to_viewport(local_position: Vector2) -> Vector2:
	var container_size := viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local_position
	return local_position * (Vector2(_viewport.size) / container_size)


func _unproject(camera_transform: Transform3D, p_world: Vector3) -> Vector2:
	var local := camera_transform.affine_inverse() * p_world
	var half_width := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var viewport_size := Vector2(_viewport.size)
	var ndc := Vector2(local.x, -local.y) / (-local.z * half_width)
	# KEEP_WIDTH: the horizontal half-angle is fixed and the vertical follows from the aspect.
	return (Vector2(ndc.x, ndc.y * (viewport_size.x / maxf(viewport_size.y, 1.0)))
		* 0.5 + Vector2(0.5, 0.5)) * viewport_size


func _project_ray(camera_transform: Transform3D, point: Vector2) -> Vector3:
	var viewport_size := Vector2(_viewport.size)
	var ndc := (point / viewport_size - Vector2(0.5, 0.5)) * 2.0
	var half_width := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var local := Vector3(
		ndc.x * half_width,
		-ndc.y * half_width * (maxf(viewport_size.y, 1.0) / viewport_size.x),
		-1.0)
	return camera_transform.basis * local


# ---------------------------------------------------------------------------
# The Lab dock pages (lab dock design §2-§4): one row's page at a time
# ---------------------------------------------------------------------------

## Which panel is each dock page's own.
const DOCK_PANELS := {"site": "Site", "course": "Course", "conditions": "Conditions"}

## How tall a rail list stands on a dock page, where the list no longer shares the rail with every
## other control and would otherwise stretch to the rail's full height over nothing. A drawing
## dimension (four rows of the theme's ItemList), not a claim about anything.
const DOCK_LIST_HEIGHT := 96.0


## The rail's controls, grouped by the page whose settings they are. Read off the built column —
## each field's row is its SpinBox's parent, each list's title the child before it.
func _collect_rail_groups() -> void:
	var column := site_list.get_parent()
	var title_of := func(list: Control) -> Control:
		return column.get_child(list.get_index() - 1) as Control
	var gate_buttons := column.get_node("GateButtons") as Control
	_rail_groups = {
		"site": [title_of.call(site_list), site_list, elevation_field.get_parent(),
			width_field.get_parent(), length_field.get_parent()],
		"course": [title_of.call(course_list), course_list, name_field,
			column.get_child(name_field.get_index() + 1), column.get_child(gate_buttons.get_index() - 1),
			gate_buttons],
		"conditions": [temperature_field.get_parent(), wind_speed_field.get_parent(),
			wind_from_field.get_parent(), gustiness_field.get_parent(), gust_tau_label,
			gust_tau_field.get_parent()],
		"all": [column.get_child(elevation_field.get_parent().get_index() - 1)],
	}


## The rail controls a dock page shows (its settings), in rail order. "" gives every control.
func rail_controls_for(page: String) -> Array:
	if page == "":
		var every: Array = []
		for child in site_list.get_parent().get_children():
			every.append(child)
		return every
	return (_rail_groups.get(page, []) as Array).duplicate()


## SHOWS ONE ROW'S PAGE: the rail keeps only that row's settings, that row's panel stands under
## them in the same column, and the head above the site carries the row's numbers and warnings.
##
## Stacked rather than side by side, and that is what lets the page stand beside the Lab's list at
## 1280: a rail, a panel column and a 500 px site do not fit the 976 px the list leaves, while one
## column and the site do (lab dock design §2 — "the list stays visible"). The other two panels are
## off the page, not moved: their facts are the other rows' pages.
##
## "" puts the whole room back — every control, all three panels in their own column.
func set_dock_page(page: String) -> void:
	if page != "" and not DOCK_PANELS.has(page):
		page = ""
	dock_page = page
	var column := site_list.get_parent() as Control
	var panels_column := _panels_scroll.get_child(0) as Control
	for title in PANEL_TITLES:
		var each := panel(str(title))
		var wanted_parent: Control = column if page != "" and DOCK_PANELS[page] == title \
			else panels_column
		if each.get_parent() != wanted_parent:
			each.get_parent().remove_child(each)
			wanted_parent.add_child(each)
			if wanted_parent == panels_column:
				panels_column.move_child(each, PANEL_TITLES.find(title))
	_panels_scroll.visible = page == ""
	var shown := rail_controls_for(page)
	for child in column.get_children():
		if child is SpecPanel:
			continue
		(child as Control).visible = shown.has(child)
	for list in [site_list, course_list]:
		(list as ItemList).size_flags_vertical = Control.SIZE_EXPAND_FILL if page == "" \
			else Control.SIZE_FILL
		(list as ItemList).custom_minimum_size.y = 44.0 if page == "" else DOCK_LIST_HEIGHT
	# The page's warnings are the head's, short + Why?; the Course panel's full list is the room's.
	(panel(PANEL_TITLES[1]) as CoursePanel).warnings.visible = page == ""
	page_view.set_head_visible(page != "")


## The open row's head: `row` from SectionRows.rows, `numbers` from SectionRows.page_numbers.
func show_dock_row(row: Dictionary, numbers: Array) -> void:
	page_view.show_item(row, numbers)


## How wide this room must be to show `site_floor` px of site beside its columns — the shell's
## question when it decides whether the Lab's list can stay open beside the page.
func width_for_site(site_floor: float) -> float:
	var row := page_view.get_parent() as Container
	var separation := float(row.get_theme_constant("separation"))
	var wanted := _rail.get_combined_minimum_size().x + separation \
		+ maxf(site_floor, page_view.get_combined_minimum_size().x)
	if _panels_scroll.visible:
		wanted += separation + _panels_scroll.get_combined_minimum_size().x
	return wanted


# ---------------------------------------------------------------------------
# The panels themselves
# ---------------------------------------------------------------------------

## §5.2's Site panel: name, shape, its typed dimensions, elevation datum, obstacle list — all five,
## in three rows and a title.
##
## **THE SUBJECT'S NAME IS IN THE TITLE, not in a row**, which is what every other `SpecPanel` in
## this app already does: `PartDetails` titles itself with the part's name and `AirframePanel` with
## the document's. These three were the odd ones out, spending a row to repeat their own heading.
## The role is kept beside the name ("SITE · FIELD") because, unlike Lab's, these panels have no
## tab above them to say which is which.
##
## **The shape and the dimensions share a row** for the same reason: they are one sentence about the
## ground ("flat · 120 × 120 m"), and §5.2 mandates that both are SHOWN, not that each has a row of
## its own. Four rows came out of the three panels between them, which is what made every row the
## design names fit above the dock's keepout — see `_build_panels`.
class SitePanel extends SpecPanel:
	var site: Site = null

	func _init() -> void:
		super([
			{"key": "ground", "label": "Ground"},
			{"key": "elevation", "label": "Elevation"},
			{"key": "obstacles", "label": "Obstacles"},
		])

	## No footer, only the width floor — see `PANEL_CONTENT_WIDTH`.
	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)

	func show_site(p_site: Site) -> void:
		site = p_site
		# RULING 19, RESTORED — and `row_text` two lines below has guarded the same object all
		# along, so this line was dereferencing a null the very next function handles.
		render_rows("Site · %s" % (p_site.site_name if p_site != null else "—"))

	func row_text(key: String) -> String:
		if site == null:
			return "—"
		match key:
			"ground": return "%s · %.0f × %.0f m" % [
				site.terrain.shape, site.extent().x, site.extent().y]
			"elevation": return "%.0f m" % site.elevation_m
			"obstacles": return "%d" % site.obstacles.size()
		return "—"


## §5.2's Course panel: the selected gate's height, heading and radius — the three things a drag
## cannot express — and the course's warnings underneath.
##
## **THE THREE FACTS ARE CONTROLS NOW, NOT READINGS (F11).** Until this slice they were three text
## rows here and three sliders in a room next door, which is two places describing one gate. The
## sliders replace the rows rather than joining them, and that is a budget as much as an argument:
## this column ships with 26 px of vertical slack at 1280x720, and three rows added on top of three
## rows kept would put the warning list §5.2 mandates into the dock's keepout. Each control is one
## line — name, slider, value — so the panel is the same height it was and says strictly more.
class CoursePanel extends SpecPanel:
	var course: GateCourse = null
	var gate_index := 0
	var warnings: WarningList
	## The room this panel edits. Set after construction, because `SpecPanel._init` builds the
	## footer before any caller can hand one over — so every handler reads it at CALL time.
	var room: FieldSystem = null
	var height_slider: HSlider
	var heading_slider: HSlider
	var radius_slider: HSlider
	var height_value: Label
	var heading_value: Label
	var radius_value: Label
	var _updating := false

	func _init() -> void:
		super([
			{"key": "gate", "label": "Selected gate"},
		])

	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)
		height_slider = _add_slider(root, "Height",
			FieldSystem.MIN_HEIGHT_M, FieldSystem.MAX_HEIGHT_M, FieldSystem.HEIGHT_STEP_M,
			func(v: float) -> void: room.set_gate_height_m(v))
		height_value = root.get_child(root.get_child_count() - 1).get_child(2) as Label
		heading_slider = _add_slider(root, "Heading",
			-180.0, 180.0, FieldSystem.HEADING_STEP_DEG,
			func(v: float) -> void: room.set_gate_heading_deg(v))
		heading_value = root.get_child(root.get_child_count() - 1).get_child(2) as Label
		radius_slider = _add_slider(root, "Radius",
			FieldSystem.MIN_RADIUS_M, FieldSystem.MAX_RADIUS_M, FieldSystem.RADIUS_STEP_M,
			func(v: float) -> void: room.set_gate_radius_m(v))
		radius_value = root.get_child(root.get_child_count() - 1).get_child(2) as Label

		warnings = WarningList.new(260.0)
		root.add_child(warnings)

	## One line: what it is, the control, what it reads. The value label is the row's third child,
	## which is what lets the caller pick it up without this helper returning two things.
	func _add_slider(root: VBoxContainer, label_text: String, minimum: float, maximum: float,
			step: float, on_change: Callable) -> HSlider:
		var row := HBoxContainer.new()
		row.name = "%sRow" % label_text
		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size = Vector2(62, 0)
		row.add_child(label)

		var slider := HSlider.new()
		slider.name = label_text
		slider.min_value = minimum
		slider.max_value = maximum
		slider.step = step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# `Range.value_changed` does not fire for a value set from code, so the model update lives
		# in a plain method this signal calls — which is also what keeps the room drivable from a
		# headless test with no sliders to move.
		slider.value_changed.connect(func(v: float) -> void:
			if not _updating and room != null:
				on_change.call(v))
		row.add_child(slider)

		var value := Label.new()
		value.theme_type_variation = &"ReadoutLabel"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(62, 0)
		row.add_child(value)

		root.add_child(row)
		return slider

	## `p_room` rather than a `Site`, because the height this panel shows is a height ABOVE THE
	## GROUND and only the room knows what the ground is — see `FieldSystem.set_gate_height_m`.
	func show_course(p_course: GateCourse, p_room: FieldSystem) -> void:
		course = p_course
		room = p_room
		gate_index = p_room.selected_gate if p_room != null else gate_index
		render_rows("Course · %s" % p_course.course_name)
		_render_controls()

	func _render_controls() -> void:
		if height_slider == null or room == null or course == null or course.gates.is_empty():
			return
		var index: int = clampi(gate_index, 0, course.gates.size() - 1)
		var gate: Dictionary = course.gates[index]
		var above := room.gate_height_above_ground_m(index)
		var heading := rad_to_deg(GateCourse.gate_heading_rad(gate))
		var radius := float(gate["radius"])

		_updating = true
		height_slider.value = above
		heading_slider.value = heading
		radius_slider.value = radius
		_updating = false

		height_value.text = "%.1f m" % above
		heading_value.text = "%.0f°" % heading
		radius_value.text = "%.2f m" % radius

	func row_text(key: String) -> String:
		if course == null or course.gates.is_empty():
			return "—"
		var index: int = clampi(gate_index, 0, course.gates.size() - 1)
		match key:
			"gate": return "%d of %d" % [index + 1, course.gates.size()]
		return "—"


## §5.2's Conditions panel: the four typed fields, the named set they belong to, and the derived ρ
## WITH ITS PERCENTAGE BELOW STANDARD.
##
## The percentage is a row of its own rather than a suffix on the density, because it is the number
## the builder actually reads: "16.3% down on sea level" means something to a pilot in a way that
## "1.0259 kg/m³" does not (`AirDensity.fraction_below_standard`'s own words). Two rows also means
## dropping it is a visibly missing row rather than a shorter string.
class ConditionsPanel extends SpecPanel:
	var conditions: Conditions = null
	var air: AirDensity = null

	func _init() -> void:
		super([
			# THE DERIVED PAIR SITS FIRST, above the typed fields it is derived from, and the order
			# is the screenshot's doing: at the bottom of a 190 px panel the percentage was the row
			# that got cut, and it is the row §5.2 names.
			{"key": "density", "label": "Air density"},
			{"key": "below", "label": "Below standard"},
			# THE WIND'S SPEED AND ITS DIRECTION SHARE A ROW — "4.0 m/s from 270°" is one fact
			# about the day, and §5.2 mandates that all four typed fields are SHOWN, not that each
			# has a row to itself. See `SitePanel` for the other rows this argument saved.
			{"key": "wind", "label": "Wind"},
			{"key": "gust", "label": "Gustiness"},
			{"key": "temperature", "label": "Temperature"},
		])

	## No footer, only the width floor — see `PANEL_CONTENT_WIDTH`.
	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)

	func show_conditions(p_conditions: Conditions, p_air: AirDensity) -> void:
		conditions = p_conditions
		air = p_air
		render_rows("Conditions · %s" % p_conditions.conditions_name)

	func row_text(key: String) -> String:
		if conditions == null or air == null:
			return "—"
		match key:
			"wind": return "%.1f m/s from %.0f°" % [
				conditions.wind_speed_mps, conditions.wind_from_deg]
			"gust": return "%.1f m/s" % conditions.gustiness_mps
			"temperature": return "%.0f °C" % conditions.temperature_c
			"density": return "%.4f kg/m³" % air.kgm3()
			"below": return "%.1f%%" % (air.fraction_below_standard() * 100.0)
		return "—"
