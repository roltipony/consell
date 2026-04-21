## Citizen.gd
## Base class for all citizen types.
## Owns visuals, movement primitives, and drives a BehaviorTree each frame.
##
## Lifecycle (enforced by CitizenManager):
##   1. add_child(citizen)       → _ready(): visuals + base context
##   2. citizen.initialize(...)  → home_cell, speeds, colors
##   3. citizen.setup_size(...)  → visual scale
##   4. citizen.start()          → builds the BT (needs home_cell to be set)
##
## Job assignment:
##   Citizens spawn as "generic" (no job, default color).
##   When work time begins and no work_cell is assigned, the citizen
##   queries GridSystem for the nearest work station whose building id
##   matches an entry in assignable_job_ids (from game_settings.json).
##   Each job id declares its own color via citizen_job_colors in config.
class_name Citizen
extends Node3D

# ─── Fallback color before any job is assigned ────────────────────────────────
const _DEFAULT_COLOR := Color(0.91, 0.753, 0.565)   # "#e8c090"

# ─── Identity ─────────────────────────────────────────────────────────────────
var home_cell: Vector2i  = Vector2i.ZERO
var citizen_type: String = "generic"

## Building ids this citizen can be assigned to work at.
## Loaded from game_settings.json["citizen_job_types"][citizen_type].
var assignable_job_ids: Array[String] = []

## Color per building id, loaded from game_settings.json["citizen_job_colors"].
var _job_colors: Dictionary = {}

## Cell of the assigned work station. Vector2i(-1,-1) means unassigned.
var work_cell: Vector2i = Vector2i(-1, -1)

# ─── Blackboard ───────────────────────────────────────────────────────────────
var _ctx: Dictionary = {}

# ─── Behavior Tree ────────────────────────────────────────────────────────────
var _bt_root: BTNode = null

# ─── Movement config ──────────────────────────────────────────────────────────
var _move_speed: float    = 1.5
var _wander_radius: float = 3.0
var _wait_timer: float    = 0.0
var _wait_duration: float = 2.0

# ─── Visual ───────────────────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _color: Color = _DEFAULT_COLOR

# ─── Movement state ───────────────────────────────────────────────────────────
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_visuals()
	EventBus.hour_changed.connect(_on_hour_changed)

## Called by CitizenManager after initialize() and setup_size().
func start() -> void:
	_load_config()
	_init_base_context()
	_bt_root = _build_behavior_tree()

func _process(delta: float) -> void:
	if _bt_root == null:
		return
	_update_context()
	_bt_root.tick(_ctx)
	_tick_movement(delta)

# ─── Config loading ───────────────────────────────────────────────────────────
## Reads citizen_job_types and citizen_job_colors from game_settings.json.
## No values are hardcoded here; all data lives in config.
func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings

	# {"wheat_field": "#d4a820", "market": "#22aadd", ...}
	var colors_cfg: Dictionary = cfg.get("citizen_job_colors", {})
	for job_id in colors_cfg:
		_job_colors[job_id] = Color(colors_cfg[job_id])

	# {"generic": ["wheat_field", "farm"], "merchant": ["market", "tavern"], ...}
	var job_types_cfg: Dictionary = cfg.get("citizen_job_types", {})
	var ids = job_types_cfg.get(citizen_type, job_types_cfg.get("generic", []))
	assignable_job_ids.clear()
	for id in ids:
		assignable_job_ids.append(str(id))

# ─── Subclass interface ───────────────────────────────────────────────────────
## Override in subclasses to supply a custom BT.
func _build_behavior_tree() -> BTNode:
	return _build_default_tree()

## Alias kept for subclass compatibility (FarmerCitizen and any other subclass
## that overrides the old name still compiles without changes).
func _build_wander_tree() -> BTNode:
	return _build_default_tree()

## Override in subclasses to push additional data into _ctx each frame.
func _update_context() -> void:
	pass

# ─── Context ──────────────────────────────────────────────────────────────────
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
		"has_work":     false,
	}

func _on_hour_changed(hour: int) -> void:
	var was_work := bool(_ctx.get("is_work_time", false))
	_ctx["is_work_time"] = (hour >= _ctx["work_start"] and hour < _ctx["work_end"])
	# First moment work starts: attempt job assignment if still unassigned
	if _ctx["is_work_time"] and not was_work and not _ctx["has_work"]:
		_try_assign_nearest_work()

# ─── Initialise (called by CitizenManager) ────────────────────────────────────
func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	home_cell      = cell
	_move_speed    = cfg.get("move_speed",    1.5)
	_wander_radius = cfg.get("wander_radius", 3.0)
	_wait_duration = cfg.get("wait_duration", 2.0)
	# Always start with the default unassigned color; job assignment changes it
	_color = _DEFAULT_COLOR

func setup_size(building_cell_size: float) -> void:
	var s: float = building_cell_size * 0.25
	if _mesh_instance:
		_mesh_instance.scale = Vector3(s, s * 1.5, s)

# ─── Visuals ──────────────────────────────────────────────────────────────────
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

# ─── Job assignment ───────────────────────────────────────────────────────────
## Scans all placed buildings for the nearest one whose id is in
## assignable_job_ids. Assigns it and updates the citizen's color.
func _try_assign_nearest_work() -> void:
	if assignable_job_ids.is_empty():
		return

	var gs: GridSystem          = GameManager.grid_system
	var nearest_cell            := Vector2i(-1, -1)
	var nearest_dist            := INF
	var assigned_id             := ""

	for bld_cell in gs.buildings:
		var bld: Building = gs.buildings[bld_cell]
		if bld == null or bld.data == null:
			continue
		if not (bld.data.id in assignable_job_ids):
			continue
		var dist: float = float((bld_cell - home_cell).length())
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_cell = bld_cell
			assigned_id  = bld.data.id

	if nearest_cell == Vector2i(-1, -1):
		return  # No matching station placed yet

	work_cell             = nearest_cell
	_ctx["has_work"]      = true
	_ctx["work_cell"]     = work_cell

	# Color comes from config; fallback to default if not listed
	set_color(_job_colors.get(assigned_id, _DEFAULT_COLOR))

	EventBus.emit_signal("citizen_assigned_job", self, work_cell, assigned_id)

# ─── Default Behavior Tree ────────────────────────────────────────────────────
## Selector
##   ├─ Sequence [work branch]     → guard: is_work_time AND has_work
##   │    └─ Action: walk to work_cell and stay
##   ├─ Sequence [seek work]       → guard: is_work_time AND NOT has_work
##   │    └─ Action: wander near home (job search fires via hour_changed)
##   └─ Action  [rest branch]      → wander near home
func _build_default_tree() -> BTNode:
	# BTSequence and BTSelector have no _init() — use add_child() builder pattern
	var work_branch := BTSequence.new()
	work_branch.add_child(BTCondition.new(_cond_should_work))
	work_branch.add_child(BTAction.new(_work_action))

	var seek_branch := BTSequence.new()
	seek_branch.add_child(BTCondition.new(_cond_work_time_no_job))
	seek_branch.add_child(BTAction.new(_wander_action))

	var root := BTSelector.new()
	root.add_child(work_branch)
	root.add_child(seek_branch)
	root.add_child(BTAction.new(_wander_action))
	return root

# ─── BT conditions ────────────────────────────────────────────────────────────
func _cond_should_work(c: Dictionary) -> bool:
	return bool(c.get("is_work_time", false)) and bool(c.get("has_work", false))

func _cond_work_time_no_job(c: Dictionary) -> bool:
	return bool(c.get("is_work_time", false)) and not bool(c.get("has_work", false))

# ─── BT actions ───────────────────────────────────────────────────────────────
func _work_action(_c: Dictionary) -> BTNode.Status:
	if _is_moving:
		return BTNode.Status.RUNNING
	var work_world: Vector3 = GameManager.grid_system.cell_to_world(work_cell)
	if global_position.distance_to(work_world) > 0.1:
		move_to(work_world)
	return BTNode.Status.RUNNING

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

# ─── Movement primitives ──────────────────────────────────────────────────────
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
