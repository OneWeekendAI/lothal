class_name DesignSession
extends RefCounted
## The Design Space's drone: the selection of part ids it opens on, and the one method that turns
## that selection into a `Build` (PLAN §3). No Node, no drawing.
##
## It holds the selection, builds it, and keeps the undo/redo history of swaps (Section 3); the
## fitted document and frame edits arrive with Section 4. It exists now
## because the class picker decides which drone the Design Space opens on, and that claim needs
## one place to be true in and tested against.
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


## The session a project opens into. Reads the project's parts; the project is not kept live, so
## an edit in the session never writes the file behind the builder's back.
static func from_project(project: Project) -> DesignSession:
	var session := DesignSession.new()
	session._project = Project.from_dict(project.to_dict())
	session.drone_class = project.drone_class
	session.selection = project.parts.duplicate(true)
	return session


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
	return trial


## The selection as physics. Null if a required part is missing from `catalog`.
func build(catalog: PartsCatalog) -> Build:
	_project.parts = selection.duplicate(true)
	return _project.to_build(catalog)


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
	_undo.append(selection.duplicate(true))
	_redo.clear()
	selection[category] = part_id
	return verdict


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Steps back one swap. False if there is nothing to undo.
func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(selection.duplicate(true))
	selection = _undo.pop_back()
	return true


## Re-applies the last undone swap. False if there is nothing to redo.
func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(selection.duplicate(true))
	selection = _redo.pop_back()
	return true
