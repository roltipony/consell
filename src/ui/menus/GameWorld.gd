## GameWorld.gd
## Root scene script. Loads UI, wires systems, and handles input routing.
##
## Citizen interaction:
##   - Hover: each _process frame a raycast detects the citizen under the cursor
##     and emits citizen_hovered / citizen_unhovered on the EventBus.
##   - Click (left button, not over UI):
##       1. Citizen under cursor → citizen_selected
##       2. Building under cursor (not in build mode) → building.select()
##       3. Otherwise → deselect + building_placer.try_place_at_mouse()
##   - Click on empty space when something is selected: deselects.
extends Node3D

const HUD_SCENE        := "res://scenes/ui/HUD.tscn"
const BUILD_MENU_SCENE := "res://scenes/ui/BuildMenu.tscn"

@onready var grid_system:               GridSystem             = $Systems/GridSystem
@onready var economy_system:            EconomySystem          = $Systems/EconomySystem
@onready var population_system:         PopulationSystem       = $Systems/PopulationSystem
@onready var event_system:              EventSystem            = $Systems/EventSystem
@onready var citizen_manager:           CitizenManager         = $Systems/CitizenManager
@onready var wheat_field_registry:      WheatFieldRegistry     = $Systems/WheatFieldRegistry
@onready var resource_object_registry:  ResourceObjectRegistry = $Systems/ResourceObjectRegistry
@onready var building_placer:           BuildingPlacer         = $BuildingPlacer
@onready var camera:                    CameraController       = $CameraController

var _hovered_citizen:   Citizen  = null
var _selected_citizen:  Citizen  = null
var _selected_building: Building = null

func _ready() -> void:
	_register_systems()
	_load_ui()
	EventBus.emit_signal("game_started")
	EventBus.citizen_died.connect(_on_citizen_died_world)

func _register_systems() -> void:
	pass

func _load_ui() -> void:
	_add_ui_scene(HUD_SCENE)
	_add_ui_scene(BUILD_MENU_SCENE)

func _add_ui_scene(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("GameWorld: Could not load UI scene: " + path)
		return
	add_child(scene.instantiate())

# ─── Per-frame hover detection ────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _is_mouse_over_ui():
		_clear_hover()
		return
	var citizen: Citizen = _raycast_citizen()
	if citizen != _hovered_citizen:
		_hovered_citizen = citizen
		if citizen != null:
			EventBus.emit_signal("citizen_hovered", citizen)
		else:
			EventBus.emit_signal("citizen_unhovered")

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if _is_mouse_over_ui():
		return

	# Priority 1: citizen under cursor.
	var citizen: Citizen = _raycast_citizen()
	if citizen != null:
		_deselect_building()
		_select_citizen(citizen)
		return

	# Priority 2: building under cursor (only when not in build mode).
	if not building_placer._active:
		var building: Building = _raycast_building()
		if building != null:
			_deselect_citizen()
			_select_building(building)
			return

	# Priority 3: deselect everything, then try to place building.
	_deselect_citizen()
	_deselect_building()
	building_placer.try_place_at_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		GameManager.pause(not GameManager.is_paused)

# ─── Citizen selection ────────────────────────────────────────────────────────
func _select_citizen(citizen: Citizen) -> void:
	_selected_citizen = citizen
	EventBus.emit_signal("citizen_selected", citizen)
	if camera != null:
		camera.follow(citizen)

func _deselect_citizen() -> void:
	if _selected_citizen == null:
		return
	_selected_citizen = null
	EventBus.emit_signal("citizen_deselected")
	if camera != null:
		camera.release_follow()

# ─── Building selection ───────────────────────────────────────────────────────
func _select_building(building: Building) -> void:
	if _selected_building != null and _selected_building != building:
		_selected_building.deselect()
	_selected_building = building
	building.select()

func _deselect_building() -> void:
	if _selected_building == null:
		return
	_selected_building.deselect()
	_selected_building = null

func _on_citizen_died_world(citizen: Object, _cause: String) -> void:
	if citizen == _hovered_citizen:
		_hovered_citizen = null
		EventBus.emit_signal("citizen_unhovered")
	if citizen == _selected_citizen:
		_selected_citizen = null
		EventBus.emit_signal("citizen_deselected")
		if camera != null:
			camera.release_follow()

func _clear_hover() -> void:
	if _hovered_citizen != null:
		_hovered_citizen = null
		EventBus.emit_signal("citizen_unhovered")

# ─── Raycasts ─────────────────────────────────────────────────────────────────
func _raycast_citizen() -> Citizen:
	var result: Dictionary = _raycast_world()
	if result.is_empty():
		return null
	var node: Node = result.get("collider", null)
	while node != null:
		if node is Citizen:
			return node as Citizen
		node = node.get_parent()
	return null

## Returns the Building at the grid cell under the mouse using the ground plane.
## No physics shape needed on the building — just intersect y=0.
func _raycast_building() -> Building:
	var cam: Camera3D = _get_camera3d()
	if cam == null:
		return null
	var mouse_pos: Vector2  = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_dir: Vector3    = cam.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return null
	var t: float           = -ray_origin.y / ray_dir.y
	var world_pos: Vector3 = ray_origin + ray_dir * t
	var cell: Vector2i     = grid_system.world_to_cell(world_pos)
	return grid_system.get_building_at(cell)

func _raycast_world() -> Dictionary:
	var cam: Camera3D = _get_camera3d()
	if cam == null:
		return {}
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin:    Vector3 = cam.project_ray_origin(mouse_pos)
	var direction: Vector3 = cam.project_ray_normal(mouse_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * 1000.0
	)
	query.collide_with_areas  = true
	query.collide_with_bodies = true
	return space.intersect_ray(query)

func _get_camera3d() -> Camera3D:
	if camera == null:
		return null
	for child in camera.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null

# ─── UI overlap ───────────────────────────────────────────────────────────────
func _is_mouse_over_ui() -> bool:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for node in get_tree().get_nodes_in_group("ui_panels"):
		if node is Control and node.is_visible_in_tree():
			if node.get_global_rect().has_point(mouse_pos):
				return true
	return false
