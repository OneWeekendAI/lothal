class_name TestEscBench
extends RefCounted
## The ESC bench (labs-and-sim.md §2.1) — a board swept against the motors actually chosen, and
## current per channel against the rating per channel.
##
## The assertions are chosen so that a bench which merely LOOKS right fails. There are two ways to
## draw a convincing ESC bench that teaches the wrong lesson, and both of them resemble a working
## feature:
##
##   1. CAP THE SWEEP WITH THE THING UNDER TEST. Every other room commands throttle through
##      Build.max_throttle_fraction(), which is already clamped by the ESC. A bench that did the
##      same would ask what the motors draw once the board had already stopped them, so the draw
##      would walk up to the rating and stop — and every board in the catalog would report exactly
##      enough headroom for itself. Checked by requiring an undersized board to be driven PAST its
##      rating, with a crossing point on the chart.
##   2. CONFUSE THE BOARD WITH THE CHANNEL. A "60 A 4-in-1" is four 60 A channels. Read as 60 A for
##      the whole aircraft, every board becomes the binding constraint on every build; read the
##      other way — the 240 A total against one motor's draw — every board has enormous headroom.
##      Checked against both figures separately, and against hand-computed margins.
##
## THE HEADROOM CHECK FAILS IN BOTH DIRECTIONS, which is the only way it means anything. Asserting
## that the reference build's board is adequate proves nothing on its own — so an undersized board
## is asserted insufficient and an adequate one sufficient, against pairings worked out on paper
## from escs.json and motors.json before any of this was run:
##
##   motor_2207_1960kv is rated 32 A, and its amp figure was measured on prop_5x43x3 — the prop
##   fitted here — so one motor pulls 32 A flat out and nothing about the prop scales it.
##     esc_4in1_20a_20x20 passes 20 A a channel  ->  20 - 32 = -12 A. Undersized.
##     esc_4in1_60a_30x30 passes 60 A a channel  ->  60 - 32 = +28 A. Ample.
##
## Every Control built here is freed, or the runner emits leaked-RID ERROR lines that read like
## failures.

const DT := 1.0 / 60.0

## Worked out by hand from the two spec sheets — see the header. Both boards are run against the
## same motors and the same prop, so the only thing that differs between the two verdicts is the
## board, exactly as only the pack differs between the battery bench's two traces.
const UNDERSIZED_ESC := "esc_4in1_20a_20x20"
const ADEQUATE_ESC := "esc_4in1_60a_30x30"
const MOTOR_RATED_A := 32.0
const UNDERSIZED_RATING_A := 20.0
const ADEQUATE_RATING_A := 60.0

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_ratings_are_per_channel(catalog))
	results.append_array(_test_headroom_fails_in_both_directions(catalog))
	results.append_array(_test_the_sweep_is_not_capped_by_the_board_under_test(catalog))
	results.append_array(_test_the_chart_is_a_rating_and_a_draw(catalog))
	results.append_array(_test_burst_is_never_quoted_as_a_limit(catalog))
	results.append_array(_test_it_names_what_runs_out_first(catalog))
	results.append_array(_test_it_is_a_room_of_its_own())

	return results


static func _bench(catalog: PartsCatalog, esc_id: String,
		motor_id: String = ReferenceBuild.MOTOR_ID,
		prop_id: String = ReferenceBuild.PROPELLER_ID,
		battery_id: String = ReferenceBuild.BATTERY_ID) -> EscBenchScreen:
	return EscBenchScreen.new(catalog, motor_id, prop_id, battery_id, esc_id)


## Runs a sweep to completion. The bench stops itself at the top of the ramp, so the guard is
## against a bench that never stops rather than a chosen duration.
static func _sweep(bench: EscBenchScreen) -> void:
	bench.start_sweep()
	var guard := 0
	while bench.running and guard < 100000:
		bench.advance(DT)
		guard += 1


# ---------------------------------------------------------------------------
# Per channel, not per board
# ---------------------------------------------------------------------------

static func _test_ratings_are_per_channel(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, ADEQUATE_ESC)
	var build := bench.current_build()
	var reading := bench.readings()

	# The rating the bench compares against is ONE CHANNEL's, and the board total is a separate
	# figure. Conflating them is the mistake escs.json's schema exists to warn about, and it fails
	# in the most expensive available direction.
	results.append(TestResult.new(
		"the bench compares against the PER-CHANNEL rating, and reports the board total separately",
		is_equal_approx(reading["rating_a"], ADEQUATE_RATING_A)
			and is_equal_approx(build.esc_max_amps(), ADEQUATE_RATING_A * 4.0)
			and reading["channels"] == 4,
		"%.0f A a channel across %d channels, %.0f A in total" % [
			reading["rating_a"], reading["channels"], build.esc_max_amps()]
	))

	# The draw is one motor's, not four motors'. The same conflation, on the other side of the
	# comparison, and it would report every board in the catalog as the binding constraint.
	_sweep(bench)
	var after := bench.readings()
	results.append(TestResult.new(
		"the draw the bench plots is one channel's, which is a quarter of what the pack delivers",
		after["draw_total_a"] > 0.0
			and absf(after["draw_per_channel_a"] - after["draw_total_a"] / 4.0) < 1e-6,
		"%.1f A a channel against %.1f A total" % [
			after["draw_per_channel_a"], after["draw_total_a"]]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# The headroom verdict, in both directions
# ---------------------------------------------------------------------------

static func _test_headroom_fails_in_both_directions(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# The demand this whole bench is measured against, checked against the spec sheet first: with
	# the prop the motor's own amp figure was measured on, one motor pulls exactly its rating.
	var probe := _bench(catalog, ADEQUATE_ESC)
	var demand: float = probe.readings()["demand_per_channel_a"]
	results.append(TestResult.new(
		"one motor's demand is its rated current on the prop that rating was measured with",
		absf(demand - MOTOR_RATED_A) < 0.01,
		"%s pulls %.2f A flat out, rated %.0f A" % [
			probe.current_build().motor["name"], demand, MOTOR_RATED_A]
	))
	probe.free()

	var small := _bench(catalog, UNDERSIZED_ESC)
	var small_read := small.readings()
	results.append(TestResult.new(
		"an undersized board reports INSUFFICIENT headroom, by the margin the two sheets give",
		not small_read["has_headroom"]
			and absf(small_read["headroom_a"] - (UNDERSIZED_RATING_A - MOTOR_RATED_A)) < 0.01,
		"%s: %.0f A a channel against %.0f A demanded — headroom %+.1f A (hand-computed %+.0f A)" % [
			small.current_build().esc["name"], small_read["rating_a"], demand,
			small_read["headroom_a"], UNDERSIZED_RATING_A - MOTOR_RATED_A]
	))
	small.free()

	var big := _bench(catalog, ADEQUATE_ESC)
	var big_read := big.readings()
	results.append(TestResult.new(
		"an adequate board reports SUFFICIENT headroom, by the margin the two sheets give",
		big_read["has_headroom"]
			and absf(big_read["headroom_a"] - (ADEQUATE_RATING_A - MOTOR_RATED_A)) < 0.01,
		"%s: %.0f A a channel against %.0f A demanded — headroom %+.1f A (hand-computed %+.0f A)" % [
			big.current_build().esc["name"], big_read["rating_a"], demand,
			big_read["headroom_a"], ADEQUATE_RATING_A - MOTOR_RATED_A]
	))
	big.free()

	return results


# ---------------------------------------------------------------------------
# The bench must not be capped by the thing it is testing
# ---------------------------------------------------------------------------

## The assertion the whole bench stands on. Build.max_throttle_fraction() is already clamped by the
## ESC, so a sweep driven through it walks the draw up to the rating and stops there — no crossing,
## no overshoot, and a confident report that every board in the catalog is adequate. The ceiling
## here has to come from the motors alone.
static func _test_the_sweep_is_not_capped_by_the_board_under_test(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, UNDERSIZED_ESC)
	_sweep(bench)
	var reading := bench.readings()

	results.append(TestResult.new(
		"an undersized board is driven PAST its rating, rather than up to it and no further",
		reading["draw_per_channel_a"] > reading["rating_a"] * 1.2
			and reading["worst_overshoot_a"] > 1.0,
		"one channel reached %.1f A against a %.0f A rating — %.1f A over" % [
			reading["draw_per_channel_a"], reading["rating_a"], reading["worst_overshoot_a"]]
	))

	# ...and the throttle at which it crossed is reported, which is the second thing §2.1 asks this
	# bench for. Read off the trace, so it is a point that is genuinely on the chart.
	var crossing: float = reading["crossing_throttle"]
	results.append(TestResult.new(
		"the throttle at which the board becomes the binding constraint is named",
		crossing > 0.0 and crossing < 1.0,
		"crosses its rating at %.0f%% throttle" % (crossing * 100.0)
	))
	bench.free()

	# The other half: an adequate board is swept just as hard and never crosses. If the sweep were
	# capped by the board this would pass trivially, which is why it is stated alongside the one
	# above rather than on its own.
	var big := _bench(catalog, ADEQUATE_ESC)
	_sweep(big)
	var big_read := big.readings()
	results.append(TestResult.new(
		"the same sweep on an adequate board never reaches its rating, so there is no crossing",
		big_read["crossing_throttle"] < 0.0
			and big_read["draw_per_channel_a"] < big_read["rating_a"]
			and big_read["draw_per_channel_a"] > UNDERSIZED_RATING_A,
		"one channel reached %.1f A against a %.0f A rating, never crossing" % [
			big_read["draw_per_channel_a"], big_read["rating_a"]]
	))
	big.free()

	return results


# ---------------------------------------------------------------------------
# The chart — the deliverable of this bench
# ---------------------------------------------------------------------------

static func _test_the_chart_is_a_rating_and_a_draw(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, UNDERSIZED_ESC)

	results.append(TestResult.new(
		"an unswept bench holds no trace and draws no current — arriving costs nothing",
		bench.trace.sample_count() == 0 and not bench.running and bench.throttle == 0.0,
		"%d samples, running=%s" % [bench.trace.sample_count(), bench.running]
	))

	_sweep(bench)

	results.append(TestResult.new(
		"sweeping the throttle plots a trace against THROTTLE, not against time",
		bench.trace.sample_count() > 20
			and bench.trace.x_axis == BandTrace.XAxis.FRACTION
			and bench.trace.span() > 0.5,
		"%d samples out to %.0f%% throttle" % [
			bench.trace.sample_count(), bench.trace.span() * 100.0]
	))

	# The rating line is FLAT — a rating does not move — and the draw line rises. A chart that
	# plotted the rating as anything but a constant would be deriving it from something.
	var rating := bench.trace.upper_series()
	var draw := bench.trace.lower_series()
	var flat := rating.size() > 1
	for i in rating.size():
		if absf(rating[i] - rating[0]) > 1e-4:
			flat = false
	results.append(TestResult.new(
		"the rating line is flat across the whole sweep and the draw line climbs through it",
		flat and draw[draw.size() - 1] > draw[0] and draw[draw.size() - 1] > rating[0],
		"rating held at %.1f A while the draw went %.1f A -> %.1f A" % [
			rating[0], draw[0], draw[draw.size() - 1]]
	))

	# Nothing drawn clipped to the axis. A draw line pinned to the top of its own chart reads as a
	# current that levelled off, which is the same lie the battery bench's resting line told when
	# its axis was sized for the wrong datum — told here in the more expensive direction.
	var clipped: Array = []
	for i in draw.size():
		if draw[i] > bench.trace.y_max or draw[i] < bench.trace.y_min:
			clipped.append("sample %d: %.1f A outside %.1f..%.1f A" % [
				i, draw[i], bench.trace.y_min, bench.trace.y_max])
	results.append(TestResult.new(
		"no part of the draw line is clipped to the axis, which would read as a false plateau",
		clipped.is_empty(),
		"axis %.0f..%.0f A holds all %d samples" % [
			bench.trace.y_min, bench.trace.y_max, draw.size()]
			if clipped.is_empty() else "; ".join(clipped)
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# Burst is carried and is not a limit
# ---------------------------------------------------------------------------

## labs-and-sim.md §2.1 is explicit that burst stays unmodelled, and that the bench must not quote a
## figure it cannot stand behind. It must also not silently omit it — it is printed next to the
## continuous rating on every product page. So: on the panel, and labelled.
static func _test_burst_is_never_quoted_as_a_limit(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, UNDERSIZED_ESC)
	_sweep(bench)
	var text := bench.instruments.readout_text()
	var reading := bench.readings()

	results.append(TestResult.new(
		"burst is shown, and shown as not modelled rather than as a second ceiling",
		text.has("burst") and text["burst"].contains("not modelled")
			and text["note_bottom"].to_lower().contains("burst")
			and text["note_bottom"].to_lower().contains("not modelled"),
		"burst row reads \"%s\"" % text.get("burst", "<absent>")
	))

	# The comparison the bench actually makes is against CONTINUOUS. If the rating line were the
	# burst figure, this undersized board would have looked adequate.
	results.append(TestResult.new(
		"the line the draw is judged against is the continuous rating, never the burst one",
		is_equal_approx(reading["rating_a"], bench.current_build().esc_continuous_a())
			and reading["burst_a"] > reading["rating_a"]
			and not reading["has_headroom"],
		"judged against %.0f A continuous, with %.0f A burst carried and unused" % [
			reading["rating_a"], reading["burst_a"]]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# ...and if it is not the board, what is
# ---------------------------------------------------------------------------

## The reason the binding constraint is reported by name rather than as a bare ceiling: "you are
## capped at 88% throttle" sends nobody anywhere, and the decision this bench exists to inform is
## whether the money goes on the board or on the pack.
static func _test_it_names_what_runs_out_first(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var small := _bench(catalog, UNDERSIZED_ESC)
	results.append(TestResult.new(
		"with an undersized board fitted, the board is what the build runs out of first",
		small.readings()["binding_component"] == "esc",
		"binding component: %s" % small.readings()["binding_component"]
	))
	small.free()

	# The reference pack is a 1500 mAh 75C — 112 A — against four 2207s wanting 128 A, so with an
	# ample board fitted it is the PACK that runs out first. That is the answer that sends a builder
	# to spend the money in the right place, and it is on the panel in words.
	var big := _bench(catalog, ADEQUATE_ESC)
	var text := big.instruments.readout_text()
	results.append(TestResult.new(
		"with an ample board fitted it names the pack instead, and says so in words",
		big.readings()["binding_component"] == "battery"
			and text["binding"].contains(big.current_build().battery["name"])
			and text["note_top"].contains(big.current_build().battery["name"]),
		"runs out first: \"%s\" — \"%s\"" % [text["binding"], text["note_top"]]
	))
	big.free()

	return results


# ---------------------------------------------------------------------------
# It is a room, and it is not there when you are not in it
# ---------------------------------------------------------------------------

## The same argument the other two benches and Sim already make: this room holds a powertrain
## draining a real pack, so "it costs nothing while you are choosing parts" has to be an absence
## rather than a paused flag.
static func _test_it_is_a_room_of_its_own() -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.lab.esc_picker.select_id(UNDERSIZED_ESC)
	shell.show_esc_bench()

	results.append(TestResult.new(
		"the ESC bench opens on the board chosen on Lab's rail, with no other room running",
		shell.esc_bench != null and shell.bench == null and shell.battery_bench == null
			and shell.sim == null
			and shell.esc_bench.current_build().esc["part_id"] == UNDERSIZED_ESC,
		"testing %s" % shell.esc_bench.current_build().esc["name"]
	))

	shell.show_lab()
	results.append(TestResult.new(
		"leaving frees it, so no pack drains behind Lab",
		shell.esc_bench == null and shell.showing_lab(),
		"esc_bench=%s" % shell.esc_bench
	))

	shell.free()
	return results
