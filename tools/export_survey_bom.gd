extends SceneTree
## Writes the per-part BOM of every SurveyBom variant: one row per part (variant, role, part, qty, unit/total mass, power,
## source tag + URL/note). Totals reconcile with Build.mass_properties (tests/test_survey_bom.gd).
## usage: godot --headless --path . --script res://tools/export_survey_bom.gd -- --out=/abs/path/bom.csv

const SurveyBom = preload("res://src/autopilot/survey_bom.gd")


func _init() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	var cat := PartsCatalog.load_default()
	var lines := PackedStringArray([",".join(PackedStringArray(SurveyBom.COLUMNS))])
	for name in SurveyBom.VARIANTS:
		var made := SurveyKitBuilds.make(SurveyBom.VARIANTS[name], cat)
		var rows: Array = SurveyBom.rows(name, made, cat)
		var s := 0.0
		for r in rows:
			s += float(r["total_mass_g"])
		var total := (made["build"] as Build).mass_properties.total_mass_kg * 1000.0
		print("BOM\t%s\t%d rows\tsum %.2f g\tbuild %.2f g" % [name, rows.size(), s, total])
		lines.append_array(SurveyBom.csv_lines(rows))
	if out_path == "":
		print("\n".join(lines))
	else:
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("wrote ", out_path)
	quit(0)
