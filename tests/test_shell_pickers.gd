class_name TestShellPickers
extends RefCounted
## The Field room's Edit world and the Design Space's Mission button reach the live glass shell.
## Needs a shell whose _ready has run, so it runs beside the laid-out suites (run(tree)).
##
## Red proof (each wiring removed in src/ui/glass_shell.gd, suite run, restored):
## - edit_world_requested.connect commented out: the WorldEditor case FAILED (other three passed).
## - design_space.mission_requested.connect commented out: the picker, ResultsPanel and
##   no-duplicate cases all FAILED (picker null); the WorldEditor case passed.
## - open_mission_picker always building a new picker (reuse check removed): only the
##   no-duplicate case FAILED (pickers=2).

const SETTLE_FRAMES := 3
const WINDOW := Vector2i(1280, 720)


static func _shell(tree: SceneTree) -> GlassShell:
	var frame := SubViewport.new()
	frame.size = WINDOW
	tree.root.add_child(frame)
	var shell := GlassShell.new()
	frame.add_child(shell)
	return shell


static func _settle(tree: SceneTree) -> void:
	for i in SETTLE_FRAMES:
		await tree.process_frame


static func _mission_shell(tree: SceneTree) -> GlassShell:
	var shell := _shell(tree)
	await _settle(tree)
	shell.show_design_space()
	await _settle(tree)
	return shell


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var held := RealFiles.hold([AssemblyTweaks.SAVE_PATH])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AssemblyTweaks.SAVE_PATH))

	var shell := _shell(tree)
	await _settle(tree)
	results.append(_edit_world_opens_a_visible_editor(shell))
	shell.get_parent().queue_free()

	var s2 := await _mission_shell(tree)
	if s2.design_space != null:
		s2.design_space.file_bar.mission_button.pressed.emit()
	results.append(_mission_opens_a_visible_picker(s2))
	results.append(_results_panel_is_under_the_picker(s2))
	if s2.design_space != null:
		s2.design_space.file_bar.mission_button.pressed.emit()
	results.append(_second_press_does_not_duplicate(s2))
	s2.get_parent().queue_free()

	held.restore()
	return results


static func _edit_world_opens_a_visible_editor(shell: GlassShell) -> TestResult:
	var field := shell.field_room()
	var ids: Array[String] = field.worlds.ids() if field != null and field.worlds != null else []
	var id := ids[0] if not ids.is_empty() else ""
	if field != null:
		field.edit_world_requested.emit(id)
	var ed := shell.find_child("WorldEditor", true, false) as WorldEditor
	return TestResult.new("shell pickers: edit_world_requested opens a visible WorldEditor for that world",
		id != "" and ed != null and ed.is_visible_in_tree() and ed.get_meta("world_id", "") == id,
		"id=%s editor=%s" % [id, str(ed)])


static func _mission_opens_a_visible_picker(shell: GlassShell) -> TestResult:
	var p := shell.find_child("MissionPicker", true, false) as MissionPicker
	return TestResult.new("shell pickers: the Mission button opens a visible MissionPicker in the shell tree",
		p != null and p.is_visible_in_tree() and p.session != null, str(p))


static func _results_panel_is_under_the_picker(shell: GlassShell) -> TestResult:
	var p := shell.find_child("MissionPicker", true, false)
	var r: Node = p.find_child("*", true, false) if false else null
	if p != null:
		for c in p.find_children("*", "ResultsPanel", true, false):
			r = c
	return TestResult.new("shell pickers: the ResultsPanel is reachable under the MissionPicker",
		r != null, str(r))


static func _second_press_does_not_duplicate(shell: GlassShell) -> TestResult:
	var n := shell.find_children("*", "MissionPicker", true, false).size()
	return TestResult.new("shell pickers: pressing Mission twice leaves exactly one MissionPicker",
		n == 1, "pickers=%d" % n)
