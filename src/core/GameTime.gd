## GameTime.gd
## Value object representing the in-game calendar (day / month / year).
## Emits signals through EventBus on each calendar advance.
class_name GameTime
extends RefCounted

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const TICKS_PER_DAY := 24  # Each tick = 1 in-game hour

var tick: int = 0
var hour: int = 0
var day: int = 1
var month: int = 1
var year: int = 1

func advance_tick() -> void:
	tick += 1
	hour = tick % TICKS_PER_DAY
	EventBus.emit_signal("hour_changed", hour)

	if tick % TICKS_PER_DAY == 0:
		_advance_day()

func _advance_day() -> void:
	day += 1
	EventBus.emit_signal("new_day", day, month, year)

	if day > DAYS_PER_MONTH:
		day = 1
		_advance_month()

func _advance_month() -> void:
	month += 1
	EventBus.emit_signal("new_month", month, year)

	if month > MONTHS_PER_YEAR:
		month = 1
		_advance_year()

func _advance_year() -> void:
	year += 1
	EventBus.emit_signal("new_year", year)

func to_dict() -> Dictionary:
	return {"tick": tick, "hour": hour, "day": day, "month": month, "year": year}

func from_dict(data: Dictionary) -> void:
	tick  = data.get("tick",  0)
	hour  = data.get("hour",  0)
	day   = data.get("day",   1)
	month = data.get("month", 1)
	year  = data.get("year",  1)

func format_date() -> String:
	return "Year %d, Month %d, Day %d — %02d:00" % [year, month, day, hour]

func serialize() -> Dictionary:
	return to_dict()

func deserialize(data: Dictionary) -> void:
	from_dict(data)
