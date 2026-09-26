class_name TestRustConstants
extends RefCounted
## Guards the constants that had to be DUPLICATED when the physics moved into the Rust crate.
##
## Rust cannot export consts to GDScript, so values that used to have exactly one definition
## now have two: the default battery chemistry (battery.rs vs build.gd), and air density
## (bemt.rs vs build.gd). Nothing structural keeps the copies equal — they agree today
## because they were written together, which is not a mechanism.
##
## P6's closure MOVED the air-density pin rather than dropping it. propeller.rs's copy of rho was
## the one this file used to invert, through `induced_velocity_mps`; that function, `power_factor`
## and the constant itself are all deleted, and the copy that decides thrust now is `bemt.rs`'s.
## The pin follows the physics: it inverts a BEMT solve, which is what actually runs.
##
## P5 DELETED the third duplicated pair. BLADE_COUNT_EXPONENT and PITCH_EXPONENT were pinned
## here by deriving them from PropellerModel.scale_k_t_to_prop; that function is gone,
## replaced by the BEMT geometry ratio (propulsion.md §0), which exists only in Rust and has
## no GDScript mirror to drift against. The cross-prop law is now verified in
## test_calibration.gd (the ratio IS BEMT(to)/BEMT(from); identity is bit-exact) and by the
## held-out points in test_validation.gd.

const EXPONENT_TOL := 1.0e-12

## Looser than EXPONENT_TOL because rho is recovered through a square root and a squaring rather
## than read back directly, so it carries a few ulps of round trip. Still nine orders of magnitude
## tighter than any drift worth having a test about: the smallest difference anyone would plausibly
## introduce is 1.225 vs 1.2250001.
const AIR_DENSITY_TOL := 1.0e-9

## One unit in the last digit ICAO publishes for standard sea-level density. See the check that
## uses it for why a derivation is not required to reproduce a rounding exactly.
const PUBLISHED_DENSITY_TOL := 0.0005


static func run() -> Array:
	var results: Array = []

	# --- Default battery chemistry ---
	# Rust falls back to its own DEFAULT_CHEMISTRY for any unrecognised string. If build.gd's
	# copy named a different chemistry, a pack saved without one would be modelled as LiPo and
	# labelled Li-ion (or the reverse) with no error anywhere.
	var unknown_nominal: float = BatteryModel.nominal_cell_v("not-a-real-chemistry")
	var gdscript_default_nominal: float = BatteryModel.nominal_cell_v(Build.BATTERY_DEFAULT_CHEMISTRY)
	results.append(TestResult.new(
		"Rust's unknown-chemistry fallback IS build.gd's BATTERY_DEFAULT_CHEMISTRY",
		absf(unknown_nominal - gdscript_default_nominal) < EXPONENT_TOL,
		"unknown -> %.4f V/cell, \"%s\" -> %.4f V/cell" % [
			unknown_nominal, Build.BATTERY_DEFAULT_CHEMISTRY, gdscript_default_nominal]
	))

	# The fallback assertion above passes vacuously if the two chemistries happen to share a
	# nominal voltage, so pin that they do NOT — this is what gives the previous check teeth.
	var lipo: float = BatteryModel.nominal_cell_v("LiPo")
	var liion: float = BatteryModel.nominal_cell_v("Li-ion")
	results.append(TestResult.new(
		"LiPo and Li-ion have different nominal voltages, so the fallback check can fail",
		absf(lipo - liion) > 0.01,
		"LiPo %.2f V/cell vs Li-ion %.2f V/cell" % [lipo, liion]
	))

	# --- Air density: the DEFAULT, derived the same way, from what Rust computes with it ---
	#
	# HOW THIS CHECK CHANGED, AND WHY IT HAD TO. propeller.rs's copy of rho was documented as
	# pinned to Build.AIR_DENSITY_KGM3 by this file for a fortnight before the pin was written. It
	# was not, and the two could have drifted at any point with every other test still passing.
	#
	# The pin, as first written, inverted the hover branch of Glauert's inflow — at
	# V_axial = V_edge = 0 the fixed point is seeded at v_h and stays there, so
	#
	#     v_i = v_h = sqrt( T / (2*rho*A) )    =>    rho = T / (2*A*v_i^2)
	#
	# recovering the rho Rust actually applied rather than one an accessor merely reports.
	#
	# Then rho became a RUNTIME PARAMETER on both sides, because a builder in Bangalore flies in
	# 16% less air than sea level. That quietly destroyed the check above: inverting Glauert on a
	# call that was HANDED a density recovers the number the test just passed in, which is
	# arithmetic on the test's own input. It would still have passed. It would still have read as
	# meaningful. And it would have been measuring parameter passing — the exact green-but-empty
	# failure this file exists to prevent, arriving as a side effect of fixing it.
	#
	# So the check now hands in a NON-POSITIVE density, which is the one input that makes Rust fall
	# back to its own constant (air_density_or_default). The value recovered is therefore Rust's
	# default, under the test's control in no way at all, and comparing it to build.gd's constant
	# is once again a statement about the two copies rather than about the argument list.
	# The inversion is now BEMT's, and it is simpler than Glauert's was: every term on both sides
	# of the annulus closure is linear in rho, so rho cancels out of the induced-velocity fixed
	# point entirely and THRUST IS EXACTLY PROPORTIONAL TO IT. So one solve at rho = 1 and one at a
	# non-positive rho — the single input that makes Rust fall back to its own constant — recover
	# that constant as a ratio of two thrusts, with nothing of the test's own left in it.
	var polar := BemtModel.global_polar()
	var t_at_unit: float = _solve_thrust(1.0, polar)
	var t_at_default: float = _solve_thrust(-1.0, polar)
	var rust_default_rho: float = t_at_default / t_at_unit
	results.append(TestResult.new(
		"the air density Rust falls back to equals Build.AIR_DENSITY_KGM3",
		absf(rust_default_rho - Build.AIR_DENSITY_KGM3) < AIR_DENSITY_TOL,
		"rust defaults to %.12f kg/m3, build.gd states %.12f kg/m3" % [
			rust_default_rho, Build.AIR_DENSITY_KGM3]
	))

	# GDScript's own standard air must be that same number, or build.gd's constant would agree with
	# Rust while the DERIVATION every Build actually runs on disagreed with both. Three copies now,
	# and the third is the one the product uses.
	#
	# CHECKED TO THE PRECISION THE PUBLISHED FIGURE CARRIES, not to AIR_DENSITY_TOL, and the reason
	# is a real disagreement rather than float noise: 101325 / (287.058 * 288.15) is 1.2249781, and
	# 1.225 is ICAO's published value already rounded to four significant figures. They are the same
	# number to the precision the standard states it in, and the derivation is the more precise of
	# the two by 0.0018%. Pinning them at 1e-9 would be demanding that a derivation reproduce a
	# rounding, which is the wrong way round — so the tolerance is one unit in the last published
	# place, which is tight enough that a real drift (1.225 vs 1.19, or a lapse-rate typo) still
	# fails and loose enough that being MORE accurate than the almanac is not an error.
	results.append(TestResult.new(
		"AirDensity's derivation at 0 m, 15 C agrees with Build.AIR_DENSITY_KGM3 to its last published digit",
		absf(AirDensity.standard_kgm3() - Build.AIR_DENSITY_KGM3) < PUBLISHED_DENSITY_TOL,
		"derived %.7f kg/m3, published constant %.7f kg/m3, difference %.5f%%" % [
			AirDensity.standard_kgm3(), Build.AIR_DENSITY_KGM3,
			100.0 * absf(AirDensity.standard_kgm3() / Build.AIR_DENSITY_KGM3 - 1.0)]
	))

	# --- And the half the default check can no longer cover: that rho is PLUMBED ---
	#
	# The two checks above pin three constants together and say nothing whatever about whether a
	# Build's air ever reaches Rust. Dropping the parameter at the seam — passing standard air
	# regardless of the field — leaves both of them green.
	#
	# So this one perturbs the air and asserts the thrust moved by the amount proportionality
	# DEMANDS, computed here independently. That is what stops it degenerating into the same
	# tautology by another route: it is not asserting the output changed, which passing any
	# parameter through would achieve, but that it changed to the value the physics requires.
	var thin_rho: float = AirDensity.new(3500.0, 20.0).kgm3()
	var t_thin: float = _solve_thrust(thin_rho, polar)
	results.append(TestResult.new(
		"a supplied air density is the one Rust solves on, to the value the physics demands",
		absf(t_thin - thin_rho * t_at_unit) < AIR_DENSITY_TOL * t_at_unit,
		"at rho %.6f: rust %.9f N, rho x T(1 kg/m3) %.9f N" % [
			thin_rho, t_thin, thin_rho * t_at_unit]
	))

	# The check above passes vacuously if thin air happens to give the same thrust as standard
	# air, so pin that it does not — the same discipline the LiPo/Li-ion pair gets above.
	results.append(TestResult.new(
		"thin air gives a different thrust from standard, so the check above can fail",
		absf(t_thin - t_at_default) / t_at_default > 0.01,
		"3500 m: %.4f N vs standard: %.4f N" % [t_thin, t_at_default]
	))

	return results


## One BEMT solve on the reference propeller at a fixed RPM, returning thrust. The prop and the RPM
## are held constant across every call so the ONLY thing that varies between them is rho — which is
## what makes a ratio of two of them a statement about the density and nothing else.
static func _solve_thrust(rho: float, polar: PackedFloat64Array) -> float:
	var doc := PropellerDocument.new()
	doc.diameter_mm = 127.0
	doc.pitch_mm = 114.3
	doc.blades = 3
	doc.chord = PropellerDocument.generate_chord(127.0, 3)
	return BemtModel.solve(rho, doc.diameter_mm * 0.001, doc.pitch_mm * 0.001,
		float(doc.blades), 20000.0, doc.chord,
		polar[0], polar[1], polar[2], polar[3])[0]
