## PopulationSystem.gd
## Manages citizen count, happiness, employment, immigration, and housing.
##
## Food/water consumption model:
##   Citizens consume food and water themselves during PHASE_EAT via their BT.
##   PopulationSystem does NOT deduct food/water from the stockpile each day.
##   It only checks if the stockpile is below demand and emits resource_shortage
##   so CitizenStats can apply the hunger/thirst penalty to affected citizens.
##
## Immigration:
##   Each new day, a pending flag is set and the cooldown counter advances.
##   The actual immigration check runs at the END of process_tick(), which is
##   called by GameManager AFTER economy_system.process_tick() has already
##   converted wheat->food for that tick. This guarantees the food stockpile
##   is fully up-to-date before the threshold is evaluated.
class_name PopulationSystem
extends Node

const CFG_POP_KEY := "population"

var population:   int   = 0
var happiness:    float = 1.0
var unemployment: float = 0.0

var house_occupancy: HouseOccupancy = null

var _housing_capacity:           int   = 0
var _jobs_available:             int   = 0
var _food_per_citizen_per_day:   float = 1.0
var _water_per_citizen_per_day:  float = 1.0
var _food_immigration_threshold: float = 1.0
## Set to true by _on_new_day so process_tick() knows to run immigration
## after the economy tick has updated the food stockpile.
var _immigration_check_pending:  bool  = false
var _immigration_cooldown_days:  int   = 1
var _days_since_immigration:     int   = 999

func _ready() -> void:
	_load_config()
	house_occupancy = HouseOccupancy.new()
	EventBus.new_day.connect(house_occupancy.process_day)
	EventBus.building_selected.connect(house_occupancy._on_building_selected)
	EventBus.citizen_grew_up.connect(house_occupancy._on_citizen_grew_up)
	EventBus.citizen_died.connect(house_occupancy._on_citizen_died)
	GameManager.register_system("population", self)
	EventBus.new_day.connect(_on_new_day)
	EventBus.citizen_spawned.connect(_on_citizen_spawned)
	EventBus.citizen_died.connect(_on_citizen_died)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_POP_KEY, {})
	population                  = cfg.get("starting_population",        0)
	happiness                   = cfg.get("starting_happiness",         1.0)
	_food_per_citizen_per_day   = float(cfg.get("food_per_citizen_per_day",   1.0))
	_water_per_citizen_per_day  = float(cfg.get("water_per_citizen_per_day",  1.0))
	_food_immigration_threshold = float(cfg.get("food_immigration_threshold", 1.0))
	_immigration_cooldown_days  = int(cfg.get("immigration_cooldown_days",    1))

# ─── Daily callback ───────────────────────────────────────────────────────────
## Called synchronously inside advance_tick(), BEFORE economy_system.process_tick()
## runs. Only advance counters and emit shortages here — the immigration check
## is deferred to process_tick() so it always sees the updated food stockpile.
func _on_new_day(_day: int, _month: int, _year: int) -> void:
	var eco: EconomySystem = GameManager.get_system("economy")
	if eco == null:
		return

	# Check shortages — citizens consume food themselves via BT eat action.
	# We only emit shortage if the total stockpile cannot cover full demand,
	# so CitizenStats penalises citizens who couldn't eat.
	if population > 0:
		_check_shortage(eco, "food",  _food_per_citizen_per_day)
		_check_shortage(eco, "water", _water_per_citizen_per_day)

	_days_since_immigration += 1
	_immigration_check_pending = true

## Emits resource_shortage if the stockpile cannot cover the full daily demand.
## Does NOT deduct from the stockpile — citizens do that themselves when eating.
func _check_shortage(eco: EconomySystem, resource_id: String, rate: float) -> void:
	var demand: float = rate * float(population)
	var supply: float = eco.get_resource(resource_id)
	if supply < demand:
		EventBus.emit_signal("resource_shortage", resource_id)

# ─── Immigration ──────────────────────────────────────────────────────────────
func _check_immigration(eco: EconomySystem) -> void:
	if _days_since_immigration < _immigration_cooldown_days:
		return
	if eco.get_resource("food") < _food_immigration_threshold:
		return
	if not _any_house_has_capacity():
		return
	var gender: String = _determine_immigrant_gender()
	_spawn_immigrant(gender)
	_days_since_immigration = 0

func _determine_immigrant_gender() -> String:
	var counts: Dictionary = _count_adults_by_gender()
	var genders: Array = ConfigLoader.game_settings \
		.get("citizen_stats", {}).get("genders", ["male", "female"])
	var min_count:  int    = 999999
	var min_gender: String = str(genders[0]) if not genders.is_empty() else "male"
	for g in genders:
		var c: int = int(counts.get(str(g), 0))
		if c < min_count:
			min_count  = c
			min_gender = str(g)
	return min_gender

func _count_adults_by_gender() -> Dictionary:
	var result: Dictionary = {}
	var genders: Array = ConfigLoader.game_settings \
		.get("citizen_stats", {}).get("genders", ["male", "female"])
	for g in genders:
		result[str(g)] = 0
	var cm: Node = GameManager.citizen_manager
	if cm == null:
		return result
	for citizen in cm.get_all_citizens():
		if not is_instance_valid(citizen) or citizen.is_child or citizen.stats == null:
			continue
		var g: String = citizen.stats.gender
		result[g] = int(result.get(g, 0)) + 1
	return result

func _spawn_immigrant(gender: String) -> void:
	var cm: Node = GameManager.citizen_manager
	if cm == null:
		return
	var target_house: Vector2i = house_occupancy.find_house_for_immigrant(gender)
	if target_house == Vector2i(-1, -1):
		return
	var citizen: Citizen = cm.spawn_immigrant(target_house, gender)
	if citizen == null:
		return
	house_occupancy.add_resident(citizen, target_house)
	EventBus.emit_signal("citizen_arrived", citizen, gender)
	EventBus.notify(
		"Nuevo habitante: %s (%s)" % [citizen.stats.citizen_name, gender],
		"info"
	)

# ─── Population count ─────────────────────────────────────────────────────────
func _on_citizen_spawned(_citizen: Object, _cell: Vector2i) -> void:
	population += 1
	EventBus.emit_signal("population_changed", population)

func _on_citizen_died(_citizen: Object, _cause: String) -> void:
	population = maxi(0, population - 1)
	EventBus.emit_signal("population_changed", population)

# ─── Per-tick ─────────────────────────────────────────────────────────────────
## Called by GameManager AFTER economy_system.process_tick(), so food is current.
func process_tick() -> void:
	_update_capacity()
	_update_happiness()
	_update_unemployment()
	if _immigration_check_pending:
		_immigration_check_pending = false
		var eco: EconomySystem = GameManager.get_system("economy")
		if eco != null:
			_check_immigration(eco)

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

func _update_unemployment() -> void:
	if population == 0:
		unemployment = 0.0
	else:
		unemployment = clampf(1.0 - float(_jobs_available) / float(population), 0.0, 1.0)
	EventBus.emit_signal("unemployment_changed", unemployment)

func _any_house_has_capacity() -> bool:
	var gs: GridSystem = GameManager.grid_system
	if gs == null:
		return false
	for cell in gs.buildings:
		var bld: Building = gs.buildings[cell]
		if bld == null or bld.data == null or not bld.is_operational:
			continue
		if bld.data.population_capacity <= 0 or cell != bld.cell:
			continue
		if house_occupancy.get_occupants(cell).size() < bld.data.population_capacity:
			return true
	return false

# ─── Public accessors ─────────────────────────────────────────────────────────
func get_housing_capacity() -> int:
	return _housing_capacity

func get_jobs_available() -> int:
	return _jobs_available

# ─── Serialization ────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"population":             population,
		"happiness":              happiness,
		"days_since_immigration": _days_since_immigration,
		"house_occupancy":        house_occupancy.serialize(),
	}

func deserialize(data: Dictionary) -> void:
	population              = data.get("population",             0)
	happiness               = data.get("happiness",              1.0)
	_days_since_immigration = data.get("days_since_immigration", 999)
	if data.has("house_occupancy"):
		house_occupancy.deserialize(data["house_occupancy"])
	EventBus.emit_signal("population_changed", population)
	EventBus.emit_signal("happiness_changed",  happiness)