## CitizenManager.gd
## Owns all Citizen nodes in the world.
##
## Spawn entry-points:
##   _spawn_citizen_for_cell → called when a building is placed (building_placed signal).
##                             After creating the citizen it calls
##                             PopulationSystem.house_occupancy.add_resident()
##                             so the initial resident appears in the house panel.
##   spawn_immigrant(cell, gender) → called by PopulationSystem on immigration.
##   spawn_child(cell, gender)     → called by HouseOccupancy on reproduction.
class_name CitizenManager
extends Node3D

const CFG_KEY       := "citizens"
const CFG_TYPES_KEY := "citizen_type_classes"

var _citizen_by_cell: Dictionary  = {}
var _all_citizens:    Array[Citizen] = []
var _citizen_cfg:     Dictionary  = {}
var _type_scripts:    Dictionary  = {}

func _ready() -> void:
	_load_config()
	GameManager.register_system("citizen_manager", self)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)
	EventBus.citizen_died.connect(_on_citizen_died)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings
	_citizen_cfg = cfg.get(CFG_KEY, {})
	var type_map: Dictionary   = cfg.get(CFG_TYPES_KEY, {})
	var path_map: Dictionary   = cfg.get("citizen_type_script_paths", {})
	_type_scripts.clear()
	for type_key in type_map:
		var class_name_str: String = type_map[type_key]
		# 1. Try explicit path first (works even before Godot re-imports the project)
		var script: GDScript = null
		if path_map.has(type_key):
			script = load(path_map[type_key]) as GDScript
		# 2. Fall back to global class list lookup
		if script == null:
			script = _find_script_by_class_name(class_name_str)
		if script:
			_type_scripts[type_key] = script
		else:
			push_warning("CitizenManager: no script found for class '%s' (type '%s')" \
				% [class_name_str, type_key])

func _find_script_by_class_name(class_name_str: String) -> GDScript:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == class_name_str:
			return load(entry["path"]) as GDScript
	return null

# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_building_placed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	# Extraction buildings start empty; an unemployed adult will move in later.
	if not building_data.spawns_initial_citizen:
		return
	_spawn_citizen_for_cell(cell, building_data)

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_despawn_all_for_cell(cell)

func _on_citizen_died(citizen: Citizen, _cause: String) -> void:
	_all_citizens.erase(citizen)
	for cell in _citizen_by_cell:
		if _citizen_by_cell[cell] == citizen:
			_citizen_by_cell.erase(cell)
			break

# ─── Core spawn / despawn ─────────────────────────────────────────────────────

func _spawn_citizen_for_cell(cell: Vector2i, building_data: BuildingData) -> void:
	if _citizen_by_cell.has(cell):
		_despawn_all_for_cell(cell)

	var cell_size:      float = GameManager.grid_system.cell_size
	var footprint_size: float = float(maxi(building_data.size.x, building_data.size.y)) * cell_size

	var citizen := _create_citizen(cell, footprint_size, building_data.citizen_type, "", -1, false)
	_citizen_by_cell[cell] = citizen
	_all_citizens.append(citizen)
	EventBus.emit_signal("citizen_spawned", citizen, cell)

	# Register the initial resident in HouseOccupancy so it appears in the panel.
	# PopulationSystem may not be ready yet on the very first frame, so we defer.
	_register_initial_resident.call_deferred(citizen, cell)

func _register_initial_resident(citizen: Citizen, cell: Vector2i) -> void:
	var pop: PopulationSystem = GameManager.get_system("population")
	if pop == null or pop.house_occupancy == null:
		return
	if not is_instance_valid(citizen):
		return
	pop.house_occupancy.add_resident(citizen, cell)

func _despawn_all_for_cell(cell: Vector2i) -> void:
	if _citizen_by_cell.has(cell):
		var primary: Citizen = _citizen_by_cell[cell]
		EventBus.emit_signal("citizen_despawned", primary, cell)
		_all_citizens.erase(primary)
		primary.queue_free()
		_citizen_by_cell.erase(cell)

	var snapshot: Array[Citizen] = _all_citizens.duplicate()
	for citizen in snapshot:
		if is_instance_valid(citizen) and citizen.home_cell == cell:
			EventBus.emit_signal("citizen_despawned", citizen, cell)
			_all_citizens.erase(citizen)
			citizen.queue_free()

# ─── Public spawn API ─────────────────────────────────────────────────────────

func spawn_immigrant(house_cell: Vector2i, gender: String) -> Citizen:
	var bld: Building = _get_building(house_cell)
	if bld == null:
		push_warning("CitizenManager.spawn_immigrant: no building at %s" % str(house_cell))
		return null

	var cell_size:      float = GameManager.grid_system.cell_size
	var footprint_size: float = float(maxi(bld.data.size.x, bld.data.size.y)) * cell_size

	var citizen := _create_citizen(house_cell, footprint_size, bld.data.citizen_type, gender, -1, false)
	_all_citizens.append(citizen)

	if not _citizen_by_cell.has(house_cell):
		_citizen_by_cell[house_cell] = citizen

	EventBus.emit_signal("citizen_spawned", citizen, house_cell)
	return citizen

func spawn_child(house_cell: Vector2i, gender: String) -> Citizen:
	var bld: Building = _get_building(house_cell)
	if bld == null:
		push_warning("CitizenManager.spawn_child: no building at %s" % str(house_cell))
		return null

	var cell_size:      float = GameManager.grid_system.cell_size
	var footprint_size: float = float(maxi(bld.data.size.x, bld.data.size.y)) * cell_size

	var citizen := _create_citizen(house_cell, footprint_size, bld.data.citizen_type, gender, 0, true)
	_all_citizens.append(citizen)
	EventBus.emit_signal("citizen_spawned", citizen, house_cell)
	return citizen

# ─── Internal factory ─────────────────────────────────────────────────────────

func _create_citizen(
	cell: Vector2i,
	footprint_size: float,
	citizen_type: String,
	forced_gender: String,
	forced_age: int,
	child: bool
) -> Citizen:
	var citizen: Citizen = _instantiate_type(citizen_type)
	citizen.name          = "Citizen_%d_%d_%d" % [cell.x, cell.y, _all_citizens.size()]
	citizen.forced_gender = forced_gender
	citizen.forced_age    = forced_age
	citizen.is_child      = child

	add_child(citizen)
	citizen.initialize(cell, _citizen_cfg)
	citizen.setup_size(footprint_size)
	citizen.start()

	var base_world: Vector3 = GameManager.grid_system.cell_to_world(cell)
	citizen.global_position = base_world + Vector3(
		randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)
	)
	return citizen

func _instantiate_type(citizen_type: String) -> Citizen:
	var script: GDScript = _type_scripts.get(citizen_type, null)
	if script == null:
		script = _type_scripts.get("generic", null)
	if script == null:
		return Citizen.new()
	var instance = script.new()
	assert(instance is Citizen,
		"citizen_type_classes entry '%s' does not extend Citizen" % citizen_type)
	return instance as Citizen

func _get_building(cell: Vector2i) -> Building:
	var gs: GridSystem = GameManager.grid_system
	if gs == null or not gs.buildings.has(cell):
		return null
	return gs.buildings[cell] as Building

# ─── Queries ──────────────────────────────────────────────────────────────────

func get_all_citizens() -> Array[Citizen]:
	_all_citizens = _all_citizens.filter(func(c): return is_instance_valid(c))
	return _all_citizens.duplicate()

func get_total_citizens() -> int:
	return _all_citizens.filter(func(c): return is_instance_valid(c)).size()

func get_citizens_at(cell: Vector2i) -> Array:
	var citizen: Citizen = _citizen_by_cell.get(cell, null)
	if citizen == null or not is_instance_valid(citizen):
		return []
	return [citizen]

func get_all_citizen_cells() -> Array:
	return _citizen_by_cell.keys()
