## FarmerCitizen.gd
## Citizen type: farmer.
## Uses a Behavior Tree to decide each frame what to do.
##
## Tree structure:
##   Selector
##   ├── Sequence [go to work]
##   │   ├── Condition: is_work_time
##   │   ├── Condition: has_field
##   │   └── Selector [reach and stay at field]
##   │       ├── Condition: is_working
##   │       └── Action: travel_to_field
##   ├── Sequence [go home]
##   │   ├── Condition: NOT is_work_time
##   │   ├── Condition: NOT is_at_home
##   │   └── Action: go_home
##   └── Action: wander (fallback)
class_name FarmerCitizen
extends Citizen

# ─── Blackboard keys ─────────────────────────────────────────────
const CTX_HAS_FIELD       := "has_field"
const CTX_IS_WORKING      := "is_working"
const CTX_IS_AT_HOME      := "is_at_home"
const CTX_GOING_TO_FIELD  := "going_to_field"
const CTX_GOING_HOME      := "going_home"

# ─── Data ────────────────────────────────────────────────────────
var assigned_field_cell: Vector2i = Vector2i(-1, -1)
var _work_color: Color = Color.WHITE
var _rest_color: Color = Color.WHITE

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	citizen_type = "farmer"
	super._ready()
	EventBus.new_day.connect(_on_new_day)

func initialize(cell: Vector2i, cfg: Dictionary) -> void:
	super.initialize(cell, cfg)
	_work_color = Color(cfg.get("farmer_work_color", "#a0c840"))
	_rest_color = Color(cfg.get("color",             "#e8c090"))
	set_color(_rest_color)

# ─── Context update ───────────────────────────────────────────────
func _update_context() -> void:
	_ctx[CTX_HAS_FIELD]      = has_field()
	if not _ctx.has(CTX_IS_WORKING):     _ctx[CTX_IS_WORKING]     = false
	if not _ctx.has(CTX_IS_AT_HOME):     _ctx[CTX_IS_AT_HOME]     = false
	if not _ctx.has(CTX_GOING_TO_FIELD): _ctx[CTX_GOING_TO_FIELD] = false
	if not _ctx.has(CTX_GOING_HOME):     _ctx[CTX_GOING_HOME]     = false

# ─── Behavior Tree ────────────────────────────────────────────────
func _build_behavior_tree() -> BTNode:
	var root := BTSelector.new()

	# Branch 1 — go to work
	var work_seq := BTSequence.new()
	work_seq.add_child(BTCondition.new(_cond_is_work_time))
	work_seq.add_child(BTCondition.new(_cond_has_field))
	work_seq.add_child(_build_reach_field_subtree())
	root.add_child(work_seq)

	# Branch 2 — go home
	var rest_seq := BTSequence.new()
	rest_seq.add_child(BTCondition.new(_cond_not_work_time))
	rest_seq.add_child(BTCondition.new(_cond_not_at_home))
	rest_seq.add_child(BTAction.new(_action_go_home))
	root.add_child(rest_seq)

	# Branch 3 — wander fallback
	root.add_child(_build_wander_tree())

	return root

func _build_reach_field_subtree() -> BTNode:
	var sel := BTSelector.new()
	sel.add_child(BTCondition.new(_cond_is_working))
	sel.add_child(BTAction.new(_action_travel_to_field))
	return sel

# ─── Conditions ───────────────────────────────────────────────────
func _cond_is_work_time(c: Dictionary) -> bool:
	return c.get("is_work_time", false)

func _cond_not_work_time(c: Dictionary) -> bool:
	return not c.get("is_work_time", false)

func _cond_has_field(c: Dictionary) -> bool:
	return c.get(CTX_HAS_FIELD, false)

func _cond_is_working(c: Dictionary) -> bool:
	return c.get(CTX_IS_WORKING, false)

func _cond_not_at_home(c: Dictionary) -> bool:
	return not c.get(CTX_IS_AT_HOME, false)

# ─── Actions ──────────────────────────────────────────────────────
func _action_travel_to_field(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_TO_FIELD, false):
		c[CTX_GOING_TO_FIELD] = true
		c[CTX_IS_AT_HOME]     = false
		c[CTX_GOING_HOME]     = false
		set_color(_work_color)
		var field_world: Vector3 = GameManager.grid_system.cell_to_world(assigned_field_cell)
		field_world.y = 0.0
		move_to(field_world)
	if is_moving():
		return BTNode.Status.RUNNING
	c[CTX_IS_WORKING]     = true
	c[CTX_GOING_TO_FIELD] = false
	return BTNode.Status.SUCCESS

func _action_go_home(c: Dictionary) -> BTNode.Status:
	if not c.get(CTX_GOING_HOME, false):
		c[CTX_GOING_HOME]     = true
		c[CTX_IS_WORKING]     = false
		c[CTX_GOING_TO_FIELD] = false
		set_color(_rest_color)
		move_to(GameManager.grid_system.cell_to_world(home_cell))
	if is_moving():
		return BTNode.Status.RUNNING
	c[CTX_IS_AT_HOME] = true
	c[CTX_GOING_HOME] = false
	return BTNode.Status.SUCCESS

# ─── Field assignment ─────────────────────────────────────────────
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

func check_current_hour() -> void:
	var hour: int = GameManager.game_time.hour
	_ctx["is_work_time"] = (hour >= _ctx.get("work_start", 6) and hour < _ctx.get("work_end", 20))
	_ctx[CTX_IS_AT_HOME] = false

# ─── Production ───────────────────────────────────────────────────
func produce_wheat() -> void:
	if not _ctx.get(CTX_IS_WORKING, false):
		return
	var wheat_cfg: Dictionary = ConfigLoader.get_resource("wheat")
	var food_value: float   = float(wheat_cfg.get("food_value",              1.0))
	var yield_amount: float = float(wheat_cfg.get("yield_per_farmer_per_day", 1))
	GameManager.economy_system.add_resource("food", yield_amount * food_value)

func _on_new_day(_day: int, _month: int, _year: int) -> void:
	_ctx[CTX_IS_WORKING]     = false
	_ctx[CTX_GOING_TO_FIELD] = false
	_ctx[CTX_IS_AT_HOME]     = false
	_ctx[CTX_GOING_HOME]     = false