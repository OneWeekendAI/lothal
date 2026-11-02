class_name TestBatteryAudit
extends RefCounted
## Task 11's guard: the old battery bench and custom-battery screens are gone, and no battery
## feature they had lives only there. Every "Carry" row of the plan's audit (A1-A8, A11, A13-A19)
## names a passing test in the suites that replaced them. Names are matched against the real
## results of those suites, so renaming or deleting a covering test fails this one.

const DEAD_CLASSES := ["BatteryBenchScreen", "BatteryInstruments", "CustomBatteryDialog", "CustomBatteries"]
const DEAD_PATHS := [
	"res://src/lab/battery_bench_screen.gd", "res://src/lab/battery_instruments.gd",
	"res://src/ui/custom_battery_dialog.gd", "res://src/lab/custom_batteries.gd",
]

## audit row -> [suite, name of the passing test that covers it]
const COVERAGE := {
	"A1 real build load": ["bench", "this drone current equals Build.average_flight_current_a"],
	"A2 peak-current warning": ["bench", "warning: pack cannot supply the drone's peak current"],
	"A3 sag readout": ["bench", "peak sag is the largest rest minus live gap"],
	"A4 run time to cutoff": ["bench", "1C discharge of a 1500 mAh pack runs ~60 min to cutoff"],
	"A5 resting vs live voltage": ["bench", "live V = rest - I*R at t0"],
	"A6 own voltage axis": ["bench", "voltage axis spans the pack's own empty and full resting voltage"],
	"A7 per-cell voltage under load": ["designer", "bench row shows the per-cell voltage under load"],
	"A8 charge left, red past the knee": ["designer", "capacity chart turns red past the knee at 20 % left"],
	"A11 recharge writes stored charge": ["designer", "recharge sets stored used_mah to 0"],
	"A13 custom cell entry": ["designer", "custom cell fields appear only for a custom cell, and are the only extra"],
	"A14 R from mAh and C": ["cells", "custom_cell_r_ohm uses the pinned K per chemistry"],
	"A15 derived nominal_v": ["design", "4S1P pouch: nominal = 4 x chemistry nominal, mah = cell mah"],
	"A16 refusals": ["packs", "a design with no cell is refused and nothing is stored"],
	"A16 unknown chemistry": ["packs", "a migrated record with an unknown chemistry is rejected loudly"],
	"A17 delete with confirm": ["designer", "My packs delete removes the pack on confirm and persists it"],
	"A18 unknown fields survive": ["packs", "unknown fields survive a round trip at schema 2"],
	"A19 cell_class bucket": ["design", "record is catalog-shaped"],
}


static func run() -> Array:
	var results: Array = []
	var live := {}
	for c in ProjectSettings.get_global_class_list():
		live[String(c.get("class", ""))] = true
	var resolved: Array = []
	for n in DEAD_CLASSES:
		if live.has(n) or ClassDB.class_exists(n):
			resolved.append(n)
	for p in DEAD_PATHS:
		if ResourceLoader.exists(p):
			resolved.append(p)
	results.append(TestResult.new("the old battery screens and custom-battery classes no longer exist",
		resolved.is_empty(), str(resolved)))

	var suites := {
		"bench": TestPackBench.run(), "designer": TestPackDesigner.run(), "cells": TestCellLibrary.run(),
		"design": TestPackDesign.run(), "packs": TestDesignedPacks.run(),
	}
	var passed := {}
	for s in suites:
		for r in suites[s]:
			passed[s + "|" + (r as TestResult).name] = (r as TestResult).passed
	var missing: Array = []
	for row in COVERAGE:
		var key: String = String(COVERAGE[row][0]) + "|" + String(COVERAGE[row][1])
		if not passed.get(key, false):
			missing.append(row)
	results.append(TestResult.new("no battery feature lives only in an old screen",
		missing.is_empty(), "uncovered: %s" % [missing]))
	return results
