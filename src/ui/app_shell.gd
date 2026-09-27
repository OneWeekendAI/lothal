class_name AppShell
extends Control
## The eight-tab shell — **the OLD one, on its way out**.
##
## Everything this file used to know about rooms now lives in `RoomHost`, and what is left here is
## the tab bar, the update notice and the link out to the site. It is kept working, and kept
## covered by the suite, while `GlassShell` grows into the shell that replaces it (CONTINUE-HERE.md
## §4: "build the new shell beside the old one, port one system at a time, keep the old tabs working
## until the new shell covers them, delete the tab bar last").
##
## **Why this is a delegate rather than a copy.** The room rules are not conventions — they are
## `_close_rooms()` freeing an instance immediately, and every room that could have drained a pack
## writing its consequence back on the way out. A second shell with its own copy would be a second
## thing capable of leaving a Powertrain turning behind a screen nobody is looking at, and the only
## evidence would be a battery that was wrong later. So both shells drive one `RoomHost`, and the
## fields below are pass-throughs to it rather than state of their own.
##
## The behaviour those rules produce is documented on `RoomHost`, not repeated here.

## Where Sim lives. Kept as a constant on this class because tests/test_lab.gd loads the scene
## through it; the room that actually instantiates it is RoomHost.
const SIM_SCENE := RoomHost.SIM_SCENE
const TAB_BAR_HEIGHT := 40.0

## The rooms, and the only owner of the rules for entering and leaving them.
var rooms: RoomHost

# ---------------------------------------------------------------------------
# Pass-throughs. Every one of these was a field on this class before RoomHost existed, and each is
# read by the suite and by the capture tools. Kept as properties rather than rewritten at ~40 call
# sites, and kept read-only, because a shell that could ASSIGN `sim` would be a second owner of the
# lifecycle by the back door.
# ---------------------------------------------------------------------------
var lab: LabScreen:
	get: return rooms.lab
var sim: Node:
	get: return rooms.sim
var bench: BenchScreen:
	get: return rooms.bench
var battery_bench: BatteryBenchScreen:
	get: return rooms.battery_bench
var esc_bench: EscBenchScreen:
	get: return rooms.esc_bench
var frame_bench: FrameBenchScreen:
	get: return rooms.frame_bench
var studio: StudioScreen:
	get: return rooms.studio
var course_library: CourseLibrary:
	get: return rooms.course_library
var pack_charge: PackCharge:
	get: return rooms.pack_charge

var _lab_button: Button
var _bench_button: Button
var _pack_bench_button: Button
var _esc_bench_button: Button
var _frame_bench_button: Button
var _sim_button: Button
var _studio_button: Button

var settings: AppSettings

func _init() -> void:
	theme = LothalTheme.get_theme()
	settings = AppSettings.load_from()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	rooms = RoomHost.new(catalog_for_lab())
	# The rooms sit below the tab bar. RoomHost insets its Control rooms by this and tells Sim
	# about it — Sim owns the whole window and draws its own panel underneath.
	rooms.top_inset = TAB_BAR_HEIGHT
	rooms.room_changed.connect(_refresh_tabs)
	add_child(rooms)

	# The tab bar sits on a high CanvasLayer so it stays reachable over Sim, whose HUD is
	# itself on a CanvasLayer and would otherwise draw straight over the only way out.
	var tab_layer := CanvasLayer.new()
	tab_layer.layer = 10
	add_child(tab_layer)

	var bar := HBoxContainer.new()
	bar.position = Vector2(LothalTheme.SPACE_2, 6)
	tab_layer.add_child(bar)

	_lab_button = _add_tab(bar, "Lab", show_lab)
	_bench_button = _add_tab(bar, "Thrust", show_bench)
	_pack_bench_button = _add_tab(bar, "Pack", show_battery_bench)
	_esc_bench_button = _add_tab(bar, "ESC", show_esc_bench)
	_frame_bench_button = _add_tab(bar, "Frame", show_frame_bench)
	_sim_button = _add_tab(bar, "Sim", show_sim)
	# Last, and after Sim deliberately: the tab order is the order the work happens in. You build
	# in the garage, you fly in the field, and then you look at what the flight left behind.
	_studio_button = _add_tab(bar, "Studio", show_studio)

	# A way to reach us: a link out to the site in the user's own browser, not an in-app view —
	# anything resembling a web window with no address bar is shaped like the phishing people are
	# taught to refuse.
	var contact := Button.new()
	contact.text = "Contact us"
	contact.flat = true
	contact.custom_minimum_size = Vector2(0, 28)
	contact.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	contact.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	contact.pressed.connect(func() -> void: OS.shell_open(LothalVersion.CONTACT_URL))
	bar.add_child(contact)

	_refresh_tabs()

	# The update bar rides the same high CanvasLayer as the tabs, for the same reason: Sim's HUD
	# is on a layer of its own and would draw straight over anything sitting in the ordinary
	# tree. Anchored to the bottom rather than the top so it never crowds the tab row, and it
	# stays hidden unless a signed manifest offers something newer — see UpdateNotice.
	var notice := UpdateNotice.new(LothalVersion.MANIFEST_URL)
	notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	notice.anchor_top = 1.0
	notice.anchor_right = 1.0
	notice.anchor_bottom = 1.0
	notice.offset_top = -UpdateNotice.BAR_HEIGHT
	tab_layer.add_child(notice)

func _ready() -> void:
	if get_tree() != null and get_tree().root != null and settings != null:
		get_tree().root.content_scale_factor = settings.ui_scale


func _add_tab(bar: HBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(92, 28)
	button.pressed.connect(handler)
	bar.add_child(button)
	return button


## Overridable seam for the catalog Lab reads. Kept as a method rather than inlined so a test
## or a later "load a different catalog" path has somewhere to stand.
##
## load_with_custom rather than load_default because LAB IS WHERE A BUILDER'S OWN FRAMES LIVE —
## and because ReferenceBuild's catalog must stay the shipped one, which is why these are two
## functions rather than one with an argument.
func catalog_for_lab() -> PartsCatalog:
	return PartsCatalog.load_with_custom()


# ---------------------------------------------------------------------------
# The doors. Each is one line now — RoomHost does the work, and the tab bar restyles itself from
# `room_changed` rather than each of these remembering to.
# ---------------------------------------------------------------------------

func showing_lab() -> bool:
	return rooms.showing_lab()


func show_lab() -> void:
	rooms.show_lab()


func show_bench() -> void:
	rooms.show_bench()


func show_battery_bench() -> void:
	rooms.show_battery_bench()


func show_esc_bench() -> void:
	rooms.show_esc_bench()


func show_frame_bench() -> void:
	rooms.show_frame_bench()


func show_studio() -> void:
	rooms.show_studio()


func show_sim() -> void:
	rooms.show_sim()


func _refresh_tabs() -> void:
	_lab_button.button_pressed = rooms.showing_lab()
	_bench_button.button_pressed = rooms.bench != null
	_pack_bench_button.button_pressed = rooms.battery_bench != null
	_esc_bench_button.button_pressed = rooms.esc_bench != null
	_frame_bench_button.button_pressed = rooms.frame_bench != null
	_sim_button.button_pressed = rooms.sim != null
	_studio_button.button_pressed = rooms.studio != null
