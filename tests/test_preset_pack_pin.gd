class_name TestPresetPackPin
extends RefCounted
## Pins how every shelf battery preset flies on the reference airframe, so the pack designer
## (which adds a second source of battery records) cannot move a preset figure unnoticed.
## Order of each row: AUW g, T:W, hover throttle, flight time min, top speed km/h, R ohm, mass g.

const REL_TOL := 1e-9

const GOLDEN := {
	"battery_1s_300": [325.530708465516, 1.11356621840302, 1.0, 0.0, 50.3259123243496, 0.09, 8.0],
	"battery_1s_550": [330.530708465516, 1.09672109342851, 1.0, 0.0, 50.3259123243016, 0.07, 13.0],
	"battery_2s_300": [336.480708465516, 4.30931094567819, 0.49667368150525, 1.18439776308276, 88.0940712825803, 0.03, 19.0],
	"battery_2s_450": [346.180708465516, 4.18856384697831, 0.49578162808755, 1.71669407144456, 89.3548289421305, 0.014, 28.0],
	"battery_3s_650": [382.480708465516, 8.52984197056345, 0.34768455888663, 2.35092996745704, 93.9228720094946, 0.02, 62.0],
	"battery_4s_1300": [477.480708465516, 12.1470876145751, 0.28918693703628, 4.12034472931419, 104.940833999123, 0.011, 155.0],
	"battery_4s_1500": [507.480708465516, 11.4290058779527, 0.2991944997083, 4.57051874348698, 108.1873206628, 0.015, 185.0],
	"battery_4s_3000_liion": [642.480708465516, 8.54612921950905, 0.40134886640514, 8.40312821296471, 121.729725437683, 0.15, 320.0],
	"battery_4s_650": [398.480708465516, 14.5552843005496, 0.26494739756381, 2.29874931494785, 95.8672450116275, 0.018, 78.0],
	"battery_5s_1200": [497.480708465516, 18.2167867935088, 0.23625850615626, 3.70450108086455, 107.116091764687, 0.014, 172.0],
	"battery_6s_1100": [503.480708465516, 25.9195631144899, 0.19770660668795, 3.36925607193986, 107.76010698442, 0.013, 178.0],
	"battery_6s_1300": [530.480708465516, 24.6003290821806, 0.20344195656818, 3.84483094366352, 110.611783268697, 0.017, 205.0],
	"battery_6s_4000_liion": [915.480708465516, 13.4946886218721, 0.33488583251924, 8.61819803328585, 145.308558702462, 0.2, 590.0],
	"battery_6s_5600": [1224.48070846552, 10.6575790943688, 0.3087596821952, 8.17358162653515, 168.051568464435, 0.0065, 892.0],
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
