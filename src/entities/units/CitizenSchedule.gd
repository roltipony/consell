## CitizenSchedule.gd
## Value object that holds the ordered day-phases for one citizen type.
##
## A phase is a Dictionary with the keys:
##   "id"    : String  — unique phase name, e.g. "work", "eat", "leisure", "sleep"
##   "start" : int     — first hour (inclusive, 0–23)
##   "end"   : int     — last  hour (exclusive, 1–24)
##
## Hours wrap around midnight: a phase with start=22, end=6 is valid and means
## it is active from 22:00 up to (but not including) 06:00 the next day.
##
## Usage:
##   var schedule := CitizenSchedule.new()
##   schedule.load_from_config("farmer")
##   var phase: String = schedule.phase_at(hour)   # → "work", "eat", …
##
## All data comes from game_settings.json["citizen_schedules"][citizen_type].
## Nothing is hardcoded here.
class_name CitizenSchedule
extends RefCounted

## Ordered list of phase Dictionaries as described above.
var phases: Array[Dictionary] = []

## Fallback phase id returned when no phase covers the current hour.
const PHASE_DEFAULT := "idle"

# ─── Loading ──────────────────────────────────────────────────────────────────

## Populate phases from config for the given citizen_type.
## Expects game_settings.json to contain:
##   "citizen_schedules": {
##     "farmer": [
##       { "id": "sleep",   "start": 0,  "end": 8  },
##       { "id": "work",    "start": 8,  "end": 14 },
##       { "id": "eat",     "start": 14, "end": 15 },
##       { "id": "leisure", "start": 15, "end": 24 }
##     ]
##   }
func load_from_config(citizen_type: String) -> void:
	phases.clear()
	var schedules_cfg: Dictionary = ConfigLoader.game_settings.get("citizen_schedules", {})
	var raw_phases = schedules_cfg.get(citizen_type, [])
	for entry in raw_phases:
		var phase: Dictionary = {
			"id":    str(entry.get("id",    PHASE_DEFAULT)),
			"start": int(entry.get("start", 0)),
			"end":   int(entry.get("end",   24)),
		}
		phases.append(phase)

# ─── Query ────────────────────────────────────────────────────────────────────

## Returns the phase id that covers the given hour (0–23).
## If no phase covers it, returns PHASE_DEFAULT.
func phase_at(hour: int) -> String:
	for phase in phases:
		if _hour_in_phase(hour, phase):
			return phase["id"]
	return PHASE_DEFAULT

## Returns true when a phase with the given id covers the current hour.
func is_in_phase(phase_id: String, hour: int) -> bool:
	return phase_at(hour) == phase_id

## Returns true if this schedule has at least one phase defined.
func has_phases() -> bool:
	return not phases.is_empty()

# ─── Serialization ────────────────────────────────────────────────────────────

func serialize() -> Array:
	return phases.duplicate(true)

func deserialize(data: Array) -> void:
	phases.clear()
	for entry in data:
		phases.append(entry.duplicate())

# ─── Private ──────────────────────────────────────────────────────────────────

## Checks whether `hour` falls inside [phase.start, phase.end).
## Handles midnight-wrapping (e.g. start=22, end=6).
func _hour_in_phase(hour: int, phase: Dictionary) -> bool:
	var s: int = phase["start"]
	var e: int = phase["end"]
	if s < e:
		return hour >= s and hour < e
	# Wraps midnight
	return hour >= s or hour < e
