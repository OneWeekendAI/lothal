class_name PropellerPicker
extends PartPicker
## Lab's propeller rail. All behaviour is PartPicker's — read its header.
##
## Diameter leads, because thrust goes as D^4 and diameter therefore dominates every other
## property on the list (physics.md §4). Blade count is the next question and material the
## last, which is also roughly the order of how much each one changes the flying.

const FILTER_KEYS := [
	{"key": "diameter_class", "label": "Diameter"},
	{"key": "blade_count", "label": "Blades"},
	{"key": "intended_use", "label": "For"},
	{"key": "material", "label": "Material"},
]

signal custom_propellers_changed()

## A delete this rail turned down, with the sentence saying why. The SIGNAL is the contract and the
## popup below is only its default presentation — separated because a refusal that exists solely as
## a Window cannot be asserted without standing a real window up, and a test that cannot see the
## refusal is a test that cannot tell "refused and explained" from "silently did nothing".
signal delete_refused(message: String)

var _delete_button: Button

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "propeller", "PROPELLERS", "propeller", FILTER_KEYS)

	# The authoring entry point, on the propeller rail for the same reason the frame and motor ones
	# are on theirs (PartPicker's header, on parallel surfaces): a second place to browse props
	# from is a second thing that can disagree about what a propeller is.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom propeller…"
	new_button.pressed.connect(_open_dialog)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_delete_selected)
	buttons.add_child(_delete_button)
	add_custom_buttons(buttons)
	part_selected.connect(func(_prop: Dictionary) -> void: _refresh_delete_button())
	_refresh_delete_button()


## Delete is only meaningful on a propeller the builder owns. Disabled rather than hidden on a
## catalog prop, so the rail does not reflow every time the selection moves.
##
## Deliberately NOT also disabled for a prop a custom motor depends on. That refusal has a
## sentence attached — which motors, and what to do about it — and a greyed-out button cannot say
## it. The builder presses Delete, and _delete_selected explains.
func _refresh_delete_button() -> void:
	_delete_button.disabled = not PartsCatalog.is_custom(str(selected_part().get("part_id", "")))


func _open_dialog() -> void:
	var dialog := CustomPropellerDialog.new()
	dialog.propeller_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_propellers_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


## The one delete path on this rail, and the only category whose delete can break a NEIGHBOURING
## document: a custom motor's `thrust_test.prop_id` may name a custom prop, and a motor whose test
## prop has gone is refused at next load with the explanation going to push_warning, where nobody
## is looking. The prop would appear deleted and the motor would simply be gone from the rail.
##
## So the refusal is CustomPropellers.remove_or_refuse's, shown here rather than discovered later.
## Refusing is the right shape rather than cascading — deleting a prop should not silently take a
## motor the builder never mentioned — and it matches labs-and-sim.md §2 only because the
## alternative here is silence rather than a warning.
func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return

	var document := CustomPropellers.load_from()
	var motors := CustomMotors.load_from()
	var blocked := document.removal_block_message(motors, part_id)
	if blocked != "":
		delete_refused.emit(blocked)
		_show_refusal(blocked)
		return

	if document.remove_or_refuse(part_id, motors):
		document.save()
		custom_propellers_changed.emit()


## The refusal, in the sentence CustomPropellers wrote. A dialog rather than a label on the rail,
## because the rail is 272 px wide and this sentence names parts.
##
## A Window can only be popped from inside the scene tree, and a rail outside one has no screen to
## put this on. Returning early there rather than pushing the message somewhere else is safe
## precisely BECAUSE delete_refused has already carried it: the refusal is never lost, only its
## presentation is skipped.
func _show_refusal(message: String) -> void:
	if not is_inside_tree():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Cannot delete this propeller"
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
