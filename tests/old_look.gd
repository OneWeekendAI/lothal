class_name OldLook
extends RefCounted
## The detector behind G1 and the per-room Design Space checks: finds nodes still wearing the old glass-shell look.
## A node is OLD when it carries one of the retired type variations, or draws a shadowed (glass_box) stylebox, set as an
## override or inherited from the theme. With `buttons` on, a Button whose hover / pressed / disabled boxes are not
## pairwise different is also reported (a press that looks like nothing).

const BANNED_VARIATIONS := [&"ReadoutLabel", &"MutedLabel", &"TitleLabel", &"SmallLabel", &"WarnLabel", &"HeroReadoutLabel",
	&"SubHeroReadoutLabel", &"CompactButton", &"CompactCheckButton", &"PrimaryButton", &"FlushPanel", &"SunkenPanel"]
const STYLEBOX_NAMES := ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus", "read_only",
	"fill", "background", "slider", "grabber_area", "grabber_area_highlight", "scroll", "scroll_focus", "grabber",
	"grabber_highlight", "grabber_pressed", "cursor", "cursor_unfocused", "selected", "selected_focus", "hovered"]


static func scan(root: Node, buttons := true) -> Array[String]:
	var out: Array[String] = []
	_walk(root, root, out, buttons)
	return out


static func _sig(sb: StyleBox) -> String:
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		return "%s|%s|%d" % [f.bg_color, f.border_color, f.content_margin_top]
	return str(sb)


static func _walk(node: Node, root: Node, out: Array[String], buttons: bool) -> void:
	if node is Control:
		var c := node as Control
		if c.theme_type_variation in BANNED_VARIATIONS:
			out.append("%s:%s" % [root.get_path_to(c), c.theme_type_variation])
		for sb_name in STYLEBOX_NAMES:
			if c.has_theme_stylebox(sb_name):
				var sb := c.get_theme_stylebox(sb_name)
				if sb is StyleBoxFlat and (sb as StyleBoxFlat).shadow_size > 0:
					out.append("%s:%s(glass)" % [root.get_path_to(c), sb_name])
		if buttons and c is Button and not (c is OptionButton) and not (c is MenuButton) and not (c is CheckBox) and not (c is CheckButton):
			var sigs := [_sig(c.get_theme_stylebox("hover")), _sig(c.get_theme_stylebox("pressed")), _sig(c.get_theme_stylebox("disabled"))]
			if sigs[0] == sigs[1] or sigs[0] == sigs[2] or sigs[1] == sigs[2]:
				out.append("%s:same-state-boxes" % root.get_path_to(c))
	for child in node.get_children():
		_walk(child, root, out, buttons)
