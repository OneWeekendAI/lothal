class_name TestSr6SimStyle
extends RefCounted
## SR6 / L3.1+L3.2: the Sim screen (DsHud, plus main.gd which builds it) carries no blue of its own; it uses Design Space tokens
## (DesignSpace.INK / INK_MUTED / INK_FAINT / SELECT_INK, the monochrome studio palette). Two cases: no blue-dominant Color(...)
## literal (b >= r+0.25 and b >= g+0.1), and no reference to a LothalTheme blue token or a *BLUE* name.
## Design Space's own accents are not scanned. FAIL-PROOFS observed 2026-11-10: RED before the fix = 0 literals, 1 named-blue
## reference (src/ui/hud.gd (now src/design/ds_hud.gd) line 36, COLOR_ACCENT := LothalTheme.ACCENT, used for the gate label and banner). GREEN after the fix.
## MT: a literal Color(0.2, 0.4, 0.9) injected into the scanned text makes the literal case FAIL (checked through _blue_literals).

const FILES := ["res://src/design/ds_hud.gd", "res://src/scenes/main.gd"]
const BLUE_TOKENS := ["LothalTheme.ACCENT", "LothalTheme.BORDER_FOCUS", "BLUE"]


static func run() -> Array:
	var lit: Array = []
	var named: Array = []
	for f in FILES:
		var txt := FileAccess.get_file_as_string(f)
		lit.append_array(_blue_literals(f, txt))
		named.append_array(_blue_names(f, txt))
	var mutant := _blue_literals("mutant", "var c := Color(0.2, 0.4, 0.9)\n")
	return [
		TestResult.new("sr6 sim style: no blue-dominant Color literal in the Sim screen files", lit.is_empty(), "%d: %s" % [lit.size(), str(lit)]),
		TestResult.new("sr6 sim style: no LothalTheme blue token or named blue in the Sim screen files", named.is_empty(), "%d: %s" % [named.size(), str(named)]),
		TestResult.new("sr6 sim style: the literal scanner does flag a blue literal (it can fail)", mutant.size() == 1, str(mutant)),
	]


static func _code_lines(txt: String) -> Array:
	var out: Array = []
	var n := 0
	for line in txt.split("\n"):
		n += 1
		var s := String(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append([n, s])
	return out


static func _blue_literals(file: String, txt: String) -> Array:
	var found: Array = []
	var re := RegEx.new()
	re.compile("Color\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)")
	for pair in _code_lines(txt):
		for m in re.search_all(pair[1]):
			var r := float(m.get_string(1))
			var g := float(m.get_string(2))
			var b := float(m.get_string(3))
			if b >= r + 0.25 and b >= g + 0.1:
				found.append("%s:%d %s" % [file, pair[0], m.get_string()])
	return found


static func _blue_names(file: String, txt: String) -> Array:
	var found: Array = []
	for pair in _code_lines(txt):
		for t in BLUE_TOKENS:
			if String(pair[1]).contains(t):
				found.append("%s:%d %s" % [file, pair[0], t])
	return found
