class_name DesignSession
extends RefCounted
## The Design Space's drone: the selection of part ids it opens on, and the one method that turns
## that selection into a `Build` (PLAN §3). No Node, no drawing.
##
## THIS IS ONLY THE SEED OF SECTION 0's SESSION. It holds the selection and builds it; the fitted
## document, frame edits, undo and the current pick arrive with Sections 0–4. It exists now
## because the class picker decides which drone the Design Space opens on, and that claim needs
## one place to be true in and tested against.
##
## The build goes through `Project.to_build`, the same path a saved drone flies by, so the Design
## Space can never open on a different aircraft from the one the project file describes.

var drone_class: String = ""
## category -> part id, dense over ProjectSchema.all_categories().
var selection: Dictionary = {}
var _project: Project


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
	var b := build(catalog)
	if b == null:
		return {}
	return {
		"auw_g": b.all_up_weight_g(),
		"thrust_to_weight": b.thrust_to_weight(),
		"hover_throttle": b.hover_throttle(),
		"flight_time_min": b.flight_time_min(),
		"top_speed_kmh": b.top_speed_kmh(),
	}
