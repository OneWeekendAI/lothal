class_name BatteryPicker
extends PartPicker
## Lab's battery rail. All behaviour is PartPicker's — read its header. This file is only the
## four axes a builder browses packs along.
##
## Cell count leads, because it is the one property that changes everything downstream: pack
## voltage sets the RPM ceiling (max_RPM = KV * live voltage), so a 6S pack under a motor wound
## for 4S is a different aircraft rather than a longer-lasting one. Chemistry is next, and it is
## the axis this rail exists to make visible — a Li-ion is not a big LiPo, it is a pack that
## trades sag for capacity, and putting the two side by side under the same filter is how that
## reads as a choice. C-rating and connector come last: the first is the pack's own claim about
## how hard it can be pushed, the second is the only thing on this list that can stop you flying
## tonight.
##
## Chemistry reads from `specs` rather than `catalog`, because it is physics-bearing — it selects
## the open-circuit discharge curve (physics.md §5). See PartPicker's header for why that is
## declared here rather than solved by copying the field into both blocks.

const FILTER_KEYS := [
	{"key": "cell_class", "label": "Cells"},
	{"key": "chemistry", "label": "Chemistry", "block": "specs"},
	{"key": "c_rating", "label": "C-rating", "block": "specs", "format": "%.0fC"},
	{"key": "connector", "label": "Connector"},
]

signal custom_batteries_changed()

var _delete_button: Button

func _init(p_catalog: PartsCatalog) -> void:
	super(p_catalog, "battery", "BATTERIES", "battery", FILTER_KEYS)

	# The authoring entry point, on the pack rail for the same reason the frame and motor ones are
	# on theirs (PartPicker's header, on parallel surfaces): a second place to browse packs from is
	# a second thing that can disagree about what a pack is.
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New custom pack…"
	new_button.pressed.connect(_open_dialog)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_delete_selected)
	buttons.add_child(_delete_button)
	add_custom_buttons(buttons)
	part_selected.connect(func(_pack: Dictionary) -> void: _refresh_delete_button())
	_refresh_delete_button()


## Delete is only meaningful on a pack the builder owns. Disabled rather than hidden on a catalog
## pack, so the rail does not reflow every time the selection moves.
##
## No dependency check, unlike the propeller rail: nothing cross-references a battery id the way a
## custom motor's `thrust_test.prop_id` names a prop, so a pack delete cannot take a neighbouring
## record down with it.
func _refresh_delete_button() -> void:
	_delete_button.disabled = not PartsCatalog.is_custom(str(selected_part().get("part_id", "")))


func _open_dialog() -> void:
	var dialog := CustomBatteryDialog.new()
	dialog.battery_saved.connect(func(_part_id: String) -> void:
		dialog.queue_free()
		custom_batteries_changed.emit())
	add_child(dialog)
	dialog.popup_centered()


func _delete_selected() -> void:
	var part_id := str(selected_part().get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return
	var document := CustomBatteries.load_from()
	if document.remove(part_id):
		document.save()
		custom_batteries_changed.emit()
