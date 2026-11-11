class_name TestFieldDs
extends RefCounted
## R1: the Field room speaks the Design Space language. Walks the room's whole scene tree (every node, shown or not, in the
## whole-room layout and on a dock page, with a warning row up) and fails on any node that still wears the old glass-shell
## look: a ReadoutLabel / MutedLabel / TitleLabel type variation, or a stylebox built by LothalTheme.glass_box (a shadowed
## StyleBoxFlat, whether set as an override or inherited from the theme).

const OLD_VARIATIONS := [&"ReadoutLabel", &"MutedLabel", &"TitleLabel"]
const STYLEBOX_NAMES := ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus", "read_only",
	"fill", "background", "slider", "grabber_area", "grabber_area_highlight", "scroll", "scroll_focus", "grabber",
	"grabber_highlight", "grabber_pressed", "cursor", "cursor_unfocused", "selected", "selected_focus", "hovered"]
const PATH := "user://test_field_ds_courses.json"


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	for path in [PATH, SiteLibrary.path_beside(PATH), ConditionsLibrary.path_beside(PATH)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var room := FieldSystem.new(SiteLibrary.load_from(SiteLibrary.path_beside(PATH)), CourseLibrary.load_from(PATH),
		ConditionsLibrary.load_from(ConditionsLibrary.path_beside(PATH)), ReferenceBuild.build(), PATH)
	room.theme = LothalTheme.get_theme()
	tree.root.add_child(room)
	await tree.process_frame
	room.refresh()

	for page in ["", "site", "course", "conditions"]:
		room.set_dock_page(page)
		if page != "":
			# One warning row, so the dynamically built Why? text exists too.
			var w := BuildWarning.new(BuildWarning.Severity.LIMITING, &"test_warning", "A long reason.")
			room.show_dock_row({"warnings": [w]}, [["Lap", "1 m"]])
		await tree.process_frame
		var old: Array[String] = []
		_walk(room, room, old)
		results.append(TestResult.new(
			"field room (%s): no old-look variation or glass_box stylebox on any node" % ("whole room" if page == "" else page + " page"),
			old.is_empty(), "%d old: %s" % [old.size(), ", ".join(old.slice(0, 8))]))
	room.queue_free()
	await tree.process_frame
	results.append(TestResult.new("the detector can fail: a ReadoutLabel and a glass_box panel are both flagged",
		_detector_fires(tree), "detector self-check"))
	return results


static func _detector_fires(tree: SceneTree) -> bool:
	var holder := Control.new()
	holder.theme = LothalTheme.get_theme()
	var bad_label := Label.new()
	bad_label.theme_type_variation = &"ReadoutLabel"
	var bad_panel := PanelContainer.new()
	bad_panel.add_theme_stylebox_override("panel", LothalTheme.glass_box())
	var themed_panel := PanelContainer.new()
	holder.add_child(bad_label)
	holder.add_child(bad_panel)
	holder.add_child(themed_panel)
	tree.root.add_child(holder)
	var found: Array[String] = []
	_walk(holder, holder, found)
	holder.free()
	return found.size() >= 3


static func _walk(node: Node, root: Node, out: Array[String]) -> void:
	if node is Control:
		var c := node as Control
		if c.theme_type_variation in OLD_VARIATIONS:
			out.append("%s:%s" % [root.get_path_to(c), c.theme_type_variation])
		for sb_name in STYLEBOX_NAMES:
			if c.has_theme_stylebox(sb_name):
				var sb := c.get_theme_stylebox(sb_name)
				if sb is StyleBoxFlat and (sb as StyleBoxFlat).shadow_size > 0:
					out.append("%s:%s(glass)" % [root.get_path_to(c), sb_name])
	for child in node.get_children():
		_walk(child, root, out)
