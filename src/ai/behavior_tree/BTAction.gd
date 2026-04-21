## BTAction.gd
## Leaf node: executes an action callable each tick.
## The callable receives the context dictionary and must return a BTNode.Status.
## Use RUNNING to indicate the action is still in progress across frames.
##
## Usage:
##   BTAction.new(func(ctx): return BTNode.Status.RUNNING)
class_name BTAction
extends BTNode

var _action: Callable

func _init(action: Callable) -> void:
	_action = action

func tick(ctx: Dictionary) -> Status:
	return _action.call(ctx) as Status