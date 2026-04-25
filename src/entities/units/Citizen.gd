## Citizen.gd
## Base class for all citizen types.
## Owns visuals, movement primitives, and drives a BehaviorTree each frame.
##
## Lifecycle (enforced by CitizenManager):
##   1. add_child(citizen)       → _ready(): visuals + base context
##   2. citizen.initialize(...)  → home_cell, speeds, colors
##   3. citizen.setup_size(...)  → visual scale
##   4. citizen.start()          → builds stats + BT (needs home_cell to be set)
##
## Schedule:
##   Each citizen type has a CitizenSchedule loaded from
##   game_settings.json["citizen_schedules"][citizen_type].
##   Every hour the schedule is queried and "current_phase" is written to the
##   blackboard. "is_work_time" remains available as a convenience alias
##   (true when current_phase == "work"), so existing BT branches keep working
##   without changes.
##
## Job assignment:
##   Citizens spawn as "generic" (no job, default color).
##   When work time begins and no work_cell is assigned, the citizen
##   queries GridSystem for the nearest work station whose building id
##   matches an entry in assignable_job_ids (from game_settings.json).
##   Each job id declares its own color via citizen_job_colors in config.
##
## Stats:
##   Each citizen owns a CitizenStats instance created in start().
##   stats.speed overrides the config-base _move_speed so every citizen
##   has a unique walking pace. Hunger/thirst decay and age increments are
##   ticked via EventBus.new_day / new_year. Death triggers queue_free().
class_name Citizen
extends Node3D

# ─── Fallback color before any job is assigned ────────────────────────────────
const _DEFAULT_COLOR := Color(0.91, 0.753, 0.565)   # "#e8c090"

# ─── Phase constants (used as keys; actual values come from config) ───────────
const PHASE_WORK    := "work"
const PHASE_EAT     := "eat"
const PHASE_LEISURE := "leisure"
const PHASE_SLEEP   := "sleep"

# ─── Identity ─────────────────────────────────────────────────────────────────
var home_cell: Vector2i  = Vector2i.ZERO
var citizen_type: String = "generic"

# ─── Personal statistics ───────────────────────────────────────────────────────
## All per-citizen stats (health, hunger, thirst, speed, gender …).
## Created in start() so ConfigLoader is ready before initialization.
var stats: CitizenStats = null

## Building ids this citizen can be assigned to work at.
## Loaded from game_settings.json["citizen_job_types"][citizen_type].
var assignable_job_ids: Array[String] = []

## Color per building id, loaded from game_settings.json["citizen_job_colors"].
var _job_colors: Dictionary = {}

## Cell of the assigned work station. Vector2i(-1,-1) means unassigned.
var work_cell: Vector2i = Vector2i(-1, -1)

## Schedule that resolves the active phase for any given hour.
var _schedule: CitizenSchedule = null

# ─── Blackboard ───────────────────────────────────────────────────────────────
var _ctx: Dictionary = {}

# ─── Behavior Tree ────────────────────────────────────────────────────────────
var _bt_root: BTNode = null

# ─── Movement config ──────────────────────────────────────────────────────────
## Set from config in initialize(); overridden by stats.speed in _init_stats().
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
	EventBus.new_day.connect(_on_new_day_stats)
	EventBus.new_year.connect(_on_new_year_stats)

## Called by CitizenManager after initialize() and setup_size().
func start() -> void:
	_load_config()
	_init_stats()
	_init_base_context()
	_bt_root = _build_behavior_tree()

func _process(delta: float) -> void:
	if _bt_root == null:
		return
	_update_context()
	_bt_root.tick(_ctx)
	_tick_movement(delta)

# ─── Config loading ───────────────────────────────────────────────────────────
## Reads citizen_job_types, citizen_job_colors, and citizen_schedules from
## game_settings.json. No values are hardcoded here; all data lives in config.
func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings

	var colors_cfg: Dictionary = cfg.get("citizen_job_colors", {})
	for job_id in colors_cfg:
		_job_colors[job_id] = Color(colors_cfg[job_id])

	var job_types_cfg: Dictionary = cfg.get("citizen_job_types", {})
	var ids = job_types_cfg.get(citizen_type, job_types_cfg.get("generic", []))
	assignable_job_ids.clear()
	for id in ids:
		assignable_job_ids.append(str(id))

	_schedule = CitizenSchedule.new()
	_schedule.load_from_config(citizen_type)

# ─── Stats initialization ────────────────────────────────────────────────────
## Creates the personal CitizenStats instance and wires up the death signal.
## Must be called after _load_config() so ConfigLoader is fully set up.
func _init_stats() -> void:
	stats = CitizenStats.new()
	var stats_cfg: Dictionary = ConfigLoader.game_settings.get("citizen_stats", {})
	stats.initialize(stats_cfg)
	# Personal speed overrides the config base — each citizen walks at a unique pace.
	_move_speed = stats.speed
	stats.citizen_died.connect(_on_stats_death)

# ─── Stat tick handlers ───────────────────────────────────────────────────────
## Driven by EventBus.new_day: hunger/thirst decay + health drain when empty.
func _on_new_day_stats(_day: int, _month: int, _year: int) -> void:
	if stats != null:
		stats.tick_day()

## Driven by EventBus.new_year: age increment and max-age death check.
func _on_new_year_stats(_year: int) -> void:
	if stats != null:
		stats.tick_year()

## Triggered by CitizenStats.citizen_died when health or age reach their limit.
## Broadcasts to the global bus so CitizenManager can handle despawn bookkeeping.
func _on_stats_death(cause: String) -> void:
	EventBus.emit_signal("citizen_died", self, cause)
	queue_free()

# ─── Subclass interface ───────────────────────────────────────────────────────
## Override in subclasses to supply a custom BT.
func _build_behavior_tree() -> BTNode:
	return _build_default_tree()

## Alias kept for subclass compatibility.
func _build_wander_tree() -> BTNode:
	return _build_default_tree()

## Override in subclasses to push additional data into _ctx each frame.
func _update_context() -> void:
	pass

# ─── Context ──────────────────────────────────────────────────────────────────
func _init_base_context() -> void:
	var day_cfg: Dictionary = ConfigLoader.game_settings.get("day_cycle", {})
	_ctx = {
		"citizen":        self,
		"home_cell":      home_cell,
		"current_phase":  CitizenSchedule.PHASE_DEFAULT,
		"is_work_time":   false,
		"is_moving":      false,
		"at_target":      false,
		"work_start":     day_cfg.get("work_start_hour", 6),
		"work_end":       day_cfg.get("work_end_hour",   20),
		"has_work":       false,
	}
	_apply_phase(GameManager.game_time.hour)

func _on_hour_changed(hour: int) -> void:
	var prev_phase: String = _ctx.get("current_phase", CitizenSchedule.PHASE_DEFAULT)
	_apply_phase(hour)
	if _ctx["current_phase"] == PHASE_WORK and prev_phase != PHASE_WORK \
			and not _ctx["has_work"]:
		_try_assign_nearest_work()

func _apply_phase(hour: int) -> void:
	var prev_phase: String = _ctx.get("current_phase", CitizenSchedule.PHASE_DEFAULT)

	if _schedule != null and _schedule.has_phases():
		_ctx["current_phase"] = _schedule.phase_at(hour)
	else:
		var in_work: bool = (hour >= _ctx["work_start"] and hour < _ctx["work_end"])
		_ctx["current_phase"] = PHASE_WORK if in_work else PHASE_SLEEP

	_ctx["is_work_time"] = (_ctx["current_phase"] == PHASE_WORK)

	if _ctx["current_phase"] != prev_phase:
		_on_phase_changed(_ctx["current_phase"])

## Override in subclasses to react to a phase transition.
func _on_phase_changed(_new_phase: String) -> void:
	pass

# ─── Initialize (called by CitizenManager) ───────────────────────────────────
func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	home_cell      = cell
	# Fallback values; _init_stats() overrides _move_speed with stats.speed.
	_move_speed    = cfg.get("move_speed",    1.5)
	_wander_radius = cfg.get("wander_radius", 3.0)
	_wait_duration = cfg.get("wait_duration", 2.0)
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

	# Area3D so raycasts (hover / click) can hit this citizen.
	# The shape is a small capsule centred at roughly head height.
	var area := Area3D.new()
	area.name = "HitArea"
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.25
	shape.height = 0.8
	col.shape = shape
	col.position.y = 0.6
	area.add_child(col)
	add_child(area)

func set_color(c: Color) -> void:
	_color = c
	if _mesh_instance and _mesh_instance.material_override:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = c

# ─── Job assignment ───────────────────────────────────────────────────────────
func _try_assign_nearest_work() -> void:
	if assignable_job_ids.is_empty():
		return

	var gs: GridSystem = GameManager.grid_system
	var nearest_cell   := Vector2i(-1, -1)
	var nearest_dist   := INF
	var assigned_id    := ""

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
		return

	work_cell          = nearest_cell
	_ctx["has_work"]   = true
	_ctx["work_cell"]  = work_cell
	set_color(_job_colors.get(assigned_id, _DEFAULT_COLOR))
	EventBus.emit_signal("citizen_assigned_job", self, work_cell, assigned_id)

# ─── Default Behavior Tree ────────────────────────────────────────────────────
## Selector
##   ├─ Sequence [work branch]  → guard: is_work_time AND has_work → walk to work
##   ├─ Sequence [seek work]    → guard: is_work_time AND NOT has_work → wander
##   └─ Action   [rest branch]  → wander near home
func _build_default_tree() -> BTNode:
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
	_target_position  = _clamp_to_grid(target)
	_is_moving        = true
	_ctx["at_target"] = false

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
