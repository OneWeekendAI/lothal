class_name TestFrameWorkbench
extends RefCounted
## The Airframe room's chrome — src/ui/frame_workbench.gd and the view controls on it.
##
## ## Why these five, and not "the room looks right"
##
## Every assertion below is about a failure that was VISIBLE in a screenshot and invisible to every
## other test in the suite. `test_frame_plan_editor.gd` covers what a gesture means and what comes
## out of the document; nothing covered what the room does with the rectangle it was given, and all
## four of the faults this suite pins were in that gap:
##
##   - the canvas drew outside its own rectangle, over the toolbar and off the window edge;
##   - the room was transparent, so another drone's propellers turned behind the toolbar;
##   - the only way to zoom was a mouse wheel nobody had been told about;
##   - the frame could not be looked at in three dimensions in the room it was drawn in.
##
## ## MUTATION NOTES
##
##   - `_test_the_canvas_clips_its_own_drawing` fails the moment `clip_contents` comes off either
##     the editor or the host, which is exactly the one-property regression that produced the
##     original overflow.
##   - `_test_a_resize_reframes_an_untouched_view_only` fails BOTH ways: re-fit unconditionally and
##     the zoomed case fails; never re-fit and the untouched case fails. A test that only checked
##     one of them would pass against "do nothing on resize", which is the bug it replaced.
##   - `_test_the_room_paints_an_opaque_floor` fails if the backdrop is dropped OR if it is given
##     the translucent glass stylebox the floating panels use — translucent is precisely the state
##     that let the 3D world through.
##   - `_test_switching_to_3d_swaps_the_whole_canvas` fails if the two views are merely stacked
##     rather than swapped: an editor left visible under a SubViewportContainer still takes the
##     clicks, so a builder would drag vertices they could not see.
##
## ## What is deliberately NOT asserted here
##
## That the inspector column sizes itself to the rows it is carrying — the other half of the same
## screenshot, and the reason `SpecPanel.content_width()` exists. It cannot be checked in this
## harness: `Label.update_minimum_size()` does nothing on a node outside the tree, so a panel's
## combined minimum size never moves off its floor no matter what it is rendering, and
## `content_width()` returns a constant 296 px for every frame in the catalog. A test asserting it
## would report the same number for correct and broken code alike. It is checked instead by
## photographing the real shell — `tests/capture_glass_shell.gd -- <out.png> 30 Airframe` — which is
## the same reason `test_glass_shell.gd` refuses to assert `current_tab`.

const CANVAS_SIZE := Vector2(900.0, 620.0)


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_canvas_clips_its_own_drawing())
	results.append(_test_the_room_paints_an_opaque_floor())
	results.append(_test_the_zoom_controls_move_the_view_and_the_readout_follows())
	results.append(_test_a_resize_reframes_an_untouched_view_only())
	results.append(_test_switching_to_3d_swaps_the_whole_canvas())
	results.append(_test_an_import_lands_in_the_open_frame_and_is_undoable())
	results.append(_test_a_refused_import_says_why_and_changes_nothing())
	return results


# ---------------------------------------------------------------------------
# The rectangle the room was given
# ---------------------------------------------------------------------------

## A Control does not clip its own `_draw`, and the plan canvas places every line through an
## unbounded pan-and-zoom. Zoomed in one step past fit, the arms of a 5" frame reach past the
## canvas, and without clipping they are painted over the toolbar above and the window edge beside.
##
## Checked as geometry rather than as a property alone: the drawing is proven to LEAVE the
## rectangle at this zoom, so the flag is being asserted about a case where it does something.
static func _test_the_canvas_clips_its_own_drawing() -> TestResult:
	var workbench := _workbench()
	var editor := workbench.editor
	editor.size = CANVAS_SIZE
	editor.fit_to_document()
	editor.zoom_by(4.0)

	var outside := 0
	for plate in editor.document.plates:
		for point in AirframeDocument.plate_outline(plate):
			var px := editor.transform.to_pixels(point)
			if px.x < 0.0 or px.y < 0.0 or px.x > CANVAS_SIZE.x or px.y > CANVAS_SIZE.y:
				outside += 1

	var clipped := editor.clip_contents
	var host_clips := _canvas_host(workbench).clip_contents
	workbench.free()
	return TestResult.new(
		"the plan canvas clips its own drawing, and there is something to clip",
		clipped and host_clips and outside > 0,
		"%d points outside the canvas at 4x; editor clips: %s, host clips: %s"
			% [outside, clipped, host_clips])


## The room covers the 3D view rather than sitting beside it, so every pixel it does not paint is a
## window onto Lab's turntable — which is how a builder ended up watching a different drone's
## propellers turn behind their own toolbar.
static func _test_the_room_paints_an_opaque_floor() -> TestResult:
	var workbench := _workbench()
	var opaque := false
	var alpha := 0.0
	for child in workbench.get_children():
		if child is Panel:
			var box := (child as Panel).get_theme_stylebox("panel")
			if box is StyleBoxFlat:
				alpha = (box as StyleBoxFlat).bg_color.a
				# 0.95 rather than 1.0: a hairline of translucency is a style choice and hides
				# nothing. The glass panels this must NOT be are at 0.86.
				opaque = alpha >= 0.95
	workbench.free()
	return TestResult.new(
		"the room paints an opaque floor, so no other room shows through it",
		opaque,
		"backdrop alpha %.2f" % alpha)


# ---------------------------------------------------------------------------
# The view controls
# ---------------------------------------------------------------------------

## Zoom used to be the mouse wheel and nothing else. The buttons drive `zoom_by`, which zooms about
## the CENTRE of the view — a button has no cursor to zoom about, and using the last mouse position
## makes the drawing jump sideways when you press "+".
static func _test_the_zoom_controls_move_the_view_and_the_readout_follows() -> TestResult:
	var workbench := _workbench()
	var editor := workbench.editor
	editor.size = CANVAS_SIZE
	editor.fit_to_document()

	var at_fit := editor.zoom_ratio()
	var centre_before := editor.transform.to_mm(CANVAS_SIZE * 0.5)

	editor.zoom_by(2.0)
	var zoomed := editor.zoom_ratio()
	var centre_after := editor.transform.to_mm(CANVAS_SIZE * 0.5)

	editor.zoom_by(0.5)
	var back := editor.zoom_ratio()

	var held := centre_before.distance_to(centre_after) < 1.0e-3
	workbench.free()
	return TestResult.new(
		"zooming reports its factor and holds the middle of the view still",
		absf(at_fit - 1.0) < 1.0e-3 and absf(zoomed - 2.0) < 1.0e-3
			and absf(back - 1.0) < 1.0e-3 and held,
		"fit %.3fx -> %.3fx -> %.3fx; centre moved %.6f mm"
			% [at_fit, zoomed, back, centre_before.distance_to(centre_after)])


## A resize must re-frame a view nobody has aimed, and must not touch one they have.
##
## Both halves, because each alone passes against a wrong answer in the other direction: always
## re-fit and the aimed case fails, never re-fit and the untouched case fails. The two wrong
## behaviours are the two obvious ones, which is why neither may be left unpinned.
##
## The PREDICATE is driven rather than the signal. `resized` does not fire on a Control outside the
## tree — verified, it fires zero times for two `size =` assignments — so a test that assigned a
## size and read the scale back would report "did not re-fit" against correct code and against
## broken code alike. That is the shape of a test that cannot fail, so the policy is asked directly
## and the one-line signal wiring is left to the running app and the capture screenshot.
static func _test_a_resize_reframes_an_untouched_view_only() -> TestResult:
	var workbench := _workbench()
	var editor := workbench.editor
	editor.size = CANVAS_SIZE
	editor.fit_to_document()
	var after_fit := editor.should_refit_on_resize()

	# That a re-fit would actually DO something at the new size — otherwise the predicate above is
	# permission to perform a no-op, and the test would pass on a canvas whose scale never moves.
	var scale_here := editor.transform.scale_px_per_mm
	editor.size = CANVAS_SIZE * 0.5
	editor.fit_to_document()
	var scale_there := editor.transform.scale_px_per_mm

	editor.zoom_by(3.0)
	var after_zoom := editor.should_refit_on_resize()

	# Panning is aiming the view too. Driven as a real DRAG through `_gui_input` — press on empty
	# space, move, release — and not by calling `transform.pan()`, which would reach past the editor
	# to the object underneath it and assert nothing about whether the editor noticed.
	var panned := _workbench()
	panned.editor.size = CANVAS_SIZE
	panned.editor.fit_to_document()
	var empty_px := Vector2(20.0, 20.0)
	panned.editor._gui_input(_press(empty_px))
	panned.editor._gui_input(_motion(empty_px + Vector2(40.0, 20.0)))
	var after_pan := panned.editor.should_refit_on_resize()
	panned.free()

	var refits := scale_there < scale_here * 0.75
	workbench.free()
	return TestResult.new(
		"a resize re-frames a view nobody aimed, and leaves an aimed one alone",
		after_fit and not after_zoom and not after_pan and refits,
		"after fit: %s, after zoom: %s, after pan: %s, refit changes scale %.2f -> %.2f px/mm"
			% [after_fit, after_zoom, after_pan, scale_here, scale_there])


## The two views share one rectangle and one switch. Stacking them instead — leaving the editor
## visible under the 3D view — would leave the invisible canvas taking the clicks, so an orbit drag
## would silently move vertices.
static func _test_switching_to_3d_swaps_the_whole_canvas() -> TestResult:
	var workbench := _workbench()
	var plan_first := workbench.editor.visible and not workbench.view_3d.visible

	workbench.set_view_3d(true)
	var in_3d := workbench.view_3d.visible and not workbench.editor.visible \
		and workbench.showing_3d()

	workbench.set_view_3d(false)
	var back_in_2d := workbench.editor.visible and not workbench.view_3d.visible \
		and not workbench.showing_3d()

	workbench.free()
	return TestResult.new(
		"the room opens in plan, switches wholly to 3D, and comes wholly back",
		plan_first and in_3d and back_in_2d,
		"plan first: %s, in 3D: %s, back: %s" % [plan_first, in_3d, back_in_2d])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The frame the room opens on in the app, and the one in every screenshot of it.
##
## NAMED, NOT INDEXED. `list_category("frame")[0]` is the 65 mm Whoop — a MOULDED frame, which by
## §7.3 has no plate model at all and produces a document with zero plates. Every assertion here
## about what is drawn and where it lands was silently vacuous against it: the first version of
## this suite reported "0 points outside the canvas" and meant "there is no canvas".
const FIXTURE_FRAME := "5\" Freestyle"


## A workbench opened on a real catalog frame, which is what the room opens on in the app. A blank
## document would make the zoom and fit assertions vacuous — there would be nothing to frame.
## Import, driven through the room rather than through `FrameImport` alone.
##
## The room's job here is the part `FrameImport` cannot do for itself: record history BEFORE the
## document is touched, so one Undo puts the frame back. Asserted by actually undoing — the plate
## count returning to what it was is the only evidence that the history entry is a snapshot rather
## than a reference to the live document.
static func _test_an_import_lands_in_the_open_frame_and_is_undoable() -> TestResult:
	var workbench := _workbench()
	var path := "user://test_workbench_import.svg"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		workbench.free()
		return TestResult.new("an import lands in the open frame", false, "no fixture")
	file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="60mm" height="60mm" ' +
		'viewBox="0 0 60 60"><rect x="5" y="5" width="50" height="30"/></svg>')
	file.close()

	var before := workbench.editor.document.plates.size()
	var imported := workbench.import_file(path)
	var after := workbench.editor.document.plates.size()
	workbench.editor.undo()
	var undone := workbench.editor.document.plates.size()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	workbench.free()

	return TestResult.new("an import lands in the open frame and one Undo removes it",
		imported and after == before + 1 and undone == before,
		"%d plates, %d after import, %d after undo" % [before, after, undone])


## A file that cannot be read must leave BOTH the document and the undo stack alone.
##
## The undo assertion is the interesting half: a room that recorded history before checking the
## error would leave a step that undoes nothing, and the builder's next Undo — aimed at the edit
## before the failed import — would appear to do nothing at all.
static func _test_a_refused_import_says_why_and_changes_nothing() -> TestResult:
	var workbench := _workbench()
	var path := "user://test_workbench_import_bad.svg"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		workbench.free()
		return TestResult.new("a refused import changes nothing", false, "no fixture")
	file.store_string("not an svg at all <<<")
	file.close()

	var before := workbench.editor.document.plates.size()
	var accepted := workbench.import_file(path)
	var after := workbench.editor.document.plates.size()
	workbench.editor.undo()
	var undone := workbench.editor.document.plates.size()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	workbench.free()

	return TestResult.new("a refused import changes neither the frame nor the undo stack",
		not accepted and after == before and undone == before,
		"%d plates, %d after, %d after undo" % [before, after, undone])


static func _workbench() -> FrameWorkbench:
	var catalog := PartsCatalog.load_default()
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(_fixture_frame(catalog))
	return workbench


static func _press(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event


static func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event


static func _fixture_frame(catalog: PartsCatalog) -> Dictionary:
	for frame in catalog.list_category("frame"):
		if str(frame.get("name", "")) == FIXTURE_FRAME:
			return frame
	return {}


## The Control the two views share. Found by walking rather than exposed, because it is an
## implementation detail of the layout everywhere except here.
static func _canvas_host(workbench: FrameWorkbench) -> Control:
	return workbench.editor.get_parent() as Control
