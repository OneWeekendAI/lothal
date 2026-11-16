class_name DsSimConditions
extends DsDrawer
## R1.7. The world and the weather, from inside the flight (the "World & weather" button, or K).
##
## Until now the only door to the wind, the temperature and the world was the Field system on the Design Space, and a pilot
## standing in the sim had no way to reach it. This is a Design Space drawer (the Parts shelf's box, DsStepper, DsList) over
## the SAME objects the Field system edits: the shell's `ConditionsLibrary`, `SiteLibrary` and `WorldLibrary`. Nothing is
## staged: Apply writes the selected set, saves both files, and hands the flight a fresh wind and a fresh air (`Main`'s
## `apply_conditions_edit`), then respawns the aircraft at the start so the next second of flight is in the new air.
##
## FLIGHT IS PAUSED WHILE IT IS OPEN, so typing a number does not also push the sticks.

signal apply_requested(edit: Dictionary)
signal conditions_chosen(id: String)
signal world_chosen(id: String)

var sim: Node
var set_list: DsList
var world_list: DsList
var wind_speed_field: DsStepper
var wind_from_field: DsStepper
var gust_field: DsStepper
var temperature_field: DsStepper
var elevation_field: DsStepper
var humidity_field: DsStepper
var wander_field: DsStepper
var speed_var_field: DsStepper
var pressure_label: Label
var status_label: Label
var apply_button: Button
var _set_ids: Array[String] = []
var _world_ids: Array[String] = []
var _filling := false


func _init(p_sim: Node) -> void:
	super._init("World & weather")
	sim = p_sim
	name = "SimConditions"
	var c := content
	c.add_child(DsUi.section("Weather set"))
	set_list = DsList.new(true)
	set_list.name = "Sets"
	set_list.item_selected.connect(func(i: int) -> void:
		if not _filling and i >= 0 and i < _set_ids.size():
			conditions_chosen.emit(_set_ids[i]))
	c.add_child(set_list)
	c.add_child(DsUi.section("World"))
	world_list = DsList.new(true)
	world_list.name = "Worlds"
	world_list.item_selected.connect(func(i: int) -> void:
		if not _filling and i >= 0 and i < _world_ids.size():
			world_chosen.emit(_world_ids[i]))
	c.add_child(world_list)
	c.add_child(DsUi.section("Air"))
	wind_speed_field = _field(c, "Wind", "m/s", 0.0, 40.0, 0.5)
	wind_from_field = _field(c, "From", "deg", 0.0, 360.0, 5.0)
	gust_field = _field(c, "Turbulence", "m/s", 0.0, 10.0, 0.1)
	temperature_field = _field(c, "Temperature", "C", AirDensity.MIN_TEMPERATURE_C, AirDensity.MAX_TEMPERATURE_C, 1.0)
	elevation_field = _field(c, "Altitude", "m", AirDensity.MIN_ELEVATION_M, AirDensity.MAX_ELEVATION_M, 50.0)
	humidity_field = _field(c, "Humidity", "%", 0.0, 100.0, 5.0)
	pressure_label = DsUi.label("", DsUi.INK_FAINT)
	pressure_label.name = "Pressure"
	c.add_child(pressure_label)
	c.add_child(DsUi.section("Wind variation"))
	wander_field = _field(c, "Direction wander", "deg", -1.0, 45.0, 1.0)
	speed_var_field = _field(c, "Speed variation", "%", 0.0, 40.0, 1.0)
	var note := DsUi.label("Direction wander -1 = automatic (labelled estimate, larger in light wind).", DsUi.INK_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	c.add_child(note)

	apply_button = DsUi.button("Apply and respawn", false, true)
	apply_button.name = "Apply"
	apply_button.focus_mode = Control.FOCUS_NONE
	apply_button.pressed.connect(func() -> void: apply_requested.emit(edit()))
	footer.add_child(apply_button)
	status_label = DsUi.label("", DsUi.INK_FAINT)
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	footer.add_child(status_label)


func _field(column: VBoxContainer, label_text: String, suffix: String, lo: float, hi: float, step: float) -> DsStepper:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := DsUi.label("%s (%s)" % [label_text, suffix], DsUi.INK_MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var f := DsStepper.new(lo, hi, step)
	f.name = label_text.replace(" ", "")
	f.custom_minimum_size = Vector2(130, 0)
	f.value_changed.connect(func(_v: float) -> void:
		if not _filling:
			_update_pressure())
	row.add_child(f)
	column.add_child(row)
	return f


## The numbers the builder typed, as the dictionary `Main.apply_conditions_edit` reads.
func edit() -> Dictionary:
	return {
		"wind_speed_mps": wind_speed_field.value, "wind_from_deg": wind_from_field.value,
		"gustiness_mps": gust_field.value, "temperature_c": temperature_field.value,
		"elevation_m": elevation_field.value, "humidity_pct": humidity_field.value,
		"dir_sigma_deg": wander_field.value, "speed_sigma_frac": speed_var_field.value / 100.0,
	}


## Reads everything off the live objects: the sets and worlds as chips, the selected set into the steppers.
func refresh(conditions: ConditionsLibrary, site: Site, worlds: WorldLibrary) -> void:
	_filling = true
	_set_ids.clear()
	set_list.clear()
	for id in conditions.ids():
		_set_ids.append(id)
		set_list.add_item(conditions.conditions(id).conditions_name)
	set_list.select(_set_ids.find(conditions.selected_id))
	_world_ids.clear()
	world_list.clear()
	if worlds != null:
		for id in worlds.ids():
			_world_ids.append(id)
			world_list.add_item(worlds.world(id).world_name)
	world_list.select(-1)
	var now := conditions.selected()
	wind_speed_field.value = now.wind_speed_mps
	wind_from_field.value = now.wind_from_deg
	gust_field.value = now.gustiness_mps
	temperature_field.value = now.temperature_c
	elevation_field.value = site.elevation_m if site != null else 0.0
	humidity_field.value = now.humidity_pct
	wander_field.value = now.dir_sigma_deg
	speed_var_field.value = now.speed_sigma_frac * 100.0
	_filling = false
	_update_pressure()


func _update_pressure() -> void:
	var air := AirDensity.new(elevation_field.value, temperature_field.value)
	pressure_label.text = "Pressure %.1f hPa   Air %.3f kg/m3" % [air.pressure_pa() / 100.0, air.kgm3()]
