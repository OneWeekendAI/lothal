class_name TestSoftMount
extends RefCounted
## Soft mounts as parts (propulsion.md §5, slice P8). The vibration model already had the right
## isolation formula; what it lacked was any way to read a builder's actual grommet choice.
## `SoftMount` fills that gap by turning Shore A durometer, contact area and grommet count into
## the natural frequency and mass a pad genuinely has.
##
## Every check below fails without the physics: a stub that returned the pre-P8 250 Hz anchor
## would fail on hardness dependence, area dependence and count dependence — each of which is
## an independent axis of what a real grommet spec varies.

const _REFERENCE_TIP_MASS_KG := 0.0365   # matches vibration_model.gd's REFERENCE_TIP_MASS_KG
const _REFERENCE_THICKNESS_M := 0.001    # 1 mm — the pre-P8 anchor's own thickness reference

## The pre-P8 anchor, kept in this file only, as the number the finding-shipping check
## compares against. Deliberately NOT read from vibration_model.gd — the constant is
## deleted there, and having it live only in the test file makes the comparison a
## one-time honest audit rather than a permanent load-bearing constant.
const _PRE_P8_ANCHOR_HZ := 250.0


static func run() -> Array:
	var results: Array = []

	# -----------------------------------------------------------------------
	# Gent's correlation — the published Shore A → Young's modulus form
	# -----------------------------------------------------------------------
	# Two spot values from the correlation itself, computed by hand:
	#   S = 60: E = (0.0981·513.4016) / (0.137505·101.6)   = 50.3646 / 13.9705 = 3.60507 MPa
	#   S = 30: E = (0.0981·284.7008) / (0.137505·177.8)   = 27.9291 / 24.4484 = 1.14237 MPa
	# Testing the formula itself, not against a downstream number, is what makes these two
	# checks fail if the correlation is edited — including "improvements" that quietly change
	# the meaning of every downstream f_n.
	var e_60a := SoftMount.youngs_modulus_pa(60.0)
	results.append(TestResult.new(
		"Young's modulus at Shore 60A matches Gent's correlation to 4 significant figures",
		absf(e_60a - 3.60507e6) / 3.60507e6 < 1.0e-5,
		"S=60: %.5f MPa against 3.60507 MPa predicted" % (e_60a * 1.0e-6)))

	var e_30a := SoftMount.youngs_modulus_pa(30.0)
	# Pure evaluation of the correlation at S=30 — not a fit to any downstream number. The two
	# spot checks are at opposite ends of the sold range, so a correlation edited to fit one
	# would have to fit the other by accident to stay green.
	results.append(TestResult.new(
		"Young's modulus at Shore 30A matches Gent's correlation to 4 significant figures",
		absf(e_30a - 1.14237e6) / 1.14237e6 < 1.0e-5,
		"S=30: %.5f MPa against 1.14237 MPa predicted" % (e_30a * 1.0e-6)))

	# Harder rubber is stiffer — monotonic and always positive. A single sign flip in the
	# formula would fail this without anyone having to know the reference numbers.
	var monotonic := true
	var prev := 0.0
	for s in [20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]:
		var e := SoftMount.youngs_modulus_pa(s)
		if e <= prev:
			monotonic = false
			break
		prev = e
	results.append(TestResult.new(
		"Young's modulus rises monotonically with Shore A across the sold range 20A–90A",
		monotonic,
		"scanned S ∈ {20,30,…,90} — %s" % ("monotonic" if monotonic else "REVERSED at some step")))

	# Out-of-band Shore values refuse rather than silently return zero-through-arithmetic —
	# S = 100 makes the denominator vanish, and a catalog corrupted to 0 or 110 would
	# otherwise produce a soft-mount frequency of NaN and a green test.
	var refused := SoftMount.youngs_modulus_pa(0.0) == 0.0 \
			and SoftMount.youngs_modulus_pa(100.0) == 0.0 \
			and SoftMount.youngs_modulus_pa(-5.0) == 0.0 \
			and SoftMount.youngs_modulus_pa(110.0) == 0.0
	results.append(TestResult.new(
		"out-of-band Shore A values refuse to produce a modulus, they do not return NaN",
		refused,
		"tried S ∈ {-5, 0, 100, 110} — %s" % ("all refused" if refused else "at least one leaked through")))

	# -----------------------------------------------------------------------
	# The finding — this file's introduction ships as one
	# -----------------------------------------------------------------------
	# propulsion.md §5.2: "run the correlation for a typical FPV grommet — 60A silicone, a few
	# mm² of contact, four per motor, carrying a 32 g motor plus a 4.5 g prop — and see whether
	# f_n lands anywhere near the 250 Hz the current constant assumes. If it does not, that is
	# the finding, and it ships as one."
	#
	# Computed here BEFORE the pre-P8 constant was removed, with the class-typical defaults
	# soft_mount.gd carries. The band the comparison passes on is deliberately WIDE (0.5x to
	# 2x): the check is that the correlation is in the right neighbourhood, not that it equals
	# a guess. NOTHING in soft_mount.gd's defaults was adjusted to make this ratio come out
	# close to 1 — the numbers came from what a real grommet reads (60A) and what a compressed
	# grommet's crushed contact patch measures (~4 mm²), not from working backwards from the
	# deleted 250 Hz.
	var reference_grommet := SoftMount.compute(_REFERENCE_THICKNESS_M, _REFERENCE_TIP_MASS_KG)
	var f_n_60a: float = reference_grommet["f_n_hz"]
	var ratio := f_n_60a / _PRE_P8_ANCHOR_HZ
	results.append(TestResult.new(
		"a 60A grommet's computed f_n lands within the band the deleted 250 Hz anchor claimed",
		ratio > 0.5 and ratio < 2.0,
		"S=60A, A=4 mm², 4 per motor, 1 mm, 36.5 g tip: %.1f Hz against the deleted %.0f Hz (ratio %.2f) — the finding"
			% [f_n_60a, _PRE_P8_ANCHOR_HZ, ratio]))

	# Pin the exact computed number so a formula edit is caught even if the ratio band still
	# passes. Recomputed by hand, every step: E = 3.605073e6 Pa, k = E·A/t = 14420.29 N/m,
	# k_total = 4·k = 57681.16 N/m, mount_mass = 1200·4e-6·1e-3·4 = 1.92e-5 kg,
	# m_supported = 0.0365 + 1.92e-5 = 0.0365192 kg, f_n = √(k_total/m)/2π = 200.0214 Hz.
	# The tolerance is 0.01 Hz — five parts in 100,000 — because every term above is arithmetic
	# on published numbers, so there is nothing here for a loose band to absorb.
	results.append(TestResult.new(
		"the 60A reference number is arithmetic, pinned to what the formula predicts",
		absf(f_n_60a - 200.0214) < 0.01,
		"%.4f Hz against 200.0214 Hz predicted by k=E·A/t and f=√(k/m)/2π" % f_n_60a))

	# -----------------------------------------------------------------------
	# The four axes the pre-P8 model could not read
	# -----------------------------------------------------------------------
	# Each of these fails on any model that keys off thickness alone — the deleted
	# `MOUNT_REFERENCE_HZ * sqrt(t_ref/t)` scaling would pass NONE of these because it has no
	# dependence on hardness, area, or grommet count at all.
	var f_50a: float = SoftMount.compute(_REFERENCE_THICKNESS_M, _REFERENCE_TIP_MASS_KG,
			{"shore_a": 50.0})["f_n_hz"]
	var f_70a: float = SoftMount.compute(_REFERENCE_THICKNESS_M, _REFERENCE_TIP_MASS_KG,
			{"shore_a": 70.0})["f_n_hz"]
	results.append(TestResult.new(
		"a harder grommet raises f_n — the builder's 50A/60A/70A choice reaches the physics",
		f_50a < f_n_60a and f_n_60a < f_70a,
		"50A: %.1f Hz  60A: %.1f Hz  70A: %.1f Hz — ordering %s"
			% [f_50a, f_n_60a, f_70a, "correct" if f_50a < f_n_60a and f_n_60a < f_70a else "WRONG"]))

	var f_double_area: float = SoftMount.compute(_REFERENCE_THICKNESS_M, _REFERENCE_TIP_MASS_KG,
			{"contact_area_m2": 8.0e-6})["f_n_hz"]
	# k scales linearly in area, so f goes as sqrt(area). 2x area → sqrt(2)x frequency.
	results.append(TestResult.new(
		"doubling contact area raises f_n by sqrt(2), as k = E·A/t predicts",
		absf(f_double_area / f_n_60a - sqrt(2.0)) < 0.005,
		"A=4e-6: %.1f Hz  A=8e-6: %.1f Hz  ratio %.3f against sqrt(2) = 1.414"
			% [f_n_60a, f_double_area, f_double_area / f_n_60a]))

	var f_double_count: float = SoftMount.compute(_REFERENCE_THICKNESS_M, _REFERENCE_TIP_MASS_KG,
			{"grommets_per_motor": 8})["f_n_hz"]
	# k_total scales linearly in count, so f goes as sqrt(count). Same law as area, tested on
	# a separate axis so a bug that conflated the two fails one of them.
	results.append(TestResult.new(
		"doubling grommet count raises f_n by sqrt(2), independently of the area axis",
		absf(f_double_count / f_n_60a - sqrt(2.0)) < 0.005,
		"N=4: %.1f Hz  N=8: %.1f Hz  ratio %.3f against sqrt(2) = 1.414"
			% [f_n_60a, f_double_count, f_double_count / f_n_60a]))

	var f_double_thick: float = SoftMount.compute(2.0 * _REFERENCE_THICKNESS_M,
			_REFERENCE_TIP_MASS_KG)["f_n_hz"]
	# k = E·A/t so f goes as 1/sqrt(t). This is the ONE axis the pre-P8 model got right —
	# and it should still be right, so a builder's thickness slider keeps its meaning.
	results.append(TestResult.new(
		"doubling thickness drops f_n by sqrt(2) — the one axis the pre-P8 anchor got right, unchanged",
		absf(f_double_thick / f_n_60a - 1.0 / sqrt(2.0)) < 0.005,
		"t=1mm: %.1f Hz  t=2mm: %.1f Hz  ratio %.3f against 1/sqrt(2) = 0.707"
			% [f_n_60a, f_double_thick, f_double_thick / f_n_60a]))

	# A damping ratio the catalog got wrong falls back rather than propagating. zeta reaches
	# transmissibility as 2·zeta·r in both halves of the quotient, so zero damping divides by
	# zero at r = 1 — an infinite gyro amplitude at exactly the frequency a builder is most
	# likely to be reading. The guard is checked at the point it matters, T(f_n) itself, not
	# just on the accessor.
	var undamped := VibrationModel.new(0.110)
	undamped.tip_load_kg = _REFERENCE_TIP_MASS_KG
	undamped.soft_mount_m = 0.002
	undamped.soft_mount_spec = {"damping_ratio": 0.0}
	var t_at_resonance := undamped.mount_transmissibility(undamped.mount_hz())
	results.append(TestResult.new(
		"a zero or out-of-band damping ratio falls back instead of returning an infinite T at f_n",
		is_finite(t_at_resonance) and t_at_resonance > 1.0
			and SoftMount.damping_ratio_for({"damping_ratio": 0.0}) == SoftMount.DEFAULT_DAMPING_RATIO
			and SoftMount.damping_ratio_for({"damping_ratio": -0.2}) == SoftMount.DEFAULT_DAMPING_RATIO,
		"zeta = 0 spec: T(f_n) = %.3f (finite, and the amplification peak is still there)"
			% t_at_resonance))

	# `mount_transmissibility_at` is a QUERY, and reading a curve at another damping ratio must not
	# write to the model it is read from. An earlier version set `soft_mount_spec`, called the
	# formula and restored the field — which is a torn read for anyone holding the sim's live model
	# and for any re-entrancy, and the failure is silent: the caller's next transmissibility comes
	# back at a zeta nobody chose. Both halves are checked — the spec Dictionary is unchanged
	# (identity AND content, since a duplicate-and-restore leaves the content right), and the
	# nominal curve reads the same before and after.
	#
	# Stated honestly: the exact prior implementation — duplicate, set, call, RESTORE the original
	# reference — is invisible to any check that looks only after the call returns, which is why it
	# survived review. What a check can hold is the property the parameter makes structural: the
	# model's spec is the same object with the same content afterwards, and the nominal curve is
	# unmoved. Every write-based version that forgets to restore, restores the wrong object, or
	# restores a duplicate is caught by that, and the version that restores perfectly is caught by
	# nothing here — it is caught by the signature no longer having a field to write.
	#
	# MUTATION that turns this red: `mount_transmissibility_at` writes the zeta into
	# `soft_mount_spec` and does NOT put it back — the one-line slip the restore existed to prevent.
	var queried := VibrationModel.new(0.110)
	queried.tip_load_kg = _REFERENCE_TIP_MASS_KG
	queried.soft_mount_m = 0.002
	var spec_before: Dictionary = queried.soft_mount_spec
	var t_before := queried.mount_transmissibility(queried.mount_hz())
	var t_band := queried.mount_transmissibility_at(
		queried.mount_hz(), SoftMount.DAMPING_RATIO_LOW)
	var t_after := queried.mount_transmissibility(queried.mount_hz())
	results.append(TestResult.new(
		"reading the curve at a stated damping ratio does not write to the model it is read from",
		is_same(queried.soft_mount_spec, spec_before)
			and queried.soft_mount_spec == spec_before
			and t_after == t_before and t_band != t_before
			and SoftMount.damping_ratio_for(queried.soft_mount_spec)
				== SoftMount.damping_ratio_for(spec_before),
		"T(f_n) = %.4f before, %.4f after a read at zeta %.2f (which gave %.4f); spec object unmoved %s"
			% [t_before, t_after, SoftMount.DAMPING_RATIO_LOW, t_band,
				str(is_same(queried.soft_mount_spec, spec_before))]))

	# An unreadable grommet spec models as NO mount rather than as a class-typical one — the
	# refusing answer. A fallback to the defaults here would attribute isolation to a pad whose
	# specs the model just declined to read.
	var corrupt := SoftMount.compute(0.002, _REFERENCE_TIP_MASS_KG, {"shore_a": 120.0})
	results.append(TestResult.new(
		"a Shore reading outside the sold range refuses, and refuses AS no-mount rather than as a default pad",
		String(corrupt["tier"]).begins_with("insufficient_data")
			and is_inf(SoftMount.f_n_hz(0.002, _REFERENCE_TIP_MASS_KG, {"shore_a": 120.0})),
		"S=120A: tier %s, f_n %s" % [corrupt["tier"],
			str(SoftMount.f_n_hz(0.002, _REFERENCE_TIP_MASS_KG, {"shore_a": 120.0}))]))

	# -----------------------------------------------------------------------
	# The pad has mass and it lands at the tip — §5.3
	# -----------------------------------------------------------------------
	# Zero when no mount is fitted, so the reference build's frame mode is bit-identical to
	# pre-P8. Positive and monotonic in thickness when a mount IS fitted, because a thicker
	# pad is more material.
	results.append(TestResult.new(
		"no mount fitted means no mount mass — the reference build's frame mode is untouched by P8",
		SoftMount.mount_mass_kg(0.0) == 0.0,
		"SoftMount.mount_mass_kg(0.0) = %.6f g" % (SoftMount.mount_mass_kg(0.0) * 1000.0)))

	var mass_1mm := SoftMount.mount_mass_kg(0.001)
	var mass_2mm := SoftMount.mount_mass_kg(0.002)
	results.append(TestResult.new(
		"a thicker pad weighs more, and mass scales linearly with thickness",
		mass_1mm > 0.0 and absf(mass_2mm / mass_1mm - 2.0) < 1.0e-6,
		"1mm: %.4f g  2mm: %.4f g  ratio %.4f against 2.000"
			% [mass_1mm * 1000.0, mass_2mm * 1000.0, mass_2mm / mass_1mm]))

	# The mass IS small — §5.3 says so — but it is present. On the reference 60A/4mm²/4/1mm
	# grommet set, the pad adds ~19 mg to a 36.5 g tip, well under 0.1%. The claim being
	# tested is not that the effect is large; it is that the effect exists and points the
	# right way (§5.3's coupling: mount mass lowers the frame mode).
	var mass_ref := SoftMount.mount_mass_kg(_REFERENCE_THICKNESS_M)
	var f_bare := VibrationModel.resonance_hz_for(0.110, _REFERENCE_TIP_MASS_KG)
	var f_padded := VibrationModel.resonance_hz_for(0.110, _REFERENCE_TIP_MASS_KG + mass_ref)
	results.append(TestResult.new(
		"pad mass at the arm tip lowers the frame mode — small, but present, per §5.3",
		f_padded < f_bare and f_padded > f_bare * 0.999,
		"tip 36.5 g: %.4f Hz;  +%.3f mg pad: %.4f Hz  (drop %.6f Hz)"
			% [f_bare, mass_ref * 1.0e6, f_padded, f_bare - f_padded]))

	# -----------------------------------------------------------------------
	# The isolation formula is unchanged, but it now reads a computed f_n
	# -----------------------------------------------------------------------
	# Above the mount's natural frequency the pad attenuates; below sqrt(2)·f_n it amplifies.
	# The pre-P8 code proved the amplification/attenuation shape (test_vibration.gd); this
	# checks that when the pad's f_n is COMPUTED rather than scaled from 250 Hz, the same
	# T(r) < 1 above and T(r) > 1 below still holds — i.e. no regression at the interface.
	var model := VibrationModel.new(0.110)
	model.tip_load_kg = _REFERENCE_TIP_MASS_KG
	model.soft_mount_m = 0.002
	var f_n_model := model.mount_hz()
	var t_above := model.mount_transmissibility(3.0 * f_n_model)
	var t_below := model.mount_transmissibility(0.3 * f_n_model)
	results.append(TestResult.new(
		"transmissibility still attenuates above f_n and amplifies below — same isolator, computed f_n",
		t_above < 1.0 and t_below > 1.0,
		"f_n = %.1f Hz;  T(3·f_n) = %.3f (<1?);  T(0.3·f_n) = %.3f (>1?)"
			% [f_n_model, t_above, t_below]))

	# No mount fitted means transmissibility of exactly 1, everywhere — no branch for "bare"
	# anywhere in the vibration path, on the same "one code path" rule motor_spin_up.gd's
	# fallback follows.
	var bare_model := VibrationModel.new(0.110)
	bare_model.soft_mount_m = 0.0
	results.append(TestResult.new(
		"no mount means transmissibility = 1 exactly at every frequency, no branch for bare",
		is_inf(bare_model.mount_hz()) and bare_model.mount_transmissibility(100.0) == 1.0,
		"mount_hz = %s;  T(100 Hz) = %.6f"
			% [str(bare_model.mount_hz()), bare_model.mount_transmissibility(100.0)]))

	# -----------------------------------------------------------------------
	# Whole path: for_build reads the tweak, and pad mass reaches the frame mode
	# -----------------------------------------------------------------------
	# The reference build with a 2 mm pad tweak fitted should read a lower frame mode than the
	# same build bare, and the drop should match what SoftMount.mount_mass_kg predicts. This
	# is the wiring test — the tweak's slider, into AssemblyTweaks, into Build, into
	# VibrationModel — and it fails if any link in that chain drops the pad's mass on the way
	# through.
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.SOFT_MOUNT, 2.0)   # 2 mm pad
	var padded_build := ReferenceBuild.build()
	padded_build.set_assembly(tweaks.resolved_m(padded_build))
	var bare_build := ReferenceBuild.build()
	var padded_res := VibrationModel.for_build(padded_build).resonance_hz
	var bare_res := VibrationModel.for_build(bare_build).resonance_hz
	# Predicted: same arm, same motor+prop, tip mass raised by SoftMount.mount_mass_kg(0.002)
	# and resonance is anchored on sqrt(REFERENCE_TIP_MASS / (tip+mount)). So the predicted
	# ratio is sqrt(bare_tip / (bare_tip + mount_mass)).
	var bare_tip := VibrationModel.tip_mass_kg_for(bare_build)
	var mount_mass_2mm := SoftMount.mount_mass_kg(0.002)
	var predicted := sqrt(bare_tip / (bare_tip + mount_mass_2mm))
	results.append(TestResult.new(
		"the mount tweak's mass reaches the frame mode through for_build, by the documented sqrt law",
		absf((padded_res / bare_res) / predicted - 1.0) < 1.0e-4,
		"bare %.3f Hz  padded %.3f Hz  ratio %.6f against sqrt(m_bare/m_tip+mount) = %.6f"
			% [bare_res, padded_res, padded_res / bare_res, predicted]))

	return results
