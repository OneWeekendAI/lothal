class_name TestStlBodies
extends RefCounted
## StlWriter checks each body on its own — printed-room slice PR13 (plan, "Third wave").
##
## Where each check could pass while proving nothing, and what stops it:
##   - "touching bodies are accepted" means nothing unless the SAME triangles are what the old whole-file
##     check refused. So the fixture is asserted refused by `check_manifold` first, then accepted by
##     `check_bodies`: the test pins the behaviour it replaces.
##   - "a mis-wound face is still refused" uses the same two cubes with ONE facet flipped in ONE body,
##     so only a check that is strict inside each body can refuse it, and it must name body 2.
##   - "a frame exports" writes through the room export and compares the bytes in the drone with the file
##     on disk, with the directory cleared first.

const DIR := "user://exports/_test_stl_bodies"


static func run() -> Array:
	var results: Array = []
	results.append_array(_touching_bodies_were_refused_and_are_now_accepted())
	results.append(_a_flipped_facet_in_one_body_is_refused_by_body())
	results.append(_an_open_body_is_refused())
	results.append(_no_bodies_or_an_empty_body_is_refused())
	results.append(_a_refused_body_set_writes_no_file())
	results.append_array(_a_printable_frame_exports_end_to_end())
	results.append(_a_pad_is_its_own_body())
	return results


## No catalog frame has a pad, so a dropped pad is invisible to every frame fixture. A document with one
## pad (a copy of its first plate) must come back as one more body, with FrameExport's full facet count.
static func _a_pad_is_its_own_body() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var document := AirframeDocument.from_catalog_frame(catalog.get_part("frame_3in_toothpick"))
	document.pads = [(document.plates[0] as Dictionary).duplicate(true)] if not document.plates.is_empty() else []
	var bodies := PrintedParts.document_bodies_mm(document)
	var facets := FrameExport.to_stl(document).count("facet normal")
	var report := StlWriter.check_bodies(bodies)
	return TestResult.new("a document with one pad is plates + 1 bodies, together FrameExport's own facets, each closed",
		document.pads.size() == 1 and bodies.size() == document.plates.size() + 1
			and int(report.get("triangle_count", 0)) == facets and bool(report.get("ok", false)),
		"%d bodies for %d plates, %d triangles vs %d facets, reasons %s" % [bodies.size(), document.plates.size(),
			report.get("triangle_count", 0), facets, report.get("reasons", [])])


## A cube of side `s` with its low corner at `origin`, wound outward. Hand-listed, as TestStlWriter's.
static func _cube(s: float, origin: Vector3) -> Array:
	var v := [
		Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, 0),
		Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s),
	]
	var faces := [[0, 3, 2], [0, 2, 1], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4],
		[3, 7, 6], [3, 6, 2], [0, 4, 7], [0, 7, 3], [1, 2, 6], [1, 6, 5]]
	var out: Array = []
	for face in faces:
		out.append(PackedVector3Array([v[face[0]] + origin, v[face[1]] + origin, v[face[2]] + origin]))
	return out


## Two 10 mm cubes, the second sitting on the first's +X face: they share that face's four edges exactly.
static func _touching() -> Array:
	return [_cube(10.0, Vector3.ZERO), _cube(10.0, Vector3(10.0, 0.0, 0.0))]


static func _flat(bodies: Array) -> Array:
	var out: Array = []
	for body in bodies:
		out.append_array(body)
	return out


static func _touching_bodies_were_refused_and_are_now_accepted() -> Array:
	var whole := StlWriter.check_manifold(_flat(_touching()))
	var per_body := StlWriter.check_bodies(_touching())
	return [
		TestResult.new("two cubes sharing a face are refused by the whole-file check — the behaviour this slice replaces",
			not bool(whole["ok"]) and ", ".join(PackedStringArray(whole["reasons"])).contains("winding is inconsistent"),
			"ok %s, %s" % [whole["ok"], whole["reasons"]]),
		TestResult.new("and accepted when each cube is checked as its own body, with both volumes counted",
			bool(per_body.get("ok", false)) and absf(float(per_body.get("volume_mm3", 0.0)) - 2000.0) < 1e-6
				and int(per_body.get("triangle_count", 0)) == 24,
			"ok %s, %.3f mm³, %d triangles, reasons %s" % [per_body.get("ok"), per_body.get("volume_mm3", 0.0),
				per_body.get("triangle_count", 0), per_body.get("reasons", [])]),
	]


static func _a_flipped_facet_in_one_body_is_refused_by_body() -> TestResult:
	var bodies := _touching()
	var second: Array = bodies[1]
	var t: PackedVector3Array = second[4]
	second[4] = PackedVector3Array([t[0], t[2], t[1]])
	var report := StlWriter.check_bodies(bodies)
	var reasons := ", ".join(PackedStringArray(report.get("reasons", [])))
	return TestResult.new("one facet flipped inside the second cube is still refused, and the reason names body 2",
		not bool(report.get("ok", true)) and reasons.contains("body 2") and not reasons.contains("body 1")
			and reasons.contains("winding is inconsistent"),
		reasons)


static func _an_open_body_is_refused() -> TestResult:
	var bodies := _touching()
	(bodies[0] as Array).remove_at(0)
	var report := StlWriter.check_bodies(bodies)
	var reasons := ", ".join(PackedStringArray(report.get("reasons", [])))
	return TestResult.new("a body with a facet missing is refused as not closed, naming body 1",
		not bool(report.get("ok", true)) and reasons.contains("body 1") and reasons.contains("not closed"),
		reasons)


static func _no_bodies_or_an_empty_body_is_refused() -> TestResult:
	var none := StlWriter.check_bodies([])
	var one_empty := StlWriter.check_bodies([_cube(10.0, Vector3.ZERO), []])
	return TestResult.new("no bodies at all is refused, and so is a set with an empty body in it",
		not bool(none.get("ok", true)) and not bool(one_empty.get("ok", true))
			and ", ".join(PackedStringArray(one_empty.get("reasons", []))).contains("body 2"),
		"none %s; one empty %s" % [none.get("reasons", []), one_empty.get("reasons", [])])


static func _a_refused_body_set_writes_no_file() -> TestResult:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("_refused_bodies.stl")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bodies := _touching()
	(bodies[1] as Array).remove_at(3)
	var result := StlWriter.write_bodies("two_cubes", bodies, path)
	return TestResult.new("a refused body set writes no file, and the reason names the part first",
		not bool(result.get("ok", true)) and String(result.get("reason", "")).begins_with("two_cubes:")
			and not FileAccess.file_exists(path),
		String(result.get("reason", "")))


static func _a_printable_frame_exports_end_to_end() -> Array:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	var catalog := PartsCatalog.load_default()
	var frame := catalog.get_part("frame_3in_toothpick").duplicate(true)
	frame["fabrication"] = "either"
	var build := ReferenceBuild.build()
	build.frame = frame
	var bodies := PrintedParts.frame_bodies_mm(frame)
	var per_body := StlWriter.check_bodies(bodies)
	var facets := FrameExport.to_stl(AirframeDocument.from_catalog_frame(frame)).count("facet normal")
	var container := ProjectContainer.make(Project.create("Printed frame"))
	var result := PrintedExport.export_part(build, PrintedParts.FRAME, DIR, container)
	var record: Dictionary = result.get("record", {})
	var on_disk := String(record.get("exported_to", ""))
	var disk_sha := FileAccess.get_file_as_string(on_disk).sha256_text() if on_disk != "" and FileAccess.file_exists(on_disk) else ""
	var member_sha := container.member_bytes(String(record.get("file", ""))).get_string_from_utf8().sha256_text()
	return [
		TestResult.new("the toothpick frame is six plate bodies, each closed on its own, together the frame export's own facets",
			bodies.size() == 6 and bool(per_body.get("ok", false)) and int(per_body.get("triangle_count", 0)) == facets,
			"%d bodies, ok %s, %d triangles vs %d facets, reasons %s" % [bodies.size(), per_body.get("ok"),
				per_body.get("triangle_count", 0), facets, per_body.get("reasons", [])]),
		TestResult.new("marked either, it exports through the room export: one record, and the drone holds the bytes on disk",
			bool(result.get("ok", false)) and String(record.get("part", "")) == "frame"
				and container.project.print_records.size() == 1 and disk_sha != "" and member_sha == disk_sha
				and String(record.get("geometry_sha256", "")) == disk_sha,
			"ok %s, reason %s, disk %s…, member %s…" % [result.get("ok"), result.get("reason", ""),
				disk_sha.substr(0, 12), member_sha.substr(0, 12)]),
	]
