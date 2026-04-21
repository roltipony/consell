## Citizen.gd
## Base class for all citizen types.
## Owns visuals, movement primitives, and drives a BehaviorTree each frame.
## Subclasses override _build_behavior_tree() and _update_context().
##
## Initialisation order (enforced by CitizenManager):
##   1. add_child(citizen)       → _ready(): visuals + base context
##   2. citizen.initialize(...)  → home_cell, speeds, colors
##   3. citizen.setup_size(...)  → visual scale
##   4. citizen.start()          → builds the BT (needs home_cell to be set)
class_name Citizen
extends Node3D

# ─── Identity ─────────────────────────────────────────────────────
var home_cell: Vector2i = Vector2i.ZERO
var citizen_type: String = "generic"

# ─── Blackboard ───────────────────────────────────────────────────
var _ctx: Dictionary = {}

# ─── Behavior Tree ────────────────────────────────────────────────
var _bt_root: BTNode = null

# ─── Movement config ──────────────────────────────────────────────
var _move_speed: float = 1.5
var _wander_radius: float = 3.0
var _wait_timer: float = 0.0
var _wait_duration: float = 2.0

# ─── Visual ───────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _color: Color = Color.WHITE

# ─── Movement state ───────────────────────────────────────────────
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	_setup_visuals()
	EventBus.hour_changed.connect(_on_hour_changed)

## Called by CitizenManager after initialize() and setup_size().
## Builds context and BT now that home_cell and config are set.
func start() -> void:
	_init_base_context()
	_bt_root = _build_behavior_tree()

func _process(delta: float) -> void:
	if _bt_root == null:
		return
	_update_context()
	_bt_root.tick(_ctx)
	_tick_movement(delta)

# ─── Subclass interface ───────────────────────────────────────────
func _build_behavior_tree() -> BTNode:
	return _build_wander_tree()

func _update_context() -> void:
	pass

# ─── Context ──────────────────────────────────────────────────────
func _init_base_context() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get("day_cycle", {})
	_ctx = {
		"citizen":      self,
		"home_cell":    home_cell,
		"is_work_time": false,
		"is_moving":    false,
		"at_target":    false,
		"work_start":   cfg.get("work_start_hour", 6),
		"work_end":     cfg.get("work_end_hour",   20),
	}

func _on_hour_changed(hour: int) -> void:
	_ctx["is_work_time"] = (hour >= _ctx["work_start"] and hour < _ctx["work_end"])

# ─── Initialise (called by CitizenManager) ────────────────────────
func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	home_cell      = cell
	_move_speed    = cfg.get("move_speed",    1.5)
	_wander_radius = cfg.get("wander_radius", 3.0)
	_wait_duration = cfg.get("wait_duration", 2.0)
	_color         = Color(cfg.get("color",   "#e8c090"))

func setup_size(building_cell_size: float) -> void:
	var s: float = building_cell_size * 0.25
	if _mesh_instance:
		_mesh_instance.scale = Vector3(s, s * 1.5, s)

# ─── Visuals ──────────────────────────────────────────────────────
func _setup_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CitizenMesh"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.75)
	_mesh_instance.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color   = _color
	mat.roughness      = 0.9
	mat.metallic       = 0.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test  = false
	_mesh_instance.material_override = mat
	_mesh_instance.position.y = 0.6
	add_child(_mesh_instance)

func set_color(c: Color) -> void:
	_color = c
	if _mesh_instance and _mesh_instance.material_override:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = c

# ─── Movement primitives ──────────────────────────────────────────
func move_to(target: Vector3) -> void:
	_target_position   = _clamp_to_grid(target)
	_is_moving         = true
	_ctx["at_target"]  = false

func is_moving() -> bool:
	return _is_moving

func _tick_movement(delta: float) -> void:
	if not _is_moving:
		return
	var dir: Vector3 = _target_position - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		global_position   = _target_position
		_is_moving        = false
		_ctx["is_moving"] = false
		_ctx["at_target"] = true
	else:
		global_position  += dir.normalized() * _move_speed * delta
		_ctx["is_moving"] = true

func _clamp_to_grid(pos: Vector3) -> Vector3:
	var gs: GridSystem = GameManager.grid_system
	return Vector3(
		clampf(pos.x, 0.0, float(gs.grid_width)  * gs.cell_size),
		0.0,
		clampf(pos.z, 0.0, float(gs.grid_height) * gs.cell_size)
	)

# ─── Built-in wander tree ─────────────────────────────────────────
func _build_wander_tree() -> BTNode:
	return BTAction.new(_wander_action)

func _wander_action(_c: Dictionary) -> BTNode.Status:
	if _is_moving:
		return BTNode.Status.RUNNING
	_wait_timer += get_process_delta_time()
	if _wait_timer >= _wait_duration:
		_wait_timer    = 0.0
		_wait_duration = randf_range(1.0, 4.0)
		var home_world: Vector3 = GameManager.grid_system.cell_to_world(home_cell)
		var offset := Vector3(
			randf_range(-_wander_radius, _wander_radius),
			0.0,
			randf_range(-_wander_radius, _wander_radius)
		)
		move_to(home_world + offset)
	return BTNode.Status.RUNNING