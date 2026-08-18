class_name ProjectMenu
extends PopupMenu
## The drone menu — what drops out of the project chip. §5: **the project name IS the menu**, so it
## has no title of its own and adds no chrome to the shell.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS BEFORE MOST OF IT CAN WORK
## ---------------------------------------------------------------------------
##
## Seven of these nine entries wait on the project container, which is not built. Building the menu
## anyway is a deliberate choice and the same one the system dropdown already made: an entry that
## is visible and greyed tells a builder what the app intends to do, and an entry that is hidden
## tells them the app has no opinion. The second is a lie in this case — the app has a very
## specific opinion about all seven.
##
## What makes it safe to ship half-live is that **being live is one field**. Every entry declares
## `waiting_on`: a non-empty string means "not yet, and here is exactly what it waits on", and it
## becomes the tooltip verbatim so nobody has to guess. Emptying that string is the whole of
## turning an entry on. There is no second list, no `if id == "rename"` anywhere, and no way to
## enable an entry while forgetting to say what it now does.
##
## The tooltips are not apologies. Each names the thing it waits on so that a builder reading them
## in order learns the shape of the app that is coming.

## Emitted when a LIVE entry is chosen. Disabled entries emit nothing — PopupMenu will not fire
## them, which is the machinery doing the work rather than a guard in a handler.
signal action_chosen(action_id: String)

## Every entry, in the order §5 lists them. `waiting_on` empty means the entry works today.
##
## THIS TABLE IS THE FEATURE LIST. Nothing else enumerates what the project menu can do, so an
## entry cannot be added to the app and forgotten here, or removed from here and left dangling in
## a handler.
const ENTRIES := [
	{
		"id": "new",
		"label": "New drone",
		"key": KEY_N,
		"waiting_on": "Waits on the project container. A new drone that left the old one's parts "
			+ "on screen would be describing an aircraft nobody chose.",
	},
	{
		"id": "open",
		"label": "Open…",
		"key": KEY_O,
		"waiting_on": "Waits on the project container. There is no .lothal file to open yet.",
	},
	{
		"id": "duplicate",
		"label": "Duplicate — try a variant",
		"key": KEY_D,
		"waiting_on": "Waits on the project container. Duplicate is how A/B comparison works "
			+ "(§5), and a copy with nowhere to live and no way to switch to it is not a copy.",
	},
	{
		"id": "rename",
		"label": "Rename",
		"key": KEY_NONE,
		"waiting_on": "",
	},
	{"separator": true},
	{
		"id": "export_build_sheet",
		"label": "Export build sheet…",
		"key": KEY_NONE,
		"waiting_on": "Waits on the build sheet itself — designed in "
			+ "2026-08-17-build-sheet-design.md, not built.",
	},
	{
		"id": "export_printed",
		"label": "Export printed parts…",
		"key": KEY_NONE,
		"waiting_on": "Waits on printable geometry: StlWriter, the manifold check, and a first "
			+ "printable part. Nothing prints yet.",
	},
	{
		"id": "reveal",
		"label": "Reveal saved files",
		"key": KEY_NONE,
		"waiting_on": "Waits on there being a saved file to reveal.",
	},
]

## What the RECENT section says while there is nothing to be recent. Not an empty menu: the section
## is part of the shape, and a builder who sees it knows reopening is coming.
const RECENT_EMPTY := "Nothing saved yet"

var _id_by_index: Dictionary = {}


func _init() -> void:
	theme = LothalTheme.get_theme()
	_build()
	id_pressed.connect(_on_id_pressed)


func _build() -> void:
	clear()
	_id_by_index.clear()

	for entry in ENTRIES:
		if bool((entry as Dictionary).get("separator", false)):
			add_separator()
			continue
		_add_entry(entry as Dictionary)

	add_separator("RECENT")
	# One disabled line rather than nothing, for the reason the whole file exists: the absence of
	# recents is a state worth showing, and an empty section looks like a bug.
	add_item(RECENT_EMPTY)
	set_item_disabled(item_count - 1, true)
	set_item_tooltip(item_count - 1,
		"Recent drones appear here once a drone can be saved.")


func _add_entry(entry: Dictionary) -> void:
	var index := item_count
	add_item(str(entry["label"]), index)
	_id_by_index[index] = str(entry["id"])

	var key: int = int(entry.get("key", KEY_NONE))
	if key != KEY_NONE:
		# The accelerator is set even on a disabled entry, so ⌘N reads as ⌘N in the menu from the
		# first day. A disabled item does not fire, so nothing happens — which is the honest
		# behaviour and needs no guard of its own.
		set_item_accelerator(index, KEY_MASK_META | key)

	var waiting_on := str(entry.get("waiting_on", ""))
	if waiting_on == "":
		return
	set_item_disabled(index, true)
	set_item_tooltip(index, waiting_on)


func _on_id_pressed(index: int) -> void:
	if not _id_by_index.has(index):
		return
	action_chosen.emit(str(_id_by_index[index]))


# ---------------------------------------------------------------------------
# Introspection, used by the shell and by the suite
# ---------------------------------------------------------------------------

## Whether `action_id` does something today. One place asks this, one table answers it.
static func is_live(action_id: String) -> bool:
	for entry in ENTRIES:
		if str((entry as Dictionary).get("id", "")) == action_id:
			return str((entry as Dictionary).get("waiting_on", "")) == ""
	return false


static func entry_ids() -> Array:
	var out: Array = []
	for entry in ENTRIES:
		if not bool((entry as Dictionary).get("separator", false)):
			out.append(str(entry["id"]))
	return out
