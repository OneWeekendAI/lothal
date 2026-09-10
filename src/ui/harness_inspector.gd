class_name HarnessInspector
extends VBoxContainer
## What the selected segment is, and the two numbers a builder is allowed to change about it —
## plans/2026-09-10-power-room-design.md §2.1, slice PW5.
##
## **Gauge and length, and nothing else**, which is §2.1's sentence and not a scoping compromise: a
## segment is not a part you buy, it is two numbers and a position in the topology. A third control
## here would have to be a control over something the model does not carry per segment.
##
## ---------------------------------------------------------------------------
## THIS PANEL EDITS NOTHING
## ---------------------------------------------------------------------------
##
## Every control emits `value_edited` and stops. It does not touch the `Harness`, it does not
## recompute a mass, and it does not decide what its own fields should read next — the ROOM applies
## the edit and hands the panel back a state to render. That is the Build-free rule seen from the
## control side, and it is what makes the room's undo able to work at all: a panel that wrote
## straight through would have changed the document before the room could remember what it used
## to be.
##
## ONE SIGNAL CARRYING THE KEY, rather than `gauge_chosen` beside `length_chosen`. Two signals is
## two things the room has to remember to record history for, and W0.7's finding is that the term a
## caller can forget is the term a caller eventually forgets. There is one door; the key rides in it.
##
## ---------------------------------------------------------------------------
## THE DEFAULT IS SHOWN BESIDE WHAT WAS TYPED
## ---------------------------------------------------------------------------
##
## Design §0's whole relaxation is "a labelled default with an editable field beside it", and a
## field that has swallowed its default is not that — it is an invented spec wearing a builder's
## handwriting. So every row says what the parts imply underneath it, and says whether the value in
## the box is authored or derived. `Harness.defaults` is what answers that, for the reason its own
## header gives: a panel recomputing the default would be a second opinion about the aircraft.

## A control changed a value. `key` is one of `Harness`'s six; `value` is an int for a gauge and a
## float for a length. The room records, applies and repaints — see the header.
signal value_edited(key: String, value: Variant)

## A row's "Use default" was pressed. Separate from `value_edited` because clearing an override is
## not the same act as setting one: `Harness` stores absence, and an edit that wrote the default
## back as a number would freeze it at whatever the frame happened to be today.
signal default_restored(key: String)

## The width the wrapped prose is laid out to. `HarnessStub`'s constant and its reason: an
## autowrapping Label reports its whole unwrapped string as its minimum width, and the room's
## columns are fitted from minimums.
const WRAP_WIDTH := 300.0

## The room's own column width. Named here rather than in the room because it is this panel's
## minimum that decides it, and a number owned by the thing it measures cannot drift from it.
const COLUMN_WIDTH := 320.0

## Length in millimetres, bounded by what a harness can physically be. The ceiling is a cinelifter's
## arm plus routing and then some; it is a SANITY bound on a typed number, not a model, and it is
## generous on purpose — `Harness.set_value` deliberately stores unclamped, so anything this box
## refuses is a typo rather than a build.
const LENGTH_MIN_MM := 5.0
const LENGTH_MAX_MM := 600.0
const LENGTH_STEP_MM := 1.0

var _title: Label
var _subtitle: Label
var _gauge_row: HBoxContainer
var _gauge_picker: OptionButton
var _gauge_note: Label
var _length_row: HBoxContainer
var _length_spin: SpinBox
var _length_note: Label
var _facts: Label
var _prompt: Label

## Which of `Harness`'s keys the two controls are currently pointed at, or "" while nothing
## editable is selected. Held so a signal handler knows what it is editing without the row having
## to carry a copy of the key in its own metadata.
var _awg_key := ""
var _length_key := ""


func _init() -> void:
	name = "Harness"
	custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", LothalTheme.SPACE_2)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	add_child(_title)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"SmallLabel"
	add_child(_subtitle)

	_prompt = Label.new()
	_prompt.theme_type_variation = &"MutedLabel"
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	add_child(_prompt)

	_gauge_row = _build_gauge_row()
	add_child(_gauge_row)
	_gauge_note = _note()

	_length_row = _build_length_row()
	add_child(_length_row)
	_length_note = _note()

	_facts = Label.new()
	_facts.theme_type_variation = &"MutedLabel"
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	add_child(_facts)

	show_nothing()


func _build_gauge_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)

	var caption := Label.new()
	caption.text = "Gauge"
	caption.custom_minimum_size = Vector2(56, 0)
	row.add_child(caption)

	# A PICKER AND NOT A SPINBOX. The gauges are a table with holes in it — 12, 14, 16, 18, 20, 22,
	# 24, 26, 28 — and a spinbox stepping by one would offer 19 AWG, which `WireGauge` refuses to
	# invent a row for. A control that can express a value the model rejects is a control that
	# produces a hairline and a warning for a keystroke.
	_gauge_picker = OptionButton.new()
	_gauge_picker.custom_minimum_size = Vector2(96, 0)
	for awg in WireGauge.gauges():
		_gauge_picker.add_item("%d AWG" % int(awg), int(awg))
	_gauge_picker.item_selected.connect(_on_gauge_selected)
	row.add_child(_gauge_picker)

	row.add_child(_default_button(func() -> void: default_restored.emit(_awg_key)))
	return row


func _build_length_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)

	var caption := Label.new()
	caption.text = "Length"
	caption.custom_minimum_size = Vector2(56, 0)
	row.add_child(caption)

	_length_spin = SpinBox.new()
	_length_spin.min_value = LENGTH_MIN_MM
	_length_spin.max_value = LENGTH_MAX_MM
	_length_spin.step = LENGTH_STEP_MM
	_length_spin.suffix = "mm"
	_length_spin.custom_minimum_size = Vector2(96, 0)
	_length_spin.value_changed.connect(_on_length_changed)
	row.add_child(_length_spin)

	row.add_child(_default_button(func() -> void: default_restored.emit(_length_key)))
	return row


func _default_button(action: Callable) -> Button:
	var button := Button.new()
	button.text = "Default"
	button.flat = true
	button.tooltip_text = ("Forget what was typed here and follow the parts again — the value "
		+ "under the box is what that would be.")
	button.pressed.connect(action)
	return button


func _note() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SmallLabel"
	add_child(label)
	return label


# ---------------------------------------------------------------------------
# Rendering — the room hands this panel a state, it never fetches one
# ---------------------------------------------------------------------------

## Nothing is selected. A prompt rather than a blank column: an empty inspector beside a drawing
## reads as a rendering fault, which is the shape `HarnessStub` was written to avoid one level up.
func show_nothing() -> void:
	_awg_key = ""
	_length_key = ""
	_title.text = "Harness"
	_subtitle.text = ""
	_prompt.text = ("Click a wire in the schematic to change its gauge or its length. Every "
		+ "segment is drawn at the gauge and the length this aircraft actually carries.")
	_prompt.visible = true
	_gauge_row.visible = false
	_gauge_note.visible = false
	_length_row.visible = false
	_length_note.visible = false
	_facts.text = ""


## The capacitor. A part, not a segment (§2.1) — so it gets a description and no controls, and the
## panel says WHY rather than showing two greyed boxes that look like a bug.
func show_capacitor(build: Build) -> void:
	_awg_key = ""
	_length_key = ""
	var row := build.harness.capacitor_row(build)
	_title.text = "Capacitor"
	_subtitle.text = String(row.get("name", "none fitted"))
	_prompt.text = ("A capacitor is a part, not a segment: it has no gauge and no length. It is "
		+ "chosen on the rule in the warning list below, and it stands across the ESC's input pads "
		+ "where it is drawn.")
	_prompt.visible = true
	_gauge_row.visible = false
	_gauge_note.visible = false
	_length_row.visible = false
	_length_note.visible = false
	var specs: Dictionary = row.get("specs", {})
	_facts.text = "" if row.is_empty() else "%.0f uF, %.0f V, ESR %.0f mOhm, %.1f g" % [
		float(specs.get("capacitance_uf", 0.0)), float(specs.get("voltage_v", 0.0)),
		float(specs.get("esr_ohm", 0.0)) * 1000.0, float(row.get("mass_g", 0.0))]


## A wire segment: what it is, what it carries, and the two boxes.
##
## `segment` is one entry of `HarnessChecks.segments` — the SAME list the ampacity check walks and
## the schematic draws. The panel does not look a segment up by id and it does not know how many
## there are; it renders the record it is handed, so a segment added to that list one day appears
## here with no edit to this file.
func show_segment(build: Build, segment: Dictionary) -> void:
	var id := String(segment["id"])
	_awg_key = Harness.MAIN_LEAD_AWG if id == "main_lead" else Harness.MOTOR_LEAD_AWG
	_length_key = Harness.MAIN_LEAD_LENGTH_MM if id == "main_lead" \
		else Harness.MOTOR_LEAD_LENGTH_MM

	_title.text = String(segment["label"])
	_subtitle.text = "%d conductors" % int(segment["conductors"])
	_prompt.visible = false
	_gauge_row.visible = true
	_gauge_note.visible = true
	_length_row.visible = true
	_length_note.visible = true

	var awg := int(segment["awg"])
	# `set_pressed_no_signal`'s reason, in the two shapes this panel has: rendering a state must not
	# look like a builder editing it. Without these the room would record an undo step and re-emit
	# `document_changed` every time it repainted, which is an infinite loop with a history in it.
	var index := _gauge_picker.get_item_index(awg)
	if index >= 0:
		_gauge_picker.select(index)
	_length_spin.set_value_no_signal(float(segment["length_mm"]))

	var harness := build.harness
	var defaults := Harness.defaults(build)
	_gauge_note.text = _provenance(harness, _awg_key, "%d AWG" % int(defaults[_awg_key]))
	_length_note.text = _provenance(harness, _length_key,
		"%.0f mm" % float(defaults[_length_key]))

	# WHAT THE TWO NUMBERS BUY, in the units the warning list uses. Read off `WireGauge` — the same
	# table the ampacity check reads — rather than restated here, so a gauge that reads 16 A in the
	# list cannot read 15 A in this panel.
	var length_m := float(segment["length_mm"]) / 1000.0
	_facts.text = "Rated %.1f A. %.1f mOhm per conductor over %.0f mm, %.1f g of wire." % [
		WireGauge.ampacity_a(awg), WireGauge.resistance_ohm(awg, length_m) * 1000.0,
		float(segment["length_mm"]), int(segment["conductors"]) * WireGauge.mass_g(awg, length_m)]


## "yours, the parts say X" or "from the parts". The sentence design §0 asks every rough default to
## carry, and the reason `Harness.defaults` is public.
static func _provenance(harness: Harness, key: String, default_text: String) -> String:
	return "authored — the parts imply %s" % default_text if harness.has_override(key) \
		else "from the parts (%s)" % default_text


func _on_gauge_selected(index: int) -> void:
	if _awg_key == "":
		return
	value_edited.emit(_awg_key, _gauge_picker.get_item_id(index))


func _on_length_changed(value: float) -> void:
	if _length_key == "":
		return
	value_edited.emit(_length_key, value)
