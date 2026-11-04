extends SceneTree
## Dev tool, not a test: photographs the motor designer pop-up over the real Design Space, the way
## a builder reaches it - GlassShell, New drone, pick a class, open the motor shelf, press
## "Design your own".
##
##   godot --script res://tests/capture_motor_designer.gd -- <out.png> [WxH] [state]
##
## state: "" (the default 2207) | "shelf" (no pop-up: the motor shelf with its tile) | "0802" |
## "3115" (largest size, two mounts) | "options" (2207, 2750 KV, 9N12P, N52H, 5 mm shaft, a name) |
## "saved" (the options motor, saved with the Save button) | "shelf_saved" (saved, the pop-up
## closed, the motor shelf scrolled to the saved card) | "sweep" | "soak" | "pickers" (punch-out on a 6S 5600 pack and a 7x4x3 prop), "punch" (the default
## 2207 with that bench run played out; "punch_hot" is a 2306 2100 KV whose punch-out warns of heat and current; "burnout" is the default 2207 on a 7x4x3 prop on a 6S 1300, whose winding burns out)
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://motor_designer.png"
	if args.size() > 1 and args[1] != "":
		var p := args[1].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var state: String = args[2] if args.size() > 2 else ""
	var shell := GlassShell.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var ds: DesignSpace = shell.design_space
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("motor")
	for i in 10:
		await process_frame
	ds.shelf.scroll.scroll_vertical = 100000
	for i in 10:
		await process_frame
	if state != "shelf":
		var tile := ds.shelf.find_child("AddMotor", true, false) as Button
		tile.pressed.emit()
		for i in 6:
			await process_frame
		var d: MotorDesigner = ds.motor_designer
		match state:
			"0802", "3115":
				d.set_stator(state)
			"sweep", "soak", "punch", "punch_hot", "sweep_warn", "pickers", "burnout":
				if state == "burnout":
					# The default 2207 on a 7 inch prop on 6S: the winding burns out mid punch-out.
					d.set_pack("battery_6s_1300")
					d.set_prop("prop_7x4x3")
					state = "punch"
				if state == "pickers":
					d.set_pack("battery_6s_5600")
					d.set_prop("prop_7x4x3")
					state = "punch"
				if state == "punch_hot":
					d.set_stator("2306")
					d.set_kv(2100.0)
				elif state == "sweep_warn":
					d.set_stator("0802")
				d.set_bench("punch" if state == "punch_hot" else ("sweep" if state == "sweep_warn" else state))
				# Let the three-second reveal finish, then a moment to settle.
				await create_timer(MotorDesigner.REVEAL_S + 0.8).timeout
			"options", "saved", "shelf_saved":
				d.set_kv(2750.0)
				d.set_poles(12)
				d.set_magnet("N52H")
				d.set_shaft(5.0)
				d.name_field.text = "Hill climber"
				d.set_motor_name("Hill climber")
				if state != "options":
					(d.find_child("Save", true, false) as Button).pressed.emit()
				if state == "shelf_saved":
					var saved_id := d.part_id
					d.close()
					for i in 10:
						await process_frame
					var row := ds.shelf.row_of(saved_id)
					ds.shelf.scroll.scroll_vertical = int(float(row.get("y", 0.0))) - 40 if not row.is_empty() else 0
		for i in 40:
			await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
