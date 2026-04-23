## FarmerCitizen.gd
## Citizen type: farmer.
##
## ALL behaviour is expressed in the Behavior Tree.
## Actions do exactly one thing. Conditions do exactly one check.
## No behaviour logic lives outside _build_behavior_tree().
##
## Color is applied once per phase change (in _on_phase_changed), NOT every tick.
##
## Day-phase schedule (game_settings.json → citizen_schedules → farmer):
##   sleep   →  0–8    go home, stay there
##   work    →  8–14   travel to assigned field, work
##   eat     → 14–15   travel home to eat
##   leisure → 15–24   wander near home
##
## Tree:
##   Selector (reactive — re-evaluates every tick)
##   ├── Sequence [sleep]
##   │   ├── Condition : phase_is("sleep")
##   │   └── Selector  : is_at_home OR walk_home
##   │       ├── Condition : is_at_home
##   │       └── Action    : walk_home
##   ├── Sequence [work]
##   │   ├── Condition : phase_is("work")
##   │   ├── Condition : has_field
##   │   └── Selector  : is_working OR walk_to_field
##   │       ├── Condition : is_working
##   │       └── Action    : walk_to_field
##   ├── Sequence [eat]
##   │   ├── Condition : phase_is("eat")
##   │   └── Selector  : is_at_home OR walk_home
##   │       ├── Condition : is_at_home
##   │       └── Action    : walk_home
##   ├── Sequence [leisure]
##   │   ├── Condition : phase_is("leisure")
##   │   └── Action    : wander
##   └── Action : wander  (safety fallback)
class_name FarmerCitizen
extends Citizen

# ─── Blackboard keys ──────────────────────────────────────────────────────────
const CTX_HAS_FIELD      := "has_field"
const CTX_IS_WORKING     := "is_working"
const CTX_IS_AT_HOME     := "is_at_home"
const CTX_GOING_TO_FIELD := "going_to_field"
const CTX_GOING_HOME     := "going_home"

# ─── Data ─────────────────────────────────────────────────────────────────────
var assigned_field_cell: Vector2i = Vector2i(-1, -1)

## Phase colors loaded from game_settings.json → citizen_phase_colors → farmer.
## Keyed by phase id so new phases only need a config entry, no code change.
var _phase_colors: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	citizen_type = "farmer"
	super._ready()
	EventBus.new_day.connect(_on_new_day)

func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	super.initialize(cell, cfg)
	_load_phase_colors(cfg)

## Reads all phase colors for this citizen type from config.
## Falls back to farmer_work_color when a specific phase key is missing.
func _load_phase_colors(cfg: Dictionary) -> void:
	var fallback: String = cfg.get("farmer_work_color", "#a0c840")
	var phase_colors_cfg: Dictionary = \
		ConfigLoader.game_settings.get("citizen_phase_colors", {}).get(citizen_type, {})
	for phase_id in [PHASE_WORK, PHASE_EAT, PHASE_LEISURE, PHASE_SLEEP]:
		_phase_colors[phase_id] = Color(phase_colors_cfg.get(phase_id, fallback))

# ─── Phase change hook ────────────────────────────────────────────────────────
## Called by Citizen._apply_phase() whenever the active phase changes.
## Resets transit flags so the new phase starts clean, then updates color.
func _on_phase_changed(new_phase: String) -> void:
	# Clear transit state on every phase transition so actions
	# don't carry stale "going_to_field / going_home" flags into the new phase.
	_ctx[CTX_GOING_TO_FIELD] = false
	_ctx[CTX_GOING_HOME]     = false
	_ctx[CTX_IS_WORKING]     = false
	_ctx[CTX_IS_AT_HOME]     = false
	if _phase_colors.has(new_phase):
		set_color(_phase_colors[new_phase])

# ─── Context update (runs every frame before BT tick) ────────────────────────
func _update_context() -> void:
	_ctx[CTX_HAS_FIELD] = has_field()
	if not _ctx.has(CTX_IS_WORKING):     _ctx[CTX_IS_WORKING]     = false
	if not _ctx.has(CTX_IS_AT_HOME):     _ctx[CTX_IS_AT_HOME]     = false
	if not _ctx.has(CTX_GOING_TO_FIELD): _ctx[CTX_GOING_TO_FIELD] = false
	if not _ctx.has(CTX_GOING_HOME):     _ctx[CTX_GOING_HOME]     = false

# ─── Behavior Tree ────────────────────────────────────────────────────────────
func _build_behavior_tree() -> BTNode:
	var root := BTSelector.new()
	root.add_child(_build_sleep_branch())
	root.add_child(_build_work_branch())
	root.add_child(_build_eat_branch())
	root.add_child(_build_leisure_branch())
	root.add_child(BTAction.new(_wander_action))  # safety fallback
	return root

## sleep: go home and stay.
func _build_sleep_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_sleep))
	seq.add_child(_build_go_home_subtree())
	return seq

## work: travel to field and stay working.
func _build_work_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_work))
	seq.add_child(BTCondition.new(_cond_has_field))
	seq.add_child(_build_reach_field_subtree())
	return seq

## eat: return home.
func _build_eat_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_eat))
	seq.add_child(_build_go_home_subtree())
	return seq

## leisure: wander near home.
func _build_leisure_branch() -> BTNode:
	var seq := BTSequence.new()
	seq.add_child(BTCondition.new(_cond_phase_is_leisure))
	seq.add_child(BTAction.new(_wander_action))
	return seq

## Subtree: already at home → SUCCESS immediately. Otherwise walk home → RUNNING.
func _build_go_home_subtree() -> BTNode:
	var sel := BTSelector.new()
	sel.add_child(BTCondition.new(_cond_is_at_home))
	sel.add_child(BTAction.new(_action_walk_home))
	return sel

## Subtree: already working → SUCCESS immediately. Otherwise walk to field → RUNNING.
func _build_reach_field_subtree() -> BTNode:
	var sel := BTSelector.new()
	sel.add_child(BTCondition.new(_cond_is_working))
	sel.add_child(BTAction.new(_action_walk_to_field))
	return sel

# ─── Phase conditions (one check each) ───────────────────────────────────────
func _cond_phase_is_sleep(c: Dictionary)   -> bool: return c.get("current_phase", "") == PHASE_SLEEP
func _cond_phase_is_work(c: Dictionary)    -> bool: return c.get("current_phase", "") == PHASE_WORK
func _cond_phase_is_eat(c: Dictionary)     -> bool: return c.get("current_phase", "") == PHASE_EAT
func _cond_phase_is_leisure(c: Dictionary) -> bool: return c.get("current_phase", "") == PHASE_LEISURE

# ─── State conditions (one check each) ───────────────────────────────────────
func _cond_has_field(c: Dictionary)  -> bool: return c.get(CTX_HAS_FIELD,  false)
func _cond_is_at_home(c: Dictionary) -> bool: return c.get(CTX_IS_AT_HOME, false)
func _cond_is_working(c: Dictionary) -> bool: return c.get(CTX_IS_WORKING,  false)

# ─── Movement actions ─────────────────────────────────────────────────────────
## Walks to the assigned field. Uses CTX_GOING_TO_FIELD to avoid restarting
## the move every frame once the farmer has arrived.
## Marks is_working=true on arrival and returns SUCCESS exactly once,
## after which _cond_is_working short-circuits the subtree.
func _action_walk_to_field(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_TO_FIELD, false):
		c[CTX_GOING_TO_FIELD] = true
		c[CTX_IS_WORKING]     = false
		c[CTX_IS_AT_HOME]     = false
		var dest: Vector3 = GameManager.grid_system.cell_to_world(assigned_field_cell)
		dest.y = 0.0
		move_to(dest)
	if is_moving():
		return BTNode.Status.RUNNING
	c[CTX_IS_WORKING]     = true
	c[CTX_GOING_TO_FIELD] = false
	return BTNode.Status.SUCCESS

## Walks home. Uses CTX_GOING_HOME to avoid restarting the move every frame.
## Marks is_at_home=true on arrival and returns SUCCESS exactly once.
func _action_walk_home(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_HOME, false):
		c[CTX_GOING_HOME]     = true
		c[CTX_IS_WORKING]     = false
		c[CTX_IS_AT_HOME]     = false
		c[CTX_GOING_TO_FIELD] = false
		move_to(GameManager.grid_system.cell_to_world(home_cell))
	if is_moving():
		return BTNode.Status.RUNNING
	c[CTX_IS_AT_HOME] = true
	c[CTX_GOING_HOME] = false
	return BTNode.Status.SUCCESS

# ─── Field assignment ─────────────────────────────────────────────────────────
func assign_field(field_cell: Vector2i) -> void:
	assigned_field_cell      = field_cell
	_ctx[CTX_IS_WORKING]     = false
	_ctx[CTX_GOING_TO_FIELD] = false

func release_field() -> void:
	assigned_field_cell      = Vector2i(-1, -1)
	_ctx[CTX_IS_WORKING]     = false
	_ctx[CTX_GOING_TO_FIELD] = false

func has_field() -> bool:
	return assigned_field_cell != Vector2i(-1, -1)

## Forces an immediate phase re-evaluation after a mid-day field assignment
## so the farmer starts moving without waiting for the next hour_changed signal.
func check_current_hour() -> void:
	_apply_phase(GameManager.game_time.hour)
	_ctx[CTX_IS_AT_HOME]     = false
	_ctx[CTX_GOING_TO_FIELD] = false
	_ctx[CTX_GOING_HOME]     = false

# ─── Queries ──────────────────────────────────────────────────────────────────
## Returns true when the farmer is physically at the field and working.
## Used by WheatFieldRegistry to count productive hours per field.
func is_working() -> bool:
	return _ctx.get(CTX_IS_WORKING, false)

# ─── Day reset ────────────────────────────────────────────────────────────────
func _on_new_day(_day: int, _month: int, _year: int) -> void:
	_ctx[CTX_IS_WORKING]     = false
	_ctx[CTX_IS_AT_HOME]     = false
	_ctx[CTX_GOING_TO_FIELD] = false
	_ctx[CTX_GOING_HOME]     = false