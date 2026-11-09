extends SceneTree
## Regenerates data/worlds/*.world.json (the shipped presets). The Illinois preset imports its ground from USGS 3DEP over the
## network (or from tests/fixtures/illinois_3dep.tif with `-- offline`), so run it deliberately; the shipped files are what
## ships. godot --headless --script res://tools/build_worlds.gd [-- offline]
func _init() -> void:
	await process_frame
	var offline := "offline" in OS.get_cmdline_user_args()
	var out := "res://data/worlds"
	var il := WorldPresets.illinois_corn_july()
	var fixture := "res://tests/fixtures/illinois_3dep.tif"
	var res: Dictionary
	if offline:
		res = ElevationImport.apply_bytes(il, FileAccess.get_file_as_bytes(fixture), ElevationImport.DEFAULT_STEP_M, ElevationImport.DEFAULT_PAD_M, "tile saved in tests/fixtures/illinois_3dep.tif")
	else:
		res = await ElevationImport.import_world(root, il, ElevationImport.DEFAULT_STEP_M, ElevationImport.DEFAULT_PAD_M, "retrieved 2026-11-09 from the 3DEPElevation ImageServer")
		if bool(res["ok"]):
			var f := FileAccess.open(fixture, FileAccess.WRITE)
			f.store_buffer(res["bytes"])
			f.close()
	print("illinois import: ", {"ok": res["ok"], "error": res.get("error", ""), "home_elevation_m": res.get("home_elevation_m"), "missing": res.get("missing_nodes")})
	if not bool(res["ok"]):
		quit(1)
		return
	for w in [il, WorldPresets.calm_test_field(), WorldPresets.windy_coast(), WorldPresets.high_altitude()]:
		print(w.world_id, " missing sources: ", w.missing_sources(), " area m2 ", w.area_m2(), " sun ", w.sun().get("elevation_deg"))
		w.save("%s/%s%s" % [out, w.world_id, WorldLibrary.SUFFIX])
	quit(0)
