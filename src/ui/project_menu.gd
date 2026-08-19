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
## A remembered drone was picked out of RECENT. Its own signal rather than an encoded action id,
## because a path is not an action and packing one into a string is how a drone called "new" ends
## up creating a new drone.
signal recent_chosen(path: String)

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
		"waiting_on": "",
	},
	{
		"id": "open",
		"label": "Open…",
		"key": KEY_O,
		"waiting_on": "",
	},
	{
		"id": "duplicate",
		"label": "Duplicate — try a variant",
		"key": KEY_D,
		"waiting_on": "",
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
		"waiting_on": "",
	},
	{"separator": true},
	# Last, and set off by a separator, because it is the one entry that destroys something. It does
	# not sit beside New or Duplicate, the entries that create drones — a builder reaching for New
	# and finding Delete in the same breath is the one-click-loses-everything shape §10 of the
	# projects design refuses. The deletion itself is a move to the app's trash, not an unlink.
	{
		"id": "delete",
		"label": "Delete",
		"key": KEY_NONE,
		"waiting_on": "",
	},
]

## What the RECENT section says while there is nothing to be recent. Not an empty menu: the section
## is part of the shape, and a builder who sees it knows reopening is coming.
const RECENT_EMPTY := "Nothing saved yet"

var _id_by_index: Dictionary = {}
var _path_by_index: Dictionary = {}
## path -> label, newest first. Set by the shell; empty until a drone has been saved.
var _recent: Array = []
## Whether a drone is open. The entries that need one are greyed while this is false; the chip owns
## the value and refreshes it whenever the open drone changes — including to "no drone" after a
## delete, which is the whole point.
var _has_project := true


func _init() -> void:
	theme = LothalTheme.get_theme()
	_build()
	id_pressed.connect(_on_id_pressed)


func _build() -> void:
	clear()
	_id_by_index.clear()
	_path_by_index.clear()

	for entry in ENTRIES:
		if bool((entry as Dictionary).get("separator", false)):
			add_separator()
			continue
		_add_entry(entry as Dictionary)

	add_separator("RECENT")
	if _recent.is_empty():
		# One disabled line rather than nothing: the absence of recents is a state worth showing,
		# and an empty section looks like a bug.
		add_item(RECENT_EMPTY)
		set_item_disabled(item_count - 1, true)
		set_item_tooltip(item_count - 1, "Drones you open appear here.")
		return

	for entry in _recent:
		var index := item_count
		add_item(str((entry as Dictionary)["label"]), index)
		_path_by_index[index] = str((entry as Dictionary)["path"])
		set_item_tooltip(index, str((entry as Dictionary)["path"]))


## The recent list, as `[{path, label}]`, newest first. Rebuilds the menu — cheap, and it keeps
## this class free of any idea of "updating" an item, which is where off-by-one index bugs live.
func set_recent(entries: Array) -> void:
	_recent = entries.duplicate(true)
	_build()


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
	if waiting_on != "":
		set_item_disabled(index, true)
		set_item_tooltip(index, waiting_on)
		return
	# Live, but meaningless without a drone. A builder who just deleted their only drone should not
	# be offered "Delete" on nothing — so the three project-dependent entries grey in that state,
	# and the greying lives in the same table that decides what the entries do.
	if not _has_project and needs_project(str(entry["id"])):
		set_item_disabled(index, true)
		set_item_tooltip(index, "No drone is open — New or Open one.")


## Whether `action_id` needs a drone open to mean anything. The three that do: Duplicate, Rename
## and Delete all act on the drone you are looking at, and with none open there is nothing to act
## on. New, Open and Reveal work without one.
static func needs_project(action_id: String) -> bool:
	return action_id == "duplicate" or action_id == "rename" or action_id == "delete"


## Tells the menu whether a drone is open, and greys the entries that need one accordingly. The
## chip calls this from `set_project`, so it fires on every New, Open, Duplicate and Delete.
func set_has_project(has_project: bool) -> void:
	_has_project = has_project
	_build()


func _on_id_pressed(index: int) -> void:
	if _path_by_index.has(index):
		recent_chosen.emit(str(_path_by_index[index]))
		return
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
