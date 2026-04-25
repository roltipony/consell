## PopulationSystem.gd
## Manages citizen count, happiness, and employment.
class_name PopulationSystem
extends Node

const CFG_KEY := "population"

var population:   int   = 0
var happiness:    float = 1.0
var unemployment: float = 0.0

var _housing_capacity:        int   = 0
var _jobs_available:          int   = 0
var _food_per_citizen_per_day: float = 1.0
var _water_per_citizen_per_day: float = 1.0

func _ready() -> void:
	_load_config()
	GameManager.register_system("population", self)
	EventBus.new_day.connect(_on_new_day)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	population                  = cfg.get("starting_population",       0)
	happiness                   = cfg.get("starting_happiness",        1.0)
	_food_per_citizen_per_day   = float(cfg.get("food_per_citizen_per_day",  1.0))
	_water_per_citizen_per_day  = float(cfg.get("water_per_citizen_per_day", 1.0))

## Called once per in-game day via EventBus.new_day.
## Consumes food and water from EconomySystem proportional to population.
## When supply falls short, emits resource_shortage so CitizenStats can
## drain hunger/thirst individually — PopulationSystem never touches citizens directly.
func _on_new_day(_day: int, _month: int, _year: int) -> void:
	if population == 0:
		return
	var eco: EconomySystem = GameManager.get_system("economy")
	if eco == null:
		return
	_consume_daily_resource(eco, "food",  _food_per_citizen_per_day)
	_consume_daily_resource(eco, "water", _water_per_citizen_per_day)

## Deducts `rate * population` units of `resource_id` from EconomySystem.
## If the stockpile cannot cover the full demand, emits resource_shortage
## for the deficit portion so the appropriate citizen stats react.
func _consume_daily_resource(eco: EconomySystem, resource_id: String, rate: float) -> void:
	var demand: float  = rate * float(population)
	var supply: float  = eco.get_resource(resource_id)
	if supply >= demand:
		eco.add_resource(resource_id, -demand)
	else:
		# Consume whatever remains and signal a shortage.
		eco.add_resource(resource_id, -supply)
		EventBus.emit_signal("resource_shortage", resource_id)

func process_tick() -> void:
	_update_capacity()
	_update_happiness()
	_update_growth()
	_update_unemployment()

func _update_capacity() -> void:
	_housing_capacity = 0
	_jobs_available   = 0
	for cell in GameManager.grid_system.buildings:
		var bld: Building = GameManager.grid_system.buildings[cell]
		if bld == null or not bld.is_operational or cell != bld.cell:
			continue
		_housing_capacity += bld.data.population_capacity
		_jobs_available   += bld.data.jobs_provided

func _update_happiness() -> void:
	var modifier: float = 0.0
	for cell in GameManager.grid_system.buildings:
		var bld: Building = GameManager.grid_system.buildings[cell]
		if bld == null or cell != bld.cell:
			continue
		modifier += bld.data.happiness_modifier
	happiness = clampf(0.5 + modifier * 0.1, 0.0, 1.0)
	EventBus.emit_signal("happiness_changed", happiness)

func _update_growth() -> void:
	if population >= _housing_capacity:
		return
	var growth_chance: float = happiness * 0.05
	if randf() < growth_chance:
		var grown: int = mini(population + randi_range(1, 5), _housing_capacity)
		population = grown
		EventBus.emit_signal("population_changed", population)

func _update_unemployment() -> void:
	if population == 0:
		unemployment = 0.0
	else:
		unemployment = clampf(1.0 - float(_jobs_available) / float(population), 0.0, 1.0)
	EventBus.emit_signal("unemployment_changed", unemployment)

func get_housing_capacity() -> int:
	return _housing_capacity

func get_jobs_available() -> int:
	return _jobs_available

func serialize() -> Dictionary:
	return {"population": population, "happiness": happiness}

func deserialize(data: Dictionary) -> void:
	population = data.get("population", 0)
	happiness  = data.get("happiness",  1.0)
	EventBus.emit_signal("population_changed", population)
	EventBus.emit_signal("happiness_changed",  happiness)