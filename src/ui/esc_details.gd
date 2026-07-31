class_name EscDetails
extends PartDetails
## What the selected ESC is, and — more usefully — what it means for this build.
##
## The rows split in two. The top half is the board: its ratings, its channels, its mass, its bolt
## pattern. The bottom half is the CONSEQUENCE, and it is the half worth having: what this board
## passes in total, and whether it or something else is the thing capping the aircraft.
##
## "45A" is an abstraction. "180 A total, and your pack runs out at 112 A" is a decision.

const SPEC_ROWS := [
	{"key": "board_class", "label": "Board"},
	{"key": "cell_range", "label": "Cells"},
	{"key": "protocol", "label": "Protocol"},
	{"key": "mass_g", "label": "Board mass"},
	{"key": "mount", "label": "Mount"},
	{"key": "continuous_a", "label": "Continuous (per motor)"},
	{"key": "burst_a", "label": "Burst (per motor)"},
	{"key": "total_a", "label": "Passes in total"},
	{"key": "limiting", "label": "Limited by"},
]

var _build: Build = null

func _init() -> void:
	super(SPEC_ROWS)

## Kept so the consequence rows can name the OTHER components. PartDetails hands the part down;
## this panel needs the aircraft the part is fitted to, which is a different thing. Stashed BEFORE
## the super call, because that is what fills the rows _read() answers.
func render(part: Dictionary, build: Build) -> void:
	_build = build
	super(part, build)

func _read(esc: Dictionary, key: String) -> String:
	var specs: Dictionary = esc.get("specs", {})

	match key:
		"mass_g":
			return "%.0f g" % float(esc.get("mass_g", 0.0))
		"mount":
			return _or_dash(str(esc.get("mounting", {}).get("pattern", "")))
		"continuous_a":
			return "%.0f A" % float(specs.get("continuous_a", 0.0))
		"burst_a":
			# Labelled as carried-but-unmodelled rather than shown as though it were a limit. See
			# escs.json's _schema: a burst rating used as a continuous one is just a bigger
			# continuous rating with a misleading name.
			return "%.0f A  (not modelled)" % float(specs.get("burst_a", 0.0))
		"total_a":
			if _build == null:
				return "—"
			return "%.0f A  (%.0f x %d)" % [_build.esc_max_amps(),
				float(specs.get("continuous_a", 0.0)), int(specs.get("channels", 4))]
		"limiting":
			# The row that turns a spec sheet into a decision: which of the three runs out first,
			# and at what throttle. Read straight off Build so this panel and the compatibility
			# warnings cannot come to different conclusions.
			if _build == null:
				return "—"
			var limit := _build.limiting_component()
			return "%s  —  %.0f A, %.0f%% throttle" % [
				limit["label"], limit["amps"], limit["throttle"] * 100.0]
	return super(esc, key)
