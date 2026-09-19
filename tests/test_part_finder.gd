class_name TestPartFinder
extends RefCounted
## The summoned finder (src/ui/part_finder.gd), QC1 and QC2 of
## plans/2026-09-19-quiet-canvas-design.md.
##
## ## What this suite is really guarding
##
## §2 of that design is one sentence and the whole object rests on it: the finder opens in BROWSE
## mode, listing, with nothing typed, because the stated audience cannot type a name they have
## never heard. That is a property no screenshot proves and no reviewer notices — a finder that
## shows nothing until the first keystroke looks correct in every still image of it with text in
## the box. So the first section below asserts the empty-query case from four directions, and the
## mutation log in the report shows each one going red against a finder whose list was made
## conditional on input.
##
## The second is preview-and-restore. The failure mode there is subtler still: restoring the LAST
## PREVIEWED part instead of the original is the implementation nearest to hand, and in the
## one-preview case the two are indistinguishable. Every restore check here arrows through several
## parts first, for that reason alone.
##
## ## No frames, no window, no tree
##
## `tools/run_one_suite.gd` processes no frames and hangs on a suite that awaits one. Nothing here
## adds the finder to a tree or reads a size: every rule under test is decided in `_init` or in a
## public method, which is what made that possible. See `tests/test_overlay_tray.gd`'s header for
## the history of shell rules that no check could reach.

## The system label the shell will pass when the dock's Propulsion icon opens this category.
const SYSTEM := "Propulsion"
## The rail's own three axes, taken from MotorPicker rather than retyped: if the rail's facets
## change, this suite is testing the facets the app actually browses along.
const MOTOR_FILTERS := MotorPicker.FILTER_KEYS


## The build seam under test, as a recorder. The finder asks nothing of a fitter but these three
## methods (PartFinder.set_fitter), so this class IS the contract — if a later slice's shell
## adapter needs anything more, this class stops compiling as a stand-in and the seam has widened
## where someone can see it.
class FitterSpy extends RefCounted:
	var previewed: Array = []
	var committed: Array = []
	var restored: Array = []

	func preview_part(part: Dictionary) -> void:
		previewed.append(str(part.get("part_id", "")))

	func commit_part(part: Dictionary) -> void:
		committed.append(str(part.get("part_id", "")))

	func restore_part(part: Dictionary) -> void:
		restored.append(str(part.get("part_id", "")))


static func run() -> Array:
	var results: Array = []
	# Collected per section rather than appended blind: a runtime error inside one helper aborts
	# only that helper, its append never runs, and the suite passes with the checks it lost.
	var sections := {
		"browse": _browse_checks(),
		"rows": _row_checks(),
		"query": _query_checks(),
		"refusal": _refusal_checks(),
		"facets": _facet_checks(),
		"preview": _preview_checks(),
		"restore": _restore_checks(),
		"tooltips": _tooltip_checks(),
		"gutter": _gutter_checks(),
		"density": _density_checks(),
		"close": _close_checks(),
		"squeeze": _squeeze_checks(),
	}
	for section_name in sections:
		var section: Array = sections[section_name]
		results.append(TestResult.new(
			"[finder] section \"%s\" produced its checks" % section_name,
			not section.is_empty(),
			"%d check(s)" % section.size()))
		results.append_array(section)
	return results


static func _catalog() -> PartsCatalog:
	return PartsCatalog.load_default()


static func _finder(catalog: PartsCatalog) -> PartFinder:
	return PartFinder.new(catalog, SYSTEM, "motor", "motor", MOTOR_FILTERS)


static func _ids(parts: Array) -> Array:
	var out: Array = []
	for part in parts:
		out.append(str(part.get("part_id", "")))
	return out


# ---------------------------------------------------------------------------
# QC1 — browse mode. §2: "If a slice ever makes the list conditional on input, that slice is wrong."
#
# Four checks and not one, because the four observable consequences of that rule fail
# independently: the model can hold every part while the WIDGET shows none, the widget can hold
# rows while the finder also claims an empty state, and a finder that opens with a query
# pre-filled would satisfy the first three and still gate the user.
# ---------------------------------------------------------------------------

static func _browse_checks() -> Array:
	var out: Array = []
	var catalog := _catalog()
	var finder := _finder(catalog)
	var total: int = catalog.list_category("motor").size()

	# THE DECISION. Nothing typed, and the list is the whole category.
	out.append(TestResult.new(
		"[finder] opens listing every motor with nothing typed",
		finder.visible_parts().size() == total and total > 0,
		"%d visible of %d in the catalog" % [finder.visible_parts().size(), total]))

	# The widget, not the model. `visible_parts()` could be correct while the ItemList the builder
	# actually looks at was left empty until a keystroke arrived.
	out.append(TestResult.new(
		"[finder] the list WIDGET carries those rows before any keystroke",
		finder.row_count() == total,
		"%d row(s) in the ItemList, %d parts" % [finder.row_count(), total]))

	# An empty query is not a refusal. If this ever goes red the finder is telling a browsing
	# beginner that their non-existent search matched nothing.
	out.append(TestResult.new(
		"[finder] no refusal notice on open — an empty query is not a failed search",
		not finder.empty_state_visible(),
		"empty state visible = %s" % finder.empty_state_visible()))

	# The box is empty, so the rows above are genuinely the unfiltered catalog and not the result
	# of a query the finder typed on the builder's behalf.
	out.append(TestResult.new(
		"[finder] the search box starts empty",
		finder.query() == "",
		"query = \"%s\"" % finder.query()))

	# The rail's title carried system and category; §4 says that must survive the rail.
	out.append(TestResult.new(
		"[finder] the header names the system and the category",
		finder._header.text == "Propulsion · Motor",
		"header = \"%s\"" % finder._header.text))

	# Opening ON a build does not narrow anything either. open_on() is the shell's entry point, so
	# browse mode has to survive it and not only survive construction.
	var opened := _finder(catalog)
	opened.open_on("motor_2207_1960kv")
	out.append(TestResult.new(
		"[finder] still lists every motor after open_on() on a fitted build",
		opened.visible_parts().size() == total,
		"%d visible of %d" % [opened.visible_parts().size(), total]))

	out.append(TestResult.new(
		"[finder] opens with the FITTED part highlighted, not the first row",
		str(opened.highlighted_part().get("part_id", "")) == "motor_2207_1960kv",
		"highlighted = %s at index %d" % [
			opened.highlighted_part().get("part_id", ""), opened.highlighted_index()]))

	return out


# ---------------------------------------------------------------------------
# QC1 — the mass column. §4: "It must not lose the mass column — the rail showed
# `2207 1960KV  32 g` and the mass is half of why a builder scans that list."
# ---------------------------------------------------------------------------

static func _row_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	var index := _ids(finder.visible_parts()).find("motor_2207_1960kv")
	var row := finder.row_text(index)

	out.append(TestResult.new(
		"[finder] a row reads exactly as the rail's did — name then mass",
		row == "2207 1960KV   32 g",
		"row = \"%s\"" % row))

	# Named separately from the row-format check above so that a change to the SPACING between the
	# two columns cannot be mistaken for the mass having been dropped, and vice versa.
	out.append(TestResult.new(
		"[finder] the mass is present in the row",
		row.contains("32 g"),
		"row = \"%s\"" % row))

	# The sub-10 g format, which is the reason PartPicker._format_mass is reused rather than a
	# "%.0f" written fresh here: a 3.2 g whoop motor printed as "3 g" loses the distinction the
	# list exists to show.
	var small := finder.row_text(_ids(finder.visible_parts()).find("motor_0802_19000kv"))
	out.append(TestResult.new(
		"[finder] a sub-10 g motor keeps its decimal",
		small.contains("3.2 g"),
		"row = \"%s\"" % small))

	return out


# ---------------------------------------------------------------------------
# QC1 — typing. §4 names four queries by example; each gets its own check, because a loop over
# four cases fails once and the failure count stops meaning anything.
# ---------------------------------------------------------------------------

static func _query_checks() -> Array:
	var out: Array = []
	var catalog := _catalog()
	var total: int = catalog.list_category("motor").size()

	# By name — the accelerator for someone who already knows what they want.
	var by_name := _finder(catalog)
	by_name.set_query("2207")
	out.append(TestResult.new(
		"[finder] \"2207\" narrows to the 2207s by name",
		by_name.visible_parts().size() > 0 and by_name.visible_parts().size() < total
			and _ids(by_name.visible_parts()).has("motor_2207_1960kv"),
		"%d of %d: %s" % [by_name.visible_parts().size(), total, _ids(by_name.visible_parts())]))

	var by_kv := _finder(catalog)
	by_kv.set_query("1960")
	out.append(TestResult.new(
		"[finder] \"1960\" narrows by the KV in the name",
		by_kv.visible_parts().size() > 0 and by_kv.visible_parts().size() < total
			and _ids(by_kv.visible_parts()).has("motor_2207_1960kv"),
		"%d of %d: %s" % [by_kv.visible_parts().size(), total, _ids(by_kv.visible_parts())]))

	# By a SPEC field no part name contains. This is the check that proves the query reads the
	# derived catalog values and not just the name — "freestyle" appears in no motor's name.
	var by_use := _finder(catalog)
	by_use.set_query("freestyle")
	out.append(TestResult.new(
		"[finder] \"freestyle\" narrows by intended use, which appears in no part name",
		by_use.visible_parts().size() > 0 and by_use.visible_parts().size() < total
			and not _ids(by_use.visible_parts()).has("motor_2807_1300kv"),
		"%d of %d: %s" % [by_use.visible_parts().size(), total, _ids(by_use.visible_parts())]))

	# By a stator class — the second spec field, and the one whose spelling ("22xx") exists in no
	# part name either.
	var by_stator := _finder(catalog)
	by_stator.set_query("22xx")
	out.append(TestResult.new(
		"[finder] \"22xx\" narrows by stator class",
		by_stator.visible_parts().size() > 0 and by_stator.visible_parts().size() < total
			and _ids(by_stator.visible_parts()).has("motor_xing2_2207_1750kv"),
		"%d of %d: %s" % [by_stator.visible_parts().size(), total, _ids(by_stator.visible_parts())]))

	# Two words AND together, or "2207 freestyle" returns every freestyle motor and the second word
	# is decoration.
	var two_words := _finder(catalog)
	two_words.set_query("22xx racing")
	out.append(TestResult.new(
		"[finder] two words are ANDed, not ORed",
		_ids(two_words.visible_parts()) == ["motor_2207_2400kv"],
		"%s" % [_ids(two_words.visible_parts())]))

	# Case is not a gate either: nobody types "22XX" and deserves an empty screen for it.
	var shouted := _finder(catalog)
	shouted.set_query("FREESTYLE")
	out.append(TestResult.new(
		"[finder] the query is case-insensitive",
		shouted.visible_parts().size() == by_use.visible_parts().size(),
		"%d vs %d for lower case" % [shouted.visible_parts().size(), by_use.visible_parts().size()]))

	# Clearing the box goes back to browse mode. A finder you can only narrow is a finder a
	# beginner gets stuck in.
	var cleared := _finder(catalog)
	cleared.set_query("22xx")
	cleared.set_query("")
	out.append(TestResult.new(
		"[finder] clearing the query returns the whole category",
		cleared.visible_parts().size() == total,
		"%d of %d" % [cleared.visible_parts().size(), total]))

	return out


# ---------------------------------------------------------------------------
# QC1 — refusing. The rule is INHERITED from part_picker.gd's header, rule two, so the wording is
# asserted against PartPicker's own sentence rather than against a string this suite likes.
# ---------------------------------------------------------------------------

static func _refusal_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	finder.set_query("zzzznotamotor")

	out.append(TestResult.new(
		"[finder] a query matching nothing matches nothing",
		finder.visible_parts().is_empty(),
		"%d visible" % finder.visible_parts().size()))

	# The rail's distinction, kept: an empty list with no explanation is indistinguishable from a
	# broken catalog load, so there is a ROW and it says why.
	out.append(TestResult.new(
		"[finder] the empty result is a row that explains itself, not a void",
		finder.row_count() == 1 and finder.row_text(0) == "No motor matches these filters",
		"%d row(s), row 0 = \"%s\"" % [finder.row_count(), finder.row_text(0)]))

	# In part_picker's words, not this suite's. Asserted against the rail's own noun formula so a
	# reworded refusal here has to be a deliberate divergence from it.
	out.append(TestResult.new(
		"[finder] in the wording the rail already uses",
		finder.no_match_text() == "No %s matches these filters" % "motor",
		"\"%s\"" % finder.no_match_text()))

	out.append(TestResult.new(
		"[finder] the refusal notice is shown",
		finder.empty_state_visible(),
		"empty state visible = %s" % finder.empty_state_visible()))

	# The refusal names what was ASKED FOR. "Nothing matched" leaves a builder with two words typed
	# and no idea which one to drop.
	out.append(TestResult.new(
		"[finder] the notice quotes the query that failed",
		finder._empty_hint.text.contains("zzzznotamotor"),
		"\"%s\"" % finder._empty_hint.text))

	# The empty row cannot be arrowed onto and committed as though it were a part.
	# The index and not only the part: with nothing visible, `highlighted_part()` returns an empty
	# dictionary whatever the index says, so asserting the part alone is a check that cannot fail.
	# The index is what a later slice draws a highlight bar from, and on a refusal row that bar
	# would be pointing at a sentence.
	out.append(TestResult.new(
		"[finder] nothing is highlighted while nothing matches",
		finder.highlighted_index() == -1 and finder.highlighted_part().is_empty()
			and finder.accept().is_empty(),
		"highlighted index = %d" % finder.highlighted_index()))

	return out


# ---------------------------------------------------------------------------
# QC1 — the facets. Rule one of part_picker.gd's header, inherited: options come from the JSON.
# ---------------------------------------------------------------------------

static func _facet_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	var stators: Array = finder.filter_options("stator_class")

	out.append(TestResult.new(
		"[finder] facet values are derived from the catalog, not listed in GDScript",
		stators.has("22xx") and stators.has("08xx") and stators.size() > 3,
		"stator_class options = %s" % [stators]))

	# ALL first, so a chip row reads "All · 08xx · 11xx …" and the widening choice is the one
	# nearest the front.
	out.append(TestResult.new(
		"[finder] \"All\" leads the facet, so widening is always reachable",
		stators.size() > 0 and stators[0] == PartPicker.ALL,
		"first option = \"%s\"" % (stators[0] if stators.size() > 0 else "<none>")))

	var filtered := _finder(_catalog())
	filtered.set_filter("intended_use", "racing")
	out.append(TestResult.new(
		"[finder] setting a facet narrows the list",
		_ids(filtered.visible_parts()) == [
			"motor_2207_2400kv", "motor_speedx_gr2306_2450kv", "motor_2306_2450kv"],
		"%s" % [_ids(filtered.visible_parts())]))

	# A facet and a typed query compose. They are two ways of saying the same kind of thing, and a
	# builder who chips "racing" then types "2306" means both.
	filtered.set_query("2306")
	out.append(TestResult.new(
		"[finder] a facet and a query compose rather than replacing each other",
		_ids(filtered.visible_parts()) == ["motor_speedx_gr2306_2450kv", "motor_2306_2450kv"],
		"%s" % [_ids(filtered.visible_parts())]))

	return out


# ---------------------------------------------------------------------------
# QC2 — preview. §2's second defence: "arrowing through the list previews the part on the model",
# which is how a beginner learns the catalog exists at all.
# ---------------------------------------------------------------------------

static func _preview_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	var spy := FitterSpy.new()
	finder.set_fitter(spy)
	finder.open_on("motor_2207_1960kv")

	# Opening previews NOTHING. The fitted part is already on the build; re-fitting it would put a
	# spurious entry in the seam's log and make "how many previews happened" unanswerable.
	out.append(TestResult.new(
		"[finder] opening previews nothing — the fitted part is already fitted",
		spy.previewed.is_empty(),
		"previewed = %s" % [spy.previewed]))

	finder.move_highlight(1)
	out.append(TestResult.new(
		"[finder] arrowing down previews the newly highlighted part",
		spy.previewed.size() == 1 and spy.previewed[0] == str(finder.highlighted_part()["part_id"]),
		"previewed = %s, highlighted = %s" % [
			spy.previewed, finder.highlighted_part().get("part_id", "")]))

	finder.move_highlight(-1)
	out.append(TestResult.new(
		"[finder] arrowing back up previews again",
		spy.previewed.size() == 2 and spy.previewed[1] == "motor_2207_1960kv",
		"previewed = %s" % [spy.previewed]))

	# Provisional, not committed: nothing is chosen by looking at it.
	out.append(TestResult.new(
		"[finder] previewing commits nothing",
		spy.committed.is_empty(),
		"committed = %s" % [spy.committed]))

	# The highlight clamps at the ends rather than wrapping — wrapping from the last row to the
	# first previews a part eleven rows from the one being looked at, which reads as a glitch.
	var top := _finder(_catalog())
	top.open_on("")
	top.move_highlight(-1)
	out.append(TestResult.new(
		"[finder] arrowing up from the top stays at the top",
		top.highlighted_index() == 0,
		"index = %d" % top.highlighted_index()))

	# Enter commits what is highlighted, and that is the ONLY call that reaches commit_part.
	var committer := _finder(_catalog())
	var commit_spy := FitterSpy.new()
	committer.set_fitter(commit_spy)
	committer.open_on("motor_2207_1960kv")
	committer.move_highlight(2)
	var chosen := committer.accept()
	out.append(TestResult.new(
		"[finder] accept commits the highlighted part",
		commit_spy.committed == [str(chosen["part_id"])] and chosen["part_id"] != "motor_2207_1960kv",
		"committed = %s" % [commit_spy.committed]))

	out.append(TestResult.new(
		"[finder] accept restores nothing — the builder chose",
		commit_spy.restored.is_empty(),
		"restored = %s" % [commit_spy.restored]))

	return out


# ---------------------------------------------------------------------------
# QC2 — restore. "Escape restores the exact part that was fitted before opening", after ANY number
# of previews. Every check here arrows through SEVERAL parts, because with one preview the correct
# behaviour and the obvious wrong one (restore the last previewed part) are the same value.
# ---------------------------------------------------------------------------

static func _restore_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	var spy := FitterSpy.new()
	finder.set_fitter(spy)
	finder.open_on("motor_2207_1960kv")

	finder.move_highlight(1)
	finder.move_highlight(1)
	finder.move_highlight(1)
	finder.move_highlight(-2)
	var last_previewed: String = spy.previewed[spy.previewed.size() - 1]
	var restored := finder.cancel()

	out.append(TestResult.new(
		"[finder] cancel restores the part fitted when the finder opened, after four previews",
		str(restored.get("part_id", "")) == "motor_2207_1960kv",
		"restored %s after previewing %s" % [restored.get("part_id", ""), spy.previewed]))

	# Stated as its own check, against the value the wrong implementation would have produced. The
	# check above would also pass if the last preview HAPPENED to be the original; this one names
	# the confusion directly.
	out.append(TestResult.new(
		"[finder] and not the last part previewed, which is what the builder just declined",
		last_previewed != "motor_2207_1960kv"
			and str(restored.get("part_id", "")) != last_previewed,
		"last previewed = %s, restored = %s" % [last_previewed, restored.get("part_id", "")]))

	# The seam is told, not merely the caller. A cancel that returns the right dictionary while
	# leaving the build on the previewed part is the defect wearing the fix's clothes.
	out.append(TestResult.new(
		"[finder] the build is told to restore, through the same seam the previews went down",
		spy.restored == ["motor_2207_1960kv"],
		"restored calls = %s" % [spy.restored]))

	out.append(TestResult.new(
		"[finder] cancel commits nothing",
		spy.committed.is_empty(),
		"committed = %s" % [spy.committed]))

	# Typing does not disturb the snapshot. The original is held as the RECORD; an index into the
	# visible list would point at a different motor — or at nothing — once a query has narrowed it.
	var typed := _finder(_catalog())
	var typed_spy := FitterSpy.new()
	typed.set_fitter(typed_spy)
	typed.open_on("motor_2207_1960kv")
	typed.move_highlight(1)
	typed.set_query("28xx")
	typed.move_highlight(1)
	out.append(TestResult.new(
		"[finder] cancel restores the original even when the query has hidden it",
		str(typed.cancel().get("part_id", "")) == "motor_2207_1960kv",
		"restored = %s while showing %s" % [
			typed_spy.restored, _ids(typed.visible_parts())]))

	# A second open takes a NEW snapshot. A finder that kept the first one would put a builder's
	# third session back on the motor from their first.
	var reopened := _finder(_catalog())
	reopened.open_on("motor_2207_1960kv")
	reopened.move_highlight(1)
	reopened.accept()
	reopened.open_on("motor_2306_2450kv")
	reopened.move_highlight(1)
	out.append(TestResult.new(
		"[finder] reopening re-snapshots — cancel restores the CURRENT fit, not the first one",
		str(reopened.cancel().get("part_id", "")) == "motor_2306_2450kv",
		"restored = %s" % reopened.cancel().get("part_id", "")))

	# Nothing fitted yet, so there is nothing to put back. Restoring an empty dictionary onto the
	# build would unfit whatever the builder previewed and call it a restore.
	var fresh := _finder(_catalog())
	var fresh_spy := FitterSpy.new()
	fresh.set_fitter(fresh_spy)
	fresh.open_on("")
	fresh.move_highlight(1)
	fresh.move_highlight(1)
	out.append(TestResult.new(
		"[finder] with nothing fitted, cancel restores nothing rather than an empty part",
		fresh.cancel().is_empty() and fresh_spy.restored.is_empty(),
		"restore calls = %s" % [fresh_spy.restored]))

	# The finder works with no fitter at all — QC1's tests construct one that way, and the shell
	# does not exist yet. A null seam must be a quiet no-op, not a crash on the first arrow key.
	var unwired := _finder(_catalog())
	unwired.open_on("motor_2207_1960kv")
	unwired.move_highlight(1)
	unwired.move_highlight(1)
	out.append(TestResult.new(
		"[finder] with no fitter injected, previewing and cancelling are quiet no-ops",
		str(unwired.cancel().get("part_id", "")) == "motor_2207_1960kv",
		"restored = %s" % unwired.cancel().get("part_id", "")))

	return out


# ---------------------------------------------------------------------------
# The tooltip that repeated the row it covered.
#
# `ItemList` falls back to an item's own text when no tooltip is set, so every row in the finder
# carried a floating copy of itself, drawn over the row the cursor was on. The fix suppresses the
# tooltip per row and keeps it for the one case where it says something new — a label too long for
# the column.
#
# Three checks and not one, because the three ways this can be wrong fail independently: the
# tooltip can be on when the row fits (the defect), off when the row is cut off (the repair
# overshooting and hiding information), and the popup can be drawn on top of the hovered row even
# when it is the right popup to show.
# ---------------------------------------------------------------------------

static func _tooltip_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())

	# EVERY ROW ON THE MOTOR SHELF, not a sample. A suppression that missed one row would be a
	# tooltip that appeared on one motor out of eighteen, which reads as a glitch and is the exact
	# shape of an off-by-one in the loop that sets it.
	var repeats: Array = []
	for i in finder.row_count():
		var tip := finder.row_tooltip(i)
		if tip != "" and tip == finder.row_text(i):
			repeats.append(finder.row_text(i))
	out.append(TestResult.new(
		"[finder] no row shows a tooltip that only repeats the row",
		repeats.is_empty(),
		"%d of %d rows repeat themselves: %s" % [
			repeats.size(), finder.row_count(), repeats.slice(0, 3)]))

	# AND THE CASE THE TOOLTIP IS FOR IS STILL SERVED. A row wide enough to be cut off keeps it,
	# because there the popup is the only way to read the end of the name. Asserted against
	# `_row_is_truncated` on a string long enough that no plausible column width fits it.
	var long_row := "X".repeat(120)
	out.append(TestResult.new(
		"[finder] a row too long for the column is still judged truncated",
		finder._row_is_truncated(long_row) and not finder._row_is_truncated("2207 1960KV   32 g"),
		"120 chars truncated = %s, a real row truncated = %s, the column fits %.0f px" % [
			finder._row_is_truncated(long_row),
			finder._row_is_truncated("2207 1960KV   32 g"),
			finder.row_text_width()]))

	# AND WHEN IT DOES APPEAR IT DOES NOT COVER THE ROW UNDER THE CURSOR. The engine puts a tooltip
	# a few pixels below the cursor, which over a 20 px row lands on the row itself; the list's own
	# `_make_custom_tooltip` is the only lever, and it insets the popup downward.
	var tip_control := finder._list._make_custom_tooltip("H743 30.5x30.5   12 g") as MarginContainer
	var drop: int = tip_control.get_theme_constant("margin_top") if tip_control != null else 0
	out.append(TestResult.new(
		"[finder] the tooltip it does show is dropped clear of the row under the cursor",
		tip_control != null and drop >= 16,
		"the tooltip is inset %d px below the cursor" % drop))

	return out


# ---------------------------------------------------------------------------
# The scrollbar standing on the words.
#
# QC5 widened the bar from zero so it could be SEEN; it did not move the rows out from under it,
# and the screenshot showed `GEPRC SPEEDX2 2107.5 1960KV  30 g` running beneath the grabber. The
# two are separate defects and the first check stayed green through the second.
# ---------------------------------------------------------------------------

static func _gutter_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())

	out.append(TestResult.new(
		"[finder] the list reserves a gutter wide enough for the scrollbar that stands in it",
		finder.row_gutter() >= finder.scrollbar_width(),
		"the gutter is %.0f px, the scrollbar %.0f px" % [
			finder.row_gutter(), finder.scrollbar_width()]))

	# And the gutter is taken OUT of the column rather than added to it: a fix that widened the
	# overlay to make room would have undone the density pass in the same commit.
	out.append(TestResult.new(
		"[finder] the gutter comes out of the list, not out of the window",
		finder.row_text_width() < PartFinder.LIST_WIDTH
			and PartFinder.LIST_WIDTH <= PartFinder.PANEL_WIDTH,
		"rows have %.0f px of a %.0f px list in a %.0f px column" % [
			finder.row_text_width(), PartFinder.LIST_WIDTH, PartFinder.PANEL_WIDTH]))

	return out


# ---------------------------------------------------------------------------
# Density. The finder was laid out at the shell's body scale and read as a page.
#
# Asserted against the theme's own published scales rather than against bare numbers, so a later
# change to the type ramp moves these with it instead of breaking them.
# ---------------------------------------------------------------------------

static func _density_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())

	var title_size: int = finder._header.get_theme_font_size("font_size")
	out.append(TestResult.new(
		"[finder] the title is a picker's, not a page's",
		title_size <= LothalTheme.FONT_SIZE_SUBTITLE,
		"the title is %d px, the page scale is %d" % [title_size, LothalTheme.FONT_SIZE_TITLE]))

	var row_size: int = finder._list.get_theme_font_size("font_size")
	out.append(TestResult.new(
		"[finder] the rows are set one step down from body, and no smaller than the legible floor",
		row_size < LothalTheme.FONT_SIZE_BODY and row_size >= LothalTheme.FONT_SIZE_SMALL,
		"rows are %d px against a body of %d and a floor of %d" % [
			row_size, LothalTheme.FONT_SIZE_BODY, LothalTheme.FONT_SIZE_SMALL]))

	# The column itself, which is what covers the aircraft. 368 was QC5's.
	out.append(TestResult.new(
		"[finder] the column is narrower than the one it replaces",
		PartFinder.PANEL_WIDTH <= 320.0,
		"the column is %.0f px wide" % PartFinder.PANEL_WIDTH))

	return out


# ---------------------------------------------------------------------------
# The way out. §4 gave the finder Escape and nothing a mouse could reach.
# ---------------------------------------------------------------------------

static func _close_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())

	out.append(TestResult.new(
		"[finder] there is a close control in the panel, by name",
		finder.close_label() == "×",
		"the close control reads \"%s\"" % finder.close_label()))

	# AND IT IS WIRED. Pressing the BUTTON — not emitting the signal by hand — has to reach the
	# shell's seam, or the × is a decoration that dismisses nothing.
	var heard: Array = []
	finder.close_requested.connect(func() -> void: heard.append("closed"))
	finder.press_close()
	out.append(TestResult.new(
		"[finder] pressing it asks to be closed",
		heard == ["closed"],
		"the finder emitted %s" % [heard])) 

	# AND CLOSING COMMITS NOTHING. The shell routes the × to `close_finder`, which cancels — so the
	# seam must see a restore and never a commit, after several previews.
	var spy := FitterSpy.new()
	var cancelling := _finder(_catalog())
	cancelling.set_fitter(spy)
	cancelling.open_on("motor_2207_1960kv")
	cancelling.move_highlight(1)
	cancelling.move_highlight(1)
	cancelling.cancel()
	out.append(TestResult.new(
		"[finder] closing leaves the build wearing what it had, and commits nothing",
		spy.committed.is_empty() and spy.restored == ["motor_2207_1960kv"],
		"committed = %s, restored = %s" % [spy.committed, spy.restored]))

	return out


# ---------------------------------------------------------------------------
# The squeeze. The column's height was a sum of constants and a `PanelContainer` obliges its
# child's minimum, so on a short window the list, the scrollbar's bottom and both authoring
# buttons drew through the bottom edge — a `Control` does not clip.
# ---------------------------------------------------------------------------

static func _squeeze_checks() -> Array:
	var out: Array = []
	var finder := _finder(_catalog())
	finder.set_actions("New custom motor…")

	var full := finder.fit_to_height(10000.0)
	out.append(TestResult.new(
		"[finder] given room, the list asks for its full height and no more",
		is_equal_approx(full, PartFinder.LIST_HEIGHT),
		"the list asked for %.0f px against a maximum of %.0f" % [full, PartFinder.LIST_HEIGHT]))

	# THE CASE THE SCREENSHOT SHOWED. A short window, and the list has to give ground rather than
	# the column overflowing it.
	var squeezed := finder.fit_to_height(200.0)
	out.append(TestResult.new(
		"[finder] on a window with less room, the LIST shrinks rather than the column overflowing",
		squeezed < full and finder.list_height() == squeezed,
		"the list shrank from %.0f px to %.0f" % [full, squeezed]))

	# And it stops being a list before it stops being visible. A squeeze to nothing would satisfy
	# "it fits" while deleting the thing the overlay is for.
	out.append(TestResult.new(
		"[finder] and never squeezes below a browsable list",
		finder.fit_to_height(0.0) >= PartFinder.LIST_HEIGHT_MIN,
		"squeezed to %.0f px against a floor of %.0f" % [
			finder.fit_to_height(0.0), PartFinder.LIST_HEIGHT_MIN]))

	return out
