class_name SimDroneModel
extends Node3D
## The aircraft the field flies: the Design Space's own per-class model, not a second drawing.
##
## The Design Space draws every drone from a Blender-built GLB per class (assets/models/classes,
## tools/blender/build_drone.py): carbon plates and arms, bevelled screws, motors with bells and
## windings, three-surface props, a wrapped pack, a stack, wiring. The field used to draw the same
## Build with AirframeModel (generated sticks and discs), so the aircraft you designed and the
## aircraft you flew looked like two different machines. This node loads the SAME GLB, re-fits the
## parts to the Build with the SAME `SwapLook` the Design Space uses, and adds only what a flying
## model needs that a still one does not: spinning props and a camera eye.
##
## Frames: the GLB's frame IS the Build's frame (x right, y up, -Z forward; y = 0 at the bottom
## plate underside; the pack's seat in the GLB is the seat `MountLayout` computes, 0.031 m on the
## reference build). The rigid body's origin is the composite centre of mass, so the whole model
## is shifted by -`Build.mass_properties.com_m`: the CG you designed is the point the physics
## rotates about. The old AirframeModel drew about the plate datum and was 12 mm off on the
## reference 5".
##
## Props: each GLB prop is one mesh whose origin is its hub. It turns about its own Y by the
## published rpm of its motor, direction from MotorLayout.spin_map (the same table the yaw torque
## reads). Above the alias limit (PropellerMesh.max_discrete_rpm) the blade surface fades and a
## swept disc takes over, which is the rule the old PropellerMesh used and for the same reason.

const MODEL_DIR := "res://assets/models/classes/"
## GLB corner -> MotorLayout motor name (M1 rear-right, M2 front-right, M3 rear-left, M4 front-left,
## bmp_classes / build_drone.py MOTORS).
const CORNER_TO_MOTOR := {"BR": "M1", "FR": "M2", "BL": "M3", "FL": "M4"}
## Meshes that exist for the Design Space's picking, never for looking at.
const PROXY_PREFIX := "pick_"
## Small hardware that is lost to the eye beyond this and is not worth a draw call or a shadow.
const SMALL_PARTS_RANGE_M := 6.0
const BLADE_FADED_ALPHA := 0.12
const BLUR_ALPHA := 0.26

var class_id := ""
## The instantiated GLB, shifted so the centre of mass is this node's origin.
var content: Node3D
var com_m := Vector3.ZERO
## SwapLook node name -> MeshInstance3D ("battery", "motor_FL", "prop_FL", "stack", ...).
var part_nodes: Dictionary = {}
## MotorLayout name (M1..M4) -> that corner's prop mesh. A coaxial lower prop is not in here: it
## shares its corner's rate and is turned with it (`_lower_props`).
var prop_nodes: Dictionary = {}
var _lower_props: Dictionary = {}
var _blur_discs: Dictionary = {}
var _faded_blade: Dictionary = {}
var _blade_surface: Dictionary = {}
var _rate_rad_s: Dictionary = {}
var _blurred: Dictionary = {}
var _spin: Dictionary = {}
var _angle: Dictionary = {}
var _blades := 2
var _eye: Node3D = null
var _drawn_selection: Dictionary = {}
var _plain_wrap: StandardMaterial3D = null

static var _scene_cache: Dictionary = {}


## The class this Build is. `hint` (the Design Space's own drone_class) wins when it names a class
## with a model; otherwise the class whose seed frame is the Build's frame; otherwise the class whose
## wheelbase is nearest the Build's diagonal (2 x arm). Never empty: five_inch is the DS default.
static func class_for(build: Build, hint: String = "") -> String:
	if hint != "" and ResourceLoader.exists(DroneClass.model_path(hint)):
		return hint
	var frame_id := String(build.frame.get("part_id", ""))
	var best := DroneClass.DEFAULT_ID
	var best_d := INF
	for id in DroneClass.ids():
		if not ResourceLoader.exists(DroneClass.model_path(id)):
			continue
		var seed_parts := DroneClass.parts_for(id)
		if frame_id != "" and String(seed_parts.get("frame", "")) == frame_id:
			return id
		var d := absf(float(DroneClass.by_id(id).get("wheelbase_mm", 0.0)) * 0.001 - 2.0 * build.arm_m)
		if d < best_d:
			best_d = d
			best = id
	return best


## The category -> part id selection a Build was made from, in the names SwapLook uses.
static func selection_of(build: Build) -> Dictionary:
	var sel := {
		"frame": String(build.frame.get("part_id", "")),
		"motor": String(build.motor.get("part_id", "")),
		"propeller": String(build.propeller.get("part_id", "")),
		"battery": String(build.battery.get("part_id", "")),
		"esc": String(build.esc.get("part_id", "")),
		"flight_controller": String(build.fc.get("part_id", "")),
	}
	for category in build.components:
		sel[category] = String((build.components[category] as Dictionary).get("part_id", ""))
	if not build.guard.is_empty():
		sel["guard"] = String(build.guard.get("part_id", ""))
	return sel


func rebuild(build: Build, p_class_id: String, catalog: PartsCatalog, tweaks: AssemblyTweaks = null) -> void:
	if content != null:
		remove_child(content)
		content.free()
	content = null
	part_nodes.clear()
	prop_nodes.clear()
	_lower_props.clear()
	_blur_discs.clear()
	_faded_blade.clear()
	_blade_surface.clear()
	_rate_rad_s.clear()
	_blurred.clear()
	_angle.clear()
	_eye = null
	class_id = p_class_id
	var scene: PackedScene = _scene_cache.get(class_id)
	if scene == null:
		scene = load(DroneClass.model_path(class_id)) as PackedScene
		_scene_cache[class_id] = scene
	if scene == null:
		return
	content = scene.instantiate() as Node3D
	content.name = "DesignSpaceModel"
	add_child(content)
	for proxy in content.find_children(PROXY_PREFIX + "*", "MeshInstance3D", true, false):
		proxy.get_parent().remove_child(proxy)
		proxy.free()
	for node_name in SwapLook.NODES:
		var mi := content.find_child(node_name, true, false) as MeshInstance3D
		if mi != null:
			part_nodes[node_name] = mi

	# Re-fit the drawn parts to the Build, exactly as the Design Space does on a swap.
	var drawn := DroneClass.parts_for(class_id)
	var seed_session := DesignSession.default_for_class(class_id)
	_drawn_selection = seed_session.selection.duplicate() if seed_session != null else drawn
	var now := selection_of(build)
	var base := {}
	for node_name in part_nodes:
		var mi := part_nodes[node_name] as MeshInstance3D
		var pivot := Vector3.ZERO
		match node_name:
			"battery":
				pivot = Vector3(0, _wrap_bottom(mi.mesh), 0)
			"stack":
				pivot = Vector3(0, mi.mesh.get_aabb().position.y, 0)
			"antennas":
				var box := mi.mesh.get_aabb()
				pivot = Vector3(0, box.position.y, box.position.z)
		base[node_name] = {"xf": mi.transform, "pivot": pivot}
	var t := SwapLook.transforms(base, _drawn_selection, now, catalog)
	for node_name in t:
		var mi := part_nodes[node_name] as MeshInstance3D
		mi.transform = t[node_name]["xf"]
		mi.visible = t[node_name]["visible"]
	_plain_label_if_swapped(now)

	# The CG is the origin of the body the physics flies.
	com_m = build.mass_properties.com_m if build.mass_properties != null else Vector3.ZERO
	content.position = -com_m

	# The payload hangs from the attach point under the belly, in the same body frame the GLB is in, so it
	# is a child of `content` and rides with the airframe. PayloadMesh is the Design Space's own drawing.
	if not build.payload_part.is_empty():
		var payload := PayloadMesh.build(build.payload_part)
		payload.name = "Payload"
		payload.position = build.payload_attach_m()
		content.add_child(payload)

	_blades = maxi(int(build.propeller.get("specs", {}).get("blades", 3)), 1)
	var spin_map := MotorLayout.spin_map(build.config)
	for corner in CORNER_TO_MOTOR:
		var motor_name: String = CORNER_TO_MOTOR[corner]
		_spin[motor_name] = float(spin_map.get(motor_name, 1.0))
		_angle[motor_name] = 0.0
		_rate_rad_s[motor_name] = 0.0
		var prop := part_nodes.get("prop_" + corner) as MeshInstance3D
		if prop == null:
			continue
		prop_nodes[motor_name] = prop
		_prepare_prop(motor_name, prop)
		var lower := part_nodes.get("prop_%s_lo" % corner) as MeshInstance3D
		if lower != null:
			_lower_props[motor_name] = lower
			_prepare_prop(motor_name + "_lo", lower)
	_fit_budget()
	var tweak_m := Build.DEFAULT_ASSEMBLY.duplicate()
	if tweaks != null:
		tweak_m = tweaks.resolved_m(build)
	_make_eye(float(tweak_m.get("camera_tilt_deg", 0.0)))


## Where the pack's cells start (the wrap's lowest vertex), as the Design Space measures it.
static func _wrap_bottom(mesh: Mesh) -> float:
	var lo := INF
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat == null or not String(mat.resource_name).begins_with("lipo_"):
			continue
		for v in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			lo = minf(lo, (v as Vector3).y)
	return lo if lo != INF else mesh.get_aabb().position.y


## A swapped pack loses the printed wrap of the seed pack (it would lie about the cells).
func _plain_label_if_swapped(now: Dictionary) -> void:
	var node := part_nodes.get("battery") as MeshInstance3D
	if node == null or String(now.get("battery", "")) == String(_drawn_selection.get("battery", "")):
		return
	if _plain_wrap == null:
		_plain_wrap = StandardMaterial3D.new()
		_plain_wrap.albedo_color = Color(0.11, 0.11, 0.12)
		_plain_wrap.roughness = 0.55
	for i in node.mesh.get_surface_count():
		var mat := node.mesh.surface_get_material(i)
		if mat != null and String(mat.resource_name).begins_with("lipo_wrap"):
			node.set_surface_override_material(i, _plain_wrap)


## Rotation about the prop's own axis is a node rotation; a swept disc and a faded blade material
## are prepared once so a frame at speed allocates nothing.
func _prepare_prop(motor_name: String, prop: MeshInstance3D) -> void:
	var base_xf := prop.transform
	prop.set_meta("base_basis", base_xf.basis)
	var blade_idx := -1
	var blade_mat: BaseMaterial3D = null
	for i in prop.mesh.get_surface_count():
		var mat := prop.mesh.surface_get_material(i) as BaseMaterial3D
		if mat != null and String(mat.resource_name).begins_with("prop_translucent"):
			blade_idx = i
			blade_mat = mat
	_blade_surface[motor_name] = blade_idx
	if blade_mat != null:
		var faded := blade_mat.duplicate() as BaseMaterial3D
		faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := faded.albedo_color
		faded.albedo_color = Color(c.r, c.g, c.b, BLADE_FADED_ALPHA)
		_faded_blade[motor_name] = faded
	# The swept disc, unshaded for the reason PropellerMesh gives: a blade passing forty times a
	# second has no stable surface for a light to fall on.
	var box := prop.mesh.get_aabb()
	var radius := 0.5 * maxf(box.size.x, box.size.z)
	var disc := MeshInstance3D.new()
	disc.name = "BlurDisc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.0006
	cyl.radial_segments = 40
	cyl.rings = 1
	disc.mesh = cyl
	var disc_mat := StandardMaterial3D.new()
	var tint := Color(0.5, 0.52, 0.55)
	if blade_mat != null:
		tint = Color(blade_mat.albedo_color.r, blade_mat.albedo_color.g, blade_mat.albedo_color.b).lerp(Color(0.5, 0.52, 0.55), 0.5)
	disc_mat.albedo_color = Color(tint.r, tint.g, tint.b, BLUR_ALPHA)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0, box.position.y + box.size.y * 0.5, 0)
	disc.visible = false
	prop.add_child(disc)
	_blur_discs[motor_name] = disc


## Frame-time budget: the big surfaces cast shadows, the screws, standoffs, wires and antennas do
## not, and the small hardware drops out entirely at range. The meshes carry their own import LODs.
func _fit_budget() -> void:
	for mi in content.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		var n := String(node.name)
		if n.begins_with("frame_screw") or n.begins_with("frame_standoff") or n == "wires" \
				or n == "antennas" or n == "camera":
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n.begins_with("frame_screw") or n.begins_with("frame_standoff"):
			node.visibility_range_end = SMALL_PARTS_RANGE_M
			node.visibility_range_end_margin = 1.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## The lens: a marker at the front face of the camera body (so a swapped, rescaled camera moves its
## own eye), looking down the body's -Z tipped UP by the builder's saved camera tilt. The tilt is the
## assembly tweak, the same number FpvView.tilt_deg() reads back and the old ComponentMesh's Eye
## carried, so the feed is unchanged by which model is drawn.
func _make_eye(tilt_deg: float) -> void:
	var cam := part_nodes.get("camera") as MeshInstance3D
	if cam == null or not cam.visible:
		return
	var box := cam.mesh.get_aabb()
	_eye = Node3D.new()
	_eye.name = "Eye"
	_eye.position = cam.transform * Vector3(box.get_center().x, box.get_center().y, box.position.z)
	_eye.basis = Basis(Vector3.RIGHT, deg_to_rad(tilt_deg))
	content.add_child(_eye)


## The fitted camera's lens, or null when the build has none (FpvView.attach reads null as "none").
func camera_eye() -> Node3D:
	return _eye


## Hands each prop the rpm of its own motor, MotorLayout.MOTOR_NAMES order (Observables.rpm).
func set_rates_rpm(rpm: PackedFloat32Array) -> void:
	for i in MotorLayout.MOTOR_NAMES.size():
		if i >= rpm.size():
			return
		_set_rate(MotorLayout.MOTOR_NAMES[i], rpm[i])


func set_all_rates_rpm(rpm: float) -> void:
	for motor_name in MotorLayout.MOTOR_NAMES:
		_set_rate(motor_name, rpm)


func _set_rate(motor_name: String, rpm: float) -> void:
	_rate_rad_s[motor_name] = absf(rpm) / 60.0 * TAU * float(_spin.get(motor_name, 1.0)) * _axis_sign(motor_name)
	var blurred := absf(rpm) > PropellerMesh.max_discrete_rpm(_blades, PropellerMesh.DESIGN_FPS)
	# Only on a CHANGE: this runs at 120 Hz per rotor, and a material swap is not free.
	if blurred == bool(_blurred.get(motor_name, false)):
		return
	_blurred[motor_name] = blurred
	_apply_blur(motor_name, prop_nodes.get(motor_name), blurred)
	_apply_blur(motor_name + "_lo", _lower_props.get(motor_name), blurred)


func _apply_blur(key: String, prop: MeshInstance3D, blurred: bool) -> void:
	if prop == null or not _blur_discs.has(key):
		return
	(_blur_discs[key] as MeshInstance3D).visible = blurred
	var idx: int = _blade_surface.get(key, -1)
	if idx >= 0 and _faded_blade.has(key):
		prop.set_surface_override_material(idx, _faded_blade[key] if blurred else null)


## +1 when the prop mesh's own +Y points up in the body, -1 when the model mounts it flipped, so a
## positive spin is a positive turn about the BODY's +Y either way.
func _axis_sign(motor_name: String) -> float:
	var prop := prop_nodes.get(motor_name) as MeshInstance3D
	if prop == null:
		return 1.0
	var base: Basis = prop.get_meta("base_basis", Basis.IDENTITY)
	return 1.0 if (base * Vector3.UP).y >= 0.0 else -1.0


func rate_rad_s(motor_name: String) -> float:
	return float(_rate_rad_s.get(motor_name, 0.0))


func is_blurred(motor_name: String) -> bool:
	var disc := _blur_discs.get(motor_name) as MeshInstance3D
	return disc != null and disc.visible


## The angle a prop is at about its own axis, rad, wrapped.
func prop_angle(motor_name: String) -> float:
	return float(_angle.get(motor_name, 0.0))


## One step of rotation. Wrapped rather than accumulated: 29,000 rpm adds 3,000 rad a second.
func advance(delta: float) -> void:
	for motor_name in prop_nodes:
		var rate: float = _rate_rad_s[motor_name]
		if rate == 0.0:
			continue
		var a := fposmod(float(_angle[motor_name]) + rate * delta, TAU)
		_angle[motor_name] = a
		_apply_angle(prop_nodes[motor_name], a)
		if _lower_props.has(motor_name):
			_apply_angle(_lower_props[motor_name], -a)


static func _apply_angle(prop: MeshInstance3D, angle: float) -> void:
	var base: Basis = prop.get_meta("base_basis", Basis.IDENTITY)
	prop.basis = base * Basis(Vector3.UP, angle)


func _process(delta: float) -> void:
	advance(delta)
