class_name BladeAero
extends RefCounted
## What the blade on the bench WOULD DO — the Propulsion room's verdict, from the same solve the
## aircraft flies on.
##
## ## Why this file exists at all, given P10e already shipped five overlays
##
## The overlays answer for the fitted aircraft: they read `Build.operating_rpm()` and the prop the
## drone currently carries, they live on `GlassShell`, and `set_blade_room_open` HIDES them while
## the Propulsion room is up (`OverlayTray`'s defect 1 is about exactly that plumbing). So the one
## screen where a builder is drawing a planform was the one screen with no aerodynamic answer on
## it: you could author a blade nothing had an opinion about, and the first opinion arrived after
## fitting it to an aircraft in another room.
##
## This class closes that. It takes a `PropellerDocument` and an RPM — NOT a `Build`, because the
## blade on the bench is not fitted to anything yet, and inventing an aircraft to hang it on would
## be answering a question the builder did not ask.
##
## ## Nothing here is a second physics
##
## Every number below is either returned by `BemtModel` or is arithmetic on what it returned:
##
##   - thrust, torque, induced and profile power come from `BemtModel.solve_with_guard`
##   - the per-station α, C_l and C_d come from `BemtModel.station_distribution`, which taps the
##     solve's OWN converged block — see its Rust docs for why it is a tap and not a formula
##   - the stall test compares those C_l against `BemtModel.global_polar()[3]`, the published cap
##     the polar itself clamps at, so the condition is not written down a third time here
##
## The one formula this file owns is the figure of merit, and it is here rather than in Rust
## because it is a comparison between the solve and momentum theory rather than a part of either:
##
##     FM = P_ideal / P_actual,   P_ideal = T^1.5 / sqrt(2·ρ·A)
##
## `test_blade_aero.gd` pins it against `BemtModel.uniform_inflow_momentum` at the induced velocity
## that closed form implies, so the definition is cross-checked against the Rust momentum
## integrator rather than merely restated in a test.
##
## ## FINDING: the lift cap is not a verdict, and this file will not report it as one
##
## Measured across the whole catalog at 18,000 RPM, EVERY propeller reports between 30% and 100%
## of its lifting blade sitting at the polar's `C_l_max`. That is two things at once and neither is
## a defect. A static rotor's inboard sections genuinely run at high incidence — β = atan(P/2πr)
## grows without bound as r → 0, so the root is at 38° on a 30 mm-pitch blade — and `C_l_max = 1.0`
## is a FITTED constant from §4.2's global polar, chosen because the calibration band barely
## depends on it, not a measured stall angle for any aerofoil anybody prints.
##
## So a "78% stalled" headline would be alarming, unactionable, and unable to tell two blades
## apart, which is the only job the room has. The capped fraction is still computed and still
## drawn — WHERE the cap reaches is a real statement about a planform, and `capped_to_r_frac` is
## the form of it worth reading — but the figures a builder decides on are g/W and FM, which span
## 3.5–17.8 and 0.62–0.73 across the same catalog and therefore discriminate.
##
## The naming follows the finding: nothing here calls it stall. It is the lift cap, because that is
## what the polar does and all this layer can honestly report.
##
## ## Grams per watt, and why it is the headline
##
## The number a builder actually decides on before printing is hover efficiency: how much lift a
## watt buys. FM is the aerodynamicist's figure and it is reported too, but g/W is the one that
## answers "is this worth printing over the 5x4.3x3 I can buy", because it is the one that shows up
## as flight time.

## Standard sea-level air, matching `BemtModel`'s own default. A room analysing a blade in
## isolation has no course and therefore no elevation; `AirDensity.standard_kgm3()` is the same
## number and this constant exists so a caller may pass a course's density instead.
const RHO_DEFAULT := 1.225

## Newtons per gram-force, for the g/W readout. 1 gf = 0.00980665 N (standard gravity), which is
## the same constant the powertrain's thrust tables are quoted in.
const NEWTON_PER_GRAM_F := 0.00980665

## The stride of `BemtModel.station_distribution`: [r_m, alpha_rad, c_l, c_d].
const STATION_STRIDE := 4


## How many stations a tap holds. A named accessor rather than `size() / STATION_STRIDE` at each
## call site because that expression is integer division between two ints, which this project
## treats as an error — and the float-divide-then-truncate that satisfies it is exactly the kind of
## line that gets written a different way in each file it appears in.
static func station_count(stations: PackedFloat64Array) -> int:
	return int(stations.size() / float(STATION_STRIDE))


## The full verdict for one document at one RPM, as a Dictionary.
##
## Keys: `refused` (bool), `thrust_n`, `torque_nm`, `power_w`, `grams_per_watt`,
## `figure_of_merit`, `disc_area_m2`, `tip_speed_mps`, `stall_fraction`, `stations`
## (the raw `[r_m, α, C_l, C_d]` tap) and `residual`.
##
## A REFUSAL IS NOT A ZERO. `BemtModel.solve` declines rotors it has no standing on (no RPM, no
## blades, a planform with fewer than two points), and `station_distribution` returns an empty
## array for the same ones. Reporting that as 0 N at 0 g/W would be this class inventing an answer
## the model would not give — the failure `ThrustOverlay` names for its own curve. So `refused` is
## a field and every number beside it is zero, which a panel must check before it draws.
static func analyse(doc: PropellerDocument, rpm: float,
		rho: float = RHO_DEFAULT, guard_closure: float = 0.0) -> Dictionary:
	var out := {
		"refused": true,
		"thrust_n": 0.0,
		"torque_nm": 0.0,
		"power_w": 0.0,
		"grams_per_watt": 0.0,
		"figure_of_merit": 0.0,
		"disc_area_m2": 0.0,
		"tip_speed_mps": 0.0,
		"stall_fraction": 0.0,
		"capped_to_r_frac": 0.0,
		"residual": 0.0,
		"stations": PackedFloat64Array(),
	}
	if doc == null or rpm <= 0.0 or doc.diameter_mm <= 0.0 or doc.blades <= 0:
		return out

	var diameter_m := doc.diameter_mm * 0.001
	var pitch_m := doc.pitch_mm * 0.001
	var blades := float(doc.blades)
	var polar: PackedFloat64Array = BemtModel.global_polar()

	var solved: PackedFloat64Array = BemtModel.solve_with_guard(
		rho, diameter_m, pitch_m, blades, rpm, doc.chord,
		polar[0], polar[1], polar[2], polar[3], guard_closure)
	var stations: PackedFloat64Array = BemtModel.station_distribution(
		rho, diameter_m, pitch_m, blades, rpm, doc.chord, guard_closure)
	if stations.is_empty() or solved.size() < 5 or solved[0] <= 0.0:
		return out

	# Total shaft power is induced + profile, the two the solve returns separately. NOT torque×Ω:
	# that is a third route to the same number and the two agree only to the convergence residual,
	# so a readout built on one and a check built on the other would disagree by an amount nobody
	# could attribute.
	var power := solved[2] + solved[3]
	var area := PI * pow(diameter_m * 0.5, 2.0)

	out["refused"] = false
	out["thrust_n"] = solved[0]
	out["torque_nm"] = solved[1]
	out["power_w"] = power
	out["residual"] = solved[4]
	out["disc_area_m2"] = area
	out["tip_speed_mps"] = (rpm * TAU / 60.0) * (diameter_m * 0.5)
	out["stations"] = stations
	out["grams_per_watt"] = (solved[0] / NEWTON_PER_GRAM_F) / power if power > 0.0 else 0.0
	out["figure_of_merit"] = ideal_power_w(solved[0], rho, area) / power if power > 0.0 else 0.0
	out["stall_fraction"] = stall_fraction(stations, polar[3])
	out["capped_to_r_frac"] = capped_to_r_frac(stations, polar[3], diameter_m * 0.5)
	return out


## Momentum theory's floor on the power needed to make `thrust_n` over a disc of area `area_m2`:
##
##     P_ideal = T^1.5 / sqrt(2·ρ·A)
##
## The denominator of the figure of merit. Public and pure so the test can pin it against
## `BemtModel.uniform_inflow_momentum` — an independent integrator for the same physics — rather
## than against a copy of this line.
static func ideal_power_w(thrust_n: float, rho: float, area_m2: float) -> float:
	if thrust_n <= 0.0 or rho <= 0.0 or area_m2 <= 0.0:
		return 0.0
	return pow(thrust_n, 1.5) / sqrt(2.0 * rho * area_m2)


## Whether the station at `index` (a station index, not a float offset) has reached the polar's
## lift cap — the definition of stall everywhere in this room.
##
## `>=` and not `>`: the polar computes `C_l = min(a0·α, C_l_max)`, so a stalled station's C_l IS
## the cap exactly, and `>` would report every stalled station as flying.
static func is_stalled(stations: PackedFloat64Array, index: int, c_l_max: float) -> bool:
	var at := index * STATION_STRIDE
	if at + 2 >= stations.size() or c_l_max <= 0.0:
		return false
	return stations[at + 2] >= c_l_max


## How much of the BLADE is stalled, as a fraction of the stations that carry chord.
##
## The denominator is the lifting stations rather than all of them, and that is the whole substance
## of this function. A planform whose inboard third is hub carries zero chord there, and those
## annuli are in the tap (the grids are aligned on purpose). Counting them as unstalled blade would
## make every blade look healthier the more hub it had — a metric that improves when you delete
## blade is worse than no metric.
static func stall_fraction(stations: PackedFloat64Array, c_l_max: float) -> float:
	var count := station_count(stations)
	var lifting := 0
	var stalled := 0
	for i in count:
		if stations[i * STATION_STRIDE + 2] <= 0.0 and stations[i * STATION_STRIDE + 1] <= 0.0:
			continue
		lifting += 1
		if is_stalled(stations, i, c_l_max):
			stalled += 1
	if lifting == 0:
		return 0.0
	return float(stalled) / float(lifting)


## The stalled stretches of the blade, as `[r_frac_begin, r_frac_end, …]` pairs — what the planform
## editor shades and the 3D view bands.
##
## Contiguous runs rather than a per-station flag because that is what a reader sees: "the inner
## 40% is stalled" is one fact, and forty booleans are not. Radii are converted to r/R here, since
## the tap is metric and both consumers draw in fractions of radius.
##
## A run's edges sit HALFWAY to the neighbouring station rather than on the stalled station's own
## radius. The stations are midpoints of annuli, so the stalled region genuinely extends half a
## width either side; drawing to the midpoints instead would leave a visible unshaded gutter
## between a stalled run and its unstalled neighbour and understate the run by one annulus width.
static func stall_bands(stations: PackedFloat64Array, c_l_max: float, radius_m: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var count := station_count(stations)
	if count == 0 or radius_m <= 0.0:
		return out
	var half := 0.0
	if count > 1:
		half = absf(stations[STATION_STRIDE] - stations[0]) * 0.5 / radius_m

	var run_begin := -1.0
	var run_end := -1.0
	for i in count:
		var r_frac := stations[i * STATION_STRIDE] / radius_m
		if is_stalled(stations, i, c_l_max):
			if run_begin < 0.0:
				run_begin = maxf(0.0, r_frac - half)
			run_end = minf(1.0, r_frac + half)
		elif run_begin >= 0.0:
			out.append(run_begin)
			out.append(run_end)
			run_begin = -1.0
	if run_begin >= 0.0:
		out.append(run_begin)
		out.append(run_end)
	return out


## How far out the lift cap reaches, as a fraction of radius — 0.0 when nothing is capped.
##
## The form of the capped-fraction finding that is worth putting in front of a builder. Inboard
## capping is universal, so its EXTENT is the discriminating fact: a blade capped to 0.53 R and one
## capped to 0.98 R are different propellers, and the second is over-pitched for the speed it is
## being asked to turn at. A percentage of blade cannot say that, because it cannot say where.
static func capped_to_r_frac(stations: PackedFloat64Array, c_l_max: float, radius_m: float) -> float:
	var out := 0.0
	var bands := stall_bands(stations, c_l_max, radius_m)
	var i := 1
	while i < bands.size():
		out = maxf(out, bands[i])
		i += 2
	return out


## The angle of attack at a station, in DEGREES, for a readout. Radians are the tap's unit and
## degrees are the builder's; the conversion lives here so no panel does it its own way.
static func alpha_deg(stations: PackedFloat64Array, index: int) -> float:
	var at := index * STATION_STRIDE
	if at + 1 >= stations.size():
		return 0.0
	return rad_to_deg(stations[at + 1])


## The station nearest a given r/R — how a caret in the planform editor finds its row in the tap.
## Returns -1 when there are no stations, which a caller must handle rather than clamp: an empty
## tap is a refusal, and a refusal has no nearest anything.
static func station_at(stations: PackedFloat64Array, r_frac: float, radius_m: float) -> int:
	var count := station_count(stations)
	if count == 0 or radius_m <= 0.0:
		return -1
	var best := 0
	var best_gap := INF
	for i in count:
		var gap := absf(stations[i * STATION_STRIDE] / radius_m - r_frac)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best
