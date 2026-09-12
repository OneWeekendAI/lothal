class_name LinkStub
extends VBoxContainer
## The Link panel, holding its place in Control until C6 writes the rows.
##
## **THE SAME ARRANGEMENT `HarnessStub` HELD FOR PW5, and deliberately the same voice.** C3 moves
## the receiver onto Control's new `Link` rail and puts the GPS and the buzzer beside it, which
## means Control's entry in `GlassShell.SYSTEMS` names three panels from this slice on. A named
## panel with no tab behind it is not harmless: `LabScreen`'s rail-to-panel routing looks the panel
## up BY TITLE and pushes an error when it cannot find one, so every click on the new rail would
## report a wiring fault, and `_show_only_tabs` would quietly show two of Control's three panels
## for the rest of the family. So the tab exists, and it says what it is waiting for.
##
## **What is behind it is NOT nothing, which is the honest part.** C1 and C2 shipped the model: the
## GPS and the buzzer are real catalog parts, weighed into `Build.mass_parts()` at real mounts, the
## GPS's mast raising its own centre of mass off the top plate. The receiver has been modelled since
## LTHL-11. All three are fitted, weighed and drawn on the aircraft today, and the rail next door
## picks them. What has never existed is the panel that READS them back — design §5's rows, the
## editable mast height, and the "not fitted" that is the entire reason a bay is distinguishable
## from a part of zero mass.
##
## A `VBoxContainer` rather than a `SpecPanel`, on `HarnessStub`'s argument: a spec grid with no
## values in it is a table of dashes, which is worse than a sentence.

## The width the wrapped text is laid out to. Set explicitly for `HarnessStub`'s reason: an
## autowrapping Label reports its whole unwrapped string as its minimum width, and `_fit_columns`
## measures minimums — a stub that asked for 900 px would widen the inspector for every system
## that shares the column.
const WRAP_WIDTH := 300.0

func _init() -> void:
	name = "Link"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", LothalTheme.SPACE_3)

	var title := Label.new()
	title.text = "Link"
	title.theme_type_variation = "TitleLabel"
	add_child(title)

	var tag := Label.new()
	tag.text = "soon — the parts are on the aircraft, the panel is not"
	tag.theme_type_variation = "WarnLabel"
	add_child(tag)

	_paragraph("The aircraft's connection to the outside: the receiver that hears the pilot, the "
		+ "GPS that knows where it is, and the buzzer that answers somebody walking towards it. "
		+ "All three are fitted from the Link rail on the left and weighed on this aircraft "
		+ "already — the GPS on its mast, above the top plate.", "MutedLabel")
	_paragraph("What is missing is the readout. C6 puts one row per bay here, reading \"not "
		+ "fitted\" rather than 0 g for an empty one, with the GPS's mast height editable beside "
		+ "it and the buzzer saying whether it has its own power. Until then these three are "
		+ "parts you can fit and cannot inspect.", "MutedLabel")
	_paragraph("Waiting on: C6 — plans/2026-09-12-control-room-plan.md", "SmallLabel")


func _paragraph(body: String, variation: String) -> void:
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	label.theme_type_variation = variation
	add_child(label)
