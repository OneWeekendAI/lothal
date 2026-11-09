class_name TestProjectsColumns
extends RefCounted
## The Projects table's right edge (src/ui/projects_screen.gd): the EDITED text and the row's "⋯"
## must never overlap. The columns were sized for "just now"; "2 weeks ago" ran under the "⋯".
##
## Laid out at the minimum window width (project.godot window/size/min_size) in a SubViewport,
## because a container has no size until a frame has been processed. Scratch library only; the
## builder's real `user://builds` is never touched.

const SCRATCH := "user://test_projects_columns"
const WINDOW := Vector2i(1024, 600)
const GAP := 8.0
const SETTLE_FRAMES := 4


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var saved_root := ProjectLibrary.root
	ProjectLibrary.root = SCRATCH
	ProjectLibrary.ensure_dir()

	var frame := SubViewport.new()
	frame.size = WINDOW
	tree.root.add_child(frame)
	var screen := ProjectsScreen.new(null)
	frame.add_child(screen)
	var now := int(Time.get_unix_time_from_system())
	# Longest strings the formatter makes: three-digit weeks, and the shorter real-data cases.
	var ages := [100 * 604800, 6 * 604800, 604800, 1]
	var names := ["A very long drone name that must give way to the other columns, not the reverse", "Short", "Mid", "x"]
	screen.entries = []
	for i in ages.size():
		screen.entries.append({"path": "%s/%d.lothal" % [SCRATCH, i], "name": names[i], "updated_unix": now - ages[i],
			"size": "5\"", "dry_g": 400.0, "auw_g": 600.0})
	screen._render()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	var font: Font = screen.theme.get_font("font", "ReadoutLabel")
	var size: int = screen.theme.get_font_size("font_size", "ReadoutLabel")
	var worst_gap := INF
	var detail := ""
	var rows := 0
	var all_text_fits := true
	for row in screen._rows.get_children():
		if not (row is Button) or not row.has_node("More"):
			continue
		rows += 1
		var label: Label = row.get_child(0).get_child(4)
		var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var text_rect := Rect2(label.get_global_rect().position, Vector2(text_w, label.size.y))
		if text_w > label.size.x + 0.5:
			all_text_fits = false
		var more_rect: Rect2 = row.get_node("More").get_global_rect()
		var gap := more_rect.position.x - text_rect.end.x
		if gap < worst_gap:
			worst_gap = gap
			detail = "'%s' text ends %.1f, more starts %.1f" % [label.text, text_rect.end.x, more_rect.position.x]
		if more_rect.size.x < 28.0 or more_rect.size.y < 28.0:
			worst_gap = -999.0
			detail = "hit area %s under 28px" % more_rect.size
	results.append(TestResult.new("EDITED text and the ⋯ keep a gap of at least 8px at 1024 wide",
		rows == ages.size() and worst_gap >= GAP, "rows=%d worst_gap=%.1f %s" % [rows, worst_gap, detail]))
	results.append(TestResult.new("the EDITED column is wide enough for its longest string",
		rows == ages.size() and all_text_fits, "rows=%d" % rows))

	# Columns stay aligned with the header labels, and NAME gives way (clipped), never the numbers.
	var aligned := true
	var head_cells: HBoxContainer = _header_cells(screen)
	if head_cells == null:
		aligned = false
	else:
		for row in screen._rows.get_children():
			if not (row is Button) or not row.has_node("More"):
				continue
			var cells: HBoxContainer = row.get_child(0)
			for i in range(1, 5):
				if absf(cells.get_child(i).get_global_rect().position.x - head_cells.get_child(i).get_global_rect().position.x) > 0.5:
					aligned = false
	results.append(TestResult.new("row columns line up with the header labels", aligned, ""))

	frame.queue_free()
	_rm(ProjectSettings.globalize_path(SCRATCH))
	ProjectLibrary.root = saved_root
	return results


static func _header_cells(node: Node) -> HBoxContainer:
	for c in node.get_children():
		if c is MarginContainer and c.get_child_count() == 1 and c.get_child(0) is HBoxContainer \
				and c.get_child(0).get_child_count() >= 5 and c.get_child(0).get_child(0) is Label \
				and (c.get_child(0).get_child(0) as Label).text == "NAME":
			return c.get_child(0)
		var found := _header_cells(c)
		if found != null:
			return found
	return null


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
