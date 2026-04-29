## LumberjackCitizen.gd
## Citizen type: lumberjack. Works at a Sawmill building and travels to
## nearby trees to chop them, yielding wood.
##
## ALL behaviour is expressed in the Behavior Tree.
##
## BT Tree:
##   Selector (reactive — re-evaluates every tick)
##   ├── Sequence [sleep]
##   │   ├── Condition : phase_is("sleep")
##   │   └── Selector  : is_at_home OR walk_home
##   ├── Sequence [work]
##   │   ├── Condition : phase_is("work")
##   │   ├── Condition : has_target_tree
##   │   └── Selector
##   │       ├── Condition : is_harvesting  (at tree, chopping)
##   │       └── Action    : walk_to_tree
##   ├── Sequence [eat]
##   │   ├── Condition : phase_is("eat")
##   │   ├── Selector  : is_at_home OR walk_home
##   │   └── Action    : eat
##   ├── Sequence [leisure]
##   │   ├── Condition : phase_is("leisure")
##   │   └── Action    : wander
##   └── Action : wander  (safety fallback)
class_name LumberjackCitizen
extends Citizen

# ─── Blackboard keys ──────────────────────────────────────────────────────────
const CTX_HAS_TARGET      := "has_target"
const CTX_IS_HARVESTING   := "is_harvesting"
const CTX_IS_AT_HOME      := "is_at_home"
const CTX_GOING_TO_TARGET := "going_to_target"
const CTX_GOING_HOME      := "going_home"

# ─── Target tracking ──────────────────────────────────────────────────────────
var assigned_target_cell: Vector2i = Vector2i(-1, -1)

var _phase_colors: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	citizen_type = "lumberjack"
	super._ready()
	EventBus.new_day.connect(_on_new_day)

func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	super.initialize(cell, cfg)
	_load_phase_colors(cfg)

func _load_phase_colors(cfg: Dictionary) -> void:
	var fallback: String = cfg.get("lumberjack_work_color", "#6aad2e")
	var phase_colors_cfg: Dictionary = \
		ConfigLoader.game_settings.get("citizen_phase_colors", {}).get(citizen_type, {})
	for phase_id in [PHASE_WORK, PHASE_EAT, PHASE_LEISURE, PHASE_SLEEP]:
		_phase_colors[phase_id] = Color(phase_colors_cfg.get(phase_id, fallback))

# ─── Phase change ─────────────────────────────────────────────────────────────
func _on_phase_changed(new_phase: String) -> void:
	if is_queued_for_deletion(): return
	_ctx[CTX_GOING_TO_TARGET] = false
	_ctx[CTX_GOING_HOME]      = false
	_ctx[CTX_IS_HARVESTING]   = false
	_ctx[CTX_IS_AT_HOME]      = false
	if _phase_colors.has(new_phase):
		set_color(_phase_colors[new_phase])

# ─── Context update ───────────────────────────────────────────────────────────
func _update_context() -> void:
	_ctx[CTX_HAS_TARGET] = has_target()
	if not _ctx.has(CTX_IS_HARVESTING):     _ctx[CTX_IS_HARVESTING]   = false
	if not _ctx.has(CTX_IS_AT_HOME):        _ctx[CTX_IS_AT_HOME]      = false
	if not _ctx.has(CTX_GOING_TO_TARGET):   _ctx[CTX_GOING_TO_TARGET] = false
	if not _ctx.has(CTX_GOING_HOME):        _ctx[CTX_GOING_HOME]      = false

# ─── Behavior Tree ────────────────────────────────────────────────────────────
func _build_behavior_tree() -> BTNode:
	var root := BTSelector.new()
	root.add_child(_build_sleep_branch())
	root.add_child(_build_work_branch())
	root.add_child(_build_eat_branch())
	root.add_child(_build_leisure_branch())
	root.add_child(BTAction.new(_wander_action))
	return root

func _build_sleep_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_sleep))
	seq.add_child(_build_go_home_subtree())
	return seq

func _build_work_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_work))
	seq.add_child(BTCondition.new(_cond_has_target))
	seq.add_child(_build_reach_target_subtree())
	return seq

func _build_eat_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_eat))
	seq.add_child(_build_go_home_subtree())
	seq.add_child(BTAction.new(_eat_action))
	return seq

func _build_leisure_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_leisure))
	seq.add_child(BTAction.new(_wander_action))
	return seq

func _build_go_home_subtree() -> BTNode:
	var sel := BTSelector.new()
	sel.add_child(BTCondition.new(_cond_is_at_home))
	sel.add_child(BTAction.new(_action_walk_home))
	return sel

func _build_reach_target_subtree() -> BTNode:
	var sel := BTSelector.new()
	sel.add_child(BTCondition.new(_cond_is_harvesting))
	sel.add_child(BTAction.new(_action_walk_to_target))
	return sel

# ─── Conditions ───────────────────────────────────────────────────────────────
func _cond_phase_is_sleep(c: Dictionary)   -> bool: return c.get("current_phase", "") == PHASE_SLEEP
func _cond_phase_is_work(c: Dictionary)    -> bool: return c.get("current_phase", "") == PHASE_WORK
func _cond_phase_is_eat(c: Dictionary)     -> bool: return c.get("current_phase", "") == PHASE_EAT
func _cond_phase_is_leisure(c: Dictionary) -> bool: return c.get("current_phase", "") == PHASE_LEISURE
func _cond_has_target(c: Dictionary)       -> bool: return c.get(CTX_HAS_TARGET, false)
func _cond_is_at_home(c: Dictionary)       -> bool: return c.get(CTX_IS_AT_HOME, false)
func _cond_is_harvesting(c: Dictionary)    -> bool: return c.get(CTX_IS_HARVESTING, false)

# ─── Actions ──────────────────────────────────────────────────────────────────
func _action_walk_to_target(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_TO_TARGET, false):
		c[CTX_GOING_TO_TARGET] = true
		c[CTX_IS_HARVESTING]   = false
		c[CTX_IS_AT_HOME]      = false
		var dest: Vector3 = GameManager.grid_system.cell_to_world(assigned_target_cell)
		dest.y = 0.0
		move_to(dest)
	if is_moving():
		return BTNode.Status.RUNNING
	# Arrived — harvest the resource object
	var reg: ResourceObjectRegistry = GameManager.get_system("resource_object_registry")
	if reg != null:
		var obj: ResourceObject = reg.get_object_at(assigned_target_cell)
		if obj != null and is_instance_valid(obj):
			obj.harvest()
	assigned_target_cell      = Vector2i(-1, -1)
	c[CTX_IS_HARVESTING]      = false
	c[CTX_GOING_TO_TARGET]    = false
	c[CTX_HAS_TARGET]         = false
	# Try to get a new assignment immediately
	_request_new_target()
	return BTNode.Status.SUCCESS

func _action_walk_home(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_HOME, false):
		c[CTX_GOING_HOME]      = true
		c[CTX_IS_HARVESTING]   = false
		c[CTX_IS_AT_HOME]      = false
		c[CTX_GOING_TO_TARGET] = false
		move_to(GameManager.grid_system.cell_to_world(home_cell))
	if is_moving():
		return BTNode.Status.RUNNING
	c[CTX_IS_AT_HOME]  = true
	c[CTX_GOING_HOME]  = false
	return BTNode.Status.SUCCESS

# ─── Target interface (used by ResourceObjectRegistry) ────────────────────────
## Returns the resource object type this worker harvests.
func get_target_type() -> String:
	return "tree"

func has_target() -> bool:
	return assigned_target_cell != Vector2i(-1, -1)

func assign_target(target_cell: Vector2i) -> void:
	assigned_target_cell   = target_cell
	_ctx[CTX_IS_HARVESTING]   = false
	_ctx[CTX_GOING_TO_TARGET] = false

func release_target() -> void:
	assigned_target_cell   = Vector2i(-1, -1)
	_ctx[CTX_IS_HARVESTING]   = false
	_ctx[CTX_GOING_TO_TARGET] = false

func check_current_hour() -> void:
	_apply_phase(GameManager.game_time.hour)
	_ctx[CTX_IS_AT_HOME]      = false
	_ctx[CTX_GOING_TO_TARGET] = false
	_ctx[CTX_GOING_HOME]      = false

func _request_new_target() -> void:
	var reg: ResourceObjectRegistry = GameManager.get_system("resource_object_registry")
	if reg == null:
		return
	reg._try_assign_worker(self)

# ─── Day reset ────────────────────────────────────────────────────────────────

# ─── Day reset ────────────────────────────────────────────────────────────────
func _on_new_day(_day: int, _month: int, _year: int) -> void:
	if is_queued_for_deletion():
		return
	_ctx[CTX_IS_HARVESTING]   = false
	_ctx[CTX_IS_AT_HOME]      = false
	_ctx[CTX_GOING_TO_TARGET] = false
	_ctx[CTX_GOING_HOME]      = false