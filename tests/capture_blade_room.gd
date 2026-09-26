extends SceneTree
## Dev tool, not a test: opens the Propulsion room on a chosen blade at a chosen RPM and writes a
## PNG. The companion to capture_frame_bench.gd and capture_bench.gd, and the answer to the one
## thing `test_blade_room.gd` says it cannot check — that the 3D view actually renders.
##
##   godot --script res://tests/capture_blade_room.gd -- <out.png> [prop_id] [rpm] [view]
##
## `view` is one of BladeView3D.VIEWS ("iso", "top", "front", "side"), defaulting to iso.
##
## Note: no --headless. This captures Godot's own framebuffer, and more pointedly a SubViewport has
## no World3D and renders nothing under the dummy driver, so a headless run writes a picture with
## the one new view in it blank — which is worse than failing.
##
## THE PAIR WORTH SHOOTING is the same blade at two speeds, where the planform does not move and
## everything under it does:
##
##   ... -- /tmp/blade_14k.png prop_5x43x3 14000
##   ... -- /tmp/blade_26k.png prop_5x43x3 26000

const DEFAULT_PROP := "prop_5x43x3"
const DEFAULT_RPM := 18000.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://blade_room.png"
	var prop_id: String = args[1] if args.size() > 1 else DEFAULT_PROP
	var rpm: float = float(args[2]) if args.size() > 2 else DEFAULT_RPM
	var view_id: String = args[3] if args.size() > 3 else BladeView3D.DEFAULT_VIEW

	DisplayServer.window_set_size(Vector2i(1280, 800))

	var backdrop := PanelContainer.new()
	backdrop.theme = LothalTheme.get_theme()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var room := PropulsionWorkbench.new()
	backdrop.add_child(room)
	room.open_preset(prop_id)
	room.blade_view.snap_to(view_id)

	# Through the room's own handler rather than by assigning `design_rpm`: the handler is what the
	# slider calls, so a capture that set the field directly could produce a picture no builder can
	# reach by moving the control.
	room._on_rpm_changed(rpm)

	var verdict := BladeAero.analyse(room.document, rpm)
	if verdict["refused"]:
		print("%s at %.0f RPM: the model declines this rotor" % [prop_id, rpm])
	else:
		print("%s at %.0f RPM — %.1f g/W, %.0f g thrust, FM %.2f, lift-capped to %.2f R" % [
			room.document.name, rpm, verdict["grams_per_watt"],
			verdict["thrust_n"] / BladeAero.NEWTON_PER_GRAM_F,
			verdict["figure_of_merit"], verdict["capped_to_r_frac"]])

	# Three frames, not two: the panel's polylines need a laid-out size before they draw, and the
	# SubViewport is set to UPDATE_ONCE, so it renders on the frame after the one that placed it.
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
