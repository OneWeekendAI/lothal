class_name TestBmpClasses
extends RefCounted
## Battery, Motor and Prop flows on EVERY class in the picker (tracker:
## landingpage/docs/lothal/plans/2026-11-09-bmp-all-classes.md). Each class x section x check is
## its own TestResult, so a failure counts once and names the class that failed.
##
## ## The checks that could have passed while proving nothing
##
## - "Class-appropriate" is judged by this file's OWN table (CLASS_ENVELOPE, typed from the class
##   picker's "Typical" line), not by anything the class code computes, so a shelf that offers
##   whatever mounts fails the small classes. The class's own seed part is always allowed.
## - Snap points are made HERE from the GLB's own mesh boxes, and the reach edge is a fixed
##   fraction of the drone's own span (REACH_PER_SPAN), so the 6 cm constant tuned to the 5" fails
##   the whoop (too generous) and the X-Class (too stingy).
## - The motor count is counted from the GLB's `motor_*` nodes and compared with the Build's count,
##   so a mount list that stops at four fails the Cinelifter.
## - Readouts must be finite, and must DIFFER after a swap, compared on the five numbers.
## - Everything is written under SCRATCH; the real parts store, designs folder and project library
##   are never named.

## One scratch folder PER PROCESS. A shared folder let two godot runs (the SR suite beside run_tests, or a second terminal)
## wipe each other's designs mid-test: "Could not replace bmp toothpick.lothaldesign" and a script abort in _motor/_prop
## (reproduced 2026-11-11 by starting two runs together; red before this, green after).
static var SCRATCH := "user://test_bmp_%d" % OS.get_process_id()
const SIZE := Vector2(1280, 720)
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
## cells lo..hi and prop inches lo..hi, from the picker's typical line (display text in
## DroneClass.CLASSES), typed again here.
const CLASS_ENVELOPE := {
	"tiny_whoop": {"cells": [1, 1], "prop": [1.22, 1.57]},
	"toothpick": {"cells": [1, 2], "prop": [2.0, 2.5]},
	"sub250_35": {"cells": [4, 4], "prop": [3.5, 3.5]},
	"cinewhoop_3": {"cells": [4, 4], "prop": [3.0, 3.0]},
	"four_inch": {"cells": [4, 6], "prop": [4.0, 4.0]},
	"five_inch": {"cells": [4, 6], "prop": [5.0, 5.0]},
	"six_inch": {"cells": [6, 6], "prop": [6.0, 6.0]},
	"seven_lr": {"cells": [6, 6], "prop": [7.0, 7.0]},
	"cinelifter": {"cells": [6, 8], "prop": [8.0, 10.0]},
	# mapper (L4.4): typical line "4S", 9.4" props (typed again from DroneClass: the seed pack is 4S Li-ion despite its id, on the 9.4x5.3 mapper prop).
	"mapper": {"cells": [4, 4], "prop": [9.4, 9.4]},
	"x_class": {"cells": [8, 12], "prop": [10.0, 13.0]},
}
## Classes whose catalog offers NO second class-fit part that mounts, per section. These are catalog
## gaps (no part to invent), listed so the swap check says so instead of passing on nothing; a part
## added to the catalog makes the matching "still a gap" check fail and this table shrink.
## mapper (L4.4) is a gap in props only: one mapper_prop (9.4"), no other 9.4" prop fits. Its motor stopped being a gap 2026-11-10 (class seed is motor_2807_1300kv, mapper_motor_2008 is the second).
const CATALOG_GAPS := {
	"motor": ["tiny_whoop", "toothpick", "cinelifter", "x_class"],
	"propeller": ["tiny_whoop", "cinelifter", "mapper", "x_class"],
}
## L4.4: classes whose GLB is a labelled STAND-IN (a byte copy of another class's), so its drawn motor count (8) is the copy's and not the build's (4).
## The two count checks then assert the mismatch still holds AND the file is still the copy; a real model fails that and the entry must be deleted.
const STAND_IN_MODELS := {"mapper": "cinelifter"}
const PROP_SLACK_IN := 0.5
const MOTOR_TEST_SLACK_IN := 1.0
## The 5" is 0.277 m across and its reach is 6 cm.
const REACH_PER_SPAN := 0.06 / 0.277


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var saved_dir := DesignFile.dir
	_wipe()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH + "/designs"))
	DesignFile.dir = SCRATCH + "/designs"
	for id in DroneClass.ids():
		results.append_array(_battery(id, catalog))
		results.append_array(_motor(id, catalog))
		results.append_array(_prop(id, catalog))
	DesignFile.dir = saved_dir
	_wipe()
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _wipe() -> void:
	var root := ProjectSettings.globalize_path(SCRATCH)
	if DirAccess.dir_exists_absolute(root):
		_rm(root)


static func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path + "/" + sub)
		d.remove(sub)
	DirAccess.remove_absolute(path)


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _space(id: String, catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(id), catalog)
	ds.size = SIZE
	ds.rig.aspect = SIZE.x / SIZE.y
	ds.custom_parts_path = SCRATCH + "/custom.json"
	ds.pack_charge_path = SCRATCH + "/charge.json"
	return ds


static func _done(ds: DesignSpace) -> void:
	for n in ["prop_designer", "motor_designer", "pack_designer"]:
		var d: Variant = ds.get(n)
		if d != null and is_instance_valid(d):
			(d as Node).free()
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()


static func _finite(r: Dictionary) -> bool:
	if r.size() != KEYS.size():
		return false
	for k in KEYS:
		var v := float(r.get(k, NAN))
		if is_nan(v) or is_inf(v):
			return false
	return true


static func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in KEYS:
		if not is_equal_approx(float(a.get(k, 0.0)), float(b.get(k, -1.0))):
			return false
	return true


## The shelf rows of one category that fit (ok), the way the user sees them: slot opened, misfits held back.
static func _shelf_fits(ds: DesignSpace, slot: String, category: String) -> Array:
	ds.shelf.set_open(true)
	ds.open_slot(slot)
	return ds.shelf.rows.filter(func(r): return String(r["category"]) == category and bool(r["ok"]) and String(r["id"]) != "")


static func _seed(id: String, category: String) -> String:
	return String(DroneClass.parts_for(id)[category])


static func _glb_boxes(id: String) -> Dictionary:
	var root: Node = (load(DroneClass.model_path(id)) as PackedScene).instantiate()
	var out := {}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("pick_"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box := xf * mi.get_aabb()
		out[String(mi.name)] = box
		lo = lo.min(box.position)
		hi = hi.max(box.end)
	out["*"] = AABB(lo, hi - lo)
	root.free()
	return out


static func _address(node_name: String) -> String:
	for pre in ["motor_", "prop_"]:
		if node_name.begins_with(pre):
			return "part/%s/%s" % [pre.trim_suffix("_"), node_name.substr(len(pre))]
	return "part/" + node_name


## Another fitted-able part of `category`: the first shelf row that is not fitted and moves the numbers.
static func _alternative(ds: DesignSpace, rows: Array, category: String) -> String:
	var base := ds.session.readouts(ds._catalog)
	var fitted := String(ds.session.selection[category])
	for r in rows:
		var pid := String(r["id"])
		if pid == fitted:
			continue
		var verdict := PartSwap.judge(ds.session, ds._catalog, category, pid, true)
		if verdict["ok"] and not _same(base, verdict["readouts"]):
			return pid
	return ""


## Saves a design to the scratch folder and opens it again; "" when it round-trips.
static func _round_trip(ds: DesignSpace, id: String) -> String:
	var r := DesignFile.save(ds.session, "bmp " + id)
	if not r["ok"]:
		return "save: " + String(r["reason"])
	var back := DesignFile.load_file(String(r["path"]), ds._catalog)
	if not back["ok"]:
		return "load: " + String(back["reason"])
	var s: DesignSession = back["session"]
	if s.drone_class != id or s.selection != ds.session.selection:
		return "selection differs"
	if not _same(s.readouts(ds._catalog), ds.session.readouts(ds._catalog)):
		return "readouts differ"
	return ""


static func _snap_at(ds: DesignSpace, _id: String, part_id: String, node_name: String, boxes: Dictionary) -> Dictionary:
	var map: Dictionary = ds._mount_map
	# Right on the mount's drawn centre: the Cinelifter's coaxial rotors sit a few cm apart.
	var near := Vector3.ZERO
	return PartSnap.resolve(ds.session, ds._catalog, part_id, (boxes[node_name] as AABB).get_center() + near, map)


## Reach: a point `k` reaches beyond the drone's own box edge.
static func _reach_case(ds: DesignSpace, _id: String, part_id: String, boxes: Dictionary, k: float) -> String:
	var all: AABB = boxes["*"]
	var span := maxf(all.size.x, all.size.z)
	var p := Vector3(all.end.x + k * REACH_PER_SPAN * span, all.get_center().y, (boxes["motor_FL"] as AABB).get_center().z)
	return String(PartSnap.resolve(ds.session, ds._catalog, part_id, p, ds._mount_map)["kind"])


# ---------------------------------------------------------------------------
# Battery
# ---------------------------------------------------------------------------

static func _battery(id: String, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var p := "[%s] battery: " % id
	var env: Dictionary = CLASS_ENVELOPE[id]
	var ds := _space(id, catalog)
	var seed_id := _seed(id, "battery")
	var rows := _shelf_fits(ds, "battery", "battery")
	var bad: Array = []
	for r in rows:
		var cells := int(catalog.get_part(String(r["id"]))["specs"]["cells"])
		if (cells < env["cells"][0] or cells > env["cells"][1]) and String(r["id"]) != seed_id:
			bad.append("%s(%dS)" % [r["id"], cells])
	out.append(_t(p + "shelf is non-empty", rows.size() > 0, str(rows.size())))
	out.append(_t(p + "shelf offers only this class's cell counts", bad.is_empty(), ", ".join(PackedStringArray(bad))))

	# Swap. An alternative inside the class when there is one, else any pack that mounts.
	var alt := _alternative(ds, rows, "battery")
	if alt == "":
		alt = _alternative(ds, catalog.list_category("battery").map(func(b): return {"id": b["part_id"]}), "battery")
	var before := ds.session.readouts(catalog)
	var v := ds.choose("battery", alt) if alt != "" else {"ok": false}
	var after := ds.session.readouts(catalog)
	var want_auw := "%.1f g" % float(after.get("auw_g", NAN))
	out.append(_t(p + "swap applies and the readouts are finite and change",
		bool(v["ok"]) and _finite(after) and not _same(before, after) and (ds.value_labels["auw_g"] as Label).text == want_auw,
		"alt=%s %s" % [alt, str(v.get("reason", ""))]))
	ds.undo()

	# Snap.
	var boxes := _glb_boxes(id)
	var snap_part := alt if alt != "" else seed_id
	var sv := _snap_at(ds, id, snap_part, "battery", boxes)
	out.append(_t(p + "a drop near the pack snaps to the battery mount", sv["kind"] == "snap" and sv["mount"] == "part/battery", "%s %s" % [sv["kind"], sv["mount"]]))
	out.append(_t(p + "a drop just inside the class reach lands", _reach_case(ds, id, snap_part, boxes, 0.8) == "snap"))
	out.append(_t(p + "a drop beyond the class reach is nothing", _reach_case(ds, id, snap_part, boxes, 1.3) == "nothing"))

	# Pack designer.
	ds.open_pack_designer()
	var pd := ds.pack_designer
	var cells_open := pd.design.series if pd != null else -1
	var fig_ok := pd != null and not pd.figures().is_empty()
	for k in (pd.figures() if pd != null else {}):
		var f: Variant = pd.figures()[k]
		if (f is float or f is int) and (is_nan(float(f)) or is_inf(float(f))):
			fig_ok = false
	out.append(_t(p + "pack designer opens on this class's cell count", pd != null and ((cells_open >= env["cells"][0] and cells_open <= env["cells"][1]) or cells_open == int(catalog.get_part(seed_id)["specs"]["cells"])), "series=%d" % cells_open))
	out.append(_t(p + "pack designer figures are finite", fig_ok))
	var pid := pd.save() if pd != null else ""
	var sv2 := ds.choose("battery", pid) if pid != "" else {"ok": false, "reason": "no id"}
	out.append(_t(p + "a designed pack saves and fits", pid != "" and bool(sv2["ok"]) and _finite(ds.session.readouts(ds._catalog)), str(sv2.get("reason", ""))))

	# Save and reopen.
	var rt := _round_trip(ds, id)
	out.append(_t(p + "save and reopen round-trips", rt == "", rt))
	_done(ds)
	return out


# ---------------------------------------------------------------------------
# Motor
# ---------------------------------------------------------------------------

static func _tested_dia(catalog: PartsCatalog, motor: Dictionary) -> float:
	var pr := catalog.get_part(String(motor.get("thrust_test", {}).get("prop_id", "")))
	return float(pr.get("specs", {}).get("diameter_inches", 0.0))


static func _motor(id: String, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var p := "[%s] motor: " % id
	var env: Dictionary = CLASS_ENVELOPE[id]
	var ds := _space(id, catalog)
	var seed_id := _seed(id, "motor")
	var rows := _shelf_fits(ds, "motor", "motor")
	var bad: Array = []
	for r in rows:
		var d := _tested_dia(catalog, catalog.get_part(String(r["id"])))
		if (d < env["prop"][0] - MOTOR_TEST_SLACK_IN or d > env["prop"][1] + MOTOR_TEST_SLACK_IN) and String(r["id"]) != seed_id:
			bad.append("%s(tested %.1f in)" % [r["id"], d])
	out.append(_t(p + "shelf is non-empty", rows.size() > 0, str(rows.size())))
	out.append(_t(p + "shelf offers only motors tested near this class's props", bad.is_empty(), ", ".join(PackedStringArray(bad))))

	# Motor count: the GLB's nodes against the Build.
	var boxes := _glb_boxes(id)
	var nodes: Array = boxes.keys().filter(func(k): return String(k).begins_with("motor_"))
	var b := ds.session.build(catalog)
	var count_ok := b != null and b.motor_count() == nodes.size()
	if STAND_IN_MODELS.has(id):
		count_ok = not count_ok and _still_copy(id)
	out.append(_t(p + "the build's motor count equals the drawn motors" + (" (stand-in: differs while the model is a copy)" if STAND_IN_MODELS.has(id) else ""), count_ok, "build=%d drawn=%d" % [b.motor_count() if b != null else -1, nodes.size()]))

	# Snap on every motor mount.
	var mounts_ok := true
	var detail := ""
	for n in nodes:
		var sv := _snap_at(ds, id, seed_id, String(n), boxes)
		if sv["kind"] != "snap" or sv["mount"] != _address(String(n)):
			mounts_ok = false
			detail += " %s->%s/%s" % [n, sv["kind"], sv["mount"]]
	out.append(_t(p + "a drop on each drawn motor snaps to that motor", mounts_ok, detail))
	var fill := PartSnap.mounts_for(ds._mount_map, "motor").size()
	out.append(_t(p + "a motor fills every drawn motor mount", fill == nodes.size(), "fills=%d drawn=%d" % [fill, nodes.size()]))
	out.append(_t(p + "a drop just inside the class reach lands", _reach_case(ds, id, seed_id, boxes, 0.8) == "snap"))
	out.append(_t(p + "a drop beyond the class reach is nothing", _reach_case(ds, id, seed_id, boxes, 1.3) == "nothing"))

	# Designer: opens on this drone's motor, saves, and fits.
	ds.open_motor_designer()
	var md := ds.motor_designer
	var drone_motor := catalog.get_part(seed_id)
	var want_d := float(drone_motor["specs"]["stator_diameter_mm"])
	var got_d := float(md.cfg.get_size(md.design.size).get("stator_diameter_mm", -99.0)) if md != null else -99.0
	out.append(_t(p + "motor designer opens on this drone's stator size", md != null and absf(got_d - want_d) <= 1.0, "want %.1f got %.1f (%s)" % [want_d, got_d, md.design.size if md != null else ""]))
	var figs_ok := md != null and not md.figures().is_empty()
	for k in (md.figures() if md != null else {}):
		var f: Variant = md.figures()[k]
		if (f is float or f is int) and (is_nan(float(f)) or is_inf(float(f))):
			figs_ok = false
	out.append(_t(p + "motor designer figures are finite", figs_ok))
	var mid := md.save() if md != null else ""
	var base := ds.session.readouts(ds._catalog)
	var sv2 := ds.choose("motor", mid) if mid != "" else {"ok": false, "reason": "not saved"}
	var aft := ds.session.readouts(ds._catalog)
	out.append(_t(p + "a designed motor saves, fits, and the readouts stay finite", mid != "" and bool(sv2["ok"]) and _finite(aft), str(sv2.get("reason", ""))))
	# Swap with whatever else the shelf offers (a catalog alternative), if the catalog has one.
	ds.undo()
	var alt := _alternative(ds, rows, "motor")
	var alt_ok := false
	if alt != "":
		var sv3 := ds.choose("motor", alt)
		alt_ok = bool(sv3["ok"]) and _finite(ds.session.readouts(ds._catalog)) and not _same(base, ds.session.readouts(ds._catalog))
	out.append(_t(p + ("catalog has a second motor and swapping it changes the readouts" if not CATALOG_GAPS["motor"].has(id) else "catalog gap: no second motor fits this class (designer only)"),
		alt_ok if not CATALOG_GAPS["motor"].has(id) else alt == "", "alt=%s" % alt))
	var rt := _round_trip(ds, id)
	out.append(_t(p + "save and reopen round-trips", rt == "", rt))
	_done(ds)
	return out


# ---------------------------------------------------------------------------
# Prop
# ---------------------------------------------------------------------------

static func _prop(id: String, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var p := "[%s] prop: " % id
	var env: Dictionary = CLASS_ENVELOPE[id]
	var ds := _space(id, catalog)
	var seed_id := _seed(id, "propeller")
	var rows := _shelf_fits(ds, "prop", "propeller")
	var bad: Array = []
	for r in rows:
		var d := float(catalog.get_part(String(r["id"]))["specs"]["diameter_inches"])
		if (d < env["prop"][0] - PROP_SLACK_IN or d > env["prop"][1] + PROP_SLACK_IN) and String(r["id"]) != seed_id:
			bad.append("%s(%.1f in)" % [r["id"], d])
	out.append(_t(p + "shelf is non-empty", rows.size() > 0, str(rows.size())))
	out.append(_t(p + "shelf offers only this class's prop sizes", bad.is_empty(), ", ".join(PackedStringArray(bad))))

	var boxes := _glb_boxes(id)
	var nodes: Array = boxes.keys().filter(func(k): return String(k).begins_with("prop_"))
	var mounts_ok := true
	var detail := ""
	for n in nodes:
		var sv := _snap_at(ds, id, seed_id, String(n), boxes)
		if sv["kind"] != "snap" or sv["mount"] != _address(String(n)):
			mounts_ok = false
			detail += " %s->%s/%s" % [n, sv["kind"], sv["mount"]]
	out.append(_t(p + "a drop on each drawn prop snaps to that prop", mounts_ok, detail))
	var b := ds.session.build(catalog)
	var fill := PartSnap.mounts_for(ds._mount_map, "propeller").size()
	var fill_ok: bool = b != null and fill == b.motor_count()
	if STAND_IN_MODELS.has(id):
		fill_ok = b != null and fill != b.motor_count() and fill == nodes.size() and _still_copy(id)  # one prop per DRAWN mount while it is a copy
	out.append(_t(p + "a prop fills one mount per motor" + (" (stand-in: one per drawn mount while the model is a copy)" if STAND_IN_MODELS.has(id) else ""), fill_ok, "fills=%d motors=%d" % [fill, b.motor_count() if b != null else -1]))
	out.append(_t(p + "a drop just inside the class reach lands", _reach_case(ds, id, seed_id, boxes, 0.8) == "snap"))
	out.append(_t(p + "a drop beyond the class reach is nothing", _reach_case(ds, id, seed_id, boxes, 1.3) == "nothing"))

	var alt := _alternative(ds, rows, "propeller")
	# Designer: opens on this drone's prop, a size step moves the thrust, it fits and flies.
	var base := ds.session.readouts(catalog)
	ds.open_prop_designer()
	var pd := ds.prop_designer
	var fitted_d := float(catalog.get_part(seed_id)["specs"]["diameter_inches"])
	var open_d := pd.doc.diameter_mm / PropellerDocument.INCH_TO_MM if pd != null else -1.0
	out.append(_t(p + "prop designer opens on this drone's prop", pd != null and absf(open_d - fitted_d) < 0.05, "want %.2f got %.2f" % [fitted_d, open_d]))
	var f0 := pd.figures() if pd != null else {}
	var finite := not f0.is_empty() and String(f0.get("refusal", "x")) == ""
	for k in f0:
		var fv: Variant = f0[k]
		# mount_hz is INF with no soft-mount pad (a stated "rigid"), not a defect.
		if k != "mount_hz" and (fv is float or fv is int) and (is_nan(float(fv)) or is_inf(float(fv))):
			finite = false
	out.append(_t(p + "prop designer figures are finite and it makes thrust", finite and float(f0.get("thrust_g", 0.0)) > 0.0, str(f0.get("refusal", ""))))
	out.append(_t(p + "prop designer opens with a hub above zero (the boss of a small prop is not rounded away)", pd != null and pd.hub_g > 0.0, "hub %s" % (pd.hub_g if pd != null else -1.0)))
	if pd != null:
		pd.step_diameter(0.1)
	var f1 := pd.figures() if pd != null else {}
	out.append(_t(p + "a size step moves the thrust", not f1.is_empty() and not is_equal_approx(float(f1.get("thrust_g", 0.0)), float(f0.get("thrust_g", 0.0)))))
	if pd != null:
		pd.step_diameter(-0.1)
	var fit := pd.fit_to_drone() if pd != null else false
	var aft := ds.session.readouts(ds._catalog)
	out.append(_t(p + "Fit to drone saves, fits and the readouts are finite", fit and _finite(aft), str(pd.status_label.text if pd != null else "")))
	ds.undo()
	var alt_ok := false
	if alt != "":
		var sv := ds.choose("propeller", alt)
		alt_ok = bool(sv["ok"]) and _finite(ds.session.readouts(ds._catalog)) and not _same(base, ds.session.readouts(ds._catalog))
	out.append(_t(p + ("catalog has a second prop and swapping it changes the readouts" if not CATALOG_GAPS["propeller"].has(id) else "catalog gap: no second prop fits this class (designer only)"),
		alt_ok if not CATALOG_GAPS["propeller"].has(id) else alt == "", "alt=%s" % alt))
	var rt := _round_trip(ds, id)
	out.append(_t(p + "save and reopen round-trips", rt == "", rt))
	_done(ds)
	return out


static func _still_copy(id: String) -> bool:
	var a := FileAccess.get_file_as_bytes(DroneClass.model_path(id))
	return not a.is_empty() and a == FileAccess.get_file_as_bytes(DroneClass.model_path(String(STAND_IN_MODELS[id])))
