class_name BatteryBenchScreen
extends Control
## The battery bench (labs-and-sim.md §2.1) — a load test. The second of Lab's component benches,
## and deliberately a different KIND of instrument from the first: the thrust stand is a stand,
## and this one is a chart.
##
## What is under test is the pack, under a load resembling flight. What it tells you is the two
## things §2.1 names: how far the voltage sags under that current, and how long the pack holds up.
## Sag is the entire content of it — a pack with high internal resistance reads a healthy capacity
## on its label and then collapses the moment the motors ask for anything, and the only way to
## know is to load it.
##
## ---------------------------------------------------------------------------
## THE LOAD IS THE REAL MOTORS, NOT AN AMP FIGURE
## ---------------------------------------------------------------------------
##
## The obvious way to build this bench is a text field where you type 40 A. It would draw the same
## chart and it would teach nothing, because the number you typed is the answer to the question
## you came to ask. So the load here is a THROTTLE applied to a Powertrain running the motors and
## propellers currently chosen on Lab's rails, and the current is whatever those draw.
##
## That is what makes the comparison mean something. Put two packs under the same build and the
## only things that differ are their internal resistance and their capacity — so the gap between
## the two traces is caused by the pack and by nothing else. A high-C 4S 1300 and a Li-ion of the
## same nominal voltage under the same punch is the whole lesson in one picture.
##
## It also produces the feedback a typed figure cannot. A sagging pack spins the motors slower,
## which draws LESS current, which limits the sag — the pack and the motors argue and settle
## somewhere. On the Li-ion that settling point is far below what the spec sheet promises, and
## watching the thrust it reaches fall short is the moment the tradeoff stops being a number.
##
## NOTHING HERE FLIES. Powertrain is the electro-mechanical half of the simulation and runs with
## no rigid body anywhere near it — the same absence the thrust stand asserts, for the same reason.
##
## ---------------------------------------------------------------------------
## TIME RUNS AT 1:1
## ---------------------------------------------------------------------------
##
## A bench run costs real pack charge for as long as it runs, because that is a motor drawing
## current (labs-and-sim.md §5). A four-minute pack takes four minutes to flatten here, and that
## is not an oversight to be compressed away: it is what makes owning two packs mean something.
## Charging is the compressed half, and it happens in the garage.

## Physics at 1 kHz, the same substep the flight loop and the thrust stand use. A bench that
## stepped once per frame would be a different electrical model from the one Sim flies, which is
## precisely what sharing Powertrain exists to prevent.
const PHYSICS_HZ := 1000.0
## High enough that a quarter-second step still runs at the full 1 kHz. The screenshot and
## timelapse tools drive this bench in large steps to watch a twenty-minute discharge without
## waiting twenty minutes, and a cap that silently coarsened the substep would make those runs a
## different simulation from the one on screen.
const MAX_SUBSTEPS := 300

enum Load { HOVER, PUNCH }

const LOAD_NAMES := {
	Load.HOVER: "hover",
	Load.PUNCH: "a full-throttle punch",
}

## Headroom above nominal on the voltage axis, and how far below an empty pack's resting voltage
## the axis reaches so a deep sag stays on the chart.
const AXIS_HEADROOM_V := 0.4
const AXIS_SAG_ROOM_V := 1.5

var catalog: PartsCatalog
var motor_id: String
var propeller_id: String
var battery_id: String

var powertrain: Powertrain
## The persistent charge of every pack, or null for a bench that should start on a full one.
## Injected rather than loaded here, for the reason AssemblyTweaks is: the tests must not depend
## on, or overwrite, the packs of whoever is running them.
var pack_charge: PackCharge = null
var trace: BandTrace
var instruments: BatteryInstruments

## Which load is applied. Switchable mid-run — the trace marks where it changed.
var load_mode: int = Load.HOVER
## Whether the load is connected. Off on arrival: walking into the room must not start draining
## a pack, and a bench you have to connect is also what a real one is.
var running := false
var elapsed_s := 0.0

var _build: Build
var _throttle := 0.0
var _title: Label
var _run_button: Button
var _mode_buttons: Dictionary = {}


func _init(p_catalog: PartsCatalog, p_motor_id: String = "", p_propeller_id: String = "",
		p_battery_id: String = "", p_pack_charge: PackCharge = null) -> void:
	catalog = p_catalog
	pack_charge = p_pack_charge
	motor_id = p_motor_id if p_motor_id != "" else ReferenceBuild.MOTOR_ID
	propeller_id = p_propeller_id if p_propeller_id != "" else ReferenceBuild.PROPELLER_ID
	battery_id = p_battery_id if p_battery_id != "" else ReferenceBuild.BATTERY_ID

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	# Padded, because the stage runs to the window edges otherwise: the caption loses its first
	# character on the left and the throttle button loses its bottom border off the end of the
	# screen. The right-hand instrument panel gets its inset from PanelContainer's stylebox;
	# this column has no panel behind it, so it states the same inset itself.
	var stage_pad := MarginContainer.new()
	stage_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		stage_pad.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	row.add_child(stage_pad)

	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_pad.add_child(stage)

	_title = Label.new()
	_title.theme_type_variation = &"MutedLabel"
	stage.add_child(_title)

	trace = BandTrace.new()
	trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(trace)

	_build_controls(stage)

	instruments = BatteryInstruments.new()
	instruments.custom_minimum_size = Vector2(InstrumentPanel.PANEL_WIDTH, 0)
	instruments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(instruments)

	_rebuild()


func _build_controls(stage: VBoxContainer) -> void:
	var controls := HBoxContainer.new()
	stage.add_child(controls)

	var caption := Label.new()
	caption.text = "LOAD"
	caption.theme_type_variation = &"MutedLabel"
	controls.add_child(caption)

	# Two buttons rather than a dropdown, because switching between them mid-run is the
	# interaction: you want to see the trace step when the punch goes on, and a dropdown puts a
	# menu between you and that.
	for mode in [Load.HOVER, Load.PUNCH]:
		var button := Button.new()
		button.text = "Hover" if mode == Load.HOVER else "Punch"
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(92, 28)
		button.pressed.connect(func() -> void: set_load_mode(mode))
		controls.add_child(button)
		_mode_buttons[mode] = button

	_run_button = Button.new()
	_run_button.toggle_mode = true
	_run_button.custom_minimum_size = Vector2(128, 28)
	_run_button.pressed.connect(func() -> void: set_running(not running))
	controls.add_child(_run_button)


## Regenerates the powertrain for the current parts and pack, and clears the trace. A new pack is
## a new run: the old trace belonged to a different battery and holding it would invite comparing
## two lines that were never under the same conditions.
func _rebuild() -> void:
	_build = Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id, propeller_id, battery_id)

	var geometry := _build.prop_geometry()
	powertrain = Powertrain.create(
		_build.motor_model(), _build.k_t, _build.k_q, _build.battery_model(),
		_build.effective_max_amps, _build.rated_rpm(),
		_build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5
	)

	# The pack arrives as it actually is, not as it came off the shelf. This one line is what
	# makes the second run of the evening different from the first, and it is why a bench run
	# costs something (labs-and-sim.md §5).
	if pack_charge != null:
		pack_charge.apply_to(battery_id, powertrain.battery)

	elapsed_s = 0.0
	trace.clear()
	_configure_axis()
	_apply_load()
	_refresh_labels()
	instruments.render_live(readings())


## The voltage axis for this pack: from a little below where it rests when empty, to a little
## above where it rests when FULL. Derived from the pack's own curve rather than from the samples,
## so two packs drawn on the same axis stay comparable and a Li-ion's deeper collapse does not
## silently rescale itself back into looking like a LiPo's.
##
## The top was nominal voltage plus headroom while nominal WAS the full-charge resting voltage.
## Since the datum moved (physics.md §5) a full 4S rests at 16.8 V rather than 14.8, which is
## above that ceiling — so the resting line started the run drawn off the top of its own chart.
## Both ends now come from the same place: the two ends of this pack's discharge.
func _configure_axis() -> void:
	var pack := powertrain.battery
	var empty := _pack_like(pack)
	empty.used_mah = empty.capacity_mah
	trace.configure(
		empty.resting_voltage_v() - AXIS_SAG_ROOM_V,
		_pack_like(pack).resting_voltage_v() + AXIS_HEADROOM_V,
		empty.resting_voltage_v())


## A full pack with this one's electrical character, for asking where its discharge starts and
## ends without disturbing the pack actually on the bench.
func _pack_like(pack: BatteryModel) -> BatteryModel:
	return BatteryModel.create(pack.nominal_v, pack.internal_r_ohm, pack.capacity_mah,
		pack.cells, pack.chemistry)


## The throttle each load applies. Both come from Build, which is what makes them properties of
## the aircraft rather than of this screen: hover is the throttle that holds this build up, and a
## punch is as far as the throttle goes before the motor's own current limit stops it.
func _apply_load() -> void:
	match load_mode:
		Load.PUNCH:
			_throttle = _build.max_throttle_fraction()
		_:
			# The hover load is the throttle that holds this build up ON THE PACK ON THE BENCH,
			# not the stats panel's nominal-datum figure. A pack half-way through its discharge
			# needs a different command from a fresh one to carry the same weight, and a bench
			# whose load ignored that would be draining the pack at the wrong current — which is
			# precisely the number this bench exists to show.
			_throttle = _build.hover_throttle_for(powertrain.battery)


func set_load_mode(mode: int) -> void:
	load_mode = mode
	_apply_load()
	_refresh_labels()


## Connects or disconnects the load. The trace is NOT cleared on stopping — a run you paused to
## look at is a run you still want to see.
func set_running(value: bool) -> void:
	running = value
	_refresh_labels()


func _refresh_labels() -> void:
	_title.text = "%s under %s — %s + %s" % [
		_build.battery["name"], LOAD_NAMES[load_mode],
		_build.motor["name"], _build.propeller["name"]]
	if _run_button != null:
		_run_button.text = "Disconnect" if running else "Apply load"
		_run_button.button_pressed = running
	for mode in _mode_buttons:
		_mode_buttons[mode].button_pressed = (mode == load_mode)
	instruments.render_build(_build, LOAD_NAMES[load_mode])


## Puts a different pack on the bench, or a different aircraft around it.
func set_selection(p_motor_id: String, p_propeller_id: String, p_battery_id: String) -> void:
	motor_id = p_motor_id
	propeller_id = p_propeller_id
	battery_id = p_battery_id
	running = false
	_rebuild()


## One frame of bench. Separate from _process so a headless test — and the timelapse capture
## tool — can drive it without a scene tree delivering frames.
func advance(delta: float) -> void:
	if not running:
		return

	elapsed_s += delta

	var substeps := clampi(int(ceil(delta * PHYSICS_HZ)), 1, MAX_SUBSTEPS)
	var dt := delta / float(substeps)
	var cmds := PackedFloat64Array([_throttle, _throttle, _throttle, _throttle])
	for _i in substeps:
		powertrain.step(cmds, dt)

	var reading := readings()
	trace.sample(elapsed_s, reading["resting_v"], reading["live_v"], load_mode)
	instruments.render_live(reading)

	# A flat pack is the end of the run, not a pack that goes negative. Disconnecting rather than
	# freezing leaves the trace and the last reading on screen, which is where the knee is.
	if powertrain.battery.remaining_fraction() <= 0.0:
		set_running(false)


func _process(delta: float) -> void:
	if visible:
		advance(delta)


## Writes what this run did back to the persistent store. Called when the room is left rather
## than every frame — the store is the record of what happened, and a save per physics tick would
## be writing a file a thousand times a second to record a number nothing else can see yet.
func persist_pack_charge() -> void:
	if pack_charge != null:
		pack_charge.record_from(battery_id, powertrain.battery)


func current_build() -> Build:
	return _build


func load_name() -> String:
	return LOAD_NAMES[load_mode]


# ---------------------------------------------------------------------------
# What the bench is reading, as numbers. Straight off the published observables and the pack,
# so a test and the panel cannot disagree about what the bench says.
# ---------------------------------------------------------------------------

func readings() -> Dictionary:
	var observables := powertrain.observables
	var pack := powertrain.battery

	var resting_v := pack.resting_voltage_v()
	# Both read off the PUBLISHED observables rather than recomputed here, which is what makes
	# "the bench and the field agree" structural. It is also the difference between this bench
	# and a chart of an amp figure somebody typed in: this current is whatever the motors
	# currently fitted actually pulled at this throttle against this pack's sag.
	var current_a: float = powertrain.observables.current_total_a
	var live_v: float = powertrain.observables.voltage_live_v
	var remaining_mah := pack.capacity_mah * pack.remaining_fraction()

	return {
		"resting_v": resting_v,
		"live_v": live_v,
		"sag_v": resting_v - live_v,
		"current_a": current_a,
		"remaining_mah": remaining_mah,
		"remaining_fraction": pack.remaining_fraction(),
		"elapsed_s": elapsed_s,
		# Time left at the present draw. The number that decides whether a pack is worth its
		# grams — and the one a capacity on a label cannot give you, because it says nothing
		# about what these motors will actually pull.
		"hold_up_s": (remaining_mah / (current_a * 1000.0)) * 3600.0 if current_a > 0.0 else 0.0,
		"thrust_g": observables.total_thrust_n / 9.81 * 1000.0,
	}
