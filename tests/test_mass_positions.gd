class_name TestMassPositions
extends RefCounted
## Where each part's mass sits, and what follows from it.
##
## Until this slice, five of the six entries in Build.mass_parts() were pinned to Vector3.ZERO:
## the frame, the pack, the FC, the ESC and the loose electronics. Only the motors had a real
## position. So the mount system — which computes a pack's travel from the frame's reach less half
## the pack's own length, narrows it as you choose a longer pack, and warns when the pack reaches
## into the front propeller discs — moved the picture, moved the fit warnings, and did not move the
## physics. labs-and-sim.md §2.2 says the fit check and the picture are the same geometry; for mass
## that was aspiration.
##
## What this suite pins is the whole of the claim: the offset reaches the centre of mass, the
## centre of mass reaches the inertia tensor, and both reach the flying aircraft.

const EPSILON := 1e-9

static func run() -> Array:
	var results: Array = []
	results.append_array(_reference_is_unmoved())
	results.append_array(_sliding_moves_the_com())
	results.append_array(_sliding_moves_the_inertia())
	results.append_array(_nose_heavy_needs_differential_thrust())
	results.append_array(_the_bench_reports_it())
	return results


static func _build(offset_mm: float, mount := "strap_top") -> Build:
	var build := ReferenceBuild.build()
	build.set_assembly({"battery_mount": mount, "battery_offset_m": offset_mm / 1000.0})
	return build


# ---------------------------------------------------------------------------
# The reference build does not move. If it does, something else is wrong.
# ---------------------------------------------------------------------------
## The reference build's centre of mass is LATERALLY exact and 11.6 mm up.
##
## The lateral half is the load-bearing check: the reference pack is centred on its mount and every
## other part is on the centreline, so X must come out at EXACTLY zero. A drift there would mean
## the mount resolution or the frame's mass distribution is wrong.
##
## Z WAS EXACTLY ZERO TOO UNTIL LTHL-11, and is now 0.18 mm aft. The camera sits at the front edge
## of the centre plate and the VTX and antenna at the rear, so 21 g of the aircraft is genuinely
## not at the origin fore and aft — which is a property of a real quad, and the reason those
## components were given real bays instead of being left in a lump. The claim that survives
## unchanged is asserted against the same build with its bays empty, which still comes out at
## exactly zero and still catches the failure the old line was worth having. tests/
## test_mass_properties.gd pins the fitted offset against the components' own moment.
##
## The vertical half is a real measurement and was a surprise worth recording. "Centred on its
## mount" constrains fore/aft and lateral only — the mount is the TOP PLATE, 12.5 mm above the
## origin by construction, and a 185 g pack seated on it sits 31 mm up and is 37% of a 496 g
## aircraft. The frame's origin is the plate midplane, not a balance point, and a real 5" quad with
## a top-mounted pack does carry its mass about a centimetre above its plates.
##
## It moves no oracle, and the reason is worth stating: thrust is always along body +Y, so the part
## of a torque arm that is parallel to Y contributes nothing to r x F. A purely VERTICAL centre-of-
## mass offset is therefore invisible to the motors at any attitude, not merely at hover. That is a
## fact about this model and not about aircraft — see labs-and-sim.md §2.6 for the limitation it
## rests on (drag has no moment arm yet).
##
## The three fixed points ride on the same check — all three are collective figures and none of them
## depends on where the mass sits, so a moved one means mass was invented or lost.
static func _reference_is_unmoved() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var com := build.mass_properties.com_m

	out.append(TestResult.new(
		"the reference build's centre of mass is laterally exact, and fore/aft exact with its bays empty",
		absf(com.x) < EPSILON
			and absf(ReferenceBuild.fore_aft_symmetric().mass_properties.com_m.z) < EPSILON,
		"fitted %s, bays empty %s" % [com, ReferenceBuild.fore_aft_symmetric().mass_properties.com_m]
	))
	out.append(TestResult.new(
		"and sits 11.8 mm up, because the pack is strapped to the top plate",
		absf(com.y - 0.011832) < 1e-5,
		"got %.4f mm up" % (com.y * 1000.0)
	))
	out.append(TestResult.new(
		"the reference build still weighs 507.5 g",
		absf(build.all_up_weight_g() - 507.48) < 0.5,
		"got %.1f g" % build.all_up_weight_g()
	))
	out.append(TestResult.new(
		"the reference build's thrust-to-weight is still 11.43:1",
		absf(build.thrust_to_weight() - 11.43) < 0.05,
		"got %.2f" % build.thrust_to_weight()
	))
	out.append(TestResult.new(
		"the reference build still hovers at 29% throttle",
		# The oracle's own tolerance, from test_hover.gd:31 — the same 29% figure, so the same band.
		absf(build.hover_throttle() - 0.29) < 0.02,
		"got %.1f%%" % (build.hover_throttle() * 100.0)
	))

	# Sliding the pack must not create or destroy mass — only move it. Stated separately because a
	# mount resolution that rebuilt the parts list could plausibly drop or double an entry, and
	# every figure above would still hold for the CENTRED build that is checked here.
	var slid := _build(30.0)
	out.append(TestResult.new(
		"sliding the pack changes no mass, only position",
		absf(slid.mass_properties.total_mass_kg - build.mass_properties.total_mass_kg) < 1e-12,
		"centred %.6f kg vs slid %.6f kg" % [
			build.mass_properties.total_mass_kg, slid.mass_properties.total_mass_kg]
	))
	return out


# ---------------------------------------------------------------------------
# The headline claim.
# ---------------------------------------------------------------------------
## Slide the pack forward and the centre of mass goes forward — by the pack's own share of the
## all-up weight times how far it moved, which is the definition of a centre of mass and not a
## fitted number. Asserting the AMOUNT rather than the direction is what makes this test able to
## fail: a model that moved the CoM by the full offset, or by the offset of the wrong part, would
## pass a sign check.
static func _sliding_moves_the_com() -> Array:
	var out: Array = []
	var offset_mm := 30.0
	var centred := ReferenceBuild.build()
	var forward := _build(offset_mm)

	# WHAT MOVES WITH THE PACK IS NO LONGER ONLY THE PACK, and that is PW2 rather than a slip. The
	# connector is soldered to the pack's own lead, so it rides at the pack's position; the main lead
	# spans the stack and the pack, so its centroid rides half as far. Both are named here as terms,
	# from the harness's own masses, rather than folded into a fudge — a model that moved the CoM by
	# the offset of the wrong part is exactly what this check exists to catch, and it can only catch
	# it while the expected value is built out of parts this file can point at.
	var moving_kg: float = float(centred.battery["mass_g"]) / 1000.0 \
		+ centred.harness.connector_mass_g(centred) / 1000.0 \
		+ centred.harness.main_lead_mass_g(centred) / 1000.0 * 0.5
	var pack_fraction: float = moving_kg / centred.mass_properties.total_mass_kg
	# Forward is -Z (physics.md §1), so a positive offset moves the CoM to negative Z — FROM WHERE
	# IT ALREADY WAS. That baseline was zero until LTHL-11 gave the camera, VTX and antenna real
	# bays, and it is 0.18 mm aft now; the claim being tested is the DISPLACEMENT, so what changed
	# here is that the displacement is measured from the aircraft's own starting point instead of
	# from an origin it no longer sits on. The bound is unchanged at 1e-9.
	var baseline_z: float = centred.mass_properties.com_m.z
	var expected_z := baseline_z - (offset_mm / 1000.0) * pack_fraction
	var actual := forward.mass_properties.com_m

	out.append(TestResult.new(
		"sliding the pack forward moves the centre of mass forward",
		actual.z < baseline_z - 1e-4,
		"com %s, from a baseline of %.6f m" % [actual, baseline_z]
	))
	out.append(TestResult.new(
		"the centre of mass moves by the offset times the pack's mass fraction",
		absf(actual.z - expected_z) < 1e-9,
		"got %.6f m, expected %.6f m (pack, plug and half the lead are %.1f%% of AUW)" % [
			actual.z, expected_z, pack_fraction * 100.0]
	))
	# Sliding is fore/aft only: a pack that gained lateral offset would mean the mount's own axes
	# had been mixed up, which a magnitude-only check would not catch.
	out.append(TestResult.new(
		"sliding the pack moves nothing sideways",
		absf(actual.x) < EPSILON,
		"com.x = %.12f" % actual.x
	))

	# Aft is the same fact with the sign reversed, and it is worth its own line: a model that took
	# absf() of the offset somewhere would pass every forward test in this file.
	# Symmetric ABOUT THE BASELINE rather than about zero, for the reason given above.
	var aft := _build(-offset_mm)
	out.append(TestResult.new(
		"sliding the pack aft moves the centre of mass aft",
		absf((aft.mass_properties.com_m.z - baseline_z) + (actual.z - baseline_z)) < EPSILON
			and aft.mass_properties.com_m.z > baseline_z,
		"com %s, from a baseline of %.6f m" % [aft.mass_properties.com_m, baseline_z]
	))

	# The pack on the BOTTOM plate hangs below the airframe, so the centre of mass drops. This is
	# the mount CHOICE reaching the physics, as distinct from the offset along it — two different
	# things the tweak file stores, and a wiring that read only the offset would pass everything
	# above.
	var underslung := _build(0.0, "strap_bottom")
	out.append(TestResult.new(
		"strapping the pack underneath drops the centre of mass",
		underslung.mass_properties.com_m.y < -1e-4,
		"com %s" % underslung.mass_properties.com_m
	))
	return out


# ---------------------------------------------------------------------------
# Position reaches the tensor, not just the readout.
# ---------------------------------------------------------------------------
## Every off-origin mass adds m*d^2 about the axes it is off. A pack 30 mm forward is 30 mm along
## the aircraft, so it adds to PITCH inertia (about body X) — and the check names pitch specifically
## rather than "the tensor changed", because a fore/aft offset that showed up in roll would mean
## the axes were crossed.
static func _sliding_moves_the_inertia() -> Array:
	var out: Array = []
	var centred := ReferenceBuild.build()
	var forward := _build(30.0)

	var pitch_before := centred.mass_properties.inertia.x.x
	var pitch_after := forward.mass_properties.inertia.x.x
	out.append(TestResult.new(
		"sliding the pack forward raises pitch inertia",
		pitch_after > pitch_before * 1.001,
		"%.8f -> %.8f kg*m^2" % [pitch_before, pitch_after]
	))

	# Roll is about the fore/aft axis, so sliding ALONG that axis cannot change it. The sharper
	# half of the same assertion: it says what must NOT move as well as what must.
	var roll_before := centred.mass_properties.inertia.z.z
	var roll_after := forward.mass_properties.inertia.z.z
	out.append(TestResult.new(
		"sliding the pack fore/aft leaves roll inertia alone",
		absf(roll_after - roll_before) < 1e-12,
		"%.10f -> %.10f kg*m^2" % [roll_before, roll_after]
	))

	# An asymmetric build has products of inertia — the tensor stops being diagonal. Only when the
	# offset is in TWO axes at once, which the underslung pack gives: down AND, once slid, forward.
	var underslung := _build(30.0, "strap_bottom")
	out.append(TestResult.new(
		"a pack that is both low and forward makes the tensor non-diagonal",
		absf(underslung.mass_properties.inertia.y.z) > 1e-7,
		"I_yz = %.10f" % underslung.mass_properties.inertia.y.z
	))
	return out


# ---------------------------------------------------------------------------
# The end-to-end proof.
# ---------------------------------------------------------------------------
## A nose-heavy quad hovering level needs the front motors working harder than the rear ones. That
## is the physical fact this whole slice exists to make representable, and it is the only assertion
## here that could not be satisfied by a correct readout alone — it flies the aircraft under the
## flight controller and reads what the motors settle at.
##
## Note what it depends on: the CoM moving (this commit) AND torque being taken about the CoM (the
## previous one). With origin-referenced arms the four thrusts would balance by symmetry and the
## aircraft would hold level with all four motors equal, which is the false pass this is written
## against.
static func _nose_heavy_needs_differential_thrust() -> Array:
	var out: Array = []
	var build := _build(40.0)
	var core := build.build_drone_core()
	var controller := FlightController.new()

	var hover := build.hover_throttle()
	core.prime_motors(hover)

	# Held level by the controller from a level start: sticks centred, so anything the motors do
	# differently is the controller holding the attitude against the offset mass.
	var dt := 1.0 / 1000.0
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover}
	var commands := {}
	for i in 4000:
		commands = controller.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, dt)
		core.step(commands, dt)

	var front: float = (float(commands["M2"]) + float(commands["M4"])) * 0.5
	var rear: float = (float(commands["M1"]) + float(commands["M3"])) * 0.5
	var pitch_rate: float = core.rigid_body.angular_velocity_rad_s.x

	out.append(TestResult.new(
		"a nose-heavy build holds level with the front motors working harder",
		front > rear + 0.005,
		"front %.4f vs rear %.4f throttle" % [front, rear]
	))
	out.append(TestResult.new(
		"and it is actually holding level while it does so",
		absf(pitch_rate) < 0.05,
		"pitch rate %.4f rad/s" % pitch_rate
	))

	# The centred build is the control: same aircraft, same controller, same four seconds, and the
	# four motors settle together. Without it, a test that reported a difference for every build
	# would look identical to this one passing.
	var level := ReferenceBuild.build()
	var level_core := level.build_drone_core()
	var level_controller := FlightController.new()
	var level_hover := level.hover_throttle()
	level_core.prime_motors(level_hover)
	var level_rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": level_hover}
	var level_commands := {}
	# AVERAGED over the last second rather than read off the final tick, and the difference is
	# the whole point of the check. Since vibration reached the sensor (LTHL-15) the commands
	# carry a ripple at the props' own frequencies — a real one, at 0.03 throttle peak on this
	# build — and a single arbitrary sample of a rippling signal says nothing about whether the
	# four motors SETTLE together, which is what this test is named after. The mean over 1000
	# ticks measures the settled asymmetry directly, and it is a STRICTER check than the final
	# sample ever was: it reads 0.00002 against this bound where the old form read 0.00024.
	var level_spread_sum := 0.0
	var level_samples := 0
	for i in 4000:
		level_commands = level_controller.update(
			level_core.rigid_body.orientation, level_core.gyro.rate_rad_s, level_rc, dt)
		level_core.step(level_commands, dt)
		if i >= 3000:
			level_spread_sum += (float(level_commands["M2"]) + float(level_commands["M4"])) * 0.5 \
				- (float(level_commands["M1"]) + float(level_commands["M3"])) * 0.5
			level_samples += 1
	var level_spread: float = absf(level_spread_sum / float(level_samples))

	out.append(TestResult.new(
		"a centred build's four motors settle together",
		level_spread < 0.001,
		"front/rear spread %.6f throttle, averaged over the settled second" % level_spread
	))
	return out


# ---------------------------------------------------------------------------
# The panel row that could only ever say zero.
# ---------------------------------------------------------------------------
static func _the_bench_reports_it() -> Array:
	var out: Array = []
	var bench := FrameBench.for_build(_build(40.0))

	var offset := bench.com_offset_m()
	out.append(TestResult.new(
		"the frame bench's CoM row shows a real offset for an off-centre build",
		offset.length() * 1000.0 > 1.0,
		"%.2f mm off centre" % (offset.length() * 1000.0)
	))
	out.append(TestResult.new(
		"and the bench reports it in millimetres to the panel",
		float(bench.readings()["com_offset_mm"]) > 1.0,
		"%.2f mm" % bench.readings()["com_offset_mm"]
	))

	# The apology is gone. frame_instruments.gd carried a hardcoded sentence telling the user that
	# "the centre of mass is the geometric centre for every build in the catalog" — a panel row
	# occupied by a limitation of the model. What replaces it has to be a function of the build,
	# which is what this asserts: the same note cannot come back for a centred build and an
	# off-centre one.
	var centred_note := FrameInstruments.com_note(ReferenceBuild.build().mass_properties.com_m)
	var offset_note := FrameInstruments.com_note(offset)
	out.append(TestResult.new(
		"the CoM note is read off the build rather than hardcoded",
		centred_note != offset_note and not offset_note.contains("every build in the catalog"),
		"off-centre note: %s" % offset_note
	))
	return out
