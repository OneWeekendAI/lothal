class_name BenchInstruments
extends InstrumentPanel
## The readout beside the thrust stand: what the pairing is doing right now, and how far the
## model can be trusted about it.
##
## Five live numbers — thrust, current, RPM, live pack voltage, efficiency — and two static
## ones: the throttle at which this pairing hits its current limit, and the predicted-versus-
## measured error at a held-out point.
##
## EFFICIENCY GETS THE WEIGHT. labs-and-sim.md §2.1 calls grams per watt "the number most
## builders never look at and the one that decides flight time", so it is not a sixth row in
## a list of six. InstrumentPanel is where that opinion now lives, and the battery bench holds
## the same one about sag — which is why the panel was generalised rather than copied when the
## second bench arrived.
##
## Everything displayed is read from the published Observables, never from the powertrain's
## internals — the bench is a consumer of the same layer the HUD and the audio synthesiser
## consume, and that is what makes "the bench and the field agree" structural rather than
## something to keep checking.

## Rows in display order. Efficiency is deliberately NOT here — it has the headline block.
const ROWS := [
	{"key": "thrust", "label": "Thrust"},
	{"key": "rpm", "label": "RPM"},
	{"key": "current", "label": "Current"},
	{"key": "voltage", "label": "Pack voltage"},
]

const HEADLINES := [
	{
		"key": "efficiency",
		"label": "EFFICIENCY",
		"caption": "grams of thrust per watt — what decides flight time",
		"colour": InstrumentPanel.EFFICIENCY_COLOUR,
	},
]

## Surfaced from Build.max_throttle_fraction(), not recomputed here.
var current_limit_throttle := 1.0

var _nominal_v := 0.0

func _init() -> void:
	super(HEADLINES, ROWS)


## The static half: what this pairing is, before it is run. Called on a selection change
## rather than every frame, because none of it moves while the motor spins.
func render_build(build: Build, catalog: PartsCatalog) -> void:
	current_limit_throttle = build.max_throttle_fraction()
	_nominal_v = build.battery_model().nominal_v

	var limit_text := ""
	if current_limit_throttle < 0.995:
		limit_text = "Hits its %.0f A limit at %.0f%% throttle — everything above that is prop the motor cannot turn." % [
			float(build.motor["specs"]["max_amps"]), current_limit_throttle * 100.0]
	else:
		limit_text = "Reaches full throttle inside its %.0f A limit." % float(build.motor["specs"]["max_amps"])

	# The bench quoting its own error bar. A motor with no held-out measurement says so
	# plainly — an unvalidated bench and a validated one must never look the same.
	var summary := ThrustValidation.summary_for(catalog, build.motor)
	var validation_text := ""
	if summary == "not validated":
		validation_text = "Held-out validation: not validated — no independently-measured point in the catalog for this motor."
	else:
		validation_text = "Held-out validation (a prop the fit did NOT come from):\n%s" % summary

	set_notes(limit_text, validation_text)


## The live half, once per frame off the published observables.
func render_live(observables: Observables) -> void:
	var readout := readings(observables)

	set_value("thrust", "%.0f g" % readout["thrust_g"])
	set_value("rpm", "%.0f" % readout["rpm"])
	set_value("current", "%.1f A" % readout["current_a"])
	set_value("voltage", "%.2f V" % readout["voltage_v"])

	# Sag stated as a colour as well as a number: the pack losing a volt under load is the
	# lesson the battery bench exists for, and it is easy to miss as a digit that ticks down.
	var sagging: bool = _nominal_v > 0.0 and readout["voltage_v"] < _nominal_v * 0.9
	set_value_colour("voltage", SAG_COLOUR if sagging else VALUE_COLOUR)

	if readout["efficiency_g_per_w"] > 0.0:
		set_headline("efficiency", "%.2f g/W" % readout["efficiency_g_per_w"])
	else:
		set_headline("efficiency", "—")


## What one motor on the stand is doing, derived from the published observables and nothing
## else. Exposed as data rather than only as text so the tests can assert on the numbers
## instead of parsing labels.
##
## The powertrain runs four identical motors because that is the one electrical model the
## project has; a thrust stand holds ONE. So thrust is read per motor and current is the pack
## total divided by four. Modelling a single motor separately would be a second copy of the
## electrical model, which is the thing the Powertrain split exists to prevent.
static func readings(observables: Observables) -> Dictionary:
	var thrust_g := observables.thrust_n[0] / 9.81 * 1000.0
	var current_a := observables.current_total_a / float(Observables.MOTOR_COUNT)
	var voltage_v := observables.voltage_live_v
	var watts := voltage_v * current_a

	return {
		"thrust_g": thrust_g,
		"rpm": float(observables.rpm[0]),
		"current_a": current_a,
		"voltage_v": voltage_v,
		"watts": watts,
		# Grams per WATT. Grams per amp would look almost identical on screen and be wrong by
		# whatever the pack voltage happens to be, which is exactly the kind of error a unit
		# nobody checks is made of.
		"efficiency_g_per_w": thrust_g / watts if watts > 0.0 else 0.0,
	}


## InstrumentPanel's keys, plus the two the thrust stand's own tests have always asked for by
## name. The notes are generic machinery in the base and specific claims here, so they are
## surfaced under both names rather than renamed in the tests.
func readout_text() -> Dictionary:
	var out := super()
	out["limit"] = out["note_top"]
	out["validation"] = out["note_bottom"]
	return out
