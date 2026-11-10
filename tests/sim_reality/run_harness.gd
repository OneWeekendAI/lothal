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
	var gate := false
	var quick := false
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
		elif a == "--quick":
			# SR0.3: Mavic hover only at a 100 Hz step. Per-change gate, not a validation run.
			quick = true
			only = "mavic_3m"
			SimRealityHarness.step_dt = SimRealityHarness.QUICK_DT
		elif a.begins_with("--dt="):
			SimRealityHarness.step_dt = float(a.get_slice("=", 1))
		elif a == "--gate":
			gate = true   # strict exit: ANY row out of band fails, context rows included (fail-proofs)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	var rows: Array = []
	for ref in SimRealityHarness.load_references():
		if only != "" and String(ref["id"]) != only:
			continue
		for case_name in ref["cases"]:
			if quick and case_name != "hover":
				continue
			rows.append(SimRealityHarness.row(ref, case_name, scale))
	print("")
	print("SIM REALITY HARNESS (SR0)  capacity_scale=%.2f  dt=%.4f s  cutoff=loaded cell V below min for %.1f s or capacity used" % [scale, SimRealityHarness.step_dt, SimRealityHarness.CUTOFF_HOLD_S])
	print(SimRealityHarness.format_table(rows))
	# Owner direction 2026-11-09/10: published whole-aircraft times are marketing-optimistic CONTEXT.
	# Out of band is a flagged warning and does not fail the run; --gate makes it fail.
	var in_band := 0
	var invalid := 0
	for r in rows:
		if not bool(r["result"]["valid"]):
			invalid += 1
		if r["in_band"]:
			in_band += 1
	print("")
	for w in SimRealityHarness.context_warnings(rows):
		print(w)
	print("%d of %d cases within the optimistic published band (context only unless --gate); %d invalid flights" % [in_band, rows.size(), invalid])
	var failed_tests := 0
	if scale == 1.0 and only == "":
		for result in TestSimReality.run(gate):
			if not result.passed:
				failed_tests += 1
			print("[%s] %s (%s)" % ["PASS" if result.passed else "FAIL", result.name, result.detail])
		for result in TestSimRealityLogic.run():
			if not result.passed:
				failed_tests += 1
			print("[%s] %s (%s)" % ["PASS" if result.passed else "FAIL", result.name, result.detail])
	quit(SimRealityHarness.exit_code(rows, failed_tests, gate))
