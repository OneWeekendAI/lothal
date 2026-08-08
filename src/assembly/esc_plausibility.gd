class_name EscPlausibility
extends RefCounted
## What a build says about an ESC whose numbers came from a builder rather than from the catalog.
##
## The custom-parts sibling to FramePlausibility, MotorPlausibility, PropPlausibility and
## BatteryPlausibility, and the same rules hold: nothing here blocks anything (labs-and-sim.md §2
## warns and never blocks — the refusals are all in CustomEscs, where the alternative is silence),
## and every bound is read off the SHIPPED catalog rather than invented here.
##
## ---------------------------------------------------------------------------
## THE PER-BOARD / PER-CHANNEL CHECK, WHICH IS WHY THIS FILE EXISTS
## ---------------------------------------------------------------------------
##
## escs.json's `_schema` names this as the single most important thing to get right, and a builder
## entering their own board is the first person in the project who can get it wrong. A "60A 4-in-1"
## is four 60 A channels. Its product page prints 60. Its box may well print 240.
##
## Detecting "a large number" would be useless — an 80 A board is in the shipped catalog and a 100 A
## board is a real product. What is detectable is the SHAPE of the mistake: a figure above anything
## the catalog stocks per channel, which becomes an ordinary per-channel figure when divided by the
## channel count. That is not a heuristic about big numbers, it is the arithmetic of the error
## itself, and it is why the warning can name the mistake rather than merely observe that a number
## is unusual.
##
## The motor is quoted alongside, because an ESC rated far above the motor it feeds is a perfectly
## reasonable build — headroom is a thing people buy — and the builder needs both numbers to decide
## which of the two is actually wrong.
##
## ---------------------------------------------------------------------------
## burst BELOW continuous
## ---------------------------------------------------------------------------
##
## Not a board. A burst rating is by definition above the continuous one, so a board claiming
## otherwise has had the two fields swapped. It changes nothing in flight — `burst_a` binds nothing,
## deliberately (Build.esc_burst_a) — which is exactly why nothing else would ever mention it, and
## why an incoherent pair would otherwise sit in the file forever.

## The severity of the whole-board warning. LIMITING rather than CHARACTERISTIC: if this fires and
## the builder is right, nothing is wrong; if it fires and the builder made the mistake, the ESC has
## silently stopped limiting a build it should limit, and a cap the aircraft should have is missing.
## That is a claim about what constrains the build, which is what LIMITING is for.


## The span of per-channel continuous ratings the shipped catalog stocks, as {"min", "max", "count"}.
##
## Derived at call time from the catalog rather than hardcoded — the same argument
## MotorPlausibility.k_t_band_for_prop makes. Custom boards are excluded, or a builder's own typo
## would widen the very band meant to catch it.
static func continuous_a_span(catalog: PartsCatalog) -> Dictionary:
	var lowest := INF
	var highest := -INF
	var count := 0
	for board in catalog.list_category("esc"):
		var record := board as Dictionary
		if PartsCatalog.is_custom(str(record.get("part_id", ""))):
			continue
		var rating := float(record.get("specs", {}).get("continuous_a", 0.0))
		if rating <= 0.0:
			continue
		lowest = minf(lowest, rating)
		highest = maxf(highest, rating)
		count += 1
	if count == 0:
		return {"min": 0.0, "max": 0.0, "count": 0}
	return {"min": lowest, "max": highest, "count": count}


## Whether this rating has the shape of a whole-board figure entered where a per-channel one belongs.
##
## BOTH halves are required and neither alone would do. Above the catalog's span on its own catches
## every unusually strong board, including honest ones. Divisible into the span on its own is true
## of almost every rating there is. Together they say: this number is not a per-channel rating, and
## it would be one if you divided it by the channel count — which is the mistake, stated exactly.
static func looks_like_whole_board(continuous_a: float, channels: int, span: Dictionary) -> bool:
	if int(span["count"]) == 0 or channels < 2 or continuous_a <= 0.0:
		return false
	if continuous_a <= float(span["max"]):
		return false
	var per_channel := continuous_a / float(channels)
	return per_channel >= float(span["min"]) and per_channel <= float(span["max"])


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var esc: Dictionary = build.esc
	if not PartsCatalog.is_custom(str(esc.get("part_id", ""))):
		return out

	var continuous_a := build.esc_continuous_a()
	var burst_a := build.esc_burst_a()
	var channels := build.esc_channels()
	var span := continuous_a_span(build.catalog)

	if looks_like_whole_board(continuous_a, channels, span):
		var per_channel := continuous_a / float(channels)
		out.append(BuildWarning.limiting(&"esc_whole_board_rating",
			"%s is entered at %.0f A per channel, which is %.0f A across %d channels — did you enter the whole-board rating? Divided by %d it is %.0f A, which is an ordinary per-channel figure, and the catalog stocks %.0f-%.0f A per channel. The %s pulls %.0f A per motor at its own limit." % [
				esc.get("name", "The ESC"), continuous_a, continuous_a * float(channels), channels,
				channels, per_channel, float(span["min"]), float(span["max"]),
				build.motor["name"], float(build.motor["specs"]["max_amps"])],
			{"continuous_a": continuous_a, "channels": channels, "per_channel_if_divided": per_channel,
				"catalog_min_a": float(span["min"]), "catalog_max_a": float(span["max"]),
				"motor_max_amps": float(build.motor["specs"]["max_amps"])}))

	if burst_a > 0.0 and continuous_a > 0.0 and burst_a < continuous_a:
		out.append(BuildWarning.characteristic(&"esc_burst_below_continuous",
			"%s claims %.0f A burst against %.0f A continuous, which is the wrong way round — a burst rating is above the continuous one, so the two fields have most likely been swapped. Neither changes how this build flies: burst is carried and never used as a limit." % [
				esc.get("name", "The ESC"), burst_a, continuous_a],
			{"burst_a": burst_a, "continuous_a": continuous_a}))

	# The provenance warning every custom part carries. It restates the per-channel reading rather
	# than merely flagging the board as builder-entered, because that is the one thing about this
	# category worth repeating on every build it flies on.
	out.append(BuildWarning.characteristic(&"custom_esc",
		"%s is a board you entered: %.0f A continuous PER CHANNEL across %d channels (%.0f A total), %.0f g. Its numbers have not been validated against anything — \"%s\". Burst is carried and never modelled as a limit." % [
			esc.get("name", "This ESC"), continuous_a, channels, build.esc_max_amps(),
			build.esc_mass_g(), str(esc.get("source", "no source given"))],
		{"continuous_a": continuous_a, "channels": channels, "burst_a": burst_a,
			"mass_g": build.esc_mass_g()}))

	return out
