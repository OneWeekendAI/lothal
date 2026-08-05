class_name FcPicker
extends PartPicker
## Lab's flight controller rail. All behaviour is PartPicker's — read its header. This file
## is only the three axes a builder browses boards along.
##
## Processor leads, because it is the axis a builder actually shops on and the one the product
## is named for. The bolt pattern is next, and it is the axis that stops a purchase being
## wrong: a 20x20 board does not go on a 30.5x30.5 frame, and the fit check warns about it
## afterwards — filtering by it first is how you avoid needing the warning.
##
## The IMU comes last and is the axis this whole category exists to make matter. It is the
## reason for all four physics-bearing specs, and two boards with the same processor and the
## same bolt pattern can be 2.5x apart on the noise that reaches the D term because of it.

const FILTER_KEYS := [
	{"key": "processor", "label": "Processor"},
	{"key": "pattern", "label": "Mount", "block": "mounting"},
	{"key": "imu", "label": "IMU"},
]

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "flight_controller", "Flight controllers", "FC", FILTER_KEYS)
