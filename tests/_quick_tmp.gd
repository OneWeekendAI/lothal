extends SceneTree
func _init() -> void:
	var bad := 0
	for r in TestSimReality._quick_matches_full() + TestSimReality._quick_sees_capacity_cut():
		print("[%s] %s (%s)" % ["PASS" if r.passed else "FAIL", r.name, r.detail])
		if not r.passed: bad += 1
	quit(bad)
