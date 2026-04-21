## BTSelector.gd
## Composite: tries children in order each tick, always starting from index 0.
## This is a REACTIVE selector — higher-priority branches always preempt lower ones.
## Returns SUCCESS as soon as one child succeeds.
## Returns FAILURE only when all children fail.
## Returns RUNNING while the active child is still running.
class_name BTSelector
extends BTNode

var _children: Array[BTNode] = []

func add_child(node: BTNode) -> BTSelector:
	_children.append(node)
	return self

func tick(ctx: Dictionary) -> Status:
	for child in _children:
		var status: Status = child.tick(ctx)
		if status != Status.FAILURE:
			return status
	return Status.FAILURE