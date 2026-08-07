class_name MotorPicker
extends PartPicker
## Lab's motor rail. All behaviour is PartPicker's — read its header. This file is only the
## three axes a builder browses motors along.
##
## Stator size, KV and intended use are the three questions in that order, because that is the
## order a real decision is made in: the stator class is set by the airframe you are building,
## KV is then set by the pack you intend to fly, and intended use is the sanity check on both.

const FILTER_KEYS := [
	{"key": "stator_class", "label": "Stator"},
	{"key": "kv_class", "label": "KV"},
	{"key": "intended_use", "label": "For"},
]

signal custom_motors_changed()

var _delete_button: Button

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "motor", "MOTORS", "motor", FILTER_KEYS)

	# The authoring entry point, on the motor rail for the same reason the frame one is on the
	# frame rail (PartPicker's header, on parallel surfaces): a second place to browse motors from
	# is a second thing that can disagree about what a motor is.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom motor…"
	new_button.pressed.connect(_open_dialog)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_delete_selected)
	buttons.add_child(_delete_button)
	add_custom_buttons(buttons)
	part_selected.connect(func(_motor: Dictionary) -> void: _refresh_delete_button())
	_refresh_delete_button()


## Delete is only meaningful on a motor the builder owns. Disabled rather than hidden on a catalog
## motor, so the rail does not reflow every time the selection moves.
func _refresh_delete_button() -> void:
	_delete_button.disabled = not PartsCatalog.is_custom(str(selected_part().get("part_id", "")))


func _open_dialog() -> void:
	var dialog := CustomMotorDialog.new()
	dialog.motor_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_motors_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return
	var document := CustomMotors.load_from()
	if document.remove(part_id):
		document.save()
		custom_motors_changed.emit()
