extends SceneTree
## Writes tests/fixtures/prop_preset_figures.json from live code. See tests/prop_preset_figures.gd
## for when this may be run; every regeneration is logged in the prop tracker with its reason.

func _init() -> void:
	var f := FileAccess.open(PropPresetFigures.FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(PropPresetFigures.snapshot(), "\t", true, true))
	f.close()
	print("PROP PIN WRITTEN")
	quit()
