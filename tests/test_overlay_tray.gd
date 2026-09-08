class_name TestOverlayTray
extends RefCounted
## The analysis tray's two decisions — which overlays are up, and where they sit (src/ui/overlay_tray.gd).
##
## ## Why these checks did not exist before, and why the code moved so they could
##
## Both defects this suite covers shipped green. `GlassShell` wires itself in `_ready()`, which
## needs a tree, a rendered frame and a real catalog, and `run_tests.gd` processes no frames by
## design — so every rule that lived inside the shell was a rule no check could reach.
## `test_glass_shell.gd` says the same about itself and tests a static function for exactly this
## reason. Nothing here constructs a shell; it drives the two static rules the shell now defers to.
##
## ## The band these checks are written against is the SHIPPING window, and that is the point
##
## `project.godot` opens at 1280×720 with a 1024 minimum. The five overlays were placed at fixed
## offsets reaching 1428 px, so the failure was not a rounding error at an unusual size — it was
## the default size of the app. `_shipping_band()` derives that band from `GlassShell`'s own
## constants rather than restating numbers, so a change to the rail or the inspector moves the
## checks with it instead of leaving them describing a layout that no longer exists.
##
## It derives the band at the FLOORS, which is the optimistic direction: `RAIL_WIDTH` and
## `INSPECTOR_WIDTH` are minimums that `_fit_columns` grows to fit content, and every pixel either
## column takes is a pixel off this band. So "five do not fit here" is the weakest form of that
## claim and still true.


static func run() -> Array:
	var results: Array = []
	# Collected per section rather than appended blind: a runtime error inside one helper aborts
	# only that helper, its append never runs, and the suite passes with the checks it lost. The
	# count below is what makes that visible — feedback the runner's empty-suite guard does not
	# catch, because the suite is not empty.
	var sections := {
		"gate": _gate_checks(),
		"layout": _layout_checks(),
		"capacity": _capacity_checks(),
		"door": _door_checks(),
		"defaults": _default_checks(),
		"shell": _shell_checks(),
	}
	for section_name in sections:
		var section: Array = sections[section_name]
		results.append(TestResult.new(
			"[tray] section \"%s\" produced its checks" % section_name,
			not section.is_empty(),
			"%d check(s)" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# The gate — the defect that put five Propulsion charts over the Airframe room
# ---------------------------------------------------------------------------

## Four separate checks rather than one loop over four cases, because a loop that asserts four
## things fails ONCE and the failure count stops meaning anything. The Airframe case is the one
## that was wrong in the shipped app; the other three are the cases that were right, and they are
## here so that a "fix" which simply returns false can be seen to be no fix at all.
static func _gate_checks() -> Array:
	var out: Array = []

	# THE DEFECT. In Lab, no room open, and Airframe is the focused system — whose plan editor
	# takes the whole viewport. The shipped shell drew all five charts here.
	out.append(TestResult.new(
		"[tray] no chart over the Airframe room, which owns the viewport",
		OverlayTray.allowed(true, false, true) == false,
		"allowed(in_lab, no blade room, Airframe) = %s" % OverlayTray.allowed(true, false, true)))

	out.append(TestResult.new(
		"[tray] no chart over the blade designer — it would describe the fitted blade, not the drawn one",
		OverlayTray.allowed(true, true, false) == false,
		"allowed(in_lab, blade room open, Propulsion) = %s" % OverlayTray.allowed(true, true, false)))

	out.append(TestResult.new(
		"[tray] no chart outside Lab — a bench, Studio, the field, Sim",
		OverlayTray.allowed(false, false, false) == false,
		"allowed(not in_lab, no rooms) = %s" % OverlayTray.allowed(false, false, false)))

	# The case that must stay true, and the reason the three above cannot be satisfied by a stub.
	out.append(TestResult.new(
		"[tray] a chart IS allowed in Lab with no room open and a system that does not cover the viewport",
		OverlayTray.allowed(true, false, false) == true,
		"allowed(in_lab, no rooms, Propulsion) = %s" % OverlayTray.allowed(true, false, false)))

	return out


# ---------------------------------------------------------------------------
# The layout — the defect that put two of five under the inspector and off-screen
# ---------------------------------------------------------------------------

static func _layout_checks() -> Array:
	var out: Array = []
	var band := _shipping_band()

	# THE DEFECT, stated as the property the old code broke. The old geometry is reproduced in
	# `_shipped_offsets()` and measured against this same band below, so the check is not merely
	# green on new code — it is red on the code that shipped.
	var fits := true
	var worst := 0.0
	var rects := OverlayTray.layout(band, OverlayTray.capacity(band))
	for rect in rects:
		if not _inside(rect, band):
			fits = false
		# The worst escape in ANY direction, not just past the inspector. Written as the inspector
		# overhang first, and a mutation that pushed the cards leftwards under the rail instead
		# reported "worst overhang 0.0" beside its own failure — a detail line that describes the
		# defect it did not find is how a failure gets read as a flake.
		worst = maxf(worst, maxf(rect.end.x - band.end.x, band.position.x - rect.position.x))
		worst = maxf(worst, maxf(rect.end.y - band.end.y, band.position.y - rect.position.y))
	out.append(TestResult.new(
		"[tray] every card lands inside the band, at the window the app opens at",
		fits and not rects.is_empty(),
		"%d card(s) in a %.0f x %.0f band; worst escape past any edge %.1f px" % [
			rects.size(), band.size.x, band.size.y, worst]))

	# The same property against what SHIPPED, so this suite carries the evidence that the check can
	# fail rather than the claim that it could.
	#
	# **This check was written expecting three of five to escape, and the measurement said FIVE.**
	# The third column running past the inspector was the visible half and is three cards. The other
	# two were escaping at the OTHER edge, by 16 px, and nobody had seen it: the old offsets started
	# the first column at `RAIL_WIDTH + 2·margin = 324`, while the rail column's actual right edge
	# is `margin + RAIL_WIDTH + 2·SPACE_2 = 328`. So the leftmost card sat under the rail glass —
	# the same constant-versus-measurement mistake as the inspector overhang, at the opposite end
	# and small enough to read as a design choice.
	#
	# Counted as two numbers rather than one, because they are two defects and a single total would
	# let one of them be fixed while the check stayed green on the other.
	var overhanging := 0
	var undercutting := 0
	for rect in _shipped_offsets():
		if rect.end.x > band.end.x + 1.0:
			overhanging += 1
		if rect.position.x < band.position.x - 1.0:
			undercutting += 1
	out.append(TestResult.new(
		"[tray] the shipped fixed offsets DID escape that band, at BOTH edges — the check above can fail",
		overhanging == 3 and undercutting == 2,
		"of 5 shipped cards: %d ran past the inspector (left edge %.0f), %d sat under the rail (right edge %.0f)" % [
			overhanging, band.end.x, undercutting, band.position.x]))

	# Two cards in one place is the other way a packer goes wrong, and it is the way a packer goes
	# wrong SILENTLY — the top one looks fine and the one underneath is simply not there.
	var overlapping := 0
	var full := OverlayTray.layout(band, OverlayTray.capacity(band))
	for i in full.size():
		for j in range(i + 1, full.size()):
			if full[i].intersects(full[j]):
				overlapping += 1
	out.append(TestResult.new(
		"[tray] no two cards overlap",
		overlapping == 0 and full.size() >= 2,
		"%d overlapping pair(s) among %d cards" % [overlapping, full.size()]))

	# A tray asked for three cards must produce three rectangles. An off-by-one that dropped the
	# last one would leave a chart ticked in the menu and absent from the screen, which is the
	# shipped defect wearing different clothes.
	var asked := mini(3, OverlayTray.capacity(band))
	out.append(TestResult.new(
		"[tray] the tray places exactly as many cards as it was asked for",
		OverlayTray.layout(band, asked).size() == asked and asked > 0,
		"asked %d, placed %d" % [asked, OverlayTray.layout(band, asked).size()]))

	# Cards keep the size the five `_draw()` implementations were laid out against whenever that
	# many fit, and shrink only to buy a column. A packer that always shrank would pass every
	# containment check above while making every chart harder to read than it needs to be.
	var one := OverlayTray.layout(band, 1)
	out.append(TestResult.new(
		"[tray] a card that fits at the preferred size is drawn at the preferred size",
		one.size() == 1 and one[0].size.is_equal_approx(OverlayTray.CARD_PREFERRED),
		"one card came back %.0f x %.0f, preferred %.0f x %.0f" % [
			one[0].size.x, one[0].size.y,
			OverlayTray.CARD_PREFERRED.x, OverlayTray.CARD_PREFERRED.y]))

	# And it does shrink when shrinking is what buys the row. Asked for one more than the preferred
	# size allows, every card comes back at the minimum rather than the tray dropping one.
	var preferred_capacity := 0
	for count in range(1, OverlayTray.ENTRIES.size() + 1):
		var placed := OverlayTray.layout(band, count)
		if placed.size() == count and placed[0].size.is_equal_approx(OverlayTray.CARD_PREFERRED):
			preferred_capacity = count
	var stretched := OverlayTray.layout(band, preferred_capacity + 1)
	out.append(TestResult.new(
		"[tray] one card past the preferred fit shrinks them all rather than dropping one",
		stretched.size() == preferred_capacity + 1
			and stretched[0].size.is_equal_approx(OverlayTray.CARD_MINIMUM),
		"%d fit at preferred; asking %d placed %d at %.0f x %.0f" % [
			preferred_capacity, preferred_capacity + 1, stretched.size(),
			stretched[0].size.x, stretched[0].size.y]))

	return out


# ---------------------------------------------------------------------------
# Capacity — the honest half: a card that does not fit is refused, not shrunk to nothing
# ---------------------------------------------------------------------------

static func _capacity_checks() -> Array:
	var out: Array = []
	var band := _shipping_band()
	var fits := OverlayTray.capacity(band)

	# THE MEASUREMENT THAT MAKES THE WHOLE SLICE NECESSARY. Five charts were never a thing the
	# shipping window could hold — not misplaced, impossible — so a fix that only moved them would
	# have moved two of them on top of the others.
	out.append(TestResult.new(
		"[tray] the window the app opens at cannot hold all five, which is why the chooser exists",
		fits < OverlayTray.ENTRIES.size() and fits >= 1,
		"%d of %d fit in a %.0f x %.0f band" % [
			fits, OverlayTray.ENTRIES.size(), band.size.x, band.size.y]))

	# And it is a measurement of the band rather than a constant: a wide window holds all five.
	# Without this the check above is satisfied by a tray that refuses everything.
	var wide := Rect2(band.position, Vector2(2672.0, 1697.0))
	out.append(TestResult.new(
		"[tray] a wide window holds all five",
		OverlayTray.capacity(wide) >= OverlayTray.ENTRIES.size(),
		"%d fit in a %.0f x %.0f band" % [
			OverlayTray.capacity(wide), wide.size.x, wide.size.y]))

	# A band with no room is answered with zero and a sentence, not with a card drawn at 8 px.
	var tiny := Rect2(Vector2(340.0, 64.0), Vector2(120.0, 90.0))
	out.append(TestResult.new(
		"[tray] a band too small for one card holds none, and says so",
		OverlayTray.capacity(tiny) == 0 and OverlayTray.layout(tiny, 3).is_empty()
			and OverlayTray.refusal(tiny).contains("widen the window"),
		"capacity %d, placed %d, refusal \"%s\"" % [
			OverlayTray.capacity(tiny), OverlayTray.layout(tiny, 3).size(),
			OverlayTray.refusal(tiny)]))

	# The refusal names the number that fits, because "no room" is true and useless — a builder
	# told two fit knows to untick one.
	out.append(TestResult.new(
		"[tray] the refusal names how many DO fit",
		OverlayTray.refusal(band).contains(str(fits)),
		"\"%s\" against a capacity of %d" % [OverlayTray.refusal(band), fits]))

	# The clamp. It should be unreachable — the chooser asks `capacity` first — and a tray that
	# honoured an over-large count would put cards back outside the band, which is the defect.
	out.append(TestResult.new(
		"[tray] asking for more than fits places what fits, never a card outside the band",
		OverlayTray.layout(band, 99).size() == fits,
		"asked 99, placed %d, capacity %d" % [OverlayTray.layout(band, 99).size(), fits]))

	return out


# ---------------------------------------------------------------------------
# The door — the thing a real builder could not find
# ---------------------------------------------------------------------------

## The blade designer existed and was unreachable in practice: its only door was a button inside the
## Prop TAB of the inspector, invisible while the Motor tab was selected. These check the rule that
## puts a door in the top strip instead, where it is visible for as long as the system is chosen.
static func _door_checks() -> Array:
	var out: Array = []
	var by_name := {}
	for system in GlassShell.SYSTEMS:
		by_name[str(system["name"])] = system

	out.append(TestResult.new(
		"[door] Propulsion carries a door into the blade designer",
		GlassShell.room_door_label(by_name["Propulsion"]) != "",
		"Propulsion door reads \"%s\"" % GlassShell.room_door_label(by_name["Propulsion"])))

	# Airframe's room opens WITH the system, so a door to it is a button that does nothing. This is
	# the check that stops "give every system a door" from passing the one above.
	out.append(TestResult.new(
		"[door] Airframe carries none — its room opens with the system",
		GlassShell.room_door_label(by_name["Airframe"]) == "",
		"Airframe door reads \"%s\"" % GlassShell.room_door_label(by_name["Airframe"])))

	# A modelled system with no room of its own. Power has a pack bench, and it is reached from the
	# inspector — `INSPECTOR_DOORS`' arrangement, which this must not quietly duplicate.
	out.append(TestResult.new(
		"[door] Power carries none",
		GlassShell.room_door_label(by_name["Power"]) == "",
		"Power door reads \"%s\"" % GlassShell.room_door_label(by_name["Power"])))

	# An unmodelled system must never offer a door, whatever its name — the greyed dropdown entry
	# is the whole of what it may promise.
	var unmodelled := 0
	var offered := 0
	for system in GlassShell.SYSTEMS:
		if not GlassShell._is_modelled(system):
			unmodelled += 1
			if GlassShell.room_door_label(system) != "":
				offered += 1
	out.append(TestResult.new(
		"[door] no unmodelled system offers a door",
		offered == 0 and unmodelled >= 1,
		"%d of %d unmodelled systems offered one" % [offered, unmodelled]))

	return out


# ---------------------------------------------------------------------------
# The defaults — a tray that opens refusing its own contents would be worse than five
# ---------------------------------------------------------------------------

static func _default_checks() -> Array:
	var out: Array = []
	var ids: Array = []
	for entry in OverlayTray.ENTRIES:
		ids.append(str(entry["id"]))

	var known := true
	for id in OverlayTray.DEFAULT_CHOSEN:
		if not ids.has(str(id)):
			known = false
	out.append(TestResult.new(
		"[tray] every default chart is one of the five",
		known and not OverlayTray.DEFAULT_CHOSEN.is_empty(),
		"defaults %s against ids %s" % [OverlayTray.DEFAULT_CHOSEN, ids]))

	# THE CHECK THAT WOULD HAVE CAUGHT THE ORIGINAL DEFECT ON ITS OWN. Five were shown by default
	# in a window that holds three; whatever the default becomes, it has to fit the window the app
	# opens at, or the app's first click on Overlays is a refusal of its own configuration.
	out.append(TestResult.new(
		"[tray] the default selection fits the window the app opens at",
		OverlayTray.DEFAULT_CHOSEN.size() <= OverlayTray.capacity(_shipping_band()),
		"%d chosen by default, %d fit" % [
			OverlayTray.DEFAULT_CHOSEN.size(), OverlayTray.capacity(_shipping_band())]))

	# One name per chart, shared by the tick and the card. Two names for one thing in a corner
	# already accused of being a menu is how a chooser stops matching what it chose.
	var titled := 0
	for id in ids:
		if OverlayTray.title_of(str(id)) != "":
			titled += 1
	out.append(TestResult.new(
		"[tray] every chart has a title, and an unknown id has none",
		titled == ids.size() and OverlayTray.title_of("not_a_chart") == "",
		"%d of %d titled" % [titled, ids.size()]))

	return out


# ---------------------------------------------------------------------------
# The shell — the defect end to end, on the path a builder actually walks
# ---------------------------------------------------------------------------

## The pure rules above say what SHOULD happen; these say the shell obeys them.
##
## **This suite's own header was too pessimistic about what is testable here, and the correction is
## worth stating.** `GlassShell` cannot have its TAB ROUTING checked headless — `current_tab` needs
## a layout pass and `run_tests.gd` renders no frames, which is what `test_glass_shell.gd` documents.
## But `tests/test_room_host.gd` builds a real shell with `GlassShell.new()` and asserts visibility
## flags on it, and visibility is exactly what the overlay defect was. So the shipped bug is
## reproducible here, and a check that only exercised `OverlayTray.allowed` would have proved the
## rule while leaving unproved the thing that was actually wrong: that `_select_system` CALLS it.
static func _shell_checks() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	# THE SHELL IS GIVEN A SIZE, and without this every check below passes for the wrong reason.
	#
	# A `Control` that has never been laid out has `size == (0, 0)`, so the band comes back with a
	# negative width, capacity is zero, and the tray hides every card — which makes "no cards over
	# the Airframe room" true in a shell where no card is ever visible anywhere. The first draft of
	# this section did exactly that and reported "0 card(s) up in Propulsion", which is the tell.
	# It is the same family as the `look_at`-outside-the-tree and `current_tab`-before-layout traps
	# this project has hit before: the geometry is not wrong, it has not happened yet.
	#
	# 1280×720 is what `project.godot` opens at, so the shell under test is the shipping window.
	# `_fit_columns` is then called by hand because `_ready` defers it and nothing here renders.
	shell.size = Vector2(1280.0, 720.0)
	shell._fit_columns()

	# THE SHIPPED DEFECT, on the path that produced it: the tray is up in Propulsion, and the
	# builder walks to Airframe. Every card must be gone.
	shell.select_system_by_name("Propulsion")
	shell.set_thrust_overlay_visible(true)
	var up_in_propulsion := _visible_cards(shell)

	shell.select_system_by_name("Airframe")
	var up_in_airframe := _visible_cards(shell)

	results.append(TestResult.new(
		"[shell] a tray that is up in Propulsion is gone when the builder walks to Airframe",
		up_in_propulsion > 0 and up_in_airframe == 0,
		"%d card(s) up in Propulsion, %d still up over the Airframe room" % [
			up_in_propulsion, up_in_airframe]))

	# The first half of that check is load-bearing and is asserted separately, because "gone in
	# Airframe" is satisfied completely by a tray that never appears anywhere. The toggle has to
	# actually put charts on screen for the check above to mean what it says.
	results.append(TestResult.new(
		"[shell] and the toggle does put charts up in the first place",
		up_in_propulsion == OverlayTray.DEFAULT_CHOSEN.size(),
		"%d card(s) up for %d chosen by default" % [
			up_in_propulsion, OverlayTray.DEFAULT_CHOSEN.size()]))

	# Walking back must bring them back. A "fix" that hid the tray on the first system change and
	# never restored it would pass both checks above while costing the feature — the toggle would
	# be a one-shot.
	shell.select_system_by_name("Propulsion")
	var back := _visible_cards(shell)
	results.append(TestResult.new(
		"[shell] and walking back to Propulsion brings them back, rather than the toggle being one-shot",
		back == up_in_propulsion,
		"%d card(s) after returning, %d before leaving" % [back, up_in_propulsion]))

	# No card may overlap the inspector, measured on the REAL columns rather than on the derived
	# band — `_fit_columns` grows both of them past their floors to fit content, and the band the
	# arithmetic above is checked against assumes the floors. This is the check that would notice
	# the inspector growing wide enough to eat a column the tray had already placed.
	var clear := true
	var inspector_left := shell.size.x + shell._inspector.offset_left
	for id in shell._overlays:
		var card: Control = shell._overlays[id]
		if card.visible and card.offset_right > inspector_left + 1.0:
			clear = false
	results.append(TestResult.new(
		"[shell] no visible card reaches under the inspector, measured on the real column",
		clear,
		"inspector left edge %.0f, %d card(s) visible" % [
			inspector_left, _visible_cards(shell)]))

	# And the ESC bench's new door, mirroring the thrust stand's in test_room_host.gd: driven
	# through the panel's SIGNAL, because calling `_open_room` directly would say nothing about
	# whether the button is connected to anything.
	shell.lab.esc_details.esc_bench_requested.emit()
	var esc_open := shell.rooms.esc_bench != null
	var esc_retracted := not shell._top_bar.visible and not shell._rail_glass.visible \
		and not shell._inspector.visible and not shell._tools_glass.visible
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"[shell] the ESC bench opens from the ESC inspector, and retracts the chrome identically",
		esc_open and esc_retracted,
		"opened=%s retracted=%s" % [esc_open, esc_retracted]))

	shell.free()
	return results


static func _visible_cards(shell: GlassShell) -> int:
	var count := 0
	for id in shell._overlays:
		if (shell._overlays[id] as Control).visible:
			count += 1
	return count


# ---------------------------------------------------------------------------
# The band, and the geometry that shipped
# ---------------------------------------------------------------------------

## The band at the window `project.godot` opens at, derived from `GlassShell`'s own constants.
##
## Derived rather than written down, so this suite cannot go on describing a layout the shell has
## moved on from — and derived at the FLOORS, which is the optimistic case: `_fit_columns` grows
## both columns to fit their content and every pixel it takes comes out of this band.
static func _shipping_band() -> Rect2:
	var window := Vector2(1280.0, 720.0)
	var margin := GlassShell.CLUSTER_MARGIN
	# The rail's own right edge, as `_fit_columns` computes it at the floor width.
	var rail_right := margin + GlassShell.RAIL_WIDTH + float(LothalTheme.SPACE_2) * 2.0
	var left := rail_right + margin
	# The inspector is anchored to the right edge and grows leftwards, same arithmetic.
	var inspector_left := window.x \
		- (GlassShell.INSPECTOR_WIDTH + float(LothalTheme.SPACE_2) * 2.0 + margin)
	var right := inspector_left - margin
	var top := margin + GlassShell.TOP_BAR_HEIGHT + float(LothalTheme.SPACE_2)
	var bottom := window.y - GlassShell.BOTTOM_KEEPOUT
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


## The five cards exactly where `_build_thrust_overlay` used to put them: three columns of 360 px
## from the rail, then a second row above. Reproduced here rather than described, because "the old
## code was wrong" is a claim and this is the measurement — without it the containment check above
## is a check nobody has seen fail.
static func _shipped_offsets() -> Array:
	var window := Vector2(1280.0, 720.0)
	var margin := GlassShell.CLUSTER_MARGIN
	var rail := GlassShell.RAIL_WIDTH
	var keepout := GlassShell.BOTTOM_KEEPOUT
	var row_one_top := window.y - (keepout + 210.0)
	var row_two_top := window.y - (keepout + 210.0 * 2.0 + margin)
	var columns := [
		rail + margin * 2.0,
		rail + margin * 3.0 + 360.0,
		rail + margin * 4.0 + 720.0,
	]
	return [
		Rect2(Vector2(columns[0], row_one_top), Vector2(360.0, 210.0)),   # thrust
		Rect2(Vector2(columns[1], row_one_top), Vector2(360.0, 210.0)),   # campbell
		Rect2(Vector2(columns[2], row_one_top), Vector2(360.0, 210.0)),   # vibration
		Rect2(Vector2(columns[0], row_two_top), Vector2(360.0, 210.0)),   # spin-up
		Rect2(Vector2(columns[1], row_two_top), Vector2(360.0, 210.0)),   # prop discs
	]


## Containment with a pixel of slack, because these are float offsets and an exact compare would
## report a card as escaping over a rounding error. A pixel is far below the 536 px the shipped
## third column overhangs by, so the slack cannot hide the thing being measured.
static func _inside(rect: Rect2, band: Rect2) -> bool:
	return rect.position.x >= band.position.x - 1.0 \
		and rect.position.y >= band.position.y - 1.0 \
		and rect.end.x <= band.end.x + 1.0 \
		and rect.end.y <= band.end.y + 1.0
