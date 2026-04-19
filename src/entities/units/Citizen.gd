## Citizen.gd
## A visible person that lives in a house and wanders the map.
## Represented as a 2D rectangle (flat quad) that moves around its home area.
class_name Citizen
extends Node3D

# ─── State ────────────────────────────────────────────────────────
var home_cell: Vector2i = Vector2i.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _move_speed: float = 1.5
var _wander_radius: float = 3.0
var _wait_timer: float = 0.0
var _wait_duration: float = 2.0
var _is_waiting: bool = false

# ─── Visual ───────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _color: Color = Color.WHITE

enum WanderState { MOVING, WAITING }
var _state: WanderState = WanderState.WAITING

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	_setup_visuals()
	_pick_new_target()

func _process(delta: float) -> void:
	match _state:
		WanderState.WAITING:
			_wait_timer += delta
			if _wait_timer >= _wait_duration:
				_wait_timer = 0.0
				_pick_new_target()
				_state = WanderState.MOVING
		WanderState.MOVING:
			_move_toward_target(delta)

# ─── Initialise ───────────────────────────────────────────────────
func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	home_cell = cell
	_move_speed    = cfg.get("move_speed",    1.5)
	_wander_radius = cfg.get("wander_radius", 3.0)
	_wait_duration = cfg.get("wait_duration", 2.0)
	_color         = Color(cfg.get("color",   "#e8c090"))

func setup_size(building_cell_size: float) -> void:
	## Scale the citizen rectangle proportionally to the building footprint.
	var citizen_scale: float = building_cell_size * 0.25
	if _mesh_instance:
		_mesh_instance.scale = Vector3(citizen_scale, citizen_scale * 1.5, citizen_scale)

# ─── Visuals ──────────────────────────────────────────────────────
func _setup_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CitizenMesh"

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.75)
	_mesh_instance.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = false
	_mesh_instance.material_override = mat

	_mesh_instance.position.y = 0.5
	add_child(_mesh_instance)

func set_color(c: Color) -> void:
	_color = c
	if _mesh_instance and _mesh_instance.material_override:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = c

# ─── Movement ─────────────────────────────────────────────────────
func _pick_new_target() -> void:
	var home_world: Vector3 = GameManager.grid_system.cell_to_world(home_cell)
	var offset := Vector3(
		randf_range(-_wander_radius, _wander_radius),
		0.0,
		randf_range(-_wander_radius, _wander_radius)
	)
	_target_position = _clamp_to_grid(home_world + offset)
	_state = WanderState.MOVING

func _move_toward_target(delta: float) -> void:
	var direction: Vector3 = _target_position - global_position
	direction.y = 0.0
	var dist: float = direction.length()

	if dist < 0.05:
		global_position = _target_position
		_wait_duration = randf_range(1.0, 4.0)
		_state = WanderState.WAITING
		return

	global_position += direction.normalized() * _move_speed * delta

func _clamp_to_grid(pos: Vector3) -> Vector3:
	var gs: GridSystem = GameManager.grid_system
	return Vector3(
		clampf(pos.x, 0.0, float(gs.grid_width)  * gs.cell_size),
		0.0,
		clampf(pos.z, 0.0, float(gs.grid_height) * gs.cell_size)
	)
