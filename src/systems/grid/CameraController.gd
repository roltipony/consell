## CameraController.gd
## Smooth panning and zoom for the city camera.
class_name CameraController
extends Camera2D

const CFG_KEY := "camera"

var move_speed:  float = 400.0
var zoom_speed:  float = 0.1
var zoom_min:    float = 0.3
var zoom_max:    float = 3.0
var edge_scroll: bool  = true
var edge_margin: int   = 20

func _ready() -> void:
	_load_config()
	# Start camera centered on the map
	_center_on_map()

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	move_speed  = cfg.get("move_speed",  move_speed)
	zoom_speed  = cfg.get("zoom_speed",  zoom_speed)
	zoom_min    = cfg.get("zoom_min",    zoom_min)
	zoom_max    = cfg.get("zoom_max",    zoom_max)
	edge_scroll = cfg.get("edge_scroll", edge_scroll)
	edge_margin = cfg.get("edge_margin", edge_margin)

func _center_on_map() -> void:
	var grid_cfg: Dictionary = ConfigLoader.game_settings.get("grid", {})
	var w: int = grid_cfg.get("width",  64)
	var h: int = grid_cfg.get("height", 64)
	var cs: Array = grid_cfg.get("cell_size", [16, 16])
	# Place camera at the center of the tile grid
	position = Vector2(w * int(cs[0]) / 2.0, h * int(cs[1]) / 2.0)
	print("CameraController: centered at %s" % str(position))

func _process(delta: float) -> void:
	_handle_movement(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_zoom(-zoom_speed)
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom(zoom_speed)

func _handle_movement(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("camera_move_up"):    dir.y -= 1.0
	if Input.is_action_pressed("camera_move_down"):  dir.y += 1.0
	if Input.is_action_pressed("camera_move_left"):  dir.x -= 1.0
	if Input.is_action_pressed("camera_move_right"): dir.x += 1.0

	if edge_scroll:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var vsize: Vector2 = get_viewport_rect().size
		if mouse.x < edge_margin:            dir.x -= 1.0
		if mouse.x > vsize.x - edge_margin:  dir.x += 1.0
		if mouse.y < edge_margin:            dir.y -= 1.0
		if mouse.y > vsize.y - edge_margin:  dir.y += 1.0

	if dir != Vector2.ZERO:
		position += dir.normalized() * move_speed * delta / zoom.x

func _zoom(delta: float) -> void:
	var new_zoom: float = clampf(zoom.x - delta, zoom_min, zoom_max)
	zoom = Vector2(new_zoom, new_zoom)