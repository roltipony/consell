## HouseOccupancy.gd
## Tracks which citizens live in each residential building cell.
## Instantiated and owned by PopulationSystem.
## Signals are connected by PopulationSystem._ready() — not here.
class_name HouseOccupancy
extends RefCounted

# house_cell -> { "residents": Array, "couple_days": int }
var _houses: Dictionary = {}
# citizen -> house_cell
var _resident_to_house: Dictionary = {}

var _max_children:     int   = 4
var _couple_days:      int   = 3
var _child_growth_age: int   = 4

func _reload_config() -> void:
	var r: Dictionary = ConfigLoader.game_settings.get("house_rules", {})
	_max_children     = int(r.get("max_children",            4))
	_couple_days      = int(r.get("couple_days_to_reproduce", 3))
	_child_growth_age = int(r.get("child_growth_age",        4))

# ---- Public API -------------------------------------------------------

func add_resident(citizen: Citizen, house_cell: Vector2i) -> void:
	_reload_config()
	if not _houses.has(house_cell):
		_houses[house_cell] = { "residents": [], "couple_days": 0 }
	var house: Dictionary = _houses[house_cell]
	if citizen in house["residents"]:
		return
	house["residents"].append(citizen)
	_resident_to_house[citizen] = house_cell
	citizen.home_cell       = house_cell
	citizen.house_occupancy = self
	_try_form_couple(house_cell)

func remove_resident(citizen: Citizen) -> void:
	if not _resident_to_house.has(citizen):
		return
	var house_cell: Vector2i = _resident_to_house[citizen]
	_resident_to_house.erase(citizen)
	if not _houses.has(house_cell):
		return
	_houses[house_cell]["residents"].erase(citizen)
	if citizen.partner != null and is_instance_valid(citizen.partner):
		citizen.partner.partner = null
	citizen.partner = null
	if not _house_has_couple(house_cell):
		_houses[house_cell]["couple_days"] = 0

func get_occupants(house_cell: Vector2i) -> Array:
	if not _houses.has(house_cell):
		return []
	var live: Array = []
	for c in _houses[house_cell]["residents"]:
		if is_instance_valid(c):
			live.append(c)
	_houses[house_cell]["residents"] = live
	return live.duplicate()

func get_house_of(citizen: Citizen) -> Vector2i:
	return _resident_to_house.get(citizen, Vector2i(-1, -1))

func can_have_child(house_cell: Vector2i) -> bool:
	_reload_config()
	return _count_children(house_cell) < _max_children

func find_house_for_immigrant(gender: String) -> Vector2i:
	_reload_config()
	var opposite: String   = _opposite_gender(gender)
	var fallback: Vector2i = Vector2i(-1, -1)
	var gs: GridSystem     = GameManager.grid_system
	if gs == null:
		return Vector2i(-1, -1)
	var visited: Dictionary = {}
	for cell in gs.buildings:
		var bld: Building = gs.buildings[cell]
		if bld == null or bld.data == null or not bld.is_operational:
			continue
		if bld.data.population_capacity <= 0:
			continue
		var origin: Vector2i = bld.cell
		if visited.has(origin):
			continue
		visited[origin] = true
		var residents: Array = get_occupants(origin)
		var capacity: int    = bld.data.population_capacity
		if residents.size() >= capacity:
			continue
		if residents.size() == 1:
			var lone: Citizen = residents[0]
			if is_instance_valid(lone) and lone.stats != null \
					and lone.stats.gender == opposite \
					and not lone.is_child \
					and lone.partner == null:
				return origin
		if fallback == Vector2i(-1, -1):
			fallback = origin
	return fallback

func process_day(_day: int, _month: int, _year: int) -> void:
	_reload_config()
	for house_cell in _houses.keys():
		_run_house_bt(house_cell)

# ---- Signal handlers (connected by PopulationSystem) -----------------

func _on_building_selected(building_data: BuildingData, cell: Vector2i) -> void:
	if building_data == null or building_data.population_capacity <= 0:
		return
	var origin: Vector2i = _resolve_origin(cell)
	var occupants: Array = get_occupants(origin)
	EventBus.emit_signal("house_info_requested", origin, occupants)

func _on_citizen_grew_up(_citizen: Citizen) -> void:
	pass

func _on_citizen_died(citizen: Citizen, _cause: String) -> void:
	if citizen != null:
		remove_resident(citizen)

# ---- Per-house Behavior Tree -----------------------------------------

func _run_house_bt(house_cell: Vector2i) -> void:
	var ctx: Dictionary = { "house_cell": house_cell }
	_build_house_bt().tick(ctx)

func _build_house_bt() -> BTNode:
	var reproduce_seq := BTSequence.new()
	reproduce_seq.add_child(BTCondition.new(_cond_should_reproduce))
	reproduce_seq.add_child(BTAction.new(_action_spawn_child))

	var reproduce_sel := BTSelector.new()
	reproduce_sel.add_child(reproduce_seq)
	reproduce_sel.add_child(BTAction.new(_action_noop))

	var couple_seq := BTSequence.new()
	couple_seq.add_child(BTCondition.new(_cond_has_couple))
	couple_seq.add_child(BTAction.new(_action_increment_couple_days))
	couple_seq.add_child(reproduce_sel)

	var root := BTSelector.new()
	root.add_child(couple_seq)
	root.add_child(BTAction.new(_action_noop))
	return root

# ---- BT conditions ---------------------------------------------------

func _cond_has_couple(ctx: Dictionary) -> bool:
	return _house_has_couple(ctx["house_cell"])

func _cond_should_reproduce(ctx: Dictionary) -> bool:
	var house_cell: Vector2i = ctx["house_cell"]
	if not _houses.has(house_cell):
		return false
	return _houses[house_cell]["couple_days"] >= _couple_days \
		and can_have_child(house_cell)

# ---- BT actions ------------------------------------------------------

func _action_increment_couple_days(ctx: Dictionary) -> BTNode.Status:
	var house_cell: Vector2i = ctx["house_cell"]
	if _houses.has(house_cell):
		_houses[house_cell]["couple_days"] += 1
	return BTNode.Status.SUCCESS

func _action_spawn_child(ctx: Dictionary) -> BTNode.Status:
	var house_cell: Vector2i = ctx["house_cell"]
	var couple: Array = _get_couple(house_cell)
	if couple.size() < 2:
		return BTNode.Status.FAILURE
	_houses[house_cell]["couple_days"] = 0
	var parent_a: Citizen = couple[0]
	var parent_b: Citizen = couple[1]
	var cm: Node = GameManager.citizen_manager
	if cm == null:
		return BTNode.Status.FAILURE
	var child: Citizen = cm.spawn_child(house_cell, _random_gender())
	if child == null:
		return BTNode.Status.FAILURE
	add_resident(child, house_cell)
	EventBus.emit_signal("child_born", child, parent_a, parent_b, house_cell)
	EventBus.notify(
		"%s & %s tuvieron un hijo: %s" % [
			parent_a.stats.citizen_name,
			parent_b.stats.citizen_name,
			child.stats.citizen_name
		], "success"
	)
	return BTNode.Status.SUCCESS

func _action_noop(_ctx: Dictionary) -> BTNode.Status:
	return BTNode.Status.SUCCESS

# ---- Couple helpers --------------------------------------------------

func _try_form_couple(house_cell: Vector2i) -> void:
	if not _houses.has(house_cell):
		return
	var lone_male:   Citizen = null
	var lone_female: Citizen = null
	for citizen in _houses[house_cell]["residents"]:
		if not is_instance_valid(citizen) or citizen.stats == null or citizen.is_child:
			continue
		if citizen.partner != null and is_instance_valid(citizen.partner):
			continue
		match citizen.stats.gender:
			"male":   if lone_male   == null: lone_male   = citizen
			"female": if lone_female == null: lone_female = citizen
	if lone_male == null or lone_female == null:
		return
	lone_male.partner   = lone_female
	lone_female.partner = lone_male
	_houses[house_cell]["couple_days"] = 0
	EventBus.emit_signal("couple_formed", lone_male, lone_female, house_cell)
	EventBus.notify(
		"%s y %s forman una pareja" % [
			lone_male.stats.citizen_name,
			lone_female.stats.citizen_name
		], "info"
	)

func _house_has_couple(house_cell: Vector2i) -> bool:
	return _get_couple(house_cell).size() >= 2

func _get_couple(house_cell: Vector2i) -> Array:
	if not _houses.has(house_cell):
		return []
	for citizen in _houses[house_cell]["residents"]:
		if not is_instance_valid(citizen) or citizen.stats == null or citizen.is_child:
			continue
		var p: Citizen = citizen.partner
		if p != null and is_instance_valid(p) \
				and _resident_to_house.get(p, Vector2i(-1, -1)) == house_cell:
			return [citizen, p]
	return []

func _count_children(house_cell: Vector2i) -> int:
	if not _houses.has(house_cell):
		return 0
	var count: int = 0
	for c in _houses[house_cell]["residents"]:
		if is_instance_valid(c) and c.is_child:
			count += 1
	return count

func _resolve_origin(cell: Vector2i) -> Vector2i:
	var gs: GridSystem = GameManager.grid_system
	if gs == null or not gs.buildings.has(cell):
		return cell
	var bld: Building = gs.buildings[cell]
	if bld == null:
		return cell
	return bld.cell

func _random_gender() -> String:
	var genders: Array = ConfigLoader.game_settings \
		.get("citizen_stats", {}).get("genders", ["male", "female"])
	return str(genders[randi() % genders.size()])

func _opposite_gender(gender: String) -> String:
	var genders: Array = ConfigLoader.game_settings \
		.get("citizen_stats", {}).get("genders", ["male", "female"])
	for g in genders:
		if str(g) != gender:
			return str(g)
	return gender

# ---- Serialization ---------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for cell in _houses:
		var key: String = "%d,%d" % [cell.x, cell.y]
		out[key] = { "couple_days": _houses[cell]["couple_days"] }
	return out

func deserialize(data: Dictionary) -> void:
	for key in data:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if not _houses.has(cell):
			_houses[cell] = { "residents": [], "couple_days": 0 }
		_houses[cell]["couple_days"] = int(data[key].get("couple_days", 0))