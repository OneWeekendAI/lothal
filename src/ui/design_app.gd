class_name DesignApp
extends Control
## THE APPLICATION ROOT: the Design Space and the screens around it, in one language.
##
## Boot lands on the Projects screen; a project opens onto the class picker (new) or the Design
## Space (existing); "Fly it" takes the design into the simulator; the DS "..." menu is the door to
## every other room (setup pages, the benches, Studio, the Field, the Mission picker, Projects).
## Every one of those is a Design Space screen: `LothalTheme` tokens, `DsUi` controls, drawers.
##
## It replaced the old glass shell, its dock, its room menu and the eight-tab shell (R9). What survived of them is the
## project lifecycle (open, adopt, autosave, disk changes), the hand-over of the design to the
## simulator and the Field, and the printed-part export. What did not: the system dropdown, the
## bottom dock, the part rail and inspector, the page bar, the finder and the Lab stage. The
## `LabScreen` still exists as the headless model every room reads (`rooms.lab`): it holds the
## catalog, the build and the sheets, and its own viewport is never shown.
##
## Built in code, not in a scene: hand-placed UI does not survive version control (architecture.md).

## The layer the app's floating screens ride on; the sim's HUD has a layer of its own above the tree.
const TOGGLE_LAYER := 10
const AUTOSAVE_SECONDS := 1.0
const EXPORT_DIRECTORY := "user://exports"

var rooms: RoomHost
var lab: LabScreen:
	get:
		return rooms.lab if rooms != null else null
var container: ProjectContainer
var printed_export_dir: String = EXPORT_DIRECTORY
var last_printed_export_summary := ""
var open_folder_after_export := true
var printed_divergence: Array = []
var projects_screen: ProjectsScreen
var class_picker: ClassPicker
var _class_picker_layer: CanvasLayer
var _picker_new_path := ""
var design_space: DesignSpace
var _design_space_layer: CanvasLayer
var settings: AppSettings
var _autosave: Timer
var _open_dialog: FileDialog
var _field: FieldSystem
## The Setup pages (the lab's sheets in a Design Space frame) and the layer they ride on.
var setup: DsSetup
var _setup_layer: CanvasLayer
## What the last status message said; a message also shows as a toast.
var _status_text := ""
var _toast: DsToast
var _toast_layer: CanvasLayer
## The room the away bar is standing over ("" when the design is up).
var away_room := ""
## True when this is the running scene: opening a project then lands on its Design Space.
var interactive := false


func _init(p_catalog: PartsCatalog = null, p_tweaks: AssemblyTweaks = null,
		p_pack_charge: PackCharge = null) -> void:
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	settings = AppSettings.load_from()
	container = ProjectContainer.make(ProjectLibrary.starting_project())
	var catalog := p_catalog if p_catalog != null else PartsCatalog.load_with_custom()
	rooms = RoomHost.new(catalog, p_tweaks, p_pack_charge)
	add_child(rooms)
	_build_update_notice()
	_build_field()
	_build_setup()
	_build_projects_screen()
	_build_toast()


func _ready() -> void:
	if get_tree() != null and get_tree().root != null and settings != null:
		get_tree().root.content_scale_factor = settings.ui_scale
	# The lab's own stage is never shown: the Design Space is the stage.
	_hide_lab_stage()
	lab.battery_details.fit_to_content()

	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(_on_autosave_tick)
	add_child(_autosave)
	_autosave.start()

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.%s ; Lothal drone" % ProjectContainer.EXTENSION])
	_open_dialog.current_dir = ProjectSettings.globalize_path(ProjectLibrary.DIR)
	_open_dialog.file_selected.connect(open_project)
	add_child(_open_dialog)

	# THE APP OPENS ON THE PROJECTS SCREEN, only when it is the running scene: an app a test
	# constructs is not, and keeps the resume-or-adopt behaviour every suite is written against.
	var boot_to_projects := get_tree() != null and get_tree().current_scene == self
	interactive = boot_to_projects
	var resumed := false
	for path in ([] if boot_to_projects else settings.existing_recent_projects()):
		open_project(path)
		if container.path == path:
			resumed = true
			break
	if not resumed and not boot_to_projects:
		adopt(container.project)
	for picker in [lab.picker, lab.motor_picker, lab.propeller_picker, lab.battery_picker,
			lab.esc_picker, lab.fc_picker]:
		picker.part_selected.connect(func(_part: Dictionary) -> void: _refresh_status())
	for rail in lab.component_rails():
		rail.components_changed.connect(_refresh_status)
	lab.propeller_details.guard_changed.connect(func(_guard_id: String) -> void: _refresh_status())
	lab.motor_details.mount_changed.connect(func(_mount_id: String) -> void: _refresh_status())
	lab.tune_panel.tune_changed.connect(_refresh_status)
	lab.print_panel.export_requested.connect(_on_printed_export_requested)
	lab.print_panel.divergence_kept.connect(keep_divergence)
	lab.print_panel.divergence_reprint_requested.connect(reprint_part)
	lab.motor_details.mount_stl_requested.connect(_on_mount_stl_requested)
	lab.propeller_details.guard_stl_requested.connect(_on_guard_stl_requested)
	lab.harness_panel.harness_room_requested.connect(func() -> void: setup.show_harness_room())
	setup.adopt_panels(lab)
	if boot_to_projects:
		_clear_project()


## The lab's viewport (its 3D stage) never shows: the Design Space is the stage.
func _hide_lab_stage() -> void:
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = false
	lab.rails().visible = false
	lab.panels.visible = false


func _build_projects_screen() -> void:
	projects_screen = ProjectsScreen.new(rooms.catalog_for_lab())
	projects_screen.visible = false
	projects_screen.new_requested.connect(new_project)
	projects_screen.open_requested.connect(func() -> void: _open_dialog.popup_centered_ratio(0.6))
	projects_screen.project_chosen.connect(open_project)
	projects_screen.project_deleted.connect(func(gone: String) -> void:
		settings.forget_project(gone)
		settings.save())
	add_child(projects_screen)


func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = TOGGLE_LAYER + 20
	add_child(_toast_layer)
	_toast = DsToast.new()
	_toast.offset_left = 24
	_toast.offset_top = 64
	_toast_layer.add_child(_toast)


func _build_setup() -> void:
	_setup_layer = CanvasLayer.new()
	_setup_layer.name = "SetupLayer"
	_setup_layer.layer = TOGGLE_LAYER + 5
	_setup_layer.visible = false
	add_child(_setup_layer)
	setup = DsSetup.new()
	setup.closed.connect(back_to_drone_from_room)
	_setup_layer.add_child(setup)


## What the last message said (a status line is a toast now).
func status_text() -> String:
	return _status_text


func _say(text: String, warn := false) -> void:
	_status_text = text
	if _toast != null and text != "":
		_toast.say(text, warn)


func _refresh_status() -> void:
	_sync_project()


func projects_shown() -> bool:
	return projects_screen != null and projects_screen.visible


## Takes the room the DS menu named. "projects" saves and goes to the Projects screen.
func open_room(room_id: String) -> bool:
	match room_id:
		"projects":
			_on_project_action("projects")
			return true
		"setup":
			return open_setup()
		"bench", "esc_bench", "frame_bench", "studio":
			if design_space == null or not _sync_design_to_lab():
				return false
			_enter_away(room_id)
			match room_id:
				"bench": rooms.show_bench()
				"esc_bench": rooms.show_esc_bench()
				"frame_bench": rooms.show_frame_bench()
				"studio": rooms.show_studio()
			return true
	push_error("no such room: %s" % room_id)
	return false


## The Setup pages: the lab's sheets (frame, propulsion, power, control, video, printed, config).
func open_setup(page := "") -> bool:
	if design_space == null or not _sync_design_to_lab():
		return false
	_enter_away("setup")
	_setup_layer.visible = true
	setup.show_page(page)
	return true


## The bar that says a newer Lothal exists, and the link out to us.
##
## Both come straight from the old shell, and both ride the toggle's CanvasLayer for the reason the
## toggle does: Sim's HUD is on a layer of its own and would draw over anything in the ordinary
## tree. An update bar that only appeared in the garage would be a bar most people never see.
func _build_update_notice() -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOGGLE_LAYER
	add_child(layer)

	var notice := UpdateNotice.new(LothalVersion.MANIFEST_URL)
	notice.theme = LothalTheme.get_theme()
	notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	notice.anchor_top = 1.0
	notice.anchor_right = 1.0
	notice.anchor_bottom = 1.0
	notice.offset_top = -UpdateNotice.BAR_HEIGHT
	layer.add_child(notice)


## The Field room (F10). Built hidden and shown with its system, the way the plan editor is, rather
## than opened on request the way the blade and harness designers are — because there is nothing to
## pick here: choosing Field IS asking to look at the field.
##
## THE THREE LIBRARIES ARE THE SHELL'S, not copies. `RoomHost` holds one of each for the session
## precisely so the garage and the field cannot come to disagree about where the builder is, and a
## room that loaded its own would be a second opinion that saves over the first.
func _build_field() -> void:
	# THE BUILD IS HANDED OVER for exactly one reason — a ring smaller than the aircraft that has
	# to fly through it is impossible, and that is a comparison of two known dimensions. It is also
	# what the footprint on the ground is drawn at. This room changes nothing about it.
	_field = FieldSystem.new(
		rooms.site_library, rooms.course_library, rooms.conditions_library,
		rooms.lab.current_build())
	_field.name = "Field"
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.anchor_right = 1.0
	_field.anchor_bottom = 1.0
	# Clear of the floating chrome on three sides. The right edge runs to the margin rather than
	# stopping short of `INSPECTOR_WIDTH`, because this room brings its own three panels — the
	# shell's inspector comes down for it, the way it does for Airframe.
	_field.offset_left = 0
	_field.offset_right = 0
	_field.offset_top = AWAY_BAR_ROOM
	_field.offset_bottom = 0
	_field.visible = false
	_field.selection_changed.connect(_on_field_selection_changed)
	# AND EVERY EDIT MOVES THE GARAGE (F11). Editing the field changes what the aircraft next door
	# CAN DO: without this the builder types 3500 m, walks back to the garage and reads a
	# thrust-to-weight for a place they are not. The old field editor carried this wiring on
	# `RoomHost`; the authoring moved, so the wiring moved with it rather than being left behind.
	_field.course_changed.connect(_on_field_course_changed)
	_field.edit_world_requested.connect(open_world_editor)
	add_child(_field)


## The Field room, for the capture tooling and for a test — `workbench()`'s posture and its reason.
func field_room() -> FieldSystem:
	return _field


## A different site or course picked in the Field room, so the GARAGE'S AIR MOVES WITH IT.
##
## This is the §3.1 rule the whole plan is built on, wired: the air the garage quotes is the air of
## the place the selected course is laid out in. Asked of `RoomHost`, which owns that answer, rather
## than composed here — two spellings of "where are we" is how the two come to disagree.
## An edit in the Field room. The air AND the weather, because this room switches both: a builder
## who picks a hotter day and walks back must see that day's numbers, not the ones Lab opened with.
func _on_field_course_changed() -> void:
	if lab != null:
		lab.set_air(rooms.air_of_selected_course())
		lab.set_conditions(rooms.conditions_library.selected())
	_refresh_status()


func _on_field_selection_changed() -> void:
	if lab != null:
		lab.set_air(rooms.air_of_selected_course())
	_refresh_status()


## The propulsion exports. Both land in the same `user://exports` folder `FrameWorkbench` writes
## to and both open it afterwards, on that room's own argument: a file you cannot find has not been
## exported. The path is in the status line too, because `OS.shell_open` does nothing headless.
func _on_mount_stl_requested(motor: Dictionary) -> void:
	if container == null:
		return
	# The stack on the AIRCRAFT, not a fresh one built from the same parts. It already carries the
	# builder's assembly tweaks — the pad thickness and the shim stack — and rebuilding it here
	# would be a second construction that could silently disagree with the one on screen about
	# exactly the two numbers a fit check is asked about.
	var mesh: MotorMesh = lab.airframe.motor_meshes.get(MotorLayout.MOTOR_NAMES[0])
	if mesh == null:
		return
	var solid_name := _safe_export_name(String(motor.get("part_id", "motor")) + "-mount")
	var path := "%s/%s.stl" % [EXPORT_DIRECTORY, solid_name]
	DirAccess.make_dir_recursive_absolute(EXPORT_DIRECTORY)
	_report_export(PropulsionExport.write_mount_stack(mesh, solid_name, path), path)


func _on_guard_stl_requested(guard_id: String) -> void:
	if guard_id == "":
		return
	var guard := lab.catalog.get_part(guard_id)
	# PG1: the ring is sized to the open drone's prop, the radius the Printed room's dispatcher
	# passes, so the two doors to this export still write the same bytes.
	var tip_m := float(lab.current_build().prop_geometry()["diameter_m"]) * 0.5
	var solid_name := _safe_export_name(guard_id)
	var path := "%s/%s.stl" % [EXPORT_DIRECTORY, solid_name]
	DirAccess.make_dir_recursive_absolute(EXPORT_DIRECTORY)
	_report_export(PropulsionExport.write_guard(guard, tip_m, path), path)


## The Printed room's Export buttons. Each id routes into the export that already exists for that
## part — the prop guard goes through the same handler Propulsion's own button uses, so there is one
## guard export and two doors to it, never two exports.
func _on_printed_export_requested(part_id: String) -> void:
	if part_id == PrintedParts.PROP_GUARD:
		_on_guard_stl_requested(lab.propeller_details.guard_id())
		return
	# Every generated part goes through the one dispatcher the whole-room export uses, on the build WITH
	# the assembly on it: the camera mount prints at the Camera tilt, which `current_build()` alone lacks.
	var solid := PrintedParts.solid_for(lab.build_with_open_harness(), part_id)
	if not bool(solid["ok"]):
		_report_export({"ok": false, "reason": String(solid["reason"])}, "")
		return
	var solid_name := _safe_export_name(String(solid["solid_name"]))
	var path := printed_export_dir.path_join("%s.stl" % solid_name)
	DirAccess.make_dir_recursive_absolute(printed_export_dir)
	_report_export(StlWriter.write_bodies(solid_name, solid["bodies"], path) if solid.has("bodies")
		else StlWriter.write(solid_name, solid["triangles"], path), path)


## "Export printed parts…" — every part this drone prints, written to the exports folder AND into the
## drone's own file under printed/, each with a print record (printed-room PR4). A refused part is
## named and refuses only itself. The container is written at once when it has a home, so the record of
## a print does not wait for the next autosave; a container with no path (a test's) writes nothing.
func export_printed_parts() -> Dictionary:
	if container == null or lab == null:
		return {}
	_sync_project()
	var result := PrintedExport.export_all(lab.build_with_open_harness(),
		printed_export_dir, container)
	if not (result.get("written", []) as Array).is_empty() and container.path != "":
		_save_container(true)
	last_printed_export_summary = String(result.get("summary", ""))
	_say(last_printed_export_summary)
	return result


## Says what happened, and says it the way `StlWriter` said it. A refusal names the part and the
## reason — "the surface is not closed", "the solid is inside out" — rather than "export failed",
## because the first is something a builder can report and the second is not.
func _report_export(result: Dictionary, path: String) -> void:
	if bool(result["ok"]):
		_say("Wrote %s" % ProjectSettings.globalize_path(path))
		if open_folder_after_export:
			OS.shell_open(ProjectSettings.globalize_path(path.get_base_dir()))
	else:
		_say("NOT EXPORTED — %s" % String(result["reason"]), true)


## One spelling of a safe file name, shared with PrintedExport so a part exported from its button and
## from the project menu lands under the same name.
static func _safe_export_name(text: String) -> String:
	return PrintedExport.safe_name(text)


## What the bottom-left strip reads: the focused system, and how many systems have been DECIDED.
##
## Decided, not scored. §9 forbids an aggregate quality score and the ring is deliberately "how much
## you have decided", not "how good the drone is" — so this counts slots that hold a choice and says
## nothing whatever about whether the choice is good. A system with no model can never be decided,
## which is why the figure starts at five of nine rather than at zero.
##
## **Today it is constant at five of nine, and that is worth saying rather than hiding.** Every rail
## opens on a selection and none can be cleared, so all six modelled systems are decided from the
## first frame and the arc never moves. I expected Video to make it live — a whoop publishes no
## camera or VTX bay — but the picker keeps its ids regardless of the frame, so `selection()` never
## returns an empty one. Checked, not assumed.
##
## Left in anyway, because the ring is a slot in the frame and a frame is what this file is. What it
## must NOT become is a number that looks live and is not: when the four unmodelled systems arrive
## the arc starts moving on its own, and until then this comment is the honest label.
## Keep (PR7): acknowledges the finding for `part_id` in this drone's printing block, writes the drone
## when it has a home, and checks again. The record stays.
func keep_divergence(part_id: String) -> void:
	for finding in printed_divergence:
		if String(finding["part"]) == part_id:
			PrintedDivergence.acknowledge(lab.printing, finding)
	_sync_project()
	if container != null and container.path != "":
		_save_container(true)
	_report_printed_divergence()


## Reprint (PR7): re-exports only `part_id` through the shared export, appending its record, writes the
## drone when it has a home, and checks again.
func reprint_part(part_id: String) -> void:
	if container == null or lab == null:
		return
	_sync_project()
	var result := PrintedExport.export_part(lab.build_with_open_harness(), part_id,
		printed_export_dir, container)
	if bool(result["ok"]) and container.path != "":
		_save_container(true)
	_report_printed_divergence()
	if not bool(result["ok"]):
		_say("NOT REPRINTED — %s" % String(result["reason"]), true)


## Rename is ProjectChip's own; everything else lands here.
func _on_project_action(action_id: String) -> void:
	match action_id:
		"new":
			new_project()
		"duplicate":
			adopt(ProjectLibrary.duplicate_of(container.project))
		"open":
			_open_dialog.popup_centered_ratio(0.6)
		"export_printed":
			export_printed_parts()
		"reveal":
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(
				container.path if container.path != "" else ProjectLibrary.DIR))
		"delete":
			# The container is moved to the app's trash, not unlinked — §10 of the projects design,
			# and the reason there is no confirmation dialog. Nothing replaces it: the app closes
			# the drone and shows the empty state, because a delete that handed you a fresh
			# "Untitled build" in the same second looked exactly like a delete that did nothing.
			var gone := container.path
			if gone != "":
				ProjectLibrary.delete(gone)
				settings.forget_project(gone)
				settings.save()
			_clear_project()
		"projects":
			# Saves first, then closes: the drone is on disk and the table shows it as just edited.
			_on_autosave_tick()
			_clear_project()
		"rename":
			pass
		_:
			push_warning("project action '%s' is not built yet" % action_id)


## New drone: the one path both New entries (the chip and the projects screen) take.
##
## The drone is adopted FIRST — written before it is shown, see `adopt` — as the 5" starting build,
## and the class picker goes up over it. Choosing a class rewrites that same project's parts and
## class; dismissing the picker leaves the 5" starting build with no class chosen. Either way there
## is exactly one new file, and no window of time in which the new drone exists only in memory.
func new_project() -> void:
	adopt(ProjectLibrary.starting_project())
	_picker_new_path = container.path
	show_class_picker()


## Puts the class picker up, over everything including the dock (its own CanvasLayer, above the
## dock's), because nothing behind it is meant to be used until a class is chosen.
func show_class_picker() -> ClassPicker:
	_close_class_picker()
	_class_picker_layer = CanvasLayer.new()
	_class_picker_layer.name = "ClassPickerLayer"
	_class_picker_layer.layer = TOGGLE_LAYER + 5
	add_child(_class_picker_layer)
	class_picker = ClassPicker.new(rooms.catalog_for_lab())
	class_picker.class_chosen.connect(choose_class)
	class_picker.dismissed.connect(_on_picker_dismissed)
	_class_picker_layer.add_child(class_picker)
	return class_picker


## Esc on the picker: it closes, and a Design Space waiting behind it comes back as it was.
##
## Back / Esc on the picker of a NEW drone (no class chosen yet) abandons it: the just-written
## starting file is removed, not trashed (nothing in it was ever the builder's work), and the
## projects screen comes back. Over a Design Space it just returns there.
func _on_picker_dismissed() -> void:
	_close_class_picker()
	if _picker_new_path != "" and container != null and container.path == _picker_new_path \
			and container.project.drone_class == "":
		var gone := _picker_new_path
		_picker_new_path = ""
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gone))
		_clear_project()
		return
	_picker_new_path = ""
	_set_design_space_shown(true)


func _set_design_space_shown(shown: bool) -> void:
	if _design_space_layer != null:
		_design_space_layer.visible = shown
	if design_space != null:
		design_space.visible = shown
		design_space.set_active(shown)


## Back from the Design Space: the picker goes up over it with the current class on show. The
## Design Space is only hidden, so Esc on the picker returns to it unchanged.
func back_to_class_picker() -> ClassPicker:
	if design_space == null:
		return null
	var id := design_space.session.drone_class
	_set_design_space_shown(false)
	var picker := show_class_picker()
	picker.show_class(id)
	return picker


## Writes the chosen class into the open project, fits its parts on the rails and saves.
func choose_class(class_id: String) -> bool:
	if container == null or not DroneClass.apply_to(container.project, class_id):
		return false
	apply_project(container.project)
	container.project.touch()
	container.write(container.path)
	_refresh_status()
	_picker_new_path = ""
	_close_class_picker()
	show_design_space()
	return true


## The Design Space over everything, on the open project's drone (its own CanvasLayer, like the picker).
func show_design_space() -> DesignSpace:
	_close_design_space()
	if container == null:
		return null
	_design_space_layer = CanvasLayer.new()
	_design_space_layer.name = "DesignSpaceLayer"
	_design_space_layer.layer = TOGGLE_LAYER + 5
	add_child(_design_space_layer)
	design_space = DesignSpace.new(DesignSession.from_project(container.project), rooms.catalog_for_lab())
	# A project the builder already changed is a saved project; an untouched one is the class seed.
	var seed_parts := DroneClass.parts_for(container.project.drone_class)
	for category in seed_parts:
		if String(container.project.parts.get(category, "")) != String(seed_parts[category]):
			design_space.design_source = "saved project"
			design_space.refresh_identity()
			break
	design_space.dismissed.connect(_close_design_space)
	design_space.back_requested.connect(back_to_class_picker)
	design_space.fly_requested.connect(_on_fly_requested)
	design_space.field_requested.connect(open_field_from_design)
	design_space.mission_requested.connect(open_mission_picker)
	design_space.room_requested.connect(open_room)
	_design_space_layer.add_child(design_space)
	design_space.migrate_old_drafts()
	return design_space


## The Mission picker's Watch: the shell re-emits it (for observers) and itself takes the design into
## the sim and starts the watched flight (`watch_mission_from_design`).
signal mission_watch_requested(opts: Dictionary)


var world_editor: WorldEditor


var mission_picker: MissionPicker


var _pickers_layer: CanvasLayer


## One overlay layer for the Mission picker and World editor, made on first use.
func _pickers_overlay() -> CanvasLayer:
	if _pickers_layer == null:
		_pickers_layer = CanvasLayer.new()
		_pickers_layer.name = "PickersLayer"
		_pickers_layer.layer = TOGGLE_LAYER + 8
		add_child(_pickers_layer)
	return _pickers_layer


## Field room's Edit world: one WorldEditor, reused, loaded with that world (a copy; saved back on change).
func open_world_editor(world_id: String) -> bool:
	if _field == null or _field.worlds == null:
		return false
	var w := _field.worlds.world(world_id)
	if w == null:
		return false
	if world_editor != null:
		_pickers_overlay().remove_child(world_editor)
		world_editor.queue_free()
	world_editor = WorldEditor.new(WorldEditModel.new(w))
	world_editor.set_meta("world_id", world_id)
	world_editor.changed.connect(func(edited: World) -> void:
		_field.worlds.put(edited))
	var layer := _pickers_overlay()
	layer.add_child(world_editor)
	world_editor.show()
	return true


## The Design Space's Mission button: one MissionPicker for the open design, reused.
func open_mission_picker() -> bool:
	if design_space == null:
		return false
	if mission_picker == null:
		mission_picker = MissionPicker.new()
		mission_picker.watch_requested.connect(func(opts: Dictionary) -> void:
			mission_watch_requested.emit(opts)
			watch_mission_from_design(opts))
		var layer := _pickers_overlay()
		layer.add_child(mission_picker)
	mission_picker.set_session(design_space.session)
	design_space.identity_sheet.hide()
	# One left drawer at a time: the Parts list closes, and opening Parts closes the drawer.
	design_space.shelf.set_open(false)
	if not design_space.shelf.toggled.is_connected(_hide_mission_picker):
		design_space.shelf.toggled.connect(_hide_mission_picker)
	design_space.side_drawer = mission_picker
	mission_picker.show()
	return true


## "Watch it": the open design flown in view. Same door as Fly it (sync, then the sim with the
## session's Build), the Mission drawer put away, and the sim's `watch_mission` started with the
## params `MissionFlow` itself builds, so the watched result equals the headless one.
func watch_mission_from_design(opts: Dictionary) -> bool:
	if not fly_it():
		return false
	var sim = rooms.sim
	if sim == null:
		return false
	if not sim.watch_finished.is_connected(_on_watch_finished):
		sim.watch_finished.connect(_on_watch_finished)
		sim.back_to_design_requested.connect(back_to_drone_from_room)
	var started: bool = sim.watch_mission(MissionFlow.params_for(design_space.session, opts))
	if mission_picker != null:
		mission_picker.set_watching(started)
	return started


## The watched flight ended: the picker's Watch and Run are free again.
func _on_watch_finished(_result: Dictionary) -> void:
	if mission_picker != null:
		mission_picker.set_watching(false)


func _hide_mission_picker(shelf_open: bool) -> void:
	if shelf_open and mission_picker != null:
		mission_picker.hide()


func _close_design_space() -> void:
	_close_away_bar()
	if mission_picker != null:
		mission_picker.hide()
	if _design_space_layer != null:
		remove_child(_design_space_layer)
		_design_space_layer.queue_free()
	_design_space_layer = null
	design_space = null


func _close_class_picker() -> void:
	if _class_picker_layer != null:
		remove_child(_class_picker_layer)
		_class_picker_layer.queue_free()
	_class_picker_layer = null
	class_picker = null


## Takes on a new drone: gives it a home, fits it on the rails, and points the chip at it.
##
## A new project is WRITTEN BEFORE IT IS SHOWN. §5 removed the save button, and a document with no
## path cannot autosave — so a new drone that waited for a save would be the one document in the
## app whose work is lost by default, which is exactly what the save button used to prevent.
func adopt(project: Project) -> Array:
	ProjectLibrary.ensure_dir()
	container = ProjectContainer.make(project)
	container.write(ProjectLibrary.path_for(project))
	var missing := apply_project(project)
	_show_project()
	_remember(container.path)
	_refresh_status()
	return missing


## Opens a container from anywhere on disk. Returns the categories that could not be fitted.
##
## A file that will not open leaves the drone on screen exactly as it was. The alternative — half
## adopting it and leaving the rails on the previous aircraft — would put the chip's name and the
## model on screen out of step, which is the state a builder cannot detect and cannot recover from.
func open_project(path: String) -> Array:
	var opened := ProjectContainer.open(path)
	if opened == null:
		push_warning("%s would not open" % path)
		return [{"category": "", "part_id": path}]
	container = opened
	var missing := apply_project(opened.project)
	_show_project()
	_remember(opened.path)
	_refresh_status()
	_report_printed_divergence()
	return missing


## Printed-room PR5: generates every printed part again and says which no longer match their print
## records. After `_refresh_status`, so the finding is what the status line ends up saying.
func _report_printed_divergence() -> void:
	printed_divergence = []
	if container == null or lab == null:
		return
	printed_divergence = PrintedDivergence.check(container.project, container,
		lab.build_with_open_harness())
	lab.print_panel.set_divergence(printed_divergence)
	# The Printed rows say it too (amber), and stop saying it once kept or reprinted.
	if printed_divergence.is_empty():
		return
	var lines: Array = []
	for finding in printed_divergence:
		lines.append(String(finding["message"]))
	_say(" ".join(PackedStringArray(lines)), true)


## Fits a project's parts on the rails. Whatever could not be fitted comes back named — see
## LabScreen.apply_selection, which refuses to substitute.
func apply_project(project: Project) -> Array:
	if lab == null:
		return []
	# The drawing is read NOW, before anything below moves a rail. `container` is already this
	# project, and every rail the selection moves fires `_refresh_status`, whose `_sync_project`
	# writes `lab.drawn_frame()` — still the PREVIOUS drone's frame, `{}` for a catalogue one — into
	# `project.airframe`. Read after the selection, the drawing was gone before it was applied: the
	# Lab opened on the catalogue frame and the next autosave wrote `{}` over the file. (Printing
	# and config escape this only because they reach the lab before the first rail moves.)
	var drawn := project.airframe.duplicate(true)
	# AND THE PARTS, for the same reason. `apply_selection` walks the dictionary it is handed while
	# each rail it moves fires `_sync_project` into `project.parts` — the very dictionary — so handed
	# `project.parts` itself it read back the PREVIOUS drone's ids for every category after the first
	# one that moved. Invisible while every drone opened onto the same rails; a reload of a file whose
	# battery had been changed outside (TestDiskChanges) kept the old battery on screen.
	var parts := project.parts.duplicate(true)
	# Printing first, so the rebuild the selection triggers already describes this drone's parts.
	lab.set_printing(project.printing)
	# Before the selection too, for the same reason printing is: the rebuild the selection triggers
	# draws the propellers, and they turn the way THIS drone is configured.
	lab.set_config(project.config)
	# And the name, for the sheet's header and its file name (C9). Set here with the rest of the
	# per-drone state, so a sheet cannot go out carrying the previously-opened drone's name.
	lab.drone_name = project.name
	var missing := lab.apply_selection(parts)
	# After the selection, so the drawing lands on THIS drone's fitted frame — and always, so a drone
	# with no drawing does not inherit the previous drone's on the same catalogue frame.
	lab.set_drawn_frame(drawn)
	project.airframe = lab.drawn_frame()
	return missing


func _remember(path: String) -> void:
	settings.remember_project(path)
	settings.save()


## Copies the rails' selection into the document.
##
## ONE DIRECTION ONLY, and that is the honest half of the wiring: the rails are still the source of
## truth for what is fitted, and the Project follows them. The other direction — a project OPENING
## and driving the rails — is what New and Open need, and it is why those two entries are greyed
## rather than half-wired. A shell that could load a drone into the pickers would have to own what
## happens to the one already there, and that question belongs with the container.
func _sync_project() -> void:
	if container == null or lab == null:
		return
	var selection := lab.selection()
	for category in selection:
		container.project.parts[category] = str(selection[category])
	# The printing block follows the lab's working copy the same way (printed-room PR0). Copied, not
	# shared, so the dirty check compares two objects rather than one object with itself.
	container.project.printing = lab.printing.duplicate(true)
	# And the config block the same way (Config C1/C3): the motor map is per drone, so it follows
	# the lab's working copy into the document rather than living anywhere global.
	container.project.config = lab.config.duplicate(true)
	# And the drawn frame (Airframe room), `{}` while the fitted frame is untouched.
	container.project.airframe = lab.drawn_frame()


## The autosave tick. Asks, rather than writes: an unchanged project costs one JSON stringify and
## one hash of the file — the hash because a file changed from outside is taken on whether or not
## anything here is unsaved (`_save_container`).
func _on_autosave_tick() -> void:
	if container == null or container.path == "":
		return
	_sync_project()
	_save_container()


## Coming back to the window is when an outside edit is most likely to be waiting — the builder was
## in the other app making it. Taken only when nothing here is unsaved; with unsaved edits the next
## tick keeps both sides, and doing that on focus as well would only do it a second earlier.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if container == null or container.path == "" or lab == null:
		return
	_sync_project()
	if container.changed_on_disk() and not container.has_unsaved_changes():
		_take_disk_version()


## The one way the shell writes its drone (ProjectContainer, "THE FILE IS NOT ONLY OURS").
##
## A file that changed from outside is never written over. With nothing unsaved here the outside
## version simply wins: it is reloaded and the Lab rebuilt from it. With unsaved edits here NEITHER
## side is lost — the outside version stays the file, this app's goes to a conflict copy beside it,
## and the Lab shows the file. The other way round (keep ours, copy theirs) would put the newer,
## deliberate edit in a file nobody opens.
##
## `always` is for the writers that changed a member rather than the document — an export puts STL
## bytes in `printed/`, which `has_unsaved_changes` does not see — and wrote unconditionally before.
func _save_container(always: bool = false) -> void:
	if container.changed_on_disk():
		_take_disk_version(always)
	elif always or container.has_unsaved_changes():
		container.write()


## Reloads the drone from its file, keeping this app's unsaved edits in a conflict copy first.
##
## Read BEFORE the copy is written: a file caught half-written by whatever is changing it will not
## open, and then nothing happens at all — the file is not written over, no copy is made, and the
## next tick asks again. A copy per tick of a file mid-write would be a folder full of them.
##
## The notice goes on the status line, where the printed-divergence findings already go: the
## calmest place that is still read, and it gives way to the ordinary readout on the next change.
##
## `keep_ours` copies even when the document has nothing unsaved — `_save_container`'s `always`
## writers, whose change may be member bytes the dirty check cannot see.
func _take_disk_version(keep_ours: bool = false) -> void:
	var opened := ProjectContainer.open(container.path)
	if opened == null:
		_say("This drone's file changed outside Lothal and will not open yet.", true)
		return
	var copy := ""
	if keep_ours or container.has_unsaved_changes():
		copy = container.write_conflict_copy()
		if copy == "":
			# Our side could not be kept, so the file stays as it is and so does the Lab.
			push_warning("could not write a conflict copy beside %s" % container.path)
			return
	container = opened
	apply_project(opened.project)
	_refresh_status()
	_report_printed_divergence()
	_say(("Changed outside Lothal — reloaded. Your edits are kept in a copy, %s" % copy.get_file())
			if copy != "" else "Changed outside Lothal — reloaded.")


## The bar over the sim and Field while the Design Space is hidden behind them.
var _sim_identity: DsDrawer


var _away_layer: CanvasLayer




## "Fly it": the build being edited in the Design Space, flown. The sim reads the old Lab's rails,
## so the design's selection (and an edited frame) is pushed into the open project, fitted on the
## rails (`apply_project`, the path Open uses) and autosaved first; then the same `rooms.show_sim()`
## the old Sim button calls. The Design Space is only hidden, so Back finds it exactly as left.
func fly_it() -> bool:
	if design_space == null:
		fly_notice = "Cannot fly: no design is open"
		return false
	if container == null:
		fly_notice = "Cannot fly: no project is open to save the design into"
		return false
	if not _sync_design_to_lab():
		fly_notice = "Cannot fly: the design could not be handed to the simulator"
		return false
	var session := design_space.session
	# The session's own Build crosses the door, not just its ids: the sim flies exactly what the
	# Design Space read out, whatever the Lab rails could or could not hold. A selection that
	# cannot be built is refused here, with the parts named, rather than flown as something else.
	var build := session.build(rooms.catalog_for_lab())
	if build == null:
		fly_notice = "Cannot fly: this design does not build"
		if not last_sync_missing.is_empty():
			fly_notice += " (missing " + ", ".join(last_sync_missing.map(
				func(m: Dictionary) -> String: return "%s %s" % [m["category"], m["part_id"]])) + ")"
		return false
	fly_notice = ""
	_enter_away()
	rooms.show_sim(build, session.selection)
	return true


## Why the last `fly_it` refused, "" after a successful one.
var fly_notice := ""


## Fly it as the builder presses it: the button goes busy and the sim loads one frame later, so the
## busy state is painted before the (synchronous) load blocks the frame. Outside a tree there is no
## frame to wait for and the load runs at once. A refusal comes back as a toast on the Design Space.
func _on_fly_requested() -> void:
	if not begin_fly():
		return
	if is_inside_tree():
		await get_tree().process_frame
	finish_fly()


## First half of Fly it. False when one is already loading.
func begin_fly() -> bool:
	if design_space == null or design_space.file_bar.fly_busy:
		return false
	design_space.file_bar.set_fly_busy(true)
	return true


## Second half: do the flight, drop the busy state, and say why when it refused.
func finish_fly() -> bool:
	if design_space == null:
		return false
	var bar := design_space.file_bar
	var ok := fly_it()
	bar.set_fly_busy(false)
	if not ok:
		bar.toast.say(fly_notice if fly_notice != "" else "Cannot fly: no design is open", true)
	return ok


## "Field": the Field system of the old shell (courses, sites, weather and the SR3 world picker).
func open_field_from_design() -> bool:
	if design_space == null or not _sync_design_to_lab():
		return false
	_enter_away("field")
	rooms.show_lab()
	lab.visible = false
	_field.visible = true
	_field.build = lab.current_build()
	# From the Design Space the Field room is the WHOLE room, as drawers: the sites, courses,
	# gates, weather and worlds together.
	_field.set_dock_page("")
	_field.refresh()
	return true


var last_sync_missing: Array = []


func _sync_design_to_lab() -> bool:
	if design_space == null or container == null:
		return false
	var session := design_space.session
	var project := container.project
	project.parts = session.selection.duplicate(true)
	var edit := session.frame_edit(rooms.catalog_for_lab())
	if not edit.is_empty() and session.frame_document() != null:
		project.airframe = session.frame_document().to_dictionary()
	# Parts the Lab rails could not select are kept, not dropped: the sim flies the session's own
	# Build, so they do not stop the flight, but the builder is told which ones.
	last_sync_missing = apply_project(project)
	container.project.touch()
	container.write(container.path)
	return true


const AWAY_BAR_ROOM := 48.0


func _enter_away(room := "sim") -> void:
	if mission_picker != null:
		mission_picker.hide()
	away_room = room
	if _away_layer == null:
		_away_layer = CanvasLayer.new()
		_away_layer.name = "AwayLayer"
		_away_layer.layer = TOGGLE_LAYER + 6
		add_child(_away_layer)
		_away_layer.add_child(_build_sim_bar())
		_sim_identity = DsIdentity.sheet()
		_away_layer.add_child(_sim_identity)
	_set_design_space_shown(false)


func _build_sim_bar() -> Control:
	# A dark Design Space panel behind the row: the sim's sky is bright and the buttons' ink is quiet.
	# Placed right of centre, clear of the sim's own BUILD panel (S2 deletes it) and the lap HUD.
	var frame := PanelContainer.new()
	frame.name = "SimBar"
	var box := DsUi.panel_style()
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", box)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.offset_left = 60
	frame.offset_top = 8
	frame.grow_horizontal = Control.GROW_DIRECTION_END
	var bar := HBoxContainer.new()
	bar.name = "Row"
	bar.add_theme_constant_override("separation", 6)
	frame.add_child(bar)
	var back := DsUi.button("\u2039 Back")
	back.name = "Back"
	back.tooltip_text = "Back to the design (Esc)"
	back.pressed.connect(back_to_drone_from_room)
	bar.add_child(back)
	var id_chip := DsUi.button("")
	id_chip.name = "IdentityChip"
	id_chip.clip_text = true
	id_chip.custom_minimum_size = Vector2(200, 0)
	id_chip.pressed.connect(_toggle_sim_identity)
	if design_space != null:
		var info := design_space.identity()
		id_chip.text = String(info["chip"])
		id_chip.tooltip_text = String(info.get("text", ""))
	bar.add_child(id_chip)
	var mission := DsUi.button("Mission")
	mission.name = "Mission"
	mission.tooltip_text = "Pick a mission and an environment, then watch or run this design"
	mission.pressed.connect(open_mission_picker)
	bar.add_child(mission)
	var field := DsUi.button("Field")
	field.name = "Field"
	field.tooltip_text = "Open the Field room: courses, sites, weather and worlds"
	field.pressed.connect(open_field_from_design)
	bar.add_child(field)
	for child in bar.get_children():
		child.custom_minimum_size.y = 32
		# Over a bright sky the quiet rest ink is faint: full ink on the dark backing.
		(child as Button).add_theme_color_override("font_color", DsUi.INK)
	return frame


## The chip in the sim bar: opens "This build" (or closes it). Mission and this sheet share the left side, so one at a time.
func _toggle_sim_identity() -> void:
	if _sim_identity == null or design_space == null:
		return
	if _sim_identity.visible:
		_sim_identity.hide()
		return
	if mission_picker != null:
		mission_picker.hide()
	DsIdentity.fill(_sim_identity, design_space.identity())
	_sim_identity.show()


## Back from the sim or Field: the Design Space layer is shown again, untouched.
func back_to_drone_from_room() -> void:
	if design_space == null:
		return
	_field.visible = false
	_setup_layer.visible = false
	setup.leave()
	away_room = ""
	rooms.show_lab()
	lab.visible = false
	_close_away_bar()
	_set_design_space_shown(true)


func _close_away_bar() -> void:
	if _away_layer != null:
		remove_child(_away_layer)
		_away_layer.queue_free()
	_away_layer = null
	_sim_identity = null


func away_from_design() -> bool:
	return _away_layer != null


# ---------------------------------------------------------------------------
# Which screen is up: Projects, the class picker, or the Design Space
# ---------------------------------------------------------------------------

## Closes the current drone without opening another: the Projects screen is the state after Delete
## and after boot. Autosave has nothing to write (container is null).
func _clear_project() -> void:
	container = null
	_close_design_space()
	_close_class_picker()
	_field.visible = false
	_setup_layer.visible = false
	projects_screen.refresh()
	projects_screen.visible = true


## A project is on screen: the Projects screen goes, and an app that is the running scene lands on
## the drone's own Design Space (or the class picker for a drone with no class yet).
func _show_project() -> void:
	projects_screen.visible = false
	if not interactive or container == null:
		return
	if container.project.drone_class == "":
		show_class_picker()
	else:
		show_design_space()
