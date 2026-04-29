## ResourceObjectRegistry.gd
## Tracks all placed resource objects (trees, rocks) in the world and assigns
## extraction workers (LumberjackCitizen / MinerCitizen) to them.
##
## Assignment flow mirrors WheatFieldRegistry exactly:
##   - building_placed  (Sawmill / Quarry) → try assign all existing workers
##   - resource_object_placed (tree / rock) → try assign all existing workers
##   - citizen_spawned  (new lumberjack / miner) → try assign that worker
##   - citizen_despawned                         → release their target
##   - resource_object_removed (after harvest)   → release worker, find new target
class_name ResourceObjectRegistry
extends Node

# ─── Constants ────────────────────────────────────────────────────────────────
## Maps building id → resource object type workers from that building harvest.
const BUILDING_TO_TARGET: Dictionary = {
	"sawmill": "tree",
	"quarry":  "rock",
}

# ─── State ────────────────────────────────────────────────────────────────────
## cell → ResourceObject node
var _objects: Dictionary = {}

## cell → worker node (LumberjackCitizen / MinerCitizen), null if unassigned
var _object_workers: Dictionary = {}

## Config per object type from config/resource_objects.json
var _object_configs: Dictionary = {}

var _citizen_manager: CitizenManager = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_object_configs = ConfigLoader.resource_objects
	GameManager.register_system("resource_object_registry", self)

	EventBus.building_placed.connect(_on_building_placed)
	EventBus.resource_object_removed.connect(_on_resource_object_removed)
	EventBus.citizen_spawned.connect(_on_citizen_spawned)
	EventBus.citizen_despawned.connect(_on_citizen_despawned)

	_citizen_manager = get_parent().get_node_or_null("CitizenManager")

# ─── Building signal ──────────────────────────────────────────────────────────
## When a Sawmill or Quarry is placed, attempt to assign any existing idle
## workers of the matching type (e.g. if a lumberjack already lives there).
func _on_building_placed(building_data: BuildingData, _cell: Vector2i) -> void:
	var target_type: String = BUILDING_TO_TARGET.get(building_data.id, "")
	if target_type == "":
		return
	_try_assign_all_unassigned_workers(target_type)

# ─── Resource object removal ──────────────────────────────────────────────────
## Called via EventBus when a ResourceObject harvests itself (queue_free).
func _on_resource_object_removed(_type: String, cell: Vector2i) -> void:
	var worker = _object_workers.get(cell, null)
	_objects.erase(cell)
	_object_workers.erase(cell)
	# Give the worker a new target immediately
	if worker != null and is_instance_valid(worker) and not worker.is_queued_for_deletion() and worker.has_method("release_target"):
		worker.release_target()
		_try_assign_worker(worker)

# ─── Citizen signals ──────────────────────────────────────────────────────────
func _on_citizen_spawned(citizen: Object, _cell: Vector2i) -> void:
	if not citizen.has_method("get_target_type"):
		return
	_try_assign_worker(citizen)

func _on_citizen_despawned(citizen: Object, _cell: Vector2i) -> void:
	if not citizen.has_method("get_target_type"):
		return
	_release_worker(citizen)

# ─── Placement API (called by BuildingPlacer) ─────────────────────────────────
## Instantiate and register a resource object at the given cell.
## Returns the created node so BuildingPlacer can parent it to the world.
func place_object(type: String, cell: Vector2i) -> ResourceObject:
	if _objects.has(cell):
		return null
	var cfg: Dictionary     = _object_configs.get(type, {})
	var script_path: String = cfg.get("script_path", "")
	var node: ResourceObject
	if script_path != "":
		var script: GDScript = load(script_path) as GDScript
		if script:
			node = script.new() as ResourceObject
	if node == null:
		node = ResourceObject.new()
	node.initialize(type, cell, cfg)
	_objects[cell]        = node
	_object_workers[cell] = null
	# A new object appeared — try to assign idle workers of the matching type
	_try_assign_all_unassigned_workers(type)
	return node

## Remove an object placed by the player (demolish, not harvest).
func remove_object(cell: Vector2i) -> void:
	if not _objects.has(cell):
		return
	var obj: ResourceObject = _objects[cell]
	var worker              = _object_workers.get(cell, null)
	_objects.erase(cell)
	_object_workers.erase(cell)
	if worker != null and is_instance_valid(worker) and not worker.is_queued_for_deletion() and worker.has_method("release_target"):
		worker.release_target()
		_try_assign_worker(worker)
	obj.queue_free()

# ─── Assignment logic ─────────────────────────────────────────────────────────
## Try to assign a single worker to its nearest free matching object.
func _try_assign_worker(worker: Object) -> void:
	if not is_instance_valid(worker) or worker.is_queued_for_deletion():
		return
	if not worker.has_method("get_target_type"):
		return
	if worker.has_method("has_target") and worker.has_target():
		return
	var target_type: String    = worker.get_target_type()
	var nearest_cell: Vector2i = _find_nearest_free_object(worker, target_type)
	if nearest_cell == Vector2i(-1, -1):
		return
	_object_workers[nearest_cell] = worker
	worker.assign_target(nearest_cell)
	worker.check_current_hour()

## Try to assign all idle workers whose target type matches the given type.
func _try_assign_all_unassigned_workers(target_type: String) -> void:
	if _citizen_manager == null:
		_citizen_manager = get_parent().get_node_or_null("CitizenManager")
	if _citizen_manager == null:
		return
	for citizen in _citizen_manager.get_all_citizens():
		if not is_instance_valid(citizen):
			continue
		if not citizen.has_method("get_target_type"):
			continue
		if citizen.get_target_type() != target_type:
			continue
		if not citizen.has_method("has_target") or citizen.has_target():
			continue
		_try_assign_worker(citizen)

func _release_worker(worker: Object) -> void:
	for cell in _object_workers:
		var w = _object_workers[cell]
		if is_instance_valid(w) and w == worker:
			_object_workers[cell] = null
			return

func _find_nearest_free_object(worker: Object, target_type: String) -> Vector2i:
	var home: Vector2i   = worker.home_cell if "home_cell" in worker else Vector2i.ZERO
	var best_cell        := Vector2i(-1, -1)
	var best_dist: float  = INF
	for cell in _objects:
		var w = _object_workers.get(cell, null)
		if w != null and is_instance_valid(w):
			continue
		var obj: ResourceObject = _objects[cell]
		if obj == null or not is_instance_valid(obj):
			continue
		if obj.object_type != target_type:
			continue
		var dist: float = float((cell - home).length())
		if dist < best_dist:
			best_dist = dist
			best_cell = cell
	return best_cell

# ─── Queries ──────────────────────────────────────────────────────────────────
func get_object_at(cell: Vector2i) -> ResourceObject:
	return _objects.get(cell, null)

func is_cell_occupied_by_object(cell: Vector2i) -> bool:
	return _objects.has(cell)

func get_total_count() -> int:
	return _objects.size()