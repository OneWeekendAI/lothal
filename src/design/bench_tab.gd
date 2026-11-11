class_name BenchTab
extends Control
## A bench as a tab of a Part sheet: the thrust stand on the Motor sheet, the ESC bench on the ESC
## sheet, the frame bench on the Frame sheet. Each is the old room's screen, hosted unchanged, and
## judging the design's own selection (the motor, prop, pack, ESC and frame fitted now).
##
## A bench is built fresh every time its tab is shown and freed when the tab is hidden or the sheet
## goes, for the old rooms' reason: a bench left spinning is a machine left unattended, and a bench
## holds a live physics step and an audio bus. Pack charge is written back as the tab leaves.

const KINDS := ["thrust", "esc", "frame"]

var ds: DesignSpace
var kind := "thrust"
## The hosted screen while the tab is showing (BenchScreen, EscBenchScreen or FrameBenchScreen).
var screen: Control = null
var _charge: PackCharge = null


func _init(p_ds: DesignSpace, p_kind: String) -> void:
	ds = p_ds
	kind = p_kind
	name = "BenchTab_" + kind
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(_on_visibility)
	tree_exiting.connect(_release)


func _ready() -> void:
	if is_visible_in_tree() and screen == null:
		_raise()


func _on_visibility() -> void:
	if is_visible_in_tree():
		if screen == null:
			_raise()
	else:
		_release()


## Puts a fresh bench on the design's current selection.
func _raise() -> void:
	_release()
	var sel: Dictionary = ds.session.selection
	var catalog: PartsCatalog = ds._catalog
	_charge = PackCharge.load_from(ds.pack_charge_path)
	match kind:
		"thrust":
			screen = BenchScreen.new(catalog, String(sel["motor"]), String(sel["propeller"]), String(sel["battery"]), _charge)
		"esc":
			screen = EscBenchScreen.new(catalog, String(sel["motor"]), String(sel["propeller"]), String(sel["battery"]),
				String(sel["esc"]), _charge, String(sel["frame"]))
		"frame":
			screen = FrameBenchScreen.new(catalog, String(sel["frame"]), String(sel["motor"]), String(sel["propeller"]),
				String(sel["battery"]), String(sel["esc"]), _charge, AssemblyTweaks.new())
	if screen == null:
		return
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)


## Takes the bench down, writing the charge its run cost back first.
func _release() -> void:
	if screen == null:
		return
	if screen.has_method("persist_pack_charge"):
		screen.call("persist_pack_charge")
	if _charge != null:
		_charge.save(ds.pack_charge_path)
	remove_child(screen)
	screen.free()
	screen = null
