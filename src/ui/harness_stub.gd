class_name HarnessStub
extends VBoxContainer
## The Harness panel, holding its place in Power until PW5 draws the thing.
##
## **A STUB THAT SAYS WHAT IT WAITS ON, in the voice the dropdown's four unmodelled systems already
## use.** Power's entry in `GlassShell.SYSTEMS` names three panels, and a third tab that rendered
## nothing would be the one shape this shell has explicitly refused everywhere else: an empty
## column that reads as a rendering fault rather than as a promise. `SystemStub` gives the same
## treatment to a whole system; this is the per-panel version of it, and the two are deliberately
## worded alike so a builder meets one convention rather than two.
##
## **What is behind it is NOT nothing, and the difference is the honest part.** PW1–PW3 shipped the
## model: `Harness` carries the connector, the capacitor and four gauged, measured wire runs; they
## are weighed into `Build.mass_parts()` at real positions, and `HarnessChecks` already warns about
## ampacity and sag on every build. So the harness is on the aircraft and in the warning list
## today. What has never existed anywhere in the app is a PICTURE of it — the schematic and the
## per-segment editing that PW5 builds. This panel is waiting on a view, not on a model, and it
## says so rather than implying the parts are missing.
##
## It is a `VBoxContainer` and not a `SpecPanel` on purpose: a spec grid with no values in it is a
## table of dashes, which is worse than a sentence.

## The width the wrapped text is laid out to. Set explicitly because an autowrapping Label reports
## its whole unwrapped string as its minimum width, and `_fit_columns` measures minimums — a stub
## that asked for 900 px would widen the inspector for every system that shares the column.
const WRAP_WIDTH := 300.0

func _init() -> void:
	name = "Harness"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", LothalTheme.SPACE_3)

	var title := Label.new()
	title.text = "Harness"
	title.theme_type_variation = "TitleLabel"
	add_child(title)

	var tag := Label.new()
	tag.text = "soon — the model is built, the view is not"
	tag.theme_type_variation = "WarnLabel"
	add_child(tag)

	_paragraph("The current path from the pack to the motor leads: the connector, the main lead, "
		+ "the capacitor across the ESC's input pads, and four motor leads. All of it is fitted "
		+ "and weighed on this aircraft already, and the ampacity and sag warnings in the list "
		+ "below any panel are computed from it.", "MutedLabel")
	_paragraph("What is missing is the drawing. PW5 puts the schematic on the left of the Power "
		+ "room — every segment at its real gauge as a stroke width and its real length as a "
		+ "length — and makes gauge and length editable per segment. Until then the harness is "
		+ "something you can be warned about and cannot look at.", "MutedLabel")
	_paragraph("Waiting on: PW5 — plans/2026-09-10-power-room-plan.md", "SmallLabel")


func _paragraph(body: String, variation: String) -> void:
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	label.theme_type_variation = variation
	add_child(label)
