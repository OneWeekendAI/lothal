extends SceneTree
## TEMPORARY: times Field edits in the real shell (each edit saves + refreshes).
var shell: Node
var frames := 0
func _initialize() -> void:
	shell = (load("res://src/scenes/root.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	process_frame.connect(_on_frame)
func _t(label: String, c: Callable) -> void:
	var a := Time.get_ticks_usec(); c.call()
	print("EDIT %-26s %7.1f ms" % [label, (Time.get_ticks_usec() - a) / 1000.0])
func _on_frame() -> void:
	frames += 1
	if frames != 60: return
	shell.select_system_by_name("Field")
	var f = shell.field_room()
	print("site %s  extent %s  gates %d" % [f.site().site_name if f.site() else "none", f.site_terrain().extent() if f.site_terrain() else "flat", f.course().gates.size()])
	var h: float = f.gate_height_above_ground_m(0) if f.course().gates.size() > 0 else 2.0
	for i in 3: _t("gate height", func(): f.set_gate_height_m(h))
	_t("gate heading", func(): f.set_gate_heading_deg(10.0))
	_t("field temperature", func(): f.set_field_temperature_c(20.0))
	_t("refresh()", func(): f.refresh())
	quit()
