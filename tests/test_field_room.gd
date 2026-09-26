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
## The shipped Sim scene as a script, so its wiring can be CALLED. `main.gd` carries no
## `class_name` (it is a scene script), which is why this is a preload rather than a bare name.
const MAIN_SCRIPT := preload("res://src/scenes/main.gd")
const RAIL_NAMES := ["Sites", "Courses"]
const PANEL_NAMES := ["Site", "Course", "Conditions"]

## What `RoomMenu` is left offering once Field has gone. A literal, so a slice that removes a
## second entry while removing Field fails here instead of passing a "field_editor is absent"
## check that a demolition also satisfies.
const ROOMS_STILL_IN_THE_MENU := ["frame_bench", "studio"]

## Two sites an order of magnitude apart. A park you could throw a whoop across and a field you
## could lose a 10" in — if one camera distance frames both, the number is not the site's.
## The Sim scene the app boots through `RoomHost.show_sim` — the scene FILE, not the script, so
## `main.gd`'s `@onready` node paths resolve. Spelled out of `RoomHost.SIM_SCENE` deliberately:
## this suite asserts what the shipped scene does, and a constant shared with the thing under
## test would follow it if it moved.
const SIM_SCENE_PATH := "res://src/scenes/main.tscn"

## A settling time no default anywhere in the repo uses, so a scene flying the default is
## distinguishable from a scene flying the record.
const BOOT_GUST_TAU_S := 4.2

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
		AppSettings.SAVE_PATH, PackCharge.SAVE_PATH])
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
		# F11 — the authoring, and the port of everything the old screen pinned.
		"editing gates": _editing_gates(),
		"the renderer follows": _the_renderer_follows(),
		"courses": _courses(),
		"what sim flies": _it_writes_what_sim_flies(),
		"a drag lands on the terrain": _a_drag_lands_on_the_terrain(),
		"the three sliders": _the_three_sliders(),
		"outside the site extent": _outside_the_site_extent(),
		"warnings refresh": _warnings_refresh_after_every_edit(),
		"it costs nothing": _it_costs_nothing(),
		"the field itself": _the_field_itself(),
		"the old editor is gone": _the_old_editor_is_gone(),
		"the preview is the terrain": _the_preview_is_the_terrain(),
		"the editable fields": _the_editable_fields(),
		"the wind fields": _the_wind_fields(),
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

	# AND IT IS A WORD ON THE ROW, NOT BEHIND A MENU (lab dock design §2: the nine sections are all
	# words; the ··· overflow is gone). Asserted on the button's own text, so a Field button that
	# lost its word would fail here.
	var word := ""
	for button in dock.system_buttons:
		if str(button.name) == "Field":
			word = button.text
	results.append(TestResult.new(
		"and it reads \"Field\" on the row — there is no overflow menu to hide it behind",
		word == "Field", "the Field button reads '%s'" % word))
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

	# Since the lab dock the Field room is the PAGE of Field's rows (design §4): choosing the
	# section shows its list over the drone, and opening a row puts the site on the stage.
	shell.select_system_by_name("Field")
	shell.open_row(&"course")
	var field_up := room.visible
	var drone_down := not lab_view.visible
	results.append(TestResult.new(
		"opening a Field row puts the site on screen and takes the drone off it",
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
	shell.open_row(&"site")
	results.append(TestResult.new(
		"and Field owns the stage: the shell's rail column and its inspector are both down",
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


# ===========================================================================
# F11 — COURSE EDITING INSIDE THE ROOM
# ===========================================================================
#
# EVERY SECTION BELOW EXCEPT THE LAST FIVE IS A PORT. `tests/test_field_editor.gd` pinned the old
# screen's behaviour and the old screen is gone; a port's failure mode is not a broken check, it is
# a behaviour that quietly stopped being guaranteed and took its assertion with it. So the ported
# sections keep the ORIGINAL WORDING of every assertion they carry, and the F11 report accounts for
# each one — carried, deliberately dropped, or not applicable.
#
# What genuinely could not come across, and why, stated here rather than only in the report:
#
# - `_air_readout`. The old screen had a prose Label composing its own sentence about the density.
#   This room has a Conditions PANEL with an "Air density" row, which is the same promise ("the
#   readout quotes the derived density, not a second copy of it") read off a different control. The
#   three checks that read that Label are re-pointed at the panel row, and they still compare
#   against `AirDensity` rather than against the panel.
# - `_start_marker`. The old screen drew a post-and-arrow at the start line; this room draws the
#   AIRCRAFT'S OWN FOOTPRINT there instead (§11 Q1, F10), at `start_position` — the same derived
#   fact, the same place. `tests/test_ground_authority.gd`'s F4 section, which used the marker as
#   its probe that the render ran to the end, is re-pointed at the silhouette for that reason.

## The scratch files this room writes when it is driven directly, named so the teardown can delete
## them. `SiteLibrary` and `ConditionsLibrary` own the pairing rule; these are the same answer.
const ROOM_LIBRARY_PATH := "user://test_field_room_courses.json"
const ROOM_SITES_PATH := "user://test_field_room_courses_sites.json"
const ROOM_CONDITIONS_PATH := "user://test_field_room_courses_conditions.json"

## A ground with real relief, so "lands on the terrain" and "keeps its clearance" are different
## numbers from "keeps its y". A flat site at zero makes the two readings identical, which is the
## version of check 1 that cannot fail.
const SLOPE_RISE_M := 12.0
const SLOPE_SITE_M := 200.0


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A room over its OWN files, the shape `TestFieldEditor._editor()` had. Driven directly rather
## than through the shell, because most of what is asserted below is about the room and a shell in
## the way is one more thing that could be producing the answer.
static func _room() -> FieldSystem:
	_forget(ROOM_LIBRARY_PATH)
	_forget(ROOM_SITES_PATH)
	_forget(ROOM_CONDITIONS_PATH)
	return FieldSystem.new(
		SiteLibrary.load_from(ROOM_SITES_PATH),
		CourseLibrary.load_from(ROOM_LIBRARY_PATH),
		ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH),
		ReferenceBuild.build(),
		ROOM_LIBRARY_PATH)


## The same room, standing on a SLOPE. `Terrain.shaped` builds the description; `height_at` and
## `TerrainMesh` both read it, which is the whole of F5's one-description rule.
static func _sloped_room() -> FieldSystem:
	var room := _room()
	room.site().terrain = Terrain.shaped(Terrain.SLOPE, SLOPE_SITE_M, SLOPE_SITE_M,
		{"rise_m": SLOPE_RISE_M, "direction_deg": 0.0})
	room.refresh()
	return room


# ---------------------------------------------------------------------------
# 11. Placing, moving, re-ordering, adding and removing (ported)
# ---------------------------------------------------------------------------

static func _editing_gates() -> Array:
	var results: Array = []
	var room := _room()

	var before := room.course().gates.size()
	room.select_gate(2)
	room.add_gate()
	results.append(TestResult.new(
		"a gate can be added, and it lands between the two it was added between",
		room.course().gates.size() == before + 1 and room.selected_gate == 3,
		"%d gates, editing gate %d" % [room.course().gates.size(), room.selected_gate + 1]))

	var added: Dictionary = room.course().gates[3]
	var neighbours := float(room.course().gates[2]["position"].distance_to(
		room.course().gates[4]["position"]))
	results.append(TestResult.new(
		"a new gate appears on the route rather than at the origin",
		added["position"].distance_to(room.course().gates[2]["position"]) < neighbours
			and added["position"].y > 0.0,
		"new gate at %s, %.1f m from the one before it" % [
			added["position"], added["position"].distance_to(room.course().gates[2]["position"])]))

	room.course().reset()
	var passes := 0
	for i in room.course().gates.size():
		var gate: Dictionary = room.course().gates[i]
		if room.course().advance(gate["position"] - gate["normal"] * 0.5,
				gate["position"] + gate["normal"] * 0.5):
			passes += 1
	results.append(TestResult.new(
		"a nine-gate course is flown and lapped as nine gates",
		passes == 9 and room.course().just_completed_lap(),
		"%d of %d gates scored" % [passes, room.course().gates.size()]))

	room.select_gate(0)
	room.set_gate_ground_position(Vector3(40.0, 0.0, -12.0))
	room.set_gate_height_m(6.5)
	room.set_gate_heading_deg(90.0)
	room.set_gate_radius_m(0.9)
	var moved: Dictionary = room.course().gates[0]
	results.append(TestResult.new(
		"a gate is placed by ground position, height, heading and ring size",
		moved["position"].distance_to(Vector3(40.0, 6.5, -12.0)) < 1.0e-6
			and absf(float(moved["radius"]) - 0.9) < 1.0e-6
			and moved["normal"].distance_to(Vector3(1.0, 0.0, 0.0)) < 1.0e-6,
		"gate 1 at %s facing %s, %.2f m ring" % [
			moved["position"], moved["normal"], float(moved["radius"])]))

	var second_before: Vector3 = room.course().gates[1]["position"]
	room.select_gate(1)
	var reordered := room.reorder_gate(1)
	results.append(TestResult.new(
		"a gate can be moved later in the running order, and the selection follows it",
		reordered and room.selected_gate == 2
			and room.course().gates[2]["position"].distance_to(second_before) < 1.0e-9,
		"the gate that was 2nd is now %d" % [room.selected_gate + 1]))

	var fresh := FieldSystem.new(
		SiteLibrary.load_from(ROOM_SITES_PATH), CourseLibrary.load_from(ROOM_LIBRARY_PATH),
		ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH), ReferenceBuild.build(),
		ROOM_LIBRARY_PATH)
	results.append(TestResult.new(
		"the first gate cannot be moved earlier than first",
		not fresh.reorder_gate(-1),
		"reordering gate 1 backwards refused"))
	fresh.free()

	var removals := 0
	while room.remove_gate():
		removals += 1
	results.append(TestResult.new(
		"gates can be removed, but never the last one — a course with no gates is not a course",
		room.course().gates.size() == 1 and removals == 8,
		"%d removed, %d gate left" % [removals, room.course().gates.size()]))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 12. One description of the world (ported)
# ---------------------------------------------------------------------------

static func _the_renderer_follows() -> Array:
	var results: Array = []
	var room := _room()

	var renderer := room.renderer
	results.append(TestResult.new(
		"the room draws the course through CourseRenderer, not through gates of its own",
		renderer != null and renderer.course == room.course()
			and renderer.get_child_count() == room.course().gates.size(),
		"%d rings drawn for %d gates" % [
			0 if renderer == null else renderer.get_child_count(),
			room.course().gates.size()]))

	room.select_gate(3)
	room.add_gate()
	results.append(TestResult.new(
		"adding a gate adds a ring — the picture cannot fall behind the model",
		renderer.get_child_count() == room.course().gates.size(),
		"%d rings for %d gates" % [renderer.get_child_count(), room.course().gates.size()]))

	results.append(TestResult.new(
		"the gate being edited is the lit one",
		renderer.highlight_index == room.selected_gate,
		"editing gate %d, lit gate %d" % [room.selected_gate + 1, renderer.highlight_index + 1]))

	room.select_gate(0)
	room.set_gate_height_m(0.5)
	var says := room.warnings()
	var complained := false
	for entry in says:
		if entry.id == CourseWarnings.GATE_BELOW_GROUND:
			complained = true
	results.append(TestResult.new(
		"burying a ring in the ground is reported the moment it happens",
		complained,
		"a 1.5 m ring centred 0.5 m up says: %s" % ", ".join(BuildWarning.messages(says))))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 13. More than one course (ported)
# ---------------------------------------------------------------------------

static func _courses() -> Array:
	var results: Array = []
	var room := _room()

	room.new_course("Whoop box")
	results.append(TestResult.new(
		"a new course is created and becomes the one being edited",
		room.course().course_name == "Whoop box"
			and room.courses.selected_id == room.course().course_id,
		"editing \"%s\"" % room.course().course_name))

	room.rename_course("Back garden")
	results.append(TestResult.new(
		"renaming keeps the id, so nothing that pointed at the course is orphaned",
		room.course().course_name == "Back garden"
			and room.course().course_id == "whoop_box",
		"\"%s\" is still id \"%s\"" % [room.course().course_name, room.course().course_id]))

	results.append(TestResult.new(
		"the default circuit is still there to go back to",
		room.open_course(GateCourse.DEFAULT_ID)
			and room.course().course_id == GateCourse.DEFAULT_ID,
		"switched to \"%s\"" % room.course().course_id))

	room.open_course("whoop_box")
	room.delete_course()
	results.append(TestResult.new(
		"deleting a course leaves you editing one that still exists",
		not room.courses.has("whoop_box") and room.course() != null,
		"now editing \"%s\"" % room.course().course_id))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 14. Lab writes; Sim reads (ported) — and check 3, the drag written through
# ---------------------------------------------------------------------------

static func _it_writes_what_sim_flies() -> Array:
	var results: Array = []
	var room := _room()

	room.new_course("Sprint")
	room.select_gate(0)
	room.set_gate_ground_position(Vector3(-60.0, 0.0, 25.0))
	room.set_gate_height_m(5.0)

	var from_disk := CourseLibrary.load_from(ROOM_LIBRARY_PATH)
	var reloaded := from_disk.course("sprint")
	results.append(TestResult.new(
		"every edit is on disk immediately — there is no exit to save on",
		reloaded != null
			and reloaded.gates[0]["position"].distance_to(Vector3(-60.0, 5.0, 25.0)) < 1.0e-6,
		"gate 1 on disk at %s" % [
			"nowhere" if reloaded == null else str(reloaded.gates[0]["position"])]))

	results.append(TestResult.new(
		"the course Sim would open is the one that was just edited",
		from_disk.selected_id == "sprint"
			and from_disk.selected().fingerprint() == room.course().fingerprint(),
		"Sim would open \"%s\"" % from_disk.selected_id))

	var before_edit := room.course().fingerprint()
	room.set_gate_height_m(9.0)
	results.append(TestResult.new(
		"moving a gate in the room retires the record set on the old layout",
		room.course().fingerprint() != before_edit,
		"fingerprint went from %s to %s" % [before_edit, room.course().fingerprint()]))

	# CHECK 3 — A DRAG, not a slider, written through and surviving a reopen.
	#
	# DRIVEN THROUGH THE VIEWPORT'S OWN INPUT HANDLER rather than by calling the setter, because
	# the mutation this check names ("the drag updates the view only") lives between the handler
	# and the library. A check that called `set_gate_ground_position` would still pass with the
	# handler wired to nothing at all.
	#
	# The pixel is not guessed: the gate's own centre is projected to the screen, moved, and the
	# point that lands there is read back — so the arithmetic below is the room's own picking maths
	# used forwards, and the assertion is about what the LIBRARY holds afterwards.
	room.select_gate(0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = room._unproject(room.camera_world_transform(),
		room.course().gates[0]["position"])
	room._on_viewport_input(press)
	var grabbed := room._dragging_gate
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(60.0, -25.0)
	room._on_viewport_input(motion)
	var dropped: Vector3 = room.course().gates[0]["position"]
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	room._on_viewport_input(release)

	results.append(TestResult.new(
		"a ring under the pointer is grabbed by a press on the viewport, not by calling a setter",
		grabbed,
		"press at %v over gate 1 at %v -> dragging %s" % [
			press.position, room.course().gates[0]["position"], grabbed]))
	results.append(TestResult.new(
		"and dragging it actually moved it on the ground",
		dropped.distance_to(Vector3(-60.0, dropped.y, 25.0)) > 1.0,
		"gate 1 went from (-60, 25) to (%.2f, %.2f)" % [dropped.x, dropped.z]))

	# THE SECOND OPINION IS THE FILE. Re-read from disk into a library that has never met this
	# room, so "it wrote through" cannot be satisfied by the room's own in-memory copy.
	var after_drag := CourseLibrary.load_from(ROOM_LIBRARY_PATH).course("sprint")
	results.append(TestResult.new(
		"and the drag is on disk and survives a reopen — the view is not the only thing that moved",
		after_drag != null
			and after_drag.gates[0]["position"].distance_to(dropped) < 1.0e-5,
		"on disk at %s, in the room at %s" % [
			"nowhere" if after_drag == null else str(after_drag.gates[0]["position"]), dropped]))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 15. CHECK 1 — a dragged gate lands ON THE TERRAIN
# ---------------------------------------------------------------------------

## The one check a flat site could not make. On a slope, `height_at` at the drop point is a
## different number from `height_at` where the gate came from, so "kept its y" and "kept its
## clearance" are two answers rather than one — and a drop at y = 0 is a third.
static func _a_drag_lands_on_the_terrain() -> Array:
	var results: Array = []
	var room := _sloped_room()

	# GUARDED ON THE GROUND ACTUALLY HAVING RELIEF before anything is compared. On a flat site
	# every assertion below is true of every implementation, including the mutation's.
	var from_ground := room.ground_height_at(-70.0, 0.0)
	var to_ground := room.ground_height_at(70.0, 0.0)
	results.append(TestResult.new(
		"the site under this check really is sloped — the two ends are different heights",
		absf(to_ground - from_ground) > 1.0,
		"ground is %.3f m at x=-70 and %.3f m at x=+70" % [from_ground, to_ground]))
	if absf(to_ground - from_ground) <= 1.0:
		room.free()
		return results

	room.select_gate(0)
	room.set_gate_ground_position(Vector3(-70.0, 0.0, 0.0))
	room.set_gate_height_m(4.0)
	var lifted: Vector3 = room.course().gates[0]["position"]

	room.set_gate_ground_position(Vector3(70.0, 0.0, 0.0))
	var landed: Vector3 = room.course().gates[0]["position"]

	# THE GOLDEN COMES FROM `Terrain`, not from the room. `height_at` is the model the room reads;
	# taking the expected y off `room.ground_height_at` would be the room agreeing with itself.
	var wanted := room.site().terrain.height_at(70.0, 0.0) + 4.0
	results.append(TestResult.new(
		"a gate dragged across the field lands ON the ground: height_at at the drop plus its height",
		absf(landed.y - wanted) < 1.0e-4,
		"dropped at y=%.4f, Terrain says %.4f + 4.0 m = %.4f" % [
			landed.y, room.site().terrain.height_at(70.0, 0.0), wanted]))
	results.append(TestResult.new(
		"and that is a different y from the one it had — a drop at y=0, or a kept y, would not be",
		absf(landed.y - lifted.y) > 1.0 and landed.y > 1.0,
		"y went from %.4f to %.4f across a slope %.3f m tall" % [
			lifted.y, landed.y, absf(to_ground - from_ground)]))
	results.append(TestResult.new(
		"and the clearance it was authored at is what survived the move",
		absf(room.gate_height_above_ground_m(0) - 4.0) < 1.0e-4,
		"%.4f m above the ground under it" % room.gate_height_above_ground_m(0)))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 16. CHECK 2 — three sliders, three properties
# ---------------------------------------------------------------------------

## Each control moves its own property AND NOTHING ELSE. Driven through the live `HSlider`'s
## `value_changed` signal, not through the setter, because the mutation this check names ("the
## height slider also writes radius") could live in either — and a check that called the setter
## would pass against a slider wired to the wrong one.
static func _the_three_sliders() -> Array:
	var results: Array = []
	var room := _room()
	var panel := room.panel("Course") as FieldSystem.CoursePanel

	results.append(TestResult.new(
		"the Course panel carries the three controls a drag cannot express",
		panel != null and panel.height_slider != null and panel.heading_slider != null
			and panel.radius_slider != null,
		"panel %s · height %s · heading %s · radius %s" % [
			panel != null, panel != null and panel.height_slider != null,
			panel != null and panel.heading_slider != null,
			panel != null and panel.radius_slider != null]))
	if panel == null or panel.height_slider == null:
		room.free()
		return results

	room.select_gate(1)
	# One case per control rather than a loop, so a failure names the slider that went wrong.
	for spec in [["Height", 7.25], ["Heading", 42.0], ["Radius", 1.35]]:
		var which := str(spec[0])
		var to := float(spec[1])
		var before := _gate_facts(room, 1)
		var slider: HSlider = panel.height_slider
		if which == "Heading":
			slider = panel.heading_slider
		elif which == "Radius":
			slider = panel.radius_slider
		slider.value_changed.emit(to)
		var after := _gate_facts(room, 1)

		var moved: Array[String] = []
		for key in after:
			if absf(float(after[key]) - float(before[key])) > 1.0e-4:
				moved.append(str(key))
		results.append(TestResult.new(
			"the %s slider moves the gate's %s and nothing else" % [
				which.to_lower(), which.to_lower()],
			moved == [which.to_lower()] and absf(float(after[which.to_lower()]) - to) < 0.05,
			"%s -> %.3f; what moved: %s (was %s, now %s)" % [
				which, to, moved, before, after]))

	room.free()
	return results


## The three facts the three sliders are about, as one dictionary, so "what moved" is a comparison
## of three numbers rather than three separate assertions that could each be about the wrong one.
static func _gate_facts(room: FieldSystem, index: int) -> Dictionary:
	var gate: Dictionary = room.course().gates[index]
	return {
		"height": room.gate_height_above_ground_m(index),
		"heading": rad_to_deg(GateCourse.gate_heading_rad(gate)),
		"radius": float(gate["radius"]),
	}


# ---------------------------------------------------------------------------
# 17. CHECK 4 — off the edge of the field is a WARNING, not a clamp
# ---------------------------------------------------------------------------

static func _outside_the_site_extent() -> Array:
	var results: Array = []
	var room := _room()
	var half := room.site().terrain.half_extent()

	# Guarded on the field having a stated size at all: a zero-extent site puts everything outside
	# it and the warning would arrive for the wrong reason.
	results.append(TestResult.new(
		"the field under this check has a stated extent to be outside of",
		half.x > 1.0 and half.y > 1.0,
		"half extent %v" % half))
	if half.x <= 1.0:
		room.free()
		return results

	var before_ids: Array[StringName] = []
	for entry in room.warnings():
		before_ids.append(entry.id)
	results.append(TestResult.new(
		"and the course starts INSIDE it — nothing is complaining before the drag",
		not before_ids.has(CourseWarnings.OUTSIDE_SITE_EXTENT),
		"before the drag: %s" % [before_ids]))

	var beyond := Vector3(half.x * 3.0, 0.0, 0.0)
	room.select_gate(0)
	room.set_gate_ground_position(beyond)
	var at: Vector3 = room.course().gates[0]["position"]

	results.append(TestResult.new(
		"a gate dragged past the edge of the field STAYS where it was put — it is not clamped back",
		absf(at.x - beyond.x) < 1.0e-4,
		"asked for x=%.1f, the gate is at x=%.1f (the field's half width is %.1f)" % [
			beyond.x, at.x, half.x]))

	var ids: Array[StringName] = []
	for entry in room.warnings():
		ids.append(entry.id)
	results.append(TestResult.new(
		"and the course says so, by id, in the vocabulary that exists — OUTSIDE_SITE_EXTENT",
		ids.has(CourseWarnings.OUTSIDE_SITE_EXTENT),
		"after the drag: %s" % [ids]))

	# AND THE PANEL SHOWS IT, because a warning nobody is told about is a warning that did not
	# happen — the refresh is what carries it from `CourseWarnings` to the builder's eye.
	var panel := room.panel("Course") as FieldSystem.CoursePanel
	var shown := false
	for entry in panel.warnings.shown:
		if entry.id == CourseWarnings.OUTSIDE_SITE_EXTENT:
			shown = true
	results.append(TestResult.new(
		"and it is on the Course panel's own warning list, not only in the function's return",
		shown,
		"the panel is showing %d warning(s)" % panel.warnings.shown.size()))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 18. CHECK 6 — the warnings are re-read after EVERY edit
# ---------------------------------------------------------------------------

## The terrain-aware one, deliberately: a below-ground check against y = 0 would pass on a flat
## site under both the right implementation and "computed once at open". A gate 3 m up on ground
## that is 9 m high is buried, and only a re-read against the TERRAIN says so.
static func _warnings_refresh_after_every_edit() -> Array:
	var results: Array = []
	var room := _sloped_room()
	var panel := room.panel("Course") as FieldSystem.CoursePanel

	# EVERY GATE RE-SEATED ON THE HILL FIRST. The default circuit was laid out over flat ground, so
	# dropping it on a 12 m slope buries most of it — and a section that starts with seven
	# below-ground warnings cannot tell an eighth arriving from a list computed once. The course
	# starts clear, and exactly one edit is made.
	for i in room.course().gates.size():
		room.select_gate(i)
		var at: Vector3 = room.course().gates[i]["position"]
		room.set_gate_ground_position(Vector3(at.x, 0.0, at.z))
		room.set_gate_height_m(6.0)

	room.select_gate(0)
	room.set_gate_ground_position(Vector3(-70.0, 0.0, 0.0))
	room.set_gate_height_m(6.0)
	var clear := _panel_warning_ids(panel)
	results.append(TestResult.new(
		"a ring hung 6 m above the low end of the slope is not reported as buried",
		not clear.has(CourseWarnings.GATE_BELOW_GROUND),
		"the panel says %s" % [clear]))

	# THE EDIT: lower it into the hillside. The gate does not move in x or z, so nothing but the
	# height changed and nothing but a re-read can notice.
	room.set_gate_height_m(MIN_CLEARANCE_M)
	var buried := _panel_warning_ids(panel)
	results.append(TestResult.new(
		"and lowering it into the hillside is reported on the panel WITHOUT reopening the room",
		buried.has(CourseWarnings.GATE_BELOW_GROUND),
		"the panel says %s" % [buried]))

	# AND IT GOES AWAY AGAIN. A list that only ever grows is also a list computed once — this is
	# the half that a "warnings appended, never cleared" implementation fails.
	room.set_gate_height_m(6.0)
	var clear_again := _panel_warning_ids(panel)
	results.append(TestResult.new(
		"and raising it again takes the warning off the panel — the list is re-read, not appended to",
		not clear_again.has(CourseWarnings.GATE_BELOW_GROUND),
		"the panel says %s" % [clear_again]))

	room.free()
	return results


## Low enough that a 1.5 m ring's bottom edge is under the ground it hangs over, and high enough to
## be a legal value of the height control. Not read from the implementation: `GATE_INNER_RADIUS_M`
## is 1.5 m, so anything below that buries the hoop.
const MIN_CLEARANCE_M := 0.4


static func _panel_warning_ids(panel: FieldSystem.CoursePanel) -> Array[StringName]:
	var out: Array[StringName] = []
	if panel == null or panel.warnings == null:
		return out
	for entry in panel.warnings.shown:
		out.append(entry.id)
	return out


# ---------------------------------------------------------------------------
# 19. CHECK 5 — laying out gates costs NO pack charge (ported, §2.4)
# ---------------------------------------------------------------------------

static func _it_costs_nothing() -> Array:
	var results: Array = []

	# Through the SHELL, which is the thing that would have to save a changed pack on the way out.
	# A room driven on its own could not charge the pack even if it wanted to.
	var shell := GlassShell.new()
	var pack_id: String = shell.lab.selection()["battery"]
	var before := shell.rooms.pack_charge.used_mah(pack_id)

	shell.select_system_by_name("Field")
	var room := shell.field_room()
	room.select_gate(1)
	room.set_gate_height_m(7.0)
	room.add_gate()
	room.set_gate_radius_m(1.2)
	shell.select_system_by_name("Power")

	results.append(TestResult.new(
		"laying out gates costs no charge — no motor turned",
		absf(shell.rooms.pack_charge.used_mah(pack_id) - before) < 1.0e-9
			and not shell.rooms.pack_charge.has_unsaved_changes(),
		"pack drew %.4f mAh before, %.4f after" % [
			before, shell.rooms.pack_charge.used_mah(pack_id)]))

	# The old screen's second check here was "the field editor is a room, and it is gone when you
	# leave it". RE-POINTED RATHER THAN DELETED: the field is a SYSTEM now, so what has to be true
	# is the opposite — it is built once and persists, and what goes away is its visibility. A
	# check asserting the room was freed would be asserting F10's design had been undone.
	results.append(TestResult.new(
		"the field is a system rather than a room: it survives leaving, and goes off screen instead",
		shell.field_room() == room and not room.visible,
		"the room is %s and visible %s" % [
			"the same instance" if shell.field_room() == room else "A DIFFERENT ONE", room.visible]))

	# AND THE HALF OF THE OLD ASSERTION THE RE-POINT ABOVE LEFT UNMIRRORED. "Gone when you leave
	# it" carried, implicitly, that nothing of the field was still being DRAWN while you worked in
	# Lab — a freed screen renders nothing. A system that survives leaving can, so the property has
	# to be asserted rather than inherited, and it is asserted here in the direction the
	# implementation actually takes: the field's `SubViewport` is `UPDATE_WHEN_VISIBLE`, and once
	# the room is hidden nothing in it is visible in the tree, so the 3D world stops being redrawn.
	#
	# BOTH CONJUNCTS ARE THE RULE AND NEITHER IS IT ALONE. `UPDATE_ALWAYS` on a hidden viewport
	# renders a field nobody is looking at every frame, behind whatever room is up — and the
	# visibility half alone would pass against exactly that, because visibility is not what
	# `UPDATE_ALWAYS` consults.
	#
	# THE VISIBILITY IS READ OFF THE CONTAINER, NOT OFF THE `SubViewport`. A `SubViewport` is not a
	# `CanvasItem` and has no `is_visible_in_tree()` — a first draft of this line called it anyway,
	# and the handler aborted before it could append anything, which the per-section "produced
	# results" guard reported as `0 checks` rather than as a pass. The container is also the
	# correct object to ask: `UPDATE_WHEN_VISIBLE` is about whether the `SubViewportContainer`
	# drawing this viewport is on screen.
	var world := room.world()
	var shown: bool = room.viewport_container != null and room.viewport_container.is_visible_in_tree()
	results.append(TestResult.new(
		"and the field it is not showing is not still being drawn behind the room that is",
		world != null
			and world.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE
			and not shown,
		"update mode %s (WHEN_VISIBLE is %d), the view it draws into is on screen: %s" % [
			-1 if world == null else world.render_target_update_mode,
			SubViewport.UPDATE_WHEN_VISIBLE, shown]))

	shell.free()
	return results


# ---------------------------------------------------------------------------
# 20. Where the course IS — elevation, temperature, the air they imply (ported)
# ---------------------------------------------------------------------------

static func _the_field_itself() -> Array:
	var results: Array = []
	var room := _room()

	results.append(TestResult.new(
		"a fresh course opens at standard sea-level air",
		room.air().is_standard(),
		"%.4f kg/m3 at %.0f m, %.0f C" % [room.air().kgm3(),
			room.air().elevation_m, room.air().temperature_c]))

	room.set_field_elevation_m(920.0)
	room.set_field_temperature_c(35.0)

	var expected := AirDensity.new(920.0, 35.0).kgm3()
	results.append(TestResult.new(
		"typing an elevation and a temperature derives the density the physics uses",
		absf(room.air().kgm3() - expected) < 1.0e-12,
		"%.4f kg/m3, %.1f%% below standard" % [
			room.air().kgm3(), room.air().fraction_below_standard() * 100.0]))

	# RE-POINTED FROM `_air_readout` TO THE CONDITIONS PANEL'S OWN ROW. Same promise, different
	# control — and the wanted value still comes from `AirDensity`, never from the panel.
	var rows := _rows_of(room.panel("Conditions"))
	results.append(TestResult.new(
		"the readout quotes the derived density, not a second copy of it",
		rows.has("Air density") and str(rows["Air density"]).contains("%.4f" % expected),
		"the density row reads \"%s\"" % [rows.get("Air density", "(no such row)")]))

	var from_disk := CourseLibrary.load_from(ROOM_LIBRARY_PATH)
	var site_on_disk := SiteLibrary.load_from(ROOM_SITES_PATH).site(from_disk.selected().site_id)
	var weather_on_disk := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected()
	var disk_air := AirDensity.compose(site_on_disk, weather_on_disk)
	results.append(TestResult.new(
		"the field is on disk immediately",
		site_on_disk != null and weather_on_disk != null
			and absf(disk_air.kgm3() - expected) < 1.0e-12,
		"nowhere on disk" if site_on_disk == null else "%.4f m, %.1f C on disk" % [
			disk_air.elevation_m, disk_air.temperature_c]))
	results.append(TestResult.new(
		"and the temperature is on the conditions rather than parked on the site",
		site_on_disk != null and site_on_disk.parked_temperature_c == null
			and weather_on_disk != null and absf(weather_on_disk.temperature_c - 35.0) < 1.0e-9,
		"site slot %s, weather \"%s\" at %.1f C" % [
			"nowhere" if site_on_disk == null else str(site_on_disk.parked_temperature_c),
			"none" if weather_on_disk == null else weather_on_disk.conditions_name,
			-999.0 if weather_on_disk == null else weather_on_disk.temperature_c]))

	# AN EDIT THAT IS NOT ABOUT THE WEATHER DOES NOT WRITE THE WEATHER FILE. Bytes AND stamp,
	# re-indented first so a round-trip that produced identical bytes is still visible as a write.
	var weather_document := JsonStore.read_document(ROOM_CONDITIONS_PATH)
	var weather_handle := FileAccess.open(ROOM_CONDITIONS_PATH, FileAccess.WRITE)
	weather_handle.store_string(JSON.stringify(weather_document, "\t"))
	weather_handle.close()
	var weather_bytes := FileAccess.get_file_as_string(ROOM_CONDITIONS_PATH)
	var weather_stamp := FileAccess.get_modified_time(ROOM_CONDITIONS_PATH)
	room.select_gate(1)
	room.set_gate_height_m(2.5)
	room.rename_course("Bando, renamed")
	room.set_field_elevation_m(920.0)
	results.append(TestResult.new(
		"moving a gate, renaming a course and nudging the elevation do not write conditions.json",
		FileAccess.get_file_as_string(ROOM_CONDITIONS_PATH) == weather_bytes
			and FileAccess.get_modified_time(ROOM_CONDITIONS_PATH) == weather_stamp,
		"%s, stamp %s" % [
			"untouched" if FileAccess.get_file_as_string(ROOM_CONDITIONS_PATH) == weather_bytes
				else "REWRITTEN",
			"unmoved" if FileAccess.get_modified_time(ROOM_CONDITIONS_PATH) == weather_stamp
				else "MOVED"]))

	room.new_course("Sea level bando")
	var sea_level_hot := AirDensity.new(0.0, 35.0).kgm3()
	results.append(TestResult.new(
		"a new course has its own elevation and does not inherit the last one's",
		absf(room.air().elevation_m) < 1.0e-9
			and absf(room.air().kgm3() - sea_level_hot) < 1.0e-12,
		"%.4f kg/m3 at %.0f m, %.0f C" % [room.air().kgm3(),
			room.air().elevation_m, room.air().temperature_c]))
	results.append(TestResult.new(
		"and the temperature stayed, because the weather is not a property of the route",
		absf(room.air().temperature_c - 35.0) < 1.0e-9
			and absf(sea_level_hot - AirDensity.standard_kgm3()) > 0.05,
		"%.1f C, %.4f kg/m3 against %.4f at 15 C" % [
			room.air().temperature_c, sea_level_hot, AirDensity.standard_kgm3()]))
	var moved_rows := _rows_of(room.panel("Conditions"))
	results.append(TestResult.new(
		"and the readout followed the course rather than staying on the old numbers",
		moved_rows.has("Air density")
			and str(moved_rows["Air density"]).contains("%.4f" % sea_level_hot),
		"the density row reads \"%s\"" % [moved_rows.get("Air density", "(no such row)")]))

	# THE SECOND COURSE IS GIVEN A DIFFERENT FIELD BEFORE SWITCHING BACK. Without this the section
	# passes against an implementation holding ONE app-wide air, because a freshly created course
	# reads as standard under both designs.
	room.set_field_elevation_m(1610.0)
	room.set_field_temperature_c(30.0)
	var denver := AirDensity.new(1610.0, 30.0).kgm3()
	var first_again := AirDensity.new(920.0, 30.0).kgm3()

	room.open_course(GateCourse.DEFAULT_ID)
	results.append(TestResult.new(
		"switching back brings the first course's field back with it",
		absf(room.air().kgm3() - first_again) < 1.0e-12,
		"%.0f m, %.0f C" % [room.air().elevation_m, room.air().temperature_c]))

	room.open_course("sea_level_bando")
	results.append(TestResult.new(
		"and the second course kept its own, so the two fields are not one shared setting",
		absf(room.air().kgm3() - denver) < 1.0e-12
			and absf(denver - first_again) > 0.01,
		"course A %.4f kg/m3, course B %.4f kg/m3" % [first_again, room.air().kgm3()]))

	room.set_field_elevation_m(1.0e9)
	results.append(TestResult.new(
		"an absurd elevation is clamped rather than turning the whole readout into NaN",
		not is_nan(room.air().kgm3()) and room.air().kgm3() > 0.0,
		"%.4f kg/m3 at %.0f m" % [room.air().kgm3(), room.air().elevation_m]))

	room.free()

	results.append_array(_the_garage_follows_the_field())
	return results


## The half a builder actually notices: change the field, look back at the garage, and the derived
## stats are for the place they are going to fly.
##
## THROUGH THE SHELL, because the wiring IS the feature. The old screen's version went through
## `AppShell`; this one goes through `GlassShell`, which is what `project.godot` actually boots.
static func _the_garage_follows_the_field() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	var before := shell.lab.current_build().thrust_to_weight()
	shell.select_system_by_name("Field")
	shell.field_room().set_field_elevation_m(3500.0)
	shell.field_room().set_field_temperature_c(30.0)
	var after := shell.lab.current_build().thrust_to_weight()

	var expected := Build.from_ids(shell.lab.catalog,
		shell.lab.selection()["frame"], shell.lab.selection()["motor"],
		shell.lab.selection()["propeller"], shell.lab.selection()["battery"],
		shell.lab.selection()["esc"], shell.lab.selection()["flight_controller"],
		{}, AirDensity.new(3500.0, 30.0)).thrust_to_weight()

	results.append(TestResult.new(
		"editing the field moves the garage's thrust-to-weight to the field's own figure",
		absf(after - expected) < 0.01 and absf(after - before) > 0.5,
		"%.2f:1 at sea level, %.2f:1 at 3500 m (expected %.2f:1)" % [before, after, expected]))

	# THE RIGHT-HAND SIDE IS READ OFF DISK, not asked of `rooms.air_of_selected_course()` — asking
	# that function is asking the very call that SET `lab.air`, so the two sides would agree by
	# construction. Going to the file and composing the air independently is the second opinion.
	var on_disk := SiteLibrary.load_from(SiteLibrary.SAVE_PATH)
	var flown_site := on_disk.site(
		CourseLibrary.load_from(CourseLibrary.SAVE_PATH).selected().site_id)
	var weather_on_disk := ConditionsLibrary.load_from(ConditionsLibrary.SAVE_PATH).selected()
	var independent := (AirDensity.compose(flown_site, weather_on_disk).kgm3()
		if flown_site != null else -1.0)
	results.append(TestResult.new(
		"and the build handed to Sim carries the same air",
		flown_site != null
			and absf(shell.lab.current_build().air.kgm3() - independent) < 1.0e-12,
		"garage %.4f kg/m3, the site on disk %.4f kg/m3" % [
			shell.lab.current_build().air.kgm3(), independent]))

	shell.free()
	return results


# ---------------------------------------------------------------------------
# 21. CHECK 7 — the old screen is gone from `src/`
# ---------------------------------------------------------------------------

## A SOURCE SCAN, because that is the only thing that can see a reference nothing calls. The old
## screen was reachable from `RoomHost.show_field_editor()` while the menu arm that called it was
## already dead — a door on the dock opening the room it replaced, which no runtime check finds
## because nothing runs it.
static func _the_old_editor_is_gone() -> Array:
	var results: Array = []
	var hits: Array[String] = []
	var scanned := _scan_for("res://src", "FieldEditorScreen", hits)

	# GUARDED ON HAVING READ SOMETHING. A scan that walked no files finds no references, which is
	# the version of this check that passes against a deleted `src/` directory.
	results.append(TestResult.new(
		"the source scan actually read the app's source — it is not reporting an empty directory",
		scanned > 50,
		"%d .gd files scanned under res://src" % scanned))
	results.append(TestResult.new(
		"nothing under src/ names FieldEditorScreen any more — the old room is retired",
		hits.is_empty(),
		"still referenced in: %s" % [hits] if not hits.is_empty() else "no references"))

	# AND THE FILE ITSELF IS GONE, which "nothing references it" is also true of when the file is
	# sitting there unreferenced — a dead room a later slice would find and wire back up.
	results.append(TestResult.new(
		"and the file is gone rather than orphaned",
		not FileAccess.file_exists("res://src/lab/field_editor_screen.gd"),
		"res://src/lab/field_editor_screen.gd %s" % [
			"still exists" if FileAccess.file_exists("res://src/lab/field_editor_screen.gd")
				else "deleted"]))
	return results


static func _scan_for(dir_path: String, needle: String, hits: Array[String]) -> int:
	var scanned := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			scanned += _scan_for(full, needle, hits)
		elif entry.ends_with(".gd"):
			scanned += 1
			if FileAccess.get_file_as_string(full).contains(needle):
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return scanned


# ---------------------------------------------------------------------------
# 22. The preview is drawn THROUGH `TerrainMesh` — one description, not two
# ---------------------------------------------------------------------------

## THE MOMENT A BUILDER CAN TYPE A DIMENSION, THIS ROOM IS WHERE A DIVERGENCE WOULD SHOW — while
## they are sculpting the very thing it would lie about. F5's rule is that the mesh and `height_at`
## come from ONE description; this is the check that the authoring screen honours it.
##
## Asserted against `TerrainMesh.vertices()` recomputed from the SITE'S OWN terrain, and then
## against `height_at` at a vertex — so a preview drawn from a `PlaneMesh`, from a second grid, or
## from a stale copy of the description all fail, and only "the same builder over the same terrain"
## passes.
##
## **WHAT THE LAST TWO ASSERTIONS DEFEND IS PROVENANCE, NOT AGREEMENT BETWEEN TWO COMPUTATIONS.**
## An earlier version of this comment claimed the `height_at` probe supplied independence from
## `TerrainMesh`. IT DOES NOT, and the claim was wrong rather than imprecise: `TerrainMesh
## .vertices()` calls `Terrain.height_at(x, z)` for every vertex it emits (`terrain_mesh.gd:68`,
## documented in its own header), so the mesh's y values ARE `height_at`'s answers and no
## disagreement between those two functions is detectable here. What is detectable, and what this
## section is for, is the mesh having been built from a DIFFERENT terrain description than the one
## this site carries — a stale copy kept across an edit, a second grid, a preview of a field of the
## same size and a different shape. Proven rather than argued: building the preview from
## `Terrain.flat(width, length)` instead of the site's own terrain reddens both, 12 m of vertical
## error and 1612 of 1621 probes off the surface. The arithmetic INSIDE `TerrainMesh` is somebody
## else's job and `TestTerrainMesh` has it, against the published shape formulae.
static func _the_preview_is_the_terrain() -> Array:
	var results: Array = []
	var room := _sloped_room()

	var mesh := room._terrain.mesh as ArrayMesh
	results.append(TestResult.new(
		"the ground in the room's world is a real mesh with surfaces on it",
		mesh != null and mesh.get_surface_count() > 0,
		"mesh %s, %d surface(s)" % [mesh != null, 0 if mesh == null else mesh.get_surface_count()]))
	if mesh == null or mesh.get_surface_count() == 0:
		room.free()
		return results

	var drawn: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rebuilt := TerrainMesh.build_mesh(room.site().terrain, room.site().obstacles)
	var wanted: PackedVector3Array = rebuilt.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for i in mini(drawn.size(), wanted.size()):
		worst = maxf(worst, drawn[i].distance_to(wanted[i]))
	results.append(TestResult.new(
		"and every point of it is TerrainMesh's own, built from THIS site's terrain description",
		drawn.size() == wanted.size() and drawn.size() > 0 and worst < 1.0e-5,
		"%d drawn points against %d from TerrainMesh, worst %.6f m apart" % [
			drawn.size(), wanted.size(), worst]))

	# AND THE SURFACE IS THE ONE `height_at` ANSWERS OVER — which is a claim about WHICH terrain
	# was drawn, not about two functions agreeing (see the header: they cannot disagree, because
	# the mesh's y values come from `height_at`). The ring that floats over a hill nobody drew is
	# what §0's one-description rule forbids, and a preview built from any other description of
	# the field is what this line catches.
	var off := 0
	var probes := 0
	var sampled := 0
	for point in drawn:
		probes += 1
		if probes % 37 != 0:
			continue
		sampled += 1
		if absf(point.y - room.site().terrain.height_at(point.x, point.z)) > 1.0e-4:
			off += 1
	results.append(TestResult.new(
		"and the ground it draws is the ground height_at answers over — one description, not two",
		off == 0 and probes > 100,
		"%d of %d sampled points off the surface height_at describes" % [off, sampled]))

	# AND IT FOLLOWS AN EDIT. A preview built once at open would pass every line above and still
	# show the old field the moment a dimension is typed.
	var before_points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var before := before_points.size()
	room.set_site_width_m(60.0)
	var after_mesh := room._terrain.mesh as ArrayMesh
	var after_points: PackedVector3Array = after_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var after := after_points.size()
	results.append(TestResult.new(
		"and typing a new width redraws it — the preview is not built once at open",
		after != before
			and absf(room.site().extent().x - 60.0) < 1.0e-6,
		"%d points at %.0f m wide, %d points at %.0f m" % [
			before, SLOPE_SITE_M, after, room.site().extent().x]))

	room.free()
	return results


# ---------------------------------------------------------------------------
# 23. The guesses that now have fields beside them (§0.1)
# ---------------------------------------------------------------------------

## THREE SHIPPED GUESSES, THREE CONTROLS. `Wind.DEFAULT_GUST_TAU_S` was labelled a guess in F7 and
## `Site.DEFAULT_WIDTH_M` / `DEFAULT_LENGTH_M` were chosen numbers F5 deferred; the constraint says
## a guess ships with an editable field BESIDE IT, and this room is the first authoring surface the
## field has ever had.
static func _the_editable_fields() -> Array:
	var results: Array = []
	var room := _room()

	results.append(TestResult.new(
		"gust_tau_s is reachable as an editable field, at the shipped default",
		room.gust_tau_field != null
			and is_equal_approx(room.gust_tau_s, Wind.DEFAULT_GUST_TAU_S)
			and is_equal_approx(room.gust_tau_field.value, Wind.DEFAULT_GUST_TAU_S),
		"room.gust_tau_s = %.4f, field.value = %.4f, Wind.DEFAULT_GUST_TAU_S = %.4f" % [
			room.gust_tau_s,
			-1.0 if room.gust_tau_field == null else room.gust_tau_field.value,
			Wind.DEFAULT_GUST_TAU_S]))

	# THIS USED TO ASSERT THAT A SETTER SETS, AND NOTHING ELSE — which read as coverage of a
	# feature that did not exist. `gust_tau_s` was a plain member on this room: not on
	# `Conditions`, never persisted, and `main.gd` built `Wind.new(conditions)` with no settling
	# time at all, so the number a builder typed was read by NOTHING, ever. The three checks below
	# follow it the whole way instead: onto the record, onto the disk, and into the gust process
	# the shipped scene flies with.
	room.set_field_gust_tau_s(4.2)
	results.append(TestResult.new(
		"editing the field puts the settling time on the SELECTED conditions record",
		is_equal_approx(room.gust_tau_s, 4.2)
			and is_equal_approx(room.conditions.selected().gust_tau_s, 4.2),
		"room.gust_tau_s = %.4f, conditions.selected().gust_tau_s = %.4f" % [
			room.gust_tau_s, room.conditions.selected().gust_tau_s]))

	# AND IT SURVIVES THE FILE. Re-read off disk through the library's own loader, not off the
	# object still in memory — the seam a dial with no wire falls through is exactly the one
	# between the room and the next process to open the file.
	var reloaded := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected()
	results.append(TestResult.new(
		"and it is persisted: conditions.json read back carries the typed settling time",
		reloaded != null and is_equal_approx(reloaded.gust_tau_s, 4.2),
		"reloaded selected().gust_tau_s = %.4f" % (
			-1.0 if reloaded == null else reloaded.gust_tau_s)))

	# AND IT REACHES THE GUST PROCESS, through the function `main.gd` itself calls. Not a source
	# scan and not `Wind.new(conditions, 4.2)` typed here — either of those proves an API and
	# leaves the wiring untested, which is how this field shipped disconnected in the first place.
	var flown: Wind = MAIN_SCRIPT.make_wind(reloaded) if reloaded != null else null
	results.append(TestResult.new(
		"and the shipped scene's own wind builder flies at it — Main.make_wind() passes the " +
			"record's settling time, not Wind's default",
		flown != null and is_equal_approx(flown.gust_tau_s, 4.2)
			and not is_equal_approx(flown.gust_tau_s, Wind.DEFAULT_GUST_TAU_S),
		"Main.make_wind(reloaded).gust_tau_s = %.4f, Wind.DEFAULT_GUST_TAU_S = %.4f" % [
			-1.0 if flown == null else flown.gust_tau_s, Wind.DEFAULT_GUST_TAU_S]))

	# AND THE SCENE THE APP ACTUALLY BOOTS, which is a different claim and the one that was
	# missing. The check above calls `Main.make_wind()` — an API that resembles the production
	# path. It says nothing about whether `_ready` calls it, so `wind = Wind.new(selected)` could
	# come back at `main.gd`'s one production line, dropping the settling time exactly as it
	# shipped, and every check above would stay green. Measured: it did, 3186 results, 0 FAIL.
	#
	# So this boots `main.tscn` itself — the scene file, so the `@onready` node paths resolve —
	# hands it a conditions library the way `RoomHost.show_sim` does, runs the scene's own
	# `_ready()`, and reads `scene.wind`. The subject is the wiring; `make_wind` above is the
	# oracle. A regression at that one line reddens HERE and not in any source scan.
	results.append_array(_the_booted_scene_flies_the_typed_settle_time())

	# The LIVE control's text, not a grep: a source-wide search for "guess" would also match this
	# file's own comments, which is a check that cannot fail against the stated mutation.
	var label_text: String = "" if room.gust_tau_label == null else room.gust_tau_label.text
	results.append(TestResult.new(
		"the shipped gust settle time is labelled a GUESS, not measured, in the UI text",
		label_text.to_lower().contains("guess"),
		"gust label reads: \"%s\"" % label_text))

	# THE SITE'S DIMENSIONS, which had no control at all until now. Driven through the live
	# SpinBox's own signal, so a field built and wired to nothing fails here.
	results.append(TestResult.new(
		"the field's width and length are editable, and open at the shipped 120 m guess",
		room.width_field != null and room.length_field != null
			and is_equal_approx(room.width_field.value, Site.DEFAULT_WIDTH_M)
			and is_equal_approx(room.length_field.value, Site.DEFAULT_LENGTH_M),
		"width %.1f, length %.1f against Site's %.1f x %.1f" % [
			-1.0 if room.width_field == null else room.width_field.value,
			-1.0 if room.length_field == null else room.length_field.value,
			Site.DEFAULT_WIDTH_M, Site.DEFAULT_LENGTH_M]))

	room.width_field.value_changed.emit(80.0)
	room.length_field.value_changed.emit(45.0)
	results.append(TestResult.new(
		"and typing them resizes the site the room is looking at",
		absf(room.site().extent().x - 80.0) < 1.0e-6
			and absf(room.site().extent().y - 45.0) < 1.0e-6,
		"the field is %.1f x %.1f m" % [room.site().extent().x, room.site().extent().y]))

	# ON DISK, like every other edit here — there is no exit to save on.
	var on_disk := SiteLibrary.load_from(ROOM_SITES_PATH).site(room.site().site_id)
	results.append(TestResult.new(
		"and the new size is on disk immediately",
		on_disk != null and absf(on_disk.extent().x - 80.0) < 1.0e-6
			and absf(on_disk.extent().y - 45.0) < 1.0e-6,
		"nowhere on disk" if on_disk == null else "%.1f x %.1f m on disk" % [
			on_disk.extent().x, on_disk.extent().y]))

	room.free()
	return results


## THE BOOTED SIM SCENE'S OWN WIND. `main.tscn` rather than `main.gd`, because `_ready` assigns
## the `@onready` node paths (`$Drone`, `$Ground/GroundMesh`) and a bare script instance has no
## children for them to resolve against. The conditions library is handed over before `_ready`
## runs, which is the order `RoomHost.show_sim` uses.
static func _the_booted_scene_flies_the_typed_settle_time() -> Array:
	var results: Array = []

	var weather := Conditions.new()
	weather.conditions_id = "f2_boot_weather"
	weather.conditions_name = "Gusty"
	weather.gust_tau_s = BOOT_GUST_TAU_S
	var conditions := ConditionsLibrary.new()
	conditions.put(weather)
	conditions.select(weather.conditions_id)

	# THE NON-VACUITY GUARD, FIRST. If the fixture's settling time were the shipped default, the
	# assertion below would hold under every mutation, including the one it exists to catch.
	results.append(TestResult.new(
		"the fixture's settling time is not Wind's shipped default, so a scene flying the " +
			"default is distinguishable from one flying the record",
		not is_equal_approx(weather.gust_tau_s, Wind.DEFAULT_GUST_TAU_S),
		"fixture gust_tau_s = %.4f, Wind.DEFAULT_GUST_TAU_S = %.4f" % [
			weather.gust_tau_s, Wind.DEFAULT_GUST_TAU_S]))

	var packed: PackedScene = load(SIM_SCENE_PATH)
	if packed == null:
		results.append(TestResult.new(
			"the Sim scene can be loaded for the boot", false,
			"load(%s) returned null" % SIM_SCENE_PATH))
		return results
	var scene: Node3D = packed.instantiate()
	scene.conditions_library = conditions
	scene._ready()

	var flown: Wind = scene.wind
	var flown_tau: float = -1.0 if flown == null else flown.gust_tau_s
	results.append(TestResult.new(
		"the BOOTED Sim scene flies the selected record's settling time — _ready builds its " +
			"wind through make_wind(), not a bare Wind.new() that drops the gust tau",
		flown != null and is_equal_approx(flown_tau, BOOT_GUST_TAU_S),
		"booted scene's wind.gust_tau_s = %.4f, the record says %.4f" % [
			flown_tau, BOOT_GUST_TAU_S]))
	# The same thing in the defect's own words, so a regression names itself: what shipped was
	# the default, silently, for any record at all.
	results.append(TestResult.new(
		"and it is NOT Wind's shipped default, which is what the disconnected dial produced",
		flown != null and not is_equal_approx(flown_tau, Wind.DEFAULT_GUST_TAU_S),
		"booted scene's wind.gust_tau_s = %.4f, Wind.DEFAULT_GUST_TAU_S = %.4f" % [
			flown_tau, Wind.DEFAULT_GUST_TAU_S]))

	scene.free()
	return results


# ---------------------------------------------------------------------------
# 24. The wind's three fields
# ---------------------------------------------------------------------------

## SPEED, BEARING AND GUSTINESS HAD NO CONTROL until now — they were on `Conditions`, saved, and
## flown since F7, and every preset anyone made was calm because nothing could make one otherwise.
## Followed the whole way, for `_the_editable_fields`' reason: onto the record, onto the disk, and
## into the Wind the shipped scene's own builder makes. Driven through each live SpinBox's own
## signal, so a field built and wired to nothing fails here.
static func _the_wind_fields() -> Array:
	var results: Array = []
	var room := _room()

	results.append(TestResult.new(
		"the three wind fields exist and open calm on a fresh install",
		room.wind_speed_field != null and room.wind_from_field != null
			and room.gustiness_field != null
			and is_zero_approx(room.wind_speed_field.value)
			and is_zero_approx(room.gustiness_field.value),
		"fields: speed %s, from %s, gust %s" % [
			room.wind_speed_field != null, room.wind_from_field != null,
			room.gustiness_field != null]))
	if room.wind_speed_field == null or room.wind_from_field == null \
			or room.gustiness_field == null:
		room.free()
		return results

	# EACH EDIT IS READ BACK OFF DISK BEFORE THE NEXT ONE. Checked once at the end, a setter that
	# forgot to save passes anyway: the next field's save writes the whole record, carrying the
	# unsaved number along with it. Measured — that mutation went green until this was split.
	var typed_on := room.conditions.selected().conditions_id
	room.wind_speed_field.value_changed.emit(6.5)
	var speed_on_disk := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected().wind_speed_mps
	room.wind_from_field.value_changed.emit(270.0)
	var from_on_disk := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected().wind_from_deg
	room.gustiness_field.value_changed.emit(2.0)
	var gust_on_disk := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected().gustiness_mps
	results.append(TestResult.new(
		"each wind edit is on disk immediately, on its own — not carried by the next field's save",
		is_equal_approx(speed_on_disk, 6.5) and is_equal_approx(from_on_disk, 270.0)
			and is_equal_approx(gust_on_disk, 2.0),
		"read back after each edit: %.2f m/s, %.1f°, gusts %.2f" % [
			speed_on_disk, from_on_disk, gust_on_disk]))
	var now := room.conditions.selected()
	results.append(TestResult.new(
		"typing them puts speed, bearing and gustiness on the SELECTED conditions record",
		is_equal_approx(now.wind_speed_mps, 6.5) and is_equal_approx(now.wind_from_deg, 270.0)
			and is_equal_approx(now.gustiness_mps, 2.0) and now.conditions_id == typed_on,
		"record %s: %.2f m/s from %.1f°, gusts %.2f m/s" % [
			now.conditions_id, now.wind_speed_mps, now.wind_from_deg, now.gustiness_mps]))

	var reloaded := ConditionsLibrary.load_from(ROOM_CONDITIONS_PATH).selected()
	results.append(TestResult.new(
		"and they are persisted: conditions.json read back carries all three",
		reloaded != null and is_equal_approx(reloaded.wind_speed_mps, 6.5)
			and is_equal_approx(reloaded.wind_from_deg, 270.0)
			and is_equal_approx(reloaded.gustiness_mps, 2.0),
		"nothing reloaded" if reloaded == null else "%.2f m/s from %.1f°, gusts %.2f" % [
			reloaded.wind_speed_mps, reloaded.wind_from_deg, reloaded.gustiness_mps]))

	var flown: Wind = MAIN_SCRIPT.make_wind(reloaded) if reloaded != null else null
	results.append(TestResult.new(
		"and the shipped scene's own wind builder flies them",
		flown != null and is_equal_approx(flown.speed_mps, 6.5)
			and is_equal_approx(flown.from_deg, 270.0)
			and is_equal_approx(flown.gustiness_mps, 2.0),
		"no wind" if flown == null else "Wind: %.2f m/s from %.1f°, gusts %.2f" % [
			flown.speed_mps, flown.from_deg, flown.gustiness_mps]))

	# ONE BEARING, ONE SPELLING. 360 is north, and -90 is west; stored any other way they would be
	# two lap fingerprints for one day's wind.
	room.wind_from_field.value_changed.emit(360.0)
	var wrapped_north := room.conditions.selected().wind_from_deg
	room.set_field_wind_from_deg(-90.0)
	var wrapped_west := room.conditions.selected().wind_from_deg
	results.append(TestResult.new(
		"the bearing is wrapped into [0, 360): 360 is stored as 0 and -90 as 270",
		is_zero_approx(wrapped_north) and is_equal_approx(wrapped_west, 270.0)
			and is_equal_approx(room.wind_from_field.value, 270.0),
		"360 -> %.1f, -90 -> %.1f, field shows %.1f" % [
			wrapped_north, wrapped_west, room.wind_from_field.value]))

	room.set_field_wind_speed_mps(-4.0)
	room.set_field_gustiness_mps(-1.0)
	results.append(TestResult.new(
		"a negative speed or gustiness from a headless caller is clamped to zero, not stored",
		is_zero_approx(room.conditions.selected().wind_speed_mps)
			and is_zero_approx(room.conditions.selected().gustiness_mps),
		"speed %.2f, gust %.2f" % [room.conditions.selected().wind_speed_mps,
			room.conditions.selected().gustiness_mps]))

	# THE CONTROLS FOLLOW THE SELECTED SET. Switching preset must show that preset's wind, not keep
	# the last one typed — otherwise the next keystroke writes the old set's wind onto the new one.
	room.set_field_wind_speed_mps(6.5)
	room.set_field_temperature_c(33.0)
	var calm_speed := room.wind_speed_field.value
	room.conditions.select(typed_on)
	room.refresh()
	results.append(TestResult.new(
		"switching preset re-reads the wind fields: a calm 33 °C set shows 0, and back shows 6.5",
		is_zero_approx(calm_speed) and is_equal_approx(room.wind_speed_field.value, 6.5),
		"on the 33 °C set the field read %.2f, back on %s it reads %.2f" % [
			calm_speed, typed_on, room.wind_speed_field.value]))

	room.free()
	return results
