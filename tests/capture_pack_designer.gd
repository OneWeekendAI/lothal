extends SceneTree
## Dev tool, not a test: photographs the pack designer pop-up over the real Design Space, the way a
## builder reaches it - DesignApp, New drone, pick a class, open the battery shelf, press "+".
##
##   godot --script res://tests/capture_pack_designer.gd -- <out.png> [WxH] [state]
##
## state: "" (the default pack, discharge tab) | "recharge" | "custom" | "preset" | "shelf" (no pop-up,
## the shelf with its "+" tile) | "mypacks" | "6s2p" | "8s" (an 8S2P pack) | "lead" (a 22 AWG pigtail on
## a drone that pulls more than it carries) | "fit" (an oversize designed pack fitted in the Design Space)
## | "drain" (a Discharge run on a saved pack) | "cellchips" (the shelf top: CELLS chips)
##
## Needs a real window; run with HOME pointed at a scratch directory (New drone writes a project).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://pack_designer.png"
	if args.size() > 1 and args[1] != "":
		var p := args[1].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var state: String = args[2] if args.size() > 2 else ""
	var shell := DesignApp.new()
	root.add_child(shell)
	for i in 4:
		await process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	for i in 20:
		await process_frame
	var ds: DesignSpace = shell.design_space
	if state.begins_with("chip"):
		# Main screen with the battery's charge chip: chip_62 | chip_mid | chip_full
		var id := ds.selected_battery()
		var mah := float(ds._catalog.get_part(id)["specs"]["mah"])
		var cp := PackCharge.load_from(ds.pack_charge_path)
		cp.set_used_mah(id, mah * 0.38)
		cp.save(ds.pack_charge_path)
		ds.refresh_charge_chip()
		if state == "chip_mid":
			ds.charge_chip.plug.pressed.emit()
			ds.charge_chip.set_process(false)
			ds.charge_chip.step(1.3)
		elif state == "chip_full":
			ds.charge_chip.plug.pressed.emit()
			ds.charge_chip.step(4.0)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png(out_path)
		print("saved %s" % ProjectSettings.globalize_path(out_path))
		quit()
		return
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	for i in 10:
		await process_frame
	if state == "cellchips":
		# The battery list scrolled to its top: the CELLS chips, with 7S and 8S.
		ds.shelf.scroll.scroll_vertical = 0
		for i in 10:
			await process_frame
	elif state == "shelf":
		# Scroll the battery list to its end so the tile shows.
		ds.shelf.scroll.scroll_vertical = 100000
		for i in 10:
			await process_frame
	else:
		ds.shelf.scroll.scroll_vertical = 100000
		var tile := ds.shelf.find_child("AddPack", true, false) as Button
		tile.pressed.emit()
		for i in 6:
			await process_frame
		var d: PackDesigner = ds.pack_designer
		match state:
			"recharge":
				d.set_series(6)
				d.set_parallel(2)
				d.set_tab("recharge")
			"8s":
				d.set_series(8)
				d.set_parallel(2)
			"lead":
				d.set_wiring("XT60", 22, 100.0)
			"fit", "fit_issue":
				d.set_cell("cell_molicel_p42a")
				d.set_series(6)
				d.set_parallel(4)
				d.name_field.text = "Big 6S4P"
				var big := d.save()
				d.close()
				for i in 6:
					await process_frame
				ds.shelf.set_open(false)
				ds.choose("battery", big)
				for i in 30:
					await process_frame
				root.get_texture().get_image().save_png(out_path)
				print("saved %s" % ProjectSettings.globalize_path(out_path))
				quit()
				return
			"drain":
				d.name_field.text = "Drained"
				d.save()
				d.run_discharge_test()
			"4s2p":
				d.set_parallel(2)
			"6s2p":
				d.set_series(6)
				d.set_parallel(2)
			"custom":
				d.set_cell("custom_cell")
			"preset":
				d.open_pack("battery_4s_1300")
			"mypacks":
				d.save()
				d.my_packs_button.pressed.emit()
			"drone":
				d.set_discharge_mode("this_drone")
			"motor":
				# A big shelf motor loads the pack instead of the drone's own.
				d.set_motor("motor_2807_1300kv")
		# Let the ~3 s reveal finish so the charts are in their static final state.
		for i in 220:
			await process_frame
	root.get_texture().get_image().save_png(out_path)
	print("saved %s" % ProjectSettings.globalize_path(out_path))
	quit()
