class_name TestOneDoor
## B1 (UI_REDESIGN_TRACKER): there is ONE door to the sim and the sim flies the Design Space's own
## Build. Every entry (Fly it, the old Sim toggle) syncs first and hands over `session.build()`.

static func run() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_onedoor_%d" % OS.get_process_id()
	for id in DroneClass.ids():
		results.append_array(_one_class(id))
	results.append_array(_missing_is_surfaced())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results


static func _open(id: String) -> GlassShell:
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class(id)
	shell.class_picker.choose()
	return shell


static func _done(shell: GlassShell) -> void:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()


static func _one_class(id: String) -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var shell := _open(id)
	var ds := shell.design_space
	var session := ds.session
	# Edits only the Design Space holds: a different battery, no camera, a thicker top plate.
	for opt in catalog.list_category("battery"):
		var bid := String(opt["part_id"])
		if bid != String(session.selection["battery"]) and ds.session.swap(catalog, "battery", bid)["ok"]:
			break
	session.remove("camera")
	if session.frame_editable():
		session.set_plate_thickness(session.plate_of_mesh("frame_plate_top"), 2.5)
	var want := session.build(catalog)
	# Through the OLD Sim toggle, the entry that used to skip the sync.
	shell._sim_button.pressed.emit()
	var sim = shell.rooms.sim
	# The object handed across the door (the shell is not in a tree here, so Sim's _ready has not
	# run; the windowed capture tests/capture_sim_door.gd prints `sim.build` itself).
	var got: Build = sim.initial_build if sim != null else null
	results.append(TestResult.new("%s: the old Sim toggle enters the sim" % id, sim != null and want != null, str(sim)))
	if sim == null or want == null:
		_done(shell)
		return results
	results.append(TestResult.new("%s: the sim flies the Design Space build (parts, AUW)" % id,
		got != null and got.fingerprint() == want.fingerprint()
		and is_equal_approx(got.all_up_weight_g(), want.all_up_weight_g()),
		"%s %.2f vs %s %.2f" % [got.fingerprint() if got != null else "-", got.all_up_weight_g() if got != null else -1.0,
			want.fingerprint(), want.all_up_weight_g()]))
	results.append(TestResult.new("%s: and the rails were synced (project holds the design's parts)" % id,
		String(shell.container.project.parts["battery"]) == String(session.selection["battery"]),
		"%s" % shell.container.project.parts.get("battery")))
	results.append(TestResult.new("%s: the Lab/Sim/Rooms dock is hidden while away" % id,
		not shell._dock.visible and shell.away_from_design(), str(shell._dock.visible)))
	shell.back_to_drone_from_room()
	results.append(TestResult.new("%s: back restores the dock" % id, shell._dock.visible, ""))
	_done(shell)
	return results


static func _missing_is_surfaced() -> Array:
	var results: Array = []
	var shell := _open("five_inch")
	var ds := shell.design_space
	ds.session.selection["camera"] = "ghost_camera_9000"
	var flew := shell.fly_it()
	results.append(TestResult.new("a part the rails cannot select refuses the flight, naming it",
		not flew and shell.rooms.sim == null and "ghost_camera_9000" in shell.fly_notice
		and not shell.last_sync_missing.is_empty(), shell.fly_notice))
	_done(shell)
	return results

