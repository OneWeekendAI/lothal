extends SceneTree
## Dev tool, not a test: photographs GlassShell — the new UI frame — so the arrangement can be
## looked at rather than reasoned about. The companion to capture_lab.gd, which shoots the old one.
##
##   godot --script res://tests/capture_glass_shell.gd -- <out.png> [settle] [system] [WxH] [menu|sim]
##
## A fifth argument of `menu` drops the project menu open before the shot, which is the only way
## to photograph an entry that is greyed — and greyed entries are most of that menu today. `sim`
## flies out to the field through the toggle instead, which is the shot that shows the chrome
## retracted — §5's "the same window with the chrome retracted" is a claim about a picture.
##
## `system` names one of GlassShell.SYSTEMS ("Propulsion", "Power", …) and selects it before the
## shot, which is how the dimming gets photographed. Dimming is the claim §5 makes to justify a
## full-bleed viewport at all, so it is the one behaviour here worth a picture.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://glass_shell.png"
	var settle: int = int(args[1]) if args.size() > 1 else 30
	var system: String = args[2] if args.size() > 2 else ""

	var menu: bool = args.size() > 4 and args[4] == "menu"
	var to_sim: bool = args.size() > 4 and args[4] == "sim"

	if args.size() > 3 and args[3] != "":
		var res_parts := args[3].split("x")
		if res_parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(res_parts[0]), int(res_parts[1])))
			root.size = Vector2i(int(res_parts[0]), int(res_parts[1]))

	var shell := GlassShell.new()
	root.add_child(shell)

	if system != "" and not shell.select_system_by_name(system):
		print("no such system: %s" % system)
		quit(1)
		return

	for i in settle:
		await process_frame

	# The idle orbit is still turning during the settle frames, and a shot of the frame should be
	# of the frame — a different airframe angle in every screenshot makes two shots of the same
	# layout look like two layouts.
	shell.lab.auto_orbit = false
	shell.lab.set_orbit(deg_to_rad(28.0), deg_to_rad(18.0))
	for i in 2:
		await process_frame

	# The drone menu, if asked for. It is a Window, so it only lands in this shot because Godot
	# embeds subwindows by default — worth knowing before anybody wonders why the menu is missing
	# from a screenshot taken with embedding turned off.
	if menu:
		shell.chip.open_menu()
		for i in 4:
			await process_frame

	# Out to the field, through the same toggle a click drives — not a private path beside it, for
	# the reason `select_system_by_name` exists: a screenshot of a route nobody takes is a
	# screenshot of nothing.
	if to_sim:
		shell.rooms.show_sim()
		for i in settle:
			await process_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
