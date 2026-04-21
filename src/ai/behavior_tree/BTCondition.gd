## BTCondition.gd
## Leaf node: evaluates a condition callable each tick.
## Returns SUCCESS if the callable returns true, FAILURE otherwise.
## The callable receives the context dictionary as its only argument.
##
## Usage:
##   BTCondition.new(func(ctx): return ctx.get("has_field", false))
class_name BTCondition
extends BTNode

var _condition: Callable

func _init(condition: Callable) -> void:
	_condition = condition

func tick(ctx: Dictionary) -> Status:
	if _condition.call(ctx):
		return Status.SUCCESS
	return Status.FAILURE