class_name PackCharge
extends RefCounted
## How much charge is left in each pack you own, and the only thing in Lothal that crosses the
## Lab/Sim boundary BACKWARDS (labs-and-sim.md §4).
##
## Everything else goes one way: the build and the field are authored in the garage and read in
## the field, and Sim authors nothing. Pack state is the exception the rule is written around,
## because it is not a design decision — it is a consequence. You flew for four minutes on a
## four-minute pack, and the pack is empty. That is Sim reporting what happened, which is exactly
## what §3 says Sim is for.
##
## ---------------------------------------------------------------------------
## PER PACK, NOT PER BUILD
## ---------------------------------------------------------------------------
##
## Charge is keyed by `part_id`, so owning two 4S packs is meaningful — fly one flat, fit the
## other, and put the first on the charger. That is the point §5 makes, and it only works if the
## state belongs to the battery rather than to the aircraft. A single "current charge" number
## attached to the build would make every pack in the catalog the same pack.
##
## The consequence to be honest about: this models a shelf holding exactly one of each catalog
## entry. Two identical 4S 1500s are one pack here. Fixing that means owned INSTANCES rather than
## catalog entries, which is a different feature (an inventory) and not this one.
##
## ---------------------------------------------------------------------------
## DRAINING RUNS AT 1:1. CHARGING DOES NOT.
## ---------------------------------------------------------------------------
##
## A four-minute pack gives four minutes of flying, and a bench run costs charge for as long as it
## runs, because a motor on a stand is drawing current. Compressing that would throw away the only
## lesson pack choice has to teach.
##
## Charging is the opposite case and gets the opposite answer. The realism of sitting through a
## 45-minute charge is honest and buys nothing: the cost lands entirely on the user's patience and
## no real-world intuition transfers. So it runs at 10:1 by default — a full charge is four and a
## half minutes — and the factor is a setting, with 1:1 there for anyone who wants it.
##
## Charging is a LAB activity. There is a charger in the garage and there is not one in the field.
##
## ---------------------------------------------------------------------------
## THE FILE
## ---------------------------------------------------------------------------
##
## `user://pack_charge.json`, following AssemblyTweaks exactly — the file-handling half is shared
## through JsonStore rather than written twice, and the rules are its rules:
##
##     {
##       "schema": 1,
##       "charge_compression": 10.0,
##       "packs": { "battery_4s_1500": { "used_mah": 412.5 } }
##     }
##
## Only packs that have been used are stored; an absent pack is a full one, which is the right
## default for a battery you have never flown. Unknown fields are preserved, both at the top level
## and inside each pack's block — a later version adding a cycle count or a storage-charge date
## must not have it deleted by this one. And a missing or corrupt file loads as defaults rather
## than stopping the app.
##
## Each pack gets a BLOCK rather than a bare number, which is the one place this schema is
## deliberately more than it needs to be today. A bare `"battery_4s_1500": 412.5` would be
## smaller and would leave the next field with nowhere to go except a parallel dictionary.

const SAVE_PATH := "user://pack_charge.json"
const SCHEMA_VERSION := 1

const USED_MAH := "used_mah"
const PACK_KEYS := [USED_MAH]
const TOP_KEYS := ["schema", "packs", "charge_compression"]

## Wall-clock seconds a full charge takes at 1:1. A hobby charger on a 5" pack is about 45 minutes
## at a bit over 1C, which is the figure labs-and-sim.md §5 quotes when it says a 45-minute charge
## becomes a four-and-a-half-minute wait.
const FULL_CHARGE_S := 45.0 * 60.0

const DEFAULT_COMPRESSION := 10.0
## 1:1 is the honest end of the range; nothing above 60:1, past which "charging" is a button that
## fills the pack and the consequence has been designed out rather than compressed.
const MIN_COMPRESSION := 1.0
const MAX_COMPRESSION := 60.0

## part_id -> used mAh. Sparse: only packs that have been used.
var _used_mah: Dictionary = {}
var charge_compression: float = DEFAULT_COMPRESSION

## True once something has actually changed since the last save. Rooms hand their pack state back
## on the way out whether or not anything happened to it, and AppShell saves on every room change
## — so without this, opening and closing a bench you never started would rewrite the file. That
## is not merely wasteful: the test suite drives AppShell through those transitions, and a save
## there would overwrite the real packs of whoever is running the tests with an empty shelf.
var _dirty := false

var _unknown_top: Dictionary = {}
## part_id -> the fields of that pack's block this version did not recognise.
var _unknown_pack_fields: Dictionary = {}


# ---------------------------------------------------------------------------
# Reading and writing charge
# ---------------------------------------------------------------------------

func used_mah(part_id: String) -> float:
	return float(_used_mah.get(part_id, 0.0))


## Records a pack's used charge. Deliberately does nothing when the value has not moved, and
## deliberately does not create an entry for a pack that is still full — an absent pack IS a full
## one, and writing zeroes for every battery anyone ever glanced at would turn the file into a
## list of the catalog.
func set_used_mah(part_id: String, mah: float) -> void:
	var value := maxf(mah, 0.0)
	if not _used_mah.has(part_id) and value <= 0.0:
		return
	if _used_mah.has(part_id) and is_equal_approx(float(_used_mah[part_id]), value):
		return
	_used_mah[part_id] = value
	_dirty = true


func remaining_fraction(part_id: String, capacity_mah: float) -> float:
	if capacity_mah <= 0.0:
		return 1.0
	return clampf(1.0 - used_mah(part_id) / capacity_mah, 0.0, 1.0)


func is_full(part_id: String) -> bool:
	return used_mah(part_id) <= 0.0


## Seeds a freshly-built BatteryModel with the charge this pack actually has left. Called by
## whoever is about to run one — the benches and the flight scene — rather than by Build, which
## must stay pure: Build's 11.7:1 and 29% are full-pack figures and cannot become a function of
## how much flying the person running the tests has done.
func apply_to(part_id: String, battery: BatteryModel) -> void:
	battery.used_mah = minf(used_mah(part_id), battery.capacity_mah)


## Records what a run did to a pack. The write-back half of the boundary.
func record_from(part_id: String, battery: BatteryModel) -> void:
	set_used_mah(part_id, battery.used_mah)


## Puts `seconds` of wall-clock time on the charger. Returns the mAh actually put back, which is
## less than the rate implies once the pack is full.
func charge(part_id: String, seconds: float, capacity_mah: float) -> float:
	if capacity_mah <= 0.0 or seconds <= 0.0:
		return 0.0
	var restored := minf(charge_rate_mah_per_s(capacity_mah) * seconds, used_mah(part_id))
	set_used_mah(part_id, used_mah(part_id) - restored)
	return restored


## mAh per wall-clock second, for a pack of this capacity at the current compression.
func charge_rate_mah_per_s(capacity_mah: float) -> float:
	return (capacity_mah / FULL_CHARGE_S) * charge_compression


## Wall-clock seconds to fill this pack from where it is now.
func seconds_to_full(part_id: String, capacity_mah: float) -> float:
	var rate := charge_rate_mah_per_s(capacity_mah)
	if rate <= 0.0:
		return 0.0
	return used_mah(part_id) / rate


func set_compression(value: float) -> void:
	var clamped := clampf(value, MIN_COMPRESSION, MAX_COMPRESSION)
	if is_equal_approx(clamped, charge_compression):
		return
	charge_compression = clamped
	_dirty = true


## Whether anything has changed since the last save. Lets a caller skip a write it does not need.
func has_unsaved_changes() -> bool:
	return _dirty


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func save(path: String = SAVE_PATH) -> bool:
	var packs: Dictionary = {}
	for part_id in _used_mah:
		var block: Dictionary = (_unknown_pack_fields.get(part_id, {}) as Dictionary).duplicate(true)
		block[USED_MAH] = _used_mah[part_id]
		packs[part_id] = block

	# A pack this version knows nothing about — one that only exists in a later catalog — still
	# has to survive the round trip, so its block is written back even though no charge was read
	# out of it.
	for part_id in _unknown_pack_fields:
		if not packs.has(part_id):
			packs[part_id] = (_unknown_pack_fields[part_id] as Dictionary).duplicate(true)

	var document := _unknown_top.duplicate(true)
	document["schema"] = SCHEMA_VERSION
	document["charge_compression"] = charge_compression
	document["packs"] = packs

	var written := JsonStore.write_document(path, document)
	if written:
		_dirty = false
	return written


## Reads the file, or returns defaults. Every failure mode lands in the same place on purpose:
## missing file, unreadable file, invalid JSON, JSON that is not an object, a "packs" block that
## is not an object, a pack entry that is not a block, a value that is not a number. None of them
## can stop Lab from opening, and none of them can produce a half-populated store — anything not
## understood is simply not a recorded charge, which reads as a full pack.
##
## A wrong-typed value is treated as ABSENT rather than coerced. float("half") is 0.0, and a
## silent zero here means a pack reported as full when the file said something unreadable — which
## is the one direction this particular error must not fail in.
static func load_from(path: String = SAVE_PATH) -> PackCharge:
	var charge := PackCharge.new()

	var document := JsonStore.read_document(path)
	if document.is_empty():
		return charge

	charge._unknown_top = JsonStore.unknown_fields(document, TOP_KEYS)

	var compression: Variant = document.get("charge_compression", DEFAULT_COMPRESSION)
	if compression is float or compression is int:
		charge.set_compression(float(compression))
	else:
		push_warning("%s: charge_compression is not a number; using the default" % path)

	var packs: Variant = document.get("packs", {})
	if not (packs is Dictionary):
		push_warning("%s has no readable packs block; using defaults" % path)
		return charge

	for part_id in (packs as Dictionary):
		var block: Variant = (packs as Dictionary)[part_id]
		if not (block is Dictionary):
			push_warning("%s: %s is not a pack block; treating it as full" % [path, part_id])
			continue

		charge._unknown_pack_fields[part_id] = JsonStore.unknown_fields(block, PACK_KEYS)

		var used: Variant = (block as Dictionary).get(USED_MAH, null)
		if used is float or used is int:
			charge._used_mah[part_id] = maxf(float(used), 0.0)
		elif used != null:
			push_warning("%s: %s used_mah is not a number; treating it as full" % [path, part_id])

	# A store that has only just been read has nothing to write back.
	charge._dirty = false
	return charge
