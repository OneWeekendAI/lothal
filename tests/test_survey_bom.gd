class_name TestSurveyBom
extends RefCounted
## Per-part BOM (cross-check phase C): one row per part, split from the Build's own mass_parts (motors, props, frame, ESC, FC,
## each harness lead, components, and the payload add-ons by part), so the sheets' "674 g by subtraction" lump is itemised.
## FAIL-PROOF (seen red 2026-11-13): with rows() a stub returning [] every reconcile case FAILED (sum 0 vs ~1911 g); with the
## harness rows dropped the reconcile cases FAIL by ~35 g; with the Payload lump kept instead of split the remote-id case FAILS.

const SurveyBom = preload("res://src/autopilot/survey_bom.gd")


static func run() -> Array:
	var out: Array = []
	var cat := PartsCatalog.load_default()
	for name in SurveyBom.VARIANTS:
		var made := SurveyKitBuilds.make(SurveyBom.VARIANTS[name], cat)
		var rows: Array = SurveyBom.rows(name, made, cat)
		var s := 0.0
		for r in rows:
			s += float(r["total_mass_g"])
		var total := (made["build"] as Build).mass_properties.total_mass_kg * 1000.0
		out.append(TestResult.new("survey bom: %s rows sum to the build's total mass within 1 g" % name, rows.size() >= 10 and absf(s - total) <= 1.0, "rows %d sum %.2f total %.2f" % [rows.size(), s, total]))
	var base: Array = SurveyBom.rows("base", SurveyKitBuilds.make(SurveyBom.VARIANTS["base"], cat), cat)
	var roles := {}
	for r in base:
		roles[String(r["role"])] = true
	var need := ["frame", "motor", "prop", "ESC", "FC", "wiring/harness", "camera kit", "RTK GNSS", "pack"]
	var missing := need.filter(func(x): return not roles.has(x))
	out.append(TestResult.new("survey bom: the baseline itemises frame, motor x4, prop x4, ESC, FC, harness, camera kit, RTK and pack", missing.is_empty(), "missing %s" % str(missing)))
	var rid: Array = SurveyBom.rows("rid", SurveyKitBuilds.make(SurveyBom.VARIANTS["base_remote_id"], cat), cat)
	var hit := rid.filter(func(r): return String(r["part_id"]) == "rid_dronetag_beacon" and absf(float(r["total_mass_g"]) - 16.0) < 1e-6 and String(r["role"]) == "Remote ID")
	out.append(TestResult.new("survey bom: the Remote ID variant lists the Dronetag Beacon as its own 16 g row (not a payload lump)", hit.size() == 1, str(hit)))
	var motors := base.filter(func(r): return String(r["role"]) == "motor")
	out.append(TestResult.new("survey bom: motors are one row of qty 4 at the catalog unit mass", motors.size() == 1 and int(motors[0]["qty"]) == 4 and absf(float(motors[0]["total_mass_g"]) - 4.0 * float(motors[0]["unit_mass_g"])) < 1e-6, str(motors)))
	return out
