class_name RoomMenu
extends MenuButton
## The way into every room that is not Lab or Sim and is not reached from an inspector — two
## benches, the field editor and Studio.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A MENU AND NOT SIX MORE DROPDOWN ENTRIES
## ---------------------------------------------------------------------------
##
## These screens are shipped, working, and **unchanged**. What they lack in the new shell is a
## door, not a design. Folding them into the system dropdown would make that list fifteen items
## long, which is the sidebar problem §5 rejected wearing a different control; giving each its own
## floating cluster would spend the viewport the full-bleed layout exists to protect.
##
## So they get one compact control next to the Lab/Sim toggle, and **that is explicitly a holding
## position rather than the design.** CONTINUE-HERE.md §5's answer is that a bench belongs to the
## system it tests — the frame bench under Airframe, the thrust stand under Propulsion — reached
## from that system's inspector, with no separate destination at all. That is the arrangement to
## build. This is what carries the rooms across in the meantime without any of them losing a
## capability, which is §4's whole method: port one system at a time, keep everything working,
## delete the tab bar last.
##
## ## THE THRUST STAND AND THE ESC BENCH HAVE LEFT THIS LIST (P10f, then this slice)
##
## The thrust stand went first, reached from the Motor inspector's own "Open thrust bench…" button
## — the same door the blade designer already uses on the Prop panel. P10f named the ESC bench as
## the next one and did not move it; it has now followed the same pattern, from the ESC panel,
## under the two rows ("Passes in total", "Limited by") that are what the bench measures.
##
## **The pack bench and the frame bench are still here, and the reason is that neither move is
## obvious.** The frame bench belongs under Airframe, whose inspector the room has taken over
## entirely — so its door is a question about where the Airframe room puts one, not about this
## menu. The pack bench tests a component the Power system owns, and that move is available; it is
## simply not this slice. A room without a door is worse than a room in a menu.
##
## **A room leaving this list does not stop being covered.** `tests/test_room_host.gd` derives the
## room list from `RoomHost`'s own `show_*` methods and asserts every one of them has a door; P10f
## amended that check to "in the menu OR in the inspector-reached list", which is an explicit list
## sitting next to the assertion rather than a flag a new room could set for itself. Deleting an
## entry here without adding it there still fails.
##
## The entries are data for the same reason ProjectMenu's are: nothing else enumerates the rooms
## this shell can open, so a room cannot be added to RoomHost and quietly left unreachable here.

## Emitted with the id of the room chosen. The shell turns it into a RoomHost call — this control
## opens nothing itself, for the reason every other part of this shell opens nothing itself.
signal room_chosen(room_id: String)

## Every room reachable from here, in the order the work happens in: you bench the parts, you lay
## out where you are going to fly, and then you look at what the flight left behind.
##
## `separator_before` marks where a group ends. The benches are one kind of thing — a machine
## running under load — and the field editor and Studio are not, and the line is the only thing
## saying so in a list this short.
const ENTRIES := [
	{"id": "battery_bench", "label": "Pack bench", "separator_before": false},
	{"id": "frame_bench", "label": "Frame bench", "separator_before": false},
	{"id": "field_editor", "label": "Field — lay out the course", "separator_before": true},
	{"id": "studio", "label": "Studio — flights already flown", "separator_before": false},
]

var _id_by_index := {}


func _init() -> void:
	text = "Rooms"
	custom_minimum_size = Vector2(96, 30)
	tooltip_text = ("The benches, the field editor and Studio — unchanged, and reached from here "
		+ "until each one lands where it belongs (a bench under the system it tests). Two have "
		+ "moved: the thrust stand opens from the Motor inspector, the ESC bench from the ESC panel.")

	var popup := get_popup()
	for entry in ENTRIES:
		if bool(entry["separator_before"]):
			popup.add_separator()
		var index := popup.item_count
		popup.add_item(str(entry["label"]), index)
		_id_by_index[index] = str(entry["id"])
	popup.id_pressed.connect(_on_id_pressed)


func _on_id_pressed(index: int) -> void:
	# A separator carries an id too and is not in the map. Guarded rather than assumed, because the
	# alternative is emitting an empty room id that the shell would then try to open.
	if _id_by_index.has(index):
		room_chosen.emit(str(_id_by_index[index]))


## The room ids this menu can emit. Exists so a test can assert the menu covers every room RoomHost
## can open, rather than checking five hardcoded strings that would agree with a sixth going
## missing. A room reached from an inspector instead is named in that same test's exemption list.
static func room_ids() -> Array:
	var ids: Array = []
	for entry in ENTRIES:
		ids.append(str(entry["id"]))
	return ids
