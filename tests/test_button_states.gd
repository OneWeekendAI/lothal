class_name TestButtonStates
## B4 (UI_REDESIGN_TRACKER): every DsUi button state looks different. For each kind of button the
## stylebox of each state must differ from every other in fill or border (primary hover brighter than
## rest, a click darker than rest, disabled and busy and keyboard focus each their own look).

static func _sig(sb: StyleBox) -> String:
	var f := sb as StyleBoxFlat
	return "%s|%s|%d" % [f.bg_color, f.border_color, int(f.content_margin_top)]


static func _differs(b: Button, states: Array) -> Array:
	var same: Array = []
	for i in states.size():
		for j in range(i + 1, states.size()):
			if _sig(b.get_theme_stylebox(states[i])) == _sig(b.get_theme_stylebox(states[j])):
				same.append("%s==%s" % [states[i], states[j]])
	return same


static func _alpha(b: Button, state: String) -> float:
	return (b.get_theme_stylebox(state) as StyleBoxFlat).bg_color.a


static func run() -> Array:
	var results: Array = []
	var kinds := {"plain": [false, false], "primary": [false, true], "toggle": [true, false]}
	for k in kinds:
		var b := DsUi.button("x", kinds[k][0], kinds[k][1])
		var states := ["normal", "hover", "pressed", "disabled", "focus"]
		if kinds[k][0]:
			states = ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
		var same := _differs(b, states)
		results.append(TestResult.new("%s button: normal/hover/pressed/disabled/focus styleboxes are pairwise different" % k,
			same.is_empty(), ", ".join(same)))
		results.append(TestResult.new("%s button: keyboard reachable" % k, b.focus_mode == Control.FOCUS_ALL, ""))
		if k != "toggle":
			results.append(TestResult.new("%s button: hover is brighter than rest, a click darker than rest" % k,
				_alpha(b, "hover") > _alpha(b, "normal") and _alpha(b, "pressed") < _alpha(b, "normal"),
				"rest %.2f hover %.2f pressed %.2f" % [_alpha(b, "normal"), _alpha(b, "hover"), _alpha(b, "pressed")]))
		var ring := b.get_theme_stylebox("focus") as StyleBoxFlat
		results.append(TestResult.new("%s button: the focus ring is the accent" % k, ring.border_color == LothalTheme.ACCENT, str(ring.border_color)))
		# Busy: not the disabled look, text swapped and restored.
		var plain_off := _sig(b.get_theme_stylebox("disabled"))
		DsUi.set_busy(b, true, "Loading...")
		var busy_ok := b.disabled and b.text == "Loading..." and _sig(b.get_theme_stylebox("disabled")) != plain_off
		DsUi.set_busy(b, false)
		results.append(TestResult.new("%s button: busy is disabled, reads Loading..., looks unlike disabled, and restores" % k,
			busy_ok and not b.disabled and b.text == "x" and _sig(b.get_theme_stylebox("disabled")) == plain_off, b.text))
		b.free()
	# The sim bar's Back button is one of these, not a one-off with hover == pressed.
	var shell := DesignApp.new()
	ProjectLibrary.root = "user://scratch_btn_%d" % OS.get_process_id()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	shell._enter_away()
	var back := shell._away_layer.get_node("SimBar/Row/Back") as Button
	results.append(TestResult.new("the sim bar's Back button: hover and pressed differ",
		_sig(back.get_theme_stylebox("hover")) != _sig(back.get_theme_stylebox("pressed")), ""))
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results
