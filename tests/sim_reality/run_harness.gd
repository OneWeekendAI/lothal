extends SceneTree
## SR0 entry point. One command, headless, pass/fail exit code:
##   tools/run_sim_reality.sh            (all references, honest table, exit 1 if any is out of band)
## or directly:
##   godot --headless --script res://tests/sim_reality/run_harness.gd [-- --capacity-scale=0.7 --only=<id>]
## Exit 0 only if every reference is in band AND every per-aircraft test passes. A red result is a
## finding about the sim, not a harness bug (see the SR0 section of the sim-reality plan).

func _init() -> void:
	var scale := 1.0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capacity-scale="):
			scale = float(a.get_slice("=", 1))
		elif a.begins_with("--field="):
			# --field=none | --field=avionics,esc,thermal,battery (only those on)
			var v := a.get_slice("=", 1)
			if v == "none":
				SimRealityHarness.field_opts = {"off": true}
			else:
				var on := v.split(",")
				SimRealityHarness.field_opts = {}
				for k in ["avionics", "esc", "thermal", "battery"]:
					SimRealityHarness.field_opts[k] = k in on
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	var rows: Array = []
	for ref in SimRealityHarness.load_references():
		if only != "" and String(ref["id"]) != only:
			continue
		for case_name in ref["cases"]:
			rows.append(SimRealityHarness.row(ref, case_name, scale))
	print("")
	print("SIM REALITY HARNESS (SR0)  capacity_scale=%.2f  dt=%.4f s  cutoff=loaded cell V below min for %.1f s or capacity used" % [scale, SimRealityHarness.DT, SimRealityHarness.CUTOFF_HOLD_S])
	print(SimRealityHarness.format_table(rows))
	# Owner direction 2026-11-09: published whole-aircraft times are marketing-optimistic CONTEXT, so
	# the exit code no longer depends on them. It depends on the flight being valid and the tests.
	var bad := 0
	var in_band := 0
	for r in rows:
		if not bool(r["result"]["valid"]):
			bad += 1
		if r["in_band"]:
			in_band += 1
	print("")
	print("%d of %d cases within the optimistic published band (context only); %d invalid flights" % [in_band, rows.size(), bad])
	var failed_tests := 0
	if scale == 1.0 and only == "":
		for result in TestSimReality.run():
			if not result.passed:
				failed_tests += 1
			print("[%s] %s (%s)" % ["PASS" if result.passed else "FAIL", result.name, result.detail])
	quit(1 if (bad > 0 or failed_tests > 0) else 0)
