class_name TestConfigRates
extends RefCounted
## Config room slice C8 — RATES AND MODES, and the sim-versus-real max-rate statement. Design:
## plans/2026-09-20-config-room-design.md §2.3 and §4.1.
##
## §2.3's split is settled: the PID tune stays under Control, because a gain is a property of THIS
## airframe's plant, and Config takes rates, because a rate is a property of the PILOT — the same
## numbers on every quad they own. So this slice adds no derivation and no second tune panel. What
## it adds is the small, true thing §4.1 asks for: the max rate the sim flies, the rate the builder
## intends to fly on the real aircraft, and THE SENTENCE THAT SAYS WHEN THE TWO DIFFER.
##
## THAT SENTENCE IS THE HONESTY SEAM OF THE SLICE, and most of what is asserted below defends it.
## Lothal's whole inner loop is normalised against `RateModeController.MAX_RATE_RAD_S`, and a
## builder who flies the sim and then flies their quad at a different max rate meets an aircraft
## that feels nothing like the one they practised on. A panel that printed the intended rate alone
## would imply the sim flies it. So:
##
##   THE SIM'S FIGURE IS DERIVED, NEVER RESTATED. `sim_max_rate_deg_s()` comes off
##     `RateModeController.MAX_RATE_RAD_S`, so the statement cannot go stale the day the loop's
##     normalisation moves. A restated 800 would pass every wording check below while lying.
##
##   PROVENANCE IS NEVER SILENT. An untouched build reads as the SIM's number, labelled as the
##     sim's; a set one reads as the builder's. Those are different kinds of claim, exactly as
##     `FailsafeSettings` separates Betaflight's default from a chosen behaviour, and the panel
##     pastes the sentence whole rather than writing its own from the value.
##
##   EXPO IS CARRIED BUT NOT MODELLED, and it says so. The sim flies a linear stick. Storing an
##     expo the sim does not apply is useful — it belongs on the config sheet — and printing it
##     without that admission would be a guess wearing a measurement's clothes.
##
##   THE MODES TAUGHT ARE THE MODES FLOWN. Lothal has exactly two, and the taught list is asserted
##     against `FlightController.Mode`'s own keys rather than a hand-written pair, so the room
##     cannot come to advertise a mode the sim does not have.
##
## WARN, NEVER BLOCK, and never store nonsense: a rate of zero or 9000 is not stored, because a
## stored one would reach the statement looking exactly like something the builder chose.


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_the_sims_figure_is_derived_from_the_loop_itself())
	results.append_array(_an_untouched_build_reads_as_the_sims_number_and_says_so())
	results.append_array(_a_chosen_rate_is_the_builders_and_reads_differently())
	results.append_array(_nonsense_is_not_stored())
	results.append_array(_the_statement_says_plainly_when_the_two_differ())
	results.append_array(_expo_is_stored_and_admits_the_sim_ignores_it())
	results.append_array(_the_modes_taught_are_the_modes_flown())
	results.append_array(_the_panel_shows_the_statement_and_edits_the_rate(catalog))
	return results


## The sim's number is the loop's number. Asserted as an equality against
## `RateModeController.MAX_RATE_RAD_S` converted, so a literal cannot impersonate it.
static func _the_sims_figure_is_derived_from_the_loop_itself() -> Array:
	var results: Array = []
	var expected := rad_to_deg(RateModeController.MAX_RATE_RAD_S)

	results.append(TestResult.new(
		"the sim's max rate is derived from the loop's own normalisation, not restated",
		absf(RateSettings.sim_max_rate_deg_s() - expected) < 0.001,
		"%.4f against %.4f" % [RateSettings.sim_max_rate_deg_s(), expected]))

	return results


static func _an_untouched_build_reads_as_the_sims_number_and_says_so() -> Array:
	var results: Array = []
	var config := {}

	results.append(TestResult.new(
		"a build with no rate set reads as the rate the sim flies",
		absf(RateSettings.intended_max_rate_deg_s(config) - RateSettings.sim_max_rate_deg_s()) < 0.001,
		"%.2f" % [RateSettings.intended_max_rate_deg_s(config)]))

	results.append(TestResult.new(
		"and carries the SIM's provenance rather than the builder's",
		RateSettings.max_rate_provenance(config) == RateSettings.SIM_DEFAULT
			and RateSettings.SIM_DEFAULT != RateSettings.CHOSEN,
		"provenance %s" % [RateSettings.max_rate_provenance(config)]))

	var sentence := RateSettings.max_rate_sentence(config).to_lower()
	results.append(TestResult.new(
		"and its sentence says the number is the sim's and invites the builder to set their own",
		sentence.contains("sim") and sentence.contains("set"),
		"sentence: %s" % [RateSettings.max_rate_sentence(config)]))

	return results


static func _a_chosen_rate_is_the_builders_and_reads_differently() -> Array:
	var results: Array = []

	var config := {}
	RateSettings.set_max_rate_deg_s(config, 1000.0)
	results.append(TestResult.new(
		"a rate the builder set is the rate that comes back",
		absf(RateSettings.intended_max_rate_deg_s(config) - 1000.0) < 0.001,
		"%.2f" % [RateSettings.intended_max_rate_deg_s(config)]))

	results.append(TestResult.new(
		"and it carries a DIFFERENT provenance from the sim's default it replaced",
		RateSettings.max_rate_provenance(config) == RateSettings.CHOSEN,
		"provenance %s" % [RateSettings.max_rate_provenance(config)]))

	var sentence := RateSettings.max_rate_sentence(config).to_lower()
	results.append(TestResult.new(
		"and its sentence says the figure is the builder's own, not the sim's default",
		sentence.contains("your") and not sentence.contains("set yours here"),
		"sentence: %s" % [RateSettings.max_rate_sentence(config)]))

	# Setting the sim's own number is still a CHOICE, and must not be silently demoted to the
	# default — the whole point of the split is that the two are different kinds of claim.
	var same := {}
	RateSettings.set_max_rate_deg_s(same, RateSettings.sim_max_rate_deg_s())
	results.append(TestResult.new(
		"and choosing the sim's own figure is still a choice, not a silent fallback to default",
		RateSettings.max_rate_provenance(same) == RateSettings.CHOSEN,
		"provenance %s, config %s" % [RateSettings.max_rate_provenance(same), same]))

	# Zero clears it, the way a zero port override does: a build with no opinion and a build
	# carrying "0 deg/s" are not the same aircraft, and only one of them exists.
	var cleared := {}
	RateSettings.set_max_rate_deg_s(cleared, 900.0)
	RateSettings.set_max_rate_deg_s(cleared, 0.0)
	results.append(TestResult.new(
		"and a zero clears the override rather than storing an aircraft that cannot rotate",
		not cleared.has(RateSettings.MAX_RATE_KEY)
			and RateSettings.max_rate_provenance(cleared) == RateSettings.SIM_DEFAULT,
		"config %s" % [cleared]))

	return results


## Nonsense never reaches the statement. A stored 9000 would print as confidently as a real number.
static func _nonsense_is_not_stored() -> Array:
	var results: Array = []

	var negative := {}
	RateSettings.set_max_rate_deg_s(negative, -120.0)
	results.append(TestResult.new(
		"a negative max rate is refused rather than stored",
		not negative.has(RateSettings.MAX_RATE_KEY), "config %s" % [negative]))

	var absurd := {}
	RateSettings.set_max_rate_deg_s(absurd, 9000.0)
	results.append(TestResult.new(
		"and a rate beyond anything a quad flies is refused rather than stored",
		not absurd.has(RateSettings.MAX_RATE_KEY), "config %s" % [absurd]))

	var ok := {}
	RateSettings.set_max_rate_deg_s(ok, RateSettings.MAX_SETTABLE_DEG_S)
	results.append(TestResult.new(
		"and the top of the admissible band IS stored, so the guard is a band not a ceiling of one",
		ok.has(RateSettings.MAX_RATE_KEY), "config %s" % [ok]))

	return results


## §4.1's sentence, and the reason this slice exists.
static func _the_statement_says_plainly_when_the_two_differ() -> Array:
	var results: Array = []

	var agreeing := {}
	RateSettings.set_max_rate_deg_s(agreeing, RateSettings.sim_max_rate_deg_s())
	var agreed := RateSettings.sim_versus_real_sentence(agreeing).to_lower()
	results.append(TestResult.new(
		"when the intended rate IS the sim's, the statement says the two agree",
		agreed.contains("agree") or agreed.contains("same"),
		"sentence: %s" % [RateSettings.sim_versus_real_sentence(agreeing)]))

	var config := {}
	RateSettings.set_max_rate_deg_s(config, 400.0)
	var differing := RateSettings.sim_versus_real_sentence(config)
	var lower := differing.to_lower()

	# BOTH NUMBERS, OR IT IS NOT A COMPARISON. A statement naming only the aircraft's figure is
	# exactly the implication this slice exists to prevent.
	results.append(TestResult.new(
		"when they differ the statement names the SIM's figure",
		differing.contains("%d" % [roundi(RateSettings.sim_max_rate_deg_s())]),
		"sentence: %s" % [differing]))

	results.append(TestResult.new(
		"and names the aircraft's intended figure beside it",
		differing.contains("400"), "sentence: %s" % [differing]))

	results.append(TestResult.new(
		"and says whose the sim's number is, rather than implying the sim flies the aircraft's",
		lower.contains("sim") and (lower.contains("not your") or lower.contains("not the aircraft")),
		"sentence: %s" % [differing]))

	# The differing and agreeing statements must not be the same sentence, or the comparison is
	# printed rather than computed.
	results.append(TestResult.new(
		"and the two cases really do read differently, so the statement is computed not printed",
		differing != RateSettings.sim_versus_real_sentence(agreeing),
		"differ: %s" % [differing]))

	# A faster-than-sim aircraft is the OTHER direction of the same error, and must read as such
	# rather than as the slower case with a number swapped in.
	var fast := {}
	RateSettings.set_max_rate_deg_s(fast, 1600.0)
	var fast_text := RateSettings.sim_versus_real_sentence(fast)
	results.append(TestResult.new(
		"and an aircraft set FASTER than the sim is described as faster, not as slower",
		fast_text.to_lower().contains("faster") and differing.to_lower().contains("slower"),
		"fast: %s / slow: %s" % [fast_text, differing]))

	return results


static func _expo_is_stored_and_admits_the_sim_ignores_it() -> Array:
	var results: Array = []

	var config := {}
	results.append(TestResult.new(
		"a build with no expo reads as no expo",
		absf(RateSettings.expo(config)) < 0.0001, "%.3f" % [RateSettings.expo(config)]))

	RateSettings.set_expo(config, 0.4)
	results.append(TestResult.new(
		"the expo a builder set is the expo that comes back",
		absf(RateSettings.expo(config) - 0.4) < 0.0001, "%.3f" % [RateSettings.expo(config)]))

	var bad := {}
	RateSettings.set_expo(bad, 1.7)
	results.append(TestResult.new(
		"an expo outside 0-1 is refused rather than stored",
		not bad.has(RateSettings.EXPO_KEY), "config %s" % [bad]))

	var sentence := RateSettings.expo_sentence(config).to_lower()
	results.append(TestResult.new(
		"and the expo line admits the sim flies a linear stick and does not apply it",
		sentence.contains("linear") and (sentence.contains("does not") or sentence.contains("not applied")),
		"sentence: %s" % [RateSettings.expo_sentence(config)]))

	return results


## The room may only advertise modes the sim actually flies. Asserted against the enum's own keys,
## so a hand-written third mode cannot appear in the prose without the sim growing one.
static func _the_modes_taught_are_the_modes_flown() -> Array:
	var results: Array = []

	var flown := RateSettings.modes_flown()
	var enum_keys: Array = FlightController.Mode.keys()
	results.append(TestResult.new(
		"the modes the room names are exactly the modes FlightController flies, in its own order",
		flown == enum_keys, "%s against %s" % [flown, enum_keys]))

	var sentence := RateSettings.modes_sentence().to_lower()
	results.append(TestResult.new(
		"and the modes line says Lothal does not model switch assignment or the other modes",
		sentence.contains("switch") and sentence.contains("two"),
		"sentence: %s" % [RateSettings.modes_sentence()]))

	return results


static func _the_panel_shows_the_statement_and_edits_the_rate(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var panel := ConfigRatesPanel.new()
	var emitted: Array = []
	var expos: Array = []
	panel.max_rate_edited.connect(func(deg: float) -> void: emitted.append(deg))
	panel.expo_edited.connect(func(value: float) -> void: expos.append(value))

	var build := _build(catalog, {})
	panel.render(build)

	# THE SENTENCE IS PASTED WHOLE. A panel that wrote its own from the value is exactly how the
	# provenance goes missing, which is the failure FailsafeSettings' header names by name.
	results.append(TestResult.new(
		"the Rates panel shows the module's own provenance sentence, unrewritten",
		panel.rate_text() == RateSettings.max_rate_sentence(build.config),
		"panel: %s" % [panel.rate_text()]))

	results.append(TestResult.new(
		"and the sim-versus-real statement, also unrewritten",
		panel.sim_versus_real_text() == RateSettings.sim_versus_real_sentence(build.config),
		"panel: %s" % [panel.sim_versus_real_text()]))

	# The signal a mouse would send: a Range assigned headlessly announces nothing.
	panel.rate_field().value_changed.emit(500.0)
	results.append(TestResult.new(
		"and typing a max rate announces it rather than writing it into the build itself",
		emitted.size() == 1 and absf(float(emitted[0]) - 500.0) < 0.001
			and not build.config.has(RateSettings.MAX_RATE_KEY),
		"emitted %s, config %s" % [emitted, build.config]))

	panel.expo_field().value_changed.emit(0.35)
	results.append(TestResult.new(
		"and typing an expo announces it too, without writing it",
		expos.size() == 1 and absf(float(expos[0]) - 0.35) < 0.001
			and not build.config.has(RateSettings.EXPO_KEY),
		"emitted %s, config %s" % [expos, build.config]))

	# Reopening a drone that carries a rate must show that rate, or the builder sees the sim's
	# default where their own number should be.
	var config := {}
	RateSettings.set_max_rate_deg_s(config, 600.0)
	RateSettings.set_expo(config, 0.25)
	var saved := _build(catalog, config)
	var modes_before := panel.modes_text()
	panel.render(saved)
	results.append(TestResult.new(
		"and reopening a drone with a set rate shows that rate, not the sim's default",
		absf(panel.field_value() - 600.0) < 0.001 and panel.rate_text().contains("600"),
		"field %.1f, row: %s" % [panel.field_value(), panel.rate_text()]))

	results.append(TestResult.new(
		"and shows its expo too",
		absf(panel.expo_value() - 0.25) < 0.0001, "expo field %.3f" % [panel.expo_value()]))

	results.append(TestResult.new(
		"and the statement moved with the build, so the panel is not showing a stale sentence",
		panel.sim_versus_real_text() == RateSettings.sim_versus_real_sentence(saved.config)
			and panel.sim_versus_real_text() != RateSettings.sim_versus_real_sentence({}),
		"panel: %s" % [panel.sim_versus_real_text()]))

	# The teaching half, on C7's rule: built once and untouched by render, so two builds that
	# disagree about every rate read the same modes prose.
	results.append(TestResult.new(
		"and the modes prose is the same for every build — it teaches, it does not report",
		panel.modes_text() == modes_before and panel.modes_text().contains(
			RateSettings.modes_flown()[0]),
		"before: %s / after: %s" % [modes_before, panel.modes_text()]))

	panel.free()
	return results


static func _build(catalog: PartsCatalog, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {"receiver": "rx_elrs_2400"})
	build.set_config(config)
	return build
