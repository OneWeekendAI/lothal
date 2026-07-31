class_name EscInstruments
extends InstrumentPanel
## The readout beside the ESC bench. All the machinery is InstrumentPanel's — read its header.
##
## TWO NUMBERS DECIDE THIS BENCH, and labs-and-sim.md §2.1 names both: current per channel against
## the board's continuous rating per channel, and — if the board is not what runs out first — which
## component is. So there are two headline blocks here, as on the battery bench.
##
## HEADROOM IS QUOTED PER CHANNEL, AS A SIGNED MARGIN. Not as "180 A available", which is the
## board's total and the reading escs.json's schema exists to warn about; not as a percentage,
## which hides how close a marginal board is to the line. "+28 A" and "−12 A" are the two answers,
## and the sign is the decision.
##
## BURST IS ON THE PANEL AND IS NOT A LIMIT. It is the number printed next to the continuous one on
## every product page, so a builder comparing two boards compares both — leaving it off would be
## its own dishonesty. It is labelled as unmodelled in the row and again in the note underneath,
## because a burst figure shown beside a headroom figure would otherwise read as the real ceiling.

const ROWS := [
	{"key": "rating", "label": "Continuous (per channel)"},
	{"key": "burst", "label": "Burst (per channel)"},
	{"key": "total", "label": "Passes in total"},
	{"key": "demand", "label": "One motor, full throttle"},
	{"key": "draw", "label": "Drawing now (per channel)"},
	{"key": "throttle", "label": "Throttle"},
	{"key": "crossing", "label": "Rating reached at"},
]

const HEADLINES := [
	{
		"key": "headroom",
		"label": "HEADROOM PER CHANNEL",
		"caption": "rating vs one motor, flat out",
		"colour": InstrumentPanel.EFFICIENCY_COLOUR,
	},
	{
		"key": "binding",
		"label": "RUNS OUT FIRST",
		"caption": "what caps this build, by name",
		"colour": InstrumentPanel.LIMIT_COLOUR,
	},
]


func _init() -> void:
	super(HEADLINES, ROWS)


## The static half: which board is on the bench, against which motors, and the verdict. Called on a
## board or motor change rather than every frame — none of it moves during a sweep.
func render_build(build: Build) -> void:
	var headroom := build.esc_channel_headroom_a()
	var adequate := build.esc_has_channel_headroom()

	set_headline("headroom", "%+.0f A" % headroom)
	set_headline_colour("headroom", EFFICIENCY_COLOUR if adequate else SAG_COLOUR)

	var limit := build.limiting_component()
	set_headline("binding", str(limit["label"]))

	set_value("rating", "%.0f A" % build.esc_continuous_a())
	# The same wording EscDetails uses, deliberately. One claim about burst, phrased one way,
	# wherever it appears.
	set_value("burst", "%.0f A  (not modelled)" % build.esc_burst_a())
	set_value_colour("burst", MUTED_COLOUR)
	set_value("total", "%.0f A  (%.0f x %d)" % [
		build.esc_max_amps(), build.esc_continuous_a(), build.esc_channels()])
	set_value("demand", "%.0f A" % build.motor_demand_per_channel_a())

	set_notes(
		_verdict(build, headroom, adequate),
		# Said in words as well as in the row, because a number on a panel beside a headroom figure
		# is read as a ceiling whatever its label says.
		"Burst is carried from the catalog and is NOT modelled as a limit — it needs a thermal "
			+ "state this bench does not have. Everything above is the continuous rating.")


## What the sign means, spelled out, and where the money goes. The point of naming the binding
## component rather than quoting a bare ceiling: "you are capped at 88%" sends nobody anywhere.
func _verdict(build: Build, headroom: float, adequate: bool) -> String:
	var limit := build.limiting_component()
	if not adequate:
		return ("The %s is undersized for four %s — %.0f A a channel against the %.0f A one motor "
			+ "pulls flat out. It is %.0f A short, and it is the part that fails.") % [
			build.esc.get("name", "board"), build.motor["name"],
			build.esc_continuous_a(), build.motor_demand_per_channel_a(), -headroom]
	if str(limit["name"]) == "esc":
		return ("The %s has %.0f A a channel spare, but across four channels it is still the "
			+ "first thing this build runs out of.") % [
			build.esc.get("name", "board"), headroom]
	return ("The %s has %.0f A a channel spare behind four %s. The %s runs out first — that is "
		+ "where the money goes.") % [
		build.esc.get("name", "board"), headroom, build.motor["name"], limit["label"]]


## The live half, once per frame during a sweep. Everything comes from the reading dictionary the
## bench builds off the published observables; this panel derives nothing.
func render_live(reading: Dictionary) -> void:
	set_value("draw", "%.1f A" % reading["draw_per_channel_a"])
	set_value("throttle", "%.0f %%" % (reading["throttle"] * 100.0))

	# Red the moment one channel is past its continuous rating, which is the fact worth a colour
	# rather than a digit the eye slides past.
	var over: bool = reading["draw_per_channel_a"] > reading["rating_a"]
	set_value_colour("draw", SAG_COLOUR if over else VALUE_COLOUR)

	var crossing: float = reading["crossing_throttle"]
	set_value("crossing", "—  (never)" if crossing < 0.0 else "%.0f %% throttle" % (crossing * 100.0))
	set_value_colour("crossing", SAG_COLOUR if crossing >= 0.0 else MUTED_COLOUR)
