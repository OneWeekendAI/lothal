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

	# -----------------------------------------------------------------------
	# SM1 — mounts as parts. One result per entry and one per required field, so the failure count
	# says how many entries or fields are wrong rather than "the loop failed".
	# -----------------------------------------------------------------------
	var catalog := PartsCatalog.load_default()
	results.append(_test_the_mount_category_loads(catalog))
	for part in catalog.list_category("mount"):
		results.append(_test_a_mount_entry_computes(part))
		results.append(_test_a_mount_entrys_mass_is_derived(part))
		results.append(_test_a_mount_entry_says_what_it_guessed(part))
	for field in SoftMount.PART_SPEC_FIELDS:
		results.append(_test_a_missing_field_is_refused_not_defaulted(catalog, field))

	# SM2 — Build.mount_id reaches VibrationModel.soft_mount_spec.
	results.append(_test_a_50a_and_a_70a_mount_give_different_mount_frequencies())
	results.append(_test_an_empty_mount_id_is_the_build_it_always_was())
	results.append(_test_a_fitted_mount_is_a_pad_by_default())
	results.append(_test_a_twin_at_another_field_keeps_its_mount())

	return results


# ---------------------------------------------------------------------------
# SM1 — data/parts/mounts.json
# ---------------------------------------------------------------------------

## The reference motor and prop: what a mount entry is computed carrying. Any positive tip mass would
## do for a tier check; this one is the aircraft the rest of the suite is pinned to.
static func _reference_tip_kg() -> float:
	return VibrationModel.tip_mass_kg_for(ReferenceBuild.build())


## The category is registered and the loader read it. Three entries is the floor because the slice
## asks for a softer and a firmer pad beside the default, and SM2's 50A-vs-70A check needs both.
##
## MUTATION CONFIRMED RED: delete the "mount" line from `PartsCatalog.CATEGORY_FILES` (0 entries).
static func _test_the_mount_category_loads(catalog: PartsCatalog) -> TestResult:
	var mounts := catalog.list_category("mount")
	return TestResult.new(
		"[SM1] the mounts category loads with no errors and at least three entries",
		mounts.size() >= 3 and catalog.load_errors.is_empty(),
		"%d mounts, load errors %s" % [mounts.size(), catalog.load_errors])


## Each shipped entry earns "computed": every field present and in band. A finite, positive f_n is
## required alongside the tier, because a tier string alone would pass a compute that labelled a
## NaN.
##
## MUTATION CONFIRMED RED: `"shore_a": 100.0` on mount_grommet_60a (insufficient_data:
## shore_a_out_of_band, for that entry's result only).
static func _test_a_mount_entry_computes(part: Dictionary) -> TestResult:
	var result := SoftMount.compute_part(part, _reference_tip_kg())
	var f_n := float(result["f_n_hz"])
	return TestResult.new(
		"[SM1] %s computes from its own fields" % part["part_id"],
		result["tier"] == "computed" and is_finite(f_n) and f_n > 0.0,
		"tier %s, f_n %.1f Hz" % [result["tier"], f_n])


## `mass_g` is carried, not authored: it must be `SoftMount.mount_mass_kg` at the entry's own
## thickness. guards.json's rule, for guards.json's reason — no mass may be written here that the
## physics would not also produce.
##
## MUTATION CONFIRMED RED: `"mass_g": 0.02` on mount_grommet_70a_firm.
static func _test_a_mount_entrys_mass_is_derived(part: Dictionary) -> TestResult:
	var spec := SoftMount.spec_from_part(part)
	var computed_g := SoftMount.mount_mass_kg(float(spec.get("thickness_m", 0.0)), spec) * 1000.0
	var authored_g := float(part.get("mass_g", -1.0))
	return TestResult.new(
		"[SM1] %s carries the mass its own fields give" % part["part_id"],
		computed_g > 0.0 and absf(authored_g - computed_g) < 1.0e-6,
		"mass_g %.6f g, SoftMount %.6f g" % [authored_g, computed_g])


## An entry that guessed says so. `assumed` must exist, name only real spec fields, and — when it is
## not empty — the entry's `source` must call the values class-typical. A product somebody actually
## measured would carry an empty list and no such word; nothing in the catalog is that yet, and the
## check is what stops a guessed 50A from reading like a measured one.
##
## MUTATION CONFIRMED RED: drop "class-typical" from mount_grommet_50a_soft's source.
static func _test_a_mount_entry_says_what_it_guessed(part: Dictionary) -> TestResult:
	var problems: Array[String] = []
	if not (part.get("assumed") is Array):
		problems.append("no `assumed` list")
	else:
		for field in part["assumed"]:
			if not SoftMount.PART_SPEC_FIELDS.has(String(field)):
				problems.append("assumed names %s, which is not a spec field" % field)
		if not (part["assumed"] as Array).is_empty() \
				and not String(part.get("source", "")).contains("class-typical"):
			problems.append("assumes %s but its source never says class-typical" % [part["assumed"]])
	return TestResult.new(
		"[SM1] %s says which of its fields are class-typical guesses" % part["part_id"],
		problems.is_empty(),
		"assumed %s%s" % [part.get("assumed"), "" if problems.is_empty() else ": " + str(problems)])


## A field the entry left out is refused, NOT filled from the class-typical default. The default
## entry itself is the subject because it is the one case where defaulting would be invisible: its
## values ARE the defaults, so a reader that filled the gap would compute the same frequency it
## computes with the field present. Only the tier can tell — and f_n must be INF and the pad's mass
## zero, the refusing answers.
##
## MUTATIONS CONFIRMED RED (3 of 3): the `missing` check in `SoftMount.compute` made `if false and …`
## (all 5 fields: compute reads "computed"); the guard in `SoftMount.mount_mass_kg` dropped (all 5:
## the pad weighs something); the check in `SoftMount.compute_part` made `if false and …` (thickness
## only: "no_mount" — for the other four `compute`'s own check still refuses, so that line is
## load-bearing for exactly the field that would otherwise read as no pad at all).
static func _test_a_missing_field_is_refused_not_defaulted(catalog: PartsCatalog,
		field: String) -> TestResult:
	var part: Dictionary = catalog.get_part("mount_grommet_60a").duplicate(true)
	(part["specs"] as Dictionary).erase(field)
	var result := SoftMount.compute_part(part, _reference_tip_kg())
	var spec := SoftMount.spec_from_part(part)
	var mass := SoftMount.mount_mass_kg(0.001, spec)
	var via_compute := SoftMount.compute(0.001, _reference_tip_kg(), spec)
	return TestResult.new(
		"[SM1] a mount entry without %s is insufficient_data, not the default" % field,
		result["tier"] == "insufficient_data:missing_" + field \
			and via_compute["tier"] == "insufficient_data:missing_" + field \
			and not is_finite(float(result["f_n_hz"])) and mass == 0.0,
		"compute_part %s, compute %s, mass %.6f kg" % [result["tier"], via_compute["tier"], mass])


# ---------------------------------------------------------------------------
# SM2 — Build.mount_id
# ---------------------------------------------------------------------------

## The reference build's parts with `mount_id` fitted, and its assembly resolved from a fresh
## configuration — so the pad is the tweak's as-built default, the posture Lab builds with.
static func _reference_with_mount(mount_id: String) -> Build:
	var build := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, null, "", {}, mount_id)
	build.set_assembly(AssemblyTweaks.new().resolved_m(build))
	return build


## The slice's own proof: picking a 50A vs a 70A mount moves `mount_hz()`, in the direction the
## physics says (harder rubber, stiffer spring, higher f_n), and each lands on exactly what
## `SoftMount` computes from that part's own fields at the pad the build carries.
##
## MUTATION CONFIRMED RED: `VibrationModel.soft_mount_spec_for` returning `{}` for every build (both
## mounts read the 60A default: 200.0 Hz twice).
static func _test_a_50a_and_a_70a_mount_give_different_mount_frequencies() -> TestResult:
	var soft := _reference_with_mount("mount_grommet_50a_soft")
	var firm := _reference_with_mount("mount_grommet_70a_firm")
	var soft_hz := VibrationModel.for_build(soft).mount_hz()
	var firm_hz := VibrationModel.for_build(firm).mount_hz()
	var expected_soft := SoftMount.f_n_hz(float(soft.assembly_value("soft_mount_m")),
		VibrationModel.tip_mass_kg_for(soft), SoftMount.spec_from_part(soft.mount))
	var expected_firm := SoftMount.f_n_hz(float(firm.assembly_value("soft_mount_m")),
		VibrationModel.tip_mass_kg_for(firm), SoftMount.spec_from_part(firm.mount))
	return TestResult.new(
		"[SM2] a 70A mount puts the mount mode above a 50A one, each at its own part's f_n",
		is_finite(soft_hz) and firm_hz > soft_hz and soft_hz == expected_soft \
			and firm_hz == expected_firm,
		"50A %.3f Hz (SoftMount %.3f), 70A %.3f Hz (SoftMount %.3f)" % [
			soft_hz, expected_soft, firm_hz, expected_firm])


## `mount_id = ""` is the build it always was: no mount part, the empty spec, no pad by default, and
## the same vibration numbers as the reference build made the pre-SM2 way — compared with `==`,
## because bit-identical is the claim.
##
## MUTATION CONFIRMED RED: `refit_from` falling back to `mount_grommet_60a` for an empty id (spec no
## longer empty, the pad defaults to 1.0 mm, and mount_hz goes from INF to 200 Hz).
static func _test_an_empty_mount_id_is_the_build_it_always_was() -> TestResult:
	var before := ReferenceBuild.build()
	before.set_assembly(AssemblyTweaks.new().resolved_m(before))
	var after := _reference_with_mount("")
	var a := VibrationModel.for_build(before)
	var b := VibrationModel.for_build(after)
	return TestResult.new(
		"[SM2] an empty mount id leaves the reference build bit-identical",
		after.mount.is_empty() and b.soft_mount_spec.is_empty() \
			and a.mount_hz() == b.mount_hz() and a.resonance_hz == b.resonance_hz \
			and a.soft_mount_m == b.soft_mount_m \
			and before.mass_properties.total_mass_kg == after.mass_properties.total_mass_kg,
		"mount %s, spec %s, f_n %s vs %s, frame mode %.9f vs %.9f Hz, %.6f vs %.6f g" % [
			after.mount.get("part_id", "none"), b.soft_mount_spec, a.mount_hz(), b.mount_hz(),
			a.resonance_hz, b.resonance_hz, before.mass_properties.total_mass_kg * 1000.0,
			after.mass_properties.total_mass_kg * 1000.0])


## A mount that is fitted is a pad that is there: the "Motor soft mount" tweak's as-built default is
## the part's own nominal thickness, and zero with none fitted. Without it a picked mount would be
## modelled at zero thickness — no_mount — and the 50A/70A choice would move nothing until the
## builder also found the tweak.
##
## MUTATION CONFIRMED RED: `AssemblyTweaks.limits` SOFT_MOUNT "default" back to `0.0` (the fitted
## build reads 0.0 mm).
static func _test_a_fitted_mount_is_a_pad_by_default() -> TestResult:
	var tweaks := AssemblyTweaks.new()
	var fitted := _reference_with_mount("mount_grommet_70a_firm")
	var bare := _reference_with_mount("")
	var fitted_mm := tweaks.value_mm(AssemblyTweaks.SOFT_MOUNT, fitted)
	var bare_mm := tweaks.value_mm(AssemblyTweaks.SOFT_MOUNT, bare)
	var part_mm := float(fitted.mount["specs"]["thickness_mm"])
	return TestResult.new(
		"[SM2] a fitted mount defaults the pad to the part's own thickness, and no mount to none",
		fitted_mm == part_mm and bare_mm == 0.0,
		"fitted %.3f mm (part %.3f mm), bare %.3f mm" % [fitted_mm, part_mm, bare_mm])


## The same aircraft at another field carries the same mount — `at_air`'s rule for the guard.
##
## MUTATION CONFIRMED RED: `at_air` computing `m_id` as `""` (twin mount none).
static func _test_a_twin_at_another_field_keeps_its_mount() -> TestResult:
	var build := _reference_with_mount("mount_grommet_50a_soft")
	var twin := build.at_air(AirDensity.standard())
	return TestResult.new(
		"[SM2] a build's twin at another field keeps its soft mount",
		str(twin.mount.get("part_id", "")) == "mount_grommet_50a_soft",
		"twin mount %s" % twin.mount.get("part_id", "none"))
