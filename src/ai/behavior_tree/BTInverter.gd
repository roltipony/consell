## BTInverter.gd
## Decorator: inverts the result of its single child.
## SUCCESS → FAILURE, FAILURE → SUCCESS, RUNNING → RUNNING.
class_name BTInverter
extends BTNode

var _child: BTNode

func _init(child: BTNode) -> void:
	_child = child

func tick(ctx: Dictionary) -> Status:
	var status: Status = _child.tick(ctx)
	match status:
		Status.SUCCESS: return Status.FAILURE
		Status.FAILURE: return Status.SUCCESS
		_:              return Status.RUNNING