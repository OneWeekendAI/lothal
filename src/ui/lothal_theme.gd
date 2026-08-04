class_name LothalTheme
extends RefCounted
## Lothal single theme provider (Deliverable 2).
## Built entirely in GDScript code so visual constants and styling are fully diffable.

# Palette (named by role)
const SURFACE_BASE := Color(0.09, 0.10, 0.12)
const PANEL_BG := Color(0.14, 0.15, 0.18)
const BORDER := Color(0.24, 0.26, 0.30)
const BORDER_FOCUS := Color(0.40, 0.82, 0.96)

const TEXT_MAIN := Color(0.88, 0.90, 0.94)
const TEXT_MUTED := Color(0.58, 0.60, 0.64)

const ACCENT := Color(0.40, 0.82, 0.96)
const WARNING := Color(1.0, 0.72, 0.25)
const DANGER := Color(1.0, 0.36, 0.30)
const SUCCESS := Color(0.40, 0.85, 0.55)

# Spacing Scale
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24
const SPACE_8 := 32

# Type Scale
const FONT_SIZE_SMALL := 12
const FONT_SIZE_BODY := 14
const FONT_SIZE_SUBTITLE := 18
const FONT_SIZE_TITLE := 22
const FONT_SIZE_HERO := 32

static var _cached_theme: Theme = null

static func get_theme() -> Theme:
	if _cached_theme == null:
		_cached_theme = _build_theme()
	return _cached_theme

static func _build_theme() -> Theme:
	var theme := Theme.new()

	# System monospaced font for numeric readouts
	var mono_font := SystemFont.new()
	mono_font.font_names = PackedStringArray(["Menlo", "Consolas", "Monaco", "Courier New", "monospace"])

	# Base font size across controls
	theme.default_font_size = FONT_SIZE_BODY

	# --- Labels ---
	theme.set_color("font_color", "Label", TEXT_MAIN)

	# Label Type Variations
	theme.set_type_variation("ReadoutLabel", "Label")
	theme.set_font("font", "ReadoutLabel", mono_font)
	theme.set_font_size("font_size", "ReadoutLabel", FONT_SIZE_BODY)
	theme.set_color("font_color", "ReadoutLabel", TEXT_MAIN)

	theme.set_type_variation("HeroReadoutLabel", "Label")
	theme.set_font("font", "HeroReadoutLabel", mono_font)
	theme.set_font_size("font_size", "HeroReadoutLabel", FONT_SIZE_HERO)
	theme.set_color("font_color", "HeroReadoutLabel", TEXT_MAIN)

	theme.set_type_variation("SubHeroReadoutLabel", "Label")
	theme.set_font("font", "SubHeroReadoutLabel", mono_font)
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
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = PANEL_BG
	panel_box.border_color = BORDER
	panel_box.set_border_width_all(1)
	panel_box.set_corner_radius_all(4)
	panel_box.set_content_margin_all(SPACE_2)

	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("panel", "Panel", panel_box)

	# --- Buttons ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.20, 0.24)
	btn_normal.border_color = BORDER
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(4)
	btn_normal.content_margin_left = SPACE_3
	btn_normal.content_margin_right = SPACE_3
	btn_normal.content_margin_top = SPACE_1
	btn_normal.content_margin_bottom = SPACE_1

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.24, 0.27, 0.32)
	btn_hover.border_color = ACCENT

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.12, 0.14, 0.18)
	btn_pressed.border_color = ACCENT

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.12, 0.13, 0.15)
	btn_disabled.border_color = Color(0.18, 0.20, 0.24)

	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", TEXT_MAIN)
	theme.set_color("font_hover_color", "Button", TEXT_MAIN)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED)

	# --- TabContainer & TabBar ---
	var tab_selected := StyleBoxFlat.new()
	tab_selected.bg_color = PANEL_BG
	tab_selected.border_color = ACCENT
	tab_selected.border_width_bottom = 2
	# Tighter than a button's SPACE_3: the right-hand rail carries five tabs in 316 px, and at
	# SPACE_3 they no longer fit — TabContainer answers that by hiding the ends behind scroll
	# arrows, so the cost of the wider margin is paid in tabs you cannot see.
	tab_selected.content_margin_left = SPACE_2
	tab_selected.content_margin_right = SPACE_2
	tab_selected.content_margin_top = SPACE_2
	tab_selected.content_margin_bottom = SPACE_2

	var tab_unselected := tab_selected.duplicate() as StyleBoxFlat
	tab_unselected.bg_color = Color(0.11, 0.12, 0.14)
	tab_unselected.border_color = BORDER
	tab_unselected.border_width_bottom = 1

	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_selected", "TabBar", tab_selected)
	theme.set_stylebox("tab_unselected", "TabBar", tab_unselected)

	# --- ProgressBar ---
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.16, 0.17, 0.20)
	pb_bg.set_corner_radius_all(3)

	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ACCENT
	pb_fill.set_corner_radius_all(3)

	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	# --- Containers ---
	theme.set_constant("h_separation", "GridContainer", SPACE_3)
	theme.set_constant("v_separation", "GridContainer", SPACE_1)
	theme.set_constant("separation", "VBoxContainer", SPACE_2)
	theme.set_constant("separation", "HBoxContainer", SPACE_2)

	return theme
