class_name TestCoaxialBuild
extends RefCounted
## Build honours a frame's `motors_per_arm` (the cinelifter's coaxial X8).
##
## Every check is tied to a mutation that makes it fail: motors_per_arm forced to 1 fails the count,
## the AUW window and the delta; dropping the lower PartMass fails the mass delta and the part-count
## check; thrust_rotor_equivalents back to 4.0 fails the T:W / hover check (hover rises to the 4-rotor
## figure, which for this build is above 0.8 only if thrust is not counted for the eighth motors).

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var coax := DesignSession.default_for_class("cinelifter").build(catalog)
	var quad_five := DesignSession.default_for_class("five_inch").build(catalog)

	results.append(TestResult.new("cinelifter has 2 motors per arm and 8 motors",
		coax != null and coax.motors_per_arm() == 2 and coax.motor_count() == 8,
		"mpa=%d count=%d" % [coax.motors_per_arm(), coax.motor_count()]))
	results.append(TestResult.new("a quad class (five_inch) has 4 motors",
		quad_five != null and quad_five.motors_per_arm() == 1 and quad_five.motor_count() == 4,
		"count=%d" % quad_five.motor_count()))
	results.append(TestResult.new("quad thrust rotor-equivalents are exactly 4",
		quad_five.thrust_rotor_equivalents() == 4.0, str(quad_five.thrust_rotor_equivalents())))
	var want_eq := 4.0 * (1.0 + Build.COAXIAL_LOWER_ROTOR_THRUST)
	results.append(TestResult.new("coaxial thrust rotor-equivalents count the lower rotor at 0.8",
		is_equal_approx(coax.thrust_rotor_equivalents(), want_eq) and is_equal_approx(want_eq, 7.2),
		str(coax.thrust_rotor_equivalents())))

	var auw := coax.all_up_weight_g()
	results.append(TestResult.new("cinelifter all-up weight is 2-4 kg", auw > 2000.0 and auw < 4000.0,
		"%.1f g" % auw))

	# The same parts on a frame without the key: a quad.
	var quad := DesignSession.default_for_class("cinelifter").build(catalog)
	quad.frame = quad.frame.duplicate(true)
	(quad.frame["specs"] as Dictionary).erase("motors_per_arm")
	quad._recompute()
	var motor_prop_g := float(coax.motor["mass_g"]) + float(coax.propeller["mass_g"])
	var lead_g := coax.harness.motor_lead_mass_g(coax)
	var delta := auw - quad.all_up_weight_g()
	var want_delta := 4.0 * (motor_prop_g + lead_g)
	results.append(TestResult.new("quad copy of the same parts has 4 motors", quad.motor_count() == 4,
		str(quad.motor_count())))
	results.append(TestResult.new("coaxial AUW exceeds the quad by 4 x (motor+prop+lead)",
		absf(delta - want_delta) < 0.01 and delta >= 4.0 * (58.0 + 12.0),
		"delta=%.3f want=%.3f" % [delta, want_delta]))

	var lowers := 0
	var lower_leads := 0
	for p in coax.mass_parts():
		if String(p.label).begins_with("Motor + prop") and String(p.label).ends_with("lower"):
			lowers += 1
		if String(p.label).begins_with("Motor lead") and String(p.label).ends_with("lower"):
			lower_leads += 1
	results.append(TestResult.new("four lower motor masses are in the part list", lowers == 4,
		str(lowers)))
	results.append(TestResult.new("four lower motor leads are in the part list",
		lower_leads == 4 or lead_g <= 0.0, "%d (lead %.2f g)" % [lower_leads, lead_g]))

	var twr := coax.thrust_to_weight()
	var hover := coax.hover_throttle()
	results.append(TestResult.new("cinelifter T:W is over 1.5", twr > 1.5, "%.2f" % twr))
	results.append(TestResult.new("cinelifter hovers under 80% throttle", hover < 0.8, "%.3f" % hover))
	# The quad copy has the same parts but half the thrust: it must hover higher and have a lower T:W.
	results.append(TestResult.new("the coaxial pair out-thrusts the same parts as a quad",
		twr > quad.thrust_to_weight() * 1.2, "%.2f vs %.2f" % [twr, quad.thrust_to_weight()]))

	# Harness counts every motor lead.
	results.append(TestResult.new("harness mass counts eight motor leads",
		absf(coax.harness_mass_g() - quad.harness_mass_g() - 4.0 * lead_g) < 0.001,
		"%.3f vs %.3f" % [coax.harness_mass_g(), quad.harness_mass_g()]))

	# The sim's hover agrees with Build's. The sim's prime-plus-one-tick thrust sits a fixed amount
	# above Build's steady figure on a QUAD too (spin-up transient), so the coaxial lump is held to
	# the quad's own ratio: an unscaled lump (half the thrust) misses it by 30%+.
	var coax_ratio := _sim_over_build(coax)
	var quad_ratio := _sim_over_build(quad_five)
	results.append(TestResult.new("sim thrust at Build's hover throttle matches the quad's sim/build ratio",
		absf(coax_ratio / quad_ratio - 1.0) < 0.05, "coax %.3f quad %.3f" % [coax_ratio, quad_ratio]))
	var coax_amps := _sim_amps_over_build(coax)
	var quad_amps := _sim_amps_over_build(quad_five)
	results.append(TestResult.new("sim pack current at hover matches the quad's sim/build ratio",
		absf(coax_amps / quad_amps - 1.0) < 0.05, "coax %.3f quad %.3f" % [coax_amps, quad_amps]))
	return results


static func _sim_amps_over_build(b: Build) -> float:
	var h := b.hover_throttle()
	var core := b.build_drone_core()
	core.prime_motors(h)
	var cmds := {}
	for name in MotorLayout.MOTOR_NAMES:
		cmds[name] = h
	core.step(cmds, 0.001)
	return float(core.observables.current_total_a) / b.hover_current_a(h)


static func _sim_over_build(b: Build) -> float:
	var h := b.hover_throttle()
	var core := b.build_drone_core()
	core.prime_motors(h)
	var cmds := {}
	for name in MotorLayout.MOTOR_NAMES:
		cmds[name] = h
	core.step(cmds, 0.001)
	var t := 0.0
	for i in MotorLayout.MOTOR_NAMES.size():
		t += core.observables.thrust_n[i]
	return t / b.thrust_at_throttle_n(h)
