class_name TestMotorDetailMesh
extends RefCounted
## The 3D motor in the motor designer is drawn from the record: its bell is the stator diameter
## times the bell ratio, its mount holes sit on the record's pattern, its shaft is the record's,
## and a copper winding shows under the bell. Each is read off the built nodes' mesh data, not off
## the formula that builds them, so a mesh that ignores the record fails.


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _record(stator_d: float, stator_h: float, mount: String, shaft: float, ratio := 1.27) -> Dictionary:
	return {"mount_pattern": mount, "specs": {"stator_diameter_mm": stator_d, "stator_height_mm": stator_h,
		"bell_diameter_ratio": ratio, "bell_height_ratio": 2.6, "shaft_mm": shaft, "config": "12N14P"}}


static func _tris(m: MotorDetailMesh) -> int:
	var n := 0
	for c in m.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return n


static func run() -> Array:
	var out: Array = []
	var m := MotorDetailMesh.new()
	# Bell diameter follows size and ratio (a 2207 and a 1404 differ; a changed ratio moves it).
	m.rebuild(_record(22.0, 7.0, "16x16", 4.0, 1.27), 0.003)
	var bell := ((m.find_child("Bell", false, false) as MeshInstance3D).mesh as CylinderMesh).top_radius * 2.0
	out.append(_t("bell diameter is the stator diameter times the bell ratio (2207)",
		absf(bell - 0.022 * 1.27) < 1e-6, str(bell)))
	m.rebuild(_record(14.0, 4.0, "12x12", 3.0, 1.30), 0.003)
	bell = ((m.find_child("Bell", false, false) as MeshInstance3D).mesh as CylinderMesh).top_radius * 2.0
	out.append(_t("bell diameter follows a 1404 and its ratio", absf(bell - 0.014 * 1.30) < 1e-6, str(bell)))
	# Mount holes: four, on a square whose side is the pattern, read from node positions.
	for pat in ["12x12", "16x16", "19x19"]:
		m.rebuild(_record(22.0, 7.0, pat, 4.0), 0.003)
		var xs: Array = []
		var zs: Array = []
		var n := 0
		for i in 4:
			var h := m.find_child("MountHole%d" % i, false, false) as Node3D
			if h != null:
				n += 1
				xs.append(h.position.x)
				zs.append(h.position.z)
		var want := float(pat.split("x")[0]) / 1000.0
		out.append(_t("mount holes sit %s apart (%s)" % [want * 1000.0, pat],
			n == 4 and absf((xs.max() - xs.min()) - want) < 1e-6 and absf((zs.max() - zs.min()) - want) < 1e-6,
			"%d holes %s %s" % [n, xs, zs]))
	# Shaft follows the record.
	m.rebuild(_record(22.0, 7.0, "16x16", 5.0), 0.003)
	var sr := ((m.find_child("Shaft", false, false) as MeshInstance3D).mesh as CylinderMesh).top_radius
	out.append(_t("shaft diameter is the record's 5 mm", absf(sr * 2.0 - 0.005) < 1e-9, str(sr)))
	m.rebuild(_record(22.0, 7.0, "16x16", 4.0), 0.003)
	sr = ((m.find_child("Shaft", false, false) as MeshInstance3D).mesh as CylinderMesh).top_radius
	out.append(_t("a 4 mm shaft is thinner than the 5 mm one", absf(sr * 2.0 - 0.004) < 1e-9, str(sr)))
	# Winding exists, is the only copper, and sits inside the bell radius, below the bell.
	var w := m.find_child("Winding", false, false) as MeshInstance3D
	var coppers := 0
	for c in m.get_children():
		var mi := c as MeshInstance3D
		var col := (mi.material_override as StandardMaterial3D).albedo_color
		if col.r - col.b > 0.2:
			coppers += 1
	out.append(_t("one copper winding, within the bell, clear of it vertically",
		w != null and coppers == 1 and w.mesh.get_aabb().size.x * 0.5 < m.bell_radius_m
		and w.position.y + w.mesh.get_aabb().size.y <= (m.find_child("Bell", false, false) as Node3D).position.y
			- ((m.find_child("Bell", false, false) as MeshInstance3D).mesh as CylinderMesh).height * 0.5 + 1e-6,
		"copper nodes %d" % coppers))
	# Vents: the lid has spokes, and the spoke count is five.
	var spokes := 0
	for c in m.get_children():
		if String(c.name).begins_with("Spoke"):
			spokes += 1
	out.append(_t("the bell lid has five spokes", spokes == 5, str(spokes)))
	# Modest triangle count.
	m.rebuild(_record(28.0, 6.5, "19x19", 5.0), 0.003)
	var tris := _tris(m)
	out.append(_t("triangle count stays modest", tris > 500 and tris < 6000, str(tris)))
	m.free()
	return out
