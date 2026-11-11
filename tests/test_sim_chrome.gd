class_name TestSimChrome
## S1 (UI_REDESIGN_TRACKER): with the sim on screen the ONLY chrome is one Design Space top bar
## (Back, identity chip, Mission, Field). No Lab/Sim/Rooms dock, no old away bar.

static func run() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_simchrome_%d" % OS.get_process_id()
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	var flew := shell.fly_it()
	results.append(TestResult.new("fly_it enters the sim", flew and shell.rooms.sim != null, shell.fly_notice))

	var all: Array = []
	_walk(shell, all)
	var banned: Array = []
	var bars: Array = []
	var buttons: Dictionary = {}
	for n in all:
		if (n is Dock or n is RoomMenu) and _shown(n):
			banned.append("%s(%s)" % [n.name, n.get_class()])
		if n is Button:
			var b := n as Button
			if b.name == "BackToDrone" or b.text == "Back to the drone":
				banned.append("button " + b.name)
			if b.name in ["Lab", "Sim", "Rooms", "ModePanel"]:
				banned.append("toggle " + b.name)
		if n.name in ["Lab", "Sim", "Rooms", "ModePanel"] and n is Control and _shown(n):
			banned.append("node " + n.name)
		if n.name == "SimBar":
			bars.append(n)
	results.append(TestResult.new("sim: no Dock, RoomMenu, away button or Lab/Sim toggle on screen",
		banned.is_empty(), str(banned)))
	results.append(TestResult.new("sim: there is no old Lab/Sim toggle node on the shell",
		shell.get("_sim_button") == null and shell.get("_lab_button") == null and shell.get("_room_menu") == null, ""))
	results.append(TestResult.new("sim: exactly one top bar", bars.size() == 1, str(bars.size())))
	if bars.size() != 1:
		return _finish(shell, results)
	var bar: Node = bars[0]
	var layer := bar.get_parent() as CanvasLayer  # SimBar is the layer's own child
	results.append(TestResult.new("the sim bar rides a CanvasLayer above the sim's HUD",
		layer != null and layer.layer > 1, str(layer)))
	var inner: Array = []
	_walk(bar, inner)
	for n in inner:
		if n is Button:
			buttons[String(n.name)] = n
	for want in ["Back", "IdentityChip", "Mission", "Field"]:
		results.append(TestResult.new("sim bar has %s" % want, buttons.has(want), str(buttons.keys())))
	results.append(TestResult.new("sim bar has only those four buttons", buttons.size() == 4, str(buttons.keys())))
	for k in buttons:
		var b: Button = buttons[k]
		var sigs := {}
		for st in ["normal", "hover", "pressed"]:
			sigs[st] = _sig(b.get_theme_stylebox(st))
		results.append(TestResult.new("%s: normal/hover/pressed differ" % k,
			sigs["normal"] != sigs["hover"] and sigs["hover"] != sigs["pressed"] and sigs["normal"] != sigs["pressed"], str(sigs)))
	if buttons.has("IdentityChip"):
		var info := shell.design_space.identity()
		results.append(TestResult.new("chip text equals the identity chip",
			(buttons["IdentityChip"] as Button).text == String(info["chip"]) and String(info["chip"]) != "",
			(buttons["IdentityChip"] as Button).text))
		results.append(TestResult.new("chip tooltip is the identity text",
			(buttons["IdentityChip"] as Button).tooltip_text == String(info["text"]), ""))
		var chip := buttons["IdentityChip"] as Button
		var ink: Color = chip.get_theme_color("font_color")
		results.append(TestResult.new("sim bar ink is full ink, readable over a bright sky",
			ink.v >= DsUi.INK.v - 0.01, str(ink)))
		chip.pressed.emit()
		var sheet = shell.get("_sim_identity")
		var words := ""
		if sheet != null:
			for n in (sheet as DsDrawer).content.get_children():
				if n is Label:
					words += (n as Label).text + "|"
		results.append(TestResult.new("chip opens the This build sheet in the sim",
			sheet != null and (sheet as DsDrawer).visible and words.contains(String(info["class_name"])), words))
		chip.pressed.emit()
		results.append(TestResult.new("chip again closes the sheet", sheet != null and not (sheet as DsDrawer).visible, ""))
	if buttons.has("Mission"):
		(buttons["Mission"] as Button).pressed.emit()
		results.append(TestResult.new("Mission opens the picker",
			shell.mission_picker != null and shell.mission_picker.visible, ""))
		shell.mission_picker.hide()
	if buttons.has("Back"):
		(buttons["Back"] as Button).pressed.emit()
		results.append(TestResult.new("Back returns to the design",
			not shell.away_from_design() and shell.design_space != null and shell._design_space_layer.visible
			and shell.rooms.sim == null, ""))
		var left: Array = []
		_walk(shell, left)
		var still := false
		for n in left:
			if n.name == "SimBar":
				still = true
		results.append(TestResult.new("Back takes the sim bar away", not still, ""))
	# Field, from a fresh flight.
	if shell.fly_it():
		var again: Array = []
		_walk(shell, again)
		for n in again:
			if n is Button and n.name == "Field" and n.get_parent() != null and _in_bar(n):
				(n as Button).pressed.emit()
		results.append(TestResult.new("Field opens the field room",
			shell._field != null and shell._field.visible, ""))
	return _finish(shell, results)


static func _in_bar(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p.name == "SimBar":
			return true
		p = p.get_parent()
	return false


static func _finish(shell: GlassShell, results: Array) -> Array:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results


static func _walk(node: Node, into: Array) -> void:
	for c in node.get_children():
		into.append(c)
		_walk(c, into)


## Visible in the tree-less sense: the node and every CanvasItem ancestor up to the shell is shown.
static func _shown(n: Node) -> bool:
	var p := n
	while p != null:
		if p is CanvasItem and not (p as CanvasItem).visible:
			return false
		p = p.get_parent()
	return true


static func _sig(sb: StyleBox) -> String:
	var f := sb as StyleBoxFlat
	if f == null:
		return "none"
	return "%s|%s|%d" % [f.bg_color, f.border_color, int(f.content_margin_top)]
