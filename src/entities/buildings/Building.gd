## Building.gd
## Base class for every building instance placed in the world.
class_name Building
extends Node2D

var data: BuildingData = null
var cell: Vector2i = Vector2i.ZERO
var current_level: int = 1
var is_operational: bool = true

@onready var sprite:             Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var selection_highlight: Node2D  = $SelectionHighlight if has_node("SelectionHighlight") else null

func _ready() -> void:
	assert(data != null, "Building placed without BuildingData!")
	_setup_visuals()
	EventBus.new_day.connect(_on_new_day)

func initialize(building_data: BuildingData, grid_cell: Vector2i) -> void:
	data = building_data
	cell = grid_cell

func _setup_visuals() -> void:
	if data and not data.icon_path.is_empty() and sprite:
		if ResourceLoader.exists(data.icon_path):
			sprite.texture = load(data.icon_path)

func select() -> void:
	if selection_highlight: selection_highlight.visible = true
	EventBus.emit_signal("building_selected", data, cell)

func deselect() -> void:
	if selection_highlight: selection_highlight.visible = false
	EventBus.emit_signal("building_deselected")

func on_tick() -> void:
	pass

func _on_new_day(_day: int, _month: int, _year: int) -> void:
	on_tick()

func can_upgrade() -> bool:
	return current_level < data.max_level

func upgrade() -> void:
	if not can_upgrade(): return
	current_level += 1
	_on_upgraded()
	EventBus.emit_signal("building_upgraded", data, cell)

func _on_upgraded() -> void:
	pass

func serialize() -> Dictionary:
	return {
		"building_id":    data.id,
		"cell":           [cell.x, cell.y],
		"level":          current_level,
		"is_operational": is_operational,
	}

func deserialize(saved: Dictionary) -> void:
	current_level  = saved.get("level",          1)
	is_operational = saved.get("is_operational", true)
	var c: Array   = saved.get("cell",           [0, 0])
	cell           = Vector2i(c[0], c[1])
