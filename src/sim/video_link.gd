class_name VideoLink
extends RefCounted
## R2.4: the FPV video link, from the fitted camera part's `video` block (data/parts/cameras.json) to what the feed
## looks like. A simple link budget, in dB:
##
##   rx_dbm = tx_dbm + tx_gain_dbi + rx_gain_dbi - FSPL(d, f) - FADE_MARGIN_DB - OBSTRUCTION_DB * blockers
##   FSPL   = 20 log10(d_m) + 20 log10(f_MHz) - 27.55          (free space, far field)
##
## and `margin_db = rx_dbm - sensitivity_dbm`. Analog fades GRADUALLY over `fade_window_db` above sensitivity (snow,
## colour loss, line tearing, sync dropouts); digital holds its picture and spends the falling margin on bitrate
## (bigger compression blocks) over its window, then stutters and freezes instead of showing static.
## The pilot's receiver stands at the course start, PILOT_ANTENNA_M above the ground. Line of sight is a segment test
## against the R1.1 collision world (CollisionWorld.blockers_between); each terrain or obstacle crossing costs
## OBSTRUCTION_DB.

## ESTIMATE: diffraction past a hill / building edge at 5.8 GHz is typically 15-30 dB; one figure per blocker.
const OBSTRUCTION_DB := 20.0
## ESTIMATE: ground reflection, body blocking and antenna misalignment, lumped (a common link-budget allowance).
const FADE_MARGIN_DB := 10.0
## ESTIMATE: a pilot's goggles at head height.
const PILOT_ANTENNA_M := 1.6
## Digital: below this fraction of the window the decoder stalls (freeze), and between it and STUTTER_Q it drops frames.
const FREEZE_Q := 0.12
const STUTTER_Q := 0.35
## Largest compression block at the bottom of the window, as a fraction of picture width (~1/40 = 32 px at 1280).
const MAX_BLOCK_FRAC := 0.025

## Used when a camera part carries no `video` block but says analog/digital in its catalog. Labelled estimates.
const ANALOG_DEFAULT := {
	"system": "analog", "tx_mw": 25.0, "freq_mhz": 5800.0, "tx_gain_dbi": 2.0, "rx_gain_dbi": 2.0,
	"sensitivity_dbm": -90.0, "fade_window_db": 20.0, "latency_ms": 0.0, "estimated": true,
	"source": "ESTIMATE: race-legal 25 mW 5.8 GHz analog VTX, dipole/pagoda antennas (~2 dBi), typical goggle receiver sensitivity ~-90 dBm; picture degrades over ~20 dB above it.",
}
const DIGITAL_DEFAULT := {
	"system": "digital", "tx_mw": 25.0, "freq_mhz": 5800.0, "tx_gain_dbi": 2.0, "rx_gain_dbi": 2.0,
	"sensitivity_dbm": -92.0, "fade_window_db": 12.0, "latency_ms": 30.0, "max_mbps": 50.0, "min_mbps": 4.0,
	"estimated": true,
	"source": "ESTIMATE: DJI/Walksnail-class digital link at 25 mW; ~-92 dBm sensitivity, ~12 dB from full bitrate to stall; glass-to-glass latency 25-40 ms published by the makers, 30 ms taken.",
}

var cfg: Dictionary = {}
var system := "none"
## Last evaluation.
var distance_m := 0.0
var blockers := 0
var rx_dbm := 0.0
var margin_db := 0.0
## 0 = lost .. 1 = full quality.
var quality := 1.0
## Digital frame delay ring: [t_s, Transform3D] oldest first.
var _ring: Array = []
var _frozen := Transform3D.IDENTITY
var _has_frozen := false
var _stutter_count := 0


static func config_for(part: Dictionary) -> Dictionary:
	var raw: Variant = part.get("video", null)
	var sig := str((part.get("catalog", {}) as Dictionary).get("signal", "")) if part.get("catalog", null) is Dictionary else ""
	var base: Dictionary = {}
	if raw is Dictionary:
		base = (DIGITAL_DEFAULT if str(raw.get("system", "")) == "digital" else ANALOG_DEFAULT).duplicate()
		base.merge(raw, true)
	elif sig == "digital":
		base = DIGITAL_DEFAULT.duplicate()
	elif sig == "analog":
		base = ANALOG_DEFAULT.duplicate()
	else:
		base = {"system": "none"}
	return base


func _init(part: Dictionary = {}) -> void:
	set_part(part)


func set_part(part: Dictionary) -> void:
	cfg = config_for(part)
	system = str(cfg.get("system", "none"))
	_ring.clear()
	_has_frozen = false


static func fspl_db(d_m: float, f_mhz: float) -> float:
	return 20.0 * log(maxf(d_m, 1.0)) / log(10.0) + 20.0 * log(f_mhz) / log(10.0) - 27.55


## Evaluates the link for a transmitter `distance_m` away with `p_blockers` terrain/obstacle crossings in between.
func evaluate(p_distance_m: float, p_blockers: int) -> float:
	distance_m = p_distance_m
	blockers = p_blockers
	if system == "none":
		quality = 0.0
		return quality
	var tx_dbm := 10.0 * log(maxf(float(cfg["tx_mw"]), 1e-6)) / log(10.0)
	rx_dbm = tx_dbm + float(cfg["tx_gain_dbi"]) + float(cfg["rx_gain_dbi"]) - fspl_db(distance_m, float(cfg["freq_mhz"])) \
		- FADE_MARGIN_DB - OBSTRUCTION_DB * float(blockers)
	margin_db = rx_dbm - float(cfg["sensitivity_dbm"])
	quality = clampf(margin_db / float(cfg["fade_window_db"]), 0.0, 1.0)
	return quality


## Analog picture noise 0..1 (0 for digital, which never shows static).
func noise() -> float:
	if system != "analog":
		return 0.0
	var n := 1.0 - quality
	return n * n * (3.0 - 2.0 * n)


func bitrate_mbps() -> float:
	if system != "digital":
		return 0.0
	return lerpf(float(cfg["min_mbps"]), float(cfg["max_mbps"]), quality)


## Compression block width as a fraction of picture width; 0 at full bitrate.
func block_frac() -> float:
	if system != "digital":
		return 0.0
	var loss := 1.0 - quality
	return MAX_BLOCK_FRAC * loss * loss if loss > 0.25 else 0.0


func latency_s() -> float:
	return float(cfg.get("latency_ms", 0.0)) / 1000.0 if system == "digital" else 0.0


## The frame delay at a feed of `frame_hz`: the latency in whole frames.
func delay_frames(frame_hz: float) -> int:
	return ceili(latency_s() * frame_hz - 1e-9)


## Digital: push the live lens pose at time `t_s`, get the pose the goggles show (`latency_s` old, held on a freeze,
## repeated on a stutter). Analog and none: the live pose.
func shown_pose(t_s: float, live: Transform3D) -> Transform3D:
	if system != "digital":
		return live
	_ring.append([t_s, live])
	var want := t_s - latency_s() + 1e-9
	var out: Transform3D = _ring[0][1]
	while _ring.size() > 1 and float(_ring[1][0]) <= want:
		_ring.pop_front()
	out = _ring[0][1]
	if quality < FREEZE_Q and _has_frozen:
		return _frozen
	if quality < STUTTER_Q and _has_frozen:
		_stutter_count += 1
		if _stutter_count % 3 != 0:
			return _frozen
	_frozen = out
	_has_frozen = true
	return out


func is_frozen() -> bool:
	return system == "digital" and quality < FREEZE_Q


## Analog sync dropout this frame (deterministic in `frame`): more likely the closer to the edge.
func dropout(frame: int) -> bool:
	var n := noise()
	if n < 0.85:
		return false
	return fposmod(sin(float(frame) * 12.9898) * 43758.5453, 1.0) < (n - 0.85) * 4.0


func shader_params(t_s: float, frame: int) -> Dictionary:
	return {"vsys": {"analog": 1, "digital": 2}.get(system, 0), "vnoise": noise(), "vblock": block_frac(),
		"vdrop": 1.0 if dropout(frame) else 0.0, "vtime": t_s}


## One line for the HUD.
func hud_text() -> String:
	if system == "none":
		return ""
	var bars := "%d%%" % roundi(quality * 100.0)
	var lo := " LOS blocked" if blockers > 0 else ""
	if system == "digital":
		var state := " FROZEN" if is_frozen() else ""
		return "Video %s  %.0f dBm  %.0f Mbps  %.0f ms%s%s" % [bars, rx_dbm, bitrate_mbps(), latency_s() * 1000.0, lo, state]
	return "Video %s  %.0f dBm  %.0f m%s" % [bars, rx_dbm, distance_m, lo]
