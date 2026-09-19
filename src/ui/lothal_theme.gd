class_name LothalTheme
extends RefCounted
## Lothal single theme provider (Deliverable 2).
## Built entirely in GDScript code so visual constants and styling are fully diffable.
##
## VISUAL PASS, 2026-09-19. The previous version was a competent dark theme and read as a default
## one, for three reasons that are worth naming because they are the reasons ANY dark app reads as
## unfinished:
##
##   1. It set a font SIZE and never a font, so every label was Godot's fallback face.
##   2. Every surface was separated from its neighbour by all three of a fill step, a 1 px grey
##      border and nothing else — no elevation. A panel sitting on a panel therefore read as a box
##      inside a box rather than as a card above a surface.
##   3. The widgets nobody styled (ItemList, OptionButton, LineEdit, ScrollBar, Tree, separators)
##      kept the engine's own look, and those are most of the pixels in a parts picker.
##
## What replaced it: a real system face, ONE hairline expressed as white-at-low-alpha rather than a
## grey that must be re-picked per surface, and depth carried by a shadow so that "floating glass"
## — which is what §5 of CONTINUE-HERE.md asks the shell to be — is actually what the panels do.
##
## The spacing scale and the type scale are UNCHANGED. Both were argued for in comments below and
## neither argument is about polish; re-deriving them here would be throwing away a decision to
## make a different one look tidier.

# Palette (named by role)
#
# The base is deeper and very slightly blue. Both are in service of the same thing: a translucent
# panel only reads as glass if what is behind it is darker than the panel, and a neutral grey
# behind a neutral grey is the flattest arrangement available.
const SURFACE_BASE := Color(0.055, 0.062, 0.078)

## The ordinary panel, and it is OPAQUE. It was translucent for one draft and that was wrong:
## `glass_shell.gd:_glass_panel` says in its own comment that "the ordinary panels inside the
## inspector must stay opaque, or text lands on text", and the shell already applies its own
## GLASS_ALPHA to these same RGB values for the floating clusters. Translucency is the SHELL's
## decision about a cluster, not this file's decision about every panel in the app.
const PANEL_BG := Color(0.145, 0.160, 0.195)

## Nested content that should feel INSET rather than stacked — a list well inside a picker.
const PANEL_SUNKEN := Color(0.085, 0.094, 0.115, 0.72)

## One hairline, as white at low alpha rather than a grey. A fixed grey has to be re-chosen for
## every background it might sit on; an alpha does the right thing on all of them.
const BORDER := Color(1.0, 1.0, 1.0, 0.075)
const BORDER_STRONG := Color(1.0, 1.0, 1.0, 0.14)
const BORDER_FOCUS := Color(0.36, 0.74, 1.0)

## Depth. A panel that floats has a shadow; the previous theme had none anywhere, which is why the
## floating clusters read as painted-on rectangles.
const SHADOW := Color(0.0, 0.0, 0.0, 0.42)
const SHADOW_SIZE := 18
const SHADOW_OFFSET := Vector2(0, 5)

const TEXT_MAIN := Color(0.92, 0.935, 0.96)
const TEXT_MUTED := Color(0.56, 0.60, 0.67)
const TEXT_FAINT := Color(0.40, 0.44, 0.50)

const ACCENT := Color(0.36, 0.74, 1.0)
## The accent at the weight a fill wants rather than the weight a line wants. Selected rows and
## pressed states use this; using ACCENT itself as a fill under body text fails contrast.
const ACCENT_FILL := Color(0.36, 0.74, 1.0, 0.16)
const ACCENT_DIM := Color(0.36, 0.74, 1.0, 0.38)

const WARNING := Color(1.0, 0.74, 0.32)
const DANGER := Color(1.0, 0.42, 0.36)
const SUCCESS := Color(0.38, 0.85, 0.58)

# Corner radii. The old theme used 4 everywhere, which is the radius that reads as neither soft nor
# sharp — large enough to see, too small to look chosen. Panels are rounder than the controls
# inside them, which is the ordinary rule and the one that makes nesting look deliberate.
const RADIUS_PANEL := 10
const RADIUS_CONTROL := 7
const RADIUS_SMALL := 5

# Spacing Scale
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24
const SPACE_8 := 32

# Type Scale
#
# TIGHTENED ONE STEP, DELIBERATELY. The old scale was written for the eight-tab shell, where a
# screen held one panel and a big viewport; the glass shell puts a top bar, a toolbar, a property
# strip and a four-tab inspector on screen at once, and at the old sizes the chrome outweighed the
# drawing it was wrapped around. The RATIOS are unchanged — this is the same scale a step down, not
# a redesign — and the two readout sizes are left alone, because a hero readout is the number the
# screen exists to show and shrinking it would be shrinking the content to make room for the frame.
const FONT_SIZE_SMALL := 11
const FONT_SIZE_BODY := 13
const FONT_SIZE_SUBTITLE := 16
const FONT_SIZE_TITLE := 18
const FONT_SIZE_HERO := 30

static var _cached_theme: Theme = null


## The interface face. A SystemFont rather than a shipped .ttf, because every platform Lothal
## targets already carries a good one and a bundled file would be a licence, a download and a
## binary in the repo to get a worse result on macOS than SF already gives. The list is ordered
## by platform and ends at a generic so a Linux box with none of them still gets a real face
## rather than the engine fallback.
static func ui_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"SF Pro Text", "SF Pro Display", "Helvetica Neue",  # macOS
		"Segoe UI Variable Text", "Segoe UI",               # Windows
		"Inter", "Noto Sans", "DejaVu Sans", "sans-serif",  # Linux / fallback
	])
	f.fallbacks = symbol_fallbacks()
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


## The glyph fallback, and a screenshot is what proved it was needed. The chrome uses geometric
## glyphs for its affordances — the overlay chooser's label is literally "▾" (U+25BE) — and
## SF Pro Text does not carry them. The moment a real interface face was set, Godot substituted a
## dot, so the shell shipped a chevron that had silently become a bullet.
##
## This has to be a `fallbacks` entry and NOT more names in `font_names`: Godot resolves
## `font_names` to the first family that EXISTS and then stops, so a symbol family listed after
## SF Pro on a Mac is never consulted. Per-glyph substitution only walks `Font.fallbacks`.
##
## And for the same reason each family gets its OWN SystemFont. A single SystemFont holding six
## symbol families is still one resolved family — on macOS that is "Apple Symbols", which turned
## out not to carry U+25BE either, so the first attempt at this fix changed nothing and the
## screenshot still showed a bullet. A list of fonts is walked; a list of names is not.
static func symbol_fallbacks() -> Array[Font]:
	var families := [
		"Menlo", "Apple Symbols", "STIXGeneral", "Arial Unicode MS",  # macOS
		"Segoe UI Symbol", "Segoe UI",                                # Windows
		"Noto Sans Symbols 2", "DejaVu Sans",                         # Linux
	]
	var fonts: Array[Font] = []
	for family in families:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([family])
		fonts.append(f)
	return fonts


## The numeric face. Every readout in the app is a number that changes while you watch it, and a
## proportional face makes a changing number jitter sideways.
static func mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"SF Mono", "Menlo", "Cascadia Mono", "Consolas", "Monaco",
		"JetBrains Mono", "DejaVu Sans Mono", "Courier New", "monospace",
	])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


static var _draw_font_cached: SystemFont = null
static var _draw_mono_cached: SystemFont = null
static var _card_plate_cached: StyleBoxFlat = null


## The face for hand-drawn Controls, and it is CACHED because `_draw` runs every frame — building
## a SystemFont per frame would resolve a family per frame.
##
## Ten Controls in this app draw their own text (every chart, every overlay card, the frame plan
## editor, the shelf chips) and every one of them called `ThemeDB.fallback_font`. That was
## invisible while the theme also had no font: the chrome and the charts agreed by both being the
## engine's face. The moment a real face was set, the charts were the only things left in the old
## one, and a screenshot of the Propulsion room showed two typefaces on one screen.
static func draw_font() -> Font:
	if _draw_font_cached == null:
		_draw_font_cached = ui_font()
	return _draw_font_cached


## The same, for the numbers on an axis.
static func draw_mono() -> Font:
	if _draw_mono_cached == null:
		_draw_mono_cached = mono_font()
	return _draw_mono_cached


## The backing plate of a hand-drawn card, so the five analysis overlays get the same corner and
## the same shadow as every other floating thing rather than a square `draw_rect`. Cached for the
## same reason as the font: `_draw` is a per-frame path.
static func card_plate() -> StyleBoxFlat:
	if _card_plate_cached == null:
		var box := glass_box(Color(0.06, 0.07, 0.09, 0.90), RADIUS_PANEL)
		box.border_color = BORDER
		_card_plate_cached = box
	return _card_plate_cached


static func get_theme() -> Theme:
	if _cached_theme == null:
		_cached_theme = _build_theme()
	return _cached_theme


## A floating surface: translucent fill, one hairline, a shadow. Everything that is supposed to
## hover over the viewport is built from this so that "floating" is one decision and not fifteen.
static func glass_box(fill: Color = PANEL_BG, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.shadow_color = SHADOW
	box.shadow_size = SHADOW_SIZE
	box.shadow_offset = SHADOW_OFFSET
	# Godot draws a stylebox's shadow OUTSIDE its rect without reserving room for it, so a panel
	# flush against a screen edge has its shadow clipped. That is fine and intended: the clusters
	# sit inset from the edges already.
	box.anti_aliasing = true
	return box


static func _build_theme() -> Theme:
	var theme := Theme.new()

	var ui := ui_font()
	var mono := mono_font()

	# Base font and size across every control. The FONT is the single largest visual change in this
	# file: the previous theme set only the size, so all non-readout text was the engine fallback.
	theme.default_font = ui
	theme.default_font_size = FONT_SIZE_BODY

	# --- Labels ---
	theme.set_color("font_color", "Label", TEXT_MAIN)

	# Label Type Variations
	theme.set_type_variation("ReadoutLabel", "Label")
	theme.set_font("font", "ReadoutLabel", mono)
	theme.set_font_size("font_size", "ReadoutLabel", FONT_SIZE_BODY)
	theme.set_color("font_color", "ReadoutLabel", TEXT_MAIN)

	theme.set_type_variation("HeroReadoutLabel", "Label")
	theme.set_font("font", "HeroReadoutLabel", mono)
	theme.set_font_size("font_size", "HeroReadoutLabel", FONT_SIZE_HERO)
	theme.set_color("font_color", "HeroReadoutLabel", TEXT_MAIN)

	theme.set_type_variation("SubHeroReadoutLabel", "Label")
	theme.set_font("font", "SubHeroReadoutLabel", mono)
	theme.set_font_size("font_size", "SubHeroReadoutLabel", 26)
	theme.set_color("font_color", "SubHeroReadoutLabel", TEXT_MAIN)

	theme.set_type_variation("MutedLabel", "Label")
	theme.set_font_size("font_size", "MutedLabel", FONT_SIZE_BODY)
	theme.set_color("font_color", "MutedLabel", TEXT_MUTED)

	theme.set_type_variation("SmallLabel", "Label")
	theme.set_font_size("font_size", "SmallLabel", FONT_SIZE_SMALL)
	theme.set_color("font_color", "SmallLabel", TEXT_MUTED)

	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", FONT_SIZE_TITLE)
	theme.set_color("font_color", "TitleLabel", TEXT_MAIN)

	theme.set_type_variation("WarnLabel", "Label")
	theme.set_font_size("font_size", "WarnLabel", FONT_SIZE_BODY)
	theme.set_color("font_color", "WarnLabel", WARNING)

	# --- Panel & PanelContainer ---
	#
	# NO BORDER, and that is the fix for the thing that made the old shell look amateur: almost
	# every panel in this app is nested inside a floating cluster, so a bordered panel drew a
	# rounded outline four pixels inside another rounded outline. Two concentric boxes is the
	# classic tell. Separation is carried by the fill step and a soft shadow instead, and the
	# radius is one step tighter than the cluster's so the nesting reads as deliberate.
	var panel_box := glass_box(PANEL_BG, RADIUS_CONTROL)
	panel_box.set_border_width_all(0)
	panel_box.shadow_size = 10
	panel_box.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	panel_box.shadow_offset = Vector2(0, 2)
	# SPACE_2, not SPACE_3, and the suite is why. A roomier panel margin looked better and pushed
	# the blade room's content column to y=683 in a 720 px window whose room ends at y=644 — it
	# collided with the Lab/Sim/Rooms cluster. Vertical air inside a panel is not free in this app;
	# it is spent against a fixed window. Horizontal air still is free, so the grid keeps its.
	panel_box.set_content_margin_all(SPACE_2)

	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("panel", "Panel", panel_box)

	# A panel with no chrome of its own, for content that is already inside one. Grouping boxes use
	# this instead of drawing a second border around the first.
	var flush_box := StyleBoxEmpty.new()
	theme.set_type_variation("FlushPanel", "PanelContainer")
	theme.set_stylebox("panel", "FlushPanel", flush_box)

	# A well: content that should read as recessed into the panel rather than stacked on it. The
	# parts list is the case this exists for.
	var sunken_box := StyleBoxFlat.new()
	sunken_box.bg_color = PANEL_SUNKEN
	sunken_box.border_color = BORDER
	sunken_box.set_border_width_all(1)
	sunken_box.set_corner_radius_all(RADIUS_CONTROL)
	sunken_box.set_content_margin_all(SPACE_1)
	theme.set_type_variation("SunkenPanel", "PanelContainer")
	theme.set_stylebox("panel", "SunkenPanel", sunken_box)

	# --- Buttons ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(1.0, 1.0, 1.0, 0.055)
	btn_normal.border_color = BORDER
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(RADIUS_CONTROL)
	btn_normal.anti_aliasing = true
	# A button is padded to be hittable, not to be large. SPACE_3 either side put about 24 px of air
	# around a four-character label, and a toolbar of fifteen of those is a toolbar that wraps onto
	# a second row in a window that had the width for one.
	btn_normal.content_margin_left = SPACE_3
	btn_normal.content_margin_right = SPACE_3
	btn_normal.content_margin_top = SPACE_2
	btn_normal.content_margin_bottom = SPACE_2

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(1.0, 1.0, 1.0, 0.11)
	btn_hover.border_color = BORDER_STRONG

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = ACCENT_FILL
	btn_pressed.border_color = ACCENT_DIM

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(1.0, 1.0, 1.0, 0.02)
	btn_disabled.border_color = Color(1.0, 1.0, 1.0, 0.035)

	var btn_focus := btn_normal.duplicate() as StyleBoxFlat
	btn_focus.bg_color = Color(0, 0, 0, 0)
	btn_focus.border_color = BORDER_FOCUS
	btn_focus.set_border_width_all(1)

	for cls in ["Button", "MenuButton", "OptionButton", "CheckButton", "CheckBox"]:
		theme.set_stylebox("normal", cls, btn_normal)
		theme.set_stylebox("hover", cls, btn_hover)
		theme.set_stylebox("pressed", cls, btn_pressed)
		theme.set_stylebox("disabled", cls, btn_disabled)
		theme.set_stylebox("focus", cls, btn_focus)
		theme.set_color("font_color", cls, TEXT_MAIN)
		theme.set_color("font_hover_color", cls, TEXT_MAIN)
		theme.set_color("font_pressed_color", cls, ACCENT)
		theme.set_color("font_focus_color", cls, TEXT_MAIN)
		theme.set_color("font_disabled_color", cls, TEXT_FAINT)

	# The compact button, for a dense workbench toolbar.
	#
	# This exists because of a measurement, not a preference. A real interface face is TALLER at the
	# same point size than the engine fallback the app used to draw with, and the blade room's
	# content column had no slack at all: at 1280x720 the column ran to y=683 against a room ending
	# at y=644 and collided with the Lab/Sim/Rooms cluster — the exact defect `test_shell_layout.gd`
	# was written for after W0.7. Roughly two thirds of the overrun was the ordinary button's new
	# vertical padding, and the rest was the face itself.
	#
	# The answer is NOT to take the padding back off every button in the app. A toolbar button and a
	# dialog button are different controls doing different jobs, and every tool this app is trying to
	# resemble draws the toolbar one tighter. So the comfortable padding stays the default, and a
	# workbench toolbar opts into this.
	var compact_normal := btn_normal.duplicate() as StyleBoxFlat
	compact_normal.content_margin_left = SPACE_2
	compact_normal.content_margin_right = SPACE_2
	compact_normal.content_margin_top = SPACE_1
	compact_normal.content_margin_bottom = SPACE_1
	var compact_hover := compact_normal.duplicate() as StyleBoxFlat
	compact_hover.bg_color = btn_hover.bg_color
	compact_hover.border_color = btn_hover.border_color
	var compact_pressed := compact_normal.duplicate() as StyleBoxFlat
	compact_pressed.bg_color = btn_pressed.bg_color
	compact_pressed.border_color = btn_pressed.border_color
	var compact_disabled := compact_normal.duplicate() as StyleBoxFlat
	compact_disabled.bg_color = btn_disabled.bg_color
	compact_disabled.border_color = btn_disabled.border_color

	theme.set_type_variation("CompactButton", "Button")
	theme.set_stylebox("normal", "CompactButton", compact_normal)
	theme.set_stylebox("hover", "CompactButton", compact_hover)
	theme.set_stylebox("pressed", "CompactButton", compact_pressed)
	theme.set_stylebox("disabled", "CompactButton", compact_disabled)

	# AND THE SAME TIGHTENING FOR A CHECKBUTTON, as a SECOND variation rather than by pointing a
	# CheckButton at `CompactButton`.
	#
	# A variation inherits from ONE base type, and `CompactButton`'s base is `Button`. A CheckButton
	# whose `theme_type_variation` is `CompactButton` therefore looks its styleboxes up through
	# `Button` and never reaches the `CheckButton` type at all — which is where the on/off switch
	# ICONS live. It would draw as a tight rectangle with a label and no switch in it: the one
	# control in the blade room's toolbar whose entire job is to show which way it is set, showing
	# nothing. So this variation is based on `CheckButton` and gets the compact boxes by copy.
	#
	# It is worth more pixels than a button is, and that is why it was the last thing in the way.
	# The toolbar is an `HFlowContainer`: the TALLEST control in a wrapped row sets that whole row's
	# height. A CheckButton is sized by its switch icon plus the stylebox, not by its text, so at
	# SPACE_2 padding it stood 36 px against the 28 px of its compact neighbours and held the entire
	# first row 8 px taller than anything in it needed.
	theme.set_type_variation("CompactCheckButton", "CheckButton")
	theme.set_stylebox("normal", "CompactCheckButton", compact_normal)
	theme.set_stylebox("hover", "CompactCheckButton", compact_hover)
	theme.set_stylebox("pressed", "CompactCheckButton", compact_pressed)
	theme.set_stylebox("disabled", "CompactCheckButton", compact_disabled)
	theme.set_stylebox("focus", "CompactCheckButton", btn_focus)

	# The accented button, for the one action a panel exists to offer.
	var primary_normal := btn_normal.duplicate() as StyleBoxFlat
	primary_normal.bg_color = ACCENT_FILL
	primary_normal.border_color = ACCENT_DIM
	var primary_hover := primary_normal.duplicate() as StyleBoxFlat
	primary_hover.bg_color = Color(0.36, 0.74, 1.0, 0.26)
	primary_hover.border_color = ACCENT
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", primary_normal)
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_color("font_color", "PrimaryButton", ACCENT)
	theme.set_color("font_hover_color", "PrimaryButton", TEXT_MAIN)

	# --- OptionButton / popup menus ---
	#
	# THE RULE, STATED ONCE AND OBEYED BY EVERY SURFACE BELOW THAT CARRIES TEXT: translucency belongs
	# to a floating cluster over the 3D viewport, never to a surface whose whole job is carrying text.
	# A menu, a tooltip and a dialog are all read-text-off surfaces, so all three are OPAQUE.
	#
	# This is the same mistake PANEL_BG's comment already records and it came back at alpha 0.98,
	# which sounds like nothing and is not: a screenshot of the open drone menu showed the frame
	# picker's labels legible straight through "New drone" and "Open…". 2% of a bright glyph on a dark
	# menu is still a readable glyph, because the eye reads contrast, not opacity. There is no alpha
	# between 0 and 1 that buys anything here — a menu is not hovering over the scene, it is a sheet
	# you read — so the alpha component simply goes away.
	var popup_box := glass_box(Color(0.125, 0.138, 0.168), RADIUS_CONTROL)
	popup_box.set_content_margin_all(SPACE_1)
	theme.set_stylebox("panel", "PopupMenu", popup_box)
	theme.set_color("font_color", "PopupMenu", TEXT_MAIN)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	theme.set_color("font_separator_color", "PopupMenu", TEXT_FAINT)
	theme.set_constant("v_separation", "PopupMenu", SPACE_1)

	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = ACCENT_FILL
	popup_hover.set_corner_radius_all(RADIUS_SMALL)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)

	# --- Text entry ---
	var input_box := StyleBoxFlat.new()
	input_box.bg_color = PANEL_SUNKEN
	input_box.border_color = BORDER
	input_box.set_border_width_all(1)
	input_box.set_corner_radius_all(RADIUS_CONTROL)
	input_box.content_margin_left = SPACE_2
	input_box.content_margin_right = SPACE_2
	# Vertical padding on a text field is charged to the same fixed window height as everything
	# else — see panel_box. SPACE_2 here put the blade room's column past the bottom cluster.
	input_box.content_margin_top = SPACE_1
	input_box.content_margin_bottom = SPACE_1
	input_box.anti_aliasing = true

	var input_focus := input_box.duplicate() as StyleBoxFlat
	input_focus.border_color = BORDER_FOCUS

	# SpinBox is NOT in this list, and that is the whole of the second defect. It was, and the entries
	# it got were inert: `Theme.set_stylebox` happily stores an item under any name, so `normal` on
	# `SpinBox` looked like it had worked while the engine never asked for it. A 4.7 SpinBox has no
	# `normal`, no `focus` and no `font_color` of its own — it is a LineEdit CHILD, which picks these
	# up from `LineEdit` below, plus a stepper the SpinBox draws itself from an entirely separate set
	# of items (`up_background`, `down_background`, the two separators, `up`/`down` icons and their
	# modulates, and four constants). Styling the field and leaving that set at the engine default is
	# exactly what a screenshot of the Airframe inspector showed: a rounded dark pill with two bare
	# chevrons floating outside it on the panel background, reading as a control come apart.
	for cls in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", cls, input_box)
		theme.set_stylebox("focus", cls, input_focus)
		theme.set_color("font_color", cls, TEXT_MAIN)
		theme.set_color("font_placeholder_color", cls, TEXT_FAINT)
		theme.set_color("caret_color", cls, ACCENT)
		theme.set_color("selection_color", cls, ACCENT_FILL)

	# --- SpinBox: the field and its stepper, made back into one control ---
	#
	# The rule the fix follows: a SpinBox should read as ONE rounded box with a divider in it, the way
	# every numeric field in the tools this app resembles does. Two things get it there.
	#
	# First, the GAP goes. `field_and_buttons_separation` ships at 2 px, so even a correctly coloured
	# stepper would sit two pixels of panel background away from its field — a seam is what made the
	# chevrons look detached in the first place, and painting the gap a different colour does not
	# close it. At 0 the two separator styleboxes have nowhere to draw, so they are set empty rather
	# than left to the engine's slabs.
	#
	# Second, the button backgrounds extend LEFT under the field. The field's right-hand corners are
	# rounded by RADIUS_CONTROL, so a button box butted flush against it leaves two crescent notches
	# of bare panel in the corners. `expand_margin_left` of exactly that radius slides the button fill
	# under the curve to fill them. The overlap is invisible: SpinBox draws its own stepper before its
	# LineEdit child, so the field's fill paints back over everything it covers, and what survives is
	# the crescents plus the field's own hairline reading as the divider the control wants anyway.
	# The outer corners are rounded on the two edges that are now the control's outer edge — top-right
	# on the up button, bottom-right on the down — so the silhouette closes as one pill.
	#
	# Everything here is the same fill, hairline and radius the field uses; no new value is invented.
	theme.set_constant("field_and_buttons_separation", "SpinBox", 0)
	theme.set_constant("buttons_vertical_separation", "SpinBox", 0)

	var step_up := StyleBoxFlat.new()
	step_up.bg_color = PANEL_SUNKEN
	step_up.border_color = BORDER
	step_up.set_border_width_all(1)
	step_up.border_width_left = 0  # the field's own right-hand hairline is already this line
	step_up.corner_radius_top_right = RADIUS_CONTROL
	step_up.expand_margin_left = RADIUS_CONTROL
	step_up.anti_aliasing = true

	var step_down := step_up.duplicate() as StyleBoxFlat
	step_down.corner_radius_top_right = 0
	step_down.corner_radius_bottom_right = RADIUS_CONTROL

	for state in ["", "_hovered", "_pressed", "_disabled"]:
		var up := step_up.duplicate() as StyleBoxFlat
		var down := step_down.duplicate() as StyleBoxFlat
		if state == "_hovered":
			up.bg_color = Color(1.0, 1.0, 1.0, 0.055)
			down.bg_color = up.bg_color
		elif state == "_pressed":
			up.bg_color = ACCENT_FILL
			down.bg_color = up.bg_color
		theme.set_stylebox("up_background" + state, "SpinBox", up)
		theme.set_stylebox("down_background" + state, "SpinBox", down)

	theme.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())

	# The chevrons themselves were the visible part of the defect, and they were bare engine white.
	# Muted at rest so the number is what you read, lit on hover, accented while held.
	for dir in ["up", "down"]:
		theme.set_color(dir + "_icon_modulate", "SpinBox", TEXT_MUTED)
		theme.set_color(dir + "_hover_icon_modulate", "SpinBox", TEXT_MAIN)
		theme.set_color(dir + "_pressed_icon_modulate", "SpinBox", ACCENT)
		theme.set_color(dir + "_disabled_icon_modulate", "SpinBox", TEXT_FAINT)

	# --- ItemList: the parts picker, and most of the pixels in the Lab ---
	#
	# Previously entirely unstyled, so it drew the engine's default striped rows with hairline
	# separators and a flat grey selection — the single most dated-looking thing on screen.
	var list_bg := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ItemList", list_bg)
	theme.set_color("font_color", "ItemList", TEXT_MAIN)
	theme.set_color("font_selected_color", "ItemList", TEXT_MAIN)
	theme.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))  # no row rules
	theme.set_constant("v_separation", "ItemList", SPACE_1)
	theme.set_constant("h_separation", "ItemList", SPACE_2)
	theme.set_constant("line_separation", "ItemList", 2)

	var row_selected := StyleBoxFlat.new()
	row_selected.bg_color = ACCENT_FILL
	row_selected.set_corner_radius_all(RADIUS_SMALL)
	row_selected.content_margin_left = SPACE_2
	row_selected.content_margin_right = SPACE_2
	row_selected.content_margin_top = SPACE_1
	row_selected.content_margin_bottom = SPACE_1
	row_selected.border_color = ACCENT_DIM
	row_selected.set_border_width_all(1)
	row_selected.anti_aliasing = true

	var row_hover := row_selected.duplicate() as StyleBoxFlat
	row_hover.bg_color = Color(1.0, 1.0, 1.0, 0.055)
	row_hover.border_color = Color(0, 0, 0, 0)

	theme.set_stylebox("selected", "ItemList", row_selected)
	theme.set_stylebox("selected_focus", "ItemList", row_selected)
	theme.set_stylebox("hovered", "ItemList", row_hover)
	theme.set_stylebox("cursor", "ItemList", row_hover)
	theme.set_stylebox("cursor_unfocused", "ItemList", row_hover)

	# --- Tree, where one is used ---
	theme.set_stylebox("panel", "Tree", list_bg)
	theme.set_color("font_color", "Tree", TEXT_MAIN)
	theme.set_color("font_selected_color", "Tree", TEXT_MAIN)
	theme.set_color("guide_color", "Tree", Color(0, 0, 0, 0))
	theme.set_stylebox("selected", "Tree", row_selected)
	theme.set_stylebox("selected_focus", "Tree", row_selected)
	theme.set_stylebox("hovered", "Tree", row_hover)

	# --- TabContainer & TabBar ---
	#
	# Unselected tabs no longer draw a filled box. A row of boxes where one is lit is a segmented
	# control; a row of labels where one is underlined is a tab strip, and the inspector is a tab
	# strip.
	var tab_selected := StyleBoxFlat.new()
	tab_selected.bg_color = Color(0, 0, 0, 0)
	tab_selected.border_color = ACCENT
	tab_selected.border_width_bottom = 2
	tab_selected.set_corner_radius_all(0)
	# Tighter than a button's SPACE_3: the right-hand rail carries five tabs in 316 px, and at
	# SPACE_3 they no longer fit — TabContainer answers that by hiding the ends behind scroll
	# arrows, so the cost of the wider margin is paid in tabs you cannot see.
	tab_selected.content_margin_left = SPACE_2
	tab_selected.content_margin_right = SPACE_2
	tab_selected.content_margin_top = SPACE_2
	tab_selected.content_margin_bottom = SPACE_2

	var tab_unselected := tab_selected.duplicate() as StyleBoxFlat
	tab_unselected.bg_color = Color(0, 0, 0, 0)
	tab_unselected.border_color = BORDER
	tab_unselected.border_width_bottom = 1

	var tab_hovered := tab_unselected.duplicate() as StyleBoxFlat
	tab_hovered.border_color = BORDER_STRONG

	for cls in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", cls, tab_selected)
		theme.set_stylebox("tab_unselected", cls, tab_unselected)
		theme.set_stylebox("tab_hovered", cls, tab_hovered)
		theme.set_color("font_selected_color", cls, TEXT_MAIN)
		theme.set_color("font_unselected_color", cls, TEXT_MUTED)
		theme.set_color("font_hovered_color", cls, TEXT_MAIN)

	# The TabContainer's own body: no second border under the strip.
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# --- ProgressBar ---
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = PANEL_SUNKEN
	pb_bg.set_corner_radius_all(RADIUS_SMALL)
	pb_bg.anti_aliasing = true

	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ACCENT
	pb_fill.set_corner_radius_all(RADIUS_SMALL)
	pb_fill.anti_aliasing = true

	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	# --- Scrollbars ---
	#
	# The default is a chunky grey slab with stepper buttons at both ends. A thin translucent
	# grabber over an invisible track is what every tool this app is trying to look like uses.
	var scroll_track := StyleBoxEmpty.new()
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	grabber.set_corner_radius_all(RADIUS_SMALL)
	grabber.anti_aliasing = true
	var grabber_hl := grabber.duplicate() as StyleBoxFlat
	grabber_hl.bg_color = Color(1.0, 1.0, 1.0, 0.30)

	for cls in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", cls, scroll_track)
		theme.set_stylebox("scroll_focus", cls, scroll_track)
		theme.set_stylebox("grabber", cls, grabber)
		theme.set_stylebox("grabber_highlight", cls, grabber_hl)
		theme.set_stylebox("grabber_pressed", cls, grabber_hl)

	# --- Sliders ---
	var slider_track := StyleBoxFlat.new()
	slider_track.bg_color = PANEL_SUNKEN
	slider_track.set_corner_radius_all(3)
	slider_track.anti_aliasing = true
	for cls in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", cls, slider_track)
		theme.set_stylebox("grabber_area", cls, pb_fill)
		theme.set_stylebox("grabber_area_highlight", cls, pb_fill)

	# --- Separators ---
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_stylebox("separator", "VSeparator", sep)
	theme.set_constant("separation", "HSeparator", SPACE_3)
	theme.set_constant("separation", "VSeparator", SPACE_3)

	# --- Tooltips ---
	# Opaque, by the rule stated at PopupMenu: a tooltip exists to be read, and at 0.97 it read the
	# viewport's own geometry through its text.
	var tip_box := glass_box(Color(0.10, 0.11, 0.135), RADIUS_SMALL)
	tip_box.set_content_margin_all(SPACE_2)
	theme.set_stylebox("panel", "TooltipPanel", tip_box)
	theme.set_color("font_color", "TooltipLabel", TEXT_MAIN)

	# --- Windows (the drone menu, the custom-part dialogs) ---
	# Opaque, by the same rule. A dialog is the most read-text-off surface in the app.
	var win_box := glass_box(Color(0.115, 0.128, 0.155), RADIUS_PANEL)
	win_box.set_content_margin_all(SPACE_4)
	theme.set_stylebox("panel", "AcceptDialog", win_box)
	theme.set_stylebox("embedded_border", "Window", win_box)
	theme.set_color("title_color", "Window", TEXT_MAIN)

	# --- Containers ---
	theme.set_constant("h_separation", "GridContainer", SPACE_4)
	theme.set_constant("v_separation", "GridContainer", SPACE_1)  # see panel_box: height is scarce
	theme.set_constant("separation", "VBoxContainer", SPACE_2)
	theme.set_constant("separation", "HBoxContainer", SPACE_2)

	return theme
