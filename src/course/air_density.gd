class_name AirDensity
extends RefCounted
## The air a course is flown in, derived from where the field is and how warm it is that day.
##
## Lothal quoted every headline number for dry air at 15 C at sea level, which is weather most of
## its users do not have. Bangalore at 920 m on a 35 C afternoon is 16.3% down on that, and 16.3%
## of the air is 16.3% of the thrust — a builder who trusts a marginal thrust-to-weight at sea
## level finds out the hard way at altitude.
##
## ---------------------------------------------------------------------------
## WHY THIS IS TWO INPUTS AND NOT ONE
## ---------------------------------------------------------------------------
##
## parts.md's rule: ask the builder for what they can look up, derive the rest. A builder knows
## their field elevation, and they know roughly how warm it gets. NOBODY knows their air density
## in kg/m3. So elevation and temperature are asked for and rho is derived and shown back.
##
## The two are combined the way a pilot computes density altitude, and the asymmetry is
## deliberate: PRESSURE comes from the standard atmosphere at the field's elevation, because the
## pressure at a place is a fact about that place; TEMPERATURE is the builder's own, because how
## warm it is is a fact about today. Mixing a standard pressure with a real temperature is the
## correct combination, not a compromise between two half-measures.
##
## ---------------------------------------------------------------------------
## THIS ONE IS NOT A GUESS, WHICH IS UNUSUAL HERE
## ---------------------------------------------------------------------------
##
## Almost every other constant in this project has to admit what it is. FIGURE_OF_MERIT is an
## outright guess with no source. REFERENCE_RESONANCE_HZ is characteristic. The blade-count and
## pitch exponents are documented rules of thumb the shipped catalog cannot validate.
##
## Rho is not in that company, and the comment says so BECAUSE it is unusual here. The barometric
## formula and the ideal gas law are textbook and exact within the troposphere, and every constant
## below is defined rather than fitted. Per validation.md's tiers this is the strongest claim
## anything in Lothal makes.
##
## AND IT DISAGREES WITH THE OLD CONSTANT IN THE FIFTH DECIMAL, which is worth stating rather than
## rounding away. 101325 / (287.058 * 288.15) is **1.2249781**, not 1.225. The two are the same
## number: 1.225 is the value ICAO PUBLISHES for standard sea-level density, already rounded to
## four significant figures, and it is what this project hardcoded for its whole life. The
## derivation is simply the more precise of the two, by 0.0018%.
##
## Nothing is renamed or corrected on the strength of that. Build.AIR_DENSITY_KGM3 stays 1.225,
## because it is the published constant and it is what the Rust copy is pinned against; the
## derivation is what every Build actually runs on. Where the two meet — the k_t density ratio —
## the derivation appears in BOTH numerator and denominator and cancels exactly, so the reference
## build's 496.0 g / 11.69:1 / 29.6% are untouched to the bit. The one place the difference is
## observable is the drag coefficient, which moves by 0.0018% and changes top speed in its fifth
## digit. That is the correct direction: the model now uses the number rather than its rounding.
##
## ---------------------------------------------------------------------------
## HUMIDITY IS SKIPPED, AND HERE IS THE MEASUREMENT RATHER THAN THE WORD "NEGLIGIBLE"
## ---------------------------------------------------------------------------
##
## This models DRY air. Moist air is less dense, and the size of that is measurable rather than
## something to wave at:
##
##     temperature      dry      saturated     difference
##          5 C       1.2690      1.2649         -0.33%
##         15 C       1.2250      1.2172         -0.63%
##         25 C       1.1839      1.1699         -1.18%
##         35 C       1.1455      1.1215         -2.10%
##
## So at the hottest realistic field it is worth about 2%, comparable to 200 m of elevation. It is
## skipped anyway, for three reasons:
##
## 1. It fails "derived, not typed" in a way the other two inputs do not. Elevation is a permanent
##    fact about a place; temperature is one a builder can bound honestly. The relative humidity on
##    the unspecified future day they will fly is neither — it would be a guess fed into an exact
##    formula, which is false precision.
## 2. Most of the effect arrives WITH heat, and the temperature input already carries that. The
##    2.10% exists only at 35 C; at 15 C it is 0.63%. The two are not independent, and the one a
##    builder can answer carries most of the signal.
## 3. The residual bias is small, one-directional and in company: dry air is denser, so this
##    OVERSTATES rho and therefore overstates thrust, by at most ~2% — the same direction as
##    j_zero's omission and the constant-profile-power assumption in propeller.rs.
##
## The table is here rather than the word "negligible" so a future reader can overrule this
## decision with data instead of taking it on trust.

## Defined constants of the International Standard Atmosphere. Every one of these is a DEFINITION
## rather than a measurement, which is what lets the claim above stand.
const SEA_LEVEL_PRESSURE_PA := 101325.0
const SEA_LEVEL_TEMPERATURE_K := 288.15
## Tropospheric lapse rate, K/m. The formula is exact for this lapse and no other; a real
## inversion is a fact about a DAY rather than about a place, and is out of scope (design §9).
const LAPSE_RATE_K_PER_M := 0.0065
## Standard gravity. Deliberately NOT Build.GRAVITY_MPS2, and they must not be unified: 9.81 is
## the rounded figure the mass and thrust model uses, while 9.80665 is the defined constant that
## appears in the DEFINITION of the standard atmosphere. Substituting the rounded one here would
## quietly downgrade this from an exact derivation to an approximate one to save a character.
const STANDARD_GRAVITY_MPS2 := 9.80665
const MOLAR_MASS_AIR_KG_PER_MOL := 0.0289644
const UNIVERSAL_GAS_CONSTANT := 8.31446
## Specific gas constant for DRY air, J/(kg K) — see the humidity note above for what "dry" costs.
const SPECIFIC_GAS_CONSTANT_DRY_AIR := 287.058

const KELVIN_AT_ZERO_C := 273.15

## Standard conditions: the air every number in this project was quoted in before this existed,
## and the air the oracle is pinned at for ever (design §4).
const STANDARD_ELEVATION_M := 0.0
const STANDARD_TEMPERATURE_C := 15.0

## The domain the formula is honest over, and the reason it is CLAMPED rather than merely
## documented: the barometric term contains (1 - L*h/T0) raised to a fractional power, which is
## NaN above ~44 km and would propagate silently through every derived stat as "nan g" on screen.
## The tropopause is the real limit — the lapse rate changes there and this formula stops being
## exact — and the lower bound is the Dead Sea, which is the lowest ground on the planet.
const MIN_ELEVATION_M := -500.0
const MAX_ELEVATION_M := 11000.0
## Wider than any flyable weather, on purpose. This is a NaN guard, not a judgement about where
## somebody is allowed to fly — Lothal warns, it does not block.
const MIN_TEMPERATURE_C := -80.0
const MAX_TEMPERATURE_C := 80.0

var elevation_m := STANDARD_ELEVATION_M
var temperature_c := STANDARD_TEMPERATURE_C


func _init(p_elevation_m: float = STANDARD_ELEVATION_M,
		p_temperature_c: float = STANDARD_TEMPERATURE_C) -> void:
	elevation_m = clampf(p_elevation_m, MIN_ELEVATION_M, MAX_ELEVATION_M)
	temperature_c = clampf(p_temperature_c, MIN_TEMPERATURE_C, MAX_TEMPERATURE_C)


## Sea level, 15 C. The oracle's air, and what a course that never said otherwise is flown in.
static func standard() -> AirDensity:
	return AirDensity.new()


## Pressure at this elevation, from the barometric formula on the standard lapse rate.
##
##     P = P0 * (1 - L*h/T0) ^ (g*M / (R*L))
##
## Note this uses the STANDARD temperature profile, not the builder's temperature, and that is
## correct rather than an oversight — see the header. The pressure at a place is what its
## elevation makes it; the builder's thermometer describes the air sitting at that pressure.
func pressure_pa() -> float:
	var exponent := (STANDARD_GRAVITY_MPS2 * MOLAR_MASS_AIR_KG_PER_MOL) / (
			UNIVERSAL_GAS_CONSTANT * LAPSE_RATE_K_PER_M)
	var ratio := 1.0 - (LAPSE_RATE_K_PER_M * elevation_m) / SEA_LEVEL_TEMPERATURE_K
	return SEA_LEVEL_PRESSURE_PA * pow(ratio, exponent)


## Air density in kg/m3, from the ideal gas law at the builder's own temperature.
##
##     rho = P / (R_specific * T)
func kgm3() -> float:
	return pressure_pa() / (SPECIFIC_GAS_CONSTANT_DRY_AIR * (temperature_c + KELVIN_AT_ZERO_C))


## Density at standard conditions. Computed through the same path rather than written as 1.225, so
## the two cannot drift — the mistake this whole slice opened by fixing, in miniature.
static func standard_kgm3() -> float:
	return standard().kgm3()


## How far down on standard air this field is, as a fraction. Positive means thinner. This is the
## number the builder actually reads: "16.3% down on sea level" means something to a pilot in a
## way that "1.0259 kg/m3" does not.
func fraction_below_standard() -> float:
	return 1.0 - kgm3() / standard_kgm3()


## True when this is standard air to within a hair. Used to decide whether the field is worth
## MENTIONING at all — a course at sea level should not carry an air warning saying nothing.
func is_standard() -> bool:
	return absf(kgm3() - standard_kgm3()) < 1.0e-9


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Reads an `air` block. ANY unreadable shape — absent, null, not a dictionary, non-numeric
## fields — comes back as standard air, which is not a fallback papering over missing data: it is
## the CORRECT reading of a course saved before air existed, because 1.225 is exactly what that
## course was flown in. See design §2.1 for why there is no migration.
static func from_data(data: Variant) -> AirDensity:
	if not (data is Dictionary):
		return standard()
	var record: Dictionary = data
	var elevation: Variant = record.get("elevation_m", STANDARD_ELEVATION_M)
	var temperature: Variant = record.get("temperature_c", STANDARD_TEMPERATURE_C)
	if not _is_number(elevation) or not _is_number(temperature):
		return standard()
	return AirDensity.new(float(elevation), float(temperature))


func to_data() -> Dictionary:
	return {"elevation_m": elevation_m, "temperature_c": temperature_c}


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
