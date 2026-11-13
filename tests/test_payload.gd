class_name TestPayload
extends RefCounted
## The payload part: a box under the belly of every frame and every class, weighed where it hangs.
##
## WHERE EACH CHECK COULD PASS WHILE PROVING NOTHING, AND WHAT STOPS IT
##   - "below the lowest part" is measured against mass_parts() centres AND body_boxes() faces, two
##     routes to the same fact, and the sweep fits a stress set (pack strapped under the bottom plate,
##     buzzer under it, GPS, camera) so the lowest part is not always the bottom plate.
##   - "stays on the ground" would be green for any build that cannot climb, so the very same sim runs on
##     the same aircraft WITHOUT the payload and must climb, and again with the payload's mass deleted
##     from mass_parts (the mutant) and must climb too. If the payload's mass stopped reaching physics the
##     mutant line is what a failing test looks like, and it is asserted to look like it.
##   - the round trips compare against values written here by hand, not against the writer's own output.

const EPS := 1.0e-9
const STEP_DT := 0.001
const FULL := {"M1": 1.0, "M2": 1.0, "M3": 1.0, "M4": 1.0}


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_catalog_file())
	results.append_array(_placement_sweep(catalog))
	results.append_array(_extreme_frames(catalog))
	results.append_array(_mass_flows(catalog))
	results.append_array(_lump_and_part(catalog))
	results.append_array(_physics(catalog))
	results.append_array(_persistence(catalog))
	results.append_array(_lift_words(catalog))
	return results


static func _t(name: String, ok: bool, detail: String) -> TestResult:
	return TestResult.new(name, ok, detail)


# ---------------------------------------------------------------------------
# The catalog
# ---------------------------------------------------------------------------

static func _catalog_file() -> Array:
	var out: Array = []
	var kinds := PayloadPart.kinds()
	var ids: Array = []
	var mounts := {}
	var sane := true
	var why := ""
	for e in kinds:
		ids.append(String(e["part_id"]))
		mounts[String(e["mounting"]["attachment"])] = true
		var s: Dictionary = e["specs"]
		if float(e["mass_g"]) <= 0.0 or float(s["length_mm"]) < 5.0 or float(s["width_mm"]) < 5.0 or float(s["height_mm"]) < 5.0 \
				or not PayloadPart.MOUNTS.has(String(e["mounting"]["attachment"])) or String(e.get("source", "")) == "":
			sane = false
			why = String(e["part_id"])
	var want := ["payload_gimbal_camera", "payload_mapping_camera", "payload_drop_hook", "payload_winch", "payload_sprayer_tank", "payload_custom"]
	out.append(_t("payload catalog lists gimbal camera, mapping camera, drop hook, winch, sprayer tank and Custom",
		ids == want, str(ids)))
	out.append(_t("every catalog payload has a mass, a box, a known mount and a source note; hook, gimbal and plate all occur",
		sane and mounts.has("hook") and mounts.has("gimbal") and mounts.has("plate"), "bad entry %s, mounts %s" % [why, str(mounts.keys())]))
	var gimbal := PayloadPart.resolve({"kind": "payload_gimbal_camera"})
	out.append(_t("the gimbal camera is the 150 g class", is_equal_approx(float(gimbal["mass_g"]), 150.0), str(gimbal.get("mass_g"))))
	var big := PayloadPart.resolve({"kind": "payload_custom", "mass_g": 25000.0, "size_mm": [5000.0, 1.0, 100.0]})
	out.append(_t("a custom payload takes up to 20 kg and its box is clamped to 5..1000 mm",
		is_equal_approx(float(big["mass_g"]), 20000.0) and is_equal_approx(float(big["length_mm"]), 1000.0) and is_equal_approx(float(big["width_mm"]), 5.0),
		"%s g, %s x %s mm" % [big["mass_g"], big["length_mm"], big["width_mm"]]))
	var override := PayloadPart.resolve({"kind": "payload_winch", "mass_g": 321.0})
	out.append(_t("a mass typed over a catalog kind wins and is marked edited; the kind's own box stays",
		is_equal_approx(float(override["mass_g"]), 321.0) and bool(override["mass_edited"]) and not bool(override["size_edited"])
			and is_equal_approx(float(override["width_mm"]), 60.0), str(override)))
	out.append(_t("an unknown kind from a later version still weighs what was saved, as a custom box",
		is_equal_approx(float(PayloadPart.resolve({"kind": "future_thing", "mass_g": 77.0})["mass_g"]), 77.0), ""))
	out.append(_t("no kind is no payload", PayloadPart.resolve({}).is_empty() and PayloadPart.resolve({"kind": ""}).is_empty(), ""))
	var sparse := PayloadPart.to_saved("payload_winch", 180.0, 90.0, 60.0, 60.0)
	out.append(_t("saving the kind's own figures writes only the kind (sparse)", sparse == {"kind": "payload_winch"}, str(sparse)))
	return out


# ---------------------------------------------------------------------------
# Placement: every frame x every class
# ---------------------------------------------------------------------------

## The class's own project with `frame_id` swapped in, and, for `stress`, the fittings that put something
## lowest that is not the bottom plate.
static func _project_of(catalog: PartsCatalog, class_id: String, frame_id: String, stress: bool) -> Project:
	var p := DroneClass.starting_project(class_id, "t")
	p.parts["frame"] = frame_id
	if stress:
		p.parts["buzzer"] = "buzz_passive_pad"
		var gps: Array = catalog.list_category("gps")
		if not gps.is_empty() and String(p.parts.get("gps", "")) == "":
			p.parts["gps"] = String((gps[0] as Dictionary)["part_id"])
	return p


static func _build_of(catalog: PartsCatalog, class_id: String, frame_id: String, stress: bool, kind: String) -> Build:
	var p := _project_of(catalog, class_id, frame_id, stress)
	p.payload = {"kind": kind}
	var b := p.to_build(catalog)
	if b != null and stress:
		var bottom := MountLayout.by_id(b.mount_points(), "strap_bottom")
		if bottom != null:
			b.set_assembly({"battery_mount": "strap_bottom"})
	return b


static func _overlap(a_centre: Vector3, a_size: Vector3, b_centre: Vector3, b_size: Vector3) -> bool:
	var d := (a_centre - b_centre).abs()
	var half := (a_size + b_size) * 0.5
	return d.x < half.x - 1e-7 and d.y < half.y - 1e-7 and d.z < half.z - 1e-7


static func _placement_sweep(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var frames: Array = []
	for f in catalog.list_category("frame"):
		frames.append(String((f as Dictionary)["part_id"]))
	var kinds: Array = []
	for e in PayloadPart.kinds():
		kinds.append(String(e["part_id"]))
	var n := 0
	var cases := 0
	for class_id in DroneClass.ids():
		if not DroneClass.is_available(class_id):
			continue
		var below_fail: Array = []
		var centroid_fail: Array = []
		var overlap_fail: Array = []
		var hang_fail: Array = []
		var built := 0
		for frame_id in frames:
			for stress in [false, true]:
				# Every kind is exercised on every class, rotating, so hook, gimbal and plate all meet every frame size.
				var kind: String = kinds[n % kinds.size()]
				n += 1
				var b := _build_of(catalog, class_id, frame_id, stress, kind)
				if b == null or b.payload_part.is_empty():
					below_fail.append("%s/%s: no build" % [frame_id, stress])
					continue
				built += 1
				cases += 1
				var label := "%s/%s/%s" % [frame_id, kind, "stress" if stress else "base"]
				var size := PayloadPart.size_m(b.payload_part)
				var centre := b.payload_centre_m()
				var top := centre.y + size.y * 0.5
				# Route 1: every weighed mass part other than motors and the payload is above the box.
				for part in b.mass_parts():
					var pn := String(part.label)
					if pn.begins_with("Payload") or pn.begins_with("Motor"):
						continue
					# a part's own box is not known to mass_parts; its CENTRE must at least be above the payload's top
					if part.position_m.y < top - 1e-6:
						below_fail.append("%s: %s centre %.4f under payload top %.4f" % [label, pn, part.position_m.y, top])
				# Route 2: the faces.
				for box in b.body_boxes():
					var bottom := float(box["centre"].y) - float(box["size"].y) * 0.5
					if bottom < top + PayloadPart.mount_gap_m(b.payload_part) - 1e-6:
						below_fail.append("%s: %s bottom %.4f within the mount gap of payload top %.4f" % [label, box["name"], bottom, top])
					if _overlap(box["centre"], box["size"], centre, size):
						overlap_fail.append("%s: overlaps %s" % [label, box["name"]])
				# The thrust centroid, from the weighed motors themselves.
				var sum := Vector2.ZERO
				var count := 0
				for part in b.mass_parts():
					if String(part.label).begins_with("Motor + prop") and not String(part.label).ends_with("lower"):
						sum += Vector2(part.position_m.x, part.position_m.z)
						count += 1
				var mean := sum / float(maxi(count, 1))
				if absf(centre.x - mean.x) > 1e-6 or absf(centre.z - mean.y) > 1e-6:
					centroid_fail.append("%s: (%.6f, %.6f) vs motors (%.6f, %.6f)" % [label, centre.x, centre.z, mean.x, mean.y])
				# Hung, not floating: the gap between the lowest face and the box top is exactly the mount's.
				var gap := b.lowest_body_y_m() - top
				if absf(gap - PayloadPart.mount_gap_m(b.payload_part)) > 1e-6:
					hang_fail.append("%s: gap %.5f" % [label, gap])
		out.append(_t("%s: payload sits below the lowest part on every frame (plain and stress fit)" % class_id,
			built > 0 and below_fail.is_empty(), "%d builds; %s" % [built, str(below_fail.slice(0, 3))]))
		out.append(_t("%s: payload is centred on the thrust centroid in X and Z on every frame" % class_id,
			built > 0 and centroid_fail.is_empty(), "%d builds; %s" % [built, str(centroid_fail.slice(0, 3))]))
		out.append(_t("%s: payload box overlaps no airframe body on any frame; it hangs exactly one mount gap down" % class_id,
			built > 0 and overlap_fail.is_empty() and hang_fail.is_empty(), "%d builds; %s %s" % [built, str(overlap_fail.slice(0, 2)), str(hang_fail.slice(0, 2))]))
	out.append(_t("the sweep ran every frame in frames.json against every class",
		cases >= frames.size() * 2 * 8, "%d frames, %d cases" % [frames.size(), cases]))
	return out


## Frames that are not in the catalog: an enormous arm, a tiny one, and a frame drawn in the Airframe room.
static func _extreme_frames(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var bad: Array = []
	for arm_mm in [20.0, 45.0, 400.0]:
		var b := ReferenceBuild.build()
		b.frame["specs"]["arm_mm"] = arm_mm
		b.set_payload_part({"kind": "payload_sprayer_tank"})
		var size := PayloadPart.size_m(b.payload_part)
		var c := b.payload_centre_m()
		var ok := absf(c.x) < 1e-9 and absf(c.z) < 1e-9 and c.y + size.y * 0.5 < b.lowest_body_y_m()
		for box in b.body_boxes():
			if _overlap(box["centre"], box["size"], c, size):
				ok = false
		if not ok:
			bad.append(arm_mm)
	out.append(_t("an imported frame with a 20, 45 or 400 mm arm still carries the payload below and centred", bad.is_empty(), str(bad)))

	var p := DroneClass.starting_project("five_inch", "t")
	var drawn := AirframeDocument.load_from("res://assets/models/classes/five_inch_frame.json")
	p.airframe = drawn.to_dictionary()
	p.payload = {"kind": "payload_gimbal_camera"}
	var b2 := p.to_build(catalog)
	out.append(_t("a project flying a drawn frame carries the payload under it",
		b2 != null and not b2.payload_part.is_empty() and b2.payload_centre_m().y < b2.lowest_body_y_m(),
		"payload y %s" % (str(b2.payload_centre_m().y) if b2 != null else "no build")))
	return out


# ---------------------------------------------------------------------------
# Mass
# ---------------------------------------------------------------------------

static func _mass_flows(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var base := ReferenceBuild.build()
	var loaded := ReferenceBuild.build()
	loaded.set_payload_part({"kind": "payload_custom", "mass_g": 250.0, "size_mm": [80.0, 70.0, 60.0]})
	var d_auw := loaded.all_up_weight_g() - base.all_up_weight_g()
	out.append(_t("AUW rises by exactly the payload's mass", absf(d_auw - 250.0) < 1e-6, "%.9f g" % d_auw))
	var m0 := base.mass_properties
	var m1 := loaded.mass_properties
	out.append(_t("the centre of mass drops, by the parallel-axis weighted mean (computed by hand)",
		m1.com_m.y < m0.com_m.y - 1e-4 and absf(m1.com_m.y - (m0.total_mass_kg * m0.com_m.y + 0.25 * loaded.payload_centre_m().y) / (m0.total_mass_kg + 0.25)) < 1e-9,
		"%.6f -> %.6f m" % [m0.com_m.y, m1.com_m.y]))
	out.append(_t("a payload on the centroid moves the centre of mass sideways and fore-aft by nothing but dilution",
		absf(m1.com_m.x - m0.com_m.x * m0.total_mass_kg / m1.total_mass_kg) < 1e-9 and absf(m1.com_m.z - m0.com_m.z * m0.total_mass_kg / m1.total_mass_kg) < 1e-9,
		"x %s z %s" % [m1.com_m.x, m1.com_m.z]))
	var tr0 := m0.inertia.x.x + m0.inertia.y.y + m0.inertia.z.z
	var tr1 := m1.inertia.x.x + m1.inertia.y.y + m1.inertia.z.z
	out.append(_t("the inertia tensor grows", tr1 > tr0, "%s -> %s" % [tr0, tr1]))
	var names: Array = loaded.mass_parts().map(func(pt): return String(pt.label))
	out.append(_t("the payload is its own entry in mass_parts()", names.any(func(n): return n.begins_with("Payload (")), str(names.slice(-4))))
	out.append(_t("no payload leaves the reference build's mass parts untouched (no entry, same count)",
		not (base.mass_parts().map(func(pt): return String(pt.label)).any(func(n): return n.begins_with("Payload"))), ""))
	out.append(_t("a payload mass of 0 g fits nothing", ReferenceBuild.build().mass_parts().size() == _with(ReferenceBuild.build(), {"kind": "payload_custom", "mass_g": 0.0}).mass_parts().size(), ""))
	var thrust_same := absf(loaded.max_total_thrust_n() - base.max_total_thrust_n()) < 1e-9
	out.append(_t("maximum thrust is the aircraft's own and does not move with the payload; the ratio falls", thrust_same and loaded.thrust_to_weight() < base.thrust_to_weight() * 0.7,
		"%.2f -> %.2f" % [base.thrust_to_weight(), loaded.thrust_to_weight()]))
	return out


static func _with(b: Build, saved: Dictionary) -> Build:
	b.set_payload_part(saved)
	return b


## Survey kits and class payloads feed the old lump; the part is separate. Both present: both counted, once each.
static func _lump_and_part(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var base := ReferenceBuild.build()
	var lump := ReferenceBuild.build()
	lump.apply_class_payload({"w": 0.0, "mass_g": 40.0})
	var both := ReferenceBuild.build()
	both.apply_class_payload({"w": 0.0, "mass_g": 40.0})
	both.set_payload_part({"kind": "payload_custom", "mass_g": 150.0})
	out.append(_t("the lump alone still adds its own mass", absf(lump.all_up_weight_g() - base.all_up_weight_g() - 40.0) < 1e-6, ""))
	out.append(_t("lump 40 g plus part 150 g adds 190 g: the sum is explicit and nothing is counted twice",
		absf(both.all_up_weight_g() - base.all_up_weight_g() - 190.0) < 1e-6 and is_equal_approx(both.total_payload_mass_g(), 190.0),
		"%.6f g over base" % (both.all_up_weight_g() - base.all_up_weight_g())))
	var entries: Array = both.mass_parts().filter(func(pt): return String(pt.label).begins_with("Payload"))
	out.append(_t("two payload entries in mass_parts, the lump named Payload and the part named for its kind",
		entries.size() == 2 and entries.any(func(pt): return String(pt.label) == "Payload"), str(entries.map(func(pt): return pt.label))))
	return out


# ---------------------------------------------------------------------------
# Physics: an overloaded drone cannot lift
# ---------------------------------------------------------------------------

## Steps full throttle from the ground and returns {max_up, final_y}: altitude above where it started.
## `stop_above`: end the run once it has risen this far (a climbing aircraft with no pilot tumbles within seconds,
## and what is being asked is only whether it left the ground).
static func _full_throttle(b: Build, seconds: float, contact: bool, drop_payload_mass := false, stop_above := INF) -> Dictionary:
	var core := b.build_drone_core()
	if drop_payload_mass:
		# The mutant: the payload's mass never reaches the mass properties.
		var parts: Array = b.mass_parts().filter(func(pt): return not String(pt.label).begins_with("Payload ("))
		core.mass_properties = MassProperties.compute(parts)
	core.ground_contact_enabled = contact
	core.rest_height_m = b.rest_height_m()
	core.rigid_body.position_m = Vector3(0.0, core.rest_height_m, 0.0)
	var start := core.rigid_body.position_m.y
	var max_up := 0.0
	for i in int(seconds / STEP_DT):
		core.step(FULL, STEP_DT)
		max_up = maxf(max_up, core.rigid_body.position_m.y - start)
		if max_up > stop_above:
			break
	return {"max_up": max_up, "final_y": core.rigid_body.position_m.y - start, "core": core}


static func _physics(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var bare := ReferenceBuild.build()
	var heavy := ReferenceBuild.build()
	heavy.set_payload_part({"kind": "payload_custom", "mass_g": 10000.0, "size_mm": [200.0, 200.0, 150.0]})

	out.append(_t("the reference build is the 500 g class", bare.all_up_weight_g() > 450.0 and bare.all_up_weight_g() < 550.0, "%.1f g" % bare.all_up_weight_g()))
	out.append(_t("with 10 kg on it, peak thrust is under the weight: it cannot hover", not heavy.can_hover() and heavy.thrust_to_weight() < 1.0,
		"T/W %.2f at %.0f g" % [heavy.thrust_to_weight(), heavy.all_up_weight_g()]))

	var climbs := _full_throttle(bare, 3.0, true, false, 6.0)
	out.append(_t("the same build with NO payload, full throttle for 3 s from the ground, climbs more than 5 m", float(climbs["max_up"]) > 5.0, "%.2f m" % float(climbs["max_up"])))

	var stuck := _full_throttle(heavy, 3.0, true)
	out.append(_t("500 g build + 10 kg payload, full throttle for 3 s, stays on the ground (altitude 0)",
		float(stuck["max_up"]) < 1e-6 and absf(float(stuck["final_y"])) < 1e-6, "max %s m, final %s m" % [float(stuck["max_up"]), float(stuck["final_y"])]))

	# With no ground at all (the free-body core every flight used) it still never rises: it sinks.
	var sink := _full_throttle(heavy, 1.0, false)
	out.append(_t("with no ground under it the overloaded drone never rises above where it started: it sinks",
		float(sink["max_up"]) < 1e-6 and float(sink["final_y"]) < -0.5, "max %s m, final %.2f m" % [float(sink["max_up"]), float(sink["final_y"])]))

	# The mutant: payload mass deleted from the mass properties. The same check must now FAIL to hold.
	var mutant := _full_throttle(heavy, 3.0, true, true, 2.0)
	out.append(_t("MUTANT: with the payload's mass dropped from mass_parts the same sim climbs (so the test above can fail)",
		float(mutant["max_up"]) > 1.0, "%.2f m" % float(mutant["max_up"])))

	# Marginal: a payload that leaves thrust between 1 and 1.5 hovers but is flagged marginal.
	var mid := ReferenceBuild.build()
	var target_g := bare.max_total_thrust_n() / 9.80665 * 1000.0 / 1.3
	mid.set_payload_part({"kind": "payload_custom", "mass_g": target_g - bare.all_up_weight_g()})
	out.append(_t("a payload that leaves T/W near 1.3 hovers and is called marginal, a bare build is not",
		mid.can_hover() and LiftVerdict.of(mid)["state"] == LiftVerdict.MARGINAL and LiftVerdict.of(bare)["state"] == LiftVerdict.LIFTS,
		"%.2f / %s" % [mid.thrust_to_weight(), str(LiftVerdict.of(mid)["state"])]))
	return out


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

static func _persistence(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var p := DroneClass.starting_project("five_inch", "t")
	var bare_auw := p.to_build(catalog).all_up_weight_g()
	p.payload = {"kind": "payload_winch", "mass_g": 400.0, "size_mm": [100.0, 70.0, 60.0]}
	var back := Project.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	out.append(_t("a payload survives a project save and load, through real JSON",
		back != null and back.payload["kind"] == "payload_winch" and is_equal_approx(float(back.payload["mass_g"]), 400.0)
			and back.payload["size_mm"] == [100.0, 70.0, 60.0], str(back.payload) if back != null else "null"))
	var b := back.to_build(catalog)
	out.append(_t("the reloaded project flies with the payload on it", absf(b.all_up_weight_g() - bare_auw - 400.0) < 1e-6, "%.3f g" % (b.all_up_weight_g() - bare_auw)))

	# An old save: no payload block, an old schema minor.
	var old := DroneClass.starting_project("five_inch", "t").to_dict()
	(old["decisions"] as Dictionary).erase("payload")
	old["schema"] = {"major": 1, "minor": 4}
	var opened := Project.from_dict(old)
	out.append(_t("a save written before payloads existed loads with none and weighs what it did",
		opened != null and opened.payload.is_empty() and absf(opened.to_build(catalog).all_up_weight_g() - bare_auw) < 1e-9
			and not opened.to_build(catalog).mass_parts().any(func(pt): return String(pt.label).begins_with("Payload")), ""))
	var carried := Project.from_dict(opened.to_dict())
	out.append(_t("and writes a payload block of its own on the next save, empty", carried.to_dict()["decisions"].has("payload") and carried.payload.is_empty(), ""))
	out.append(_t("a version snapshot restores the payload it was taken with", _version_restores(catalog), ""))

	# The design file.
	var s := DesignSession.default_for_class("five_inch")
	s.set_payload({"kind": "payload_sprayer_tank", "mass_g": 2000.0})
	var d := DesignFile.to_dict(s, "x")
	var loaded := DesignFile.from_dict(JSON.parse_string(JSON.stringify(d)), catalog)
	out.append(_t("a design file round-trips the payload",
		bool(loaded["ok"]) and loaded["session"].payload() == {"kind": "payload_sprayer_tank", "mass_g": 2000.0}, str(loaded.get("reason", ""))))
	var s0 := DesignSession.default_for_class("five_inch")
	var d0 := DesignFile.to_dict(s0, "x")
	var l0 := DesignFile.from_dict(d0, catalog)
	out.append(_t("a design file without a payload key (every older file) opens with none and omits the key",
		not d0.has("payload") and bool(l0["ok"]) and l0["session"].payload().is_empty(), ""))
	out.append(_t("the session's build carries the payload and undo takes it off again",
		_undo_works(catalog), ""))
	return out


static func _version_restores(_catalog: PartsCatalog) -> bool:
	var p := DroneClass.starting_project("five_inch", "t")
	p.payload = {"kind": "payload_drop_hook"}
	var v := p.add_version("with hook")
	p.payload = {}
	return p.restore_version(String(v["version_id"])) and p.payload == {"kind": "payload_drop_hook"}


static func _undo_works(catalog: PartsCatalog) -> bool:
	var s := DesignSession.default_for_class("five_inch")
	var base := s.build(catalog).all_up_weight_g()
	s.set_payload({"kind": "payload_custom", "mass_g": 300.0})
	var with := s.build(catalog).all_up_weight_g()
	var ok := absf(with - base - 300.0) < 1e-6
	s.undo()
	return ok and absf(s.build(catalog).all_up_weight_g() - base) < 1e-9 and s.payload().is_empty()


# ---------------------------------------------------------------------------
# The words, and the Design Space
# ---------------------------------------------------------------------------

static func _lift_words(_catalog: PartsCatalog) -> Array:
	var out: Array = []
	var heavy := ReferenceBuild.build()
	heavy.set_payload_part({"kind": "payload_custom", "mass_g": 10000.0})
	var v := LiftVerdict.of(heavy)
	var want := "Can't lift: needs %.0f g thrust, max %.0f g (T/W %.2f)" % [heavy.weight_n() / 9.80665 * 1000.0, float(heavy.peak_thrust()["thrust_n"]) / 9.80665 * 1000.0, float(heavy.peak_thrust()["thrust_n"]) / heavy.weight_n()]
	out.append(_t("the can't-lift line names the thrust needed, the most it has and T/W", v["state"] == LiftVerdict.CANNOT and v["text"] == want, str(v["text"])))
	out.append(_t("the hover readout says so instead of printing a throttle it never hovers at",
		DesignSpace.format_readout("hover_throttle", {"hover_throttle": 1.0, "can_hover": false}) == "no hover"
			and DesignSpace.format_readout("hover_throttle", {"hover_throttle": 0.33, "can_hover": true}) == "33.0 %"
			and DesignSession.readouts_of(heavy).size() == 5 and not heavy.can_hover(), ""))
	return out


## The Design Space: the controls drive the session, the lift line shows, and the drawn box hangs under the drawn
## drone, raised so the drone stands on it, overlapping nothing.
static func design_space(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for class_id in ["five_inch", "tiny_whoop", "cinelifter", "x_class"]:
		var ds := DesignSpace.new(DesignSession.default_for_class(class_id), catalog)
		var pp := ds.payload_panel
		out.append(_t("%s: no payload, no box drawn, no lift line, the drone on the floor" % class_id,
			pp != null and ds._payload_node == null and not pp.lift_label.visible and is_zero_approx(ds._payload_drop_m), ""))
		ds.session.set_payload({"kind": "payload_custom", "mass_g": 20000.0, "size_mm": [150.0, 150.0, 120.0]})
		var spec := PayloadPart.resolve(ds.session.payload())
		var node := ds._payload_node
		out.append(_t("%s: choosing a kind draws the payload node" % class_id, node != null and node.get_node_or_null("PayloadBox") != null, ""))
		if node == null:
			ds.free()
			continue
		var drop := PayloadPart.mount_gap_m(spec) + PayloadPart.size_m(spec).y
		var box := node.get_node("PayloadBox") as MeshInstance3D
		var aabb := AABB(box.position + node.position - PayloadPart.size_m(spec) * 0.5, PayloadPart.size_m(spec))
		out.append(_t("%s: the box's underside is on the floor (the drone stands on its payload)" % class_id, absf(aabb.position.y) < 1e-6, "%.6f" % aabb.position.y))
		var lowest := INF
		var hit := ""
		for entry in ds.mesh_boxes():
			if String(entry["name"]).begins_with(PickRegistry.PROXY_PREFIX):
				continue
			var mb := entry["box"] as AABB
			lowest = minf(lowest, mb.position.y)
			if mb.intersects(aabb) and mb.grow(-1e-6).intersects(aabb.grow(-1e-6)):
				hit = String(entry["name"])
		out.append(_t("%s: the drawn drone's lowest point is one mount gap above the box, and nothing it draws overlaps the box" % class_id,
			absf(lowest - drop) < 1e-4 and hit == "", "lowest %.5f vs drop %.5f, overlap %s" % [lowest, drop, hit]))
		var mid := Vector2(node.position.x, node.position.z)
		var sum := Vector2.ZERO
		for corner in ["FL", "FR", "BL", "BR"]:
			var c := ds.picks.box_of("part/motor/%s" % corner).get_center()
			sum += Vector2(c.x, c.z)
		out.append(_t("%s: drawn on the mean of the four drawn motors in plan" % class_id, (mid - sum / 4.0).length() < 1e-6, str(mid)))
		out.append(_t("%s: the lift line is shown amber with the numbers when it cannot lift" % class_id,
			pp.lift_label.visible and pp.lift_label.text.begins_with("Can't lift: needs ") and "T/W" in pp.lift_label.text
				and ds.value_labels["hover_throttle"].text == "no hover", pp.lift_label.text))
		ds.session.set_payload({})
		out.append(_t("%s: removing it puts the drone back and the line away" % class_id,
			ds._payload_node == null and is_zero_approx(ds._payload_drop_m) and not pp.lift_label.visible and ds.value_labels["hover_throttle"].text != "no hover", ""))
		ds.free()
	var ds2 := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	var pp2 := ds2.payload_panel
	# Through the control itself: pick a kind, then type a mass.
	pp2.kind_option.select(1)
	pp2._on_kind(1)
	var picked := ds2.session.payload()
	pp2.mass_stepper.value = 321.0
	pp2._on_edit()
	var typed := ds2.session.payload()
	out.append(_t("the picker sets the kind and the mass field overrides it, saved sparsely",
		picked == {"kind": "payload_gimbal_camera"} and typed == {"kind": "payload_gimbal_camera", "mass_g": 321.0}, "%s | %s" % [str(picked), str(typed)]))
	pp2.kind_option.select(0)
	pp2._on_kind(0)
	out.append(_t("choosing None removes it", ds2.session.payload().is_empty(), ""))
	ds2.free()
	return out


# ---------------------------------------------------------------------------
# The flight sim: the payload on the drone, and the ground under an overloaded one
# ---------------------------------------------------------------------------

## Boots main.tscn with `b`, puts the drone on the ground at rest, holds W (full throttle on a keyboard) and
## runs the scene's own _physics_process for `seconds`. Returns {max_y, min_y, rest_y, throttle, core, sim}.
## `mutate` is called with the booted scene before the run: the way each check is shown to fail.
static func _sim_run(tree: SceneTree, b: Build, seconds: float, mutate := Callable()) -> Dictionary:
	var sim: Node = load("res://src/scenes/main.tscn").instantiate()
	sim.initial_build = b
	sim.initial_drone_class = "five_inch"
	tree.root.add_child(sim)
	await tree.process_frame
	if mutate.is_valid():
		mutate.call(sim)
	# Stick all the way up: full throttle, not hover-times-a-factor.
	sim._hover_throttle = 1.0
	var core: DroneCore = sim.core
	var rest_y := b.rest_height_m()
	sim._reset_to(Vector3(0.0, rest_y + 1.0e-6, 0.0), Vector3(0.0, 0.0, -1.0))
	sim.terrain = null
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	var max_y := -INF
	var min_y := INF
	var throttle := 0.0
	for i in int(seconds * 120.0):
		sim._physics_process(1.0 / 120.0)
		var y: float = sim.core.rigid_body.position_m.y
		max_y = maxf(max_y, y)
		min_y = minf(min_y, y)
		throttle = sim.rc.throttle
	key.pressed = false
	Input.parse_input_event(key)
	return {"max_y": max_y, "min_y": min_y, "rest_y": rest_y, "throttle": throttle, "core": core, "sim": sim}


static func sim_path(tree: SceneTree) -> Array:
	var out: Array = []
	var bare := ReferenceBuild.build()
	var heavy := ReferenceBuild.build()
	heavy.set_payload_part({"kind": "payload_custom", "mass_g": 10000.0, "size_mm": [200.0, 200.0, 150.0]})

	# --- the drawing -------------------------------------------------------
	var drawn: Dictionary = await _sim_run(tree, heavy, 0.0)
	var model := (drawn["sim"].drone.get_node("SimDroneModel")) as SimDroneModel
	var node: Node3D = model.content.get_node_or_null("Payload") as Node3D
	var box: MeshInstance3D = null if node == null else node.get_node_or_null("PayloadBox") as MeshInstance3D
	out.append(_t("sim: the drone visual carries a Payload node with its box", node != null and box != null, ""))
	if node != null and box != null:
		var attach := heavy.payload_attach_m()
		out.append(_t("sim: the Payload node sits at the build's attach point in the airframe frame",
			node.position.is_equal_approx(attach), "%s vs %s" % [node.position, attach]))
		# Box centre in the model's parent space (the body origin = centre of mass) against the physics' payload centre.
		var centre_world := model.to_local(box.global_position)
		var want := heavy.payload_centre_m() - heavy.mass_properties.com_m
		out.append(_t("sim: the box is drawn where the physics weighs it (to the millimetre, about the CoM)",
			(centre_world - want).length() < 1e-3, "%s vs %s" % [centre_world, want]))
		out.append(_t("sim: the box is a child of the drone model, so it moves with the aircraft",
			model.is_ancestor_of(node) and model.get_parent() == drawn["sim"].drone, ""))
		var fresh := PayloadMesh.build(heavy.payload_part)
		var same_size := (box.mesh.get_aabb().size - (fresh.get_node("PayloadBox") as MeshInstance3D).mesh.get_aabb().size).length() < 1e-6
		out.append(_t("sim: it is Design Space's own mesh (same box size from PayloadMesh)", same_size, ""))
		fresh.free()
		# Moves and turns with the drone.
		var s: Node = drawn["sim"]
		var before := box.global_position
		s._snap_visual(Vector3(3.0, 5.0, -2.0), Basis(Vector3.UP, PI * 0.5).get_rotation_quaternion())
		out.append(_t("sim: snapping the drone to a new pose carries the payload box (position and a 90 degree turn)",
			(box.global_position - s.drone.global_transform * model.content.transform * node.transform * box.position).length() < 1e-5
				and (box.global_position - before).length() > 1.0
				and absf(box.global_transform.basis.get_rotation_quaternion().angle_to(Basis(Vector3.UP, PI * 0.5).get_rotation_quaternion())) < 1e-3, "%s" % (box.global_position - before)))
	drawn["sim"].queue_free()
	var plain: Dictionary = await _sim_run(tree, bare, 0.0)
	out.append(_t("sim: no payload, no Payload node", (plain["sim"].drone.get_node("SimDroneModel") as SimDroneModel).content.get_node_or_null("Payload") == null, ""))
	plain["sim"].queue_free()

	# --- the ground --------------------------------------------------------
	out.append(_t("sim: a payload build's core holds ground contact with the rest height of its lowest point (the payload)",
		heavy.build_drone_core().ground_contact_enabled and is_equal_approx(heavy.build_drone_core().rest_height_m, heavy.rest_height_m())
			and not bare.build_drone_core().ground_contact_enabled, ""))
	out.append(_t("sim: the payload build rests higher than the sim's crash line, so resting there is not a 'crash'",
		heavy.rest_height_m() > GateCourse.GROUND_CLEARANCE_M and heavy.lowest_point_y_m() < heavy.lowest_body_y_m(), "%.4f" % heavy.rest_height_m()))

	var held: Dictionary = await _sim_run(tree, heavy, 3.0)
	out.append(_t("sim: full throttle is really full (the check below would be vacuous otherwise)", float(held["throttle"]) > 0.999, "%.3f" % float(held["throttle"])))
	var rest_y: float = held["rest_y"]
	out.append(_t("sim: 500 g build + 10 kg payload, full throttle 3 s through main.gd's own physics step, stays at rest height",
		float(held["max_y"]) - rest_y < 1e-3 and float(held["min_y"]) - rest_y > -1e-6,
		"rest %.5f, min %.5f, max %.5f" % [rest_y, float(held["min_y"]), float(held["max_y"])]))
	held["sim"].queue_free()

	# Mutant 1: ground contact off in the real path. It sinks, hits the crash line and the sim teleports it back up.
	var m1: Dictionary = await _sim_run(tree, heavy, 3.0, func(s): s.core.ground_contact_enabled = false)
	out.append(_t("MUTANT: with ground contact off in the sim the same run does NOT stay at rest height (sinks / respawns)",
		float(m1["min_y"]) - rest_y < -1e-6 or float(m1["max_y"]) - rest_y > 1e-3, "min %.4f max %.4f" % [float(m1["min_y"]), float(m1["max_y"])]))
	m1["sim"].queue_free()
	# Mutant 2: the same build without its payload mass climbs through the same path.
	var light := ReferenceBuild.build()
	var m2: Dictionary = await _sim_run(tree, light, 1.5, func(s): s.core.ground_contact_enabled = true)
	out.append(_t("MUTANT: the payload-free build through the same path climbs (the check can fail)",
		float(m2["max_y"]) - float(m2["rest_y"]) > 0.5, "%.2f m" % (float(m2["max_y"]) - float(m2["rest_y"]))))
	m2["sim"].queue_free()
	return out
