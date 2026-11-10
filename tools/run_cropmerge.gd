extends SceneTree
## L5.1 CLI: see tools/run_cropmerge.sh. Exit 0 printed both rows, 2 usage error.

const USAGE := "usage: tools/run_cropmerge.sh [--n=8] [--seed=1]"
const CLASSES := ["mapper", "mavic_3m"]


func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg or not String(arg.substr(2).get_slice("=", 0)) in ["n", "seed"]:
			print("bad argument '%s'\n%s" % [arg, USAGE])
			quit(2)
			return
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var n := int(a.get("n", "8"))
	var seed_value := int(a.get("seed", "1"))
	var w := WorldPresets.by_id("illinois_corn_july")
	if w == null or n < 1:
		print("cannot load the Illinois world or n < 1\n" + USAGE)
		quit(2)
		return
	var field := w.polygon_sim()
	var acres := w.area_acres()
	print("")
	print("CROPMERGE acres per battery  world %s (%s)  field %.1f acres  n %d  master seed %d" % [w.world_id, w.world_name, acres, n, seed_value])
	print("  wind 10-20 mph (15 +- 5) and pack capacity +-5 percent, other tolerances off; the world supplies the polygon, the wind is the example's range")
	for cid in CLASSES:
		var t0 := Time.get_ticks_msec()
		var c := Sensitivity.cropmerge_example(cid, field, acres, n, seed_value)
		var row: Dictionary = c["row"]
		var ab: Dictionary = row["acres_per_battery"]
		var pub: Dictionary = row["published"]
		var nom: Dictionary = c["nominal"]
		var trail: Dictionary = row["trail"]
		print("")
		print("  class %s%s" % [cid, "  (reference build)" if cid == "mavic_3m" else ""])
		print("    acres per battery  %.0f-%.0f (mid %.0f)  [%s]  10th-90th percentile of %d flights" % [ab["low"], ab["high"], ab["mid"], ab["tag"], ab["n"]])
		print("    published claim    %.0f-%.0f acres/battery  [%s, optimistic; context only]" % [pub["low"], pub["high"], pub["tag"]])
		print("    area               %.1f acres mapped  [%s]  basis: %s" % [row["area"]["mapped_acres"], row["area"]["tag"], row["area"]["basis"]])
		print("    batteries used     %.2f  [%s]%s" % [row["batteries_used"]["value"], row["batteries_used"]["tag"], "  (part pack: acres per battery EXTRAPOLATED)" if nom["extrapolated"] else ""])
		print("    flight time        %.1f s (%.1f min), %d sortie(s), %s  [%s]" % [row["flight_time"]["value_s"], row["flight_time"]["value_s"] / 60.0, nom["sorties"], "completed" if nom["completed"] else "NOT COMPLETED (ended by %s)" % nom["ended_by"], row["flight_time"]["tag"]])
		print("    trail              build %s | world %s %s | seed %d (master %d) | model %s" % [trail["build_fingerprint"], w.world_id, w.fingerprint(), trail["seed"], trail["master_seed"], trail["model_version"]])
		print("    wall time          %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
