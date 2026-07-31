class_name EscPicker
extends PartPicker
## Lab's ESC rail. All behaviour is PartPicker's — read its header. This file is only the three
## axes a builder browses boards along.
##
## Continuous current leads, because it is the only physics-bearing number on the board and the
## one that decides whether this ESC or something else is what stops you. It reads from `specs`
## for that reason, and it is filtered PER CHANNEL — the figure printed on the board — while the
## model multiplies by the channel count to get what the aircraft can pass. A rail that filtered
## on the total would be asking a question no product page answers.
##
## The bolt pattern is next, and it is the axis that stops a purchase being wrong: a 20x20 board
## does not go on a 30.5x30.5 frame, and the fit check warns about it afterwards. Filtering by it
## first is how you avoid needing the warning. Cell range comes last — it is the constraint that
## bites when someone puts a 6S pack behind a 4S board.

const FILTER_KEYS := [
	{"key": "continuous_a", "label": "Continuous", "block": "specs", "format": "%.0f A"},
	{"key": "pattern", "label": "Mount", "block": "mounting"},
	{"key": "cell_range", "label": "Cells"},
]

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "esc", "ESCs", "ESC", FILTER_KEYS)
