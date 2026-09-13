class_name TestComponentRegistration
extends RefCounted
## THE FIVE LISTS THAT MUST STAY IN STEP, asserted together — control-room design §7, slice C4.
##
## Adding a component category touches five registrations that do not know about each other, and
## the failure mode of every one of them is SILENCE. A category with no mount is weighed at the
## origin; with no system it is on no rail; with no node prefix it never lights up; with no
## persistence entry it works until the file is reopened; with no picker it cannot be chosen at
## all. C2 watched two of these happen for real — adding `gps` and `buzzer` to the mass model
## silently broke `BuildPanel.CATEGORY_ORDER` and rendered both parts as raw category strings —
## and neither was caught by a check written for it.
##
## THE RULE THIS FILE IS WRITTEN UNDER, and it is the reason it exists as its own slice:
##
##   A CHECK DERIVED FROM THE TABLE IT ASSERTS CANNOT CATCH AN EDIT TO THAT TABLE.
##
## C3 measured that. Moving `gps` to Video inside `COMPONENT_SYSTEM` left its rail check GREEN,
## because the expected value and the actual value both came from the table that moved. So every
## row below asks a question only the CONSUMER can answer — does `MountLayout` really offer that
## bay id, does `GlassShell.SYSTEMS` really contain that system name, does an instantiated
## `LabScreen` really put it on exactly one rail — rather than comparing two constants that would
## agree with each other no matter what either one said.
##
## ONE ASSERTION PER COMPONENT PER PROPERTY, not one looping assertion over six names
## (`feedback_loop_tests_hide_coverage`): a looping test fails once, and the failure count stops
## meaning anything at exactly the moment you need it to mean something. Six components by five
## properties is thirty rows, and that is the point — deleting one registration reddens one row.

## The node a fitted component is drawn as, which is what `SYSTEM_NODE_PREFIXES` is matched against.
const NODE_PREFIX := "Component_"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var components: Array = Build.OPTIONAL_COMPONENTS

	# THE VACUITY GUARD, and it is not a formality. Every row below loops over this list, so an
	# empty or truncated one would make all thirty pass while asserting nothing whatsoever — the
	# worst possible version of a coverage file. Asserted as a positive count rather than
	# "not empty", so a component QUIETLY DROPPED from the mass model fails here too.
	results.append(TestResult.new(
		"the coverage list is the six optional components, so the thirty rows below are not vacuous",
		components.size() == 6,
		"%d components: %s" % [components.size(), components]))

	results.append_array(_every_component_has_a_bay_mount_layout_offers(components))
	results.append_array(_every_component_has_a_system_the_shell_knows(components))
	results.append_array(_every_component_lights_up_under_its_system(components))
	results.append_array(_every_component_persists(components))
	results.append_array(_every_component_is_claimed_by_exactly_one_rail(catalog, components))

	return results


## PROPERTY 1 — the mount, asked of `MountLayout`.
##
## `COMPONENT_MOUNTS` naming a bay proves nothing on its own: the consumer question is whether the
## id it names is one the layout actually BUILDS for a real frame. A typo'd id, or a bay removed
## from `_component_bays` while the table kept pointing at it, resolves to null — and
## `MountLayout.seated_centre_m(null, ...)` returns `Vector3.ZERO`, so the component is silently
## weighed at the origin instead of where it sits. That is the whole failure this row catches.
static func _every_component_has_a_bay_mount_layout_offers(components: Array) -> Array:
	var results: Array = []
	var mounts := ReferenceBuild.build().mount_points()

	var offered: Array[String] = []
	for mount in mounts:
		offered.append(String(mount.id))

	for category in components:
		var id := String(Build.COMPONENT_MOUNTS.get(category, ""))
		var bay: MountPoint = MountLayout.by_id(mounts, id) if id != "" else null
		results.append(TestResult.new(
			"%s sits on a bay MountLayout actually offers" % category,
			bay != null,
			"COMPONENT_MOUNTS says \"%s\"; MountLayout offers %s" % [id, offered]))
	return results


## PROPERTY 2 — the owning system, asked of `GlassShell.SYSTEMS`.
##
## `COMPONENT_SYSTEM` may name any string it likes; what matters is whether that string is a system
## the shell has. A component owned by "Contol" is owned by nothing, and every downstream lookup
## keyed on the system name returns empty rather than failing.
static func _every_component_has_a_system_the_shell_knows(components: Array) -> Array:
	var results: Array = []

	var shell_systems: Array[String] = []
	for entry in GlassShell.SYSTEMS:
		shell_systems.append(String(entry["name"]))

	for category in components:
		var system := String(Build.COMPONENT_SYSTEM.get(category, ""))
		results.append(TestResult.new(
			"%s is owned by a system GlassShell actually has" % category,
			system != "" and shell_systems.has(system),
			"COMPONENT_SYSTEM says \"%s\"; the shell has %s" % [system, shell_systems]))
	return results


## PROPERTY 3 — the node prefix, asked of the table the DIMMING reads.
##
## The consumer question is not "is there a prefix list" but "would this component's own node match
## a prefix under the system that owns it". A prefix filed under the wrong system dims the part
## when its own room is selected and lights it in somebody else's, which is invisible in a diff and
## obvious on screen — and which is exactly what `Component_receiver` did before C3, sitting under
## Control while the receiver was picked from Video.
static func _every_component_lights_up_under_its_system(components: Array) -> Array:
	var results: Array = []

	for category in components:
		var system := String(Build.COMPONENT_SYSTEM.get(category, ""))
		var node_name := NODE_PREFIX + String(category)
		var prefixes: Array = GlassShell.SYSTEM_NODE_PREFIXES.get(system, [])

		var matched := ""
		for prefix in prefixes:
			if node_name.begins_with(String(prefix)):
				matched = String(prefix)
				break

		results.append(TestResult.new(
			"%s lights up under %s, because a node prefix there matches it" % [
				category, system if system != "" else "(no system)"],
			matched != "",
			"node \"%s\" against %s's prefixes %s, matched \"%s\"" % [
				node_name, system, prefixes, matched]))
	return results


## PROPERTY 4 — persistence, asked of `ProjectSchema.all_categories()`.
##
## `all_categories()` rather than `OPTIONAL_CATEGORIES` on purpose: it is what the round trip, the
## unknown-field carry and the defaults all read, so it is the list whose contents actually decide
## whether a fitted component survives being saved and reopened. A category missing from it is a
## part that works all session and is gone the next time the file is opened — the one failure in
## this file that a builder discovers rather than a test.
static func _every_component_persists(components: Array) -> Array:
	var results: Array = []
	var persisted: Array = ProjectSchema.all_categories()

	for category in components:
		results.append(TestResult.new(
			"%s survives being saved and reopened, because the schema persists it" % category,
			persisted.has(category),
			"ProjectSchema.all_categories() = %s" % [persisted]))
	return results


## PROPERTY 5 — the rail, asked of an INSTANTIATED `LabScreen`.
##
## The strongest consumer question in the file, and the only one that builds real UI to ask it:
## after both rails are constructed, does exactly one of them carry this category, and does it
## browse under a written label rather than its raw category string. Two rails claiming it is a
## component a builder can set in two places that disagree; zero is a component that cannot be
## chosen at all, which is what `gps` and `buzzer` were between C2 and C3.
##
## Deliberately NOT `components_for_system(...)` compared against `COMPONENT_SYSTEM` — that is the
## circular shape this file's header refuses, and C3 proved it green under a table edit.
static func _every_component_is_claimed_by_exactly_one_rail(
		catalog: PartsCatalog, components: Array) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	for category in components:
		var carrying: Array[String] = []
		for rail in lab.component_rails():
			if rail.has_category(category):
				carrying.append(String(rail.name))

		var label := String(ElectronicsPicker.CATEGORY_LABELS.get(category, ""))
		results.append(TestResult.new(
			"%s is offered on exactly one rail, under a written label" % category,
			carrying.size() == 1 and label != "" and label != String(category),
			"carried by %d rail(s) %s, labelled \"%s\"" % [carrying.size(), carrying, label]))

	lab.free()
	return results
