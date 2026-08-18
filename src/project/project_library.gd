class_name ProjectLibrary
extends RefCounted
## Where drones live on disk, and the three operations that make one: start, duplicate, remember.
##
## Deliberately thin, and static. The container knows how to read and write a file; this knows
## where files go and what a new one contains. Keeping them apart is what lets a builder save a
## drone anywhere they like — nothing in ProjectContainer has an opinion about directories.
##
## ---------------------------------------------------------------------------
## A NEW DRONE IS WRITTEN IMMEDIATELY, AND THAT IS THE WHOLE POINT
## ---------------------------------------------------------------------------
##
## §5 settles that there is no save button. The consequence people miss is that **a document with
## no path cannot autosave**, so "no save button" plus "new drone" plus "no path" is a design in
## which work is lost by default until someone remembers to save it — which is the behaviour the
## save button existed to fix.
##
## So a new drone gets a home the moment it exists: `user://builds/<project_id>.lothal`. It is
## named after the id and not the name, because a rename must never move a file, two drones may
## be called "5 inch", and a name may contain a slash. Reveal saved files opens that folder, and
## Open… can still open a container anywhere on disk.

const DIR := "user://builds"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


static func path_for(project: Project) -> String:
	return "%s/%s.%s" % [DIR, project.project_id, ProjectContainer.EXTENSION]


## What "New drone" starts from.
##
## The reference build, and NOT an empty canvas. §5: "a blank canvas is the worst possible first
## screen for someone who doesn't know what a 2207 is." This is a stand-in for the launcher's four
## real starting builds (W0.5b) — one known-good 5" freestyle rather than four, because inventing
## three more starting points is catalog work, not shell work, and a made-up starting build would
## be exactly the kind of invention §9 forbids.
##
## The four optional bays are fitted with their defaults, which is what makes this weigh the
## reference build's 496 g rather than 475 g. A project created by Project.create() fits nothing
## optional on purpose — see ProjectSchema rule 2 — and that is right for a document read off
## disk and wrong for a drone somebody just asked for.
static func starting_project(p_name: String = "Untitled build") -> Project:
	var project := Project.create(p_name)
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	for category in Build.OPTIONAL_COMPONENTS:
		project.parts[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	return project


## A copy of `source`: same decisions, new identity, its own history.
##
## **Versions are not copied**, and that is a decision rather than an omission. Duplicate is how
## comparison works (§5) — duplicate, change the pack, flip between them — and a copy that carried
## the original's named versions would let a builder restore, inside the variant, a state that
## belongs to the drone they were comparing it against. A duplicate starts its own history from
## the moment it is made.
##
## Print records are not copied either, for a stronger reason: they are records of physical
## objects. The camera mount on the bench was printed for the original. Copying the record would
## claim a part exists for a drone that has never been built.
static func duplicate_of(source: Project) -> Project:
	var copy := Project.create(_copy_name(source.name))
	copy.parts = source.parts.duplicate(true)
	copy.assembly = source.assembly.duplicate(true)
	copy.tune = source.tune.duplicate(true)
	copy.air = source.air.duplicate(true)
	copy.printing = source.printing.duplicate(true)
	copy.notes = source.notes
	return copy


## "Weekend 5" -> "Weekend 5 copy" -> "Weekend 5 copy 2". Suffixing rather than prefixing so the
## two sort next to each other in any list, which is the whole reason a builder duplicated it.
static func _copy_name(name: String) -> String:
	if not name.ends_with(" copy") and not _ends_with_copy_number(name):
		return "%s copy" % name
	if name.ends_with(" copy"):
		return "%s 2" % name
	var parts := name.split(" ")
	var last := int(parts[parts.size() - 1])
	parts.remove_at(parts.size() - 1)
	return "%s %d" % [" ".join(parts), last + 1]


static func _ends_with_copy_number(name: String) -> bool:
	var parts := name.split(" ")
	if parts.size() < 3:
		return false
	return parts[parts.size() - 2] == "copy" and String(parts[parts.size() - 1]).is_valid_int()
