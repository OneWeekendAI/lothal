class_name TestPropGap
extends RefCounted
## PD1: how far the shipped model sits from UIUC wind-tunnel tables, as tripwires. Each band is
## today's model/measured ratio +-0.05. They are not accuracy claims: they say the gap the page
## reports is still the gap, so a band moves only with a logged reason in PROP_TRACKER.md.
## tools/report_prop_gap.gd prints the figures.
##
## TO MAKE THIS FAIL: multiply a fixture's CT column by 1.5.

const BANDS := {
	"apcff_4.2x4": {"ct": 0.864, "cp": 0.567, "eta": 0.898, "eta_j": 0.793, "j0": 0.906},
	"da4002_5x3.75": {"ct": 0.937, "cp": 0.737, "eta": 0.725, "eta_j": 0.762, "j0": 0.841},
	"apce_9x4.5": {"ct": 0.765, "cp": 0.929, "eta": 0.581, "eta_j": 0.651, "j0": 0.759},
}
const HALF_WIDTH := 0.05


static func run() -> Array:
	var results: Array = []
	var all := PropGap.props()
	results.append(TestResult.new("prop gap: all three measured props present",
		all.size() == BANDS.size() and all.has_all(BANDS.keys()), str(all.keys())))
	for id in BANDS:
		if not all.has(id):
			continue
		var m := PropGap.measured_figures(all[id])
		var f := PropGap.model_figures(all[id])
		for k in BANDS[id]:
			var ratio: float = float(f[k]) / float(m[k]) if float(m[k]) != 0.0 else INF
			results.append(TestResult.new("prop gap: %s model/measured %s within band" % [id, k],
				absf(ratio - float(BANDS[id][k])) <= HALF_WIDTH,
				"%.3f vs band %.3f" % [ratio, BANDS[id][k]]))
	return results
