## WheatFieldRegistry.gd
## Tracks all placed wheat field buildings.
## Assigns the nearest free field to each FarmerCitizen when spawned or when a new field is placed.
## Triggers wheat production once per day for each farmer on their field.
class_name WheatFieldRegistry
extends Node

# ─── State ────────────────────────────────────────────────────────
## cell → FarmerCitizen or null (null = field is unassigned)
var _fields: Dictionary = {}

var _citizen_manager: CitizenManager = null

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)
	EventBus.citizen_spawned.connect(_on_citizen_spawned)
	EventBus.citizen_despawned.connect(_on_citizen_despawned)
	EventBus.hour_changed.connect(_on_hour_changed)
	# CitizenManager is a sibling node under Systems
	_citizen_manager = get_parent().get_node_or_null("CitizenManager")

# ─── Building signals ─────────────────────────────────────────────
func _on_building_placed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.id != "wheat_field":
		return
	_fields[cell] = null
	EventBus.emit_signal("wheat_field_registered", cell)
	_try_assign_all_unassigned_farmers()

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.id != "wheat_field":
		return
	var farmer = _fields.get(cell, null)
	if farmer is FarmerCitizen:
		(farmer as FarmerCitizen).release_field()
	_fields.erase(cell)
	EventBus.emit_signal("wheat_field_unregistered", cell)

# ─── Citizen signals ──────────────────────────────────────────────
func _on_citizen_spawned(citizen: Object, _cell: Vector2i) -> void:
	if not citizen is FarmerCitizen:
		return
	_try_assign_farmer(citizen as FarmerCitizen)

func _on_citizen_despawned(citizen: Object, _cell: Vector2i) -> void:
	if not citizen is FarmerCitizen:
		return
	var farmer := citizen as FarmerCitizen
	if farmer.has_field():
		_fields[farmer.assigned_field_cell] = null
		farmer.release_field()

# ─── Assignment ───────────────────────────────────────────────────
func _try_assign_farmer(farmer: FarmerCitizen) -> void:
	if farmer.has_field():
		return
	var nearest_cell: Vector2i = _find_nearest_free_field(farmer.home_cell)
	if nearest_cell == Vector2i(-1, -1):
		return
	_fields[nearest_cell] = farmer
	farmer.assign_field(nearest_cell)
	# If it is already work time, send the farmer to the field immediately
	farmer.check_current_hour()

func _try_assign_all_unassigned_farmers() -> void:
	if _citizen_manager == null:
		_citizen_manager = get_parent().get_node_or_null("CitizenManager")
	if _citizen_manager == null:
		return
	for cell in _citizen_manager.get_all_citizen_cells():
		for citizen in _citizen_manager.get_citizens_at(cell):
			if citizen is FarmerCitizen and not (citizen as FarmerCitizen).has_field():
				_try_assign_farmer(citizen as FarmerCitizen)

func _find_nearest_free_field(from_cell: Vector2i) -> Vector2i:
	var best_cell: Vector2i = Vector2i(-1, -1)
	var best_dist: float = INF
	for field_cell in _fields:
		if _fields[field_cell] != null:
			continue
		var dist: float = float((field_cell - from_cell).length())
		if dist < best_dist:
			best_dist = dist
			best_cell = field_cell
	return best_cell

# ─── Daily production ─────────────────────────────────────────────
func _on_hour_changed(hour: int) -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get("day_cycle", {})
	var work_end: int = cfg.get("work_end_hour", 20)
	if hour != work_end:
		return
	for field_cell in _fields:
		var farmer = _fields[field_cell]
		if farmer is FarmerCitizen:
			(farmer as FarmerCitizen).produce_wheat()

# ─── Queries ──────────────────────────────────────────────────────
func get_field_count() -> int:
	return _fields.size()

func get_assigned_count() -> int:
	var count: int = 0
	for cell in _fields:
		if _fields[cell] != null:
			count += 1
	return count