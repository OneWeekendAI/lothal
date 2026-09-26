class_name FailsafeSettings
extends RefCounted
## WHAT THIS AIRCRAFT IS CONFIGURED TO DO WHEN THE LINK DROPS, and whether bidirectional DShot was
## asked for — config-room design §4.4, slice C6. The sibling of `PortBudget` and
## `MotorLayout.spin_map`, and written to their rule: ONE ACCESSOR, so the panel, the checks and
## anything downstream cannot come to say it three different ways.
##
## Both values live in the drone's `config` decision block (C1). Both are per-build, because both
## describe THIS aircraft — §6 — and versions snapshot the whole block, so a failsafe change lands
## in a named version for free.
##
## ---------------------------------------------------------------------------
## WHOSE DEFAULT IT IS, SAID OUT LOUD
## ---------------------------------------------------------------------------
##
## Stage 2 defaults to DROP. That is not Lothal's advice about what your quad should do — it is
## BETAFLIGHT'S OWN DEFAULT, and design §8's fifth row ships it quoted as Betaflight's for exactly
## the reason every other guess in this room carries a label: a recommendation and a quoted default
## are different kinds of claim, and a builder is entitled to know which one they are reading.
##
## So an untouched drone and a chosen one DO NOT READ THE SAME. `stage2_provenance` separates them
## and `stage2_sentence` says it in words; the panel prints the sentence whole rather than writing
## its own from the value, which is how a label gets lost.
##
## WHAT IS DELIBERATELY NOT HERE: simulating the link drop. Design §4.4 refuses it — receivers are
## physics-inert, carrying three dimensions and nothing else, so there is nothing to trigger a
## failsafe with. The room says what failsafe will do; it does not show it happening.

## Where each value lives in the `config` block.
const STAGE2_KEY := "failsafe_stage2"
const BIDIR_KEY := "bidir_dshot"

## The three stage-2 behaviours, as they are stored. Constants rather than literals so a check and
## a panel cannot disagree by a spelling — `PortBudget`'s provenance constants exist for the same
## reason.
const DROP := "drop"
const LAND := "land"
const GPS_RESCUE := "gps_rescue"

## Betaflight's own, and the reason `BETAFLIGHT_DEFAULT` exists as a provenance at all.
const DEFAULT_STAGE2 := DROP

## The two provenances a stage-2 setting can have. Not confidence levels: different kinds of fact.
## BETAFLIGHT_DEFAULT is a value quoted from somewhere else; CHOSEN is the builder's own decision.
const BETAFLIGHT_DEFAULT := "betaflight_default"
const CHOSEN := "chosen"

## The behaviours in the order they are offered, with the words a builder reads. Drop first because
## it is the default, and the labels are the Configurator's own vocabulary rather than Lothal's.
const STAGE2_CHOICES := [
	{"value": DROP, "label": "Drop — cut the motors"},
	{"value": LAND, "label": "Land — descend under power"},
	{"value": GPS_RESCUE, "label": "GPS rescue — fly home"},
]


## The stage-2 behaviour in force. An absent, malformed or unrecognised value reads as the default,
## which is the only honest answer to a setting that was never made.
static func stage2(config: Dictionary) -> String:
	var raw := str(config.get(STAGE2_KEY, ""))
	return raw if _is_stage2(raw) else DEFAULT_STAGE2


## Where the value in force came from — the thing that must never be silent.
static func stage2_provenance(config: Dictionary) -> String:
	return CHOSEN if _is_stage2(str(config.get(STAGE2_KEY, ""))) else BETAFLIGHT_DEFAULT


## The behaviour and its provenance IN ONE SENTENCE, on `PortBudget`'s rule: the caller pastes this
## whole rather than picking the value out and writing its own, because a caller that wrote its own
## is precisely how a quoted default comes to read as a recommendation.
static func stage2_sentence(config: Dictionary) -> String:
	var label := label_for(stage2(config))
	if stage2_provenance(config) == CHOSEN:
		return "Stage 2 failsafe: %s — your setting for this build." % label
	return ("Stage 2 failsafe: %s. That is Betaflight's own default, quoted as Betaflight's and "
		+ "not as Lothal's advice about what yours should do — choose it here.") % label


## Stores a stage-2 behaviour, or refuses one that is not a behaviour.
##
## AN UNRECOGNISED VALUE IS NOT STORED. It would otherwise reach the cross-checks looking exactly
## like something the builder chose, and every check here is written against what they chose.
static func set_stage2(config: Dictionary, value: String) -> void:
	if not _is_stage2(value):
		return
	config[STAGE2_KEY] = value


## Whether the builder has asked for bidirectional DShot (and the RPM filtering that rides on it).
## The SETTING; whether the ESC can do it is a separate question, and asking both at once is the
## cross-check `ConfigPlausibility` makes.
static func bidir_dshot(config: Dictionary) -> bool:
	return bool(config.get(BIDIR_KEY, false))


## Turning it off ERASES rather than storing `false`: a build carrying no opinion and a build
## carrying "no" are the same aircraft, and the smaller file is the one that round-trips cleanly.
static func set_bidir_dshot(config: Dictionary, on: bool) -> void:
	if on:
		config[BIDIR_KEY] = true
		return
	config.erase(BIDIR_KEY)


## The words for one behaviour, or the stored value itself if it is somehow not one of the three —
## which `set_stage2` prevents, and which is still better shown than swallowed.
static func label_for(value: String) -> String:
	for choice in STAGE2_CHOICES:
		if String(choice["value"]) == value:
			return String(choice["label"])
	return value


static func _is_stage2(value: String) -> bool:
	for choice in STAGE2_CHOICES:
		if String(choice["value"]) == value:
			return true
	return false
