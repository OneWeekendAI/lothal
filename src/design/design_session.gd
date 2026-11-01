class_name DesignSession
extends RefCounted
## The Design Space's drone: the selection of part ids it opens on, and the one method that turns
## that selection into a `Build` (PLAN §3). No Node, no drawing.
##
## It holds the selection, builds it, and keeps ONE undo/redo history of swaps (Section 3) and frame
## edits (Section 4): each entry restores both the selection and the frame document.
##
## THE FRAME DOCUMENT (Section 4) is the frame on screen, not a generated preset: the 5" GLB's own
## plates, written by tools/blender/build_drone.py as `FRAME_DOCUMENTS[class]`. A class without one
## (every class but the 5" for now) has `frame_document() == null` and every frame op refuses. The
## edit flies through `FittedFrame.edit_of` against the document as loaded, so the flown frame is
## the catalog's weighed mass plus what the edits removed or added.
##
## The build goes through `Project.to_build`, the same path a saved drone flies by, so the Design
## Space can never open on a different aircraft from the one the project file describes.

var drone_class: String = ""
## category -> part id, dense over ProjectSchema.all_categories().
var selection: Dictionary = {}
var _project: Project
## Undo and redo stacks of whole selections (Section 3). A swap pushes the selection it replaced.
var _undo: Array = []
var _redo: Array = []

## Class -> the frame document its GLB was built with (Section 4). The document's id is the class's
## frame part id, so an edit is an EDIT of that frame and not a replacement.
const FRAME_DOCUMENTS := {"five_inch": "res://assets/models/classes/five_inch_frame.json"}
## The frame as edited, or null when this drone has no editable frame drawing.
var _frame_doc: AirframeDocument
## `FittedFrame.drawn` of the document as loaded: the baseline every edit is measured against.
var _frame_baseline: Dictionary = {}


## The session a project opens into. Reads the project's parts; the project is not kept live, so
## an edit in the session never writes the file behind the builder's back.
static func from_project(project: Project) -> DesignSession:
	var session := DesignSession.new()
	session._project = Project.from_dict(project.to_dict())
	session.drone_class = project.drone_class
	session.selection = project.parts.duplicate(true)
	session._load_frame_document()
	return session


## A project that already flies a drawn frame (Project.airframe) keeps it, so the GLB's document is
## not loaded over it: the frame ops refuse and the plan editor stays the place to edit that drawing.
func _load_frame_document() -> void:
	_frame_doc = null
	_frame_baseline = {}
	if not FRAME_DOCUMENTS.has(drone_class) or not _project.airframe.is_empty():
		return
	var doc := AirframeDocument.load_from(String(FRAME_DOCUMENTS[drone_class]))
	if doc.plates.is_empty() or doc.id == "":
		return
	_frame_doc = doc
	_frame_baseline = FittedFrame.drawn(doc)


## The default drone of a class: what a new project of that class opens on. Null for a
## coming-soon or unknown class.
static func default_for_class(class_id: String) -> DesignSession:
	if not DroneClass.is_available(class_id):
		return null
	return from_project(DroneClass.starting_project(class_id, "Design session"))


## A copy of `session` with one part changed: what a swap WOULD build, without touching `session`.
static func from_selection(session: DesignSession, category: String, part_id: String) -> DesignSession:
	var trial := DesignSession.new()
	trial._project = session._project
	trial.drone_class = session.drone_class
	trial.selection = session.selection.duplicate(true)
	trial.selection[category] = part_id
	# The edited frame comes along (read only), so a previewed swap is measured on the frame on screen.
	trial._frame_doc = session._frame_doc
	trial._frame_baseline = session._frame_baseline
	return trial


## The selection as physics. Null if a required part is missing from `catalog`.
func build(catalog: PartsCatalog) -> Build:
	_project.parts = selection.duplicate(true)
	var b := _project.to_build(catalog)
	if b != null:
		var edit := frame_edit(catalog)
		if not edit.is_empty():
			b.set_frame_edit(edit)
	return b


## The edit the frame document makes to the fitted frame (`FittedFrame.edit_of`), `{}` when there is
## none: no document, a different frame fitted (the drawing belongs to the frame it was drawn on),
## or a document still as loaded.
func frame_edit(catalog: PartsCatalog) -> Dictionary:
	if _frame_doc == null or String(selection.get("frame", "")) != _frame_doc.id:
		return {}
	return FittedFrame.edit_of(catalog.get_part(_frame_doc.id), _frame_doc, _frame_baseline)


## Swaps one part of the selection (the session's only edit so far). False for an unknown category.
func set_part(category: String, part_id: String) -> bool:
	if not selection.has(category):
		return false
	selection[category] = part_id
	return true


## The vital signs, read straight off the selection's `Build`: nothing is computed here, and nothing
## is cached, so a changed selection can never show last build's figures. Empty if it cannot build.
## Keys: auw_g, thrust_to_weight, hover_throttle (0..1), flight_time_min, top_speed_kmh.
func readouts(catalog: PartsCatalog) -> Dictionary:
	return readouts_of(build(catalog))


## The five readouts of one `Build`, read straight off it. Empty for null.
static func readouts_of(b: Build) -> Dictionary:
	if b == null:
		return {}
	return {
		"auw_g": b.all_up_weight_g(),
		"thrust_to_weight": b.thrust_to_weight(),
		"hover_throttle": b.hover_throttle(),
		"flight_time_min": b.flight_time_min(),
		"top_speed_kmh": b.top_speed_kmh(),
	}


## Click to swap: fits `part_id` as `category` unless `PartSwap.judge` refuses it. Returns the
## verdict ({ok, reason, ...}); a refused swap leaves the selection and both stacks untouched.
func swap(catalog: PartsCatalog, category: String, part_id: String) -> Dictionary:
	var verdict := PartSwap.judge(self, catalog, category, part_id, false)
	if not verdict["ok"]:
		return verdict
	if String(selection.get(category, "")) == part_id:
		return verdict
	_push_undo()
	selection[category] = part_id
	return verdict


# ---------------------------------------------------------------------------
# Frame edits (Section 4)
# ---------------------------------------------------------------------------

## The frame as edited, or null when this drone has no editable frame drawing. The caller reads it
## and must not write it: every write goes through the ops below, which keep the history.
func frame_document() -> AirframeDocument:
	return _frame_doc


## Whether the frame ops apply: a document is loaded and the frame it describes is fitted.
func frame_editable() -> bool:
	return _frame_doc != null and String(selection.get("frame", "")) == _frame_doc.id


## Which document plate a GLB mesh (frame_arm_FL, frame_plate_top) is; -1 if none.
func plate_of_mesh(mesh_name: String) -> int:
	return FrameTools.plate_of_mesh(_frame_doc, mesh_name)


## Which (plate, hole) a pick proxy (pick_hole_arm_FL_2) is; Vector2i(-1, -1) if none.
func hole_of_proxy(proxy_name: String) -> Vector2i:
	return FrameTools.hole_of_proxy(_frame_doc, proxy_name)


## Drills a `d_mm` hole at `point_mm` (the plate's plan mm). `d_mm` from FrameTools.DRILL_SIZES or
## free. Returns {ok, reason}; a refusal changes nothing, history included.
func drill(plate_index: int, point_mm: Vector2, d_mm: float) -> Dictionary:
	return _frame_op(func(doc: AirframeDocument) -> Dictionary:
		return FrameTools.drill(doc, plate_index, point_mm, d_mm))


## Cuts a pocket: `shape` is a closed polygon from FrameTools.rect_pocket or FrameTools.slot_pocket.
func pocket(plate_index: int, shape: PackedVector2Array) -> Dictionary:
	return _frame_op(func(doc: AirframeDocument) -> Dictionary:
		return FrameTools.pocket(doc, plate_index, shape))


## Fills hole (or pocket) `hole_index` of a plate back in.
func fill(plate_index: int, hole_index: int) -> Dictionary:
	return _frame_op(func(doc: AirframeDocument) -> Dictionary:
		return FrameTools.fill(doc, plate_index, hole_index))


func set_plate_thickness(plate_index: int, thickness_mm: float) -> Dictionary:
	return _frame_op(func(doc: AirframeDocument) -> Dictionary:
		return FrameTools.set_thickness(doc, plate_index, thickness_mm))


## Sets an arm's width, as a multiple of the arm as drawn (FrameTools.ARM_WIDTH_MIN..MAX).
func set_arm_width(plate_index: int, scale: float) -> Dictionary:
	return _frame_op(func(doc: AirframeDocument) -> Dictionary:
		return FrameTools.set_arm_width(doc, plate_index, scale))


## Runs one op on a COPY of the document, and adopts the copy (with one undo step) only on `ok`, so a
## refusal can leave nothing behind even if an op wrote before it refused.
func _frame_op(op: Callable) -> Dictionary:
	if _frame_doc == null:
		return FrameTools.refuse("This frame has no editable drawing.")
	if not frame_editable():
		return FrameTools.refuse("Frame edits are for the frame the drawing was made from; swap it back to edit.")
	var trial := AirframeDocument.from_dictionary(_frame_doc.to_dictionary())
	var verdict: Dictionary = op.call(trial)
	if not verdict.get("ok", false):
		return verdict
	_push_undo()
	_frame_doc = trial
	return verdict


func _snapshot() -> Dictionary:
	return {"selection": selection.duplicate(true),
		"document": _frame_doc.to_dictionary() if _frame_doc != null else {}}


func _restore(entry: Dictionary) -> void:
	selection = (entry["selection"] as Dictionary).duplicate(true)
	var doc: Dictionary = entry["document"]
	_frame_doc = AirframeDocument.from_dictionary(doc) if not doc.is_empty() else null


func _push_undo() -> void:
	_undo.append(_snapshot())
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Steps back one swap or frame edit. False if there is nothing to undo.
func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	return true


## Re-applies the last undone swap or frame edit. False if there is nothing to redo.
func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	return true
