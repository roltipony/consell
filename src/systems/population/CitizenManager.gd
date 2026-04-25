## CitizenManager.gd
## Owns all Citizen nodes in the world.
## Spawns one citizen per residential building using a data-driven type factory.
## The mapping citizen_type → class lives in game_settings.json["citizen_type_classes"],
## so new citizen types never require changes to this file.
class_name CitizenManager
extends Node3D

const CFG_KEY       := "citizens"
const CFG_TYPES_KEY := "citizen_type_classes"

# ─── State ────────────────────────────────────────────────────────────────────
## Maps building origin cell → Citizen (one per house)
var _citizen_by_cell: Dictionary = {}

var _citizen_cfg:     Dictionary = {}
## Maps citizen_type string → GDScript resource (loaded once at startup)
var _type_scripts:    Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	GameManager.register_system("citizen_manager", self)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)
	EventBus.citizen_died.connect(_on_citizen_died)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings
	_citizen_cfg = cfg.get(CFG_KEY, {})

	# Build script cache from config map: {"farmer": "FarmerCitizen", "generic": "Citizen"}
	# Scripts are resolved by class_name — we store them keyed by type string.
	var type_map: Dictionary = cfg.get(CFG_TYPES_KEY, {})
	_type_scripts.clear()
	for type_key in type_map:
		var class_name_str: String = type_map[type_key]
		var script := _find_script_by_class_name(class_name_str)
		if script:
			_type_scripts[type_key] = script
		else:
			push_warning("CitizenManager: no script found for class '%s' (type '%s')" \
				% [class_name_str, type_key])

## Searches the global class list for a GDScript matching the given class_name string.
func _find_script_by_class_name(class_name_str: String) -> GDScript:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == class_name_str:
			return load(entry["path"]) as GDScript
	return null

# ─── Signal Handlers ──────────────────────────────────────────────────────────
func _on_building_placed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_spawn_citizen_for_cell(cell, building_data)

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_despawn_citizen_for_cell(cell)

## Handles natural death (starvation, dehydration, old age) triggered by CitizenStats.
## Removes the citizen from the registry; queue_free() is called by Citizen itself.
func _on_citizen_died(citizen: Citizen, _cause: String) -> void:
	for cell in _citizen_by_cell:
		if _citizen_by_cell[cell] == citizen:
			_citizen_by_cell.erase(cell)
			return

# ─── Spawn / Despawn ──────────────────────────────────────────────────────────
func _spawn_citizen_for_cell(cell: Vector2i, building_data: BuildingData) -> void:
	if _citizen_by_cell.has(cell):
		_despawn_citizen_for_cell(cell)

	var cell_size:      float = GameManager.grid_system.cell_size
	var footprint_size: float = float(maxi(building_data.size.x, building_data.size.y)) * cell_size

	var citizen := _create_citizen(cell, footprint_size, building_data.citizen_type)
	_citizen_by_cell[cell] = citizen
	EventBus.emit_signal("citizen_spawned", citizen, cell)

func _despawn_citizen_for_cell(cell: Vector2i) -> void:
	if not _citizen_by_cell.has(cell):
		return
	var citizen: Citizen = _citizen_by_cell[cell]
	EventBus.emit_signal("citizen_despawned", citizen, cell)
	citizen.queue_free()
	_citizen_by_cell.erase(cell)

func _create_citizen(cell: Vector2i, footprint_size: float, citizen_type: String) -> Citizen:
	var citizen: Citizen = _instantiate_type(citizen_type)
	citizen.name = "Citizen_%d_%d" % [cell.x, cell.y]

	# 1. Add to tree so _ready() runs (sets up visuals with default color)
	add_child(citizen)

	# 2. Initialize config and home cell
	citizen.initialize(cell, _citizen_cfg)
	citizen.setup_size(footprint_size)

	# 3. Build BT and context now that home_cell is set
	citizen.start()

	# 4. Position in world
	citizen.global_position = GameManager.grid_system.cell_to_world(cell)
	return citizen

## Instantiates the correct Citizen subclass using the data-driven script cache.
## Falls back to base Citizen if the type is not registered.
func _instantiate_type(citizen_type: String) -> Citizen:
	var script: GDScript = _type_scripts.get(citizen_type, null)
	if script == null:
		script = _type_scripts.get("generic", null)
	if script == null:
		return Citizen.new()
	var instance = script.new()
	assert(instance is Citizen, \
		"citizen_type_classes entry '%s' does not extend Citizen" % citizen_type)
	return instance as Citizen

# ─── Queries ──────────────────────────────────────────────────────────────────
func get_total_citizens() -> int:
	return _citizen_by_cell.size()

func get_citizens_at(cell: Vector2i) -> Array:
	var citizen: Citizen = _citizen_by_cell.get(cell, null)
	if citizen == null:
		return []
	return [citizen]

func get_all_citizen_cells() -> Array:
	return _citizen_by_cell.keys()
