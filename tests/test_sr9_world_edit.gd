class_name TestSr9WorldEdit
extends RefCounted
## L2.1-L2.3 WorldEditModel: vertex / obstacle / preset / sun / wind edits on a duplicate, tags per field, save-load fingerprint.
## FAIL-PROOFS observed 2026-11-10 (each restored, 16/16 green after): MT1 delete_vertex size guard removed: only the delete-below-3 case FAILS (count=2).
## MT2 _mark_user removed from set_obstacle_field: 4 cases FAIL (height user tag, pole radius, tag shift, tag survives save/load).
## MT3 constructor keeps the caller's World instead of a duplicate: the original-not-mutated case FAILS (plus add_obstacle, as the shared base is polluted).
## MT4 World.from_data drops gustiness_mps (a round trip losing one field): the set_wind case FAILS (the gust it stored is gone from result()).
## L2.4 editor: ME1 wind handler stops calling model.set_wind (control not wired): 4 cases FAIL (wind speed, direction+gust, wind tag, changed signal). ME2 tag labels made static (text "estimated"): 2 cases FAIL (wind tag, obstacle height tag). Both restored, 32/32 green. Editor cases run free-standing (no SceneTree): see _put.

const PRESET := "calm_test_field"


static func _base() -> World:
	return WorldPresets.by_id(PRESET)


static func _model() -> WorldEditModel:
	return WorldEditModel.new(_base())


static func _box() -> Dictionary:
	return {"kind": "box", "x": 10.0, "z": 5.0, "dims": {"w": 4.0, "h": 3.0, "d": 4.0, "yaw_deg": 0.0}}


static func run() -> Array:
	var out: Array = []
	var base := _base()
	var fp0 := base.fingerprint()
	var n0 := floori(base.polygon.size() * 0.5)

	var m := _model()
	var ok := m.add_vertex(1, Vector2(40.0601, -88.2299))
	var w := m.result()
	out.append(TestResult.new("sr9 world edit: add_vertex grows the polygon and changes the fingerprint",
		ok and w.polygon.size() == base.polygon.size() + 2 and w.fingerprint() != fp0, "n=%d" % floori(w.polygon.size() * 0.5)))

	m = _model()
	m.move_vertex(0, Vector2(40.07, -88.22))
	w = m.result()
	out.append(TestResult.new("sr9 world edit: move_vertex changes that vertex and the fingerprint",
		absf(w.polygon[0] - 40.07) < 1.0e-5 and w.polygon.size() == base.polygon.size() and w.fingerprint() != fp0, str(w.polygon[0])))

	m = _model()
	ok = m.delete_vertex(0)
	w = m.result()
	out.append(TestResult.new("sr9 world edit: delete_vertex removes one vertex (4 -> 3) and changes the fingerprint",
		n0 == 4 and ok and w.polygon.size() == base.polygon.size() - 2 and w.fingerprint() != fp0, "n0=%d" % n0))

	m = _model()
	m.delete_vertex(0)
	var refused := not m.delete_vertex(0)
	out.append(TestResult.new("sr9 world edit: delete below 3 vertices is refused and the polygon stays at 3",
		refused and m.vertex_count() == 3, "count=%d" % m.vertex_count()))

	m = WorldEditModel.new(base)
	m.add_vertex(0, Vector2(40.0, -88.0))
	m.add_obstacle(_box())
	m.set_wind(9.0, 90.0, 1.0)
	m.set_obstacle_field(0, "h", 9.0)
	out.append(TestResult.new("sr9 world edit: the original World is not mutated by edits",
		base.fingerprint() == fp0 and base.obstacles.is_empty(), "fp changed" if base.fingerprint() != fp0 else ""))

	m = _model()
	ok = m.add_obstacle(_box())
	out.append(TestResult.new("sr9 world edit: add_obstacle appends one obstacle",
		ok and m.result().obstacles.size() == base.obstacles.size() + 1 and m.result().fingerprint() != fp0, ""))

	m = _model()
	m.add_obstacle(_box())
	m.remove_obstacle(0)
	out.append(TestResult.new("sr9 world edit: remove_obstacle restores the original fingerprint",
		m.result().fingerprint() == fp0, m.result().fingerprint()))

	m = _model()
	m.add_obstacle(_box())
	out.append(TestResult.new("sr9 world edit: obstacle height starts estimated",
		m.field_tag("obstacle.0.h") == "estimated", m.field_tag("obstacle.0.h")))

	m = _model()
	m.add_obstacle(_box())
	m.set_obstacle_field(0, "h", 7.5)
	out.append(TestResult.new("sr9 world edit: obstacle height is tagged user after an edit, default_tag estimated kept, value stored",
		m.field_tag("obstacle.0.h") == "user" and m.default_tag("obstacle.0.h") == "estimated"
		and is_equal_approx(float(m.result().obstacles[0].dims["h"]), 7.5), m.field_tag("obstacle.0.h")))

	m = _model()
	m.add_obstacle({"kind": "pole", "x": 1.0, "z": 1.0, "dims": {"radius": 0.2, "height": 5.0}})
	m.set_obstacle_field(0, "radius", 0.3)
	out.append(TestResult.new("sr9 world edit: obstacle radius starts estimated then user (pole)",
		m.field_tag("obstacle.0.height") == "estimated" and m.field_tag("obstacle.0.radius") == "user", ""))

	m = _model()
	m.add_obstacle(_box())
	m.add_obstacle({"kind": "pole", "x": 1.0, "z": 1.0, "dims": {"radius": 0.2, "height": 5.0}})
	m.set_obstacle_field(1, "radius", 0.3)
	m.remove_obstacle(0)
	out.append(TestResult.new("sr9 world edit: removing obstacle 0 shifts the tags of obstacle 1 down with it",
		m.field_tag("obstacle.0.radius") == "user" and m.field_tag("obstacle.1.radius") == "", m.field_tag("obstacle.0.radius")))

	m = _model()
	m.add_vertex(0, Vector2(40.0, -88.0))
	m.set_preset("windy_coast")
	out.append(TestResult.new("sr9 world edit: set_preset equals the preset's fingerprint (earlier edits do not linger)",
		m.result().fingerprint() == WorldPresets.by_id("windy_coast").fingerprint(), ""))

	m = _model()
	var sun_before := m.field_tag("sun.time")
	m.set_sun("2026-12-21T17:00:00Z", 35.0, -100.0)
	w = m.result()
	out.append(TestResult.new("sr9 world edit: set_sun stores time and place, sun() is computed from them, both fields tagged user",
		sun_before != "user" and w.utc == "2026-12-21T17:00:00Z" and is_equal_approx(w.origin_lat, 35.0)
		and not is_nan(float(w.sun()["elevation_deg"])) and m.field_tag("sun.time") == "user" and m.field_tag("sun.origin") == "user"
		and m.default_tag("sun.time") == sun_before, "before=" + sun_before))

	m = _model()
	var wind_before := m.field_tag("wind.speed")
	m.set_wind(8.0, 270.0, 1.2)
	w = m.result()
	out.append(TestResult.new("sr9 world edit: set_wind stores speed, direction, gust; all three tagged user with default kept",
		is_equal_approx(w.wind_speed_mps, 8.0) and is_equal_approx(w.wind_from_deg, 270.0) and is_equal_approx(w.gustiness_mps, 1.2)
		and m.field_tag("wind.speed") == "user" and m.field_tag("wind.from") == "user" and m.field_tag("wind.gust") == "user"
		and m.default_tag("wind.speed") == wind_before and wind_before != "user", "before=" + wind_before))

	m = _model()
	m.add_vertex(2, Vector2(40.0605, -88.2297))
	m.add_obstacle(_box())
	m.set_obstacle_field(0, "h", 6.0)
	m.set_wind(8.0, 270.0, 1.2)
	m.set_sun("2026-12-21T17:00:00Z", 35.0, -100.0)
	w = m.result()
	var path := "user://sr9_world_edit_roundtrip.world.json"
	var saved := w.save(path)
	var loaded := World.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	out.append(TestResult.new("sr9 world edit: save then load gives an identical fingerprint (edits, tags and all)",
		saved and loaded != null and loaded.fingerprint() == w.fingerprint(), "saved=%s" % str(saved)))

	m = _model()
	m.add_obstacle(_box())
	m.set_obstacle_field(0, "h", 6.0)
	var loaded2 := World.from_data(JSON.parse_string(m.result().to_json()))
	var wm := WorldEditModel.new(loaded2)
	out.append(TestResult.new("sr9 world edit: a user tag survives save/load",
		wm.field_tag("obstacle.0.h") == "user" and wm.default_tag("obstacle.0.h") == "estimated", wm.field_tag("obstacle.0.h")))
	out.append_array(_editor_cases(base))
	return out


## L2.4 WorldEditor, one case each. NOTE: the suite runner has no SceneTree, so the editor is built free-standing (never added to a
## tree); signals and button presses are driven by hand (value = x / pressed.emit()), which runs the same callbacks.
## Free-standing SpinBoxes (as DsStepper does not) queue value_changed for the tree (verified: it never fires without one), so the test sets the value and
## emits the signal itself; in a tree the handler runs the same way.
static func _put(sb: DsStepper, v: float) -> void:
	sb.value = v
	sb.value_changed.emit(sb.value)


static func _editor() -> WorldEditor:
	return WorldEditor.new(_model())


static func _editor_cases(base: World) -> Array:
	var out: Array = []
	var fp0 := base.fingerprint()
	var e := _editor()
	out.append(TestResult.new("sr9 world edit: editor has preset, sun, wind, vertex and obstacle controls",
		e.preset_option != null and e.sun_lat != null and e.sun_lon != null and e.sun_time != null and e.wind_speed != null
		and e.wind_from != null and e.wind_gust != null and e.vertex_list != null and e.add_vertex_button != null
		and e.delete_vertex_button != null and e.obstacle_list != null and e.add_obstacle_button != null
		and e.remove_obstacle_button != null and e.vertex_list.item_count == 4, ""))

	e = _editor()
	e.preset_option.item_selected.emit(WorldPresets.IDS.find("windy_coast"))
	out.append(TestResult.new("sr9 world edit: preset control switches the model to that preset",
		e.model.result().fingerprint() == WorldPresets.by_id("windy_coast").fingerprint()
		and absf(e.wind_speed.value - WorldPresets.by_id("windy_coast").wind_speed_mps) < 0.001, ""))

	e = _editor()
	_put(e.sun_lat, base.origin_lat + 1.0)
	out.append(TestResult.new("sr9 world edit: sun latitude field changes the model fingerprint",
		e.model.result().fingerprint() != fp0 and is_equal_approx(e.model.result().origin_lat, base.origin_lat + 1.0), ""))

	e = _editor()
	e.sun_time.text = "2026-12-21T17:00:00Z"
	e.sun_time.text_submitted.emit(e.sun_time.text)
	out.append(TestResult.new("sr9 world edit: sun time field changes the model fingerprint",
		e.model.result().fingerprint() != fp0 and e.model.result().utc == "2026-12-21T17:00:00Z", ""))

	e = _editor()
	_put(e.wind_speed, 9.0)
	out.append(TestResult.new("sr9 world edit: wind speed field changes the model fingerprint",
		e.model.result().fingerprint() != fp0 and is_equal_approx(e.model.result().wind_speed_mps, 9.0), ""))

	e = _editor()
	_put(e.wind_from, 123.0)
	_put(e.wind_gust, 2.0)
	out.append(TestResult.new("sr9 world edit: wind direction and gust fields reach the model",
		is_equal_approx(e.model.result().wind_from_deg, 123.0) and is_equal_approx(e.model.result().gustiness_mps, 2.0), ""))

	e = _editor()
	e.add_vertex_button.pressed.emit()
	out.append(TestResult.new("sr9 world edit: add-vertex button adds a vertex, list shows 5",
		e.model.vertex_count() == 5 and e.vertex_list.item_count == 5 and e.model.result().fingerprint() != fp0, ""))

	e = _editor()
	_put(e.vertex_lat, base.polygon[0] + 0.001)
	out.append(TestResult.new("sr9 world edit: vertex latitude field moves the selected vertex",
		absf(e.model.result().polygon[0] - (base.polygon[0] + 0.001)) < 1.0e-5 and e.model.result().fingerprint() != fp0, ""))

	e = _editor()
	e.delete_vertex_button.pressed.emit()
	out.append(TestResult.new("sr9 world edit: delete-vertex button removes a vertex (4 -> 3)",
		e.model.vertex_count() == 3 and e.vertex_list.item_count == 3, ""))

	e = _editor()
	e.delete_vertex_button.pressed.emit()
	var fp3 := e.model.result().fingerprint()
	var disabled3 := e.delete_vertex_button.disabled
	e.delete_vertex_button.pressed.emit()
	out.append(TestResult.new("sr9 world edit: at 3 vertices the delete button is disabled and pressing it changes nothing",
		disabled3 and e.model.vertex_count() == 3 and e.model.result().fingerprint() == fp3, ""))

	e = _editor()
	e.add_obstacle_button.pressed.emit()
	out.append(TestResult.new("sr9 world edit: add-obstacle button adds one, with editable fields",
		e.model.result().obstacles.size() == 1 and e.obstacle_list.item_count == 1 and e.obstacle_fields.has("x")
		and e.obstacle_fields.size() == 6 and e.model.result().fingerprint() != fp0, str(e.obstacle_fields.size())))

	e = _editor()
	e.add_obstacle_button.pressed.emit()
	var fp1 := e.model.result().fingerprint()
	_put(e.obstacle_fields["h"], 7.5)
	out.append(TestResult.new("sr9 world edit: obstacle field changes the model fingerprint and value",
		e.model.result().fingerprint() != fp1 and is_equal_approx(float(e.model.result().obstacles[0].dims["h"]), 7.5), ""))

	e = _editor()
	e.add_obstacle_button.pressed.emit()
	e.remove_obstacle_button.pressed.emit()
	out.append(TestResult.new("sr9 world edit: remove-obstacle button restores the original fingerprint",
		e.model.result().fingerprint() == fp0 and e.remove_obstacle_button.disabled, ""))

	e = _editor()
	var before := (e.tag_labels["wind.speed"] as Label).text
	_put(e.wind_speed, 9.0)
	out.append(TestResult.new("sr9 world edit: wind tag label shows user after an edit (was not user before)",
		before != "user" and (e.tag_labels["wind.speed"] as Label).text == "user", "before=" + before))

	e = _editor()
	e.add_obstacle_button.pressed.emit()
	var h_before := (e.tag_labels["obstacle.0.h"] as Label).text
	_put(e.obstacle_fields["h"], 7.5)
	out.append(TestResult.new("sr9 world edit: obstacle height tag label estimated -> user after an edit",
		h_before == "estimated" and (e.tag_labels["obstacle.0.h"] as Label).text == "user", "before=" + h_before))

	e = _editor()
	var seen: Array = []
	e.changed.connect(func(w: World) -> void: seen.append(w))
	_put(e.wind_speed, 9.0)
	out.append(TestResult.new("sr9 world edit: changed(world) fires once per edit with the edited world",
		seen.size() == 1 and is_equal_approx((seen[0] as World).wind_speed_mps, 9.0), str(seen.size())))
	return out
