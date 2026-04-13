## EventSystem.gd
## Rolls random in-game events on a configurable cadence.
class_name EventSystem
extends Node

const CFG_KEY := "events"

var _event_pool: Array = []
var _ticks_between_rolls: int = 240
var _tick_counter: int = 0

func _ready() -> void:
	_load_config()
	GameManager.register_system("events", self)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	_ticks_between_rolls = cfg.get("ticks_between_rolls", _ticks_between_rolls)
	_event_pool.clear()
	for eid in ConfigLoader.events:
		_event_pool.append(ConfigLoader.events[eid])

func process_tick() -> void:
	_tick_counter += 1
	if _tick_counter >= _ticks_between_rolls:
		_tick_counter = 0
		_roll_event()

func _roll_event() -> void:
	if _event_pool.is_empty():
		return
	var eligible: Array = []
	for e in _event_pool:
		if _is_eligible(e):
			eligible.append(e)
	if eligible.is_empty():
		return
	var total_weight: float = 0.0
	for e in eligible:
		total_weight += float(e.get("weight", 1.0))
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for event in eligible:
		cumulative += float(event.get("weight", 1.0))
		if roll <= cumulative:
			_trigger_event(event)
			return

func _is_eligible(event_data: Dictionary) -> bool:
	var min_pop: int = event_data.get("min_population", 0)
	if GameManager.population_system and GameManager.population_system.population < min_pop:
		return false
	return true

func _trigger_event(event_data: Dictionary) -> void:
	EventBus.emit_signal("game_event_triggered", event_data)
	EventBus.notify(event_data.get("title", "Event"), "info")
	var effects: Dictionary = event_data.get("effects", {})
	if effects.has("gold_delta") and GameManager.economy_system:
		GameManager.economy_system.add_gold(int(effects["gold_delta"]))
	if effects.has("happiness_delta") and GameManager.population_system:
		var new_h: float = GameManager.population_system.happiness + float(effects["happiness_delta"])
		GameManager.population_system.happiness = clampf(new_h, 0.0, 1.0)
