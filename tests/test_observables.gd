class_name TestObservables
extends RefCounted
## The observables layer is the contract between physics and everything that renders it,
## so these tests run a REAL simulation and check what it published — not a hand-filled
## Observables object, which would only prove that assignment works.
##
## The check with teeth is the last one. Every other test here would still pass if audio
## quietly computed its own blade-pass frequency from its own copy of RPM, which is the
## exact failure architecture.md says this layer exists to prevent.

static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()

	# --- Published before anything is stepped ---
	core.prime_motors(build.hover_throttle())
	var obs := core.observables

	results.append(TestResult.new(
		"priming publishes immediately, so no consumer reads a stale tick after a respawn",
		obs.mean_rpm() > 1000.0,
		"mean RPM after prime = %.0f" % obs.mean_rpm()
	))

	# --- Blade pass and electrical frequency against the reference figures ---
	# physics.md quotes ~1.45 kHz blade-pass and ~3.4 kHz electrical for a 3-blade prop on
	# a 14-pole motor at 29,000 RPM. Reproducing those two numbers is what proves the
	# pole-pairs halving and the blade multiply are the right way round: swapping either
	# for its inverse lands nowhere near.
	var rpm := 29000.0
	for name in MotorLayout.MOTOR_NAMES:
		core.motor_rpm[name] = rpm
	core.powertrain.pole_pairs = 7.0
	core.powertrain.blades = 3.0
	core._publish(Vector3.ZERO)

	var blade_hz: float = core.observables.blade_pass_hz[0]
	var elec_hz: float = core.observables.electrical_hz[0]

	results.append(TestResult.new(
		"blade-pass frequency at 29,000 RPM with 3 blades is ~1.45 kHz",
		absf(blade_hz - 1450.0) < 20.0,
		"got %.0f Hz" % blade_hz
	))
	results.append(TestResult.new(
		"electrical frequency uses pole PAIRS, not poles: 14-pole at 29,000 RPM is ~3.4 kHz",
		absf(elec_hz - 3383.0) < 40.0,
		"got %.0f Hz (a poles-not-pairs bug would read %.0f)" % [elec_hz, elec_hz * 2.0]
	))

	# --- Specific force excludes gravity ---
	# An accelerometer in free fall reads zero. If gravity leaked into this observable, a
	# motionless hovering drone would read 0 g and a dropped one would read 1 g, which is
	# backwards and would drive every consumer of g_force the wrong way.
	var falling := build.build_drone_core()
	falling.step({"M1": 0.0, "M2": 0.0, "M3": 0.0, "M4": 0.0}, 0.001)
	results.append(TestResult.new(
		"specific force excludes gravity: motors off reads ~0 g, not 1 g",
		falling.observables.g_force < 0.05,
		"motors off reads %.3f g" % falling.observables.g_force
	))

	# The FLYING hover throttle, solved against the pack this core actually holds, rather than the
	# stats panel's nominal-datum figure. A fresh pack rests above nominal (physics.md §5), so
	# commanding the quoted 29% here would read about 1.29 g — which is a correct reading of a
	# climbing aircraft, and not the hover this test is about.
	var flying_hover := ReferenceBuild.hover_throttle()
	var hovering := build.build_drone_core()
	hovering.prime_motors(flying_hover)
	hovering.step(_even_throttle(flying_hover), 0.001)
	results.append(TestResult.new(
		"specific force at hover reads ~1 g, the weight the airframe is carrying",
		absf(hovering.observables.g_force - 1.0) < 0.15,
		"hover reads %.3f g" % hovering.observables.g_force
	))

	# --- Thrust and airspeed track the live simulation ---
	var flying := build.build_drone_core()
	flying.prime_motors(build.hover_throttle())
	for _i in 500:
		flying.step(_even_throttle(build.max_throttle_fraction()), 0.001)

	var summed := 0.0
	for i in Observables.MOTOR_COUNT:
		summed += flying.observables.thrust_n[i]
	results.append(TestResult.new(
		"total thrust equals the sum of the four published per-motor thrusts",
		absf(summed - flying.observables.total_thrust_n) < 0.001,
		"sum = %.3f N, published total = %.3f N" % [summed, flying.observables.total_thrust_n]
	))
	results.append(TestResult.new(
		"airspeed tracks the rigid body under full throttle",
		absf(flying.observables.airspeed_mps - flying.rigid_body.velocity_mps.length()) < 0.001
			and flying.observables.airspeed_mps > 1.0,
		"published %.3f m/s, rigid body %.3f m/s" % [flying.observables.airspeed_mps, flying.rigid_body.velocity_mps.length()]
	))

	# --- Tip speed, which broadband rotor noise scales off ---
	# The reference 5" prop at ~29,000 RPM runs a tip near 190 m/s (Mach 0.55). This is a
	# real and slightly startling number, and it is the reason the broadband component
	# dominates at speed.
	results.append(TestResult.new(
		"tip speed at 29,000 RPM on a 5\" prop is ~190 m/s",
		absf(core.observables.tip_speed_mps[0] - 193.0) < 15.0,
		"got %.0f m/s (Mach %.2f)" % [core.observables.tip_speed_mps[0], core.observables.tip_speed_mps[0] / 343.0]
	))

	# --- The claim the layer exists for ---
	# Audio must render the PUBLISHED frequency, not one it derived itself from RPM. The
	# only way to tell those apart is to make them disagree: this publishes a blade-pass
	# frequency deliberately inconsistent with the RPM beside it, and the synthesiser has
	# to follow the published number. A synthesiser carrying its own rpm/60 x blades — the
	# duplication this whole layer exists to forbid — produces 1450 Hz here and fails.
	var divergent := build.build_drone_core()
	for name in MotorLayout.MOTOR_NAMES:
		divergent.motor_rpm[name] = 29000.0
	divergent._publish(Vector3.ZERO)
	for i in Observables.MOTOR_COUNT:
		divergent.observables.blade_pass_hz[i] = 800.0
		divergent.observables.thrust_n[i] = divergent.observables.weight_n * 0.25

	var synth := RotorSynth.new(RotorSynth.DEFAULT_SAMPLE_RATE_HZ)
	var rendered := _dominant_frequency(synth, divergent.observables, [800.0, 1450.0])
	results.append(TestResult.new(
		"audio renders the published blade-pass frequency, never its own from RPM",
		is_equal_approx(rendered, 800.0),
		"published 800 Hz alongside 29,000 RPM (which would imply 1450 Hz); synth rendered %.0f Hz" % rendered
	))

	# --- The three quantities the flight recorder needed (LTHL-18) -------------------------
	#
	# Added to this layer rather than recovered by the recorder, because a recorder that
	# re-derived reaction torque from k_q would be the SECOND expression of it in the project,
	# and two expressions of one quantity is how a log and the flight it claims to describe
	# start disagreeing. Each check below is written against the way a re-derivation would go
	# subtly wrong, not merely against "the field exists".

	# Simulated time, not wall clock, and not advanced by a republish. A recorder timestamping
	# from Time.get_ticks_msec() would produce a trace whose sample spacing is the frame rate of
	# the machine that ran it, which is worthless for a spectrum.
	var clocked := build.build_drone_core()
	clocked.prime_motors(build.hover_throttle())
	var primed_at: float = clocked.observables.elapsed_s
	for _i in 250:
		clocked.step(_even_throttle(build.hover_throttle()), 0.001)
	clocked._publish(Vector3.ZERO)
	results.append(TestResult.new(
		"elapsed time is accumulated SIMULATED time — priming starts a clock at zero and a republish does not advance it",
		primed_at == 0.0 and absf(clocked.observables.elapsed_s - 0.25) < 1e-6,
		"primed at %.6f s, %.6f s after 250 steps of 1 ms" % [primed_at, clocked.observables.elapsed_s]
	))

	# Per-motor current. The check that bites is the ASYMMETRIC one: a naive implementation
	# publishing current_total_a/4 into each slot sums correctly and is wrong about the only
	# thing this observable is for, which is which corner is working hardest.
	var leaning := build.build_drone_core()
	leaning.prime_motors(build.hover_throttle())
	leaning.step({"M1": 0.9, "M2": 0.9, "M3": 0.2, "M4": 0.2}, 0.05)
	var per_motor_sum := 0.0
	for i in Observables.MOTOR_COUNT:
		per_motor_sum += leaning.observables.current_a[i]
	results.append(TestResult.new(
		"per-motor current sums to the published pack current",
		absf(per_motor_sum - leaning.observables.current_total_a) < 1e-4,
		"sum %.3f A against pack %.3f A" % [per_motor_sum, leaning.observables.current_total_a]
	))
	results.append(TestResult.new(
		"per-motor current is per MOTOR: the hard-working corner draws more than the idling one",
		leaning.observables.current_a[0] > leaning.observables.current_a[2] * 1.5,
		"M1 %.2f A at 90%% against M3 %.2f A at 20%%" % [
			leaning.observables.current_a[0], leaning.observables.current_a[2]]
	))

	# Per-motor reaction torque, against the same law DroneCore integrates. Checked at an
	# asymmetric rpm for the same reason as above, and against PropellerModel directly so that a
	# published constant, or one computed from mean rpm, fails.
	var torque_ok := true
	for i in Observables.MOTOR_COUNT:
		# Against the powertrain's own 64-bit rpm, not the published rpm beside it: that one is
		# 32-bit for the audio path, and rounding it first would leave this check comparing the
		# torque law to a slightly different motor.
		var true_rpm: float = leaning.powertrain.motor_rpm[MotorLayout.MOTOR_NAMES[i]]
		var expected := PropellerModel.reaction_torque_n_m(leaning.powertrain.k_q, true_rpm)
		if absf(leaning.observables.reaction_torque_n_m[i] - expected) > 1e-12:
			torque_ok = false
	results.append(TestResult.new(
		"per-motor reaction torque is published, per motor, and is k_q x omega^2 on that motor's own rpm",
		torque_ok and leaning.observables.reaction_torque_n_m[0] > leaning.observables.reaction_torque_n_m[2],
		"M1 %.6f N*m, M3 %.6f N*m" % [
			leaning.observables.reaction_torque_n_m[0], leaning.observables.reaction_torque_n_m[2]]
	))

	# And the flight integrates the PUBLISHED torque rather than a second copy of the formula.
	# An absence, so it is read from the source, in the shape test_pid_tunes.gd uses: a runtime
	# check cannot see this, because two copies of a correct formula agree right up until one of
	# them is edited.
	var core_code := _code_only(FileAccess.get_file_as_string("res://src/sim/drone_core.gd"))
	results.append(TestResult.new(
		"the flight integrates the published reaction torque — the formula has ONE expression, in PropellerModel via Powertrain",
		not core_code.contains("PropellerModel.reaction_torque_n_m")
			and core_code.contains("observables.reaction_torque_n_m"),
		"drone_core.gd reads the published value"
	))

	return results

## Comments stripped, so that a file MENTIONING a call in prose does not read as making it.
## Borrowed in shape from tests/test_pid_tunes.gd.
static func _code_only(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		var hash_index := line.find("#")
		lines.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(lines)

## Which of `candidates` carries the most energy in a rendered block, by Goertzel.
static func _dominant_frequency(synth: RotorSynth, obs: Observables, candidates: Array) -> float:
	var block := synth.render_block(obs, 1.0, 8192)
	var best := 0.0
	var best_energy := -1.0
	for hz in candidates:
		var energy := RotorSynth.goertzel_energy(block, hz, synth.sample_rate_hz)
		if energy > best_energy:
			best_energy = energy
			best = hz
	return best

static func _even_throttle(throttle: float) -> Dictionary:
	return {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}
