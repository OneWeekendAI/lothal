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

signal custom_escs_changed()

var _delete_button: Button


func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "esc", "ESCs", "ESC", FILTER_KEYS)

	# The authoring entry point, on the ESC rail for the same reason the other four are on theirs
	# (PartPicker's header, on parallel surfaces): a second place to browse boards from is a second
	# thing that can disagree about what a board is.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom ESC…"
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
##
## No dependency check: nothing cross-references an ESC id the way a custom motor's
## `thrust_test.prop_id` names a prop.
func _refresh_delete_button() -> void:
	_delete_button.disabled = not PartsCatalog.is_custom(str(selected_part().get("part_id", "")))


func _open_dialog() -> void:
	var dialog := CustomEscDialog.new()
	dialog.esc_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_escs_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return
	var document := CustomEscs.load_from()
	if document.remove(part_id):
		document.save()
		custom_escs_changed.emit()
