## BuildingPlacer.gd
## Handles placement mode: ghost preview, click to place, R to rotate, Escape to cancel.
## Supports both BuildingData placement and ResourceObject placement (trees, rocks).
## El click del mouse lo gestiona GameWorld._input y llama try_place_at_mouse().
class_name BuildingPlacer
extends Node3D

var _active: bool = false
var _pending_data: BuildingData = null
var _ghost: Node3D = null
var _hover_cell: Vector2i = Vector2i.ZERO
var _can_place_here: bool = false
var _rotation_steps: int = 0

## When non-empty, we are placing a resource object (tree/rock) rather than a building.
var _pending_resource_object_type: String = ""

const COLOR_VALID:   Color = Color(0.2, 1.0, 0.2, 0.5)
const COLOR_INVALID: Color = Color(1.0, 0.2, 0.2, 0.5)

func _ready() -> void:
	EventBus.build_mode_entered.connect(_on_build_mode_entered)
	EventBus.build_mode_exited.connect(_on_build_mode_exited)
	EventBus.build_mode_rotate.connect(_on_build_mode_rotate)

func _process(_delta: float) -> void:
	if not _active:
		return
	_update_ghost_position()
	if Input.is_action_just_pressed("rotate_building"):
		_rotate()
	if Input.is_action_just_pressed("cancel_action"):
		_cancel()

func try_place_at_mouse() -> void:
	if not _active:
		return
	if _pending_resource_object_type != "":
		_try_place_resource_object()
	else:
		_try_place()

# ── Building Placement ─────────────────────────────────────────────

func _try_place() -> void:
	if not _can_place_here:
		EventBus.notify("No se puede colocar aquí.", "warning")
		return
	var cost: int = _pending_data.build_cost
	if not GameManager.economy_system.can_afford(cost):
		EventBus.notify("Oro insuficiente. Necesitas %d." % cost, "error")
		return
	if not GameManager.grid_system.can_place(_pending_data_rotated(), _hover_cell):
		EventBus.notify("Celda ocupada.", "warning")
		return
	GameManager.economy_system.spend_gold(cost)
	var scene: PackedScene = load(_pending_data.scene_path)
	if scene == null:
		push_error("BuildingPlacer: escena no encontrada: " + _pending_data.scene_path)
		return
	var node: Building = scene.instantiate()
	node.initialize(_pending_data, _hover_cell)
	GameManager.grid_system.place_building(_pending_data_rotated(), _hover_cell, node)
	node.rotation_degrees.y = _rotation_steps * 90.0

# ── Resource Object Placement ──────────────────────────────────────

func _try_place_resource_object() -> void:
	if not _can_place_here:
		EventBus.notify("No se puede colocar aquí.", "warning")
		return
	var reg: ResourceObjectRegistry = GameManager.get_system("resource_object_registry")
	if reg == null:
		push_error("BuildingPlacer: ResourceObjectRegistry not found.")
		return
	var obj: ResourceObject = reg.place_object(_pending_resource_object_type, _hover_cell)
	if obj == null:
		EventBus.notify("Celda ya ocupada por un objeto.", "warning")
		return
	# Parent the new node to the grid so it appears in the world
	GameManager.grid_system.add_child(obj)
	obj.position = GameManager.grid_system.cell_to_world(_hover_cell)


func _can_place_resource_object_at(cell: Vector2i) -> bool:
	var gs: GridSystem = GameManager.grid_system
	if not gs.is_cell_free(cell):
		return false
	var reg: ResourceObjectRegistry = GameManager.get_system("resource_object_registry")
	if reg != null and reg.is_cell_occupied_by_object(cell):
		return false
	return true

# ── Rotation ──────────────────────────────────────────────────────

func _rotate() -> void:
	_rotation_steps = (_rotation_steps + 1) % 4
	if _ghost:
		_ghost.rotation_degrees.y = _rotation_steps * 90.0
	_update_ghost_position()

func _pending_data_rotated() -> BuildingData:
	if _rotation_steps % 2 == 0:
		return _pending_data
	var rotated := BuildingData.new()
	rotated.id                   = _pending_data.id
	rotated.display_name         = _pending_data.display_name
	rotated.description          = _pending_data.description
	rotated.category             = _pending_data.category
	rotated.icon_path            = _pending_data.icon_path
	rotated.scene_path           = _pending_data.scene_path
	rotated.size                 = Vector2i(_pending_data.size.y, _pending_data.size.x)
	rotated.build_cost           = _pending_data.build_cost
	rotated.demolish_refund      = _pending_data.demolish_refund
	rotated.upkeep_per_tick      = _pending_data.upkeep_per_tick
	rotated.income_per_tick      = _pending_data.income_per_tick
	rotated.population_capacity  = _pending_data.population_capacity
	rotated.jobs_provided        = _pending_data.jobs_provided
	rotated.happiness_modifier   = _pending_data.happiness_modifier
	rotated.resource_production  = _pending_data.resource_production
	rotated.resource_consumption = _pending_data.resource_consumption
	rotated.material_cost        = _pending_data.material_cost
	rotated.spawns_initial_citizen = _pending_data.spawns_initial_citizen
	rotated.requires_road        = _pending_data.requires_road
	rotated.requires_power       = _pending_data.requires_power
	rotated.requires_water       = _pending_data.requires_water
	rotated.unlock_level         = _pending_data.unlock_level
	rotated.max_level            = _pending_data.max_level
	rotated.upgrade_costs        = _pending_data.upgrade_costs
	rotated.mesh_config          = _pending_data.mesh_config
	return rotated

func _cancel() -> void:
	EventBus.emit_signal("build_mode_exited")

# ── Ghost ─────────────────────────────────────────────────────────

func _update_ghost_position() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse_pos: Vector2  = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_dir: Vector3    = cam.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return
	var t: float           = -ray_origin.y / ray_dir.y
	var world_pos: Vector3 = ray_origin + ray_dir * t
	_hover_cell = GameManager.grid_system.world_to_cell(world_pos)

	if _pending_resource_object_type != "":
		_can_place_here = _can_place_resource_object_at(_hover_cell)
	else:
		_can_place_here = GameManager.grid_system.can_place(_pending_data_rotated(), _hover_cell)

	if _ghost:
		_ghost.position           = GameManager.grid_system.cell_to_world(_hover_cell)
		_ghost.rotation_degrees.y = _rotation_steps * 90.0
		_tint_ghost(_can_place_here)

func _tint_ghost(valid: bool) -> void:
	var color: Color = COLOR_VALID if valid else COLOR_INVALID
	var mesh_inst: MeshInstance3D = _ghost.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst and mesh_inst.material_override:
		(mesh_inst.material_override as StandardMaterial3D).albedo_color = color

func _create_ghost() -> void:
	_destroy_ghost()
	if _pending_resource_object_type != "":
		_create_resource_object_ghost()
		return
	var scene: PackedScene = load(_pending_data.scene_path)
	if scene == null:
		return
	_ghost = scene.instantiate()
	if _ghost.has_method("initialize"):
		_ghost.initialize(_pending_data, Vector2i.ZERO)
	add_child(_ghost)
	_ghost.rotation_degrees.y = _rotation_steps * 90.0

func _create_resource_object_ghost() -> void:
	var cfg: Dictionary   = ConfigLoader.resource_objects.get(_pending_resource_object_type, {})
	var script_path: String = cfg.get("script_path", "")
	var obj: ResourceObject
	if script_path != "":
		var script: GDScript = load(script_path) as GDScript
		if script:
			obj = script.new() as ResourceObject
	if obj == null:
		obj = ResourceObject.new()
	obj.initialize(_pending_resource_object_type, Vector2i.ZERO, cfg)
	_ghost = obj
	add_child(_ghost)

func _destroy_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null

# ── EventBus handlers ─────────────────────────────────────────────

func _on_build_mode_entered(building_id: String) -> void:
	# Check if this is a resource object type
	if ConfigLoader.resource_objects.has(building_id):
		_pending_resource_object_type = building_id
		_pending_data                 = null
		_rotation_steps               = 0
		_active                       = true
		_create_ghost()
		return
	# Otherwise treat as normal building
	var raw: Dictionary = ConfigLoader.get_building(building_id)
	if raw.is_empty():
		push_error("BuildingPlacer: ID desconocido '%s'" % building_id)
		return
	_pending_data                 = BuildingData.from_dict(raw)
	_pending_resource_object_type = ""
	_rotation_steps               = 0
	_active                       = true
	_create_ghost()

func _on_build_mode_exited() -> void:
	_active                       = false
	_pending_data                 = null
	_pending_resource_object_type = ""
	_rotation_steps               = 0
	_destroy_ghost()

func _on_build_mode_rotate() -> void:
	if _active:
		_rotate()
