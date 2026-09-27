class_name BatteryDetails
extends PartDetails
## The battery panel. All the machinery is PartDetails' — read its header.
##
## Two rows here are not on the pack's label and are the ones worth explaining.
##
## "Energy" is capacity times voltage. Milliamp-hours alone is the number every pack is sold on
## and it is not comparable across cell counts: a 6S 1100 holds more energy than a 4S 1500, which
## is invisible if you only read the capacity. Watt-hours is what actually decides how long you
## fly, and putting it next to the mAh is the cheapest way to make that legible.
##
## "Sag at 30 A" is internal resistance stated as the thing it does. 15 mΩ is an abstraction;
## "0.45 V gone the moment you punch it" is a consequence, and the difference between a good LiPo
## and the Li-ion is a tenth of a volt against three volts. 30 A is a real punch current for a 5"
## quad rather than a derived figure — it is a fixed yardstick chosen so two packs can be compared
## at the same load, which is exactly what the battery bench then does properly against the motors
## actually fitted. It is a label, not a model: nothing reads it.
##
## **THE PACK BENCH OPENS FROM HERE** (PW4). It was the first entry in the Rooms menu — a machine
## that loads one pack, sitting in a list of destinations beside the field editor — and
## `room_menu.gd`'s own header states the arrangement that menu is a holding position for: *a bench
## belongs to the system it tests, reached from that system's inspector.* The two rows directly
## above the button, "Internal resistance" and "Sag at 30 A", are the yardstick version of exactly
## what the bench measures properly: this panel quotes one fixed punch current as a label, and the
## bench runs the pack down against the motors actually fitted. The button is under them for that
## reason and no other.
##
## Same posture as the ESC panel's bench and the Motor panel's thrust stand: the button says what
## happened and the shell decides what to do about it. This panel opens nothing, and the room
## lifecycle stays `RoomHost`'s.

## Emitted when the builder asks for the pack bench. The shell opens it.
signal pack_bench_requested()

const SPEC_ROWS := [
	{"key": "cell_class", "label": "Cells"},
	{"key": "chemistry", "label": "Chemistry"},
	{"key": "c_rating", "label": "C-rating"},
	{"key": "connector", "label": "Connector"},
	{"key": "mass_g", "label": "Pack mass"},
	{"key": "nominal_v", "label": "Nominal voltage"},
	{"key": "mah", "label": "Capacity"},
	{"key": "energy_wh", "label": "Energy"},
	{"key": "internal_r_ohm", "label": "Internal resistance"},
	{"key": "sag_at_30a", "label": "Sag at 30 A"},
]

## The reference punch current the sag row is quoted at. See the header: a yardstick, not a model.
const SAG_REFERENCE_A := 30.0

var _bench_button: Button

func _init() -> void:
	super(SPEC_ROWS)

## The bench door, under the spec rows and above PartDetails' own footer — the same placement and
## the same argument as the ESC panel's.
func _build_footer(root: VBoxContainer) -> void:
	var bench_button := Button.new()
	_bench_button = bench_button
	bench_button.text = "Open pack bench…"
	bench_button.tooltip_text = ("Run this pack down against the motors actually fitted: what it "
		+ "sags to under a real punch, and how long it holds up — the measured form of the two "
		+ "rows above.")
	bench_button.pressed.connect(func() -> void: pack_bench_requested.emit())
	root.add_child(bench_button)

	# PartDetails' stat block still has to be built: `render()` writes into the labels it creates.
	super(root)


## Moves the bench door to the top of the sheet. The Lab dock's Pack page calls this: there the
## sheet sits under the charger in a column 539 px tall at 1280x720, and the charger's shelf line
## grows with every part-used pack, so a button under the ten spec rows lands below the window
## (it measured y=721-757). The header's placement argument — under the two sag rows — loses to
## "one press away" there; everywhere else the button stays where the header says.
func put_bench_button_first() -> void:
	_bench_button.get_parent().move_child(_bench_button, 0)


func _read(battery: Dictionary, key: String) -> String:
	var specs: Dictionary = battery.get("specs", {})

	match key:
		"chemistry":
			return _or_dash(str(specs.get("chemistry", "")))
		"c_rating":
			# Shown as the rating AND as what it means. "75C" is the number on the wrapper; the
			# amps are the thing that decides whether this pack can feed these motors, and a
			# builder should not have to multiply to find out.
			return "%.0fC (%.0f A)" % [float(specs.get("c_rating", 0.0)),
				float(specs.get("mah", 0.0)) / 1000.0 * float(specs.get("c_rating", 0.0))]
		"mass_g":
			return "%.0f g" % float(battery.get("mass_g", 0.0))
		"nominal_v":
			return "%.1f V" % float(specs.get("nominal_v", 0.0))
		"mah":
			return "%.0f mAh" % float(specs.get("mah", 0.0))
		"energy_wh":
			return "%.1f Wh" % (float(specs.get("nominal_v", 0.0)) * float(specs.get("mah", 0.0)) / 1000.0)
		"internal_r_ohm":
			return "%.0f mΩ" % (float(specs.get("internal_r_ohm", 0.0)) * 1000.0)
		"sag_at_30a":
			return "−%.2f V" % (float(specs.get("internal_r_ohm", 0.0)) * SAG_REFERENCE_A)
	return super(battery, key)
