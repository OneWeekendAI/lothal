class_name TestAssetLedger
extends RefCounted
## The licence ledger (ASSETS.txt): every shipped file under assets/ has one row, with an allowed licence.
## Mirrors tools/check_assets.py. The checker is a pure function (ledger text + file list), so the
## fixture tests can prove it refuses what it must without touching the disk.
##
## Why the fixtures: a checker that returned "clean" for everything would pass the real-tree checks
## above them. Each fixture feeds a deliberately bad ledger and requires the matching failure.

const ALLOWED := ["CC0-1.0", "GPL-3.0-or-later (own work)"]
const LEDGER := "res://ASSETS.txt"
const KINDS := ["malformed", "licence", "duplicate", "unlisted", "missing"]


static func check(ledger_text: String, files: PackedStringArray) -> Dictionary:
	var errs := {"malformed": [], "licence": [], "duplicate": [], "unlisted": [], "missing": []}
	var seen := {}
	var date_re := RegEx.new()
	date_re.compile("^\\d{4}-\\d{2}-\\d{2}$")
	var n := 0
	for raw in ledger_text.split("\n"):
		n += 1
		var line: String = raw.trim_suffix("\r")
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var cols := line.split("\t")
		var path := cols[0]
		var ok := cols.size() == 5 and path.begins_with("assets/") and not path.ends_with("/") \
				and not ("*" in path or "?" in path or "[" in path) and date_re.search(cols[4]) != null
		if ok:
			for c in cols:
				if c.strip_edges() == "":
					ok = false
		if not ok:
			errs["malformed"].append("line %d: %s" % [n, line.substr(0, 80)])
			continue
		if not (cols[3] in ALLOWED):
			errs["licence"].append("line %d: %s has licence '%s'" % [n, path, cols[3]])
		if seen.has(path):
			errs["duplicate"].append("line %d: %s (first on line %d)" % [n, path, seen[path]])
		seen[path] = n
	var fileset := {}
	for f in files:
		fileset[f] = true
		if not seen.has(f):
			errs["unlisted"].append("not in ledger: %s" % f)
	for p in seen:
		if not fileset.has(p):
			errs["missing"].append("row for missing file: %s" % p)
	return errs


static func walk(dir_path: String = "res://assets") -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.include_hidden = true
	for f in d.get_files():
		if not f.ends_with(".import"):
			out.append((dir_path + "/" + f).trim_prefix("res://"))
	for sub in d.get_directories():
		out.append_array(walk(dir_path + "/" + sub))
	return out


static func _joined(msgs: Array) -> String:
	return "none" if msgs.is_empty() else "%d: %s" % [msgs.size(), "; ".join(msgs.slice(0, 5))]


static func run() -> Array:
	var results: Array = []
	var files := walk()
	var text := FileAccess.get_file_as_string(LEDGER)
	results.append(TestResult.new("ledger file exists and the tree is not empty", text != "" and files.size() > 0,
		"ledger %d bytes, %d files under assets/" % [text.length(), files.size()]))
	var errs := check(text, files)
	for kind in KINDS:
		results.append(TestResult.new("ledger real tree: no %s rows/files" % kind, errs[kind].is_empty(), _joined(errs[kind])))

	# fixtures: pure checker against bad ledgers
	var good := "# header\nassets/a.glb\tme\tsrc\tCC0-1.0\t2026-01-01\nassets/b.png\tme\tsrc\tGPL-3.0-or-later (own work)\t2026-01-02\n"
	var both := PackedStringArray(["assets/a.glb", "assets/b.png"])
	var clean := check(good, both)
	var all_clean := true
	for k in KINDS:
		all_clean = all_clean and clean[k].is_empty()
	results.append(TestResult.new("fixture: a correct ledger is accepted", all_clean, str(clean)))
	var unl := check(good, PackedStringArray(["assets/a.glb", "assets/b.png", "assets/models/parts/zz_unlisted.glb"]))
	results.append(TestResult.new("fixture: an unlisted file is refused", unl["unlisted"].size() == 1 and "zz_unlisted" in unl["unlisted"][0], str(unl["unlisted"])))
	var nc := check(good.replace("CC0-1.0", "CC-BY-NC-4.0"), both)
	results.append(TestResult.new("fixture: a disallowed licence (CC-BY-NC-4.0) is refused", nc["licence"].size() == 1 and "CC-BY-NC-4.0" in nc["licence"][0], str(nc["licence"])))
	var gone := check(good, PackedStringArray(["assets/a.glb"]))
	results.append(TestResult.new("fixture: a row for a missing file is refused", gone["missing"].size() == 1 and "b.png" in gone["missing"][0], str(gone["missing"])))
	var dup := check(good + "assets/a.glb\tme\tsrc\tCC0-1.0\t2026-01-01\n", both)
	results.append(TestResult.new("fixture: a duplicate row is refused", dup["duplicate"].size() == 1, str(dup["duplicate"])))
	var bad_rows := ["assets/*\tme\tsrc\tCC0-1.0\t2026-01-01", "assets/a.glb\tme\tsrc\tCC0-1.0", "assets/a.glb\tme\tsrc\tCC0-1.0\tyesterday", "other/a.glb\tme\tsrc\tCC0-1.0\t2026-01-01"]
	var all_refused := true
	for row in bad_rows:
		var m := check(row + "\n", both)
		all_refused = all_refused and m["malformed"].size() == 1
	results.append(TestResult.new("fixture: glob, short, bad-date and out-of-tree rows are malformed", all_refused, "4 rows tried"))
	return results
