## BTNode.gd
## Base class for every node in a Behavior Tree.
## All nodes implement tick(ctx) and return one of three statuses.
class_name BTNode
extends RefCounted

enum Status { SUCCESS, FAILURE, RUNNING }

## Execute this node for one frame. ctx is a Dictionary owned by the citizen.
func tick(ctx: Dictionary) -> Status:
	return Status.FAILURE