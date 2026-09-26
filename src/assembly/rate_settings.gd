class_name RateSettings
extends RefCounted
## THE PILOT'S NUMBERS — max rate, expo, and the two modes this sim flies — config-room design
## §2.3 and §4.1, slice C8. The sibling of `PortBudget` and `FailsafeSettings`, written to their
## rule: ONE ACCESSOR, so the panel, the sheet and anything downstream cannot come to say it three
## different ways.
##
## ---------------------------------------------------------------------------
## WHY THIS IS IN CONFIG AND THE PID TUNE IS NOT
## ---------------------------------------------------------------------------
##
## §2.3 is settled and is not re-opened here. A PID gain is a property of THIS AIRFRAME'S PLANT:
## it comes out of the frame bench, it changes when the frame changes, and `TunePanel` stays under
## Control beside the board it runs on. A rate is a property of the PILOT — the same number on
## every quad they own — so it lives here with the other things typed in once per build. Nothing
## in this file derives anything; there is no second tune.
##
## ---------------------------------------------------------------------------
## THE SIM-VERSUS-REAL STATEMENT, WHICH IS THE WHOLE POINT OF THE SLICE
## ---------------------------------------------------------------------------
##
## Lothal's inner loop is written against `RateModeController.MAX_RATE_RAD_S` — 800 deg/s at full
## stick — and that is a fact about the SIMULATOR, not about the aircraft being configured. A
## builder who practises here and then flies a quad set to 400 deg/s meets an aircraft that feels
## nothing like the one they learned on, and the most useful sentence this room can print is the
## one that says so BEFORE the maiden rather than after it.
##
## So two rules govern everything below:
##
##   THE SIM'S FIGURE IS DERIVED, NEVER RESTATED. `sim_max_rate_deg_s()` converts the loop's own
##   constant. A literal 800 here would be a second opinion about the normalisation the whole
##   controller is written against, and it would keep reading 800 on the day that changed.
##
##   PROVENANCE IS NEVER SILENT. An untouched build reads as the SIM's number, labelled as the
##   sim's; a set one is the builder's. Those are different KINDS of claim rather than two
##   confidence levels — the same separation `FailsafeSettings` makes between Betaflight's default
##   and a chosen behaviour — and `max_rate_sentence` exists so a caller pastes the label instead
##   of re-deriving it from the value and losing it.
##
## WHAT IS DELIBERATELY NOT HERE. Expo is STORED but NOT FLOWN: the sim's stick is linear, and
## `expo_sentence` admits that in the same breath as printing the number, because a curve that is
## carried on a config sheet is useful and a curve that looks simulated is a lie. Filter
## configuration is refused outright (§4.1, §9) — Lothal models a gyro and a PT1, and this is the
## one place §0.1's relaxation explicitly does not apply, because a merely-plausible filter setting
## gets typed into a real quad and flown. Switch assignment is not modelled either: the sim has two
## modes and a keystroke, and `modes_sentence` says that rather than drawing a channel map.

## Where each value lives in the drone's `config` block (C1's decision block). Per-build, never per
## app — design §6 — even though a rate is a pilot's habit, because versions snapshot the block and
## a builder who flies two quads at two rates has two builds.
const MAX_RATE_KEY := "max_rate_deg_s"
const EXPO_KEY := "rate_expo"

## The two provenances a max rate can have. Constants rather than literals so a check and a panel
## cannot disagree by a spelling — `PortBudget`'s exist for the same reason.
const SIM_DEFAULT := "sim_default"
const CHOSEN := "chosen"

## The band a stored rate must fall inside. The low end keeps an aircraft that cannot rotate out of
## the statement; the high end keeps a fat-fingered 9000 from printing as confidently as a real
## number. Neither is a recommendation and neither blocks anything: a refused value simply is not
## stored, so the sim's own figure — correctly labelled — comes back.
const MIN_SETTABLE_DEG_S := 10.0
const MAX_SETTABLE_DEG_S := 2000.0

## Below this the two figures are treated as the same number rather than as a comparison worth
## printing. Half a degree per second is far inside anything a radio can set.
const SAME_RATE_EPSILON_DEG_S := 0.5


## What the SIM flies at full stick, in deg/s. Derived from the loop's own normalisation — see the
## header. Not a `const`, because a const cannot call `rad_to_deg`, and hand-converting it here is
## exactly the restatement this function exists to prevent.
static func sim_max_rate_deg_s() -> float:
	return rad_to_deg(RateModeController.MAX_RATE_RAD_S)


## The max rate this aircraft is configured to fly. An absent or out-of-band value reads as the
## sim's, which is the only honest answer to a setting that was never made.
static func intended_max_rate_deg_s(config: Dictionary) -> float:
	var stored := float(config.get(MAX_RATE_KEY, 0.0))
	return stored if _is_settable(stored) else sim_max_rate_deg_s()


## Where the figure in force came from — the thing that must never be silent.
static func max_rate_provenance(config: Dictionary) -> String:
	return CHOSEN if _is_settable(float(config.get(MAX_RATE_KEY, 0.0))) else SIM_DEFAULT


## Stores a max rate, or refuses one that is not a rate.
##
## ZERO CLEARS IT, the way a zero port override does: a build carrying no opinion and a build
## carrying "0 deg/s" are not the same aircraft, and only one of them exists.
##
## SETTING THE SIM'S OWN FIGURE IS STILL A CHOICE and is stored as one. Demoting it to the default
## because the numbers happen to match would erase the difference between "I have not thought about
## this" and "I fly 800", which is the entire distinction this module keeps.
static func set_max_rate_deg_s(config: Dictionary, deg_s: float) -> void:
	if deg_s <= 0.0:
		config.erase(MAX_RATE_KEY)
		return
	if not _is_settable(deg_s):
		return
	config[MAX_RATE_KEY] = deg_s


## The rate and its provenance IN ONE SENTENCE, on `FailsafeSettings.stage2_sentence`'s rule: the
## caller pastes this whole rather than picking the number out and writing its own, because a
## caller that wrote its own is precisely how a label goes missing.
static func max_rate_sentence(config: Dictionary) -> String:
	var rate := intended_max_rate_deg_s(config)
	if max_rate_provenance(config) == CHOSEN:
		return "Max rate: %d deg/s at full stick — your figure for this aircraft." % [roundi(rate)]
	return ("Max rate: %d deg/s at full stick. That is the rate the sim flies, not a reading from "
		+ "your build — set yours here.") % [roundi(rate)]


## THE HONESTY SEAM. What the sim flies against what this aircraft is configured to fly, said
## plainly, in both directions, with the sim's number labelled as the sim's every time.
static func sim_versus_real_sentence(config: Dictionary) -> String:
	var sim := sim_max_rate_deg_s()
	var real := intended_max_rate_deg_s(config)
	if absf(sim - real) < SAME_RATE_EPSILON_DEG_S:
		return ("The sim flies %d deg/s at full stick and this aircraft is set to the same, so "
			+ "stick feel here and stick feel on the bench should agree.") % [roundi(sim)]
	var direction := "slower" if real < sim else "faster"
	return ("The sim flies %d deg/s at full stick. This aircraft is set to %d, so at full "
		+ "deflection your quad will roll %s than anything you practise here. %d deg/s is the "
		+ "sim's number, not your aircraft's — do not read the sim's stick feel as yours."
		) % [roundi(sim), roundi(real), direction, roundi(sim)]


## The expo on the sticks, 0 for none. Stored for the config sheet; see `expo_sentence`.
static func expo(config: Dictionary) -> float:
	var stored := float(config.get(EXPO_KEY, 0.0))
	return stored if stored > 0.0 and stored <= 1.0 else 0.0


## Refuses anything outside 0–1, and erases at zero for the same reason `set_max_rate_deg_s` does.
static func set_expo(config: Dictionary, value: float) -> void:
	if value <= 0.0:
		config.erase(EXPO_KEY)
		return
	if value > 1.0:
		return
	config[EXPO_KEY] = value


## The expo, and the admission that the sim does not fly it. Printed together for the same reason
## the port count is printed with its provenance: the number alone would look simulated.
static func expo_sentence(config: Dictionary) -> String:
	var value := expo(config)
	var head := ("No expo — full stick travel is linear." if value <= 0.0
		else "Expo: %.2f on roll, pitch and yaw." % [value])
	return (head + " Lothal's stick is linear and this figure is not applied to it: it is carried "
		+ "for the sheet you will type into your radio, and the sim does not fly it.")


## The modes the SIM flies, read off `FlightController`'s own enum rather than written out here, so
## the room cannot come to advertise a mode the aircraft does not have.
static func modes_flown() -> Array:
	return FlightController.Mode.keys()


## What the room says about modes. The honest version is short: two modes, one key, no channel map.
static func modes_sentence() -> String:
	return ("Lothal flies two modes — %s — and switches between them with a key. Betaflight has "
		+ "many more, and which mode sits on which switch is a radio setup Lothal does not model "
		+ "and cannot check: nothing here is simulated as a switch."
		) % [" and ".join(modes_flown())]


static func _is_settable(deg_s: float) -> bool:
	return deg_s >= MIN_SETTABLE_DEG_S and deg_s <= MAX_SETTABLE_DEG_S
