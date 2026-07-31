class_name BatteryInstruments
extends InstrumentPanel
## The readout beside the battery bench. All the machinery is InstrumentPanel's — read its header.
##
## TWO NUMBERS DECIDE THIS BENCH, and labs-and-sim.md §2.1 names both: "how far the voltage sags
## under that current, and how long the pack holds up." So there are two headline blocks here
## where the thrust stand has one. Everything else on the panel is context for those two.
##
## Sag is quoted as a drop, not as a voltage — "−2.14 V" rather than "12.66 V". A pack losing two
## volts the instant the motors ask for something is the entire content of this bench, and it is
## the difference between two readings rather than either of them. Both readings are on the panel
## underneath for anyone who wants them.
##
## Hold-up is quoted as time REMAINING at the present draw, not as elapsed time. Elapsed is on the
## panel too, but it answers a question nobody has: what you want to know standing at the bench is
## whether this pack gets you through the flight you had in mind.

const ROWS := [
	{"key": "current", "label": "Current (pack)"},
	{"key": "resting", "label": "Resting voltage"},
	{"key": "live", "label": "Under load"},
	{"key": "per_cell", "label": "Per cell, under load"},
	{"key": "remaining", "label": "Charge left"},
	{"key": "elapsed", "label": "Elapsed"},
	{"key": "thrust", "label": "Thrust reached"},
]

const HEADLINES := [
	{
		"key": "sag",
		"label": "SAG UNDER LOAD",
		"caption": "how far it falls when the motors ask",
		"colour": InstrumentPanel.SAG_COLOUR,
	},
	{
		"key": "hold_up",
		"label": "HOLDS UP FOR",
		"caption": "time left at this draw",
		"colour": InstrumentPanel.EFFICIENCY_COLOUR,
	},
]

var _cells := 1

func _init() -> void:
	super(HEADLINES, ROWS)


## The static half: which pack is on the bench and what the load is. Called on a pack or load
## change rather than every frame.
func render_build(build: Build, load_name: String) -> void:
	_cells = maxi(1, int(build.battery["specs"].get("cells", 1)))

	var pack: Dictionary = build.battery
	set_notes(
		"%s on %s + %s, under %s." % [pack["name"], build.motor["name"],
			build.propeller["name"], load_name],
		# The comparison the bench is FOR, said once in words so the trace does not have to be
		# read cold. Which two packs to try is not prescribed — the point is that the answer is
		# in the shape of the line, not in the capacity on the label.
		"The load is these motors, not a typed-in amp figure. Swap the pack and nothing else "
			+ "changes.")


## The live half, once per frame. Everything comes from the reading dictionary the bench builds
## off the published observables; this panel derives nothing.
func render_live(reading: Dictionary) -> void:
	set_headline("sag", "−%.2f V" % reading["sag_v"])
	set_headline("hold_up", Duration.or_dash(reading["hold_up_s"]))

	set_value("current", "%.1f A" % reading["current_a"])
	set_value("resting", "%.2f V" % reading["resting_v"])
	set_value("live", "%.2f V" % reading["live_v"])
	set_value("per_cell", "%.2f V" % (reading["live_v"] / float(_cells)))
	set_value("remaining", "%.0f mAh  (%.0f %%)" % [
		reading["remaining_mah"], reading["remaining_fraction"] * 100.0])
	set_value("elapsed", Duration.or_dash(reading["elapsed_s"]))
	set_value("thrust", "%.0f g" % reading["thrust_g"])

	# Below the knee the pack is not low, it is finished — and the difference is worth a colour
	# rather than a digit the eye slides past.
	var past_knee: bool = reading["remaining_fraction"] < 0.2
	set_value_colour("remaining", SAG_COLOUR if past_knee else VALUE_COLOUR)
	set_headline_colour("hold_up", SAG_COLOUR if past_knee else EFFICIENCY_COLOUR)
