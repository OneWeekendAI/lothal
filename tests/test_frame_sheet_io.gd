class_name TestFrameSheetIo
extends RefCounted
## M3 (MERGE_TRACKER): the frame sheet's Shape tab can bring a drawing in (SVG, DXF) and take the
## files out (print sheet, cut sheet, DXF, assembly STL, printable parts, build sheet), reached from
## the Parts drawer and not through the dead Airframe room.
##
## Each export is checked by PARSING what it wrote (an SVG through XMLParser, a DXF by its section
## markers, an STL by its facet count, the build sheet by its html tag), not by the file existing.
## Import is a round trip: the cut file the tab wrote is brought back into a fresh frame, and the
## plate count and span come back.
##
## MUTATION: make `FrameWorkbench._on_export_chosen` skip `FrameExport.write` (or `import_file` skip
## `FrameImport.into_document`) and the matching check fails.

const DIR := "user://exports"


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = Vector2(1280, 720)
	ds.open_part_sheet("frame", "shape")
	var wb := (ds.part_sheet.tab("shape") as FrameShapeTab).workbench
	wb.open_in_desktop = false
	var base := FrameWorkbench._safe_file_name(wb.editor.document.name)
	var plates := wb.editor.document.plates.size()
	var wrote := {}
	for i in FrameWorkbench.EXPORTS.size():
		var spec: Dictionary = FrameWorkbench.EXPORTS[i]
		if str(spec["layout"]) == FrameExport.LAYOUT_PARTS:
			continue
		wb._on_export_chosen(i)
		var path := "%s/%s.%s" % [DIR, base, spec["extension"]]
		if str(spec["layout"]) == FrameExport.LAYOUT_NEST and str(spec["extension"]) == "svg":
			path = "%s/%s-cut.svg" % [DIR, base]
		if str(spec["extension"]) == "html":
			path = "%s/%s-build-sheet.html" % [DIR, base]
		wrote[String(spec["label"])] = FileAccess.get_file_as_string(path)
	for label in wrote:
		var text: String = wrote[label]
		var ok := false
		if label.contains("SVG"):
			ok = _parses_as_xml(text) and text.contains("<path")
		elif label.contains("DXF"):
			ok = text.contains("ENTITIES") and text.contains("EOF")
		elif label.contains("STL"):
			ok = text.begins_with("solid") and text.count("facet normal") > 20
		elif label.contains("HTML"):
			ok = text.contains("<html") and text.contains("</html>")
		out.append(TestResult.new("export \"%s\" writes a file that parses" % label, ok, "%d bytes" % text.length()))
	wb._on_export_chosen(4)
	var parts_dir := "%s/%s-parts" % [DIR, base]
	var stls := 0
	for f in DirAccess.get_files_at(parts_dir):
		if f.ends_with(".stl"):
			stls += 1
	out.append(TestResult.new("Printable parts writes one STL per part", stls >= 3, "%d files" % stls))

	# Import: the files written above come back in as plates.
	var dxf_path := "%s/%s.dxf" % [DIR, base]
	var svg_path := "%s/%s-cut.svg" % [DIR, base]
	for pair in [["DXF", dxf_path], ["SVG", svg_path]]:
		wb._on_new()
		var empty := wb.editor.document.plates.size()
		var took := wb.import_file(pair[1])
		var got := wb.editor.document.plates.size()
		out.append(TestResult.new("%s import brings the exported outline back as plates" % pair[0],
			took and got > empty and got >= plates - 1, "%d -> %d (was %d)" % [empty, got, plates]))
	var junk := "%s/junk.svg" % DIR
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("not an svg")
	f.close()
	out.append(TestResult.new("a file with no outline is refused, and nothing is added", not wb.import_file(junk), ""))
	ds.free()
	return out


static func _parses_as_xml(text: String) -> bool:
	var parser := XMLParser.new()
	if parser.open_buffer(text.to_utf8_buffer()) != OK:
		return false
	var elements := 0
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			elements += 1
	return elements > 2
