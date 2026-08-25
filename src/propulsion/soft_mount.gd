class_name SoftMount
extends RefCounted
## The natural frequency of the anti-vibration pad between motor and arm, computed from
## published grommet specs rather than anchored on a guessed constant — propulsion.md §5 and
## slice P8.
##
## ## What this replaces
##
## Before P8, `vibration_model.gd` carried:
##
##     const MOUNT_REFERENCE_HZ := 250.0            # "GUESSED", per the file's own comment
##     const MOUNT_REFERENCE_THICKNESS_M := 0.001
##     f_n = MOUNT_REFERENCE_HZ * sqrt(MOUNT_REFERENCE_THICKNESS_M / thickness)
##
## Thickness was the only input. Material, hardness, contact area and grommet count — every
## one a published spec of every product on sale — did not exist in the physics. So a builder
## picking between a 50A and a 60A grommet was making a decision the model could not read.
##
## ## The physics, in the same shape §5.2 states
##
##     E (MPa)  = 0.0981 · (56 + 7.62336·S) / ( 0.137505 · (254 - 2.54·S) )     S = Shore A
##     k        = E · A_contact / t                per grommet
##     k_total  = k · N_grommets_per_motor
##     f_n      = (1 / 2·pi) · sqrt( k_total / m_supported )
##
## The correlation is Gent's — the standard published Shore A → Young's modulus form, cited
## in every rubber-mechanics textbook. It is a formula not a fit: nothing in this file is
## tuned to make a downstream number come out right.
##
## m_supported is the motor + prop + the grommet stack's own share, because the pad carries
## its own weight AND the tip. Grommet mass is small (a few milligrams to a gram per motor at
## typical FPV sizes) but present, and letting it approach zero silently would be the same
## kind of hidden zero motor_spin_up.gd was written to avoid.
##
## ## The class-typical defaults, and why they are here rather than authored per-mount
##
## No frame in the catalog lists which grommet a builder will fit under its motors — grommets
## are a hardware store item bought separately, and the catalog knows what the FRAME allows
## (bore diameter, depth of the motor mounting boss) rather than what the BUILDER will
## choose. So this file offers a class-typical default the same way motor_spin_up.gd offers a
## bell mass fraction: one number that is right for a common case, replaced by an authored
## per-mount spec the moment one is sourced.
##
## The default is a 60A silicone grommet at 4 mm² contact per grommet, 4 grommets per motor,
## silicone density 1200 kg/m³. Sourced positions (see docs/lothal/propulsion.md §5.2 and
## Sources): 60A is what the two commodity FPV grommet products this project's own spare bin
## contains actually read on a Shore A gauge; four grommets per motor is the geometry every
## quad frame in the catalog uses (four M3 screws through the motor mounting plate); 4 mm²
## is the crushed contact patch of a compressed 6 mm OD grommet — a lower bound on the true
## bearing area rather than the full grommet cross-section.
##
## ## The finding this file's introduction ships as one
##
## §5.2's rule: "run the correlation for a typical FPV grommet ... and see whether f_n lands
## anywhere near the 250 Hz the current constant assumes. If it does not, that is the
## finding, and it ships as one." tests/test_soft_mount.gd computes exactly this comparison
## and prints the ratio — the assertion is that the number lies within a band the old anchor
## could plausibly have been in, NOT that it equals 250 Hz. The formula was not tuned to
## produce agreement.
##
## ## Doubles
##
## Same rule as BladeGeometry and MotorSpinUp: every arithmetic step is GDScript `float`.
## E is order 1e6 Pa, A is order 1e-6 m², t is 1e-3 m — so k is order 1e3 N/m per grommet
## and a single-precision path would round the mount mass (order 1e-6 kg) below the ULP of
## the tip mass (order 1e-2 kg) and quietly report the pad as massless.

## Class-typical grommet properties. These are the pre-P8 defaults being made explicit; the
## door is open for a per-mount authored spec in the same shape motors specify their bell
## ratios. They are NOT tuned to reproduce the deleted 250 Hz — that comparison is exactly
## the finding tests/test_soft_mount.gd reports.
const _DEFAULT_SHORE_A := 60.0
const _DEFAULT_CONTACT_AREA_M2 := 4.0e-6      # 4 mm², one compressed 6 mm-OD grommet
const _DEFAULT_GROMMETS_PER_MOTOR := 4
const _DEFAULT_DENSITY_KG_M3 := 1200.0        # silicone rubber, class-typical
## Damping ratio for silicone/rubber isolators. Vibration textbook range is 0.05 to 0.15;
## 0.10 is the middle. Kept as the guess it always was — this file replaces the stiffness
## anchor, not the damping one, and pretending the damping is now sourced would be a lie
## with a number on it.
const DEFAULT_DAMPING_RATIO := 0.10


## Gent's Shore A → Young's modulus correlation, in MPa. Exact form of §5.2. Elementary and
## documented — nothing to tune here.
##
## Undefined at S = 100 (denominator zero) and refuses out-of-band Shore values: real Shore A
## readings are 20-90 for the pads sold as motor grommets, and 0 or 100 are catalog corruption
## rather than a soft or a rock-hard mount to be modelled.
static func youngs_modulus_pa(shore_a: float) -> float:
	if shore_a <= 0.0 or shore_a >= 100.0:
		return 0.0
	var numerator := 0.0981 * (56.0 + 7.62336 * shore_a)
	var denominator := 0.137505 * (254.0 - 2.54 * shore_a)
	return (numerator / denominator) * 1.0e6  # MPa -> Pa


## The full computation. Returns a dictionary the vibration model reads plus every
## intermediate a panel would want, on the same "render why" precedent motor_spin_up.gd
## established:
##
##     {
##         "f_n_hz":                  float,     the natural frequency, hertz
##         "youngs_modulus_pa":       float,
##         "stiffness_per_n_per_m":   float,     k per grommet, N/m
##         "stiffness_total_n_per_m": float,     k_total, N/m
##         "mount_mass_kg":           float,     the whole pad stack's mass
##         "m_supported_kg":          float,     motor + prop + pad share the pad carries
##         "damping_ratio":           float,     zeta, dimensionless
##         "tier":                    String,    "computed" | "insufficient_data:..." | "no_mount"
##     }
##
## `thickness_m` is the compressed pad thickness — the same tweak the builder sets in Lab.
## `tip_mass_kg` is what the pad carries above itself (motor + prop). `spec` is optional per-
## mount overrides (shore_a, contact_area_m2, grommets_per_motor, density_kg_m3,
## damping_ratio); anything absent falls back to the class-typical defaults above.
static func compute(thickness_m: float, tip_mass_kg: float,
		spec: Dictionary = {}) -> Dictionary:
	if thickness_m <= 0.0:
		return _no_mount()
	if tip_mass_kg <= 0.0:
		return _insufficient("tip_mass_non_positive")

	var shore_a := float(spec.get("shore_a", _DEFAULT_SHORE_A))
	var contact_area_m2 := float(spec.get("contact_area_m2", _DEFAULT_CONTACT_AREA_M2))
	var grommets := int(spec.get("grommets_per_motor", _DEFAULT_GROMMETS_PER_MOTOR))
	var density := float(spec.get("density_kg_m3", _DEFAULT_DENSITY_KG_M3))
	var zeta := damping_ratio_for(spec)

	var e_pa := youngs_modulus_pa(shore_a)
	if e_pa <= 0.0:
		return _insufficient("shore_a_out_of_band")
	if contact_area_m2 <= 0.0 or grommets <= 0 or density <= 0.0:
		return _insufficient("bad_grommet_spec")

	var k_per := e_pa * contact_area_m2 / thickness_m
	var k_total := k_per * float(grommets)

	# m = rho · A · t per grommet, summed across the four screws on one motor's mount plate.
	# A lower bound on the true grommet body mass (the crushed contact patch is smaller than
	# the whole grommet), but the doc's §5.3 is written in this shape and a fatter model
	# needs a spec no vendor lists.
	var mount_mass := density * contact_area_m2 * thickness_m * float(grommets)
	# The pad carries the tip AND itself. The self-mass share is a small correction on top of
	# the motor+prop but it belongs, on the same reasoning motor_spin_up.gd used to include
	# the blade inertia in J_total: an equation that could not tell the difference between a
	# heavy pad and a light one is not modelling the pad.
	var m_supported := tip_mass_kg + mount_mass
	if m_supported <= 0.0:
		return _insufficient("m_supported_non_positive")

	var f_n := (1.0 / TAU) * sqrt(k_total / m_supported)

	return {
		"f_n_hz": f_n,
		"youngs_modulus_pa": e_pa,
		"stiffness_per_n_per_m": k_per,
		"stiffness_total_n_per_m": k_total,
		"mount_mass_kg": mount_mass,
		"m_supported_kg": m_supported,
		"damping_ratio": zeta,
		"tier": "computed",
	}


## Just the frequency, for the vibration model's mount_hz() replacement. Returns INF when
## there is no mount fitted — same convention the pre-P8 mount_hz() used, so
## mount_transmissibility()'s "no branch for bare" property is preserved.
##
## INF is ALSO what a spec this file cannot evaluate returns (`insufficient_data:*` — a Shore
## reading outside the sold range, a non-positive contact area, a zero grommet count). That is
## deliberate and it is the refusing answer rather than a convenient one: an unreadable pad
## models as no pad, so transmissibility is exactly 1 and the vibration path reports what the
## frame does with nothing fitted. The alternative — falling back to a class-typical f_n — would
## quietly attribute isolation to a mount whose specs the model just declined to read.
## `compute()` carries the tier string for a panel that wants to say WHY.
static func f_n_hz(thickness_m: float, tip_mass_kg: float,
		spec: Dictionary = {}) -> float:
	var result := compute(thickness_m, tip_mass_kg, spec)
	if result["tier"] == "no_mount":
		return INF
	var value: float = float(result.get("f_n_hz", 0.0))
	return value if value > 0.0 else INF


## The pad's own mass, for adding to the frame's tip mass so the mode moves correctly. Zero
## when no mount is fitted — the reference build's frame mode is untouched by P8, which is
## §5.3's "small but present" claim made concrete.
static func mount_mass_kg(thickness_m: float, spec: Dictionary = {}) -> float:
	if thickness_m <= 0.0:
		return 0.0
	var contact_area_m2 := float(spec.get("contact_area_m2", _DEFAULT_CONTACT_AREA_M2))
	var grommets := int(spec.get("grommets_per_motor", _DEFAULT_GROMMETS_PER_MOTOR))
	var density := float(spec.get("density_kg_m3", _DEFAULT_DENSITY_KG_M3))
	if contact_area_m2 <= 0.0 or grommets <= 0 or density <= 0.0:
		return 0.0
	return density * contact_area_m2 * thickness_m * float(grommets)


## The damping ratio in force for this spec, so the vibration model reads a single source
## rather than duplicating the default.
##
## Guarded, because zeta reaches transmissibility as `2·zeta·r` in BOTH halves of the quotient:
## a spec carrying zero or a negative damping ratio would divide by zero at r = 1 and hand the
## vibration path an infinite gyro amplitude at exactly the frequency a builder is most likely
## to be looking at. An undamped isolator is not a real product; a corrupt field is. Out-of-band
## values fall back to the class-typical default rather than propagating.
static func damping_ratio_for(spec: Dictionary = {}) -> float:
	var zeta := float(spec.get("damping_ratio", DEFAULT_DAMPING_RATIO))
	return zeta if zeta > 0.0 and zeta < 1.0 else DEFAULT_DAMPING_RATIO


static func _no_mount() -> Dictionary:
	return {
		"f_n_hz": INF,
		"youngs_modulus_pa": 0.0,
		"stiffness_per_n_per_m": 0.0,
		"stiffness_total_n_per_m": 0.0,
		"mount_mass_kg": 0.0,
		"m_supported_kg": 0.0,
		"damping_ratio": DEFAULT_DAMPING_RATIO,
		"tier": "no_mount",
	}


static func _insufficient(reason: String) -> Dictionary:
	return {
		"f_n_hz": INF,
		"youngs_modulus_pa": 0.0,
		"stiffness_per_n_per_m": 0.0,
		"stiffness_total_n_per_m": 0.0,
		"mount_mass_kg": 0.0,
		"m_supported_kg": 0.0,
		"damping_ratio": DEFAULT_DAMPING_RATIO,
		"tier": "insufficient_data:" + reason,
	}
