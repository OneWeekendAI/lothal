class_name WarningList
extends VBoxContainer
## One block of warnings, presented so that the severity is visible at a glance.
##
## Both part panels used to dump every warning into a single amber label, which is the UI half of
## the bug this slice exists to fix: a pack that physically does not fit and a build that is merely
## heavy arrived looking identical. A user who had correctly built a cinelifter read the same
## orange as someone who had bolted a 7" prop to a 3" frame.
##
## So there is one label per severity, in severity order, coloured by the theme's existing roles:
##
##   IMPOSSIBLE     DANGER      — this does not work. Read it as a problem, because it is one.
##   LIMITING       WARNING     — it works, and this part is what binds. The old amber.
##   CHARACTERISTIC TEXT_MUTED  — this is what you have built. Information, not a scolding, and
##                                deliberately the quietest thing in the block.
##
## No icons, no new colour literals — LothalTheme already has the roles, and a fourth colour
## invented here would be a second opinion about what "serious" looks like.
##
## Ordering is not left to the physics: whatever order the warnings were computed in, the
## impossible ones are never below the descriptive ones on screen.

## Ordered the way they are shown. BuildWarning.Severity is already declared most-severe-first, so
## this is its own order and there is no second table to disagree with it.
const ORDER := [BuildWarning.Severity.IMPOSSIBLE, BuildWarning.Severity.LIMITING,
	BuildWarning.Severity.CHARACTERISTIC]

const COLORS := {
	BuildWarning.Severity.IMPOSSIBLE: LothalTheme.DANGER,
	BuildWarning.Severity.LIMITING: LothalTheme.WARNING,
	BuildWarning.Severity.CHARACTERISTIC: LothalTheme.TEXT_MUTED,
}

var _labels: Dictionary = {}   # Severity -> Label


func _init(width: float = 280.0) -> void:
	custom_minimum_size = Vector2(width, 0)
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	for severity in ORDER:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(width, 0)
		label.theme_type_variation = &"WarnLabel"
		# Exception: severity is the whole point of this control, and the theme's roles are what
		# say it. Each is one of LothalTheme's own colours, not a literal.
		label.add_theme_color_override("font_color", COLORS[severity])
		label.visible = false
		_labels[severity] = label
		add_child(label)


## Show these warnings, grouped by severity and ordered most severe first. An empty list hides the
## whole block, and a severity with nothing in it hides its own label rather than leaving a gap.
func show_warnings(entries: Array[BuildWarning]) -> void:
	# Array rather than PackedStringArray, deliberately: a packed array read back out of a
	# Dictionary is a COPY, so appending to it appends to nothing and every label comes out empty.
	var grouped: Dictionary = {}
	for severity in ORDER:
		grouped[severity] = []
	for entry in BuildWarning.by_severity(entries):
		(grouped[entry.severity] as Array).append(entry.message)

	for severity in ORDER:
		var text: String = "\n".join(PackedStringArray(grouped[severity]))
		var label: Label = _labels[severity]
		label.text = text
		label.visible = text != ""

	visible = not entries.is_empty()


## What one severity currently reads, and what the whole block reads top to bottom. Named accessors
## rather than tests reaching into the labels, so the control's internals stay its own.
func text_for(severity: BuildWarning.Severity) -> String:
	return (_labels[severity] as Label).text


func color_for(severity: BuildWarning.Severity) -> Color:
	return COLORS[severity]


func ordered_text() -> String:
	var blocks: PackedStringArray = []
	for severity in ORDER:
		var text := text_for(severity)
		if text != "":
			blocks.append(text)
	return "\n".join(blocks)
