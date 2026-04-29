## Citizen.gd
## Base class for all citizen types.
##
## BT priority (evaluated every frame):
##   1. eat  — PHASE_EAT: walk home, consume food+water, restore hunger+thirst.
##   2. work — PHASE_WORK + assigned job: walk to work cell.
##   3. seek — PHASE_WORK + no job: wander (looking for work).
##   4. rest — any other phase: wander near home.
##
## Food consumption model:
##   Each eat phase the citizen takes food/water from EconomySystem and calls
##   stats.restore_hunger() / stats.restore_thirst(). The amount restored per
##   eat phase equals food_per_citizen_per_day from config (default 1.0 unit).
##   PopulationSystem does NOT deduct food — only citizens do.
class_name Citizen
extends Node3D

const _DEFAULT_COLOR := Color(0.91, 0.753, 0.565)

const PHASE_WORK    := "work"
const PHASE_EAT     := "eat"
const PHASE_LEISURE := "leisure"
const PHASE_SLEEP   := "sleep"

# ─── Identity ─────────────────────────────────────────────────────────────────
var home_cell:       Vector2i   = Vector2i.ZERO
var citizen_type:    String     = "generic"
var is_child:        bool       = false
var forced_gender:   String     = ""
var forced_age:      int        = -1
var partner:         Citizen    = null
var house_occupancy: RefCounted = null

# ─── Stats ────────────────────────────────────────────────────────────────────
var stats: CitizenStats = null

# ─── Job ──────────────────────────────────────────────────────────────────────
var assignable_job_ids: Array[String] = []
var _job_colors: Dictionary = {}
var work_cell: Vector2i = Vector2i(-1, -1)

# ─── Schedule / BT ────────────────────────────────────────────────────────────
var _schedule: CitizenSchedule = null
var _ctx:      Dictionary      = {}
var _bt_root:  BTNode          = null

# ─── Movement ────────────────────────────────────────────────────────────────
var _move_speed:    float = 1.5
var _wander_radius: float = 3.0
var _wait_timer:    float = 0.0
var _wait_duration: float = 2.0

# ─── Visuals ──────────────────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _name_label:    Label3D        = null
var _color: Color = _DEFAULT_COLOR

# ─── Movement state ───────────────────────────────────────────────────────────
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false

# ─── Eat state ────────────────────────────────────────────────────────────────
## How much food/water to consume per eat phase — from config.
var _food_per_eat:  float = 1.0
var _water_per_eat: float = 1.0
## Flags reset each time the eat phase begins.
var _ate_this_phase:   bool = false
var _drank_this_phase: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_visuals()
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.new_day.connect(_on_new_day_stats)
	EventBus.new_year.connect(_on_new_year_stats)

func start() -> void:
	_load_config()
	_init_stats()
	_init_base_context()
	_bt_root = _build_behavior_tree()
	if is_child:
		_apply_child_scale()
	if _name_label != null and stats != null:
		_name_label.text = stats.citizen_name

func _process(delta: float) -> void:
	if _bt_root == null:
		return
	_update_context()
	_bt_root.tick(_ctx)
	_tick_movement(delta)

# ─── Config ───────────────────────────────────────────────────────────────────
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

	var pop_cfg: Dictionary = cfg.get("population", {})
	_food_per_eat  = float(pop_cfg.get("food_per_citizen_per_day",  1.0))
	_water_per_eat = float(pop_cfg.get("water_per_citizen_per_day", 1.0))

# ─── Stats ────────────────────────────────────────────────────────────────────
func _init_stats() -> void:
	stats = CitizenStats.new()
	var stats_cfg: Dictionary = ConfigLoader.game_settings.get("citizen_stats", {})
	stats.initialize(stats_cfg, forced_gender, forced_age)
	_move_speed = stats.speed
	stats.citizen_died.connect(_on_stats_death)

func _on_new_day_stats(_day: int, _month: int, _year: int) -> void:
	if is_queued_for_deletion(): return
	if stats != null:
		stats.tick_day()
		# Children age every day so they grow up quickly (1 day per year of age).
		if is_child:
			stats.tick_day_age(true)
			_check_child_grown_up()

func _on_new_year_stats(_year: int) -> void:
	if is_queued_for_deletion(): return
	if stats != null:
		stats.tick_year()

func _check_child_grown_up() -> void:
	if not is_child or stats == null:
		return
	var growth_age: int = int(ConfigLoader.game_settings
		.get("house_rules", {}).get("child_growth_age", 4))
	if stats.age < growth_age:
		return
	is_child = false
	_apply_adult_scale()
	EventBus.emit_signal("citizen_grew_up", self)
	_try_emancipate()

## When a child becomes an adult, attempt to move to a different house that has
## a free slot. If none is available the citizen stays in the family home.
## The move is handled entirely through HouseOccupancy so all partner/couple
## logic is triggered automatically by add_resident/_try_form_couple.
func _try_emancipate() -> void:
	var pop: PopulationSystem = GameManager.get_system("population")
	if pop == null or pop.house_occupancy == null:
		return
	var occ: HouseOccupancy = pop.house_occupancy
	var current_house: Vector2i = occ.get_house_of(self)
	# Find a residential building with capacity that is NOT the current house.
	var gs: GridSystem = GameManager.grid_system
	if gs == null:
		return
	var visited: Dictionary = {}
	for cell in gs.buildings:
		var bld: Building = gs.buildings[cell]
		if bld == null or bld.data == null or not bld.is_operational:
			continue
		if bld.data.population_capacity <= 0 or cell != bld.cell:
			continue
		if visited.has(cell) or cell == current_house:
			continue
		visited[cell] = true
		if occ.get_occupants(cell).size() < bld.data.population_capacity:
			# Move out of family home, move into the new house.
			occ.remove_resident(self)
			occ.add_resident(self, cell)
			home_cell           = cell
			_ctx["home_cell"]   = cell
			EventBus.notify(
				"%s se ha mudado a una nueva casa" % stats.citizen_name, "info"
			)
			return

func _on_stats_death(cause: String) -> void:
	EventBus.emit_signal("citizen_died", self, cause)
	queue_free()

# ─── Subclass interface ───────────────────────────────────────────────────────
func _build_behavior_tree() -> BTNode:
	return _build_default_tree()

func _update_context() -> void:
	pass

# ─── Context / phase ─────────────────────────────────────────────────────────
func _init_base_context() -> void:
	var day_cfg: Dictionary = ConfigLoader.game_settings.get("day_cycle", {})
	_ctx = {
		"citizen":       self,
		"home_cell":     home_cell,
		"current_phase": CitizenSchedule.PHASE_DEFAULT,
		"is_work_time":  false,
		"is_eat_time":   false,
		"is_moving":     false,
		"at_target":     false,
		"work_start":    day_cfg.get("work_start_hour", 6),
		"work_end":      day_cfg.get("work_end_hour",   20),
		"has_work":      false,
	}
	_apply_phase(GameManager.game_time.hour)

func _on_hour_changed(hour: int) -> void:
	if is_queued_for_deletion(): return
	var prev_phase: String = _ctx.get("current_phase", CitizenSchedule.PHASE_DEFAULT)
	_apply_phase(hour)
	# Reset eat flags at start of each eat phase.
	if _ctx["current_phase"] == PHASE_EAT and prev_phase != PHASE_EAT:
		_ate_this_phase   = false
		_drank_this_phase = false
	if _ctx["current_phase"] == PHASE_WORK and prev_phase != PHASE_WORK \
			and not _ctx["has_work"]:
		_try_assign_nearest_work()

func _apply_phase(hour: int) -> void:
	var prev_phase: String = _ctx.get("current_phase", CitizenSchedule.PHASE_DEFAULT)
	if _schedule != null and _schedule.has_phases():
		_ctx["current_phase"] = _schedule.phase_at(hour)
	else:
		# Default fallback when no schedule is defined for this citizen type.
		var in_work: bool = (hour >= _ctx["work_start"] and hour < _ctx["work_end"])
		_ctx["current_phase"] = PHASE_WORK if in_work else PHASE_SLEEP
	_ctx["is_work_time"] = (_ctx["current_phase"] == PHASE_WORK)
	_ctx["is_eat_time"]  = (_ctx["current_phase"] == PHASE_EAT)
	if _ctx["current_phase"] != prev_phase:
		_on_phase_changed(_ctx["current_phase"])

func _on_phase_changed(_new_phase: String) -> void:
	pass

# ─── Initialize ───────────────────────────────────────────────────────────────
func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	home_cell      = cell
	_move_speed    = cfg.get("move_speed",    1.5)
	_wander_radius = cfg.get("wander_radius", 3.0)
	_wait_duration = cfg.get("wait_duration", 2.0)

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
	mat.albedo_color   = _DEFAULT_COLOR
	mat.roughness      = 0.9
	mat.metallic       = 0.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test  = false
	_mesh_instance.material_override = mat
	_mesh_instance.position.y = 0.6
	add_child(_mesh_instance)

	_name_label = Label3D.new()
	_name_label.name          = "NameLabel"
	_name_label.text          = ""
	_name_label.font_size     = 32
	_name_label.pixel_size    = 0.005
	_name_label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate      = Color.WHITE
	_name_label.position      = Vector3(0.0, 1.2, 0.0)
	add_child(_name_label)

	var area := Area3D.new()
	area.name = "HitArea"
	var col  := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.25
	shape.height = 0.8
	col.shape    = shape
	col.position.y = 0.6
	area.add_child(col)
	add_child(area)

func set_color(c: Color) -> void:
	_color = c
	if _mesh_instance and _mesh_instance.material_override:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = c

func _apply_child_scale() -> void:
	if _mesh_instance == null:
		return
	var f: float = float(ConfigLoader.game_settings
		.get("house_rules", {}).get("child_mesh_scale_factor", 0.55))
	_mesh_instance.scale *= f
	if _name_label != null:
		_name_label.font_size = 22

func _apply_adult_scale() -> void:
	if _mesh_instance == null:
		return
	var f: float = float(ConfigLoader.game_settings
		.get("house_rules", {}).get("child_mesh_scale_factor", 0.55))
	_mesh_instance.scale /= f
	if _name_label != null:
		_name_label.font_size = 32

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
	work_cell         = nearest_cell
	_ctx["has_work"]  = true
	_ctx["work_cell"] = work_cell
	set_color(_job_colors.get(assigned_id, _DEFAULT_COLOR))
	EventBus.emit_signal("citizen_assigned_job", self, work_cell, assigned_id)

# ─── Default Behavior Tree ────────────────────────────────────────────────────
func _build_default_tree() -> BTNode:
	# Eat branch
	var eat_seq := BTSequence.new()
	eat_seq.add_child(BTCondition.new(_cond_is_eat_time))
	eat_seq.add_child(BTAction.new(_eat_action))

	# Work branch
	var work_seq := BTSequence.new()
	work_seq.add_child(BTCondition.new(_cond_should_work))
	work_seq.add_child(BTAction.new(_work_action))

	# Seek-work branch
	var seek_seq := BTSequence.new()
	seek_seq.add_child(BTCondition.new(_cond_work_time_no_job))
	seek_seq.add_child(BTAction.new(_wander_action))

	var root := BTSelector.new()
	root.add_child(eat_seq)
	root.add_child(work_seq)
	root.add_child(seek_seq)
	root.add_child(BTAction.new(_wander_action))
	return root

# ─── BT conditions ────────────────────────────────────────────────────────────
func _cond_is_eat_time(c: Dictionary) -> bool:
	return bool(c.get("is_eat_time", false))

func _cond_should_work(c: Dictionary) -> bool:
	return bool(c.get("is_work_time", false)) and bool(c.get("has_work", false))

func _cond_work_time_no_job(c: Dictionary) -> bool:
	return bool(c.get("is_work_time", false)) and not bool(c.get("has_work", false))

# ─── BT actions ───────────────────────────────────────────────────────────────

## Walk home, then take food/water from EconomySystem and restore stats.
## Eats once per eat phase (_ate/_drank flags reset each phase start).
func _eat_action(_c: Dictionary) -> BTNode.Status:
	var home_world: Vector3 = GameManager.grid_system.cell_to_world(home_cell)
	if global_position.distance_to(home_world) > 0.5:
		if not _is_moving:
			move_to(home_world)
		return BTNode.Status.RUNNING

	var eco: EconomySystem = GameManager.get_system("economy")
	if eco == null:
		return BTNode.Status.FAILURE

	if not _ate_this_phase:
		var available: float = eco.get_resource("food")
		if available > 0.0:
			var amount: float = minf(_food_per_eat, available)
			eco.add_resource("food", -amount)
			if stats != null:
				stats.restore_hunger(amount * stats.max_hunger)
		_ate_this_phase = true

	if not _drank_this_phase:
		var available: float = eco.get_resource("water")
		if available > 0.0:
			var amount: float = minf(_water_per_eat, available)
			eco.add_resource("water", -amount)
			if stats != null:
				stats.restore_thirst(amount * stats.max_thirst)
		_drank_this_phase = true

	return BTNode.Status.SUCCESS

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
		move_to(home_world + Vector3(
			randf_range(-_wander_radius, _wander_radius),
			0.0,
			randf_range(-_wander_radius, _wander_radius)
		))
	return BTNode.Status.RUNNING

# ─── Movement ────────────────────────────────────────────────────────────────
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
