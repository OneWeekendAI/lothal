class_name TestFlyFeedback
## B3 (UI_REDESIGN_TRACKER): Fly it shows something. The button is busy while the sim loads, and a
## refusal says why in a Design Space toast instead of returning false silently.

static func _open() -> GlassShell:
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	return shell


static func _done(shell: GlassShell) -> void:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()


static func run() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_flyfb_%d" % OS.get_process_id()
	var shell := _open()
	var bar := shell.design_space.file_bar
	results.append(TestResult.new("idle: Fly it is enabled and says Fly it",
		not bar.fly_busy and not bar.fly_button.disabled and bar.fly_button.text == "Fly it", bar.fly_button.text))
	results.append(TestResult.new("begin: the button is busy, disabled and says Loading, and no sim yet",
		shell.begin_fly() and bar.fly_busy and bar.fly_button.disabled and bar.fly_button.text == "Loading..."
		and shell.rooms.sim == null, bar.fly_button.text))
	results.append(TestResult.new("a second press while loading is ignored", not shell.begin_fly(), ""))
	var ok := shell.finish_fly()
	results.append(TestResult.new("finish: the sim is up and the button is restored",
		ok and shell.rooms.sim != null and not bar.fly_busy and not bar.fly_button.disabled
		and bar.fly_button.text == "Fly it", bar.fly_button.text))
	shell.back_to_drone_from_room()

	# A design that cannot be built is refused with the part named, on screen.
	shell.design_space.session.selection["camera"] = "ghost_camera_9000"
	shell.begin_fly()
	ok = shell.finish_fly()
	results.append(TestResult.new("an unbuildable design: refused, toast names the part, button restored",
		not ok and bar.toast.visible and "ghost_camera_9000" in bar.toast.message and not bar.fly_busy
		and shell.rooms.sim == null, bar.toast.message))
	bar.toast.clear()
	shell.design_space.session.selection["camera"] = ""

	# No project to save into: refused with a reason, not silently.
	var saved := shell.container
	shell.container = null
	shell.begin_fly()
	ok = shell.finish_fly()
	results.append(TestResult.new("no project open: refused with a toast reason",
		not ok and bar.toast.visible and bar.toast.message.begins_with("Cannot fly"), bar.toast.message))
	shell.container = saved
	_done(shell)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results
