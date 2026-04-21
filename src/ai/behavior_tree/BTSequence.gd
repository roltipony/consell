## BTSequence.gd
## Composite: runs children in order each tick, always starting from index 0.
## This is a REACTIVE sequence — re-evaluates all conditions every tick.
## Returns FAILURE as soon as one child fails.
## Returns SUCCESS only when all children succeed.
## Returns RUNNING while a child is running (after all prior conditions pass).
class_name BTSequence
extends BTNode

var _children: Array[BTNode] = []

func add_child(node: BTNode) -> BTSequence:
	_children.append(node)
	return self

func tick(ctx: Dictionary) -> Status:
	for child in _children:
		var status: Status = child.tick(ctx)
		if status != Status.SUCCESS:
			return status
	return Status.SUCCESS