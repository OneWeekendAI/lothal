class_name TestPropCapability
extends RefCounted
## PD13: the spec's old-to-new capability map, row by row. Each row names the tests that prove it;
## this suite goes red on a blank row or on a named test that no longer exists in its file. Those
## tests run in their own suites. Row order follows PROP_DESIGNER.md.

const D := "test_prop_designer"

const ROWS := [
	{"old": "New blade from a prop", "home": "+ tile, start-from", "proof": [[D, "the prop shelf ends with a + tile"], [D, "it starts from this drone's prop"]]},
	{"old": "Save draft, Publish", "home": "One Save", "proof": [[D, "a save returns a custom id"], [D, "chord comes back bit-exact"]]},
	{"old": "Duplicate", "home": "Save as new", "proof": [[D, "Save as new makes a second prop"], [D, "the one opened is untouched"]]},
	{"old": "Stations, drag chord, caret", "home": "Chord canvas", "proof": [[D, "chord + station"], [D, "chord - station"], [D, "chord drag moves mass"], [D, "the chord canvas moves the twist canvas's caret"]]},
	{"old": "Measured-chord toggle", "home": "Blade section", "proof": [[D, "a drawn chord stops being assumed, and the toggle shows it"], [D, "toggle sets it back"]]},
	{"old": "Undo, redo, Ctrl-Z", "home": "Top bar", "proof": [[D, "undo restores every figure bit-exact"], [D, "Ctrl-Z undoes a hub edit"], [D, "Ctrl-Shift-Z redoes it"]]},
	{"old": "Pitch with authored-twist refusal", "home": "Size", "proof": [[D, "on drawn twist, pitch stays authored"], [D, "a helix blade is not offered anything"]]},
	{"old": "Design-rpm slider", "home": "Tunnel rpm and figures", "proof": [[D, "rpm: opens on the rated rpm at the design fraction"], [D, "rpm control moves the curve"], [D, "rpm control moves the figures too"]]},
	{"old": "Pad slider, motor max", "home": "Hub & material", "proof": [[D, "pad stops at the motor's boss height"]]},
	{"old": "Mount profile, soft-mount Hz", "home": "Structure, Details", "proof": [[D, "mount: details give the soft-mount Hz"], [D, "mount: the profile draws the pad"]]},
	{"old": "3D orbit, snaps, stopped mesh, rings", "home": "Middle view", "proof": [[D, "view: a drag orbits the blade"], [D, "%s view button turns the camera"], [D, "view: the mesh stands still"], [D, "view: the caret ring is drawn"]]},
	{"old": "Section view with caption", "home": "Middle", "proof": [[D, "the section draws the designer's document"], [D, "and the caption"]]},
	{"old": "g/W, thrust, FM, capped-to, alpha, refusal", "home": "Tunnel Details", "proof": [[D, "details: g/W is BladeAero's"], [D, "details: thrust is BladeAero's"], [D, "details: FM is BladeAero's"], [D, "details: capped-to is BladeAero's"], [D, "details: the alpha curve has a point per lifting station"], [D, "details: a refusal reaches the panel as a refusal"]]},
	{"old": "Saved list, preset chips", "home": "Prop shelf, tiles", "proof": [[D, "a saved prop reaches the shelf's catalog"], [D, "the shelf prop's record is unchanged"]]},
	{"old": "Typed custom prop", "home": "Custom entry", "proof": [[D, "the designer has a typed entry"], [D, "and is marked typed"], [D, "the dialog reports a failed write"]]},
	{"old": "Prop inspector blade rows", "home": "Inspector's Open sheet", "proof": [["test_propulsion_panel", "_test_every_blade_row_renders_for_every_prop"], ["test_part_sheet", "Open sheet on the battery opens the battery's sheet"]]},
	{"old": "Delete", "home": "Two-press on the card", "proof": [[D, "the first delete press only arms"], [D, "the second press deletes"]]},
]
## 17: the "Five analysis overlays" row went with the overlays themselves (deleted in R9), not with a test.
const SPEC_ROWS := 17


static func run() -> Array:
	var out: Array = []
	out.append(TestResult.new("capability map: every spec row is here", ROWS.size() == SPEC_ROWS, str(ROWS.size())))
	var sources := {}
	for row: Dictionary in ROWS:
		var proof: Array = row.proof
		out.append(TestResult.new("capability map: %s has a home and a proof" % row.old, String(row.home) != "" and not proof.is_empty(), ""))
		for p: Array in proof:
			if not sources.has(p[0]):
				sources[p[0]] = FileAccess.get_file_as_string("res://tests/%s.gd" % p[0])
			out.append(TestResult.new("capability map: %s names a test that exists: %s" % [row.old, p[1]], String(p[1]) in String(sources[p[0]]), ""))
	return out
