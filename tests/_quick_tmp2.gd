extends SceneTree
func _init() -> void:
	var a := TestSimReality._quick_time(1.0)
	var b := TestSimReality._quick_time(0.7)
	print("QUICK base %.3f cut %.3f  err_vs_full(43.318) %.3f%%  cut_moves %.1f%%" % [a, b, absf(a - 43.318) / 43.318 * 100.0, absf(b - a) / a * 100.0])
	quit(0)
