class_name TestFieldRoom
extends RefCounted
## F10 — Field on the dock, and the viewport that shows the SITE.
##
## ---------------------------------------------------------------------------
## WHAT THIS SLICE CAN GET WRONG QUIETLY, AND WHAT EACH SECTION DOES ABOUT IT
## ---------------------------------------------------------------------------
##
## **A door that is in two places.** Field was reachable twice over — as a greyed overflow entry
## and as a Rooms-menu entry opening the old editor. Moving it to the dock and forgetting either
## half looks fine on screen: an extra menu row and a working icon. So §1 asserts the icon EXISTS
## and the overflow entry is GONE, and §7 asserts the Rooms menu's remaining entries against a
## literal list rather than against "field_editor is missing" alone — a second entry going with it
## would be silent otherwise.
##
## **A viewport swap that only goes one way.** Selecting Field hides Lab's viewport and shows the
## room's. A swap that never swaps back leaves the site on screen under a Power inspector, and a
## check that only looks at the Field half passes against it. §3 asserts both directions.
##
## **A camera that looks like it frames the site and does not.** Lab's camera distance is a
## constant computed once; if Field's were too, a 30 m park and a 400 m field would render
## identically and neither would look obviously wrong — both are a field with gates on it. §4 asks
## the SAME function for two sites and requires two answers, and then asks the camera where it
## actually is, because a distance function nothing applies is a distance function that cannot be
## wrong.
##
## **A silhouette that is a marker rather than the aircraft.** A plate drawn at a convenient size
## at the start gate looks exactly like one drawn at `airframe_span_m()`. §6 compares it with the
## build's own span, computed from the build rather than read back off the plate.
##
## The layout half of this slice — the three panels fitting 1280x720 — is NOT here. It has no
## answer until a container has run, and `tests/run_tests.gd` renders no frames; it lives in
## `tests/test_shell_layout.gd`, which is the one suite that waits.

## The room's two levels and its three panels, written out rather than read off `FieldSystem`.
##
## The two sides of every check in §5 and §6 have to come from different places or the check is a
## tautology: the room's side is walked off the live node tree, and this side is the specification.
## A shared constant would have passed a rename of both halves.
const RAIL_NAMES := ["Sites", "Courses"]
const PANEL_NAMES := ["Site", "Course", "Conditions"]

## What `RoomMenu` is left offering once Field has gone. A literal, so a slice that removes a
## second entry while removing Field fails here instead of passing a "field_editor is absent"
## check that a demolition also satisfies.
const ROOMS_STILL_IN_THE_MENU := ["frame_bench", "studio"]

## Two sites an order of magnitude apart. A park you could throw a whoop across and a field you
## could lose a 10" in — if one camera distance frames both, the number is not the site's.
const SMALL_SITE_M := 30.0
const LARGE_SITE_M := 400.0


static func run() -> Array:
	var results: Array = []
	# The hold is taken HERE and released HERE, for `tests/real_files.gd`'s reason: `GlassShell.new()`
	# reads `user://sites.json`, `user://courses.json` and `user://conditions.json` by name, and a
	# restore written at the end of a section is skipped by exactly the abort it most needs to
	# survive.
	var held := RealFiles.hold([
		SiteLibrary.SAVE_PATH, CourseLibrary.SAVE_PATH, ConditionsLibrary.SAVE_PATH,
		AppSettings.SAVE_PATH])
	var sections := {
		"the dock": _the_dock(),
		"the shell entry": _the_shell_entry(),
		"the viewport swap": _the_viewport_swap(),
		"the camera frames the site": _the_camera_frames_the_site(),
		"the two-level rail": _the_two_level_rail(),
		"the three panels": _the_three_panels(),
		"the conditions selector": _the_conditions_selector(),
		"the rooms menu": _the_rooms_menu(),
		"the drone silhouette": _the_drone_silhouette(),
	}
	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))
	# A runtime error partway through a section aborts only that section and its append never runs,
	# so the suite would pass with its best checks silently deleted.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 1. Field is on the dock, and is no longer in the overflow menu
# ---------------------------------------------------------------------------

static func _the_dock() -> Array:
	var results: Array = []
	var dock := Dock.new(GlassShell.SYSTEMS, StyleBoxEmpty.new())

	# THE ICON, FOUND ON THE LIVE ROW rather than by reading `ICONED_SYSTEMS` back to itself. The
	# constant is what the dock is built FROM, so asserting Field is in it proves only that the
	# word was typed; what has to be true is that a button called Field is standing in the row.
	var icon_names: Array[String] = []
	for button in dock.system_buttons:
		icon_names.append(str(button.name))
	results.append(TestResult.new(
		"a system icon called \"Field\" is standing in the dock's row",
		icon_names.has("Field"),
		"the icons are %s" % [icon_names]))

	# AND THE OVERFLOW MENU HAS LET IT GO. Guarded on the menu existing and holding SOMETHING
	# first: an empty popup satisfies "Field is not in it" under every mutation, which is this
	# project's twice-shipped defect (two "(no such row)" strings compare equal).
	var popup := dock.more_menu.get_popup()
	var overflow: Array[String] = []
	for index in popup.item_count:
		overflow.append(str(popup.get_item_text(index)))
	results.append(TestResult.new(
		"the overflow menu is still a menu — it has entries for the systems that have no icon",
		popup.item_count > 0,
		"the overflow offers %s" % [overflow]))
	var named_field := false
	for text in overflow:
		if text.begins_with("Field"):
			named_field = true
	results.append(TestResult.new(
		"and Field is not one of them — it is on the dock, not behind the ···",
		not named_field,
		"the overflow offers %s" % [overflow]))
	dock.free()
	return results


# ---------------------------------------------------------------------------
# 2. The shell's own entry for Field is a real system now
# ---------------------------------------------------------------------------

static func _the_shell_entry() -> Array:
	var results: Array = []
	var entry := _system("Field")

	results.append(TestResult.new(
		"GlassShell.SYSTEMS has an entry called \"Field\"",
		not entry.is_empty(),
		"the systems are %s" % [_system_names()]))
	if entry.is_empty():
		return results

	results.append(TestResult.new(
		"Field's rails are the two levels of the field — sites, then that site's courses",
		entry.get("rails", []) == RAIL_NAMES,
		"rails %s" % [entry.get("rails", [])]))
	results.append(TestResult.new(
		"and its panels are §5.2's three, by name",
		entry.get("panels", []) == PANEL_NAMES,
		"panels %s" % [entry.get("panels", [])]))
	# THE STUB KEY IS ABSENT, not empty. A `"stub": {}` left behind would render nothing and read
	# as a fix; what it would actually be is the next person's reason to fill it back in.
	results.append(TestResult.new(
		"and the stub is GONE — the key is absent, not blanked",
		not entry.has("stub"),
		"keys %s" % [entry.keys()]))
	results.append(TestResult.new(
		"so the shell counts Field as modelled and shows it real columns rather than a stub",
		GlassShell._is_modelled(entry),
		"rails %s · panels %s" % [entry.get("rails", []), entry.get("panels", [])]))
	return results


# ---------------------------------------------------------------------------
# 3. Selecting Field swaps the viewport — and selecting anything else swaps it BACK
# ---------------------------------------------------------------------------

static func _the_viewport_swap() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	var lab_view := shell.lab.viewport().get_parent() as Control
	var room := shell.field_room()

	results.append(TestResult.new(
		"the shell built a Field room with a viewport of its own to swap TO",
		room != null and room.viewport_container != null and lab_view != null,
		"room %s · site view %s · lab view %s" % [
			room != null, room != null and room.viewport_container != null, lab_view != null]))
	if room == null or lab_view == null:
		shell.free()
		return results

	shell.select_system_by_name("Field")
	var field_up := room.visible
	var drone_down := not lab_view.visible
	results.append(TestResult.new(
		"choosing Field puts the site on screen and takes the drone off it",
		field_up and drone_down,
		"the field room is visible %s · Lab's viewport is visible %s" % [
			field_up, lab_view.visible]))

	# THE OTHER DIRECTION, which is the half a one-way swap passes. Power rather than Airframe:
	# Airframe hides Lab's viewport too, so it would report "still hidden" for its own reason and
	# say nothing about whether Field put anything back.
	shell.select_system_by_name("Power")
	var field_down := not room.visible
	var drone_back := lab_view.visible
	results.append(TestResult.new(
		"and choosing another system swaps it back — the drone returns and the site goes away",
		field_down and drone_back,
		"the field room is visible %s · Lab's viewport is visible %s" % [
			room.visible, lab_view.visible]))

	# The chrome the room needs the space of, asserted while Field is up. The shell's own two
	# columns would otherwise float over a room that brings its own.
	shell.select_system_by_name("Field")
	results.append(TestResult.new(
		"and Field owns the window: the shell's rail column and its inspector are both down",
		not shell._rail_glass.visible and not shell._inspector.visible,
		"rail %s · inspector %s" % [shell._rail_glass.visible, shell._inspector.visible]))
	shell.free()
	return results


# ---------------------------------------------------------------------------
# 4. The camera frames the SITE
# ---------------------------------------------------------------------------

static func _the_camera_frames_the_site() -> Array:
	var results: Array = []
	var world := _scratch_field(SMALL_SITE_M)
	var room: FieldSystem = world["room"]
	var sites: SiteLibrary = world["sites"]

	# THE FUNCTION IS CALLED, not inferred from what the camera happens to be doing. A check that
	# asserted the camera's position alone would pass against a distance computed anywhere.
	var near_m := room.camera_distance_m()
	results.append(TestResult.new(
		"a 30 m site gives a real camera distance rather than zero or a divide-by-nothing",
		near_m > 0.0 and is_finite(near_m),
		"%.1f m out from a %.0f m site" % [near_m, SMALL_SITE_M]))

	# AND THE CAMERA IS ACTUALLY THERE. `global_transform` is IDENTITY for a Node3D outside the
	# tree, so this reads the camera's own position on its pivot — which is where `_refresh_world`
	# puts it, and which is the whole of the framing.
	# A MILLIMETRE, and the tolerance is not slack. A `Vector3` holds 32-bit floats while this
	# arithmetic runs in 64, so a distance of 39.229 m stored and read back differs in the seventh
	# significant figure — the same storage fact `GateCourse.PLACEMENT_MARGIN` exists because of. A
	# millimetre out of 39 m is four orders of magnitude tighter than the difference the next check
	# demands, so nothing real can hide under it.
	results.append(TestResult.new(
		"and the camera is standing at that distance, not merely able to compute it",
		absf(room.camera().position.z - near_m) < 1.0e-3,
		"camera at %.5f m, function says %.5f m" % [room.camera().position.z, near_m]))

	sites.selected().terrain = Terrain.flat(LARGE_SITE_M, LARGE_SITE_M)
	room.refresh()
	var far_m := room.camera_distance_m()
	results.append(TestResult.new(
		"a 400 m site pulls the camera further back than a 30 m one — the distance is the SITE'S",
		far_m > near_m * 2.0,
		"%.1f m for %.0f m of field, against %.1f m for %.0f m" % [
			far_m, LARGE_SITE_M, near_m, SMALL_SITE_M]))

	# A GATE MOVING MUST NOT MOVE THE CAMERA. Dragging a ring would otherwise reframe the whole
	# field under the builder's hand, which is the failure "frames the site" is chosen over "frames
	# the course" to avoid.
	var course := room.course()
	course.gates[0]["position"] += Vector3(7.0, 3.0, -5.0)
	room.refresh()
	var after_drag := room.camera_distance_m()
	results.append(TestResult.new(
		"and moving a gate does not move the camera — the course is not what is being framed",
		absf(after_drag - far_m) < 1.0e-9,
		"%.6f m before the gate moved, %.6f m after" % [far_m, after_drag]))
	room.free()
	return results


# ---------------------------------------------------------------------------
# 5. The rail is two-level
# ---------------------------------------------------------------------------

static func _the_two_level_rail() -> Array:
	var results: Array = []
	var world := _scratch_field(SMALL_SITE_M)
	var room: FieldSystem = world["room"]
	var sites: SiteLibrary = world["sites"]
	var courses: CourseLibrary = world["courses"]

	results.append(TestResult.new(
		"the rail has two lists and they are the two levels — sites, and that site's courses",
		room.site_list != null and room.course_list != null
			and str(room.site_list.name) == RAIL_NAMES[0]
			and str(room.course_list.name) == RAIL_NAMES[1],
		"the lists are named %s and %s" % [
			"—" if room.site_list == null else str(room.site_list.name),
			"—" if room.course_list == null else str(room.course_list.name)]))

	# A SECOND PLACE, WITH TWO ROUTES OF ITS OWN. Two at the far site, one here, and the library's
	# own default course at the default site — so "all the courses in the file" (4) and "the
	# courses at this site" (1, then 2) are different numbers in both directions. With one course
	# apiece the two readings agree and the check could not fail.
	var far_site := sites.create("Far field")
	var first_there := courses.create("Over there")
	first_there.site_id = far_site.site_id
	var second_there := courses.create("Over there too")
	second_there.site_id = far_site.site_id
	room.refresh()

	results.append(TestResult.new(
		"with the near site selected the second list shows ITS course and not the file's four",
		room.course_list.item_count == 1 and courses.ids().size() == 4,
		"%d of %d courses listed" % [room.course_list.item_count, courses.ids().size()]))

	# THE FUNCTION THE CLICK CALLS, called. Asserting the outcome of a click and trusting the right
	# function produced it is how four F8 defects passed.
	var far_index := sites.ids().find(far_site.site_id)
	room.choose_site(far_index)
	results.append(TestResult.new(
		"choosing a site selects its FIRST course, so the panels never describe a route from elsewhere",
		courses.selected().course_id == first_there.course_id,
		"selected %s, wanted %s" % [courses.selected().course_id, first_there.course_id]))
	results.append(TestResult.new(
		"and the second list is now that site's two, not the near site's one and not all four",
		room.course_list.item_count == 2,
		"%d listed of %d in the file" % [room.course_list.item_count, courses.ids().size()]))
	room.free()
	return results


# ---------------------------------------------------------------------------
# 6. The three panels, and the density the Conditions one is for
# ---------------------------------------------------------------------------

static func _the_three_panels() -> Array:
	var results: Array = []
	var world := _scratch_field(SMALL_SITE_M)
	var room: FieldSystem = world["room"]
	var sites: SiteLibrary = world["sites"]

	# One check per panel rather than a loop over three — a looping check fails once and names the
	# loop rather than the panel that went missing.
	for title in PANEL_NAMES:
		results.append(TestResult.new(
			"the room has a panel called \"%s\"" % title,
			room.panel(title) != null,
			"the panels are %s" % [PANEL_NAMES]))

	# THIN AIR, SO THE PERCENTAGE IS A NUMBER AND NOT ZERO. At sea level the row would read "0.0%"
	# and a dropped row and a correct one would be equally uninformative.
	sites.selected().elevation_m = 3000.0
	room.refresh()
	var conditions_panel := room.panel(PANEL_NAMES[2])
	if conditions_panel == null:
		return results
	var rows := _rows_of(conditions_panel)

	# GUARDED ON THE ROW EXISTING before its text is compared with anything. Two missing rows
	# render as the same empty string and compare equal under every mutation.
	results.append(TestResult.new(
		"the Conditions panel has a row for the derived air density",
		rows.has("Air density"),
		"the rows are %s" % [rows.keys()]))
	results.append(TestResult.new(
		"and a row for how far below standard that density is",
		rows.has("Below standard"),
		"the rows are %s" % [rows.keys()]))
	if not (rows.has("Air density") and rows.has("Below standard")):
		room.free()
		return results

	# The expected numbers come from `AirDensity` — the model this panel RENDERS — rather than from
	# the panel, which is the subject under test. TestAirDensity is what guards the arithmetic
	# itself, against the published ISA table.
	var air := AirDensity.compose(sites.selected(), ConditionsLibrary.with_default().selected())
	var wanted_density := "%.4f" % air.kgm3()
	var wanted_percent := "%.1f" % (air.fraction_below_standard() * 100.0)
	results.append(TestResult.new(
		"the density row quotes the air composed from this site's elevation and these conditions",
		str(rows["Air density"]).contains(wanted_density),
		"row reads \"%s\", wanted %s kg/m³" % [rows["Air density"], wanted_density]))
	results.append(TestResult.new(
		"and the percentage is a real shortfall at 3000 m, not a rounded-off zero",
		str(rows["Below standard"]).contains(wanted_percent)
			and air.fraction_below_standard() > 0.2,
		"row reads \"%s\", wanted %s%% (fraction %.4f)" % [
			rows["Below standard"], wanted_percent, air.fraction_below_standard()]))
	room.free()
	return results


# ---------------------------------------------------------------------------
# 7. §5.3 — the conditions selector is reachable from the GARAGE
# ---------------------------------------------------------------------------

static func _the_conditions_selector() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	# A system that is NOT Field, deliberately: the whole claim is that the selector is reachable
	# without walking into the field.
	shell.select_system_by_name("Power")
	var picker := shell.conditions_picker()

	results.append(TestResult.new(
		"the shell has a conditions selector",
		picker != null,
		"picker %s" % [picker != null]))
	if picker == null:
		shell.free()
		return results

	# IN THE TOP STRIP, walked up from the control rather than asserted about a member. A selector
	# built and left unparented is a selector nobody can reach, and `shell._conditions_picker` would
	# still point at it.
	var in_top_bar := false
	var walk: Node = picker
	while walk != null:
		if walk == shell._top_bar:
			in_top_bar = true
			break
		walk = walk.get_parent()
	results.append(TestResult.new(
		"and it is in the garage's own top strip, with a system other than Field focused",
		in_top_bar and picker.visible and shell._top_bar.visible,
		"in the top bar %s · the strip is visible %s" % [in_top_bar, shell._top_bar.visible]))

	var library := shell.rooms.conditions_library
	results.append(TestResult.new(
		"it offers every named set the library holds, and the library holds at least one",
		picker.item_count == library.ids().size() and picker.item_count >= 1,
		"%d entries for %d sets" % [picker.item_count, library.ids().size()]))

	# AND SWITCHING IT MOVES THE GARAGE. A selector that changes nothing is a decoration, and §5.3's
	# whole argument is the flight time that silently means "in calm air".
	var windy := Conditions.new()
	windy.conditions_id = "f10_windy"
	windy.conditions_name = "F10 windy"
	windy.wind_speed_mps = 7.5
	windy.temperature_c = 35.0
	library.put(windy)
	shell._fill_conditions_picker()
	var at := -1
	for index in picker.item_count:
		if str(picker.get_item_text(index)) == windy.conditions_name:
			at = index
	results.append(TestResult.new(
		"the set just authored appears in the strip without leaving the garage",
		at >= 0,
		"looked for \"%s\" among %d entries" % [windy.conditions_name, picker.item_count]))
	if at >= 0:
		# Through the control's own signal, which is the path a click takes.
		picker.item_selected.emit(at)
		results.append(TestResult.new(
			"and choosing it moves the garage's wind and the name it quotes under",
			absf(shell.lab.wind_mps - windy.wind_speed_mps) < 1.0e-6
				and shell.lab.conditions_name == windy.conditions_name,
			"Lab quotes %.2f m/s under \"%s\"" % [shell.lab.wind_mps, shell.lab.conditions_name]))
	shell.free()
	return results


# ---------------------------------------------------------------------------
# 8 and 9. The Rooms menu
# ---------------------------------------------------------------------------

static func _the_rooms_menu() -> Array:
	var results: Array = []
	var ids := RoomMenu.room_ids()
	# BY ID, not by label — a label is prose and a rename would fail this for the wrong reason.
	results.append(TestResult.new(
		"the Rooms menu no longer offers \"field_editor\" — Field is a destination on the dock now",
		not ids.has("field_editor"),
		"the menu offers %s" % [ids]))
	# AND NOTHING ELSE WENT WITH IT, against a literal. "field_editor is absent" is also true of an
	# empty menu, which is the deletion this second line exists to catch.
	results.append(TestResult.new(
		"and the entries that remain are exactly the ones that were not this slice's to move",
		ids == ROOMS_STILL_IN_THE_MENU,
		"the menu offers %s, wanted %s" % [ids, ROOMS_STILL_IN_THE_MENU]))
	return results


# ---------------------------------------------------------------------------
# 10. The drone silhouette (§11 Q1, built ON)
# ---------------------------------------------------------------------------

static func _the_drone_silhouette() -> Array:
	var results: Array = []
	var world := _scratch_field(SMALL_SITE_M)
	var room: FieldSystem = world["room"]
	var build: Build = world["build"]

	var plate := room.silhouette()
	results.append(TestResult.new(
		"the room draws a drone silhouette, and it is in the site's own world",
		plate != null and plate.get_parent() == room.world()
			and str(plate.name) == FieldSystem.SILHOUETTE_NAME,
		"silhouette %s" % ["absent" if plate == null else str(plate.name)]))
	if plate == null:
		room.free()
		return results

	results.append(TestResult.new(
		"it is on by default, so §11's question is answered by looking rather than by arguing",
		room.show_drone_silhouette and plate.visible,
		"flag %s · visible %s" % [room.show_drone_silhouette, plate.visible]))

	# THE SPAN COMES FROM THE BUILD, not from the plate. A golden read back off the mesh would
	# agree with any size it happened to be.
	var span := build.airframe_span_m()
	var box := plate.mesh as BoxMesh
	results.append(TestResult.new(
		"and it is drawn at the aircraft's real span — the same number a ring is warned against",
		box != null and span > 0.0 and absf(box.size.x - span) < 1.0e-6
			and absf(box.size.z - span) < 1.0e-6,
		"plate %s across, the build spans %.4f m" % [
			"—" if box == null else "%.4f × %.4f m" % [box.size.x, box.size.z], span]))
	# A 1 m marker is the mutation, and the reference build is nowhere near 1 m across — stated so
	# that "equals the span" is visibly not also "equals a convenient round number".
	results.append(TestResult.new(
		"and the span is not itself a round number a fixed-size marker would match by accident",
		absf(span - 1.0) > 0.1,
		"the build spans %.4f m" % span))

	results.append(TestResult.new(
		"it stands at the start gate, on the ground the site describes",
		plate.position.distance_to(room.course().start_position(room.site().terrain)) < 1.0e-5,
		"plate at %s, start line at %s" % [
			plate.position, room.course().start_position(room.site().terrain)]))

	# NOT THE LAB MODEL. The design says "not the Lab model" and the cheap way to satisfy the span
	# check would have been to drop an `AirframeModel` in and scale it — which brings a whole
	# aircraft's meshes, its motors and its turning props into a picture of a field.
	results.append(TestResult.new(
		"and it is a footprint rather than Lab's aircraft — no AirframeModel is in this world",
		not _holds_an_airframe_model(room.world()),
		"the world holds %d nodes" % room.world().get_child_count()))
	room.free()
	return results


static func _holds_an_airframe_model(node: Node) -> bool:
	for child in node.get_children():
		if child is AirframeModel or _holds_an_airframe_model(child):
			return true
	return false


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A Field room over libraries built in memory — one site of the given size with one course on it.
##
## Built through the libraries' own `create`/`put`, never through the room, so no fixture here is
## made by the code a check is about.
static func _scratch_field(size_m: float) -> Dictionary:
	var sites := SiteLibrary.with_default()
	var here := sites.create("F10 field")
	here.terrain = Terrain.flat(size_m, size_m)
	sites.select(here.site_id)

	var courses := CourseLibrary.with_default()
	var route := courses.create("F10 circuit")
	route.site_id = here.site_id
	courses.select(route.course_id)

	var build := ReferenceBuild.build()
	var room := FieldSystem.new(sites, courses, ConditionsLibrary.with_default(), build)
	return {"room": room, "sites": sites, "courses": courses, "build": build}


## A panel's rendered rows as label → value. Parsed off `SpecPanel.rendered_text()`, the seam every
## other panel suite reads through.
static func _rows_of(panel: SpecPanel) -> Dictionary:
	var out: Dictionary = {}
	for line in panel.rendered_text().split("\n"):
		var at := str(line).find(": ")
		if at > 0:
			out[str(line).substr(0, at)] = str(line).substr(at + 2)
	return out


static func _system(system_name: String) -> Dictionary:
	for system in GlassShell.SYSTEMS:
		if str(system["name"]) == system_name:
			return system
	return {}


static func _system_names() -> Array:
	var names: Array = []
	for system in GlassShell.SYSTEMS:
		names.append(str(system["name"]))
	return names
