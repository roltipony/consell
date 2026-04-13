## BuildingPlacer.gd
## Handles placement mode: ghost preview, click to place, Escape to cancel.
class_name BuildingPlacer
extends Node2D

var _active: bool = false
var _pending_data: BuildingData = null
var _ghost: Node2D = null
var _hover_cell: Vector2i = Vector2i.ZERO
var _can_place_here: bool = false

const COLOR_VALID:   Color = Color(0.2, 1.0, 0.2, 0.5)
const COLOR_INVALID: Color = Color(1.0, 0.2, 0.2, 0.5)

func _ready() -> void:
	EventBus.build_mode_entered.connect(_on_build_mode_entered)
	EventBus.build_mode_exited.connect(_on_build_mode_exited)

func _process(_delta: float) -> void:
	if not _active:
		return
	_update_ghost_position()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("place_building"):
		_try_place()
	elif event.is_action_pressed("cancel_action"):
		_cancel()

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
	GameManager.grid_system.place_building(_pending_data, _hover_cell, node)

func _cancel() -> void:
	EventBus.emit_signal("build_mode_exited")

func _update_ghost_position() -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	_hover_cell = GameManager.grid_system.world_to_cell(mouse_world)
	_can_place_here = GameManager.grid_system.can_place(_pending_data, _hover_cell)
	if _ghost:
		_ghost.position = GameManager.grid_system.cell_to_world(_hover_cell)
		_ghost.modulate = COLOR_VALID if _can_place_here else COLOR_INVALID

func _create_ghost() -> void:
	_destroy_ghost()
	var scene: PackedScene = load(_pending_data.scene_path)
	if scene:
		_ghost = scene.instantiate()
		add_child(_ghost)
		_ghost.modulate = COLOR_VALID

func _destroy_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null

func _on_build_mode_entered(building_id: String) -> void:
	var raw: Dictionary = ConfigLoader.get_building(building_id)
	if raw.is_empty():
		push_error("BuildingPlacer: Unknown building id '%s'" % building_id)
		return
	_pending_data = BuildingData.from_dict(raw)
	_active       = true
	_create_ghost()

func _on_build_mode_exited() -> void:
	_active       = false
	_pending_data = null
	_destroy_ghost()
