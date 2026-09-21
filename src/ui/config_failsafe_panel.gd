class_name ConfigFailsafePanel
extends PanelContainer
## Config's Failsafe panel: what this aircraft does when the link drops, whether bidirectional
## DShot was asked for, and the three things that are wrong with those answers given what is
## actually fitted — Config room slice C6 (plans/2026-09-20-config-room-design.md §4.4).
##
## THE PANEL WRITES NOTHING, on ConfigMotorsPanel's and ConfigPortsPanel's rule: each edit
## announces itself and LabScreen writes it into the drone's `config` block, so every value lives
## in exactly one place.
##
## ---------------------------------------------------------------------------
## WHY THIS PANEL SHOWS A WARNING THAT IS NOT ITS OWN MODULE'S
## ---------------------------------------------------------------------------
##
## §4.4's table names three refusals predictable from a build, and one of them — the buzzer that
## goes silent when the pack ejects — WAS ALREADY BUILT, in `ControlPlausibility`. The design says
## it "belongs on this sheet", and the tempting alternative was to write a second copy of it here.
## That would be a second opinion about one fact, which is the failure the whole project's
## one-accessor rule exists to prevent. So this panel reads BOTH modules and shows the three ids it
## is about, by name.
##
## Reading both modules and filtering by id rather than dumping everything is deliberate in the
## other direction too: the serial-port row is a Ports question, and a failsafe sheet that repeated
## it would be a sheet a builder stops reading.
##
## THE DEFAULT SAYS WHOSE IT IS. Drop is Betaflight's default, not Lothal's recommendation, and the
## provenance line is `FailsafeSettings`'s own sentence pasted whole — never re-written here from
## the value, because that is exactly how a quoted default comes to read as advice.
##
## WHAT IT REFUSES: showing the failsafe happen. §4.4 — receivers are physics-inert, so there is no
## link to drop. The runtime arming refusals (throttle up, not level, gyro calibrating) are taught
## rather than checked: C7 added that half below the warnings, as `ArmingNotes`' prose, and it is
## deliberately the one thing on this sheet `render` does not touch.

## The three checks this sheet is about, by id. Two are C6's own and one is C4's, and the list is
## the reason both modules are asked.
const SHOWN_WARNINGS := [&"failsafe_gps_rescue_no_gps", &"bidir_dshot_unsupported",
	&"buzzer_not_self_powered"]

signal failsafe_stage2_edited(value: String)
signal bidir_dshot_edited(on: bool)

var _chooser: OptionButton
var _provenance: Label
var _bidir: CheckBox
var _warnings: WarningList
## The arming list. Static prose, written once in `_init` and never touched by `render` — see
## ArmingNotes, and C7's note above.
var _arming: Label
var _updating := false


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
	title.text = "FAILSAFE"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = ("What this aircraft does when the link drops. Lothal cannot show it happening — "
		+ "there is no radio link to lose in the sim — but it can tell you when the behaviour you "
		+ "chose needs something this build does not carry.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)

	root.add_child(HSeparator.new())

	_chooser = OptionButton.new()
	for choice in FailsafeSettings.STAGE2_CHOICES:
		_chooser.add_item(String(choice["label"]))
	_chooser.item_selected.connect(_on_stage2)
	root.add_child(_chooser)

	_provenance = Label.new()
	_provenance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_provenance.custom_minimum_size = Vector2(280, 0)
	_provenance.theme_type_variation = &"MutedLabel"
	root.add_child(_provenance)

	root.add_child(HSeparator.new())

	_bidir = CheckBox.new()
	_bidir.text = "Bidirectional DShot"
	_bidir.toggled.connect(_on_bidir)
	root.add_child(_bidir)

	var bidir_note := Label.new()
	bidir_note.text = ("Rpm back down the signal wire, and the RPM filtering that rides on it. "
		+ "Your ESC's protocol decides whether it can.")
	bidir_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bidir_note.custom_minimum_size = Vector2(280, 0)
	bidir_note.theme_type_variation = &"MutedLabel"
	root.add_child(bidir_note)

	_warnings = WarningList.new(280)
	root.add_child(_warnings)

	# THE TEACHING HALF (C7). §4.4: "the section has two halves and they must look different on
	# screen." The checks above move with the build; this does not, and it is built HERE, in
	# `_init`, rather than in `render` — so there is no code path by which a build could reach it
	# and no way for it to drift into a verdict. The test asserts the two halves apart by rendering
	# two builds that disagree about every check and requiring identical arming text.
	root.add_child(HSeparator.new())

	var arming_title := Label.new()
	arming_title.text = "IF IT WON'T ARM"
	arming_title.theme_type_variation = &"TitleLabel"
	root.add_child(arming_title)

	_arming = Label.new()
	_arming.text = ArmingNotes.preamble() + "\n\n" + "\n\n".join(ArmingNotes.lines())
	_arming.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arming.custom_minimum_size = Vector2(280, 0)
	_arming.theme_type_variation = &"MutedLabel"
	root.add_child(_arming)


## Shows this build's failsafe configuration and what is wrong with it. Every value read through
## `FailsafeSettings` and every check through the two modules that own them, so the panel cannot
## come to disagree with the warning pins on the model.
func render(build: Build) -> void:
	_updating = true
	var in_force := FailsafeSettings.stage2(build.config)
	for i in FailsafeSettings.STAGE2_CHOICES.size():
		if String(FailsafeSettings.STAGE2_CHOICES[i]["value"]) == in_force:
			_chooser.select(i)
	_bidir.set_pressed_no_signal(FailsafeSettings.bidir_dshot(build.config))
	_updating = false

	_provenance.text = FailsafeSettings.stage2_sentence(build.config)

	var entries: Array[BuildWarning] = []
	for warning in ConfigPlausibility.warnings_for(build):
		if SHOWN_WARNINGS.has(warning.id):
			entries.append(warning)
	for warning in ControlPlausibility.warnings_for(build):
		if SHOWN_WARNINGS.has(warning.id):
			entries.append(warning)
	_warnings.show_warnings(entries)


## The behaviour showing in the chooser.
func selected_stage2() -> String:
	var index := _chooser.selected
	if index < 0 or index >= FailsafeSettings.STAGE2_CHOICES.size():
		return ""
	return String(FailsafeSettings.STAGE2_CHOICES[index]["value"])


func bidir_enabled() -> bool:
	return _bidir.button_pressed


## The sentence that says whose the setting is. Read by the test that holds this panel to §8's
## fifth row.
func provenance_text() -> String:
	return _provenance.text


## The teaching half, as it reads on screen. Held to being the same for every build.
func arming_text() -> String:
	return _arming.text


func warning_text() -> String:
	return _warnings.ordered_text() if _warnings.visible else ""


## The controls themselves, so a headless check can drive the signals a mouse would. An
## OptionButton selected or a CheckBox pressed in code announces nothing, so the connection between
## each control and this panel's own signal is otherwise untestable outside a window — and that
## connection is the thing that breaks.
func stage2_chooser() -> OptionButton:
	return _chooser


func bidir_box() -> CheckBox:
	return _bidir


func _on_stage2(index: int) -> void:
	if _updating or index < 0 or index >= FailsafeSettings.STAGE2_CHOICES.size():
		return
	failsafe_stage2_edited.emit(String(FailsafeSettings.STAGE2_CHOICES[index]["value"]))


func _on_bidir(on: bool) -> void:
	if _updating:
		return
	bidir_dshot_edited.emit(on)
