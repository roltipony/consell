## WheatFieldRegistry.gd
## Tracks all placed wheat fields and their accumulated work hours.
##
## Each field has its own hours counter. Every in-game hour, any farmer
## currently working on a field contributes +1 hour to that field's counter.
## When the counter reaches hours_per_unit (from resources.json → wheat),
## the field produces 1 wheat (converted to food by EconomySystem), and the
## counter resets to 0 to start again.
##
## This means:
##   - Multiple farmers on the same field accumulate hours faster (future).
##   - Hours persist across days — no work is lost at midnight.
##   - FarmerCitizen only needs to expose is_working; no production logic there.
class_name WheatFieldRegistry
extends Node

# ─── State ────────────────────────────────────────────────────────────────────
## cell → FarmerCitizen or null (null = field is unassigned)
var _fields: Dictionary = {}

## cell → int hours accumulated toward next wheat unit
var _field_hours: Dictionary = {}

## Loaded once from resources.json → wheat → hours_per_unit
var _hours_per_unit: int = 2

var _citizen_manager: CitizenManager = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	var wheat_cfg: Dictionary = ConfigLoader.get_resource("wheat")
	_hours_per_unit = int(wheat_cfg.get("hours_per_unit", 2))

	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)
	EventBus.citizen_spawned.connect(_on_citizen_spawned)
	EventBus.citizen_despawned.connect(_on_citizen_despawned)
	EventBus.hour_changed.connect(_on_hour_changed)
	_citizen_manager = get_parent().get_node_or_null("CitizenManager")

# ─── Building signals ─────────────────────────────────────────────────────────
func _on_building_placed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.id != "wheat_field":
		return
	_fields[cell]      = null
	_field_hours[cell] = 0
	EventBus.emit_signal("wheat_field_registered", cell)
	_try_assign_all_unassigned_farmers()

func _on_building_removed(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data.id != "wheat_field":
		return
	var farmer = _fields.get(cell, null)
	_fields.erase(cell)
	_field_hours.erase(cell)
	EventBus.emit_signal("wheat_field_unregistered", cell)
	# Release the farmer AFTER removing the cell from _fields so the
	# field-search below cannot accidentally re-assign them to the deleted cell.
	if farmer is FarmerCitizen:
		(farmer as FarmerCitizen).release_field()
		_try_assign_farmer(farmer as FarmerCitizen)

# ─── Citizen signals ──────────────────────────────────────────────────────────
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

# ─── Hourly tick ──────────────────────────────────────────────────────────────
## Each hour, check every assigned field. If its farmer is working,
## increment that field's hour counter and produce when threshold is reached.
func _on_hour_changed(_hour: int) -> void:
	for field_cell in _fields:
		var farmer = _fields[field_cell]
		if not farmer is FarmerCitizen:
			continue
		if not (farmer as FarmerCitizen).is_working():
			continue
		_field_hours[field_cell] += 1
		if _field_hours[field_cell] >= _hours_per_unit:
			_field_hours[field_cell] = 0
			_produce_wheat()

func _produce_wheat() -> void:
	var wheat_cfg: Dictionary = ConfigLoader.get_resource("wheat")
	var food_value: float     = float(wheat_cfg.get("food_value", 1.0))
	GameManager.economy_system.add_resource("wheat", food_value)

# ─── Assignment ───────────────────────────────────────────────────────────────
func _try_assign_farmer(farmer: FarmerCitizen) -> void:
	if farmer.has_field():
		return
	var nearest_cell: Vector2i = _find_nearest_free_field(farmer.home_cell)
	if nearest_cell == Vector2i(-1, -1):
		return
	_fields[nearest_cell] = farmer
	farmer.assign_field(nearest_cell)
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
	var best_dist: float    = INF
	for field_cell in _fields:
		if _fields[field_cell] != null:
			continue
		var dist: float = float((field_cell - from_cell).length())
		if dist < best_dist:
			best_dist = dist
			best_cell = field_cell
	return best_cell

# ─── Queries ──────────────────────────────────────────────────────────────────
func get_field_count() -> int:
	return _fields.size()

func get_assigned_count() -> int:
	var count: int = 0
	for cell in _fields:
		if _fields[cell] != null:
			count += 1
	return count
