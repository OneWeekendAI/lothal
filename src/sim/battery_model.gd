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
## THE CONSTRAINT: THE STATE-OF-CHARGE TERM IS EXACTLY ZERO AT FULL CHARGE
## ---------------------------------------------------------------------------
##
## `nominal_v` is treated as the pack's RESTING voltage at full charge, and the curve below
## measures its fall from there. That is a deliberate choice of datum rather than an oversight
## about real cell voltages — a real 4S LiPo comes off the charger at 16.8 V, not 14.8 V.
##
## The reason is that the reference build's 11.7:1 thrust-to-weight and 29% hover throttle are
## FULL-PACK figures, quoted at nominal voltage the way every manufacturer's thrust table and
## every spec sheet quotes them. They are the project's fixed points: if a state-of-charge term
## could move them, every number Lothal reports would depend on how much flying had been done
## since, and no two builders could compare anything. So the term is exactly zero at used_mah = 0
## — not small, not within a tolerance, zero, asserted as an exact equality in
## tests/test_battery_model.gd — and voltage_live() at full charge returns precisely what it
## returned before this file grew a curve.
##
## What that buys is the whole point: everything AFTER the first minute of flight is honest, and
## nothing before it moved.
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


## Where the pack sits with nothing drawing from it. Falls as the pack empties, and is EXACTLY
## nominal_v at full charge — see the constraint in the header.
func resting_voltage_v() -> float:
	return nominal_v + soc_offset_v()


## The state-of-charge term itself, in volts at the pack. Written as a difference from the
## curve's own full-charge value rather than as an absolute, which is what makes the zero at full
## charge exact instead of a coincidence of two hand-entered numbers agreeing to five places.
func soc_offset_v() -> float:
	var curve: Array = CURVES[chemistry]
	var full_cell_v: float = curve[curve.size() - 1][1]
	return float(cells) * (cell_open_circuit_v(remaining_fraction(), chemistry) - full_cell_v)


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


func voltage_live(current_total_a: float) -> float:
	return resting_voltage_v() - current_total_a * internal_r_ohm

func drain(current_total_a: float, dt: float) -> void:
	used_mah += current_total_a * (dt / 3600.0) * 1000.0

func remaining_fraction() -> float:
	return clampf(1.0 - used_mah / capacity_mah, 0.0, 1.0)
