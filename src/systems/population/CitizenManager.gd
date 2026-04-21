## CitizenManager.gd
## Owns all Citizen nodes in the world.
## Spawns exactly 1 citizen per residential building, of the type defined by citizen_type in buildings.json.
## Listens to building_placed / building_removed signals via EventBus.
class_name CitizenManager
extends Node3D

const CFG_KEY := "citizens"

# ─── State ────────────────────────────────────────────────────────
## Maps building origin cell → Citizen (one per house)
var _citizen_by_cell: Dictionary = {}

var _citizen_cfg: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)

func _load_config() -> void:
	_citizen_cfg = ConfigLoader.game_settings.get(CFG_KEY, {})

# ─── Signal Handlers ──────────────────────────────────────────────
func _on_building_placed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_spawn_citizen_for_cell(cell, building_data)

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_despawn_citizen_for_cell(cell)

# ─── Spawn / Despawn ──────────────────────────────────────────────
func _spawn_citizen_for_cell(cell: Vector2i, building_data: BuildingData) -> void:
	if _citizen_by_cell.has(cell):
		_despawn_citizen_for_cell(cell)

	var cell_size: float = GameManager.grid_system.cell_size
	var footprint_size: float = float(maxi(building_data.size.x, building_data.size.y)) * cell_size
	var citizen_type: String = building_data.citizen_type

	var citizen := _create_citizen(cell, footprint_size, citizen_type)
	_citizen_by_cell[cell] = citizen
	# Emit after start() so listeners (WheatFieldRegistry) find _ctx ready
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
	citizen.name = "Citizen_%s_%d_%d" % [citizen_type, cell.x, cell.y]

	# 1. Add to tree first so _ready() runs (sets up visuals)
	add_child(citizen)

	# 2. Initialize config and home cell
	citizen.initialize(cell, _citizen_cfg)
	citizen.setup_size(footprint_size)

	# 3. Build BT and context now that home_cell is set
	citizen.start()

	# 4. Position in world
	citizen.global_position = GameManager.grid_system.cell_to_world(cell)
	return citizen

func _instantiate_type(citizen_type: String) -> Citizen:
	match citizen_type:
		"farmer":
			return FarmerCitizen.new()
		_:
			return Citizen.new()

# ─── Queries ──────────────────────────────────────────────────────
func get_total_citizens() -> int:
	return _citizen_by_cell.size()

func get_citizens_at(cell: Vector2i) -> Array:
	var citizen: Citizen = _citizen_by_cell.get(cell, null)
	if citizen == null:
		return []
	return [citizen]

func get_all_citizen_cells() -> Array:
	return _citizen_by_cell.keys()
