class_name TestWarningPins
extends RefCounted
## Part-anchored warnings (PLAN Section 8, owner-approved addition) on the 5": every warning kind
## the Design Space can show, each through the production path (choose / remove / drag-and-drop),
## one check per kind and per property.
##
## ## The checks that could have passed while proving nothing
##
## - TAG NUMBERS ARE WORKED OUT HERE, from a fresh Build's own warning values, with this file's own
##   format; a tag that typed its number, or took the wrong value, differs.
## - THE ANCHOR IS JUDGED ON SCREEN: the drawn pin must fall inside the projected box of the part
##   this file expects (the box's eight corners projected here, not `warning_pin_px`).
## - THE IN-AIR MARK is compared with peak thrust over weight computed here from Build, and the
##   readout beside it must still read the bench figure.
## - NO EMPTY PASSES: every geometry case first demands its warning label is actually shown.
## - The per-kind data checks run over every id WarningRows knows, one check per id.

const CLASS_ID := "five_inch"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080)]
const READOUT_KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]

## The build-warning cases: [case, category, part (null = seed), pin id, anchor, readout, blocking].
const CASES := [
	["seed current cap", "", null, "w:current_limit:battery", "part/battery", "thrust_to_weight", false],
	["seed sag", "", null, "w:pack_sag:battery", "part/battery", "thrust_to_weight", false],
	["6S pack, motor current cap", "battery", "battery_6s_1300", "w:current_limit:motors", "part/motor/FR", "thrust_to_weight", false],
	["16\" props, cannot hover", "propeller", "prop_16x12x4", "w:cannot_hover:motors", "part/motor/FR", "thrust_to_weight", true],
	["2S 300 pack, plug over rating", "battery", "battery_2s_300", "w:connector_rating:harness", "part/wires", "", false],
	["6S 5600 pack, wire over rating", "battery", "battery_6s_5600", "w:harness_ampacity:harness", "part/wires", "", false],
	["no receiver", "receiver", "", "w:no_receiver:receiver", "part/stack", "", false],
	["FC-powered buzzer", "buzzer", "buzz_passive_pad", "w:buzzer_not_self_powered:receiver", "part/stack", "", false],
]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	var home: Dictionary = ds.session.selection.duplicate(true)
	_set_size(ds, SIZES[0])
	_reset(ds, home)
	results.append_array(_seed(ds, catalog))
	for c in CASES:
		_reset(ds, home)
		if String(c[1]) != "":
			ds.choose(String(c[1]), String(c[2]))
		ds.update_callouts()
		results.append_array(_kind(ds, catalog, c))
	_reset(ds, home)
	results.append_array(_mark_opens_both(ds, catalog))
	_reset(ds, home)
	results.append_array(_missing_battery(ds))
	_reset(ds, home)
	results.append_array(_refused_drop(ds, catalog, "motor_2808_1300kv", "motor", "part/motor/",
		"Motor mount · %s", "frame_pattern"))
	_reset(ds, home)
	results.append_array(_refused_drop(ds, catalog, "prop_10x5x2", "propeller", "part/prop/",
		"Props too big · %.1f\" max", "max_prop_inches"))
	_reset(ds, home)
	results.append(_refusal_clears_on_change(ds, catalog))
	_reset(ds, home)
	results.append(_selecting_closes_warning(ds))
	_reset(ds, home)
	results.append(_orbit_tracks(ds))
	for sz in SIZES:
		_set_size(ds, sz)
		for g in ["seed", "cannot hover", "no battery", "refused drop"]:
			_reset(ds, home)
			_geometry_state(ds, String(g))
			results.append_array(_geometry(ds, "%dx%d %s" % [sz.x, sz.y, g]))
	_set_size(ds, SIZES[0])
	_reset(ds, home)
	results.append_array(_data_per_kind(ds))
	ds.free()
	results.append(_esc_current_cap_on_stack())
	results.append(_impossible_is_blocking())
	results.append(_count_text())
	return results


static func _set_size(ds: DesignSpace, sz: Vector2) -> void:
	ds.size = sz
	ds.rig.aspect = sz.x / sz.y


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.cancel_drag()
	ds.select("")
	ds.hovered = ""
	ds.callout_focus = ""
	ds.shelf.set_open(false)
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	ds._after_change()
	ds.go_home()
	ds.rig.snap_home()
	ds.update_callouts()


static func _fresh(catalog: PartsCatalog, sel: Dictionary) -> Build:
	var s := DesignSession.default_for_class(CLASS_ID)
	s.selection = sel.duplicate(true)
	return s.build(catalog)


static func _warning_of(b: Build, id: StringName) -> BuildWarning:
	for w in b.warnings():
		if w.id == id:
			return w
	return null


## The tag this file expects for a build warning, from its own values.
static func _expected_tag(w: BuildWarning) -> String:
	var v := w.values
	match w.id:
		&"current_limit": return "Current cap · %d%% throttle" % roundi(float(v["throttle_cap"]) * 100.0)
		&"pack_sag": return "Sags · %.1f:1 in air" % float(v["reachable_twr"])
		&"cannot_hover": return "Cannot hover · %.1f:1 in air" % float(v["reachable_twr"])
		&"connector_rating": return "Plug overloaded · %.0f A" % float(v["sustained_a"])
		&"harness_ampacity": return "Wire overloaded · %.0f A" % float(v["segment_current_a"])
		&"no_receiver": return "No receiver"
		&"buzzer_not_self_powered": return "Buzzer dies with pack"
	return "?"


## The screen rect of `address`'s drawn box (its eight corners projected here).
static func _screen_box(ds: DesignSpace, address: String) -> Rect2:
	var box := ds.picks.box_of(address)
	var r := Rect2()
	for i in 8:
		var p := PickerPlace.to_px(ds.rig.project(box.get_endpoint(i)), ds.size)
		r = Rect2(p, Vector2.ZERO) if i == 0 else r.expand(p)
	return r


## Whether the shown pin `s` sits on `address` (its box, widened by the per-part pin step).
static func _on_part(ds: DesignSpace, s: Dictionary, address: String) -> bool:
	return not s.is_empty() and _screen_box(ds, address).grow(DesignSpace.WARN_PIN_STEP + 1.0).has_point(s["pin"])


static func _peak_twr(b: Build) -> float:
	return float(b.peak_thrust()["thrust_n"]) / b.weight_n()


# ---------------------------------------------------------------------------
# The seed
# ---------------------------------------------------------------------------

static func _seed(ds: DesignSpace, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ids: Array = ds.warning_pins.map(func(p): return String(p["id"]))
	out.append(TestResult.new("seed: its two issues are the pack's current cap and its sag",
		ids == ["w:current_limit:battery", "w:pack_sag:battery"], str(ids)))
	out.append(TestResult.new("seed: the readouts panel says \"2 issues\"",
		ds.issues_label.visible and ds.issues_label.text == "2 issues", "'%s'" % ds.issues_label.text))
	var b := _fresh(catalog, ds.session.selection)
	var mark := ds.mark_buttons["thrust_to_weight"] as Button
	var want := "▲ %.1f in air" % _peak_twr(b)
	out.append(TestResult.new("seed: T:W reads \"%s\" with \"%s\" beside it" % [
		DesignSpace.format_readout("thrust_to_weight", {"thrust_to_weight": b.thrust_to_weight()}), want],
		mark.visible and mark.text == want and (ds.value_labels["thrust_to_weight"] as Label).text == "%.2f : 1" % b.thrust_to_weight()
		and mark.get_theme_color("font_color") == LothalTheme.WARNING,
		"'%s' / '%s'" % [(ds.value_labels["thrust_to_weight"] as Label).text, mark.text]))
	var others: Array = []
	for k in READOUT_KEYS:
		if k != "thrust_to_weight" and (ds.mark_buttons[k] as Button).visible:
			others.append(k)
	out.append(TestResult.new("seed: no other readout is marked", others.is_empty(), str(others)))
	var a := ds.callouts.item("w:current_limit:battery")
	var c := ds.callouts.item("w:pack_sag:battery")
	out.append(TestResult.new("seed: the two battery pins are two dots, a pin step apart",
		not a.is_empty() and not c.is_empty()
		and is_equal_approx((c["pin"] as Vector2).distance_to(a["pin"]), DesignSpace.WARN_PIN_STEP),
		"%s %s" % [a.get("pin"), c.get("pin")]))
	var numbered: Array = TestCallouts._callouts_only(ds.callouts.shown)
	out.append(TestResult.new("seed at 1280x720 home: all six numbered callouts still shown beside the warnings",
		numbered.size() == Callouts.TABLE.size(), "%d" % numbered.size()))
	var characteristic: Array = []
	for w in b.warnings():
		if w.severity == BuildWarning.Severity.CHARACTERISTIC and ids.any(func(i): return String(i).begins_with("w:%s:" % w.id)):
			characteristic.append(w.id)
	out.append(TestResult.new("seed: a description (climb margin, resonance...) gets no pin",
		characteristic.is_empty() and b.warnings().size() > 2, str(characteristic)))
	return out


# ---------------------------------------------------------------------------
# One build-warning kind
# ---------------------------------------------------------------------------

static func _kind(ds: DesignSpace, catalog: PartsCatalog, c: Array) -> Array:
	var out: Array = []
	var case := String(c[0])
	var pid := String(c[3])
	var anchor := String(c[4])
	var readout := String(c[5])
	var blocking: bool = c[6]
	var b := _fresh(catalog, ds.session.selection)
	var wid := StringName(pid.split(":")[1])
	var w := _warning_of(b, wid)
	var p := ds.warning_pin(pid)
	var s := ds.callouts.item(pid)
	out.append(TestResult.new("%s: the build warns %s and the drone carries its pin" % [case, wid],
		w != null and not p.is_empty() and String(s.get("kind", "")) == "warning",
		"warning %s, pin %s, shown %s" % [w != null, not p.is_empty(), s.get("kind", "-")]))
	if w == null or p.is_empty():
		return out
	out.append(TestResult.new("%s: the tag reads \"%s\" (number from the warning's values)" % [case, _expected_tag(w)],
		String(p["tag"]) == _expected_tag(w) and String(s.get("name", "")) == _expected_tag(w),
		"'%s' / drawn '%s'" % [p["tag"], s.get("name", "")]))
	out.append(TestResult.new("%s: the pin sits on %s" % [case, anchor],
		String(p["anchor"]) == anchor and _on_part(ds, s, anchor),
		"anchor %s, pin %s, box %s" % [p["anchor"], s.get("pin"), _screen_box(ds, anchor)]))
	out.append(TestResult.new("%s: it affects the readout '%s'" % [case, readout], String(p["readout"]) == readout,
		"'%s'" % p["readout"]))
	if readout != "":
		var want := "▲ %.1f in air" % _peak_twr(b)
		var mark := ds.mark_buttons[readout] as Button
		out.append(TestResult.new("%s: the %s mark reads \"%s\" (peak thrust over weight)" % [case, readout, want],
			mark.visible and mark.text == want and is_equal_approx(float(p["mark_value"]), _peak_twr(b)),
			"'%s', value %s" % [mark.text, p["mark_value"]]))
	else:
		# This pin's own mark only: the case builds carry other pins whose marks are legitimate.
		var m := WarningPins.marks(ds.warning_pins)
		var any := m.keys().filter(func(k): return (m[k]["ids"] as Array).has(pid))
		out.append(TestResult.new("%s: no readout carries its number, so no mark" % case,
			is_nan(float(p["mark_value"])) and String(p["mark_text"]) == "" and any.is_empty(),
			"value %s, text '%s', marked on %s" % [p["mark_value"], p["mark_text"], any]))
	out.append(TestResult.new("%s: %s, %s dot%s" % [case, "blocking" if blocking else "caution",
		"solid" if blocking else "outline", ", part tinted" if blocking else ", no tint"],
		String(p["severity"]) == (WarningPins.BLOCKING if blocking else WarningPins.CAUTION)
		and bool(s.get("solid", not blocking)) == blocking and bool(s.get("tint", not blocking)) == blocking
		and ds.tinted_parts().has(anchor) == blocking,
		"%s solid %s tint %s tinted %s" % [p["severity"], s.get("solid"), s.get("tint"), ds.tinted_parts()]))
	out.append(TestResult.new("%s: clicking its pin shows the full sentence in the inspector" % case,
		ds.open_warning_at(s.get("pin", Vector2(-1, -1))) and ds.inspector.visible and ds.inspector_lines().has(w.message)
		and ds.warning_open == [pid], "%s" % [ds.inspector_lines()]))
	return out


## The T:W mark is shared by the seed's two warnings: pressing it opens both sentences.
static func _mark_opens_both(ds: DesignSpace, catalog: PartsCatalog) -> Array:
	var b := _fresh(catalog, ds.session.selection)
	var want := [_warning_of(b, &"current_limit").message, _warning_of(b, &"pack_sag").message]
	(ds.mark_buttons["thrust_to_weight"] as Button).pressed.emit()
	var lines := ds.inspector_lines()
	return [TestResult.new("seed: pressing the T:W mark shows both sentences, word for word",
		ds.inspector.visible and lines.has(want[0]) and lines.has(want[1]), str(lines))]


# ---------------------------------------------------------------------------
# Blocking: a missing part, a refused drop
# ---------------------------------------------------------------------------

static func _missing_battery(ds: DesignSpace) -> Array:
	var out: Array = []
	ds.select("part/battery")
	var r := ds.remove_selected()
	ds.update_callouts()
	var p := ds.warning_pin("w:missing:battery")
	var s := ds.callouts.item("w:missing:battery")
	out.append(TestResult.new("no battery: removed, and the drone carries a \"No battery · cannot fly\" pin",
		r["ok"] and not p.is_empty() and String(p["tag"]) == "No battery · cannot fly"
		and String(s.get("kind", "")) == "warning", "%s / %s" % [p.get("tag", "-"), s.get("kind", "-")]))
	out.append(TestResult.new("no battery: the pin sits on the top plate the pack straps to",
		_on_part(ds, s, "frame/plate/top"), "%s" % [s.get("pin")]))
	out.append(TestResult.new("no battery: blocking, solid dot, the top plate tinted",
		String(p.get("severity", "")) == WarningPins.BLOCKING and bool(s.get("solid", false))
		and ds.tinted_parts() == ["frame/plate/top"], "%s" % [ds.tinted_parts()]))
	out.append(TestResult.new("no battery: \"1 issue\", and no numbered callouts without a build",
		ds.issues_label.text == "1 issue" and ds.callouts.shown.size() == 1, "'%s', %d shown" % [
			ds.issues_label.text, ds.callouts.shown.size()]))
	out.append(TestResult.new("no battery: clicking the pin says a drone cannot fly without its battery",
		not s.is_empty() and ds.open_warning_at(s["pin"]) and ds.inspector_lines().has("A drone cannot fly without its battery."),
		str(ds.inspector_lines())))
	return out


## Drags `part` off the shelf onto the first mount `prefix` names and releases it there.
static func _drop_on(ds: DesignSpace, part: String, prefix: String) -> Dictionary:
	var at := ""
	for a in ds.picks.addresses():
		if String(a).begins_with(prefix):
			at = String(a)
			break
	var px := PickerPlace.to_px(ds.rig.project(ds.picks.box_of(at).get_center()), ds.size)
	ds.begin_shelf_drag(part)
	ds.drag_over(px)
	var v := ds.end_drag(px)
	ds.update_callouts()
	return v


static func _refused_drop(ds: DesignSpace, catalog: PartsCatalog, part: String, category: String,
		prefix: String, tag_format: String, value_key: String) -> Array:
	var out: Array = []
	var before: Dictionary = ds.session.selection.duplicate(true)
	var v := _drop_on(ds, part, prefix)
	var trial := DesignSession.from_selection(ds.session, category, part).build(catalog)
	var by: BuildWarning = null
	for w in trial.warnings():
		if PartSwap.HARD_IDS.has(w.id):
			by = w
	var p := ds.warning_pin("w:refused")
	var s := ds.callouts.item("w:refused")
	var case := "refused drop of %s" % part
	out.append(TestResult.new("%s: refused, nothing changes, and a refusal pin is shown" % case,
		String(v.get("kind", "")) == "refused" and ds.session.selection == before and not p.is_empty()
		and String(s.get("kind", "")) == "warning", "%s, pin %s" % [v.get("kind", "-"), not p.is_empty()]))
	if by == null or p.is_empty():
		return out
	var raw: Variant = by.values[value_key]
	var want := tag_format % (raw if raw is String else float(raw))
	out.append(TestResult.new("%s: the tag reads \"%s\" (from the refusing warning's values)" % [case, want],
		String(p["tag"]) == want, "'%s'" % p["tag"]))
	var on := String(p["anchor"])
	out.append(TestResult.new("%s: the pin sits on the %s mount it was dropped on" % [case, category],
		on.begins_with(prefix) and _on_part(ds, s, on), "%s at %s" % [on, s.get("pin")]))
	out.append(TestResult.new("%s: blocking, solid dot, the mount tinted, counted as an issue" % case,
		String(p["severity"]) == WarningPins.BLOCKING and bool(s.get("solid", false)) and ds.tinted_parts().has(on)
		and ds.issues_label.text == WarningPins.count_text(ds.warning_pins.size()) and ds.warning_pins.size() == 3,
		"%s, %s, '%s'" % [p["severity"], ds.tinted_parts(), ds.issues_label.text]))
	out.append(TestResult.new("%s: clicking it shows the refusing warning's full sentence" % case,
		ds.open_warning_at(s.get("pin", Vector2(-1, -1))) and ds.inspector_lines().has(by.message), str(ds.inspector_lines())))
	return out


static func _refusal_clears_on_change(ds: DesignSpace, _catalog: PartsCatalog) -> TestResult:
	_drop_on(ds, "motor_2808_1300kv", "part/motor/")
	var had := not ds.warning_pin("w:refused").is_empty()
	ds.choose("battery", "battery_4s_1300")
	ds.update_callouts()
	return TestResult.new("a refusal pin goes with the next change",
		had and ds.warning_pin("w:refused").is_empty() and ds.callouts.item("w:refused").is_empty(), "had %s" % had)


static func _selecting_closes_warning(ds: DesignSpace) -> TestResult:
	ds.open_warning(["w:pack_sag:battery"])
	var open := ds.warning_open.duplicate()
	ds.select("part/battery")
	return TestResult.new("selecting a part closes the open warning for the part's own page",
		open == ["w:pack_sag:battery"] and ds.warning_open.is_empty() and ds.inspector_lines().size() > 0
		and not ds.inspector_lines().has(String(ds.warning_pin("w:pack_sag:battery")["long"])), str(open))


static func _orbit_tracks(ds: DesignSpace) -> TestResult:
	ds.update_callouts()
	var a: Vector2 = ds.callouts.item("w:pack_sag:battery").get("pin", Vector2.ZERO)
	ds.rig.goal_yaw += deg_to_rad(70.0)
	ds.rig.snap()
	ds._update_callouts_if_moved()
	var s := ds.callouts.item("w:pack_sag:battery")
	return TestResult.new("the sag pin follows the battery as the camera orbits (frame loop relays out)",
		not s.is_empty() and (s["pin"] as Vector2).distance_to(a) > 4.0 and _on_part(ds, s, "part/battery"),
		"%s -> %s" % [a, s.get("pin")])


# ---------------------------------------------------------------------------
# Geometry: warning labels obey the callouts' rules, judged on test-owned geometry
# ---------------------------------------------------------------------------

static func _geometry_state(ds: DesignSpace, g: String) -> void:
	match g:
		"cannot hover":
			ds.choose("propeller", "prop_16x12x4")
		"no battery":
			ds.select("part/battery")
			ds.remove_selected()
		"refused drop":
			_drop_on(ds, "motor_2808_1300kv", "part/motor/")
	ds.go_home()
	ds.rig.snap_home()
	ds.update_callouts()


static func _geometry(ds: DesignSpace, case: String) -> Array:
	var out: Array = []
	var shown: Array = ds.callouts.shown
	var warns: Array = shown.filter(func(s): return String(s.get("kind", "")) == "warning")
	var want := ds.warning_pins.size()
	out.append(TestResult.new("%s: every warning pin is placed" % case, want > 0 and warns.size() == want,
		"%d of %d" % [warns.size(), want]))
	var bad := ""
	# With one label on screen (no battery: no callouts, one pin) label/label and leader/leader
	# cannot fail, so they are only asked where there are others.
	var alone := shown.size() < 2
	if not alone:
		for w in warns:
			for s in shown:
				if s != w and (w["rect"] as Rect2).intersects(s["rect"] as Rect2):
					bad = "%s over %s" % [w["id"], s["id"]]
		out.append(TestResult.new("%s: no warning label covers another label" % case, bad == "" and not warns.is_empty(), bad))
	bad = ""
	for w in warns:
		for poly in TestCallouts._true_silhouette(ds):
			if not Geometry2D.intersect_polygons(TestCallouts._rect_poly(w["rect"]), poly).is_empty():
				bad = "%s over the drone" % w["id"]
	out.append(TestResult.new("%s: no warning label covers the drone's silhouette" % case,
		bad == "" and not warns.is_empty(), bad))
	bad = ""
	var ui := TestCallouts._ui_rects(ds)
	var screen := Rect2(Vector2.ZERO, ds.size)
	for w in warns:
		if not screen.encloses(w["rect"] as Rect2):
			bad = "%s off screen" % w["id"]
		for k in ui:
			if (w["rect"] as Rect2).intersects(ui[k] as Rect2):
				bad = "%s over the %s" % [w["id"], k]
	out.append(TestResult.new("%s: no warning label covers a panel or leaves the screen" % case,
		bad == "" and not warns.is_empty(), bad))
	bad = ""
	if not alone:
		for w in warns:
			for s in shown:
				if s != w and Callouts.leaders_cross(w["pin"], w["end"], s["pin"], s["end"]):
					bad = "%s crosses %s" % [w["id"], s["id"]]
		out.append(TestResult.new("%s: no warning leader crosses another leader" % case, bad == "" and not warns.is_empty(), bad))
	return out


# ---------------------------------------------------------------------------
# Data: every warning kind WarningRows knows
# ---------------------------------------------------------------------------

static func _data_per_kind(ds: DesignSpace) -> Array:
	var out: Array = []
	var have := ds.picks.addresses()
	for id in WarningRows.TABLE:
		var w := BuildWarning.limiting(id, "sentence", {})
		var p := WarningPins.of_warning(w, null)
		var words := String(p["tag"]).split(" · ")[0].split(" ", false).size()
		out.append(TestResult.new("data %s: a 1-4 word tag, a drawn 5\" anchor, a slot, a readout key" % id,
			words >= 1 and words <= 4 and have.has(String(p["anchor"])) and String(p["slot"]) != ""
			and (String(p["readout"]) == "" or READOUT_KEYS.has(String(p["readout"])))
			and WarningPins.ROW_ANCHOR.has(w.item) and String(p["long"]) == "sentence",
			"tag '%s', anchor %s, slot '%s', readout '%s', item %s" % [p["tag"], p["anchor"], p["slot"], p["readout"], w.item]))
	return out


static func _esc_current_cap_on_stack() -> TestResult:
	var w := BuildWarning.limiting(&"current_limit", "x", {"limited_by": "esc", "throttle_cap": 0.8})
	var p := WarningPins.of_warning(w, null)
	return TestResult.new("an ESC current cap sits on the stack and reads \"Current cap · 80% throttle\"",
		String(p["anchor"]) == "part/stack" and String(p["slot"]) == "esc" and String(p["tag"]) == "Current cap · 80% throttle",
		"%s %s '%s'" % [p["anchor"], p["slot"], p["tag"]])


static func _impossible_is_blocking() -> TestResult:
	var a := WarningPins.of_warning(BuildWarning.impossible(&"connector_mismatch", "x", {}), null)
	var b := WarningPins.of_warning(BuildWarning.limiting(&"connector_rating", "x", {"sustained_a": 12.0}), null)
	return TestResult.new("IMPOSSIBLE is blocking and tints; LIMITING is a caution and does not",
		a["severity"] == WarningPins.BLOCKING and a["tint"] and b["severity"] == WarningPins.CAUTION and not b["tint"],
		"%s %s / %s %s" % [a["severity"], a["tint"], b["severity"], b["tint"]])


static func _count_text() -> TestResult:
	return TestResult.new("the count reads \"\", \"1 issue\", \"3 issues\"",
		WarningPins.count_text(0) == "" and WarningPins.count_text(1) == "1 issue" and WarningPins.count_text(3) == "3 issues",
		"%s|%s|%s" % [WarningPins.count_text(0), WarningPins.count_text(1), WarningPins.count_text(3)])
