## GridSystem.gd
## Manages the city grid: cell occupancy, zone types, road network,
## placement validation, and procedural 3D ground generation.
class_name GridSystem
extends Node3D

const CFG_KEY := "grid"

# ── State ─────────────────────────────────────────────────────────
var grid_width: int  = 20
var grid_height: int = 20
var cell_size: float = 2.0

var buildings: Dictionary  = {}  # Vector2i → Building
var zones: Dictionary      = {}  # Vector2i → String
var road_cells: Dictionary = {}  # Vector2i → true

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	GameManager.register_system("grid", self)
	_build_ground()

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	grid_width  = cfg.get("width",     grid_width)
	grid_height = cfg.get("height",    grid_height)
	# cell_size puede venir como float o como Array legacy [64,32]
	var raw = cfg.get("cell_size", cell_size)
	if raw is Array:
		cell_size = float(raw[0]) / 32.0  # normalizar: 64px → 2.0 unidades
	else:
		cell_size = float(raw)

func _build_ground() -> void:
	for x in range(grid_width):
		for z in range(grid_height):
			_spawn_ground_tile(x, z)

func _spawn_ground_tile(x: int, z: int) -> void:
	var tile := Node3D.new()
	tile.name = "Tile_%d_%d" % [x, z]

	# Plano de hierba con variación de color sutil
	var grass := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(cell_size * 0.97, cell_size * 0.97)
	grass.mesh = plane
	var mat := StandardMaterial3D.new()
	var v := randf_range(-0.04, 0.04)
	mat.albedo_color = Color(0.22 + v, 0.55 + v, 0.12 + v)
	mat.roughness = 1.0
	grass.material_override = mat
	tile.add_child(grass)

	# Borde oscuro de celda
	var border := MeshInstance3D.new()
	var border_plane := PlaneMesh.new()
	border_plane.size = Vector2(cell_size, cell_size)
	border.mesh = border_plane
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.28, 0.04)
	bmat.roughness = 1.0
	border.material_override = bmat
	border.position.y = -0.001
	tile.add_child(border)

	tile.position = cell_to_world(Vector2i(x, z))
	add_child(tile)

# ── Coordinate helpers ────────────────────────────────────────────
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		cell.x * cell_size + cell_size * 0.5,
		0.0,
		cell.y * cell_size + cell_size * 0.5
	)

func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.z / cell_size)
	)

func get_grid_center() -> Vector3:
	return Vector3(
		grid_width  * cell_size * 0.5,
		0.0,
		grid_height * cell_size * 0.5
	)

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
	if not can_place(building_data, origin):
		push_warning("GridSystem: can_place false en origin %s" % str(origin))
		return
	building_node.position = cell_to_world(origin)
	add_child(building_node)
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
