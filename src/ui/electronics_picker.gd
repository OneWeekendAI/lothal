class_name ElectronicsPicker
extends PanelContainer
## Lab's electronics rail: the camera, the video transmitter, the antenna and the receiver.
##
## ONE RAIL FOR FOUR CATEGORIES, which breaks the pattern the other six rails follow, and the
## reason is what these parts are. The other rails each browse a shelf — there are twelve frames
## and a builder narrows them by material, size and mount, which is what PartPicker's filters and
## its tall ItemList are for. These four are a PAYLOAD DECISION taken in one sitting: four entries
## per category, no physics-bearing specs to filter on beyond mass and the box the part occupies,
## and the question is "what am I carrying" rather than "which camera". Four PartPicker rails
## would have put four filtered ItemLists behind four tabs to answer it, and made the tab bar ten
## tabs wide in a 292 px column on the way.
##
## So the control here is a dropdown per category rather than a list, and the panel is a form.
## Nothing about that is a downgrade of the browsing experience; there is no browsing to do.
##
## NOT FITTED IS A ROW, and it is the row this rail exists for. Build already distinguished a
## component left out of `component_ids` (fit the default) from one set to "" (fit nothing) — see
## its header — but nothing could say "" out loud, so every aircraft in the app flew a camera, a
## VTX, an antenna and a receiver whether or not it had anywhere to put them. A whoop on an AIO
## board carries none of the four as separate parts, and until this rail existed it could not be
## described. The row is first in every list rather than last, because "what is this costing me"
## is the question a builder opens this rail to ask.
##
## Built in code like every other Control here (architecture.md: "Hand-placed UI does not survive
## version control"), and it computes nothing: it emits ids and Build does the weighing.

signal components_changed()

## What the "" row reads as. One constant rather than a literal per list, so the four lists
## cannot drift into saying it three different ways.
const NOT_FITTED := "Not fitted"

## The label each category browses under. The ORDER comes from Build.OPTIONAL_COMPONENTS rather
## than from this table, so the rail lists the components in the order the mass model weighs them
## and a fifth component cannot be added to the model and silently left off this rail — it turns
## up here as a missing label instead, which is loud.
const CATEGORY_LABELS := {
	"camera": "Camera",
	"vtx": "Video TX",
	"antenna": "Antenna",
	"receiver": "Receiver",
}

var catalog: PartsCatalog

var _selectors: Dictionary = {}   # category -> OptionButton
## category -> Array[String] of part ids, "" first. The selector's index is an index into THIS,
## never into catalog.list_category() — the lists differ by the "Not fitted" row, and reading a
## part out of the catalog by a selector index is off by one for the whole of every list here.
var _ids: Dictionary = {}


func _init(p_catalog: PartsCatalog) -> void:
	catalog = p_catalog

	custom_minimum_size = Vector2(272, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	PartDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = "Electronics"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	for category in Build.OPTIONAL_COMPONENTS:
		var label := Label.new()
		label.text = str(CATEGORY_LABELS.get(category, category))
		grid.add_child(label)

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Clipped and width-capped for the reason PartPicker's filters are: "RHCP SMA long-range
		# (5.8 GHz)" would otherwise set this rail's width from its longest string and shove the
		# details column off the right-hand edge of the window.
		selector.clip_text = true
		selector.custom_minimum_size = Vector2(170, 0)

		var ids: Array = [""]
		selector.add_item(NOT_FITTED)
		for part in catalog.list_category(category):
			selector.add_item("%s   %s g" % [
				PartPicker.display_name(part), PartPicker._format_mass(part)])
			ids.append(str(part["part_id"]))
		_ids[category] = ids

		# Opens on what Build would have fitted anyway, so a builder who never touches this rail
		# is flying the aircraft they were flying before it existed. The default is read from
		# Build rather than restated here: two lists of default components is two things to get
		# out of step, and the difference between them is 21 g of aircraft.
		var default_id := str(Build.DEFAULT_COMPONENT_IDS.get(category, ""))
		selector.select(maxi(ids.find(default_id), 0))
		selector.item_selected.connect(_on_selector_changed)
		grid.add_child(selector)
		_selectors[category] = selector

	root.add_child(HSeparator.new())

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(252, 0)
	note.theme_type_variation = &"MutedLabel"
	note.text = ("Each of these was a share of the flat %.0f g electronics budget until it "
		+ "became a part. Take one off and the aircraft is lighter by what it actually "
		+ "weighs — an AIO whoop carries none of the four.") % Build.ELECTRONICS_MASS_G
	root.add_child(note)


# ---------------------------------------------------------------------------
# Public surface (also what the tests drive)
# ---------------------------------------------------------------------------

## The whole payload, in the shape Build.from_ids takes: every category present, "" for a bay
## left empty. Every category present ALWAYS — an absent key would mean "fit the default" to
## Build, which is the one thing an empty bay must not turn back into.
func component_ids() -> Dictionary:
	var out := {}
	for category in Build.OPTIONAL_COMPONENTS:
		out[category] = selected_id(category)
	return out


func selected_id(category: String) -> String:
	var selector: OptionButton = _selectors[category]
	return str(_ids[category][selector.selected])


func has_category(category: String) -> bool:
	return _selectors.has(category)


## Every id this category can be set to, "" first. The rail's own list rather than the catalog's,
## which is what a caller wanting to drive this control needs.
func options_for(category: String) -> Array:
	return _ids.get(category, [])


## Fits a part by id, or empties the bay when given "". Reports whether it could, so a caller
## restoring a selection across a catalog reload can tell the difference between "put back" and
## "that part is gone now".
func select_component(category: String, part_id: String) -> bool:
	if not _selectors.has(category):
		return false
	var index: int = _ids[category].find(part_id)
	if index < 0:
		return false
	_selectors[category].select(index)
	components_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _on_selector_changed(_index: int) -> void:
	components_changed.emit()
