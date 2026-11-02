class_name TestLabelToggle
extends RefCounted
## The eye (and L) that hides every label over the drone, and the idle fade. Time and input are
## driven through `step_labels(seconds)` and `note_input()`, so nothing here waits on a clock.
##
## - THE LABELS ARE READ OFF THE CALLOUT LAYER'S OWN VISIBILITY AND ALPHA, and "there were labels to
##   hide" is asserted first: a layer with nothing shown would pass every hide check.
## - THE TOGGLE-BEATS-IDLE CASE steps past the timeout, then sends input, and demands the labels
##   stay hidden; with the eye open the same input must bring them back (the two halves differ only
##   in the toggle).

const CLASS_ID := "five_inch"


static func _fresh() -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), PartsCatalog.load_default())
	ds.size = Vector2(1280, 720)
	ds.rig.snap()
	ds.update_callouts()
	return ds


static func _shown(ds: DesignSpace) -> bool:
	return ds.callouts.visible and ds.callouts.modulate.a > 0.99


static func _gone(ds: DesignSpace) -> bool:
	return not ds.callouts.visible or ds.callouts.modulate.a <= 0.0


static func run() -> Array:
	var results: Array = []
	var ds := _fresh()
	results.append(TestResult.new("seed: labels and warning pins are on screen to begin with",
		ds.callouts.shown.size() >= 3 and ds.warning_pins.size() >= 1 and _shown(ds),
		"%d shown, %d warnings" % [ds.callouts.shown.size(), ds.warning_pins.size()]))
	var eye_at := Vector2(ds.labels_button.offset_left, ds.size.y + ds.labels_button.offset_top)
	var avoided := false
	for r in ds.callout_avoid_rects():
		avoided = avoided or ((r as Rect2).position.is_equal_approx(eye_at) and (r as Rect2).size.x >= 20.0)
	results.append(TestResult.new("the eye button sits bottom-left, above Home, and the callouts keep clear of it",
		ds.labels_button != null and ds.labels_button.anchor_top == 1.0
		and ds.labels_button.offset_bottom <= ds.home_button.offset_top and avoided, ""))

	# The toggle hides every label node, warning pins included, and shows them again.
	ds.labels_button.pressed.emit()
	results.append(TestResult.new("the eye hides every label, callout and warning pin at once",
		ds.labels_hidden and _gone(ds) and ds.open_warning_at(ds.callouts.shown[0]["pin"]) == false,
		"hidden %s visible %s a %s" % [ds.labels_hidden, ds.callouts.visible, ds.callouts.modulate.a]))
	results.append(TestResult.new("hiding keeps the layout computed, so showing again needs no rebuild",
		ds.callouts.shown.size() >= 3, str(ds.callouts.shown.size())))
	ds.toggle_labels()
	ds.step_labels(1.0)
	results.append(TestResult.new("pressing it again shows them all",
		not ds.labels_hidden and _shown(ds), "a %s" % ds.callouts.modulate.a))
	var l_key := InputEventKey.new()
	l_key.keycode = KEY_L
	l_key.pressed = true
	ds._unhandled_key_input(l_key)
	results.append(TestResult.new("L toggles the labels off",
		ds.labels_hidden and _gone(ds), ""))
	ds._unhandled_key_input(l_key)
	ds.step_labels(1.0)
	results.append(TestResult.new("and L toggles them back on",
		not ds.labels_hidden and _shown(ds), ""))
	var ctrl_l := InputEventKey.new()
	ctrl_l.keycode = KEY_L
	ctrl_l.ctrl_pressed = true
	ctrl_l.pressed = true
	ds._unhandled_key_input(ctrl_l)
	results.append(TestResult.new("Ctrl+L is not the shortcut", not ds.labels_hidden, ""))
	ds.free()

	# Idle: hidden after the timeout, back on any input.
	ds = _fresh()
	results.append(TestResult.new("the idle timeout is a constant, about 4 s, and the fade 0.3 s",
		absf(DesignSpace.IDLE_HIDE_S - 4.0) < 0.5 and is_equal_approx(DesignSpace.LABEL_FADE_S, 0.3), ""))
	ds.step_labels(DesignSpace.IDLE_HIDE_S - 0.05)
	results.append(TestResult.new("just before the timeout the labels are still fully shown",
		_shown(ds) and not ds.labels_idle(), "a %s" % ds.callouts.modulate.a))
	ds.step_labels(0.05 + 0.1)
	var mid := ds.callouts.modulate.a
	results.append(TestResult.new("past the timeout they are fading, not yet gone, 0.3 s long",
		ds.labels_idle() and mid > 0.0 and mid < 1.0, "a %s" % mid))
	ds.step_labels(DesignSpace.LABEL_FADE_S)
	results.append(TestResult.new("and gone when the fade has run",
		_gone(ds), "a %s visible %s" % [ds.callouts.modulate.a, ds.callouts.visible]))
	ds.note_input()
	ds.step_labels(DesignSpace.LABEL_FADE_S * 0.5)
	results.append(TestResult.new("any input starts them fading back in",
		not ds.labels_idle() and ds.callouts.visible and ds.callouts.modulate.a > 0.0 and ds.callouts.modulate.a < 1.0,
		"a %s" % ds.callouts.modulate.a))
	ds.step_labels(DesignSpace.LABEL_FADE_S)
	results.append(TestResult.new("and fully back after the fade",
		_shown(ds), "a %s" % ds.callouts.modulate.a))
	# Real events reach note_input through _input.
	ds.step_labels(DesignSpace.IDLE_HIDE_S + 1.0)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300, 300)
	ds._input(mm)
	ds.step_labels(1.0)
	results.append(TestResult.new("a mouse move through the real input path restores them",
		_shown(ds), "a %s" % ds.callouts.modulate.a))
	ds.step_labels(DesignSpace.IDLE_HIDE_S + 1.0)
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	ds._input(key)
	ds.step_labels(1.0)
	results.append(TestResult.new("and so does a key press",
		_shown(ds), "a %s" % ds.callouts.modulate.a))
	# Idle time accumulates in small frame steps too.
	ds.note_input()
	for i in int(ceil((DesignSpace.IDLE_HIDE_S + 1.0) * 60.0)):
		ds.step_labels(1.0 / 60.0)
	results.append(TestResult.new("sixty-frames-a-second steps reach the same hidden state",
		_gone(ds), "a %s" % ds.callouts.modulate.a))
	ds.free()

	# The toggle's hidden state wins over idle.
	ds = _fresh()
	ds.toggle_labels()
	ds.step_labels(DesignSpace.IDLE_HIDE_S + 1.0)
	ds.note_input()
	ds.step_labels(1.0)
	results.append(TestResult.new("hidden by the eye, input does not bring the labels back",
		ds.labels_hidden and _gone(ds), "a %s visible %s" % [ds.callouts.modulate.a, ds.callouts.visible]))
	ds.toggle_labels()
	ds.note_input()
	ds.step_labels(1.0)
	results.append(TestResult.new("shown by the eye again, and input keeps them on",
		_shown(ds), ""))
	ds.step_labels(DesignSpace.IDLE_HIDE_S + 1.0)
	results.append(TestResult.new("with the eye open, idle still hides them", _gone(ds), ""))
	ds.free()
	return results
