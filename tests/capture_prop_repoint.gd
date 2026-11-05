extends SceneTree
## Dev tool, not a test: the Lab's prop doors in a real window (PD14), with a real Escape and a real fit.
##
##   godot --path . --script res://tests/capture_prop_repoint.gd -- <out_prefix> [WxH]
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

var prefix: String


func _shot(tag: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, tag])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	prefix = args[0]
	if args.size() > 1:
		var p := args[1].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	shell._close_design_space()
	shell._select_system(1)
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == "Propulsion":
			shell._select_system(i)
	await _shot("lab")
	print("DOOR label ", shell._room_door.text if shell._room_door != null else "?")
	shell._on_room_door_pressed()
	await _shot("door")
	print("DOOR designer ", shell.prop_designer != null, " room ", shell.blade_room().visible, " page ", shell.page_open())
	var focused := shell._focused_index
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _shot("after_esc")
	print("ESC designer ", shell.prop_designer != null, " focus kept ", shell._focused_index == focused)
	var shown := shell.lab.catalog.get_part("prop_7x35x2")
	shell.lab.propeller_details.render(shown, shell.lab.current_build())
	shell.lab.propeller_details.design_blade_requested.emit(shown)
	await _shot("inspector_7in")
	var d := shell.prop_designer
	print("INSPECTOR source ", d.source_name, " session ", d.session != null)
	d.close()
	shell._on_room_door_pressed()
	d = shell.prop_designer
	d.set_prop_name("PD14 from Lab")
	print("FIT ", d.fit_to_drone(), " status: ", shell.lab.propeller_picker.selected_part().get("part_id", ""))
	await _shot("fitted")
	d.close()
	shell._show_page(SectionRows.rows("Propulsion", shell.lab.current_build())[1])
	await _shot("lab_after_fit")
	print("LAB fits ", shell.lab.selection()["propeller"], " project ", shell.container.project.parts["propeller"])
	shell.lab.propeller_picker.new_prop_requested.emit()
	await _shot("new")
	print("NEW name ", shell.prop_designer.doc.name)
	quit(0)
