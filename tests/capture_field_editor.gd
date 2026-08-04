extends SceneTree
## Dev tool, not a test: boots the real app shell, lays out a course in the field editor with the
## editor's own API, and writes a PNG — of the editor with that course under construction, or of
## the same course being flown in Sim. The companion to capture_lab.gd and the four bench captures.
##
##   godot --script res://tests/capture_field_editor.gd -- <out.png> [edit|fly] [frame_id]
##
## Note: no --headless. This captures Godot's own framebuffer, which the dummy driver does not
## have, so a headless run HANGS silently rather than failing.
##
## THE PAIR WORTH SHOOTING is the two modes on the same course, which is the whole argument of the
## slice in two frames — the world was built in one room and flown in the other:
##
##   ... -- /tmp/field_editor.png edit
##   ... -- /tmp/field_flown.png  fly
##
## It writes to a SCRATCH course file rather than to user://courses.json. A dev tool that quietly
## added a course to the courses of whoever ran it would be the screenshot equivalent of the
## frame bench draining the reference pack every time you looked at a frame.
const SCRATCH_LIBRARY := "user://capture_field_editor_courses.json"

## A course that is visibly not the default circuit: six gates, an S through two heights, rings
## from 1.0 m to 2.2 m, and a hairpin at the far end. A capture of a slightly different circle
## would prove nothing — the same picture would come out of an implementation that had merely made
## COURSE_RADIUS_M a variable.
const LAYOUT := [
	{"x": 0.0, "z": 0.0, "height": 2.5, "radius": 1.6},
	{"x": 16.0, "z": -14.0, "height": 4.5, "radius": 1.2},
	{"x": 34.0, "z": -6.0, "height": 2.2, "radius": 2.2},
	{"x": 40.0, "z": 16.0, "height": 6.0, "radius": 1.0},
	{"x": 20.0, "z": 26.0, "height": 3.2, "radius": 1.8},
	{"x": -2.0, "z": 20.0, "height": 5.0, "radius": 1.4},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://field_editor.png"
	var mode: String = args[1] if args.size() > 1 else "edit"
	var frame_id: String = args[2] if args.size() > 2 else ""

	if mode != "edit" and mode != "fly":
		print("no such mode: %s (want edit or fly)" % mode)
		quit(1)
		return

	if FileAccess.file_exists(SCRATCH_LIBRARY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_LIBRARY))

	var shell: AppShell = load("res://src/scenes/root.tscn").instantiate()
	# The shell's library is the one that crosses the door into Sim, so the course has to be built
	# into THIS instance rather than into one loaded from the scratch file afterwards.
	shell.course_library = CourseLibrary.load_from(SCRATCH_LIBRARY)
	root.add_child(shell)

	if frame_id != "" and not shell.lab.picker.select_id(frame_id):
		print("no such frame in the visible list: %s" % frame_id)
		quit(1)
		return

	shell.show_field_editor()
	var editor: FieldEditorScreen = shell.field_editor
	# Before any edit, so nothing is ever written to the real courses file.
	editor.save_path = SCRATCH_LIBRARY

	editor.new_course("Capture")
	_lay_out(editor)

	# Left mid-edit on purpose: one gate selected and lit, its height and ring on the sliders. The
	# picture is meant to be a course under construction, not a finished one being admired.
	editor.select_gate(3)

	var course: GateCourse = editor.course()
	print("%s: %d gates, %s" % [course.course_name, course.gates.size(), course.fingerprint()])
	for warning in editor.warnings():
		print("  [%s] %s" % [BuildWarning.severity_name(warning.severity), warning.message])

	if mode == "fly":
		shell.show_sim()
		var sim: Node = shell.sim
		print("  flying \"%s\": start %v, gate 1 of %d" % [
			sim.course.course_name, sim.course.start_position(), sim.course.gate_count()])
		# The flight scene builds its airframe, its HUD and its course rings in _ready, and the
		# camera is only snapped onto the start line once the build has landed — so this needs real
		# processed frames rather than one.
		for i in 8:
			await process_frame

	# Two frames, because the panels only queue a redraw — the first processes the layout and the
	# second is the one that has the sliders and the warnings in it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()


## Builds LAYOUT through the editor's own API rather than by assembling gates and handing them over,
## so what is photographed is what the buttons and sliders actually do.
func _lay_out(editor: FieldEditorScreen) -> void:
	while editor.course().gates.size() > LAYOUT.size():
		editor.select_gate(editor.course().gates.size() - 1)
		editor.remove_gate()
	while editor.course().gates.size() < LAYOUT.size():
		editor.select_gate(editor.course().gates.size() - 1)
		editor.add_gate()

	for i in LAYOUT.size():
		var row: Dictionary = LAYOUT[i]
		editor.select_gate(i)
		editor.set_gate_ground_position(Vector3(float(row["x"]), 0.0, float(row["z"])))
		editor.set_gate_height_m(float(row["height"]))
		editor.set_gate_radius_m(float(row["radius"]))

	# Headings last, and derived from where the gates ended up: a gate faces the way the route runs
	# through it, which is only knowable once every gate has been placed.
	for i in LAYOUT.size():
		var gates := editor.course().gates
		var here: Vector3 = gates[i]["position"]
		var next: Vector3 = gates[(i + 1) % gates.size()]["position"]
		var along := next - here
		editor.select_gate(i)
		editor.set_gate_heading_deg(rad_to_deg(atan2(along.x, -along.z)))
