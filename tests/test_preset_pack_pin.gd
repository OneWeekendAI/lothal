class_name TestPresetPackPin
extends RefCounted
## Pins how every shelf battery preset flies on the reference airframe, so the pack designer
## (which adds a second source of battery records) cannot move a preset figure unnoticed.
## Order of each row: AUW g, T:W, hover throttle, flight time min, top speed km/h, R ohm, mass g.

const REL_TOL := 1e-9

const GOLDEN := {
	"battery_1s_300": [325.530708465516, 1.57560899416339, 0.76624318342433, 0.0, 50.6196012842886, 0.09, 8.0],
	"battery_1s_550": [330.530708465516, 1.55177446148898, 1.0, 0.0, 50.6196012842917, 0.07, 13.0],
	"battery_2s_300": [336.480708465516, 5.3281728323371, 0.40881691913019, 1.54804180321239, 88.0940712825803, 0.03, 19.0],
	"battery_2s_450": [346.180708465516, 5.17887717486744, 0.40971606520504, 1.63273212562374, 89.3548289421305, 0.014, 28.0],
	"battery_3s_650": [382.480708465516, 9.41352908042022, 0.28718114793021, 2.72095245511905, 93.9228720094946, 0.02, 62.0],
	"battery_4s_1300": [477.480708465516, 12.1470876141998, 0.24142761113708, 6.37337742023283, 104.940833999123, 0.011, 155.0],
	"battery_4s_1500": [507.480708465516, 11.4290058775997, 0.24995732891784, 6.97573902241136, 108.1873206628, 0.015, 185.0],
	"battery_4s_3000_liion": [642.480708465516, 8.63251304643224, 0.3196709027859, 10.9323707369991, 121.729725437683, 0.15, 320.0],
	"battery_4s_650": [398.480708465516, 14.5552843001, 0.21927611448334, 3.59205452387837, 95.8672450116275, 0.018, 78.0],
	"battery_5s_1200": [497.480708465516, 16.6948345585631, 0.19736417039845, 7.12865383317867, 107.116091764687, 0.014, 172.0],
	"battery_6s_1100": [503.480708465516, 21.9632456527765, 0.16535410497744, 7.78765675488374, 107.76010698442, 0.013, 178.0],
	"battery_6s_1300": [530.480708465516, 20.8453772304915, 0.17023673626546, 8.79344850204899, 110.611783268697, 0.017, 205.0],
	"battery_6s_4000_liion": [915.480708465516, 11.5750972119866, 0.25921521245948, 12.9776649912546, 145.308558702462, 0.2, 590.0],
	"battery_6s_5600": [1224.48070846552, 9.03082458140132, 0.26987622377995, 13.0043773604272, 168.051568464435, 0.0065, 892.0],
}

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ids: Array = []
	for part in catalog.list_category("battery"):
		var pid := String(part.get("part_id", ""))
		if pid.begins_with("battery_"):
			ids.append(pid)
	ids.sort()
	results.append(TestResult.new("the shelf has exactly 14 preset batteries",
		ids.size() == 14, "%d ids: %s" % [ids.size(), ids]))
	for id in ids:
		var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, id)
		var got: Array = [b.all_up_weight_g(), b.thrust_to_weight(), b.hover_throttle(),
			b.flight_time_min(), b.top_speed_kmh(),
			float(b.battery.specs.internal_r_ohm), float(b.battery.mass_g)]
		var want: Array = GOLDEN.get(id, [])
		var ok := want.size() == got.size()
		var detail := ""
		if ok:
			for i in got.size():
				if absf(got[i] - want[i]) > REL_TOL * maxf(absf(want[i]), 1e-12):
					ok = false
					detail += " [%d] got %s want %s" % [i, got[i], want[i]]
		results.append(TestResult.new("%s flies exactly as before the pack designer" % id,
			ok, detail if detail != "" else "matches golden"))
	return results
