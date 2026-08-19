extends SceneTree
func _init() -> void:
	var catalog := PartsCatalog.load_default()
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var doc := AirframeDocument.from_catalog_frame(frame)
	for plate in doc.plates:
		var outline := AirframeDocument.plate_outline(plate)
		var area := PolygonProps.area(outline)
		var mesh := PlateMesh.extrude(outline, AirframeDocument.plate_thickness_mm(plate), AirframeDocument.plate_z_mm(plate))
		print(plate.get("role"), " pts=", outline.size(), " area=", area,
			" mesh=", "null" if mesh == null else str(mesh.get_aabb()),
			" tris=", 0 if mesh == null else int(mesh.surface_get_array_len(0) / 3.0))
	var model := FrameModel.new()
	model.rebuild(frame)
	print("children: ", model.get_child_count(), " side=", model.plate_side_m, " topface=", model.plate_top_face_m())
	model.free()
	quit()
