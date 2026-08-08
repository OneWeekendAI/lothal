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

signal custom_flight_controllers_changed()

var _delete_button: Button


func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "flight_controller", "Flight controllers", "FC", FILTER_KEYS)

	# The authoring entry point, on the FC rail for the same reason the other five are on theirs —
	# see PartPicker's header on parallel surfaces.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom FC…"
	new_button.pressed.connect(_open_dialog)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_delete_selected)
	buttons.add_child(_delete_button)
	add_custom_buttons(buttons)
	part_selected.connect(func(_board: Dictionary) -> void: _refresh_delete_button())
	_refresh_delete_button()


## Delete is only meaningful on a board the builder owns. Disabled rather than hidden on a catalog
## board, so the rail does not reflow every time the selection moves.
func _refresh_delete_button() -> void:
	_delete_button.disabled = not PartsCatalog.is_custom(str(selected_part().get("part_id", "")))


func _open_dialog() -> void:
	var dialog := CustomFcDialog.new()
	dialog.fc_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_flight_controllers_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return
	var document := CustomFlightControllers.load_from()
	if document.remove(part_id):
		document.save()
		custom_flight_controllers_changed.emit()
