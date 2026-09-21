class_name ConfigRatesPanel
extends PanelContainer
## Config's Rates panel: the rate this aircraft is meant to fly, the expo that goes on the radio,
## and THE SENTENCE THAT SAYS WHERE THE SIM STOPS BEING THIS AIRCRAFT — Config room slice C8
## (plans/2026-09-20-config-room-design.md §2.3, §4.1).
##
## THE PANEL WRITES NOTHING, on ConfigMotorsPanel's, ConfigPortsPanel's and ConfigFailsafePanel's
## rule: each edit announces itself and LabScreen writes it into the drone's `config` block, so
## every value lives in exactly one place.
##
## EVERY SENTENCE IS `RateSettings`' OWN, PASTED WHOLE. None of them is re-written here from the
## value. That is the same instruction `ConfigFailsafePanel` carries about Betaflight's default and
## it matters more here, because the number this panel shows is the one a builder is most likely to
## mistake for a measurement of their aircraft.
##
## THE MODES HALF TEACHES AND DOES NOT REPORT, exactly as C7's arming list does: it is built in
## `_init` and `render` never touches it, so there is no code path by which a build could reach it
## and turn it into a verdict. The test asserts the two halves apart by rendering two builds that
## disagree about the rate and requiring identical modes prose.
##
## WHAT IT REFUSES: filter configuration — gyro and D-term lowpass, RPM filtering, dynamic notch.
## §4.1 and §9. Lothal models a gyro and a PT1; a notch recommendation would be a construction
## wearing a measurement's confidence, and it would be typed into a real quad and flown. Named here
## so its absence is a decision rather than an omission. The PID tune is refused too, and for a
## different reason: it is not missing, it lives under Control (§2.3).

signal max_rate_edited(deg_s: float)
signal expo_edited(value: float)

var _rate_field: SpinBox
var _rate_row: Label
var _statement: Label
var _expo_field: SpinBox
var _expo_row: Label
## The modes half. Static prose, written once in `_init` and never touched by `render`.
var _modes: Label


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	AssemblyPanel._padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "RATES & MODES"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = ("How fast full stick turns the aircraft. This is a pilot's number rather than the "
		+ "airframe's — the same on every quad you own — which is why it is here and the PID tune "
		+ "is under Control.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	_rate_field = SpinBox.new()
	_rate_field.min_value = 0.0
	_rate_field.max_value = RateSettings.MAX_SETTABLE_DEG_S
	_rate_field.step = 10.0
	_rate_field.suffix = "deg/s"
	_rate_field.value_changed.connect(_on_rate)
	root.add_child(_rate_field)

	_rate_row = Label.new()
	_rate_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rate_row.custom_minimum_size = Vector2(280, 0)
	_rate_row.theme_type_variation = &"MutedLabel"
	root.add_child(_rate_row)

	_statement = Label.new()
	_statement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_statement.custom_minimum_size = Vector2(280, 0)
	root.add_child(_statement)

	root.add_child(HSeparator.new())

	_expo_field = SpinBox.new()
	_expo_field.min_value = 0.0
	_expo_field.max_value = 1.0
	_expo_field.step = 0.05
	_expo_field.prefix = "Expo"
	_expo_field.value_changed.connect(_on_expo)
	root.add_child(_expo_field)

	_expo_row = Label.new()
	_expo_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_expo_row.custom_minimum_size = Vector2(280, 0)
	_expo_row.theme_type_variation = &"MutedLabel"
	root.add_child(_expo_row)

	root.add_child(HSeparator.new())

	var modes_title := Label.new()
	modes_title.text = "MODES"
	modes_title.theme_type_variation = &"TitleLabel"
	root.add_child(modes_title)

	_modes = Label.new()
	_modes.text = RateSettings.modes_sentence()
	_modes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modes.custom_minimum_size = Vector2(280, 0)
	_modes.theme_type_variation = &"MutedLabel"
	root.add_child(_modes)


## Shows this build's rates. Every value and every sentence read through `RateSettings`, so the
## panel cannot come to disagree with the config sheet about what this aircraft is set to.
func render(build: Build) -> void:
	# `set_value_no_signal`, on ConfigPortsPanel's precedent: showing what is stored is not the
	# builder editing it, and a plain assignment here would announce an edit nobody made — which,
	# with LabScreen writing what this panel announces, is a panel that edits the build by being
	# looked at. It cannot be caught headless (a Range outside the tree emits nothing), which is
	# exactly why it is written the safe way rather than guarded by a flag and hoped about.
	_rate_field.set_value_no_signal(RateSettings.intended_max_rate_deg_s(build.config))
	_expo_field.set_value_no_signal(RateSettings.expo(build.config))

	_rate_row.text = RateSettings.max_rate_sentence(build.config)
	_statement.text = RateSettings.sim_versus_real_sentence(build.config)
	_expo_row.text = RateSettings.expo_sentence(build.config)


## The rate row, with its provenance. Read by the test that holds the panel to pasting rather than
## re-writing.
func rate_text() -> String:
	return _rate_row.text


## The sim-versus-real statement, as it reads on screen.
func sim_versus_real_text() -> String:
	return _statement.text


func expo_text() -> String:
	return _expo_row.text


## The teaching half. Held to being the same for every build.
func modes_text() -> String:
	return _modes.text


func field_value() -> float:
	return _rate_field.value


func expo_value() -> float:
	return _expo_field.value


## The controls themselves, so a headless check can drive the signals a mouse would: a `Range`
## assigned in code announces nothing, so the connection between each box and this panel's own
## signal is otherwise untestable outside a window — and that connection is the thing that breaks.
func rate_field() -> SpinBox:
	return _rate_field


func expo_field() -> SpinBox:
	return _expo_field


func _on_rate(value: float) -> void:
	max_rate_edited.emit(value)


func _on_expo(value: float) -> void:
	expo_edited.emit(value)
