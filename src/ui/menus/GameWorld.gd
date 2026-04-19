## GameWorld.gd
extends Node3D

const HUD_SCENE        := "res://scenes/ui/HUD.tscn"
const BUILD_MENU_SCENE := "res://scenes/ui/BuildMenu.tscn"

@onready var grid_system:       GridSystem       = $Systems/GridSystem
@onready var economy_system:    EconomySystem    = $Systems/EconomySystem
@onready var population_system: PopulationSystem = $Systems/PopulationSystem
@onready var event_system:      EventSystem      = $Systems/EventSystem
@onready var citizen_manager:   CitizenManager   = $Systems/CitizenManager
@onready var building_placer:   BuildingPlacer   = $BuildingPlacer
@onready var camera:            CameraController = $CameraController

func _ready() -> void:
	_register_systems()
	_load_ui()
	EventBus.emit_signal("game_started")

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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _is_mouse_over_ui():
				building_placer.try_place_at_mouse()

	if event.is_action_pressed("pause_game"):
		if not _is_mouse_over_ui():
			GameManager.pause(not GameManager.is_paused)

func _is_mouse_over_ui() -> bool:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for node in get_tree().get_nodes_in_group("ui_panels"):
		if node is Control and node.is_visible_in_tree():
			if node.get_global_rect().has_point(mouse_pos):
				return true
	return false
