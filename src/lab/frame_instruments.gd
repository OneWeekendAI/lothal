class_name FrameInstruments
extends InstrumentPanel
## The readout beside the frame bench. All the machinery is InstrumentPanel's — read its header.
##
## INERTIA IN kg*m^2 IS NOT THE HEADLINE, AND THAT IS DELIBERATE. A single build's roll inertia is
## a number no builder has an intuition for; quoted large and alone it would be the most impressive
## and least useful thing on the screen. What decides the question is what that inertia DOES —
## how hard the aircraft accelerates when the stick goes over, and how long it takes to get to a
## rate. So the two headline blocks are the felt quantities, and the three inertias are rows under
## them, present because they are the cause and readable because they are next to the effect.
##
## Quoted in g*cm^2 rather than kg*m^2, which is the same decision. A catalog spanning a 65 mm
## whoop and a 10" long-range covers roughly 0.00013 to 0.0053 kg*m^2, and a column of numbers that
## all begin "0.00" cannot be compared at a glance. The same span in g*cm^2 is 1291 to 53265, which
## can. The unit is stated in the caption so nobody has to guess.
##
## THE COMPARISON IS THE TEACHING, and it is in the top note rather than in a second column: the
## current build against the 5" reference, with the arm ratio, the leverage ratio and the
## acceleration ratio side by side. That is the arm/torque/inertia exponent argument written out for
## the exact aircraft on the bench, which no general statement about parallel axes achieves.
##
## The bottom note carries the centre-of-mass caveat, which is the honest half. See
## FrameBench.com_offset_m: the mass model lumps every centre-mounted part at the origin, so sliding
## the pack moves the picture and the fit warnings and not the physics. A panel that showed a COM
## row without saying so would be quoting a zero as though it were a measurement.

const ROWS := [
	{"key": "roll_inertia", "label": "Roll inertia"},
	{"key": "pitch_inertia", "label": "Pitch inertia"},
	{"key": "yaw_inertia", "label": "Yaw inertia"},
	{"key": "torque", "label": "Peak torque"},
	{"key": "rate", "label": "Rate now"},
	{"key": "arm", "label": "Arm (centre to motor)"},
	{"key": "weight", "label": "All-up weight"},
	{"key": "clearance", "label": "Prop clearance"},
	{"key": "com", "label": "Centre of mass"},
]

const HEADLINES := [
	{
		"key": "alpha",
		"label": "PEAK ANGULAR ACCELERATION",
		"caption": "rad/s^2 — the four real motors' torque over this airframe's inertia",
		"colour": InstrumentPanel.EFFICIENCY_COLOUR,
	},
	{
		"key": "time_to_rate",
		"label": "TIME TO %.0f DEG/S" % FrameBench.TARGET_RATE_DEG_S,
		"caption": "how long full stick needs to get there — the number a pilot feels",
		"colour": InstrumentPanel.LIMIT_COLOUR,
	},
]


func _init() -> void:
	super(HEADLINES, ROWS)


## Inertia in the unit the whole catalog is legible in. One expression, used by every row and by
## the note, so two places on the same panel cannot quote the same quantity differently.
static func inertia_text(kg_m2: float) -> String:
	return "%.0f g*cm^2" % (kg_m2 * 1.0e7)


## The static half: what this airframe IS, and how it compares. Called on a build change rather than
## every frame — nothing here moves during a run.
##
## `comparison` is the reference build's own measured step, or an empty dictionary when the bench is
## already sitting on the reference frame and there is nothing to compare against.
func render_build(bench: FrameBench, comparison: Dictionary) -> void:
	var reading := bench.readings()

	set_value("roll_inertia", inertia_text(reading["inertia_roll_kg_m2"]))
	set_value("pitch_inertia", inertia_text(reading["inertia_pitch_kg_m2"]))
	set_value("yaw_inertia", inertia_text(reading["inertia_yaw_kg_m2"]))
	set_value("arm", "%.0f mm" % reading["arm_mm"])
	set_value("weight", "%.0f g" % reading["all_up_weight_g"])

	var gap_mm: float = reading["prop_gap_mm"]
	set_value("clearance", "%+.1f mm" % gap_mm)
	set_value_colour("clearance", SAG_COLOUR if gap_mm < 0.0 else VALUE_COLOUR)

	# Zero for every build in the catalog, and the note underneath says why rather than letting a
	# reader conclude the aircraft happens to be perfectly balanced.
	set_value("com", "%.1f mm off centre" % reading["com_offset_mm"])
	set_value_colour("com", MUTED_COLOUR)

	set_notes(_comparison_text(reading, comparison), _com_caveat())


## The arm/torque/inertia argument, for the aircraft actually on the bench.
##
## Three ratios in one sentence, because any one of them alone is the wrong lesson: the longer arm
## has MORE leverage (or the reader concludes long arms are simply weaker), it carries MORE than
## proportionally more inertia (which is the squared term), and it therefore accelerates LESS.
func _comparison_text(reading: Dictionary, comparison: Dictionary) -> String:
	if comparison.is_empty():
		return ("This is the reference build. Its roll inertia is the yardstick the trace compares "
			+ "every other frame against — put a longer or shorter frame under the same parts and "
			+ "watch the second line move.")

	var arm_ratio: float = reading["arm_mm"] / float(comparison["arm_mm"])
	var inertia_ratio: float = reading["inertia_roll_kg_m2"] / float(comparison["inertia_roll_kg_m2"])
	var torque_ratio: float = float(reading["peak_torque_n_m"]) / float(comparison["peak_torque_n_m"]) \
		if float(comparison["peak_torque_n_m"]) > 0.0 else 0.0
	var alpha_ratio: float = float(reading["peak_alpha_rad_s2"]) / float(comparison["peak_alpha_rad_s2"]) \
		if float(comparison["peak_alpha_rad_s2"]) > 0.0 else 0.0

	# Torque is quoted only once a run has produced one; before that the sentence would claim a 0.0x
	# leverage ratio, which is the opposite of what it is there to say.
	if torque_ratio <= 0.0:
		return ("Against the 5\" reference build: %.0f mm of arm to its %.0f (%.2fx), and %.2fx its "
			+ "roll inertia — because the arm is SQUARED in the parallel axis theorem. Run the step "
			+ "to see what that costs.") % [
			reading["arm_mm"], comparison["arm_mm"], arm_ratio, inertia_ratio]

	return ("Against the 5\" reference build: %.2fx the arm, so %.2fx the torque — and %.2fx the "
		+ "roll inertia, because the arm is squared and the leverage is not. Net: it accelerates "
		+ "%.2fx as hard. Longer arms have more leverage and still roll slower.") % [
		arm_ratio, torque_ratio, inertia_ratio, alpha_ratio]


## Said in words, because a "0.0 mm off centre" row is otherwise read as a measurement of a
## perfectly balanced aircraft rather than as a limit of the model.
func _com_caveat() -> String:
	return ("The centre of mass is the geometric centre for every build in the catalog: the mass "
		+ "model lumps the pack, the stack and the electronics at the origin. Sliding the pack on "
		+ "its mount moves the picture and the fit warnings and NOT this number.")


## The live half, once per substep-batch during a run. Everything comes from the bench's own
## readings dictionary; this panel derives nothing.
func render_live(reading: Dictionary) -> void:
	set_headline("alpha", "%.0f rad/s^2" % reading["peak_alpha_rad_s2"])

	var time_to_rate: float = reading["time_to_rate_s"]
	set_headline("time_to_rate", "—" if time_to_rate < 0.0 else "%.0f ms" % (time_to_rate * 1000.0))

	set_value("torque", "%.3f N*m" % reading["peak_torque_n_m"])
	set_value("rate", "%.0f deg/s" % reading["rate_deg_s"])
