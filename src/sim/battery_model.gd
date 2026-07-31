class_name BatteryModel
extends RefCounted
## Voltage sag, capacity drain, and how far the pack has fallen as it empties (physics.md §5).
## Small, and it is what makes battery choice feel real instead of cosmetic: punch throttle ->
## current spikes -> voltage drops -> RPM ceiling drops -> thrust drops.
##
## Two separate things pull the voltage down, and keeping them separate is most of what this file
## is for:
##
##   resting_voltage_v()  — where the pack sits with nothing drawing from it, which falls as the
##                          pack empties. Slow, and it never comes back on its own.
##   I * internal_r_ohm   — the sag under load. Instant, and it recovers the moment the throttle
##                          does.
##
## Until the battery bench existed only the second was modelled, so a pack at 5% rested at exactly
## the same open-circuit voltage as a full one. Nothing in the project could see that: sag against
## a flat baseline still rose and fell correctly, hover still solved, and the only symptom was that
## a four-minute flight ended as strong as it started. A bench that plots voltage over a sustained
## load makes it the first thing anyone notices.
##
## ---------------------------------------------------------------------------
## THE DATUM: NOMINAL VOLTAGE IS AN OPERATING POINT, NOT FULL CHARGE
## ---------------------------------------------------------------------------
##
## `nominal_v` is the voltage the pack rests at somewhere down the middle of its discharge — the
## point the whole plateau is named after — and the curve below measures displacement from THERE,
## in both directions. A full pack rests ABOVE nominal and an empty one below it. For a 4S LiPo
## that is 16.8 V off the charger, 14.8 V nominal, and about 13.1 V flat, which is what a real
## one does.
##
## WHAT THIS REPLACED, AND WHY. Until this slice `nominal_v` was treated as the RESTING VOLTAGE
## AT FULL CHARGE, and the state-of-charge term was defined to be exactly zero at used_mah = 0.
## That was a considered choice rather than an oversight, and the reasoning was sound given what
## it was protecting: the reference build's 11.7:1 thrust-to-weight and 29% hover throttle are
## the project's fixed points, and if a state-of-charge term could move them, every number Lothal
## reported would depend on how much flying had been done since and no two builders could compare
## anything. Anchoring at full charge made the term vanish exactly where those numbers are quoted.
##
## The cost was that every pack was physically wrong from the first minute of flight: the curve's
## shape was right and its anchor was half a volt per cell too high, so the entire discharge was
## displaced DOWNWARD by that much. A 4S at half charge rested at 13.16 V instead of 15.16 V. RPM
## ceiling is KV times live voltage and thrust goes as omega squared, so a fifth of the available
## thrust was missing at half pack — and since scenes/main.gd rests the throttle stick at a hover
## figure solved at nominal voltage, the aircraft simply sank once the pack was half gone. That is
## a bug a pilot meets on every flight, and it was reported as one.
##
## The two goals looked like they conflicted and did not, because the oracles were never full-pack
## figures in the first place. They are quoted AT NOMINAL VOLTAGE — the datum every manufacturer's
## thrust table and every spec sheet uses, which the old header already said in as many words.
## Moving the anchor from full charge to nominal therefore leaves them exactly where they were:
## 11.7:1 and 29% are what this build does at 14.8 V, and tests/test_battery_model.gd now asserts
## the identity at that stated datum rather than at a state of charge.
##
## What changes is that a freshly charged pack delivers MORE than the spec figure. That is true of
## every real aircraft, it is the reason a fresh pack feels different on the first punch-out, and
## it is worth learning rather than hiding.
##
## ---------------------------------------------------------------------------
## THE CURVE
## ---------------------------------------------------------------------------
##
## Per cell, against state of charge, as a piecewise-linear fit through published resting-voltage
## tables. The shape matters far more than any single point on it, and it is not a straight line:
##
##   - a steep drop across the top ~20%, which is why a "full" pack stops reading full so quickly
##   - a long flat PLATEAU across the middle, where a cell sits near its nominal voltage and the
##     pack tells you almost nothing about how much is left
##   - a KNEE below ~20%, where it falls away sharply
##
## The knee is the behaviour worth modelling. It is what turns "the pack is getting low" into "the
## pack has stopped", and it is why a timer is a better fuel gauge than a voltmeter. A straight
## line from full to empty would satisfy every check anyone would think to write about voltage
## falling, and would throw the knee away.
##
## Li-ion gets its own curve rather than a scaled LiPo one, and that is why `chemistry` sits in
## batteries.json's `specs` block rather than in `catalog`: it is physics-bearing. An 18650 or
## 21700 cell rests lower through the middle (nearer 3.6 V than 3.7 V nominal), holds a flatter
## plateau, and has a longer, softer tail before it goes. Together with an internal resistance ten
## times a LiPo's, that is the entire character of a long-range pack.

## Per-cell open-circuit voltage against state of charge, ascending by state of charge.
## Sources are cited in physics.md §5; both are class-typical published resting curves rather than
## a measurement of one specific cell.
const CURVES := {
	"LiPo": [
		[0.00, 3.27], [0.05, 3.40], [0.10, 3.50], [0.20, 3.63], [0.30, 3.70],
		[0.40, 3.75], [0.50, 3.79], [0.60, 3.83], [0.70, 3.87], [0.80, 3.97],
		[0.90, 4.08], [1.00, 4.20],
	],
	"Li-ion": [
		[0.00, 2.80], [0.05, 3.05], [0.10, 3.22], [0.20, 3.40], [0.30, 3.50],
		[0.40, 3.57], [0.50, 3.63], [0.60, 3.70], [0.70, 3.78], [0.80, 3.88],
		[0.90, 4.03], [1.00, 4.20],
	],
}

## Where each chemistry's NOMINAL voltage sits on its own curve, per cell. This is the datum: the
## state-of-charge term is displacement from here, so it is zero at whatever state of charge the
## cell happens to rest at its nominal voltage — around 30% for a LiPo, around 60% for a Li-ion,
## which is a real difference between the two rather than a tuning knob.
##
## These are the published nominal figures for the chemistries (3.7 V for LiPo, 3.6 V for a
## Li-ion 18650/21700), not values read off the curve, and the two must agree: a knot table that
## did not pass through its own nominal voltage would make `nominal_v` mean something slightly
## different from what batteries.json says it means. tests/test_battery_model.gd asserts the
## agreement, which is what stops these four numbers from drifting into being two opinions.
const NOMINAL_CELL_V := {
	"LiPo": 3.70,
	"Li-ion": 3.60,
}

## What an unrecognised chemistry gets. batteries.json is contributor-editable, and a typo there
## must not silently delete the model and leave a flat baseline that looks like the old behaviour.
const DEFAULT_CHEMISTRY := "LiPo"

var nominal_v: float
var internal_r_ohm: float
var capacity_mah: float
var used_mah: float = 0.0
## Cell count, which is what turns the per-cell curve into a pack curve.
var cells: int
## Selects the curve. See the header for why this is a spec rather than browsing metadata.
var chemistry: String

## `p_cells` defaults to whatever the nominal voltage implies at 3.7 V per cell, so a pack
## constructed directly — as several tests and capture tools do — still gets the right curve
## shape rather than a one-cell one. Build always passes the catalog's own figure.
func _init(p_nominal_v: float, p_internal_r_ohm: float, p_capacity_mah: float,
		p_cells: int = 0, p_chemistry: String = DEFAULT_CHEMISTRY) -> void:
	nominal_v = p_nominal_v
	internal_r_ohm = p_internal_r_ohm
	capacity_mah = p_capacity_mah
	cells = p_cells if p_cells > 0 else maxi(1, int(round(p_nominal_v / 3.7)))
	chemistry = p_chemistry if CURVES.has(p_chemistry) else DEFAULT_CHEMISTRY


## Where the pack sits with nothing drawing from it. Falls as the pack empties, passing THROUGH
## nominal_v partway down rather than starting there — see the datum in the header.
func resting_voltage_v() -> float:
	return nominal_v + soc_offset_v()


## The state-of-charge term itself, in volts at the pack: how far this pack is from its nominal
## resting voltage right now. POSITIVE above the nominal point and negative below it, which is the
## whole content of the change of datum.
##
## Written as a difference from the chemistry's nominal cell voltage rather than as an absolute,
## so that a pack whose catalog `nominal_v` is not exactly cells x NOMINAL_CELL_V — a contributor
## rounding 21.6 V to 22 V, say — still gets a curve hung off the figure the catalog actually
## states, rather than one that silently disagrees with the number shown in the UI.
func soc_offset_v() -> float:
	return float(cells) * (cell_open_circuit_v(remaining_fraction(), chemistry) - nominal_cell_v(chemistry))


## The nominal resting voltage of one cell of a chemistry. Falls back to LiPo's alongside the
## curve, so an unrecognised chemistry gets a consistent pair rather than one of each.
static func nominal_cell_v(p_chemistry: String) -> float:
	return float(NOMINAL_CELL_V.get(p_chemistry, NOMINAL_CELL_V[DEFAULT_CHEMISTRY]))


## One cell's resting voltage at a state of charge, linearly interpolated between the knots.
## Static because it is a property of a chemistry rather than of a particular pack, and the tests
## and physics.md read it as one.
static func cell_open_circuit_v(soc: float, p_chemistry: String = DEFAULT_CHEMISTRY) -> float:
	var curve: Array = CURVES.get(p_chemistry, CURVES[DEFAULT_CHEMISTRY])
	var clamped := clampf(soc, 0.0, 1.0)

	for i in range(1, curve.size()):
		var high: Array = curve[i]
		if clamped <= float(high[0]):
			var low: Array = curve[i - 1]
			var span: float = float(high[0]) - float(low[0])
			# Guard against a duplicated knot rather than dividing by zero: two entries at the
			# same state of charge is a typo, and the sane reading of it is a step.
			if span <= 0.0:
				return float(high[1])
			var t: float = (clamped - float(low[0])) / span
			return lerpf(float(low[1]), float(high[1]), t)

	return float(curve[curve.size() - 1][1])


## Puts this pack AT the nominal datum: the state of charge where it rests at exactly its nominal
## voltage, so resting_voltage_v() == nominal_v and soc_offset_v() is zero.
##
## This is the aircraft's reference operating point, and it is what anything comparing a dynamic
## run against Build's analytic figures should be run at — those are quoted at nominal voltage and
## at no other. The rate-loop step-response budget in tests/test_rate_step_response.gd is measured
## here for the same reason: its gains' arithmetic is derived at this condition, and a pack resting
## two volts higher is a different aircraft to tune, not a worse tune.
func set_to_nominal_datum() -> void:
	used_mah = capacity_mah * (1.0 - soc_at_nominal(chemistry))


## Where a chemistry's nominal voltage sits on its own discharge, as a state of charge. Bisected on
## the curve rather than written down: it is a consequence of the curve's shape — about 30% for a
## LiPo, about 45% for a Li-ion — and a fourth hand-entered number would be a fourth thing to keep
## in step with the other three.
static func soc_at_nominal(p_chemistry: String = DEFAULT_CHEMISTRY) -> float:
	var target := nominal_cell_v(p_chemistry)
	var low := 0.0
	var high := 1.0
	for _i in 200:
		var mid := (low + high) * 0.5
		if cell_open_circuit_v(mid, p_chemistry) < target:
			low = mid
		else:
			high = mid
	return high


func voltage_live(current_total_a: float) -> float:
	return resting_voltage_v() - current_total_a * internal_r_ohm

func drain(current_total_a: float, dt: float) -> void:
	used_mah += current_total_a * (dt / 3600.0) * 1000.0

func remaining_fraction() -> float:
	return clampf(1.0 - used_mah / capacity_mah, 0.0, 1.0)
