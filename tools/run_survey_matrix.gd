extends SceneTree
## Batch worker: runs the specs of a JSON array file (every `shards`-th one, starting at `shard`) and prints "ROW<TAB>index<TAB>csv line".
## usage: godot --headless --script res://tools/run_survey_matrix.gd -- --specs=file.json [--shard=0 --shards=1]
## Normally driven by tools/run_survey_matrix.sh, which shards across processes and writes the CSV.

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		a[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	var f := FileAccess.open(String(a.get("specs", "")), FileAccess.READ)
	if f == null:
		print("usage: --specs=file.json [--shard=i --shards=n]")
		quit(2)
		return
	var specs = JSON.parse_string(f.get_as_text())
	if not specs is Array:
		print("specs file must be a JSON array")
		quit(2)
		return
	var shard := int(a.get("shard", "0"))
	var shards := maxi(1, int(a.get("shards", "1")))
	for i in range(shard, specs.size(), shards):
		var t0 := Time.get_ticks_msec()
		var row := SurveyMatrix.run_spec(specs[i])
		print("ROW\t%d\t%s" % [i, SurveyMatrix.csv_line(row)])
		print("WALL\t%d\t%.1f" % [i, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
