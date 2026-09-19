class_name Dock
extends PanelContainer
## ONE CENTRED CLUSTER AT THE BOTTOM — QC3 of the Quiet Canvas plan.
##
## It replaces three of the four things that used to float over the viewport: the system dropdown
## out of the top bar, the bottom-left tool cluster (Overlays, the chooser, Explode, X-ray, Measure,
## the status readout, the completeness ring) and the bottom-right Lab/Sim/Rooms cluster. Six system
## icons · divider · the tools · divider · Lab/Sim/Rooms.
##
## ## Why this is its own file
##
## `glass_shell.gd` is 2300 lines and owns the state of the whole screen. The dock is furniture:
## it knows how to lay nine icons out and how to say what it offers, and it decides NOTHING — every
## button here is wired by the shell, and the shell is still the only thing that knows what a
## system change means. Splitting it out is also what makes `action_names()` possible, which is the
## check that this slice lost no capability.
##
## ## The three things that made this risky, and what each one turned into here
##
## 1. **The window is 1280×720 and the blade room fits it with zero pixels of slack.** So the dock
##    does not get its own strip — it lives inside `GlassShell.BOTTOM_KEEPOUT`, the 76 px the
##    bottom-left and bottom-right clusters already stood in. Nothing above the dock moved, and
##    `OverlayTray`'s band, which is measured to `size.y - BOTTOM_KEEPOUT`, is the same band it was.
##    A dock that needed a 78th pixel would have had to come out of the room, and it does not.
##
## 2. **The status readout is prose and prose has no width.** `_refresh_status` writes
##    `"Propulsion  ·  4 of 10 systems decided"`, and the export paths write
##    `"Wrote /Users/…/exports/mount.stl"` — an absolute path, unbounded. A `Label` in an
##    `HBoxContainer` reports its text width as its minimum, so dropping one into a centred dock
##    hands the length of a filesystem path the power to push Lab and Sim off the screen. Measured:
##    with no guard at all the dock goes to **28220 px** on a 4000-character status, and
##    `layout_in`'s clamp does not save it — a `Container` in Godot expands to its combined minimum
##    whatever its offsets say, which is the same fact `test_shell_layout.gd` names about the Power
##    room's column.
##
##    There are THREE guards and each one is independently sufficient, which a mutation run proved
##    by removing them one at a time and watching the check stay green: `clip_text`,
##    `OVERRUN_TRIM_ELLIPSIS`, and the plain `Control` wrapper with `clip_contents` — a `Control` is
##    not a `Container`, so its minimum is its `custom_minimum_size` and nothing else and a child's
##    demands do not reach the row. Two of the three are properties of a Label and would go quietly
##    if someone restyled it; the wrapper is structural and is the one to keep. They are all three
##    kept rather than reduced to the wrapper alone, and the honest consequence is stated where it
##    matters: `test_dock`'s status check goes red only when ALL THREE are removed.
##
## 3. **An icon that needs a tooltip has failed.** Ten are drawn below as strokes, from
##    `LothalTheme`'s tokens, one weight. Where a glyph could not carry its meaning it is labelled
##    in words instead — see `ICON_FALLBACK_LABELS`, which exists so that failure is a named list
##    rather than a tooltip nobody reads.

## The six systems that get an icon, in the plan's order. The other four — Drone, Config, Ground
## kit, Field — are NOT dropped: they are behind `more_menu`. Six icons is what §3 of the plan
## specifies, and ten systems is what the dropdown it replaces offered, so the difference has to go
## somewhere visible or this slice quietly deletes four destinations. An overflow menu is the honest
## holding position; §8.1 of the plan is the open question that decides whether it stays.
const ICONED_SYSTEMS := ["Airframe", "Propulsion", "Power", "Control", "Video", "Printed"]

## The four tools of §3, in the order the old cluster offered them. `Overlays` is the only one with
## a feature behind it; the other three are slots and stay disabled, which is the state the old
## cluster shipped and is not this slice's to change.
const TOOLS := ["Overlays", "Explode", "X-ray", "Measure"]

## THE ICONS THAT DID NOT SURVIVE THE "no tooltip" RULE, named rather than quietly tooltipped.
##
## All three were drawn, rendered at 1280x720, cropped and looked at before they were given up on.
## The drawings are still in `DockIcon._draw` under their names, because the next person to try
## deserves to see what was tried.
##
## - **Printed.** A nozzle over three layer lines. At 18 px a trapezoid is a shape and not a nozzle:
##   the same crop read as a funnel, a filter and a loudspeaker. There is no settled glyph for "a
##   part you printed" the way there is for a battery.
## - **Explode.** Four arrows off a centre read as a spider — four 6 px arrowheads are four blobs.
##   The second attempt, three plates on a dashed axis, is the real exploded-view idiom and reads
##   cleanly as something else entirely: it is the standard SLIDERS icon, and a control that looks
##   like settings sitting in a row of tools is worse than a word.
## - **X-ray.** A circle with its hidden edges dashed read as a striped ball. The second attempt,
##   half solid and half outline, reads as the standard CONTRAST icon for the same reason — the
##   shape is already spoken for.
##
## - **Measure.** A dimension line with end ticks and three scale marks. This one SHIPPED as an
##   icon and should not have: cropped at 10x out of the 1280x720 window it is five short verticals
##   standing on a short baseline inside an 18 px box, and it reads as a text glyph — a comb, or a
##   Cyrillic Щ — rather than as a ruler. It was the least legible thing in the row while three
##   less-bad drawings had honestly fallen back to words. A sparser redraw (a diagonal rule, two
##   ticks) was considered and refused: it removes the marks that make the shape a comb and leaves
##   a slash, which is a picture of nothing. The rule below predicted this failure before the crop
##   did, and the crop only confirmed it.
##
## The pattern in the four failures is worth stating, because it is now a rule with a prediction
## behind it rather than an observation: every icon that survived is a picture of a PHYSICAL OBJECT
## the builder holds — a quad frame, a propeller, a cell, a board, a camera. Every one that failed
## is a picture of an OPERATION — print, explode, x-ray, measure — and the vocabulary for
## operations at this size is small and already owned by other software. A fifth operation icon
## proposed here should be assumed to fail until a crop says otherwise.
const ICON_FALLBACK_LABELS := {
	"Printed": "Print", "Explode": "Explode", "X-ray": "X-ray", "Measure": "Measure"}

## A square hit target, and the icon inside it. 30 px because `BOTTOM_KEEPOUT` is 76, the dock's
## margins take 16 and the glass leaves 60 for a row — a 30 px control clears it with the separator
## and the Lab/Sim buttons, which are taller.
const ICON_SIZE := 30.0
const ICON_BOX := 18.0
## One weight for every glyph. Two weights in one row reads as two icon sets.
const STROKE := 1.6

## What the status readout is allowed to take, whatever it says. See the header, point 2.
const STATUS_WIDTH := 232.0

## Fired when one of the ten systems is chosen, by icon or out of the overflow menu. The index is
## into the array the shell handed in, so the shell's `_select_system` takes it unchanged — the dock
## never learns what a system IS.
signal system_chosen(index: int)


## The three groups, exposed because the shell hides them independently: Sim retracts the systems
## and the tools and leaves Lab/Sim standing, Airframe retracts the tools alone, and the empty state
## retracts all three. They are the nodes the shell's `_dropdown_glass` / `_tools_glass` /
## `_bottom_right_glass` members now point at, so every retraction path that already existed keeps
## working against the same three names.
var systems_group: HBoxContainer
var tools_group: HBoxContainer
var mode_group: HBoxContainer

var system_buttons: Array[Button] = []
var more_menu: MenuButton
var overlays_button: Button
var overlays_menu: MenuButton
var status_label: Label
var lab_button: Button
var sim_button: Button
var room_menu: RoomMenu

var _systems: Array = []
## Which system index each entry of `_menu_indices` maps to — the overflow menu's ids are positions
## in its own popup, not positions in SYSTEMS, and conflating the two is how a four-entry menu ends
## up selecting the first four systems.
var _menu_indices: Array[int] = []


## `glass` is handed in rather than built here. `GlassShell._glass_stylebox()` is the surface every
## other cluster wears and there must be exactly one of it; asking for it as an argument also keeps
## this file from naming `GlassShell`, which would be a cycle — the shell already names `Dock`.
func _init(systems: Array, glass: StyleBox) -> void:
	_systems = systems
	add_theme_stylebox_override("panel", glass)
	# CENTRED, AND SIZED BY ITS CONTENT — the anchors put the dock's middle on the window's middle
	# and leave the offsets to `_layout()`, which the shell calls after every resize. A
	# `PRESET_BOTTOM_WIDE` dock would have been a bar, and a bar is the top strip this plan deletes.
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	add_child(row)

	systems_group = _group(row, "Systems")
	_build_systems()
	row.add_child(_divider())
	tools_group = _group(row, "Tools")
	_build_tools()
	row.add_child(_divider())
	mode_group = _group(row, "Modes")
	_build_modes()


## The six, then the overflow. Built off the array the shell handed in rather than off a private
## list of names, so a system added to `GlassShell.SYSTEMS` appears in the menu without an edit
## here — and cannot appear only in one of the two places a builder might look for it.
func _build_systems() -> void:
	for index in _systems.size():
		var system: Dictionary = _systems[index]
		var system_name := str(system["name"])
		if not ICONED_SYSTEMS.has(system_name):
			continue
		var button := DockIcon.new(system_name, str(ICON_FALLBACK_LABELS.get(system_name, "")))
		button.toggle_mode = true
		# The name IS the action name — see `action_names()`. Set here rather than derived from the
		# button's text, because the two icons that fall back to a word carry a SHORT word ("Print")
		# and a by-name check reading "Print" would not notice "Printed" had gone.
		button.name = system_name
		button.pressed.connect(func() -> void: system_chosen.emit(index))
		systems_group.add_child(button)
		system_buttons.append(button)

	# THE FOUR WITHOUT AN ICON. A menu rather than four more icons, because the plan says six and
	# because three of these four have no model behind them — an icon promising Config would be a
	# picture of a feature that does not exist, which is a stronger promise than a greyed menu row.
	more_menu = MenuButton.new()
	more_menu.name = "More systems"
	more_menu.text = "···"
	more_menu.flat = false
	more_menu.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var popup := more_menu.get_popup()
	for index in _systems.size():
		var system: Dictionary = _systems[index]
		var system_name := str(system["name"])
		if ICONED_SYSTEMS.has(system_name):
			continue
		var modelled: bool = not (system.get("rails", []) as Array).is_empty() \
			or not (system.get("panels", []) as Array).is_empty()
		# "soon" rather than disabled, which is the dropdown's own treatment carried over intact:
		# a builder who cannot see that Config exists cannot know the app has an opinion about it.
		# The id is this entry's position in `_menu_indices`, not the system's index. The popup emits
		# ids and `_menu_indices` is the translation; an `add_item(name, index)` here would have
		# worked by accident for exactly as long as the first four systems were the unmodelled ones.
		popup.add_item(system_name if modelled else "%s   soon" % system_name, _menu_indices.size())
		_menu_indices.append(index)
	popup.id_pressed.connect(func(id: int) -> void:
		# GUARDED, the same way `RoomMenu` guards its separators: an id this menu did not issue must
		# be a visible error rather than an index into `_menu_indices` that happens to land on a
		# system. Without it, an `add_item(name, system_index)` — the bug `_menu_indices` exists to
		# prevent — selects whatever system sits at that position and looks like it worked.
		if id < 0 or id >= _menu_indices.size():
			push_error("dock: overflow menu issued id %d, which names no system" % id)
			return
		system_chosen.emit(_menu_indices[id]))
	systems_group.add_child(more_menu)


func _build_tools() -> void:
	for tool_name in TOOLS:
		var button := DockIcon.new(tool_name, str(ICON_FALLBACK_LABELS.get(tool_name, "")))
		button.name = tool_name
		button.disabled = true
		button.tooltip_text = "%s is a frame slot — no overlay behind it yet." % tool_name
		tools_group.add_child(button)
		if tool_name != "Overlays":
			continue
		button.disabled = false
		button.toggle_mode = true
		button.tooltip_text = ("Analysis charts over the Lab. The chevron chooses which — "
			+ "five exist and the window decides how many fit at once.")
		overlays_button = button

		# The chooser, still a control of its own beside the toggle rather than folded into it.
		# Two actions, and the alternative already shipped: five charts up at once on a screen that
		# holds two.
		overlays_menu = MenuButton.new()
		overlays_menu.name = "Choose overlays"
		overlays_menu.text = "▾"
		overlays_menu.flat = false
		overlays_menu.custom_minimum_size = Vector2(20, ICON_SIZE)
		overlays_menu.tooltip_text = "Choose which analysis charts are up."
		tools_group.add_child(overlays_menu)

	# THE STATUS READOUT AND THE RING STAY WITH THE TOOLS, and this is a decision rather than a
	# leftover. Both are about the aircraft in the garage and both retract with the tools in Sim and
	# in Airframe; splitting them into a fifth floating cluster would have made this slice replace
	# three clusters with two, which is not the quieting the plan is for.
	#
	# THE READOUT IS CLIPPED THREE TIMES OVER, and header point 2 says which of the three to keep if
	# one ever has to go: this wrapper. A `Control` is not a `Container`, so its minimum size is its
	# `custom_minimum_size` and a child's demands never reach the row.
	var clip := Control.new()
	clip.name = "Status"
	clip.custom_minimum_size = Vector2(STATUS_WIDTH, ICON_SIZE)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tools_group.add_child(clip)

	status_label = Label.new()
	status_label.theme_type_variation = "SmallLabel"
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.add_child(status_label)


## Where the completeness ring goes — and it goes nowhere visible. Still handed in rather than
## constructed, because the ring is an inner class of `GlassShell` and naming it here would be the
## cycle `_init`'s comment avoids.
##
## THE RING IS ADOPTED AND HIDDEN, which is a deletion and is meant to read as one.
##
## Cropped at 8x out of the shipping window it is a blue arc with a gap and nothing inside it. It
## does have a track ring behind the filled segment, but the track is dark enough against the glass
## that the crop shows only the arc — so what the eye gets is the universal "something is in
## flight" shape, sitting in a toolbar, saying WAIT. It does not say "6 of 10 systems decided". The
## words immediately to its left say exactly that, in words, with the number: the ring was a second
## rendering of a sentence that was already there, and the second rendering was the one that lied.
## The dock also wants 1050 px of a 1280 window, so the 34 px it took were not free.
##
## HIDDEN RATHER THAN DROPPED ON THE FLOOR, and the distinction is the whole of this function.
## `GlassShell` builds the ring, keeps a member pointing at it and writes `fraction`, `tooltip_text`
## and `queue_redraw()` on it on every project change. Freeing it here would leave that member
## dangling — `_ring != null` is TRUE for a freed object in GDScript, so the shell's own guard would
## not catch it and the next project change would error. Parenting it hidden keeps every one of
## those writes valid and harmless, keeps the node owned so it is freed with the dock, and costs no
## layout: a hidden child of a `BoxContainer` is skipped and takes zero width. Re-showing it is one
## line, which is the point — this is a decision about what the dock SHOWS, not a demolition.
func adopt_ring(ring: Control) -> void:
	ring.name = "Completeness"
	ring.visible = false
	tools_group.add_child(ring)


func _build_modes() -> void:
	lab_button = Button.new()
	lab_button.name = "Lab"
	lab_button.text = "Lab"
	lab_button.toggle_mode = true
	lab_button.button_pressed = true
	lab_button.custom_minimum_size = Vector2(62, ICON_SIZE)
	lab_button.tooltip_text = "The garage. Choose parts, assemble, bench, tune."
	mode_group.add_child(lab_button)

	sim_button = Button.new()
	sim_button.name = "Sim"
	sim_button.text = "Sim"
	sim_button.toggle_mode = true
	sim_button.custom_minimum_size = Vector2(62, ICON_SIZE)
	sim_button.tooltip_text = ("The field. Flies what the garage built, and authors nothing "
		+ "except what the flight actually cost the pack.")
	mode_group.add_child(sim_button)

	room_menu = RoomMenu.new()
	room_menu.name = "Rooms"
	mode_group.add_child(room_menu)


## Keeps the six icons showing which system has focus, and is the reason they are toggles.
##
## Every one is cleared before the focused one is lit, rather than the previous one being unlit:
## `select_system_by_name` can be called before the dock has ever been clicked, and "unlight the
## last one I lit" has no answer on the first call.
func set_focused(index: int) -> void:
	for button in system_buttons:
		button.button_pressed = index >= 0 and index < _systems.size() \
			and str(_systems[index]["name"]) == button.name


## Puts the dock against the bottom edge of `window`, centred, at whatever width its content needs.
##
## Called by the shell on resize. The offsets are horizontal halves of the measured minimum because
## the anchors are both 0.5 — a centred control in Godot positions by offsets from the anchor, so
## "centred" is `-w/2 … +w/2` and not an alignment flag.
func layout_in(window: Vector2, margin: float, keepout: float) -> void:
	var wanted := get_combined_minimum_size()
	# CLAMPED TO THE WINDOW, and the clamp is not decoration. At 1280 the dock wants ~870 px and
	# fits; a builder on a 1024 window (`project.godot`'s minimum) is the case where it does not,
	# and an unclamped centred control does not get narrower — it hangs equally off both edges, so
	# the systems at one end and Sim at the other are the first things to leave the screen.
	var width := minf(wanted.x, maxf(window.x - margin * 2.0, 0.0))
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_bottom = -margin
	# THE TOP EDGE IS THE KEEPOUT'S, not the content's. `BOTTOM_KEEPOUT` is the strip the two old
	# clusters stood in and it is what `OverlayTray`'s band is measured against; a dock that sized
	# its own top edge to its content would make the tray's floor a function of a font, and the day
	# the row got one pixel taller the charts above it would not know.
	offset_top = -(keepout - margin)


## Every action this dock offers, by name, walked off the live tree.
##
## THIS IS THE CHECK THAT QC3 LOST NOTHING, and it is walked rather than listed for one reason: a
## constant array would keep answering "Measure" for a full minute after the Measure button was
## deleted, and a capability check that cannot notice a deletion is the test-that-cannot-fail this
## project keeps re-inventing. `test_dock.gd` compares this against a literal written from the three
## clusters being retired, so the list on the test's side is the specification and this side is the
## measurement.
##
## The Rooms menu contributes its six ids rather than the word "Rooms": the bottom-right cluster
## offered six destinations through it, and a check satisfied by an empty menu button would be the
## same failure one level down.
func action_names() -> PackedStringArray:
	var names := PackedStringArray()
	_collect(self, names)
	# THE ROOMS ARE READ OFF THE MENU THAT IS ACTUALLY IN THE DOCK, not off `RoomMenu.room_ids()`.
	# The first draft appended that static list unconditionally, and deleting `mode_group.add_child(
	# room_menu)` left all six room checks green — a mutation run confirmed it. A list that reports
	# six destinations for a control that is not on screen is the exact shape of a check that cannot
	# fail, and it was in the function whose entire job is to notice a deletion.
	var menu := _find_room_menu(self)
	if menu != null:
		var popup := menu.get_popup()
		for entry in RoomMenu.ENTRIES:
			for index in popup.item_count:
				if popup.is_item_separator(index):
					continue
				if str(popup.get_item_text(index)) == str(entry["label"]):
					names.append("room:%s" % entry["id"])
					break
	# The overflow menu's destinations, by the system's own name. Read off `_menu_indices`, which is
	# what the popup actually emits with, so a menu wired to the wrong indices reports the wrong
	# names rather than the right ones.
	for index in _menu_indices:
		names.append(str((_systems[index] as Dictionary)["name"]))
	return names


## The Rooms menu, wherever in the dock it has been put. Searched rather than read off `room_menu`,
## because the member would still hold a live node after the line that adds it to the tree was
## deleted — which is the deletion this is here to catch.
static func _find_room_menu(node: Node) -> RoomMenu:
	for child in node.get_children():
		if child is RoomMenu:
			return child as RoomMenu
		var found := _find_room_menu(child)
		if found != null:
			return found
	return null


static func _collect(node: Node, into: PackedStringArray) -> void:
	for child in node.get_children():
		# `RoomMenu` is a MenuButton and contributes its ids above; counting it here as well would
		# put a "Rooms" in the list that the specification side has no entry for.
		if child is RoomMenu:
			continue
		# A HIDDEN CONTROL IS NOT AN ACTION THIS DOCK OFFERS. Without this line the completeness
		# ring, which `adopt_ring` now parents hidden, would keep answering "Completeness" here
		# forever — a capability list that reports what nobody can see is the same
		# check-that-cannot-fail as the `RoomMenu.room_ids()` static list above, one node along.
		# `visible` and not `is_visible_in_tree()`: `action_names()` is called on a dock that has
		# never entered a tree, where the latter is false for every child and the list is empty.
		var shown: bool = not (child is CanvasItem) or (child as CanvasItem).visible
		if shown and (child is Button or child is MenuButton
				or str(child.name) in ["Status", "Completeness"]):
			into.append(str(child.name))
		_collect(child, into)


func _group(row: HBoxContainer, group_name: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = group_name
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", LothalTheme.SPACE_1)
	row.add_child(box)
	return box


func _divider() -> VSeparator:
	var line := VSeparator.new()
	line.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	return line


## One icon: a square button that draws a stroke figure instead of carrying a word.
##
## A `Button` rather than a bare `Control`, so focus, hover, the disabled state and the pressed
## state all come from the theme and the nine icons cannot drift apart from the two word buttons
## beside them. `_draw` paints OVER the stylebox, which is why the glyph colour is chosen from the
## button's own state below rather than from one token.
class DockIcon extends Button:
	var glyph: String
	## Empty for an icon that reads. A word for one that does not — see `ICON_FALLBACK_LABELS`.
	var fallback: String

	func _init(p_glyph: String, p_fallback: String = "") -> void:
		glyph = p_glyph
		fallback = p_fallback
		custom_minimum_size = Vector2(Dock.ICON_SIZE, Dock.ICON_SIZE)
		if fallback != "":
			text = fallback
			# Sized by its own word rather than by a hand-picked width. A fixed 44 px held "Print"
			# and clipped "Explode", which is the same constant-versus-measurement mistake the
			# inspector's `_fit_columns` exists because of, two letters at a time.
			custom_minimum_size = Vector2(0, Dock.ICON_SIZE)
			add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)

	func _draw() -> void:
		if fallback != "":
			return
		var ink := LothalTheme.TEXT_MAIN
		if disabled:
			ink = LothalTheme.TEXT_FAINT
		elif button_pressed:
			ink = LothalTheme.ACCENT
		var box := Rect2(
			(size - Vector2.ONE * Dock.ICON_BOX) * 0.5, Vector2.ONE * Dock.ICON_BOX)
		match glyph:
			"Airframe": _draw_airframe(box, ink)
			"Propulsion": _draw_propulsion(box, ink)
			"Power": _draw_power(box, ink)
			"Control": _draw_control(box, ink)
			"Video": _draw_video(box, ink)
			"Overlays": _draw_overlays(box, ink)
			"Explode": _draw_explode(box, ink)
			"X-ray": _draw_xray(box, ink)
			"Measure": _draw_measure(box, ink)

	## The aircraft from above: four arms out of a hub, a motor on each. The one shape in this row
	## that is unambiguously a multirotor, which is why it is the frame's icon and not a rectangle.
	func _draw_airframe(box: Rect2, ink: Color) -> void:
		var c := box.get_center()
		var arm := box.size.x * 0.44
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var tip: Vector2 = c + corner.normalized() * arm
			draw_line(c, tip, ink, Dock.STROKE, true)
			draw_arc(tip, box.size.x * 0.15, 0.0, TAU, 12, ink, Dock.STROKE, true)
		draw_rect(Rect2(c - Vector2.ONE * box.size.x * 0.13, Vector2.ONE * box.size.x * 0.26),
			ink, false, Dock.STROKE)

	## A two-blade propeller: a hub and two swept blades. Drawn as filled lenses rather than as
	## outlines, because an 18 px outline of a blade is two lines a pixel apart.
	func _draw_propulsion(box: Rect2, ink: Color) -> void:
		var c := box.get_center()
		var r := box.size.x * 0.46
		for sign_ in [1.0, -1.0]:
			var blade := PackedVector2Array()
			for step in 13:
				var t := float(step) / 12.0
				var angle: float = lerpf(-0.35, 0.35, t)
				blade.append(c + Vector2(cos(angle), sin(angle)) * r * sign_)
			for step in 13:
				var t := 1.0 - float(step) / 12.0
				var angle: float = lerpf(-0.35, 0.35, t)
				var radius: float = r * (0.30 + 0.25 * sin(PI * t))
				blade.append(c + Vector2(cos(angle), sin(angle)) * radius * sign_)
			draw_colored_polygon(blade, ink)
		draw_arc(c, box.size.x * 0.14, 0.0, TAU, 14, ink, Dock.STROKE, true)

	## A cell with a terminal. The most literal glyph here and deliberately so — a builder looking
	## for the pack is looking for a battery.
	func _draw_power(box: Rect2, ink: Color) -> void:
		var body := Rect2(box.position + Vector2(0.0, box.size.y * 0.26),
			Vector2(box.size.x * 0.82, box.size.y * 0.48))
		draw_rect(body, ink, false, Dock.STROKE)
		draw_rect(Rect2(Vector2(body.end.x + 1.0, body.position.y + body.size.y * 0.28),
			Vector2(box.size.x * 0.12, body.size.y * 0.44)), ink, true)
		# Two bars of charge, so the outline reads as a cell and not as a rounded rectangle.
		for i in 2:
			var x := body.position.x + body.size.x * (0.20 + 0.26 * float(i))
			draw_line(Vector2(x, body.position.y + 3.0), Vector2(x, body.end.y - 3.0),
				ink, Dock.STROKE, true)

	## The flight controller: a square board with a chip on it and a mounting hole in each corner.
	##
	## THE HOLES SIT IN THE CORNERS AND NOT INSET, which is the whole difference between this glyph
	## and a die face — the first drawing put them at 22% of the board and the screenshot read as a
	## four-pip domino. Pushed out to the corner radius they read as the 30.5 mm pattern, which is
	## the thing a builder measures an FC by, and the chip in the middle is what makes the outline
	## a board rather than a frame.
	func _draw_control(box: Rect2, ink: Color) -> void:
		var board := box.grow(-box.size.x * 0.06)
		draw_rect(board, ink, false, Dock.STROKE)
		var inset := board.size.x * 0.11
		for corner in [Vector2(inset, inset), Vector2(board.size.x - inset, inset),
				Vector2(inset, board.size.y - inset),
				Vector2(board.size.x - inset, board.size.y - inset)]:
			draw_arc(board.position + corner, 1.1, 0.0, TAU, 8, ink, Dock.STROKE, true)
		draw_rect(Rect2(board.get_center() - Vector2.ONE * board.size.x * 0.20,
			Vector2.ONE * board.size.x * 0.40), ink, true)

	## A camera: a body, a lens and the lens hood an FPV cam has. Drawn side-on rather than
	## front-on, because front-on is a circle in a square and so is half the icon set.
	func _draw_video(box: Rect2, ink: Color) -> void:
		var body := Rect2(box.position + Vector2(0.0, box.size.y * 0.22),
			Vector2(box.size.x * 0.62, box.size.y * 0.56))
		draw_rect(body, ink, false, Dock.STROKE)
		# The lens, as a truncated cone off the right-hand face.
		var top := Vector2(body.end.x, body.position.y + body.size.y * 0.22)
		var bottom := Vector2(body.end.x, body.end.y - body.size.y * 0.22)
		var far_top := Vector2(box.end.x, box.position.y + box.size.y * 0.10)
		var far_bottom := Vector2(box.end.x, box.end.y - box.size.y * 0.10)
		draw_line(top, far_top, ink, Dock.STROKE, true)
		draw_line(bottom, far_bottom, ink, Dock.STROKE, true)
		draw_line(far_top, far_bottom, ink, Dock.STROKE, true)

	## Stacked sheets — the standing idiom for layers, and an overlay is a sheet over the model.
	func _draw_overlays(box: Rect2, ink: Color) -> void:
		var card := Vector2(box.size.x * 0.72, box.size.y * 0.56)
		draw_rect(Rect2(box.position, card), ink, false, Dock.STROKE)
		draw_rect(Rect2(box.end - card, card), ink, false, Dock.STROKE)

	## An assembly pulled apart: three plates, spaced, on a common axis.
	##
	## NOT four arrows off a centre, which is what this drew first. Four 6 px arrowheads at 18 px
	## are four blobs, and the screenshot read as a spider rather than as motion — the shape said
	## "something radiates" and not "the stack comes apart". Three plates on a dashed axis is the
	## standing exploded-view idiom and it survives the size, because it is made of straight lines
	## at one spacing and nothing in it is smaller than the stroke.
	func _draw_explode(box: Rect2, ink: Color) -> void:
		var c := box.get_center()
		# The axis first, dashed, so the plates read as separated along it rather than as a list.
		for d in 5:
			var y0: float = box.position.y + box.size.y * (float(d) / 5.0)
			draw_line(Vector2(c.x, y0), Vector2(c.x, y0 + box.size.y * 0.12), ink, 1.0, true)
		for i in 3:
			var y: float = box.position.y + box.size.y * (0.12 + 0.38 * float(i))
			var half: float = box.size.x * (0.46 - 0.10 * float(i))
			draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), ink, Dock.STROKE, true)

	## Seeing inside a solid: one shape, half of it drawn as skin and half as the outline it would
	## have if the skin were not there.
	##
	## NOT a circle with dashed verticals inside it, which is what this drew first and which read
	## as a striped ball. The half-solid/half-outline pair is the idiom that carries "the same
	## object, transparent" at any size, because the two halves are the SAME circle and the reader
	## gets the comparison for free rather than having to infer it from texture.
	func _draw_xray(box: Rect2, ink: Color) -> void:
		var outer := box.grow(-box.size.x * 0.06)
		var c := outer.get_center()
		var r := outer.size.x * 0.5
		draw_arc(c, r, 0.0, TAU, 28, ink, Dock.STROKE, true)
		# The solid half, as a filled half-disc. Drawn as a polygon rather than with a wide arc,
		# because a filled half-disc has a straight diameter and an arc of width r does not.
		var half := PackedVector2Array([c + Vector2(0.0, -r)])
		for step in 15:
			var angle: float = lerpf(-PI * 0.5, PI * 0.5, float(step) / 14.0)
			half.append(c + Vector2(cos(angle), sin(angle)) * r)
		half.append(c + Vector2(0.0, r))
		draw_colored_polygon(half, ink)

	## A dimension line with end ticks and a scale above it — a ruler, not a tape. IT IS NOT A
	## RULER AT 18 px: five verticals on a baseline read as a comb or a text glyph, which is why
	## `Measure` is in `ICON_FALLBACK_LABELS` and this never runs. Kept, like the other three, so
	## the next person to try can see what was tried rather than draw it again.
	func _draw_measure(box: Rect2, ink: Color) -> void:
		var y := box.position.y + box.size.y * 0.68
		draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), ink, Dock.STROKE, true)
		for x in [box.position.x, box.end.x]:
			draw_line(Vector2(x, y - box.size.y * 0.22), Vector2(x, y + box.size.y * 0.16),
				ink, Dock.STROKE, true)
		for i in 3:
			var x := box.position.x + box.size.x * (0.25 + 0.25 * float(i))
			draw_line(Vector2(x, y), Vector2(x, y - box.size.y * 0.30), ink, Dock.STROKE, true)
