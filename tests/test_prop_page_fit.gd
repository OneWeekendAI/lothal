class_name TestPropPageFit
extends RefCounted
## PD15: the designer page stays inside a 1280x720 window in every state a capture showed spilling.
## A control's minimum height is what pushes a page past the window's bottom edge, so it is what this
## measures. Also the left column's cue, because hub and material sit below its fold at every size.

const WINDOW_H := 720.0


static func _states() -> Dictionary:
	return {
		"figures": _none,
		"tunnel": _tunnel,
		"tunnel above Mach": _tunnel_mach,
		"tunnel with measured dots": _tunnel_measured,
		"tunnel details": _tunnel_details,
		"stand": _stand,
		"structure": _structure,
		"structure details": _structure_details,
		"make": _make,
	}


static func run() -> Array:
	return [
		_test_cue_up_while_more_lies_below(),
		_test_cue_gone_at_the_end(),
		_test_cue_gone_when_all_fits(),
	]


## Needs frames: a Control's minimum is 0 outside the tree, so `TestShellLayout.run` calls this.
static func run_in_tree(tree: SceneTree) -> Array:
	var view := SubViewport.new()
	view.size = Vector2i(1280, int(WINDOW_H))
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(view)
	var results: Array = []
	var states := _states()
	for state: String in states:
		results.append(await _fits(tree, view, state, states[state]))
	view.queue_free()
	return results


static func _designer() -> PropDesigner:
	return PropDesigner.new(PartsCatalog.load_default(), FrameMaterials.load_default())


static func _fits(tree: SceneTree, view: SubViewport, state: String, arrange: Callable) -> TestResult:
	var d := _designer()
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.add_child(d)
	await tree.process_frame
	arrange.call(d)
	for i in 4:
		await tree.process_frame
	var h := d.window.get_combined_minimum_size().y + 2.0 * DesignerShell.MARGIN_Y
	d.free()
	return TestResult.new("[PD15] page fits 720: " + state, h > 100.0 and h <= WINDOW_H, "needs %.0f px" % h)


static func _cue_after(max_value: float, page: float, value: float) -> bool:
	var d := _designer()
	var bar := d.left_scroll.get_v_scroll_bar()
	bar.max_value = max_value
	bar.page = page
	bar.value = value
	d.update_left_cue()
	var shown := d.left_cue.modulate.a > 0.5
	d.free()
	return shown


static func _test_cue_up_while_more_lies_below() -> TestResult:
	return TestResult.new("[PD15] left cue: up while more lies below", _cue_after(1000.0, 500.0, 0.0), "")


static func _test_cue_gone_at_the_end() -> TestResult:
	return TestResult.new("[PD15] left cue: gone at the end", not _cue_after(1000.0, 500.0, 500.0), "")


static func _test_cue_gone_when_all_fits() -> TestResult:
	return TestResult.new("[PD15] left cue: gone when all fits", not _cue_after(400.0, 500.0, 0.0), "")


static func _none(_d: PropDesigner) -> void:
	pass


static func _tunnel(d: PropDesigner) -> void:
	d.show_tab("tunnel")


static func _tunnel_mach(d: PropDesigner) -> void:
	d.show_tab("tunnel")
	d.step_rpm(60000.0)


static func _tunnel_measured(d: PropDesigner) -> void:
	d.doc.diameter_mm = 4.2 * PropellerDocument.INCH_TO_MM
	d.doc.pitch_mm = 4.0 * PropellerDocument.INCH_TO_MM
	d.set_blades(2)
	d.show_tab("tunnel")
	d.step_rpm(8067.0 - d.rpm)


static func _tunnel_details(d: PropDesigner) -> void:
	d.show_tab("tunnel")
	d.tunnel.set_details(true)


static func _stand(d: PropDesigner) -> void:
	d.show_tab("stand")


static func _structure(d: PropDesigner) -> void:
	d.show_tab("structure")


static func _structure_details(d: PropDesigner) -> void:
	d.show_tab("structure")
	d.structure.set_details(true)


static func _make(d: PropDesigner) -> void:
	d.show_tab("make")
