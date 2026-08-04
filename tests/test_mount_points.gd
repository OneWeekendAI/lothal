class_name TestMountPoints
extends RefCounted
## A frame's mount points: the places on it where something attaches. The centre-plate bolt
## pattern that the stack sandwiches into, and the strap locations on the top and bottom plates.
##
## The regression these exist to catch is a mount table that was TYPED rather than derived.
## A uniform "every frame has a 30.5x30.5 stack and three mounts" would satisfy any test that
## only ever looked at the reference build, and would be wrong for two thirds of the catalog —
## a 65 mm whoop takes a 25.5 AIO and has no room under its plate for anything at all. So every
## test below either sweeps the whole catalog or compares two frames against each other, and
## the values it compares against were read off frames.json by hand before the code ran.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_every_frame_exposes_its_own_stack_pattern(catalog))
	results.append(_test_the_stack_pattern_is_not_uniform(catalog))
	results.append(_test_a_big_frame_offers_more_mounts_than_a_toothpick(catalog))
	results.append(_test_mounts_sit_on_the_surfaces_they_name(catalog))
	results.append(_test_the_standoff_tweak_carries_the_mounts(catalog))
	results.append(_test_fore_aft_reach_follows_the_arm())

	results.append(_test_a_matching_bolt_pattern_does_not_warn(catalog))
	results.append(_test_a_mismatched_bolt_pattern_warns(catalog))
	results.append(_test_a_strapped_part_on_a_bolt_mount_warns(catalog))
	results.append(_test_a_board_wider_than_its_plate_warns(catalog))
	results.append(_test_every_pack_declares_that_it_straps(catalog))

	return results


# ---------------------------------------------------------------------------
# Does it fit? Both directions, on pairings checked by hand against the two spec sheets.
#
# The FC/ESC stack is drilled 30.5x30.5 — the full-size standard. frames.json drills the 5"
# freestyle 30.5x30.5 and the 3.5" freestyle 20x20. So one of those two pairings must be silent
# and the other must not, and a fit check that always says yes fails the first pair while a fit
# check that always says no fails the second. Asserting only that the reference build's own stack
# fits its own frame would prove neither.
# ---------------------------------------------------------------------------

static func _test_a_matching_bolt_pattern_does_not_warn(catalog: PartsCatalog) -> TestResult:
	var mount: MountPoint = _mount_by_id(
		FrameModel.mount_points_for(catalog.get_part("frame_5in_freestyle"), -1.0), "stack")
	var warnings := mount.fit_warnings("The FC/ESC stack", Build.stack_mounting(),
		StackMesh.size_m(Build.STACK_MOUNT_PATTERN))

	return TestResult.new(
		"a 30.5 stack on a 30.5-drilled frame is not warned about",
		mount.pattern == "30.5x30.5" and warnings.is_empty(),
		"5\" freestyle mount is %s; warnings: %s" % [mount.pattern, BuildWarning.messages(warnings)])


static func _test_a_mismatched_bolt_pattern_warns(catalog: PartsCatalog) -> TestResult:
	var mount: MountPoint = _mount_by_id(
		FrameModel.mount_points_for(catalog.get_part("frame_35in_freestyle"), -1.0), "stack")
	var warnings := mount.fit_warnings("The FC/ESC stack", Build.stack_mounting(),
		StackMesh.size_m(Build.STACK_MOUNT_PATTERN))

	var mentions_both := false
	for warning in warnings:
		if warning.message.contains("30.5x30.5") and warning.message.contains("20x20"):
			mentions_both = true

	return TestResult.new(
		"a 30.5 stack on a 20x20-drilled frame is warned about, in both patterns' words",
		mount.pattern == "20x20" and mentions_both,
		"3.5\" freestyle mount is %s; warnings: %s" % [mount.pattern, BuildWarning.messages(warnings)])


## A pack is strapped, and a bolt pattern is not something a strap can pass through. The warning
## is the whole answer here — the pack still mounts, because Lothal never blocks.
static func _test_a_strapped_part_on_a_bolt_mount_warns(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var pack: Dictionary = catalog.get_part("battery_4s_1500")
	var mounts := FrameModel.mount_points_for(frame, -1.0)

	var on_bolts := (_mount_by_id(mounts, "stack") as MountPoint).fit_warnings(
		pack["name"], MountPoint.mounting_of(pack), Build.battery_size_of(pack))
	var on_strap := (_mount_by_id(mounts, "strap_top") as MountPoint).fit_warnings(
		pack["name"], MountPoint.mounting_of(pack), Build.battery_size_of(pack))

	return TestResult.new(
		"a strapped pack warns on a bolt pattern and not on a strap location",
		on_bolts.size() == 1 and on_strap.is_empty(),
		"on the stack mount: %s; on the top plate: %s" % [on_bolts, on_strap])


## The geometry half of the check, on the frame it actually bites on: a 65 mm whoop's centre plate
## is 17.6 mm across (32 mm arm x 0.55) and a 30.5 stack is a 36.5 mm board. It is drilled wrong
## AND it hangs off the plate, and both are worth saying.
static func _test_a_board_wider_than_its_plate_warns(catalog: PartsCatalog) -> TestResult:
	var mount: MountPoint = _mount_by_id(
		FrameModel.mount_points_for(catalog.get_part("frame_65mm_whoop"), -1.0), "stack")
	var warnings := mount.fit_warnings("The FC/ESC stack", Build.stack_mounting(),
		StackMesh.size_m(Build.STACK_MOUNT_PATTERN))

	var overhangs := false
	for warning in warnings:
		if warning.message.contains("overhangs"):
			overhangs = true

	return TestResult.new(
		"a board wider than the plate it bolts to is called out as well as mis-drilled",
		warnings.size() == 2 and overhangs,
		"65 mm whoop stack mount (%s, plate %.1f mm): %s" % [
			mount.pattern, mount.span_m.x * 1000.0, BuildWarning.messages(warnings)])


## Every pack in the catalog says how it attaches, rather than falling through to a default. A
## default that happened to be right is a default nobody would notice being wrong.
static func _test_every_pack_declares_that_it_straps(catalog: PartsCatalog) -> TestResult:
	var missing: Array = []
	for pack in catalog.list_category("battery"):
		var block: Dictionary = pack.get("mounting", {})
		if String(block.get("attachment", "")) != MountPoint.STRAP:
			missing.append(pack["part_id"])

	return TestResult.new(
		"every pack in the catalog declares that it straps",
		missing.is_empty(),
		"%d packs checked, %d without a mounting block: %s" % [
			catalog.list_category("battery").size(), missing.size(), missing])


## Every frame in the catalog offers a bolt-pattern stack mount, and the pattern it offers is the
## one its own `specs.stack_mount` string names. Swept across the catalog rather than checked on
## the reference build, because the reference build is exactly the frame a hardcoded 30.5 would
## look right on.
static func _test_every_frame_exposes_its_own_stack_pattern(catalog: PartsCatalog) -> TestResult:
	var all_ok := true
	var detail := ""
	var checked := 0

	for frame in catalog.list_category("frame"):
		var declared: String = frame["specs"].get("stack_mount", "")
		# Split here rather than through MountPoint.parse_pattern_m, deliberately: asking the
		# code under test what it thinks the string means and then checking it against itself
		# is a test that cannot fail.
		var halves := declared.split("x")
		var expected := Vector2(float(halves[0]) / 1000.0, float(halves[1]) / 1000.0)
		var stack: MountPoint = _mount_by_id(FrameModel.mount_points_for(frame, -1.0), "stack")

		if stack == null:
			all_ok = false
			detail += "%s has no stack mount; " % frame["part_id"]
			continue
		if stack.attachment != MountPoint.BOLT:
			all_ok = false
			detail += "%s stack mount is %s, not a bolt pattern; " % [frame["part_id"], stack.attachment]
			continue
		if (stack.pattern_m - expected).length() > EPS:
			all_ok = false
			detail += "%s declares %s (%s) but the mount reports %s; " % [
				frame["part_id"], declared, expected, stack.pattern_m]
			continue
		checked += 1

	if all_ok:
		detail = "%d frames, each offering the bolt pattern its own specs name" % checked
	return TestResult.new("every frame's stack mount comes from its own specs", all_ok, detail)


## Two frames whose stack patterns really are different, checked by hand against frames.json:
## the 5" freestyle is drilled 30.5x30.5 and the 3.5" freestyle 20x20. A single authored constant
## passes the sweep above and fails here.
static func _test_the_stack_pattern_is_not_uniform(catalog: PartsCatalog) -> TestResult:
	var full: MountPoint = _mount_by_id(
		FrameModel.mount_points_for(catalog.get_part("frame_5in_freestyle"), -1.0), "stack")
	var small: MountPoint = _mount_by_id(
		FrameModel.mount_points_for(catalog.get_part("frame_35in_freestyle"), -1.0), "stack")

	var full_ok := full != null and absf(full.pattern_m.x - 0.0305) < EPS
	var small_ok := small != null and absf(small.pattern_m.x - 0.020) < EPS
	var passed := full_ok and small_ok

	return TestResult.new(
		"stack patterns differ between frames rather than being one constant",
		passed,
		"5\" freestyle %s (want 0.0305), 3.5\" freestyle %s (want 0.020)" % [
			"none" if full == null else str(full.pattern_m.x),
			"none" if small == null else str(small.pattern_m.x)])


## How many mount points a frame has is a property of that frame's geometry. A 5" freestyle has a
## bottom plate with room beside the bolt pattern for strap slots; a 3" toothpick's plate is
## 41 mm across with a 25.5 pattern through the middle of it, and there is nothing left to cut a
## slot into. Both numbers were worked out on paper from frames.json before this ran.
static func _test_a_big_frame_offers_more_mounts_than_a_toothpick(catalog: PartsCatalog) -> TestResult:
	var big := FrameModel.mount_points_for(catalog.get_part("frame_5in_freestyle"), -1.0)
	var small := FrameModel.mount_points_for(catalog.get_part("frame_3in_toothpick"), -1.0)

	var big_ids := _ids(big)
	var small_ids := _ids(small)

	var passed := big_ids.has("stack") and big_ids.has("strap_top") and big_ids.has("strap_bottom") \
		and small_ids.has("stack") and small_ids.has("strap_top") \
		and not small_ids.has("strap_bottom") \
		and big.size() > small.size()

	return TestResult.new(
		"a bigger frame offers more mount points than a toothpick",
		passed,
		"5\" freestyle %s, 3\" toothpick %s" % [big_ids, small_ids])


## Each mount is where its name says it is, measured against the plates that were actually
## generated: the top strap on the top plate's upper face, the bottom strap on the bottom plate's
## lower face, the stack seated on the bottom plate's upper face — which is where the standoffs
## start and where the lower board in the stack sits.
static func _test_mounts_sit_on_the_surfaces_they_name(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var model := FrameModel.new()
	model.rebuild(frame)

	var gap := FrameModel.default_plate_gap_m()
	var thickness := Build.FRAME_PLATE_THICKNESS_M
	var expected := {
		"strap_top": gap * 0.5 + thickness * 0.5,
		"strap_bottom": -(gap * 0.5 + thickness * 0.5),
		"stack": -(gap * 0.5) + thickness * 0.5,
	}
	var expected_normal := {"strap_top": 1, "strap_bottom": -1, "stack": 1}

	var all_ok := true
	var detail := ""
	for id in expected:
		var mount: MountPoint = _mount_by_id(model.mount_points, id)
		if mount == null:
			all_ok = false
			detail += "%s missing; " % id
			continue
		if absf(mount.position.y - expected[id]) > EPS:
			all_ok = false
			detail += "%s at y=%.4f, want %.4f; " % [id, mount.position.y, expected[id]]
		if mount.normal != expected_normal[id]:
			all_ok = false
			detail += "%s faces %d, want %d; " % [id, mount.normal, expected_normal[id]]

	# The top strap must land on the same face anything strapped there is already seated against.
	if absf(model.plate_top_face_m() - expected["strap_top"]) > EPS:
		all_ok = false
		detail += "plate_top_face_m disagrees with the top strap mount; "

	model.free()
	if all_ok:
		detail = "three mounts within %.4f m of the plate faces they name" % EPS
	return TestResult.new("mount points sit on the surfaces they name", all_ok, detail)


## Taller standoffs move the mounts, because the mounts are on the plates and the standoffs are
## what hold the plates apart. This is the check that a mount position is geometry rather than a
## number written down once.
static func _test_the_standoff_tweak_carries_the_mounts(catalog: PartsCatalog) -> TestResult:
	var frame: Dictionary = catalog.get_part("frame_5in_freestyle")
	var short_gap := FrameModel.min_plate_gap_m()
	var tall_gap := FrameModel.max_plate_gap_m(0.110)

	var low: MountPoint = _mount_by_id(FrameModel.mount_points_for(frame, short_gap), "strap_top")
	var high: MountPoint = _mount_by_id(FrameModel.mount_points_for(frame, tall_gap), "strap_top")

	var passed := low != null and high != null \
		and high.position.y - low.position.y > (tall_gap - short_gap) * 0.5 - EPS \
		and high.position.y > low.position.y

	return TestResult.new(
		"the standoff height moves the mounts with the plates",
		passed,
		"top strap at y=%s on %.1f mm standoffs, y=%s on %.1f mm" % [
			"none" if low == null else "%.4f" % low.position.y, short_gap * 1000.0,
			"none" if high == null else "%.4f" % high.position.y, tall_gap * 1000.0])


## How far fore and aft a mount reaches before it is inside a propeller hub, which is a property
## of the arm and nothing else. A constant passes nothing here.
static func _test_fore_aft_reach_follows_the_arm() -> TestResult:
	var short_reach := FrameModel.mount_reach_m(0.075)
	var long_reach := FrameModel.mount_reach_m(0.150)
	var expected_long: float = absf(MotorLayout.motor_position("M2", 0.150).z)

	var passed := long_reach > short_reach and absf(long_reach - expected_long) < EPS
	return TestResult.new(
		"fore/aft mount reach is the arm's own forward extent",
		passed,
		"75 mm arm reaches %.4f m, 150 mm arm reaches %.4f m (front motor at %.4f m)" % [
			short_reach, long_reach, expected_long])


static func _mount_by_id(mounts: Array, id: String) -> MountPoint:
	for mount in mounts:
		if (mount as MountPoint).id == id:
			return mount
	return null


static func _ids(mounts: Array) -> Array:
	var out: Array = []
	for mount in mounts:
		out.append((mount as MountPoint).id)
	return out
