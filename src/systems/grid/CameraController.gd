## CameraController.gd
## Isometric 3D camera with smooth panning, zoom, and optional citizen follow mode.
##
## Follow mode:
##   Set follow_target to a Node3D to lock the pivot onto it each frame.
##   Any manual pan input (keyboard or edge scroll) cancels follow mode
##   so the player never feels locked in.
class_name CameraController
extends Node3D

const CFG_KEY := "camera"

var move_speed: float  = 20.0
var zoom_speed: float  = 3.0
var zoom_min: float    = 8.0
var zoom_max: float    = 60.0
var edge_scroll: bool  = true
var edge_margin: int   = 20

var _current_distance: float = 30.0
var _pivot: Vector3 = Vector3.ZERO
var _camera: Camera3D

## When set, the camera pivot tracks this node's world position each frame.
## Cleared automatically when the player pans manually.
var follow_target: Node3D = null

# Ángulos isométricos fijos (true isometric)
const ISO_ANGLE_Y: float = 45.0
const ISO_ANGLE_X: float = 35.264

func _ready() -> void:
	_load_config()
	_camera = Camera3D.new()
	_camera.fov = ConfigLoader.game_settings.get(CFG_KEY, {}).get("fov", 45)
	add_child(_camera)
	center_on_grid()
	GameManager.register_system("camera", self)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	move_speed        = cfg.get("move_speed",  move_speed)
	zoom_speed        = cfg.get("zoom_speed",  zoom_speed)
	zoom_min          = cfg.get("zoom_min",    zoom_min)
	zoom_max          = cfg.get("zoom_max",    zoom_max)
	edge_scroll       = cfg.get("edge_scroll", edge_scroll)
	edge_margin       = cfg.get("edge_margin", edge_margin)
	_current_distance = cfg.get("distance",    _current_distance)

func center_on_grid() -> void:
	var grid_cfg: Dictionary = ConfigLoader.game_settings.get("grid", {})
	var w: int   = grid_cfg.get("width",  20)
	var h: int   = grid_cfg.get("height", 20)
	var raw      = grid_cfg.get("cell_size", 2.0)
	var cs: float
	if raw is Array:
		cs = float(raw[0]) / 32.0
	else:
		cs = float(raw)
	_pivot = Vector3(w * cs * 0.5, 0.0, h * cs * 0.5)
	_apply_transform()

func _apply_transform() -> void:
	var ay := deg_to_rad(ISO_ANGLE_Y)
	var ax := deg_to_rad(ISO_ANGLE_X)
	var offset := Vector3(
		-_current_distance * sin(ay),
		 _current_distance * sin(ax),
		-_current_distance * cos(ay)
	)
	global_position = _pivot + offset
	look_at(_pivot, Vector3.UP)

func _process(delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		_pivot = Vector3(follow_target.global_position.x, 0.0,
			follow_target.global_position.z)
		_apply_transform()
	else:
		_handle_movement(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_change_zoom(-zoom_speed)
	elif event.is_action_pressed("camera_zoom_out"):
		_change_zoom(zoom_speed)

func _handle_movement(delta: float) -> void:
	var dir := Vector2.ZERO

	if Input.is_action_pressed("camera_move_up"):    dir.y -= 1.0
	if Input.is_action_pressed("camera_move_down"):  dir.y += 1.0
	if Input.is_action_pressed("camera_move_left"):  dir.x -= 1.0
	if Input.is_action_pressed("camera_move_right"): dir.x += 1.0

	if edge_scroll:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var vsize: Vector2 = get_viewport().get_visible_rect().size
		if mouse.x < edge_margin:            dir.x -= 1.0
		if mouse.x > vsize.x - edge_margin:  dir.x += 1.0
		if mouse.y < edge_margin:            dir.y -= 1.0
		if mouse.y > vsize.y - edge_margin:  dir.y += 1.0

	if dir != Vector2.ZERO:
		# Any manual pan cancels follow mode.
		follow_target = null
		dir = dir.normalized()
		var ay := deg_to_rad(ISO_ANGLE_Y)
		var forward := Vector3(-sin(ay), 0.0, -cos(ay))
		var right   := Vector3( cos(ay), 0.0, -sin(ay))
		_pivot += (right * dir.x + forward * dir.y) * move_speed * delta
		_apply_transform()

func _change_zoom(delta: float) -> void:
	_current_distance = clampf(_current_distance + delta, zoom_min, zoom_max)
	_apply_transform()

## Locks the camera pivot onto a Node3D target.
func follow(target: Node3D) -> void:
	follow_target = target

## Releases follow mode without moving the pivot.
func release_follow() -> void:
	follow_target = null
