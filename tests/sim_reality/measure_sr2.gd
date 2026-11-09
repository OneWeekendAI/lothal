extends SceneTree
## SR2: altitude and position hold in turbulence. godot --headless --script res://tests/sim_reality/measure_sr2.gd -- [cls=seven_lr] [mph=20] [gust=<m/s or mil>] [secs=120] [model=dryden|first]
func _init() -> void:
	var cls := "seven_lr"; var mph := 20.0; var gust := "mil"; var secs := 120.0; var model := "dryden"
	for a in OS.get_cmdline_user_args():
		var k: String = a.get_slice("=", 0); var v: String = a.get_slice("=", 1)
		match k:
			"cls": cls = v
			"mph": mph = float(v)
			"gust": gust = v
			"secs": secs = float(v)
			"model": model = v
	var spd := mph * 0.44704
	var g := Wind.mil_gustiness_mps(spd, 0.03) if gust == "mil" else float(gust)
	var c := FlightRig.conditions_with_wind(spd, 90.0, g)
	var rig := FlightRig.from_class(cls, c, 3, Vector3(0, 10, 0))
	if model == "first":
		rig.wind = Wind.new(c, c.gust_tau_s, 3, Wind.Model.FIRST_ORDER)
		rig.core.wind = rig.wind
	rig.nav.set_hold(Vector2.ZERO)
	rig.nav.set_altitude_msl(10.0)
	var worst_z := 0.0; var sum2 := 0.0; var n := 0; var worst_r := 0.0
	for k in int(secs * 500):
		rig.step()
		if k > 20 * 500:
			var p := rig.position()
			var ez := p.y - 10.0
			worst_z = maxf(worst_z, absf(ez)); sum2 += ez * ez; n += 1
			worst_r = maxf(worst_r, Vector2(p.x, p.z).length())
	print("SR2 hold %s %s mph %.1f m/s sigma_u %.2f %s: alt max %.2f m rms %.2f m, radius max %.2f m" % [cls, "%.0f" % mph, spd, g, model, worst_z, sqrt(sum2 / n), worst_r])
	quit()
