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
## Where a deleted drone goes. A subdirectory of DIR rather than a sibling, so it is reachable
## from the same "Reveal saved files" folder the builder already knows.
const TRASH_SUBDIR := "trash"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


static func path_for(project: Project) -> String:
	return "%s/%s.%s" % [DIR, project.project_id, ProjectContainer.EXTENSION]


## Moves a container into the app's trash — a rename, never a delete (§10 of the projects design).
##
## Deletion is reversible by construction: the file still exists, one Finder step away in
## `user://builds/trash/`, and nothing empties that directory automatically. The easy version —
## unlink with a confirmation dialog — makes losing a month of design one misplaced click, which is
## exactly what the trash exists to prevent.
##
## A container opened from anywhere on disk moves the same way one born in `user://builds` does:
## the trash is app-owned, the source path is irrelevant. Nothing here deletes anything.
static func delete(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	ensure_dir()
	var trash := "%s/%s" % [DIR, TRASH_SUBDIR]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trash))
	var target := "%s/%s" % [trash, path.get_file()]
	# A container can only be deleted once, so a collision is near-impossible; if one somehow
	# occurs, move under a suffixed name rather than clobbering whatever is already there.
	var attempt := 0
	while FileAccess.file_exists(target):
		attempt += 1
		target = "%s/%s-%d.%s" % [trash, path.get_file().get_basename(), attempt,
			path.get_file().get_extension()]
	if DirAccess.rename_absolute(path, target) != OK:
		push_warning("could not move %s to the trash" % path)


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
##
## The default name is NOT the literal "Untitled build" any more. Every New was named that, so a
## wall of identical drones accumulated and deleting one was indistinguishable from having done
## nothing — the replacement had the same name as the thing removed. The default now comes from
## what is already on disk; see _default_build_name.
static func starting_project(p_name: String = "") -> Project:
	var project := Project.create(p_name if p_name != "" else _default_build_name())
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	for category in Build.OPTIONAL_COMPONENTS:
		project.parts[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	return project


## What a new drone is called when the builder did not name it: the next number past the highest
## "Untitled build N" already on disk.
##
## The builds folder AND the trash are scanned, so a number is never reused while a copy of that
## name still exists anywhere — "Untitled build 4" deleted to the trash is not a free slot until
## it is gone from both. Numbers skip if a builder renamed one; skipping is fine, reuse is not.
static func _default_build_name() -> String:
	ensure_dir()
	var highest := -1
	for folder in [DIR, "%s/%s" % [DIR, TRASH_SUBDIR]]:
		var absolute := ProjectSettings.globalize_path(folder)
		if not DirAccess.dir_exists_absolute(absolute):
			continue
		for file in DirAccess.get_files_at(absolute):
			if not file.ends_with(".%s" % ProjectContainer.EXTENSION):
				continue
			var number := _untitled_number(ProjectContainer.read_name("%s/%s" % [folder, file]))
			if number > highest:
				highest = number
	if highest < 0:
		return "Untitled build"
	return "Untitled build %d" % (highest + 1)


## "Untitled build" -> 0, "Untitled build 12" -> 12, anything else -> -1 (not a default name).
static func _untitled_number(name: String) -> int:
	if name == "Untitled build":
		return 0
	if not name.begins_with("Untitled build "):
		return -1
	var suffix := name.substr("Untitled build ".length())
	return int(suffix) if suffix.is_valid_int() else -1


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
