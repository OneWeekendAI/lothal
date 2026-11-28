extends SceneTree
## Dev tool, not a test: photographs the S7 realistic parts (PartAssets, PropellerMesh, WireTubes)
## on the five_inch class model, plus a parts row, and measures orbit FPS against the stock GLB.
##   godot --path . --script res://tests/capture_s7_parts.gd
## Needs a real window (no --headless). Writes PNGs to build/.

const GLB := "res://assets/models/classes/five_inch.glb"
const SIZE := Vector2i(1280, 720)
# M1 rear-right, M2 front-right, M3 rear-left, M4 front-left; M1/M4 spin +1, M2/M3 -1 (MotorLayout).
const CORNERS := {"BR": 1.0, "FR": -1.0, "BL": -1.0, "FL": 1.0}

var cam: Camera3D
var stage: Node3D
var catalog: PartsCatalog
var seed_parts := {}


func _init() -> void:
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	catalog = PartsCatalog.load_default()
	for c in DroneClass.CLASSES:
		if String(c["id"]) == "five_inch":
			seed_parts = c["seed"]
	_studio()
	_run()


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.37, 0.39)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 1.5
	key.light_angular_distance = 2.0
	key.rotation_degrees = Vector3(-50, -35, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.5
	rim.light_color = Color(0.8, 0.9, 1.0)
	rim.rotation_degrees = Vector3(-20, 150, 0)
	root.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	floor_mi.mesh = pm
	floor_mi.position.y = -0.045
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.33)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	floor_mi.name = "Floor"
	root.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 35
	cam.near = 0.005
	cam.far = 5
	root.add_child(cam)
	cam.make_current()


func _look(from: Vector3, at: Vector3, up := Vector3.UP) -> void:
	cam.look_at_from_position(from, at, up)


func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)


func _glb() -> Node3D:
	return (load(GLB) as PackedScene).instantiate() as Node3D


func _part(kind: String, id: String) -> Node3D:
	return PartAssets.instance(kind, catalog.get_part(id))


func _first(category: String) -> Dictionary:
	var l := catalog.list_category(category)
	return l[0]


func _seed_or_first(key: String, category: String) -> Dictionary:
	if seed_parts.has(key):
		return catalog.get_part(String(seed_parts[key]))
	return _first(category)


func _world_box(n: Node3D) -> AABB:
	return n.transform * (n.get_child(0) as MeshInstance3D).get_aabb() if false else AABB()


## Place `part` so its bottom-centre sits at (x, y_bottom, z) in `parent`.
func _seat(parent: Node3D, part: Node3D, x: float, y_bottom: float, z: float) -> void:
	var b := PartAssets.measured_aabb(part)
	part.position = Vector3(x - (b.position.x + b.size.x * 0.5), y_bottom - b.position.y, z - (b.position.z + b.size.z * 0.5))
	parent.add_child(part)


func _glb_box(model: Node3D, node_name: String) -> AABB:
	var n := model.find_child(node_name, true, false) as MeshInstance3D
	return n.transform * n.get_aabb()


func _assembled() -> Node3D:
	var rootn := Node3D.new()
	rootn.name = "Assembled"
	var g := _glb()
	rootn.add_child(g)
	var model := g.get_child(0) as Node3D
	var stock_box := {}
	for child in model.get_children():
		var nm := String(child.name)
		if nm.begins_with("frame_"):
			continue
		if child is MeshInstance3D:
			stock_box[nm] = child.transform * (child as MeshInstance3D).get_aabb()
		child.visible = false
	var mount := Node3D.new()
	model.add_child(mount)
	# motors + props
	var prop_dict := catalog.get_part(String(seed_parts["propeller"]))
	var motor_pts: Array = []
	for corner in CORNERS:
		var mb: AABB = stock_box["motor_" + corner]
		var motor := PartAssets.instance("motor", _seed_or_first("motor", "motor"))
		var mbox := PartAssets.measured_aabb(motor)
		var cx := mb.position.x + mb.size.x * 0.5
		var cz := mb.position.z + mb.size.z * 0.5
		_seat(mount, motor, cx, mb.position.y, cz)
		var top := mb.position.y + mbox.size.y
		var prop := PropellerMesh.new()
		prop.spin = CORNERS[corner]
		prop.rebuild(prop_dict)
		prop.position = Vector3(cx, top + prop.underside_m, cz)
		PartAssets.fit_prop(motor, prop.stack_height_m)
		mount.add_child(prop)
		motor_pts.append(Vector3(cx, mb.position.y + 0.004, cz))
	# everything else seated from the stock GLB's own node bounds
	var sb: AABB = stock_box["stack"]
	var fc := PartAssets.instance("flight_controller", _seed_or_first("flight_controller", "flight_controller"))
	var fcb := PartAssets.measured_aabb(fc)
	_seat(mount, fc, sb.position.x + sb.size.x * 0.5, sb.position.y, sb.position.z + fcb.size.z * 0.5)
	var rear := sb.position.z + fcb.size.z
	var vtx := PartAssets.instance("vtx", _seed_or_first("vtx", "vtx"))
	var vb := PartAssets.measured_aabb(vtx)
	_seat(mount, vtx, 0.0, sb.position.y, rear + vb.size.z * 0.5)
	var rx := PartAssets.instance("receiver", _seed_or_first("receiver", "receiver"))
	var rb := PartAssets.measured_aabb(rx)
	_seat(mount, rx, 0.0, sb.position.y, rear + vb.size.z + rb.size.z * 0.5)
	var bat := PartAssets.instance("battery", _seed_or_first("battery", "battery"))
	var bb := PartAssets.measured_aabb(bat)
	var bs: AABB = stock_box["battery"]
	_seat(mount, bat, bs.position.x + bs.size.x * 0.5, bs.end.y - bb.size.y, bs.position.z + bs.size.z * 0.5)
	var cb: AABB = stock_box["camera"]
	var cam_part := PartAssets.instance("camera", _seed_or_first("camera", "camera"))
	_seat(mount, cam_part, cb.position.x + cb.size.x * 0.5, cb.position.y, cb.position.z + cb.size.z * 0.5)
	var ab: AABB = stock_box["antennas"]
	var ant := PartAssets.instance("antenna", _seed_or_first("antenna", "antenna"))
	var anb := PartAssets.measured_aabb(ant)
	_seat(mount, ant, ab.position.x + ab.size.x * 0.5, ab.position.y, ab.position.z + anb.size.z * 0.5)
	# wires: stack side edge to each motor base
	var r := WireTubes.radius_for_awg(20)
	var wt_r := WireTubes.build(Vector3(0.019, 0.0105, 0.0), motor_pts.filter(func(p): return p.x > 0), r, 3)
	var wt_l := WireTubes.build(Vector3(-0.019, 0.0105, 0.0), motor_pts.filter(func(p): return p.x < 0), r, 3)
	for w in [wt_r, wt_l]:
		mount.add_child(w)
	return rootn


func _row() -> Node3D:
	var rowroot := Node3D.new()
	var items: Array = []
	for k in PartAssets.kinds():
		var cat := String(k)
		var part: Dictionary = _seed_or_first(cat, cat)
		items.append(PartAssets.instance(k, part))
	for spin in [1.0, -1.0]:
		var p := PropellerMesh.new()
		p.spin = spin
		p.rebuild(catalog.get_part(String(seed_parts["propeller"])))
		items.append(p)
	var x := 0.0
	var gap := 0.015
	for it in items:
		var b := PartAssets.measured_aabb(it)
		it.position = Vector3(x - b.position.x, -b.position.y, 0)
		if it is PropellerMesh:
			it.position = Vector3(x + 0.0635, 0.0, 0.0)
			x += 0.127 + gap
		else:
			x += b.size.x + gap
		rowroot.add_child(it)
	rowroot.position.x = -x * 0.5
	return rowroot


func _fps(label: String, target: Node3D) -> void:
	stage.add_child(target)
	var times: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	var dur := 4.0
	await process_frame
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1e6)
		last = now
		var t := float(now - t0) / 1e6
		if t >= dur:
			break
		var a := TAU * t / dur
		_look(Vector3(cos(a) * 0.32, 0.17, sin(a) * 0.32), Vector3(0, 0.01, 0))
	times.remove_at(0)
	var sum := 0.0
	for d in times:
		sum += d
	var mean := float(times.size()) / sum
	var sorted := times.duplicate()
	sorted.sort()
	var worst_n := maxi(1, int(ceil(sorted.size() * 0.01)))
	var s := 0.0
	for i in worst_n:
		s += sorted[sorted.size() - 1 - i]
	var p1 := float(worst_n) / s
	print("S7_FPS %s mean=%.1f p1low=%.1f frames=%d" % [label, mean, p1, times.size()])
	target.queue_free()
	await process_frame


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	for i in 3:
		await process_frame
	# Scene A
	var a := _assembled()
	stage.add_child(a)
	_look(Vector3(0.20, 0.17, 0.24), Vector3(0, 0.0, 0.0))
	await _shot("res://build/s7_assembled_34.png")
	_look(Vector3(0, 0.42, 0.001), Vector3(0, 0, 0), Vector3(0, 0, -1))
	await _shot("res://build/s7_assembled_top.png")
	_look(Vector3(0.14, 0.07, -0.03), Vector3(0.0778, 0.02, -0.0778))
	await _shot("res://build/s7_motor_close.png")
	a.queue_free()
	await process_frame
	# Scene B
	var row := _row()
	stage.add_child(row)
	_look(Vector3(0, 0.25, 0.42), Vector3(0, 0.0, 0))
	await _shot("res://build/s7_parts_row.png")
	row.queue_free()
	await process_frame
	# FPS
	await _fps("s7", _assembled())
	var stock := Node3D.new()
	stock.add_child(_glb())
	await _fps("stock", stock)
	quit()
