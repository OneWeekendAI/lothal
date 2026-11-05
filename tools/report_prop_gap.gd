extends SceneTree
## Prints the measured-gap table for PROP_DESIGNER.md from the real Rust solve.

func _init() -> void:
	var all := PropGap.props()
	for id in all:
		var m := PropGap.measured_figures(all[id])
		var f := PropGap.model_figures(all[id])
		print("%s @%d measured ct %.4f cp %.4f eta %.3f@%.2f j0 %.3f" % [id, all[id]["run_rpm"], m.ct, m.cp, m.eta, m.eta_j, m.j0])
		print("   model    ct %.4f cp %.4f eta %.3f@%.2f j0 %.3f" % [f.ct, f.cp, f.eta, f.eta_j, f.j0])
		print("   ratio    ct %.3f cp %.3f eta %.3f eta_j %.3f j0 %.3f" % [f.ct / m.ct, f.cp / m.cp, f.eta / m.eta, f.eta_j / m.eta_j, f.j0 / m.j0])
	quit()
