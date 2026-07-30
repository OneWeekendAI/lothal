class_name AppShell
extends Control
## The two rooms, and the door between them (labs-and-sim.md §1).
##
## Lab is the garage and it is where the app opens. Sim is the field, reached deliberately.
## Before this shell existed, Lothal booted straight into a flight simulation with a parts
## panel bolted onto the side, which made every part change feel like a cheat-menu slider
## rather than a decision.
##
## The important behaviour is what happens on the way through the door:
##
## **Sim does not exist while you are in Lab.** It is instantiated when the tab is opened and
## FREED when it is left — not hidden, not paused. That is the honest form of "choosing parts
## does not cost a 1 kHz integrator, a renderer and a real-time audio synthesiser": a paused
## node still holds a chase camera, a DroneAudio bus and a HUD CanvasLayer, and a flag saying
## it is idle is something that can rot. A freed instance cannot.
##
## **Lab persists.** It is cheap — no integrator lives in it — and the frame you chose should
## still be chosen when you walk back from the field. This is the boundary labs-and-sim.md §4
## describes: the build crosses from Lab to Sim, and nothing crosses back except consequences.
##
## Consequence worth naming: because Sim is rebuilt on entry, a lap in progress does not
## survive a trip to the garage. That is the intended reading — you landed and walked away.

const SIM_SCENE := "res://src/scenes/main.tscn"
const TAB_BAR_HEIGHT := 40.0

var lab: LabScreen
## The flight simulation, or null whenever Lab is showing. Null IS the assertion — see above.
var sim: Node = null

var _host: Control
var _lab_button: Button
var _sim_button: Button
var _showing_lab := true

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Lab's Controls go in a host inset below the tab bar. Sim is added as a direct child
	# instead, because it is a Node3D scene carrying its own cameras and its own HUD layer
	# and has no business inside a Control layout.
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.anchor_right = 1.0
	_host.anchor_bottom = 1.0
	_host.offset_top = TAB_BAR_HEIGHT
	add_child(_host)

	lab = LabScreen.new(catalog_for_lab())
	_host.add_child(lab)

	# The tab bar sits on a high CanvasLayer so it stays reachable over Sim, whose HUD is
	# itself on a CanvasLayer and would otherwise draw straight over the only way out.
	var tab_layer := CanvasLayer.new()
	tab_layer.layer = 10
	add_child(tab_layer)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.position = Vector2(8, 6)
	tab_layer.add_child(bar)

	_lab_button = _add_tab(bar, "Lab", show_lab)
	_sim_button = _add_tab(bar, "Sim", show_sim)
	_refresh_tabs()

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
func catalog_for_lab() -> PartsCatalog:
	return PartsCatalog.load_default()


func showing_lab() -> bool:
	return _showing_lab


## Back to the garage. Sim is removed from the tree and freed immediately rather than
## queue_free()'d, so that "the flight loop has stopped" is true the moment this returns
## instead of at the end of the frame — which is also what makes it testable synchronously.
func show_lab() -> void:
	if sim != null:
		remove_child(sim)
		sim.free()
		sim = null
	_showing_lab = true
	lab.visible = true
	_refresh_tabs()


## Out to the field. The existing flight scene, unchanged, instantiated fresh.
func show_sim() -> void:
	if sim == null:
		sim = load(SIM_SCENE).instantiate()
		add_child(sim)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


func _refresh_tabs() -> void:
	_lab_button.button_pressed = _showing_lab
	_sim_button.button_pressed = not _showing_lab
