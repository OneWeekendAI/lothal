class_name TestConfigFailsafe
extends RefCounted
## Config room slice C6 — THE FAILSAFE PANEL AND THE THREE CHECKS PREDICTABLE FROM A BUILD.
## Design: plans/2026-09-20-config-room-design.md §4.4.
##
## §4.4's table splits arming and failsafe refusals into two kinds. Most are RUNTIME facts — the
## gyro did not calibrate, the throttle is up, the board is not level — and Lothal cannot predict
## any of them from a build; they are taught, not checked, and that half is C7. Three are
## predictable, and this slice is those three and nothing else:
##
##   GPS RESCUE WITH NO GPS      — a setting in the `config` block against a fitted category.
##                                 §4.4 calls it "the single most useful check in the section".
##   BIDIRECTIONAL DSHOT vs THE  — a setting against `catalog.protocol`, which C4 already reads for
##   ESC'S PROTOCOL                the port budget. C4 deliberately left the SETTING non-existent
##                                 and said so in its own comment; this is the slice where it exists.
##   THE BUZZER THAT DIES WITH   — already built as `_buzzer_dies_with_the_pack`, and §4.4 says it
##   THE PACK                      BELONGS ON THIS SHEET. So C6's buzzer work is surfacing it here,
##                                 not writing it again: a second copy would be a second opinion.
##
## THE ROW'S OWN CLAIM IS "ALL THREE READ FIELDS THAT EXIST", so `_the_fields_all_three_read_exist`
## asserts that against the shipped catalog rather than trusting it — including the uncomfortable
## half, which is that every ESC in the catalog today IS a DShot ESC, so the bidir check is
## unreachable through the picker and reachable only through a custom or an older entry. Saying
## that out loud is the difference between a vacuity guard and a vacuous test.
##
## And the standing rule the panel is written against: a guess may never be presented as measured.
## The stage-2 default is BETAFLIGHT'S, quoted as Betaflight's — §8's fifth row — and the panel has
## to say whose it is for as long as nobody has chosen.

## A protocol with no return path on the signal wire, so bidirectional DShot cannot be what it is.
const NO_RETURN_PROTOCOL := "Multishot"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_the_defaults_and_whose_they_are())
	results.append_array(_an_unknown_setting_is_refused_rather_than_stored())
	results.append_array(_gps_rescue_with_no_gps(catalog))
	results.append_array(_bidir_dshot_against_the_protocol(catalog))
	results.append_array(_the_fields_all_three_read_exist(catalog))
	results.append_array(_the_panel_shows_all_three_and_writes_nothing(catalog))
	results.append_array(_the_room_carries_the_panel_and_the_edit_reaches_the_drone())
	return results


## §8's fifth row: the stage-2 default ships as BETAFLIGHT'S OWN DEFAULT, quoted as Betaflight's
## rather than as Lothal's recommendation — and the moment a builder chooses, the sentence stops
## calling it anybody's default and starts calling it theirs. Provenance is never silent, so an
## untouched drone and a chosen one must not read the same.
static func _the_defaults_and_whose_they_are() -> Array:
	var results: Array = []

	var untouched := {}
	results.append(TestResult.new(
		"an untouched drone's stage 2 is drop, and bidirectional DShot is off",
		FailsafeSettings.stage2(untouched) == FailsafeSettings.DROP
			and not FailsafeSettings.bidir_dshot(untouched),
		"stage2 \"%s\", bidir %s" % [FailsafeSettings.stage2(untouched),
			FailsafeSettings.bidir_dshot(untouched)]))

	var default_sentence := FailsafeSettings.stage2_sentence(untouched)
	results.append(TestResult.new(
		"and the untouched sentence says the default is BETAFLIGHT'S, not Lothal's recommendation",
		default_sentence.to_lower().contains("betaflight")
			and FailsafeSettings.stage2_provenance(untouched) == FailsafeSettings.BETAFLIGHT_DEFAULT,
		"\"%s\" / provenance \"%s\"" % [default_sentence,
			FailsafeSettings.stage2_provenance(untouched)]))

	var chosen := {}
	FailsafeSettings.set_stage2(chosen, FailsafeSettings.LAND)
	var chosen_sentence := FailsafeSettings.stage2_sentence(chosen)
	results.append(TestResult.new(
		"and once chosen it is the builder's setting, no longer quoted as anyone's default",
		FailsafeSettings.stage2(chosen) == FailsafeSettings.LAND
			and FailsafeSettings.stage2_provenance(chosen) == FailsafeSettings.CHOSEN
			and not chosen_sentence.to_lower().contains("default"),
		"\"%s\" / provenance \"%s\"" % [chosen_sentence,
			FailsafeSettings.stage2_provenance(chosen)]))

	var toggled := {}
	FailsafeSettings.set_bidir_dshot(toggled, true)
	results.append(TestResult.new(
		"and bidirectional DShot stores as the boolean it is, and clears back off",
		FailsafeSettings.bidir_dshot(toggled),
		"config %s" % [toggled]))
	FailsafeSettings.set_bidir_dshot(toggled, false)
	# `has`, not just the reader: storing `false` would read the same through `bidir_dshot` and
	# would put an opinion into every drone's file that nobody expressed.
	results.append(TestResult.new(
		"and turning it back off leaves no setting behind claiming otherwise",
		not FailsafeSettings.bidir_dshot(toggled)
			and not toggled.has(FailsafeSettings.BIDIR_KEY), "config %s" % [toggled]))

	return results


## Never invent. A value that is not one of the three stage-2 behaviours is not stored, because a
## stored one would reach the check and be cross-examined against a build as though a builder had
## chosen it — and the honest response to nonsense is the default, said as the default.
static func _an_unknown_setting_is_refused_rather_than_stored() -> Array:
	var config := {}
	FailsafeSettings.set_stage2(config, "teleport_home")
	return [TestResult.new(
		"a stage-2 value that is not one of the three is refused, not stored",
		not config.has(FailsafeSettings.STAGE2_KEY)
			and FailsafeSettings.stage2(config) == FailsafeSettings.DROP,
		"config %s, reads \"%s\"" % [config, FailsafeSettings.stage2(config)])]


## §4.4's single most useful check. It is a cross-section between a panel and the fitted parts, and
## both halves matter: it fires when the rescue has nothing to navigate with, and it is silent both
## when a GPS is fitted and when the rescue was never asked for.
static func _gps_rescue_with_no_gps(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var rescue := {}
	FailsafeSettings.set_stage2(rescue, FailsafeSettings.GPS_RESCUE)
	var warning := _warning(_build(catalog, {}, rescue), &"failsafe_gps_rescue_no_gps")

	results.append(TestResult.new(
		"GPS rescue with no GPS fitted is warned about",
		warning != null, "warning: %s" % ["<missing>" if warning == null else warning.message]))
	results.append(TestResult.new(
		"and it says what the rescue cannot do rather than naming a firmware flag it has not checked",
		warning != null and warning.message.to_lower().contains("gps")
			and warning.message.to_lower().contains("position"),
		"message: %s" % ["<missing>" if warning == null else warning.message]))
	results.append(TestResult.new(
		"and it is limiting — the aircraft flies, so it must not be read as impossible",
		warning != null and warning.severity == BuildWarning.Severity.LIMITING,
		"severity %s" % [-1 if warning == null else warning.severity]))
	results.append(TestResult.new(
		"and `values` carries the setting and the missing part, for the sheet that reads values",
		warning != null and String(warning.values.get("failsafe_stage2", "")) == FailsafeSettings.GPS_RESCUE
			and warning.values.get("gps_fitted", true) == false,
		"values: %s" % [{} if warning == null else warning.values]))

	var with_gps := _build(catalog, {"receiver": "rx_elrs_2400", "gps": "gps_micro_flat"}, rescue)
	results.append(TestResult.new(
		"a build that HAS a GPS is told nothing — the rescue can do what it was asked",
		_warning(with_gps, &"failsafe_gps_rescue_no_gps") == null, "fired anyway"))

	results.append(TestResult.new(
		"and a drone on the default drop with no GPS is told nothing either",
		_warning(_build(catalog, {}, {}), &"failsafe_gps_rescue_no_gps") == null,
		"fired on a build that never asked for a rescue"))

	return results


## The setting C4 said did not exist yet, now cross-examined against `catalog.protocol` — the field
## the port budget already reads, so this needs no catalog work at all.
static func _bidir_dshot_against_the_protocol(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var on := {}
	FailsafeSettings.set_bidir_dshot(on, true)

	var multishot := _build(catalog, {}, on)
	multishot.esc = multishot.esc.duplicate(true)
	(multishot.esc["catalog"] as Dictionary)["protocol"] = NO_RETURN_PROTOCOL
	var warning := _warning(multishot, &"bidir_dshot_unsupported")
	results.append(TestResult.new(
		"bidirectional DShot asked for on a %s ESC is warned about" % NO_RETURN_PROTOCOL,
		warning != null, "warning: %s" % ["<missing>" if warning == null else warning.message]))
	results.append(TestResult.new(
		"and it quotes the protocol it read, rather than asserting a capability in the abstract",
		warning != null and warning.message.contains(NO_RETURN_PROTOCOL),
		"message: %s" % ["<missing>" if warning == null else warning.message]))
	results.append(TestResult.new(
		"and `values` carries the protocol beside the setting",
		warning != null and String(warning.values.get("protocol", "")) == NO_RETURN_PROTOCOL
			and warning.values.get("bidir_dshot", false) == true,
		"values: %s" % [{} if warning == null else warning.values]))

	var dshot := _build(catalog, {}, on)
	results.append(TestResult.new(
		"a DShot ESC with the same setting is told nothing — it can do what was asked",
		_warning(dshot, &"bidir_dshot_unsupported") == null,
		"fired on %s" % [(dshot.esc.get("catalog", {}) as Dictionary).get("protocol", "?")]))

	var silent := _build(catalog, {}, on)
	silent.esc = silent.esc.duplicate(true)
	(silent.esc["catalog"] as Dictionary)["protocol"] = ""
	var unknown := _warning(silent, &"bidir_dshot_unsupported")
	results.append(TestResult.new(
		"an ESC publishing NO protocol still gets a word, erring the way the port budget errs",
		unknown != null and unknown.message.to_lower().contains("publish"),
		"message: %s" % ["<missing>" if unknown == null else unknown.message]))

	var off := _build(catalog, {}, {})
	off.esc = off.esc.duplicate(true)
	(off.esc["catalog"] as Dictionary)["protocol"] = NO_RETURN_PROTOCOL
	results.append(TestResult.new(
		"and with the setting off, a %s ESC is nobody's problem" % NO_RETURN_PROTOCOL,
		_warning(off, &"bidir_dshot_unsupported") == null, "fired with the setting off"))

	return results


## THE C6 ROW'S OWN CLAIM, asserted against the shipped data: all three checks read fields that
## already exist. Two of them are catalog fields and one is a category, and the honest third
## sentence is that no ESC in the catalog can fail the bidir check today.
static func _the_fields_all_three_read_exist(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var escs := catalog.list_category("esc")
	var all_publish := not escs.is_empty()
	var all_dshot := true
	for entry in escs:
		var protocol := str((entry.get("catalog", {}) as Dictionary).get("protocol", ""))
		if protocol.is_empty():
			all_publish = false
		if not protocol.to_lower().begins_with(ControlPlausibility.DSHOT_PREFIX):
			all_dshot = false
	results.append(TestResult.new(
		"every ESC entry publishes the `protocol` the bidir check reads",
		all_publish, "%d ESCs" % escs.size()))
	results.append(TestResult.new(
		"and every one of them is a DShot ESC, so the check is reachable only via a custom entry",
		all_dshot, "a non-DShot catalog ESC exists; this note is now stale"))

	results.append(TestResult.new(
		"the gps category the rescue check reads is populated",
		not catalog.list_category("gps").is_empty(), "no gps entries"))

	var buzzers := catalog.list_category("buzzer")
	var all_declare := not buzzers.is_empty()
	for entry in buzzers:
		if not (entry.get("specs", {}) as Dictionary).has("self_powered"):
			all_declare = false
	results.append(TestResult.new(
		"and every buzzer declares the `self_powered` the third check reads",
		all_declare, "%d buzzers" % buzzers.size()))

	return results


## The panel. Three requirements, and each is a different failure it prevents:
##   it shows all three checks, INCLUDING the one that lives in ControlPlausibility — §4.4 says the
##     buzzer belongs on this sheet, and a panel that showed only its own module's warnings would
##     quietly drop it;
##   it announces edits rather than writing them, on ConfigMotorsPanel's rule;
##   it shows whose the default is for as long as nobody has chosen.
static func _the_panel_shows_all_three_and_writes_nothing(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var config := {}
	FailsafeSettings.set_stage2(config, FailsafeSettings.GPS_RESCUE)
	FailsafeSettings.set_bidir_dshot(config, true)
	var build := _build(catalog, {"receiver": "rx_elrs_2400", "buzzer": "buzz_active_5v"}, config)
	build.esc = build.esc.duplicate(true)
	(build.esc["catalog"] as Dictionary)["protocol"] = NO_RETURN_PROTOCOL

	var panel := ConfigFailsafePanel.new()
	var stage_edits: Array = []
	var bidir_edits: Array = []
	panel.failsafe_stage2_edited.connect(func(value: String) -> void: stage_edits.append(value))
	panel.bidir_dshot_edited.connect(func(on: bool) -> void: bidir_edits.append(on))
	panel.render(build)

	var shown := panel.warning_text().to_lower()
	results.append(TestResult.new(
		"the Failsafe panel shows the GPS-rescue check",
		shown.contains("rescue"), "shown: %s" % [panel.warning_text()]))
	results.append(TestResult.new(
		"and the bidirectional-DShot check",
		shown.contains("dshot"), "shown: %s" % [panel.warning_text()]))
	results.append(TestResult.new(
		"and the buzzer check, which lives in another module and still belongs on this sheet",
		shown.contains("buzzer"), "shown: %s" % [panel.warning_text()]))
	results.append(TestResult.new(
		"and nothing else — an unrelated build warning does not leak onto the failsafe sheet",
		not shown.contains("serial port"), "shown: %s" % [panel.warning_text()]))

	results.append(TestResult.new(
		"and it shows the settings the drone was opened with, not the defaults",
		panel.selected_stage2() == FailsafeSettings.GPS_RESCUE and panel.bidir_enabled(),
		"stage2 \"%s\", bidir %s" % [panel.selected_stage2(), panel.bidir_enabled()]))

	# The signals a mouse would send. Assigning to an OptionButton or a CheckBox headlessly
	# announces nothing, so these drive the controls' own signals — which is the wiring that breaks.
	var land_index := -1
	for i in FailsafeSettings.STAGE2_CHOICES.size():
		if String(FailsafeSettings.STAGE2_CHOICES[i]["value"]) == FailsafeSettings.LAND:
			land_index = i
	panel.stage2_chooser().item_selected.emit(land_index)
	panel.bidir_box().toggled.emit(false)
	results.append(TestResult.new(
		"and choosing a behaviour announces it rather than writing it into the build",
		stage_edits == [FailsafeSettings.LAND]
			and String(build.config[FailsafeSettings.STAGE2_KEY]) == FailsafeSettings.GPS_RESCUE,
		"emitted %s, config %s" % [stage_edits, build.config]))
	results.append(TestResult.new(
		"and so does the bidirectional-DShot box",
		bidir_edits == [false] and FailsafeSettings.bidir_dshot(build.config),
		"emitted %s, config %s" % [bidir_edits, build.config]))

	panel.render(_build(catalog, {"receiver": "rx_elrs_2400"}, {}))
	results.append(TestResult.new(
		"and on an untouched drone it says the default is Betaflight's, not Lothal's advice",
		panel.provenance_text().to_lower().contains("betaflight"),
		"provenance row: %s" % [panel.provenance_text()]))

	panel.free()
	return results


## §7's wiring, both halves in one edit as the P10f lesson asks: the panel is in the room's list and
## the edit made in it reaches the drone's `config` block through LabScreen, which is the only
## writer.
static func _the_room_carries_the_panel_and_the_edit_reaches_the_drone() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Failsafed"))
	shell.select_system_by_name("Config")

	var shown: Array = []
	for i in shell.lab.panels.get_tab_count():
		if not shell.lab.panels.is_tab_hidden(i):
			shown.append(shell.lab.panels.get_tab_title(i))
	results.append(TestResult.new(
		"selecting Config shows Motors, Ports, Failsafe, Rates and Sheet, and nothing else",
		shown == ["Motors", "Ports", "Failsafe", "Rates", "Sheet"], "showing %s" % [shown]))

	shell.lab.failsafe_panel.failsafe_stage2_edited.emit(FailsafeSettings.GPS_RESCUE)
	results.append(TestResult.new(
		"a failsafe choice made in the panel lands in the drone's config block",
		FailsafeSettings.stage2(shell.lab.config) == FailsafeSettings.GPS_RESCUE,
		"config %s" % [shell.lab.config]))

	# The panel must SHOW the new setting too, which it only can if the room re-rendered it. A
	# writer wired without a render leaves a builder looking at the choice they just replaced.
	results.append(TestResult.new(
		"and the panel is re-rendered with it, rather than still showing the old choice",
		shell.lab.failsafe_panel.selected_stage2() == FailsafeSettings.GPS_RESCUE,
		"panel shows \"%s\"" % [shell.lab.failsafe_panel.selected_stage2()]))

	shell.lab.failsafe_panel.bidir_dshot_edited.emit(true)
	results.append(TestResult.new(
		"and so does the bidirectional-DShot setting",
		FailsafeSettings.bidir_dshot(shell.lab.config), "config %s" % [shell.lab.config]))

	shell.free()
	return results


static func _build(catalog: PartsCatalog, components: Dictionary, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, components)
	build.set_config(config)
	return build


## Every check C6 adds lives in ConfigPlausibility, so that is what is asked — not `build.warnings()`,
## which would let a check pass here while never being registered.
static func _warning(build: Build, id: StringName) -> BuildWarning:
	for warning in ConfigPlausibility.warnings_for(build):
		if warning.id == id:
			return warning
	return null
