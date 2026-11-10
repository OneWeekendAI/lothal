class_name TestSr4Watch
extends RefCounted
## SR4.3: a watched mission (stepped in render-frame chunks, as src/scenes/main.gd `watch_mission` does) gives the same
## result JSON as the headless MissionRunner.run with the same params and seed. One TestResult per case.
## The chunking is MissionRunner.begin / advance / finish, the very calls main.gd makes each physics frame
## (8 ticks = 1/60 s at 500 Hz); the scene's own drawing is not exercised here (it needs a window).
##
## FAIL-PROOFS (observed, fix removed by a temporary edit, then restored):
##   W1 advance() stepping the rig one extra time inside every 8-tick chunk (a watch path with a stray substep): the 8-tick
##        cruise, survey and hover cases FAIL (JSON differs); the 1-tick and 7-tick cases pass.
##   W2 the in-suite control "extra substep per frame" drives a watcher that does that itself (no runner edit); it must
##        differ from headless, showing the equality check can fail.
##   Not a valid proof (tried, passed, discarded): merely SKIPPING loop iterations in advance() only shortens a chunk, the
##        flight still takes the same ticks in the same order, so it is rightly invisible.
## Cheap settings: capacity_scale 0.15 and a 70 x 50 m field, seed 11, gusts on, so the gust process (seeded) is in the comparison.

const SEED := 11


static func _params(mission: String) -> Dictionary:
	var d := {"class_id": "five_inch", "mission": mission, "seed": SEED, "capacity_scale": 0.15, "gust_mps": 1.5,
		"wind_speed_mps": 3.0, "wind_from_deg": 60.0}
	if mission == Mission.SURVEY:
		d["polygon"] = PackedVector2Array([Vector2(30, 0), Vector2(100, 0), Vector2(100, 50), Vector2(30, 50)])
	return d


static func _watched(params: Dictionary, ticks_per_frame: int, extra_step_per_frame := false) -> String:
	var runner := MissionRunner.new()
	if runner.begin(params):
		while not runner.is_done():
			runner.advance(ticks_per_frame)
			if extra_step_per_frame:
				runner.rig.step()      # a dropped/duplicated substep: the control that must NOT match
	return MissionResult.to_json(runner.finish())


static func run() -> Array:
	return [
		_equal("cruise_loop", 8),
		_equal("cruise_loop", 1),
		_equal("cruise_loop", 7),
		_equal("survey", 8),
		_equal("hover_endurance", 8),
		_control_differs(),
		_not_flown_is_final(),
	]


static func _equal(mission: String, tpf: int) -> TestResult:
	var p := _params(mission)
	var head := MissionResult.to_json(MissionRunner.run(p))
	var watch := _watched(p, tpf)
	var ok := head == watch and head.length() > 500
	return TestResult.new("sr4 watch %s, %d ticks per frame: watched result JSON equals the headless run byte for byte" % [mission, tpf],
		ok, "%d vs %d bytes, equal=%s" % [head.length(), watch.length(), str(ok)])


static func _control_differs() -> TestResult:
	var p := _params("cruise_loop")
	var head := MissionResult.to_json(MissionRunner.run(p))
	var bad := _watched(p, 8, true)
	return TestResult.new("sr4 watch control: a watcher that steps one extra substep per frame gives a DIFFERENT result (the equality check can fail)",
		head != bad, "equal=%s" % str(head == bad))


static func _not_flown_is_final() -> TestResult:
	var p := _params("cruise_loop")
	p["fields"] = {"reserve_pct": 95.0}
	var runner := MissionRunner.new()
	var flying := runner.begin(p)
	var r := runner.finish()
	return TestResult.new("sr4 watch: a mission that cannot fly (reserve 95 percent) is final at begin(), nothing to watch, same result as headless",
		not flying and String(r["ended_by"]) == "not_flown" and MissionResult.to_json(r) == MissionResult.to_json(MissionRunner.run(p)),
		"flying %s, ended_by %s" % [str(flying), r["ended_by"]])
