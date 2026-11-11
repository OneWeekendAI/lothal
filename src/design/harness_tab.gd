class_name HarnessTab
extends Control
## The ESC sheet's Harness tab: the old Power room (`PowerWorkbench`: the wiring drawn as a schematic,
## each segment's gauge and length, the pack's place, undo) inside the Parts drawer, editing THIS
## design's harness. The authored values live in the session (`harness_overrides`), so they fly, save
## with the design and undo with it; the room's own history still steps its edits one at a time.
##
## The battery offset slider is the assembly tweak `battery_offset_mm`, written to the session's tweaks.

var ds: DesignSpace
var room: PowerWorkbench
var _tweaks: AssemblyTweaks


func _init(p_ds: DesignSpace) -> void:
	ds = p_ds
	name = "HarnessTab"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	room = PowerWorkbench.new()
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(room)
	room.document_changed.connect(_on_document_changed)
	room.pack_offset_edited.connect(_on_offset)
	ds.session.changed.connect(_on_session_changed)
	tree_exiting.connect(func():
		if ds.session.changed.is_connected(_on_session_changed):
			ds.session.changed.disconnect(_on_session_changed))
	_load()


## Puts the design's aircraft on the room's bench.
func _load() -> void:
	_tweaks = AssemblyTweaks.from_dict(ds.session.tweaks.to_dict())
	var build := ds.session.build(ds._catalog)
	if build == null:
		return
	room.set_build(build, _tweaks, ds.session.frame_document())


func _on_document_changed(harness: Harness) -> void:
	ds.session.set_harness_overrides(harness.overrides())


func _on_offset(millimetres: float) -> void:
	_tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, millimetres)
	ds.session.set_tweaks(_tweaks)


## Something else changed the design (an undo, a swap): re-read it unless the room already shows it.
func _on_session_changed() -> void:
	if room.build != null and room.build.harness.overrides() == ds.session.harness_overrides \
			and _tweaks.to_dict() == ds.session.tweaks.to_dict():
		return
	_load()
