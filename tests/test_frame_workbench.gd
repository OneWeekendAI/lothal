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

const CANVAS_SIZE := Vector2(900.0, 620.0)


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_canvas_clips_its_own_drawing())
	results.append(_test_the_room_paints_an_opaque_floor())
	results.append(_test_the_zoom_controls_move_the_view_and_the_readout_follows())
	results.append(_test_a_resize_reframes_an_untouched_view_only())
	results.append(_test_switching_to_3d_swaps_the_whole_canvas())
	results.append(_test_a_panel_asks_for_the_width_its_longest_value_needs())
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
## Both halves, because each alone passes against doing nothing on resize in one direction and
## against always re-fitting in the other — and the two wrong behaviours are the two that shipped.
static func _test_a_resize_reframes_an_untouched_view_only() -> TestResult:
	var untouched := _workbench()
	untouched.editor.size = CANVAS_SIZE
	untouched.editor.fit_to_document()
	var before_fit := untouched.editor.transform.scale_px_per_mm
	untouched.editor.size = CANVAS_SIZE * 0.5
	var after_fit := untouched.editor.transform.scale_px_per_mm
	untouched.free()

	var aimed := _workbench()
	aimed.editor.size = CANVAS_SIZE
	aimed.editor.fit_to_document()
	aimed.editor.zoom_by(3.0)
	var before_zoom := aimed.editor.transform.scale_px_per_mm
	aimed.editor.size = CANVAS_SIZE * 0.5
	var after_zoom := aimed.editor.transform.scale_px_per_mm
	aimed.free()

	# Halving the view halves the scale a fit chooses; a view the builder aimed keeps its own.
	var reframed := after_fit < before_fit * 0.75
	var left_alone := absf(after_zoom - before_zoom) < 1.0e-6
	return TestResult.new(
		"a resize re-frames a view nobody aimed, and leaves an aimed one exactly where it was",
		reframed and left_alone,
		"untouched %.3f -> %.3f px/mm; aimed %.3f -> %.3f px/mm"
			% [before_fit, after_fit, before_zoom, after_zoom])


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
# What the inspector asks the shell for
# ---------------------------------------------------------------------------

## The shell sizes the inspector column to the width its rows need, and it can only do that if a
## panel will say what that width is AFTER its values have been rendered. Measured once at startup,
## the column was sized to eleven dashes and every real value ran off the window edge.
static func _test_a_panel_asks_for_the_width_its_longest_value_needs() -> TestResult:
	var panel := StructureDetails.new()
	var empty := panel.content_width()

	var catalog := PartsCatalog.load_default()
	var frames := catalog.list_category("frame")
	panel.render(AirframeDocument.from_catalog_frame(frames[0]))
	var rendered := panel.content_width()
	panel.free()

	return TestResult.new(
		"a spec panel asks for more width once it is carrying real values",
		rendered > empty and rendered > 0.0,
		"%.0f px empty -> %.0f px rendered" % [empty, rendered])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A workbench opened on a real catalog frame, which is what the room opens on in the app. A blank
## document would make the zoom and fit assertions vacuous — there would be nothing to frame.
static func _workbench() -> FrameWorkbench:
	var catalog := PartsCatalog.load_default()
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(catalog.list_category("frame")[0])
	return workbench


## The Control the two views share. Found by walking rather than exposed, because it is an
## implementation detail of the layout everywhere except here.
static func _canvas_host(workbench: FrameWorkbench) -> Control:
	return workbench.editor.get_parent() as Control
