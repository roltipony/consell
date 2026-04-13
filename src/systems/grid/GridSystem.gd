## GridSystem.gd
## Manages the city grid: cell occupancy, zone types, road network,
## placement validation, and initial map generation.
class_name GridSystem
extends Node

const CFG_KEY := "grid"

# ── State ─────────────────────────────────────────────────────────
var grid_width:  int = 64
var grid_height: int = 64
var cell_size:   Vector2i = Vector2i(64, 32)

var buildings:  Dictionary = {}   # Vector2i → Building
var zones:      Dictionary = {}   # Vector2i → String
var road_cells: Dictionary = {}   # Vector2i → true

# ── Node refs ─────────────────────────────────────────────────────
@onready var tilemap: TileMapLayer = $TileMapLayer

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	GameManager.register_system("grid", self)
	_run_map_generator()

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	grid_width  = cfg.get("width",     grid_width)
	grid_height = cfg.get("height",    grid_height)
	var cs: Array = cfg.get("cell_size", [cell_size.x, cell_size.y])
	cell_size   = Vector2i(int(cs[0]), int(cs[1]))

func _run_map_generator() -> void:
	var gen: MapGenerator = MapGenerator.new()
	add_child(gen)
	gen.generate(tilemap, grid_width, grid_height)

# ── Placement ─────────────────────────────────────────────────────
func can_place(building_data: BuildingData, origin: Vector2i) -> bool:
	for dx in range(building_data.size.x):
		for dy in range(building_data.size.y):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not _in_bounds(c):
				return false
			if buildings.has(c):
				return false
	if building_data.requires_road and not _has_adjacent_road(origin, building_data.size):
		return false
	return true

func place_building(building_data: BuildingData, origin: Vector2i, building_node: Building) -> void:
	assert(can_place(building_data, origin), "Tried to place building on occupied/invalid cell")
	for dx in range(building_data.size.x):
		for dy in range(building_data.size.y):
			buildings[origin + Vector2i(dx, dy)] = building_node
	EventBus.emit_signal("building_placed", building_data, origin)

func remove_building(origin: Vector2i) -> void:
	if not buildings.has(origin):
		return
	var node: Building = buildings[origin]
	var bd: BuildingData = node.data
	for dx in range(bd.size.x):
		for dy in range(bd.size.y):
			buildings.erase(origin + Vector2i(dx, dy))
	EventBus.emit_signal("building_removed", bd, origin)
	node.queue_free()

# ── Roads ─────────────────────────────────────────────────────────
func set_road(cell: Vector2i, has_road: bool) -> void:
	if has_road:
		road_cells[cell] = true
	else:
		road_cells.erase(cell)

func is_road(cell: Vector2i) -> bool:
	return road_cells.has(cell)

# ── Zones ─────────────────────────────────────────────────────────
func set_zone(cell: Vector2i, zone_type: String) -> void:
	zones[cell] = zone_type
	EventBus.emit_signal("zone_changed", cell, zone_type)

func get_zone(cell: Vector2i) -> String:
	return zones.get(cell, "none")

# ── Queries ───────────────────────────────────────────────────────
func get_building_at(cell: Vector2i) -> Building:
	return buildings.get(cell, null)

func is_cell_free(cell: Vector2i) -> bool:
	return not buildings.has(cell) and _in_bounds(cell)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var x: int = int(world_pos.x / cell_size.x)
	var y: int = int(world_pos.y / cell_size.y)
	return Vector2i(x, y)

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size.x, cell.y * cell_size.y)

# ── Internals ─────────────────────────────────────────────────────
func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height

func _has_adjacent_road(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			var c: Vector2i = origin + Vector2i(dx, dy)
			for adj in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				if is_road(c + adj):
					return true
	return false

# ── Serialisation ─────────────────────────────────────────────────
func serialize() -> Dictionary:
	var buildings_data: Array = []
	var visited: Dictionary = {}
	for cell_key in buildings:
		var bld: Building = buildings[cell_key]
		if visited.has(bld):
			continue
		visited[bld] = true
		buildings_data.append(bld.serialize())

	var roads_data: Array = []
	for c in road_cells:
		roads_data.append([c.x, c.y])

	var zones_data: Dictionary = {}
	for c in zones:
		zones_data["%d,%d" % [c.x, c.y]] = zones[c]

	return {"buildings": buildings_data, "roads": roads_data, "zones": zones_data}

func deserialize(data: Dictionary) -> void:
	for road in data.get("roads", []):
		road_cells[Vector2i(road[0], road[1])] = true
	for kv in data.get("zones", {}).keys():
		var parts: PackedStringArray = kv.split(",")
		zones[Vector2i(int(parts[0]), int(parts[1]))] = data["zones"][kv]
