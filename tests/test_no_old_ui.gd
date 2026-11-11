class_name TestNoOldUi
extends RefCounted
## G1: nothing of the old glass-shell design is reachable.
##
## (a) SOURCE GREP. The retired look (glass_box, the ReadoutLabel / MutedLabel / TitleLabel family, any theme_type_variation,
## the BuildPanel and the Hud) must not appear in src/ at all. The shell chrome classes (GlassShell, Dock, RoomMenu, AppShell)
## are deleted by R9, which needs owner sign-off; until then they sit in PENDING_R9, and the test also asserts every
## PENDING_R9 entry still occurs (so deleting the code without trimming the list fails, and the list can only shrink).
## (b) RUNTIME WALK. Boot the real shell, go through every door, and walk every node with OldLook: no banned variation, no
## shadowed (glass) stylebox, and every Button has distinct hover / pressed / disabled boxes.

const BANNED_TOKENS := ["glass_box", "ReadoutLabel", "MutedLabel", "TitleLabel", "SmallLabel", "WarnLabel", "CompactButton",
	"theme_type_variation =", "BuildPanel", "class_name Hud"]
## Deleted by R9 (the swap). Allowed ONLY while R9 is open.
const PENDING_R9 := ["GlassShell", "class_name Dock", "RoomMenu", "AppShell"]
## Files that may use a banned token: none.
const ALLOW := {}


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var files := _gd_files("res://src")
	var texts := {}
	for f in files:
		texts[f] = FileAccess.get_file_as_string(f)
	for token in BANNED_TOKENS:
		var hits: Array[String] = []
		for f in files:
			if token in String(texts[f]) and not (ALLOW.has(token) and f in ALLOW[token]):
				hits.append(f.trim_prefix("res://src/"))
		results.append(TestResult.new("source: no '%s' anywhere in src/" % token, hits.is_empty(), "%d files: %s" % [hits.size(), ", ".join(hits.slice(0, 6))]))
	for token in PENDING_R9:
		var found := false
		for f in files:
			if token in String(texts[f]):
				found = true
				break
		results.append(TestResult.new("source: pending-R9 entry '%s' still exists (shrink the list when R9 deletes it)" % token, found, "stale allow-list entry"))

	var old := await _runtime(tree)
	for state in old:
		results.append(TestResult.new("runtime: no old look reachable at '%s'" % state, (old[state] as Array).is_empty(),
			"%d old: %s" % [(old[state] as Array).size(), ", ".join((old[state] as Array).slice(0, 6))]))
	results.append(TestResult.new("the detector can fail: a re-added old node is caught", _detector_fires(tree), "detector self-check"))
	return results


static func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out


static func _runtime(tree: SceneTree) -> Dictionary:
	var out := {}
	var shell := GlassShell.new()
	tree.root.add_child(shell)
	for i in 4:
		await tree.process_frame
	out["lab"] = OldLook.scan(shell)
	for i in GlassShell.SYSTEMS.size():
		shell._select_system(i)
		await tree.process_frame
		out["system " + str(GlassShell.SYSTEMS[i]["name"])] = OldLook.scan(shell)
	shell._select_system(-1)
	for room in ["bench", "esc_bench", "frame_bench", "studio"]:
		shell._open_room(room)
		for i in 3:
			await tree.process_frame
		out["room " + room] = OldLook.scan(shell)
	shell.show_class_picker()
	await tree.process_frame
	out["class picker"] = OldLook.scan(shell)
	shell._close_class_picker()
	if shell.container != null:
		var ds := shell.show_design_space()
		for i in 3:
			await tree.process_frame
		out["design space"] = OldLook.scan(shell)
		if ds != null:
			shell.open_mission_picker()
			await tree.process_frame
			out["mission picker"] = OldLook.scan(shell)
	shell.queue_free()
	await tree.process_frame

	var extras := {
		"projects screen": ProjectsScreen.new(),
		"project menu": ProjectMenu.new(),
		"update notice": UpdateNotice.new(LothalVersion.MANIFEST_URL),
		"new blade dialog": NewBladeDialog.new(),
		"custom motor dialog": CustomMotorDialog.new(),
		"custom esc dialog": CustomEscDialog.new(),
		"custom fc dialog": CustomFcDialog.new(),
		"custom frame dialog": CustomFrameDialog.new(),
		"custom propeller dialog": CustomPropellerDialog.new(),
		"custom component dialog": CustomComponentDialog.new("battery"),
	}
	for k in extras:
		var n: Node = extras[k]
		if n is Control:
			(n as Control).theme = LothalTheme.get_theme()
		tree.root.add_child(n)
		await tree.process_frame
		out[k] = OldLook.scan(n)
		n.queue_free()
		await tree.process_frame
	return out


static func _detector_fires(tree: SceneTree) -> bool:
	var holder := Control.new()
	holder.theme = LothalTheme.get_theme()
	var l := Label.new()
	l.theme_type_variation = &"MutedLabel"
	var p := PanelContainer.new()
	var sb := LothalTheme.plate()
	sb.shadow_size = 9
	p.add_theme_stylebox_override("panel", sb)
	var b := Button.new()
	var same := StyleBoxFlat.new()
	b.add_theme_stylebox_override("hover", same)
	b.add_theme_stylebox_override("pressed", same)
	holder.add_child(l)
	holder.add_child(p)
	holder.add_child(b)
	tree.root.add_child(holder)
	var found := OldLook.scan(holder)
	holder.free()
	return found.size() >= 3
