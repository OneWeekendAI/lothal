class_name EscBenchScreen
extends Control
## The ESC bench (labs-and-sim.md §2.1) — the third of Lab's component benches, and a chart rather
## than a stand, like the battery bench and unlike the thrust stand.
##
## What is under test is the board against THE MOTORS ALREADY CHOSEN. Never the ESC alone: a 45 A
## 4-in-1 is enormous headroom behind four 1404s and marginal behind four 2808s, and the unit under
## test is the pairing, exactly as it is on the thrust stand.
##
## What you do is sweep the throttle from idle to full and watch what the motors actually pull.
## What it tells you is current PER CHANNEL against the board's continuous rating PER CHANNEL —
## the comparison the hardware really makes, and the one number a builder cannot get off a product
## page. What you decide is whether this board has the headroom for these motors, or whether the
## money is better spent on the pack.
##
## ---------------------------------------------------------------------------
## THE SWEEP MUST NOT BE CAPPED BY THE THING UNDER TEST
## ---------------------------------------------------------------------------
##
## Every other room in Lothal commands throttle through Build.max_throttle_fraction(), which is
## already clamped by whichever of the motors, the pack and the ESC runs out first. Doing that here
## would ask what the motors draw once the board has already stopped them — so the draw would
## approach the rating and never cross it, and EVERY board in the catalog would report exactly
## enough headroom for itself. That is a failure that looks exactly like a working feature, which
## is why the ceiling here comes from the motors alone (Build.motor_throttle_limit) and why
## tests/test_esc_bench.gd asserts that an undersized board is driven past its rating rather than
## up to it.
##
## Pack SAG still limits the current, because it is real and physical — a sagging pack spins the
## motors slower, which draws less current. What is left out is the pack's C-rating cap, which is
## a modelled ceiling belonging to the battery bench: applied here, a weak pack would make a weak
## board look adequate, and the board is what fails the day a better battery goes on.
##
## ---------------------------------------------------------------------------
## BURST IS NOT MODELLED, AND THE BENCH SAYS SO
## ---------------------------------------------------------------------------
##
## escs.json carries a burst rating for every board because it is printed next to the continuous
## one and builders compare both. It is not used as a limit anywhere, and this bench must not be
## the place that starts: a burst figure quoted beside a headroom figure reads as the real ceiling
## whatever its label says. So it appears on the panel labelled as unmodelled, in the row and again
## in the note, rather than being silently left off.
##
## NOTHING HERE FLIES. Powertrain is the electro-mechanical half of the simulation and runs with no
## rigid body anywhere near it — the same absence the other two benches assert, for the same reason.

## Physics at 1 kHz, the same substep the flight loop and the other two benches use. A bench that
## stepped once per frame would be a different electrical model from the one Sim flies, which is
## precisely what sharing Powertrain exists to prevent.
const PHYSICS_HZ := 1000.0
## High enough that a quarter-second step still runs at the full 1 kHz, for the same reason
## BatteryBenchScreen's is: the screenshot tool drives this bench by hand in large steps.
const MAX_SUBSTEPS := 300

## Idle to full, one direction. The thrust stand sweeps up and back because it is judging a curve;
## here the top of the ramp is the answer, so the sweep stops there and leaves it on screen.
const SWEEP_SECONDS := 6.0

## How finely the trace samples the throttle axis. Far finer than the battery bench's default,
## because the whole axis is one unit wide rather than several hundred seconds.
const SAMPLE_INTERVAL := 0.004

## Headroom left above the taller of the rating and the demand, so neither line is drawn against
## the top edge of its own chart.
const AXIS_HEADROOM := 1.25
## Gridlines every ten amps. A rating axis running to eighty would otherwise be eighty lines.
const AXIS_STEP_A := 10.0

var catalog: PartsCatalog
var frame_id: String
var motor_id: String
var propeller_id: String
var battery_id: String
var esc_id: String

var powertrain: Powertrain
## The persistent charge of every pack, or null for a bench that should start on a full one. A
## sweep costs charge exactly as a flight does — motors on a bench are drawing current
## (labs-and-sim.md §5) — and injecting it rather than loading it keeps the tests off the packs of
## whoever is running them.
var pack_charge: PackCharge = null
var trace: BandTrace
var instruments: EscInstruments

## Whether a sweep is under way. Off on arrival: walking into the room must not start spinning
## motors, and a bench you have to start is also what a real one is.
var running := false
var throttle := 0.0
var sweep_elapsed := 0.0

var _build: Build
var _title: Label
var _run_button: Button


func _init(p_catalog: PartsCatalog, p_motor_id: String = "", p_propeller_id: String = "",
		p_battery_id: String = "", p_esc_id: String = "", p_pack_charge: PackCharge = null,
		p_frame_id: String = "") -> void:
	catalog = p_catalog
	pack_charge = p_pack_charge
	motor_id = p_motor_id if p_motor_id != "" else ReferenceBuild.MOTOR_ID
	propeller_id = p_propeller_id if p_propeller_id != "" else ReferenceBuild.PROPELLER_ID
	battery_id = p_battery_id if p_battery_id != "" else ReferenceBuild.BATTERY_ID
	esc_id = p_esc_id if p_esc_id != "" else ReferenceBuild.ESC_ID
	frame_id = p_frame_id if p_frame_id != "" else ReferenceBuild.FRAME_ID

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
	# Against THROTTLE, not against time. The sweep takes six seconds to run, but "at what throttle
	# does this board become the binding constraint" is not a question a time axis can answer.
	trace.x_axis = BandTrace.XAxis.FRACTION
	trace.x_max = 1.0
	trace.base_interval = SAMPLE_INTERVAL
	trace.y_unit = "A"
	trace.y_step = AXIS_STEP_A
	trace.upper_colour = InstrumentPanel.LIMIT_COLOUR
	trace.lower_colour = InstrumentPanel.EFFICIENCY_COLOUR
	trace.fill_colour = Color(0.55, 0.86, 0.68, 0.16)
	trace.empty_hint = "Sweep the throttle to see what one channel actually passes."
	trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(trace)

	_build_controls(stage)

	instruments = EscInstruments.new()
	instruments.custom_minimum_size = Vector2(InstrumentPanel.PANEL_WIDTH, 0)
	instruments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(instruments)

	_rebuild()


func _build_controls(stage: VBoxContainer) -> void:
	var controls := HBoxContainer.new()
	stage.add_child(controls)

	var caption := Label.new()
	caption.text = "THROTTLE"
	caption.theme_type_variation = &"MutedLabel"
	controls.add_child(caption)

	_run_button = Button.new()
	_run_button.custom_minimum_size = Vector2(128, 28)
	_run_button.pressed.connect(start_sweep)
	controls.add_child(_run_button)


## Regenerates the powertrain for the current board and motors, and clears the trace. A new board
## is a new run: the old trace belonged to a different rating and holding it would invite comparing
## two lines that were never drawn against the same ceiling.
func _rebuild() -> void:
	_build = Build.from_ids(catalog, frame_id, motor_id, propeller_id, battery_id, esc_id)

	var geometry := _build.prop_geometry()
	powertrain = Powertrain.create(
		_motor_model_for_the_sweep(), _build.k_t, _build.k_q, _build.battery_model(),
		_build.effective_max_amps, _build.rated_rpm(),
		_build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5, geometry.pitch_m,
		_build.air.kgm3()
	)

	# The pack arrives as it actually is, not as it came off the shelf — the same line that makes
	# the second run of the evening different from the first on the other two benches.
	if pack_charge != null:
		pack_charge.apply_to(battery_id, powertrain.battery)

	running = false
	throttle = 0.0
	sweep_elapsed = 0.0
	trace.clear()
	_configure_axis()
	_refresh_labels()
	instruments.render_build(_build)
	instruments.render_live(readings())


## The motor model this bench sweeps, whose ceiling is the MOTORS' current limit and not the
## build's. See the header: a sweep clamped by the board under test cannot fail.
func _motor_model_for_the_sweep() -> MotorModel:
	return MotorModel.create(float(_build.motor["specs"]["kv"]), sweep_ceiling())


## The ceiling the ramp runs to — what these MOTORS will ask for, and deliberately not
## Build.max_throttle_fraction(), which is already clamped by the board under test. See the header:
## a sweep capped by the thing it is measuring walks the draw up to the rating and stops, and
## reports that every board in the catalog is exactly big enough.
func sweep_ceiling() -> float:
	return _build.motor_throttle_limit()


## The current axis for this pairing: zero to comfortably above whichever is taller, the rating or
## the demand. Derived from both rather than from the samples, so two boards under the same motors
## are drawn on the same axis and an undersized one does not silently rescale itself back into
## looking adequate.
func _configure_axis() -> void:
	var tallest := maxf(_build.esc_continuous_a(), _build.motor_demand_per_channel_a())
	trace.configure(0.0, maxf(tallest * AXIS_HEADROOM, AXIS_STEP_A))


func _refresh_labels() -> void:
	_title.text = "%s under four %s — %s" % [
		_build.esc.get("name", "ESC"), _build.motor["name"], _build.propeller["name"]]
	if _run_button != null:
		_run_button.text = "Sweeping…" if running else "Sweep throttle"
		_run_button.disabled = running


## Puts a different board on the bench, or different motors around it.
func set_selection(p_motor_id: String, p_propeller_id: String, p_battery_id: String,
		p_esc_id: String, p_frame_id: String = "") -> void:
	motor_id = p_motor_id
	propeller_id = p_propeller_id
	battery_id = p_battery_id
	esc_id = p_esc_id
	if p_frame_id != "":
		frame_id = p_frame_id
	_rebuild()


## Runs the throttle from idle to the motors' own ceiling. Starting a sweep clears the previous
## one: two ramps drawn over each other on a throttle axis are not two runs, they are one
## illegible line.
func start_sweep() -> void:
	trace.clear()
	sweep_elapsed = 0.0
	throttle = 0.0
	running = true
	_refresh_labels()


## One frame of bench. Separate from _process so a headless test — and the screenshot tool — can
## drive it without a scene tree delivering frames, and so the two never drive it at once.
func advance(delta: float) -> void:
	if not running:
		return

	sweep_elapsed += delta
	var phase := clampf(sweep_elapsed / SWEEP_SECONDS, 0.0, 1.0)
	throttle = sweep_ceiling() * phase

	var substeps := clampi(int(ceil(delta * PHYSICS_HZ)), 1, MAX_SUBSTEPS)
	var dt := delta / float(substeps)
	var cmds := PackedFloat64Array([throttle, throttle, throttle, throttle])
	for _i in substeps:
		powertrain.step(cmds, dt)

	var reading := readings()
	trace.sample(throttle, reading["rating_a"], reading["draw_per_channel_a"])
	instruments.render_live(reading)

	# The top of the ramp is the answer, so the run stops there rather than falling back to idle —
	# leaving the last reading and the whole curve on screen, which is where the crossing is.
	if phase >= 1.0:
		running = false
		_refresh_labels()


func _process(delta: float) -> void:
	if visible:
		advance(delta)


## Writes what this sweep took out of the pack back to the persistent store. Called when the room
## is left rather than every frame — see BatteryBenchScreen.persist_pack_charge.
func persist_pack_charge() -> void:
	if pack_charge != null:
		pack_charge.record_from(battery_id, powertrain.battery)


func current_build() -> Build:
	return _build


# ---------------------------------------------------------------------------
# What the bench is reading, as numbers. Straight off the published observables and the board, so
# a test and the panel cannot disagree about what the bench says.
# ---------------------------------------------------------------------------

func readings() -> Dictionary:
	# PER CHANNEL, and this division is the whole point of the bench. A 4-in-1 gives each motor its
	# own channel, so what one channel passes is what one motor pulls — total current divided by
	# four — and that is what the board's per-channel rating is a rating OF. Comparing the total
	# against the per-channel rating instead would report every board in the catalog as the binding
	# constraint on every build.
	var draw_per_channel: float = powertrain.observables.current_total_a / 4.0

	return {
		"rating_a": _build.esc_continuous_a(),
		"burst_a": _build.esc_burst_a(),
		"channels": _build.esc_channels(),
		"draw_per_channel_a": draw_per_channel,
		"draw_total_a": powertrain.observables.current_total_a,
		"demand_per_channel_a": _build.motor_demand_per_channel_a(),
		"headroom_a": _build.esc_channel_headroom_a(),
		"has_headroom": _build.esc_has_channel_headroom(),
		"throttle": throttle,
		# Where the draw line crossed the rating line, read off the trace rather than recomputed,
		# so the number the panel quotes is a point that is actually on the chart.
		"crossing_throttle": trace.first_crossing_x(),
		"worst_overshoot_a": trace.worst_overshoot(),
		"binding_component": str(_build.limiting_component()["name"]),
	}
