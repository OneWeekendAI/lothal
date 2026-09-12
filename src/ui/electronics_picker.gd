class_name ElectronicsPicker
extends PanelContainer
## Lab's payload rails: the parts that are fitted by naming them and can be left off entirely.
##
## TWO INSTANCES SINCE C3, ONE CLASS. Video's `Electronics` rail carries the camera, the video
## transmitter and the antenna; Control's `Link` rail carries the receiver, the GPS and the buzzer.
## Which categories an instance renders is an ARGUMENT, and both call sites derive it by filtering
## `Build.OPTIONAL_COMPONENTS` through `Build.COMPONENT_SYSTEM` — neither is a hand-written list of
## three names, because that is the arrangement P10f found had drifted (*the two lists were never
## the same list*), and `Build.components_for_system` refuses outright rather than quietly dropping
## a category no system claims.
##
## The class did not have to change shape for the split: nothing in it was ever about video, and
## the argument below for a form of dropdowns is about what KIND of decision these parts are, not
## about which system they belong to.
##
## ONE RAIL FOR SEVERAL CATEGORIES, which breaks the pattern the other six rails follow, and the
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

## The label each category browses under. ONE TABLE FOR BOTH RAILS, because a label is a property
## of the component and not of the system that owns it — splitting it in two would be the third
## hand-written list in a slice whose whole subject is that two were already one too many.
##
## The ORDER comes from `Build.components_for_system` rather than from this table, so each rail
## lists its components in the order the mass model weighs them, and a seventh component added to
## the model cannot be silently left off — it turns up as a missing label, which is loud. C2 shipped
## `gps` and `buzzer` into the model without entries here and they rendered as `gps` and `buzzer`:
## loud worked, and this is the fix.
const CATEGORY_LABELS := {
	"camera": "Camera",
	"vtx": "Video TX",
	"antenna": "Antenna",
	"receiver": "Receiver",
	"gps": "GPS",
	"buzzer": "Buzzer",
}

var catalog: PartsCatalog
## The categories THIS instance renders, in Build's weighing order. Held because every public
## method below answers about this rail rather than about every optional component there is:
## `component_ids()` returning six keys from a rail carrying three would hand Build a payload for
## bays this rail cannot see, and the other rail's selections would be overwritten with defaults.
var categories: Array[String] = []

var _selectors: Dictionary = {}   # category -> OptionButton
## category -> Array[String] of part ids, "" first. The selector's index is an index into THIS,
## never into catalog.list_category() — the lists differ by the "Not fitted" row, and reading a
## part out of the catalog by a selector index is off by one for the whole of every list here.
var _ids: Dictionary = {}


func _init(p_catalog: PartsCatalog, p_categories: Array, p_title: String) -> void:
	catalog = p_catalog
	for category in p_categories:
		categories.append(String(category))
	# The tab title and the heading are one string, set here rather than by the caller: they are
	# the same name in the rail strip and at the top of the form, and LabScreen setting one while
	# this file drew the other is how a rail comes to be called two things.
	name = p_title

	custom_minimum_size = Vector2(272, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	PartDetails._padded(self).add_child(root)

	var title := Label.new()
	title.text = p_title
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	# WHAT AN EMPTY RAIL SAYS. `Build.components_for_system` answers nothing at all when any
	# optional component is claimed by no system (see its header), so this is the shape that
	# refusal takes on screen: a rail that says why it is empty, rather than a form with no rows
	# in it that reads as a rendering fault. There is no other way to reach this branch — both
	# call sites pass that function's result — so it is the refusal made visible and nothing else.
	if categories.is_empty():
		var refused := Label.new()
		refused.text = ("No component category is claimed by this system.\n"
			+ "Build.COMPONENT_SYSTEM is missing an entry — see the error log.")
		refused.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		refused.custom_minimum_size = Vector2(252, 0)
		refused.theme_type_variation = &"WarnLabel"
		root.add_child(refused)
		return

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	for category in categories:
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

	# TWO SENTENCES BECAUSE THERE ARE TWO KINDS OF ROW, and which ones this rail has is a
	# question about its own categories. The carved components were a share of the 55 g lump, so
	# taking one off makes the aircraft LIGHTER; the added ones never were, so fitting one makes it
	# HEAVIER. The old single sentence said the first about all four, which was true of Video's
	# three and false of two of Control's — so it is derived from Build.CARVED_SHARES per rail
	# rather than written once and left to go wrong on whichever rail it does not describe.
	var carved: Array[String] = []
	var added: Array[String] = []
	for category in categories:
		if Build.CARVED_SHARES.has(category):
			carved.append(category)
		else:
			added.append(category)

	var sentences: Array[String] = []
	if not carved.is_empty():
		sentences.append(("%s was a share of the flat %.0f g electronics budget until it became "
			+ "a part. Take one off and the aircraft is lighter by what it actually weighs — "
			+ "an AIO whoop carries none of them.") % [
				"Each of these" if added.is_empty() else "Each of the first %d" % carved.size(),
				Build.ELECTRONICS_BUDGET_G])
	if not added.is_empty():
		sentences.append(("%s was never in that budget. Fitting one makes the aircraft heavier "
			+ "by what it weighs.") % [
				"Each of these" if carved.is_empty() else "The rest"])

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(252, 0)
	note.theme_type_variation = &"MutedLabel"
	note.text = " ".join(sentences)
	root.add_child(note)


# ---------------------------------------------------------------------------
# Public surface (also what the tests drive)
# ---------------------------------------------------------------------------

## THIS RAIL's half of the payload, in the shape Build.from_ids takes: every category this rail
## carries, "" for a bay left empty. Every one present ALWAYS — an absent key would mean "fit the
## default" to Build, which is the one thing an empty bay must not turn back into.
##
## THIS RAIL's, not every optional component: the two rails' dictionaries are merged before they
## reach Build (LabScreen.component_ids), and a rail that answered for the other rail's categories
## would answer "" for bays it cannot see — silently emptying them.
func component_ids() -> Dictionary:
	var out := {}
	for category in categories:
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
