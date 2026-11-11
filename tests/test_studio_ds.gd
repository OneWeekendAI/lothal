class_name TestStudioDs
extends RefCounted
## R2: Studio (the log reader) speaks the Design Space language. Walks the whole scene tree of a StudioScreen over a real
## recorded log, in the gap view and the explorer, and fails on any node still wearing the old glass-shell look: a
## ReadoutLabel / MutedLabel / TitleLabel type variation, or a shadowed (glass_box) stylebox, set or inherited.

const OLD_VARIATIONS := [&"ReadoutLabel", &"MutedLabel", &"TitleLabel"]
const STYLEBOX_NAMES := ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus", "read_only",
	"fill", "background", "slider", "grabber_area", "grabber_area_highlight", "scroll", "scroll_focus", "grabber",
	"grabber_highlight", "grabber_pressed", "cursor", "cursor_unfocused", "selected", "selected_focus", "hovered"]
const DIR := "user://test_studio_ds_logs"


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/flight-20260816-130000.csv" % DIR
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	core.prime_motors(ReferenceBuild.hover_throttle())
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": ReferenceBuild.hover_throttle()}
	var recorder := FlightRecorder.new(build, 1, null, core.gyro)
	for _i in 300:
		core.step(fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, 0.001), 0.001)
		recorder.capture(core.observables)
	recorder.save(path)

	var studio := StudioScreen.new(FlightLogLibrary.load_from(DIR))
	studio.theme = LothalTheme.get_theme()
	tree.root.add_child(studio)
	await tree.process_frame
	studio.select(studio.library.ids()[0])
	await tree.process_frame
	for mode in [StudioScreen.ViewMode.GAP, StudioScreen.ViewMode.EXPLORE]:
		studio.set_view_mode(mode)
		studio.set_declared_expanded(true)
		await tree.process_frame
		var old: Array[String] = []
		_walk(studio, studio, old)
		results.append(TestResult.new(
			"studio (%s view): no old-look variation or glass_box stylebox on any node" % ("gap" if mode == StudioScreen.ViewMode.GAP else "explore"),
			old.is_empty(), "%d old: %s" % [old.size(), ", ".join(old.slice(0, 8))]))
	studio.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	results.append(TestResult.new("the detector can fail: a ReadoutLabel and a glass_box panel are both flagged",
		TestFieldDs._detector_fires(tree), "detector self-check"))
	return results


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
