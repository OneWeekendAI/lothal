class_name PrintedExport
extends RefCounted
## "Export printed parts…" — every part this drone prints, written out AND kept in the drone.
## Printed-room slice PR4 (plans/2026-09-14-printed-room-plan.md; persistence design §7.2–§7.4).
##
## ## A print is an event, so the drone keeps what was printed
##
## Each part that passes StlWriter is written twice, from the same text:
##
##   - to the exports folder, where a slicer can open it today;
##   - into the container as `printed/<name>-<first 8 of its sha256>.stl`, beside a **print record** on
##     `project.print_records` saying what, when, by which generator version, at which clearance, and
##     the hash of those exact bytes. Improving a generator later changes the picture; it cannot change
##     the part already bolted to the frame, and the record is how the app will notice (PR5).
##
## The hash names the member, so exporting an unchanged part twice writes the same member again and two
## records pointing at it — one per event, one file per distinct geometry.
##
## ## One refusal refuses only itself
##
## A part whose dimensions refuse, or whose solid StlWriter refuses, is named in `refused` with its
## reason and writes nothing anywhere. Every other part still writes. A refusal is information about
## THAT part; holding back the rest would make the builder fix an arm guard to get a camera mount.
##
## ## What this does not do
##
## It does not write the container file. The caller owns the file and when to write it (the shell does
## so at once when the drone has a home). And it does not decide what is printable: PrintedParts'
## rows do, and `PrintedParts.solid_for` is the one door to each part's triangles.


## Exports every listed part. Returns `{"written": [record…], "refused": [reason…], "summary": String}`.
## `container` may be null, in which case files are written and nothing is recorded.
static func export_all(build: Build, prop_tip_radius_m: float, export_dir: String,
		container: ProjectContainer) -> Dictionary:
	var written: Array = []
	var refused: Array = []
	DirAccess.make_dir_recursive_absolute(export_dir)
	var clearance := PrintSettings.clearance_mm(build.printing)
	var material := PrintSettings.material(build.printing)

	for row in PrintedParts.for_build(build):
		var solid := PrintedParts.solid_for(build, String(row["id"]), prop_tip_radius_m)
		if not bool(solid["ok"]):
			refused.append(String(solid["reason"]))
			continue
		var solid_name := safe_name(String(solid["solid_name"]))
		var triangles: Array = solid["triangles"]
		var path := export_dir.path_join("%s.stl" % solid_name)
		var result := StlWriter.write(solid_name, triangles, path)
		if not bool(result["ok"]):
			refused.append(String(result["reason"]))
			continue

		# The same text StlWriter just wrote, so the member, the file and the hash are one thing.
		var text := StlWriter.to_ascii(solid_name, triangles)
		var sha := text.sha256_text()
		var record := {
			"part": String(solid["part"]),
			"file": "printed/%s-%s.stl" % [solid_name, sha.substr(0, 8)],
			"printed_at": Time.get_datetime_string_from_system(true) + "Z",
			"generator": String(solid["generator"]),
			"geometry_sha256": sha,
			"material": material,
			"clearance_mm": clearance,
			"triangles": triangles.size(),
			"bbox_mm": bbox_mm(triangles),
			"quantity": int(solid["quantity"]),
			"exported_to": path,
		}
		if container != null:
			container.set_member_bytes(String(record["file"]), text.to_utf8_buffer())
			container.project.print_records.append(record)
		written.append(record)

	return {"written": written, "refused": refused, "summary": summary_text(written, refused)}


## What the status line says: what was written, then what was not and why, in one line.
static func summary_text(written: Array, refused: Array) -> String:
	var parts: Array = []
	for record in written:
		parts.append("%s ×%d" % [String(record["part"]), int(record["quantity"])])
	var out := ""
	if written.is_empty() and refused.is_empty():
		return "Nothing on this drone is printed."
	if not written.is_empty():
		out = "Exported %d printed part%s into this drone and the exports folder: %s." % [
			written.size(), "" if written.size() == 1 else "s", ", ".join(PackedStringArray(parts))]
	if not refused.is_empty():
		out += (" " if out != "" else "") + "NOT EXPORTED — %s" % "; ".join(PackedStringArray(refused))
	return out


## The solid's extent along X, Y and Z, in millimetres, rounded to a hundredth.
static func bbox_mm(triangles: Array) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for t in triangles:
		for p in t:
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	if triangles.is_empty():
		return [0.0, 0.0, 0.0]
	var size := hi - lo
	return [snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01)]


## A name safe for a file and for an STL header: letters, digits, `_` and `-`; anything else becomes
## `_`. The ONE spelling — GlassShell's per-part buttons call this too, so a part lands under the same
## name from its button and from the project menu.
static func safe_name(text: String) -> String:
	var out := ""
	for index in text.length():
		var character := text[index]
		out += character if character.is_valid_identifier() or character.is_valid_int() \
			or character == "-" else "_"
	return "part" if out.is_empty() else out
