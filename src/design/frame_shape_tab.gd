class_name FrameShapeTab
extends Control
## The frame sheet's Shape tab: the old Airframe room (layout shelf, 2D plan editor, dimension
## sliders, numbers strip, SVG/DXF import, the print/cut/STL/build-sheet exports) hosted inside the
## Part sheet.
##
## ## The seam to the design
##
## The room edits a COPY of the session's frame document; the edit reaches the design through
## `DesignSession.adopt_frame_document`, a moment after each change (a drag fires dozens a second
## and every adoption redraws the 3D frame), and once more on `flush`. The first adoption pushes
## one undo step, so Undo on the Design Space takes the whole sheet visit back.
##
## ## What flies, per class (the editability decision)
##
## The seam is live when the session holds an editable document (a frame the class's GLB was drawn
## from, today the 5") and the room is editing THAT frame. Anything else (a class with no document,
## a different frame fitted, or a layout/new frame/open chosen inside the room, which is a different
## frame) is a design workbench: you can draw, import and export it, and the status line says it
## does not replace the fitted frame.

## How long after the last change the design is told, seconds.
const SETTLE_S := 0.25

var ds: DesignSpace
var sheet: PartSheet
var workbench: FrameWorkbench
var seam_live := false
var adopted := 0
var _opening := false
var _dirty := false
var _undo_pushed := false
var _timer: Timer


func _init(p_ds: DesignSpace, p_sheet: PartSheet = null) -> void:
	ds = p_ds
	sheet = p_sheet
	name = "FrameShapeTab"
	workbench = FrameWorkbench.new(ds._catalog)
	workbench.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(workbench)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = SETTLE_S
	_timer.timeout.connect(flush)
	add_child(_timer)
	var frame: Dictionary = ds._catalog.get_part(String(ds.session.selection.get("frame", "")))
	var doc := ds.session.frame_document()
	_opening = true
	if ds.session.frame_editable():
		seam_live = true
		workbench.open_fitted(frame, AirframeDocument.from_dictionary(doc.to_dictionary()))
		_status("Your edits fly: this is the fitted frame.")
	else:
		workbench.start_from(frame)
		_status("A copy to draw and export. It does not replace this class's fitted frame.")
	_opening = false
	workbench.document_changed.connect(_on_changed)


func _status(text: String) -> void:
	if sheet != null:
		sheet.set_status(text)


func _on_changed(document: AirframeDocument) -> void:
	if _opening:
		return
	# A layout, New or Open inside the room is another frame, not an edit of the fitted one.
	var fitted := ds.session.frame_document()
	if seam_live and (fitted == null or document.id != fitted.id):
		seam_live = false
		_dirty = false
		_status("A different frame from the fitted one: export or save it; it does not fly.")
	if not seam_live:
		return
	_dirty = true
	_timer.start()


## Hands the room's document to the design now. True when the design took it.
func flush() -> bool:
	if not _dirty or not seam_live or workbench.editor.document == null:
		return false
	_dirty = false
	var ok := ds.session.adopt_frame_document(workbench.editor.document.to_dictionary(), not _undo_pushed)
	if ok:
		_undo_pushed = true
		adopted += 1
	return ok


func _exit_tree() -> void:
	flush()
