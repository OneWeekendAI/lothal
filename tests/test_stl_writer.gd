class_name TestStlWriter
extends RefCounted
## StlWriter — the printable-geometry boundary (track.md W1P.1, landed for P10f's guard export).
##
## ## The check that carries this file, and why the obvious one does not
##
## A manifold check is easy to write in a form that cannot fail. Summing facet normals, or
## computing a volume and asserting it is positive, both pass against a shell that is wound
## entirely inside out — because such a shell is perfectly consistent, and its volume is the
## right magnitude with the wrong sign. And a volume check ALONE passes against a cube with ONE
## facet flipped: five sixths of the surface still dominates the sum, the total stays positive,
## and the part that reaches the slicer has a hole in it.
##
## So the two failures are separated deliberately and each is proved by a mutation applied to a
## solid that is otherwise correct:
##
##   - **`_one_flipped_facet_is_caught_where_volume_alone_would_pass`** flips one triangle of a
##     good cube and asserts BOTH that the check refuses it AND that the signed volume is still
##     positive. The second half is the load-bearing one: it is the evidence that the edge-pairing
##     test is doing work no volume test could do.
##   - **`_a_shell_wound_inside_out_is_caught`** reverses EVERY triangle, which the edge test
##     cannot see (every directed edge still appears exactly once), and asserts the volume is the
##     exact negation. The pair is what makes the two checks non-redundant.
##
## ## The unit boundary
##
## `from_metres` is asserted at a scale where a missing conversion and a doubled one are both
## visible and distinguishable — 1 m goes to 1000 mm, not to 1 and not to 1e6. It matters because
## every producer in this app models in metres and every slicer reads millimetres, and both wrong
## answers render as a perfectly plausible preview.
##
## ## The refusal
##
## `_a_refused_part_writes_no_file` is the posture check. A warning next to a written file is a
## part somebody prints six hours of filament into, so the assertion is on the FILESYSTEM — the
## path must not exist afterwards — rather than on the returned flag, which a writer that wrote
## anyway would also set correctly.



static func run() -> Array:
	var results: Array = []
	results.append(_a_good_cube_passes())
	results.append(_the_volume_is_the_cube_s_own())
	results.append(_a_shell_wound_inside_out_is_caught())
	results.append(_one_flipped_facet_is_caught_where_volume_alone_would_pass())
	results.append(_an_open_surface_is_caught())
	results.append(_a_surface_enclosing_nothing_is_caught())
	results.append(_a_degenerate_facet_is_named())
	results.append(_nothing_at_all_is_caught())
	results.append(_metres_become_millimetres_once())
	results.append(_a_triangle_list_converts_through_the_same_factor())
	results.append(_the_text_carries_every_facet())
	results.append(_a_refused_part_writes_no_file())
	results.append(_a_good_part_writes_and_reads_back())
	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## An axis-aligned cube of side `side_mm` with its low corner at the origin, wound outward.
## Twelve triangles, hand-listed rather than generated, so the fixture cannot share a bug with
## the geometry producers this class exists to check.
static func _cube(side_mm: float) -> Array:
	var s := side_mm
	var v := [
		Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, 0),
		Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s),
	]
	var faces := [
		[0, 3, 2], [0, 2, 1],   # z = 0, facing -Z
		[4, 5, 6], [4, 6, 7],   # z = s, facing +Z
		[0, 1, 5], [0, 5, 4],   # y = 0, facing -Y
		[3, 7, 6], [3, 6, 2],   # y = s, facing +Y
		[0, 4, 7], [0, 7, 3],   # x = 0, facing -X
		[1, 2, 6], [1, 6, 5],   # x = s, facing +X
	]
	var out: Array = []
	for face in faces:
		out.append(PackedVector3Array([v[face[0]], v[face[1]], v[face[2]]]))
	return out


static func _reversed(triangles: Array) -> Array:
	var out: Array = []
	for triangle in triangles:
		out.append(PackedVector3Array([triangle[2], triangle[1], triangle[0]]))
	return out


static func _joined(reasons: Array) -> String:
	return " / ".join(PackedStringArray(reasons))


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

static func _a_good_cube_passes() -> TestResult:
	var report := StlWriter.check_manifold(_cube(10.0))
	return TestResult.new(
		"a closed, outward-wound cube passes the manifold check",
		bool(report["ok"]) and int(report["triangle_count"]) == 12,
		"ok=%s reasons=%s" % [report["ok"], _joined(report["reasons"])])


## The volume is not decoration: it is what the inside-out check reads, so it has to be the real
## number rather than merely a positive one.
static func _the_volume_is_the_cube_s_own() -> TestResult:
	var report := StlWriter.check_manifold(_cube(10.0))
	var volume := float(report["volume_mm3"])
	return TestResult.new(
		"and its signed volume is the cube's own 1000 mm³",
		absf(volume - 1000.0) < 1e-6,
		"%.9f mm³" % volume)


## Every triangle reversed. The edge test cannot see this — reversing the whole surface maps every
## directed edge onto its own reverse and the pairing still holds exactly — so this is the failure
## the signed volume is FOR, and the negation is asserted exactly rather than as "negative".
static func _a_shell_wound_inside_out_is_caught() -> TestResult:
	var good := StlWriter.check_manifold(_cube(10.0))
	var flipped := StlWriter.check_manifold(_reversed(_cube(10.0)))
	var named := false
	for reason in flipped["reasons"]:
		if String(reason).contains("inside out"):
			named = true
	return TestResult.new(
		"a shell wound entirely inside out is refused, and its volume is the exact negation",
		not bool(flipped["ok"]) and named
			and absf(float(flipped["volume_mm3"]) + float(good["volume_mm3"])) < 1e-6,
		"volume %.6f against %.6f · %s" % [flipped["volume_mm3"], good["volume_mm3"],
			_joined(flipped["reasons"])])


## THE mutation this file exists for. One facet of an otherwise-good cube is reversed. The volume
## stays positive — five sixths of the surface still points out — so a check built on the volume
## sign alone passes a part with a hole in it. The second assertion is the one that proves the
## edge test is not redundant.
static func _one_flipped_facet_is_caught_where_volume_alone_would_pass() -> TestResult:
	var triangles := _cube(10.0)
	triangles[0] = PackedVector3Array([triangles[0][2], triangles[0][1], triangles[0][0]])
	var report := StlWriter.check_manifold(triangles)
	var named := false
	for reason in report["reasons"]:
		if String(reason).contains("winding is inconsistent"):
			named = true
	var volume_still_positive := float(report["volume_mm3"]) > 0.0
	return TestResult.new(
		"one flipped facet is refused by the edge pairing, where the volume sign alone would "
			+ "have passed it",
		not bool(report["ok"]) and named and volume_still_positive,
		"volume %.6f (still positive: %s) · %s" % [report["volume_mm3"], volume_still_positive,
			_joined(report["reasons"])])


static func _an_open_surface_is_caught() -> TestResult:
	var triangles := _cube(10.0)
	triangles.remove_at(0)
	var report := StlWriter.check_manifold(triangles)
	var named := false
	for reason in report["reasons"]:
		if String(reason).contains("not closed"):
			named = true
	return TestResult.new(
		"a surface with a facet missing is refused as not closed",
		not bool(report["ok"]) and named,
		_joined(report["reasons"]))


## Two coincident triangles wound opposite ways: closed, consistently wound, and not a part.
static func _a_surface_enclosing_nothing_is_caught() -> TestResult:
	var a := Vector3(0, 0, 0)
	var b := Vector3(10, 0, 0)
	var c := Vector3(0, 10, 0)
	var report := StlWriter.check_manifold([
		PackedVector3Array([a, b, c]), PackedVector3Array([c, b, a])])
	var named := false
	for reason in report["reasons"]:
		if String(reason).contains("no volume"):
			named = true
	return TestResult.new(
		"a closed, consistent surface enclosing no volume is still refused",
		not bool(report["ok"]) and named,
		"volume %.9f · %s" % [report["volume_mm3"], _joined(report["reasons"])])


static func _a_degenerate_facet_is_named() -> TestResult:
	var triangles := _cube(10.0)
	triangles.append(PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]))
	var report := StlWriter.check_manifold(triangles)
	var named := false
	for reason in report["reasons"]:
		if String(reason).contains("no area"):
			named = true
	return TestResult.new(
		"a zero-area facet is refused by name rather than silently dropped",
		not bool(report["ok"]) and named,
		_joined(report["reasons"]))


static func _nothing_at_all_is_caught() -> TestResult:
	var report := StlWriter.check_manifold([])
	return TestResult.new(
		"an empty solid is refused rather than reported as a valid part of zero facets",
		not bool(report["ok"]) and int(report["triangle_count"]) == 0,
		_joined(report["reasons"]))


## A missing conversion and a doubled one are both plausible-looking parts, so the assertion has
## to distinguish 1000 from 1 and from 1e6 rather than merely "was scaled".
static func _metres_become_millimetres_once() -> TestResult:
	var converted := StlWriter.from_metres(Vector3(1.0, -0.0635, 0.012))
	# Bounded relatively at the float32 floor rather than to the bit: Vector3 is single precision,
	# so 0.0635 m arrives as 63.500004 mm. The tolerance is nine orders looser than the noise and
	# still eight orders tighter than either wrong answer this check exists to exclude.
	return TestResult.new(
		"a metre becomes 1000 mm — not 1, and not a million",
		absf(converted.x - 1000.0) < 1e-3 and absf(converted.y + 63.5) < 1e-3
			and absf(converted.z - 12.0) < 1e-3,
		"%v" % converted)


static func _a_triangle_list_converts_through_the_same_factor() -> TestResult:
	var metres := [PackedVector3Array([
		Vector3(0.001, 0, 0), Vector3(0, 0.002, 0), Vector3(0, 0, 0.003)])]
	var mm := StlWriter.from_metres_triangles(metres)
	var t: PackedVector3Array = mm[0]
	return TestResult.new(
		"and a whole triangle list converts through that same one factor",
		absf(t[0].x - 1.0) < 1e-5 and absf(t[1].y - 2.0) < 1e-5 and absf(t[2].z - 3.0) < 1e-5,
		"%v %v %v" % [t[0], t[1], t[2]])


static func _the_text_carries_every_facet() -> TestResult:
	var text := StlWriter.to_ascii("test cube", _cube(10.0))
	var facets := text.count("facet normal")
	return TestResult.new(
		"the ASCII text carries one facet per triangle, inside a named solid",
		facets == 12 and text.begins_with("solid test_cube")
			and text.strip_edges().ends_with("endsolid test_cube"),
		"%d facets" % facets)


## The posture check, asserted on the filesystem rather than on the returned flag — a writer that
## wrote the file anyway would return the same flag.
static func _a_refused_part_writes_no_file() -> TestResult:
	var path := "user://test_stl_refused.stl"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var result := StlWriter.write("guard_duct_5in_cinewhoop", _reversed(_cube(10.0)), path)
	var wrote := FileAccess.file_exists(path)
	if wrote:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return TestResult.new(
		"a part that fails the check writes NO file, and the refusal names the part first",
		not bool(result["ok"]) and not wrote
			and String(result["reason"]).begins_with("guard_duct_5in_cinewhoop: "),
		"wrote=%s reason=%s" % [wrote, result["reason"]])


static func _a_good_part_writes_and_reads_back() -> TestResult:
	var path := "user://test_stl_good.stl"
	var result := StlWriter.write("guard_bumper_5in_abs", _cube(10.0), path)
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return TestResult.new(
		"and a part that passes lands on disk with its geometry in it",
		bool(result["ok"]) and text.count("facet normal") == 12
			and absf(float(result["volume_mm3"]) - 1000.0) < 1e-6,
		"ok=%s bytes=%d volume=%.3f" % [result["ok"], text.length(), result["volume_mm3"]])
