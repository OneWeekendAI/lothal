class_name PrintTab
extends Control
## The Printed tab of the Frame, Camera, Antenna, Battery and Guard sheets: the old Printed room
## (`PrintPanel`) cut to the part's own page, editing THIS design. Print settings (clearance, the
## generated mounts, the arm guard, the battery pad) live in the session (`set_printing`: undo, the
## design file, the Build); an export writes the part's STL (checked closed by `StlWriter`) and notes a
## print record in the design, which is what the Keep / Reprint divergence check compares against.
##
## The frame sheet shows the whole room (frame, arm guard); the others show their own part.

## Sheet category -> the printed row it is the page of ("" = every row).
const PART_OF := {"frame": "", "camera": "camera_mount", "antenna": "antenna_mount", "battery": "battery_pad", "guard": "prop_guard"}

var ds: DesignSpace
var sheet: PartSheet
var category := ""
var panel: PrintPanel
## Where STL files go (tests point it at a scratch folder).
var export_dir := "user://exports"
## The last thing the tab said (also on the sheet's status line).
var last_message := ""


func _init(p_ds: DesignSpace, p_sheet: PartSheet, p_category: String) -> void:
	ds = p_ds
	sheet = p_sheet
	category = p_category
	name = "PrintTab_" + category
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = PrintPanel.new()
	panel.clearance_edited.connect(func(mm: float): _edit(func(p): PrintSettings.set_clearance_mm(p, mm)))
	panel.arm_guard_edited.connect(func(k: String, v: Variant): _edit(func(p): ArmGuard.set_value(p, k, v)))
	panel.camera_mount_edited.connect(func(k: String, v: Variant): _edit(func(p): CameraMount.set_value(p, k, v)))
	panel.antenna_mount_edited.connect(func(k: String, v: Variant): _edit(func(p): AntennaMount.set_value(p, k, v)))
	panel.gps_mast_edited.connect(func(k: String, v: Variant): _edit(func(p): GpsMast.set_value(p, k, v)))
	panel.battery_pad_edited.connect(func(k: String, v: Variant): _edit(func(p): BatteryPad.set_value(p, k, v)))
	panel.export_requested.connect(export_part)
	panel.divergence_kept.connect(keep)
	panel.divergence_reprint_requested.connect(export_part)
	add_child(ConfigTab.host(panel))
	panel.set_dock_part(String(PART_OF.get(category, "")))
	ds.session.changed.connect(refresh)
	tree_exiting.connect(func():
		if ds.session.changed.is_connected(refresh):
			ds.session.changed.disconnect(refresh))
	refresh()


func _edit(mutate: Callable) -> void:
	var p := ds.session.printing()
	mutate.call(p)
	ds.session.set_printing(p)


## One part's STL, on the design's build; a record goes into the design. Says what happened.
func export_part(part_id: String) -> void:
	var build := ds.session.build(ds._catalog)
	if build == null:
		return
	var result := PrintedExport.export_part(build, part_id, export_dir, null)
	if bool(result["ok"]):
		ds.session.add_print_record(result["record"])
		_say("Wrote %s" % ProjectSettings.globalize_path(String(result["record"]["exported_to"])))
	else:
		_say("NOT EXPORTED: %s" % String(result["reason"]))


## Keep: acknowledges the finding for `part_id` in the design's printing block.
func keep(part_id: String) -> void:
	var p := ds.session.printing()
	for finding in ds.session.print_divergence(ds._catalog):
		if String(finding["part"]) == part_id:
			PrintedDivergence.acknowledge(p, finding)
	ds.session.set_printing(p)


func _say(text: String) -> void:
	last_message = text
	if sheet != null:
		sheet.set_status(text)


func refresh() -> void:
	var build := ds.session.build(ds._catalog)
	if build == null:
		return
	panel.render(build, ds.session.printing())
	panel.set_divergence(ds.session.print_divergence(ds._catalog))
	panel.set_dock_part(String(PART_OF.get(category, "")))
