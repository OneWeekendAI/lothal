extends SceneTree
## Dev tool, not a test: photographs GlassShell — the new UI frame — so the arrangement can be
## looked at rather than reasoned about. The companion to capture_lab.gd, which shoots the old one.
##
##   godot --script res://tests/capture_glass_shell.gd -- <out.png> [settle] [system] [WxH] [menu|sim|3d|overlay|finder|collapsed|page:<row id>]
##
## `collapsed` folds the right-hand list to its strip; `page:<row id>` opens that row's page in the
## stage (e.g. `page:frame`, `page:motors`, `page:battery`) — lab dock design §5.5's drilled-in shot;
## `page:guards@<guard id>` fits that guard first; `page:printed:<part>@diverged` prints every
## part, loosens the clearance and checks again, so the Printed rows show a real divergence.
##
## A fifth argument of `menu` drops the project menu open before the shot, which is the only way
## to photograph an entry that is greyed — and greyed entries are most of that menu today. `sim`
## flies out to the field through the toggle instead, which is the shot that shows the chrome
## retracted — §5's "the same window with the chrome retracted" is a claim about a picture.
##
## A fifth argument of `3d` flips the Airframe room to its 3D view, which is the shot that shows the
## frame you drew as the stack it is. Only meaningful together with `Airframe` as the system.
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
	var to_3d: bool = args.size() > 4 and args[4] == "3d"
	var overlay: bool = args.size() > 4 and args[4] == "overlay"
	# QC5: the summoned finder, which is the control the whole slice is about and the one thing on
	# this screen that cannot be photographed without being opened first.
	var to_finder: bool = args.size() > 4 and args[4] == "finder"
	var collapsed: bool = args.size() > 4 and args[4] == "collapsed"
	var page_row: String = args[4].trim_prefix("page:") if args.size() > 4 \
		and args[4].begins_with("page:") else ""

	if args.size() > 3 and args[3] != "":
		var res_parts := args[3].split("x")
		if res_parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(res_parts[0]), int(res_parts[1])))
			root.size = Vector2i(int(res_parts[0]), int(res_parts[1]))

	var shell := GlassShell.new()
	root.add_child(shell)

	# THE TRAY GOES UP BEFORE THE SYSTEM IS CHOSEN, and the order is the whole point of this shot.
	#
	# Turning it on afterwards photographs the toggle, which was never the defect: the defect was a
	# tray that was already up being carried into a room it is not about. `_select_system` hid the
	# tool cluster for Airframe and left the five charts floating over the frame editor with their
	# own dismiss button off-screen. A capture that switched the overlay on last could not have seen
	# it, and did not.
	if overlay:
		shell.set_thrust_overlay_visible(true)
		for i in 4:
			await process_frame

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

	# The finder, summoned the way a builder summons it — through the dock's own signal, which is
	# what a click on a system icon emits. Calling `open_finder` here would photograph a code path
	# nobody takes.
	# The finder, summoned the way a builder summons it now — from the first row whose choice line
	# picks a part (lab dock design §2).
	if to_finder:
		for row in shell.section_list().rows():
			if row.has("pick"):
				shell.pick_from_row(row["id"])
				break
		for i in 6:
			await process_frame

	# Folded without saving: a screenshot must not change how the developer's own drone opens.
	if collapsed:
		shell.section_list().set_collapsed(true)
		shell._fit_columns()
		for i in 6:
			await process_frame

	# `page:guards@<guard id>` fits that guard first, through the Prop panel's own selector handler
	# (not saved: the scratch HOME the captures run under holds the project).
	# `page:printed:<part>@diverged` prints every part (into the scratch HOME), loosens the fit
	# clearance to 0.35 mm, and checks again — a real divergence on every printed row.
	if page_row.ends_with("@diverged"):
		page_row = page_row.trim_suffix("@diverged")
		shell.open_folder_after_export = false
		shell.export_printed_parts()
		shell.lab.print_panel.clearance_edited.emit(0.35)
		await process_frame
		shell._report_printed_divergence()
	if page_row.contains("@"):
		var guard_id := page_row.get_slice("@", 1)
		page_row = page_row.get_slice("@", 0)
		var details := shell.lab.propeller_details
		var index := details._guard_ids.find(guard_id)
		if index >= 0:
			details._guard_selector.select(index)
			details._on_guard_selected(index)
	if page_row != "":
		if not shell.open_row(StringName(page_row)):
			print("no such row: %s" % page_row)
		for i in settle:
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

	# The Airframe room's other view. Driven through the same toggle a click drives, and it only
	# means anything with `system` set to Airframe — the room is the only thing that has a 3D view
	# of the frame being DRAWN rather than of the frame that is fitted.
	if to_3d and shell.workbench() != null:
		shell.workbench().set_view_3d(true)
		for i in settle:
			await process_frame

	# The analysis tray (P10e). Switched on above, before the system, so the shot answers "what
	# happens to a tray that is already up" rather than "does the toggle work". Its geometry is
	# proven headless in tests/test_overlay_tray.gd; whether the cards are legible over a turning
	# airframe, and whether they are correctly ABSENT over a room, is what a picture is for.

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()
