class_name MotorDetails
extends PartDetails
## The motor panel. All the machinery is PartDetails' — read its header.
##
## The row worth explaining is "Thrust measured on". A motor's headline thrust figure is
## meaningless without the propeller and pack it was measured with, and Build fits the thrust
## coefficient from exactly that pairing (physics.md §4). Showing it puts the provenance of the
## number on screen next to the number, which is the difference between a spec sheet and a
## claim. It is also the row that makes an over-propped build legible: when the max thrust says
## 1450 g and the pairing says a 5x4.3 on 4S, a 7" prop fitted to it is visibly not the test
## condition.
##
## ## THE TWO BUTTONS AT THE BOTTOM — P10f
##
## **The thrust stand opens from here**, and that is the whole of P10f's navigation change. It used
## to be the first entry in the Rooms menu, which put a machine that tests a motor-and-propeller
## pairing in a list of destinations next to the field editor. `room_menu.gd`'s own header states
## the arrangement it was a holding position for: *a bench belongs to the system it tests*, reached
## from that system's inspector. This panel is that inspector, the pairing is what the two rows
## above ("Max thrust", "Thrust measured on") are about, and the bench is where that pairing is put
## under load. The Prop panel's "Design this blade…" already established the pattern.
##
## The button says what happened; the shell decides what to do about it. This panel opens nothing,
## on the rule every control in this UI follows, and the room lifecycle stays `RoomHost`'s — the
## bench is the same `BenchScreen` the menu used to construct, opened the same way, retracting the
## same chrome.
##
## **And the mount stack exports as STL**, because the stack drawn under the propeller is the one
## piece of geometry a builder needs OUTSIDE this app: to check a camera clears the bell, or that
## the frame they are drawing has room for the pad. It is not a printed part and the export does
## not pretend it is — `PropulsionExport` says so in its own header. The guard, which IS printed,
## exports from the Prop panel's guard row, because a guard wraps the disc rather than the motor.

## Emitted when the builder asks for the thrust stand. The shell opens it.
signal thrust_bench_requested()

## Emitted with the motor record when the builder asks for the mount stack as an STL. The shell
## owns the file dialog, for the same reason it owns the room: a details panel that opened a save
## dialog would be a panel that knows where this app puts files.
signal mount_stl_requested(motor: Dictionary)

const SPEC_ROWS := [
	{"key": "stator_class", "label": "Stator class"},
	{"key": "kv_class", "label": "KV class"},
	{"key": "intended_use", "label": "Intended for"},
	{"key": "mass_g", "label": "Motor mass"},
	{"key": "kv", "label": "KV"},
	{"key": "stator", "label": "Stator (Ø × height)"},
	{"key": "max_thrust_g", "label": "Max thrust (each)"},
	{"key": "max_amps", "label": "Max current"},
	{"key": "poles", "label": "Poles"},
	{"key": "mount_pattern", "label": "Mount"},
	{"key": "thrust_test", "label": "Thrust measured on"},
]

var _catalog: PartsCatalog

## The catalog is held so the thrust_test row can name the propeller rather than its part_id —
## "5x4.3x3 at 14.8 V" is provenance a builder can read; "prop_5x43x3" is a database key.
func _init(p_catalog: PartsCatalog) -> void:
	_catalog = p_catalog
	super(SPEC_ROWS)

## The bench door and the stack export, under the spec rows and above PartDetails' own footer —
## the same placement, and the same argument, as the Prop panel's "Design this blade…": the button
## sits directly under the rows that motivate pressing it.
func _build_footer(root: VBoxContainer) -> void:
	var bench_button := Button.new()
	bench_button.text = "Open thrust bench…"
	bench_button.tooltip_text = ("Run this motor and propeller up under load: thrust, current and "
		+ "the RPM they actually reach, against the pairing the row above was measured on.")
	bench_button.pressed.connect(func() -> void: thrust_bench_requested.emit())
	root.add_child(bench_button)

	var stl_button := Button.new()
	stl_button.text = "Export mount stack (STL)…"
	stl_button.tooltip_text = ("The motor, its soft-mount pad, the adapter and the shaft as a "
		+ "solid, in millimetres — for checking fit in someone else's CAD, not for printing.")
	stl_button.pressed.connect(func() -> void: mount_stl_requested.emit(_rendered_part))
	root.add_child(stl_button)

	super(root)


func _read(motor: Dictionary, key: String) -> String:
	var specs: Dictionary = motor.get("specs", {})

	match key:
		"mass_g":
			return "%.0f g" % float(motor.get("mass_g", 0.0))
		"kv":
			return "%.0f KV" % float(specs.get("kv", 0.0))
		"stator":
			return "%.0f × %.0f mm" % [
				float(specs.get("stator_diameter_mm", 0.0)), float(specs.get("stator_height_mm", 0.0))]
		"max_thrust_g":
			return "%.0f g" % float(specs.get("max_thrust_g", 0.0))
		"max_amps":
			return "%.0f A" % float(specs.get("max_amps", 0.0))
		"poles":
			return "%.0f" % float(specs.get("poles", 0.0))
		"mount_pattern":
			return _or_dash(str(motor.get("mount_pattern", "")))
		"thrust_test":
			var test: Dictionary = motor.get("thrust_test", {})
			var prop: Dictionary = _catalog.get_part(str(test.get("prop_id", "")))
			if prop.is_empty():
				return "—"
			return "%s at %.1f V" % [prop.get("name", "?"), float(test.get("voltage_v", 0.0))]
	return super(motor, key)
