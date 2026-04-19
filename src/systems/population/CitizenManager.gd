## CitizenManager.gd
## Owns all Citizen nodes in the world.
## Listens to building_placed / building_removed signals to spawn / despawn citizens.
## Citizens are always in sync with population_capacity across all residential buildings.
class_name CitizenManager
extends Node3D

const CFG_KEY := "citizens"

# ─── State ────────────────────────────────────────────────────────
## Maps building origin cell → Array[Citizen] for citizens that live there.
var _citizens_by_cell: Dictionary = {}

## Citizen visual config loaded from game_settings.json
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
	var capacity: int = building_data.population_capacity
	if capacity <= 0:
		return
	_spawn_citizens_for_cell(cell, building_data, capacity)

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.population_capacity <= 0:
		return
	_despawn_citizens_for_cell(cell)

# ─── Spawn / Despawn ──────────────────────────────────────────────
func _spawn_citizens_for_cell(cell: Vector2i, building_data: BuildingData, count: int) -> void:
	if _citizens_by_cell.has(cell):
		_despawn_citizens_for_cell(cell)

	var citizens: Array[Citizen] = []
	var cell_size: float = GameManager.grid_system.cell_size
	# Building footprint size to scale citizens proportionally
	var footprint_size: float = float(maxi(building_data.size.x, building_data.size.y)) * cell_size

	for i in range(count):
		var citizen := _create_citizen(cell, footprint_size, i, count)
		citizens.append(citizen)
		EventBus.emit_signal("citizen_spawned", citizen, cell)

	_citizens_by_cell[cell] = citizens

func _despawn_citizens_for_cell(cell: Vector2i) -> void:
	if not _citizens_by_cell.has(cell):
		return
	var citizens: Array = _citizens_by_cell[cell]
	for citizen in citizens:
		EventBus.emit_signal("citizen_despawned", citizen, cell)
		citizen.queue_free()
	_citizens_by_cell.erase(cell)

func _create_citizen(cell: Vector2i, footprint_size: float, index: int, total: int) -> Citizen:
	var citizen := Citizen.new()
	citizen.name = "Citizen_%d_%d_%d" % [cell.x, cell.y, index]

	citizen.initialize(cell, _citizen_cfg)
	citizen.setup_size(footprint_size)
	citizen.set_color(_pick_color(index))

	# Must be in the tree before accessing global_position
	add_child(citizen)

	var home_world: Vector3 = GameManager.grid_system.cell_to_world(cell)
	var offset := _spread_offset(index, total, footprint_size * 0.3)
	citizen.global_position = home_world + offset

	return citizen

## Distribute citizens evenly in a small circle around home.
func _spread_offset(index: int, total: int, radius: float) -> Vector3:
	if total <= 1:
		return Vector3.ZERO
	var angle: float = (TAU / float(total)) * float(index)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## Returns a varied but deterministic skin-tone color per index slot.
func _pick_color(index: int) -> Color:
	var colors: Array = _citizen_cfg.get("palette", [
		"#e8c090", "#c89060", "#a06030", "#f0d0a0", "#d0a070"
	])
	return Color(colors[index % colors.size()])

# ─── Queries ──────────────────────────────────────────────────────
func get_total_citizens() -> int:
	var total: int = 0
	for cell in _citizens_by_cell:
		total += (_citizens_by_cell[cell] as Array).size()
	return total

func get_citizens_at(cell: Vector2i) -> Array:
	return _citizens_by_cell.get(cell, [])
