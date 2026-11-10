class_name TestDragRange
extends RefCounted
## Drag item (2026-11-10). FINDING: the sim's mapper / Mavic 3M-like body has frontal Cd*A 0.0107 m2 (0.009 x (arm/0.11)^2 x 0.4),
## NOT the 0.0036 the earlier handover quoted (that was the 0.11 m arm value). Only the mapper class and the mavic_3m reference are
## streamlined; the other ten classes are open frames and are untouched. Against NASA Ames's Phantom 3 airframe 0.020 m2 the sim is
## 1.9x lower, inside a range [0.5 x nominal, 0.020]. Nominal unchanged, so no golden moved.
## FAIL-PROOF (observed 2026-11-10): with drag_front_range_m2 returning low=high=nominal for streamlined bodies the range cases FAIL.

static func run() -> Array:
	var out: Array = []
	var cat := PartsCatalog.load_default()
	var pf := DroneClass.parts_for("mapper")
	var m := Build.from_ids(cat, pf["frame"], pf["motor"], pf["propeller"], pf["battery"], pf["esc"], pf["flight_controller"])
	var r := m.drag_front_range_m2()
	out.append(TestResult.new("drag range: mapper (streamlined) low < nominal < high, nominal is the Build's own frontal Cd*A",
		r["low"] < r["nominal"] and r["nominal"] < r["high"] and absf(float(r["nominal"]) - m.drag_cda_m2.z) < 1e-6, str(r)))
	out.append(TestResult.new("drag range: mapper high is the cited Phantom 3 figure 0.020 m2 and the source names NASA and a ceiling",
		float(r["high"]) == 0.020 and str(r["source"]).contains("NASA") and str(r["source"]).contains("ceiling") and r["tag"] == "estimated", str(r["source"]).left(60)))
	out.append(TestResult.new("drag range: the default +-20 percent drag tolerance does NOT reach the sourced ceiling (so the range is real news)",
		float(r["nominal"]) * 1.2 < float(r["high"]), "%.4f x1.2 vs %.4f" % [r["nominal"], r["high"]]))
	var q := DroneClass.parts_for("five_inch")
	var f := Build.from_ids(cat, q["frame"], q["motor"], q["propeller"], q["battery"], q["esc"], q["flight_controller"])
	var rf := f.drag_front_range_m2()
	out.append(TestResult.new("drag range: an open frame carries no range (low == nominal == high)", not rf.is_empty() and rf["low"] == rf["nominal"] and rf["nominal"] == rf["high"], str(rf)))
	return out
