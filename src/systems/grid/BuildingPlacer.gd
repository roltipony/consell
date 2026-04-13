## BuildingPlacer.gd
## Handles placement mode: ghost preview, click to place, R to rotate, Escape to cancel.
class_name BuildingPlacer
extends Node2D

var _active: bool = false
var _pending_data: BuildingData = null
var _ghost: Node2D = null
var _hover_cell: Vector2i = Vector2i.ZERO
var _can_place_here: bool = false
var _rotation_steps: int = 0   # 0=0°, 1=90°, 2=180°, 3=270°

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

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("place_building"):
		_try_place()
	elif event.is_action_pressed("rotate_building"):
		_rotate()
	elif event.is_action_pressed("cancel_action"):
		_cancel()

# ── Placement ─────────────────────────────────────────────────────
func _try_place() -> void:
	if not _can_place_here:
		EventBus.notify("Cannot place here!", "warning")
		return
	var cost: int = _pending_data.build_cost
	if not GameManager.economy_system.can_afford(cost):
		EventBus.notify("Not enough gold! Need %d" % cost, "error")
		return
	GameManager.economy_system.spend_gold(cost)
	var scene: PackedScene = load(_pending_data.scene_path)
	assert(scene != null, "Building scene not found: " + _pending_data.scene_path)
	var node: Building = scene.instantiate()
	node.initialize(_pending_data, _hover_cell)
	get_parent().add_child(node)
	node.position = GameManager.grid_system.cell_to_world(_hover_cell)
	# Apply visual rotation to the placed building
	node.rotation_degrees = _rotation_steps * 90.0
	GameManager.grid_system.place_building(_pending_data_rotated(), _hover_cell, node)

# ── Rotation ──────────────────────────────────────────────────────
func _rotate() -> void:
	_rotation_steps = (_rotation_steps + 1) % 4
	if _ghost:
		_ghost.rotation_degrees = _rotation_steps * 90.0
	_update_ghost_position()

## Returns a BuildingData with size swapped if rotated 90° or 270°
func _pending_data_rotated() -> BuildingData:
	if _rotation_steps % 2 == 0:
		return _pending_data
	# Swap width and height for 90/270 rotation
	var rotated := BuildingData.new()
	rotated.id                  = _pending_data.id
	rotated.display_name        = _pending_data.display_name
	rotated.description         = _pending_data.description
	rotated.category            = _pending_data.category
	rotated.icon_path           = _pending_data.icon_path
	rotated.scene_path          = _pending_data.scene_path
	rotated.size                = Vector2i(_pending_data.size.y, _pending_data.size.x)
	rotated.build_cost          = _pending_data.build_cost
	rotated.demolish_refund     = _pending_data.demolish_refund
	rotated.upkeep_per_tick     = _pending_data.upkeep_per_tick
	rotated.income_per_tick     = _pending_data.income_per_tick
	rotated.population_capacity = _pending_data.population_capacity
	rotated.jobs_provided       = _pending_data.jobs_provided
	rotated.happiness_modifier  = _pending_data.happiness_modifier
	rotated.resource_production = _pending_data.resource_production
	rotated.resource_consumption = _pending_data.resource_consumption
	rotated.requires_road       = _pending_data.requires_road
	rotated.requires_power      = _pending_data.requires_power
	rotated.requires_water      = _pending_data.requires_water
	rotated.unlock_level        = _pending_data.unlock_level
	rotated.max_level           = _pending_data.max_level
	rotated.upgrade_costs       = _pending_data.upgrade_costs
	return rotated

func _cancel() -> void:
	EventBus.emit_signal("build_mode_exited")

# ── Ghost ─────────────────────────────────────────────────────────
func _update_ghost_position() -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	_hover_cell = GameManager.grid_system.world_to_cell(mouse_world)
	_can_place_here = GameManager.grid_system.can_place(_pending_data_rotated(), _hover_cell)
	if _ghost:
		_ghost.position = GameManager.grid_system.cell_to_world(_hover_cell)
		_ghost.modulate = COLOR_VALID if _can_place_here else COLOR_INVALID
		_ghost.rotation_degrees = _rotation_steps * 90.0

func _create_ghost() -> void:
	_destroy_ghost()
	var scene: PackedScene = load(_pending_data.scene_path)
	if scene:
		_ghost = scene.instantiate()
		# Initialize before entering the tree so Building._ready() assertion passes
		if _ghost.has_method("initialize"):
			_ghost.initialize(_pending_data, Vector2i.ZERO)
		add_child(_ghost)
		_ghost.modulate = COLOR_VALID
		_ghost.rotation_degrees = _rotation_steps * 90.0

func _destroy_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null

# ── EventBus handlers ─────────────────────────────────────────────
func _on_build_mode_entered(building_id: String) -> void:
	var raw: Dictionary = ConfigLoader.get_building(building_id)
	if raw.is_empty():
		push_error("BuildingPlacer: Unknown building id '%s'" % building_id)
		return
	_pending_data    = BuildingData.from_dict(raw)
	_rotation_steps  = 0
	_active          = true
	_create_ghost()

func _on_build_mode_exited() -> void:
	_active          = false
	_pending_data    = null
	_rotation_steps  = 0
	_destroy_ghost()

func _on_build_mode_rotate() -> void:
	if _active:
		_rotate()