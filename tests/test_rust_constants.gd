class_name TestRustConstants
extends RefCounted
## Guards the constants that had to be DUPLICATED when the physics moved into the Rust crate.
##
## Rust cannot export consts to GDScript, so four values that used to have exactly one
## definition now have two: the blade-count and pitch exponents (propeller.rs vs
## prop_extrapolation.gd and prop_plausibility.gd), the default battery chemistry
## (battery.rs vs build.gd), and air density (propeller.rs vs build.gd). Nothing structural
## keeps the copies equal — they agree today because they were written together, which is
## not a mechanism.
##
## That matters more than it looks. prop_extrapolation.gd PRINTS its copy of the exponent to
## the user ("the blades^0.8 rule of thumb") while the Rust copy is what actually scales k_t.
## Drift would make the app state one law and apply another, and every existing test would
## still pass, because each side is self-consistent.
##
## The exponents are NOT read from a Rust accessor here — they are DERIVED from what
## scale_k_t_to_prop actually computes, by handing it unit geometry and changing one factor
## at a time. Feeding it 1 -> 2 blades at fixed diameter and pitch leaves k_t' = 2^blade_exp,
## so log2 of the answer is the exponent the Rust really applied. An accessor would only
## prove Rust can report a number; this proves Rust USES it.

const EXPONENT_TOL := 1.0e-12

## Looser than EXPONENT_TOL because rho is recovered through a square root and a squaring rather
## than read back directly, so it carries a few ulps of round trip. Still nine orders of magnitude
## tighter than any drift worth having a test about: the smallest difference anyone would plausibly
## introduce is 1.225 vs 1.2250001.
const AIR_DENSITY_TOL := 1.0e-9


static func run() -> Array:
	var results: Array = []

	# --- Smoke guard: the derivation only means something if the identity case holds. ---
	# Same prop in and out must return k_t unchanged. If this fails, every exponent below is
	# measuring a broken function rather than a constant, and the passes would be worthless.
	var identity: float = PropellerModel.scale_k_t_to_prop(1.0, 0.127, 0.109, 3.0, 0.127, 0.109, 3.0)
	results.append(TestResult.new(
		"scale_k_t_to_prop is the identity on an unchanged prop (guards the derivations below)",
		absf(identity - 1.0) < EXPONENT_TOL,
		"k_t' / k_t = %.15f" % identity
	))

	# --- Blade-count exponent, derived from behaviour ---
	# 1 -> 2 blades, diameter and pitch held at 1.0, so k_t' = 2^BLADE_COUNT_EXPONENT.
	var blade_doubled: float = PropellerModel.scale_k_t_to_prop(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0)
	var blade_exponent: float = log(blade_doubled) / log(2.0)
	results.append(TestResult.new(
		"the blade-count exponent Rust APPLIES equals prop_extrapolation.gd's printed copy",
		absf(blade_exponent - PropExtrapolation.BLADE_COUNT_EXPONENT) < EXPONENT_TOL,
		"rust applies %.15f, GDScript states %.15f" % [blade_exponent, PropExtrapolation.BLADE_COUNT_EXPONENT]
	))
	results.append(TestResult.new(
		"prop_plausibility.gd's second copy of the blade-count exponent agrees too",
		absf(blade_exponent - PropPlausibility.BLADE_COUNT_EXPONENT) < EXPONENT_TOL,
		"rust applies %.15f, prop_plausibility states %.15f" % [blade_exponent, PropPlausibility.BLADE_COUNT_EXPONENT]
	))

	# --- Pitch exponent, same method ---
	var pitch_doubled: float = PropellerModel.scale_k_t_to_prop(1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0)
	var pitch_exponent: float = log(pitch_doubled) / log(2.0)
	results.append(TestResult.new(
		"the pitch exponent Rust APPLIES equals prop_extrapolation.gd's printed copy",
		absf(pitch_exponent - PropExtrapolation.PITCH_EXPONENT) < EXPONENT_TOL,
		"rust applies %.15f, GDScript states %.15f" % [pitch_exponent, PropExtrapolation.PITCH_EXPONENT]
	))

	# --- Diameter exponent: the one law that is exact, not a rule of thumb ---
	# Stated as D^4 in physics.md and in the user-facing string. Derived the same way.
	var diameter_doubled: float = PropellerModel.scale_k_t_to_prop(1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0)
	var diameter_exponent: float = log(diameter_doubled) / log(2.0)
	results.append(TestResult.new(
		"the diameter exponent is exactly 4 — the dimensional law, not a fitted guess",
		absf(diameter_exponent - 4.0) < EXPONENT_TOL,
		"rust applies D^%.15f" % diameter_exponent
	))

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

	# --- Air density, derived the same way: from what Rust COMPUTES with it ---
	# propeller.rs's copy of rho was documented as pinned to Build.AIR_DENSITY_KGM3 by this file
	# for a fortnight before the pin was actually written. It was not. The two could have drifted
	# at any point and every other test would still have passed, because each side is
	# self-consistent — the airframe would have been dragged through one atmosphere while its own
	# rotors hovered in another.
	#
	# There is no accessor for rho and there should not be one; an accessor proves Rust can report
	# a number, not that it uses it. Instead invert the hover branch of Glauert's inflow. At
	# V_axial = V_edge = 0 the fixed point is seeded at v_h and stays there, so
	#
	#     v_i = v_h = sqrt( T / (2*rho*A) )    =>    rho = T / (2*A*v_i^2)
	#
	# recovers exactly the rho that induced_velocity_mps — and therefore power_factor, and
	# therefore every flight-time and top-speed figure downstream of it — actually applied.
	var disc_area: float = PropellerModel.disc_area_m2(1.0)
	var v_hover: float = PropellerModel.induced_velocity_mps(1.0, 1.0, 0.0, 0.0)
	var rust_rho: float = 1.0 / (2.0 * disc_area * v_hover * v_hover)
	results.append(TestResult.new(
		"the air density Rust APPLIES in Glauert inflow equals Build.AIR_DENSITY_KGM3",
		absf(rust_rho - Build.AIR_DENSITY_KGM3) < AIR_DENSITY_TOL,
		"rust applies %.12f kg/m3, build.gd states %.12f kg/m3" % [rust_rho, Build.AIR_DENSITY_KGM3]
	))

	return results
