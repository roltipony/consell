## InfoPanel.gd
## Panel anchored bottom-left. Shows info about the selected building.
## For residential buildings also lists occupants.
##
## Connected signals:
##   EventBus.building_selected    → fill fields and show
##   EventBus.building_deselected  → hide
##   EventBus.house_info_requested → fill occupants list
##
## IMPORTANT: house_info_requested is emitted by HouseOccupancy AFTER
## building_selected. This panel always accepts the latest emission without
## filtering by cell so there is no race-condition between the two signals.
class_name InfoPanel
extends PanelContainer

@onready var _name_label:      Label  = $MarginContainer/VBox/NameLabel
@onready var _level_label:     Label  = $MarginContainer/VBox/LevelLabel
@onready var _income_label:    Label  = $MarginContainer/VBox/IncomeLabel
@onready var _upkeep_label:    Label  = $MarginContainer/VBox/UpkeepLabel
@onready var _pop_label:       Label  = $MarginContainer/VBox/PopLabel
@onready var _jobs_label:      Label  = $MarginContainer/VBox/JobsLabel
@onready var _occupants_label: Label  = $MarginContainer/VBox/OccupantsLabel
@onready var _occupants_list:  Label  = $MarginContainer/VBox/OccupantsList
@onready var _upgrade_button:  Button = $MarginContainer/VBox/UpgradeButton
@onready var _demolish_button: Button = $MarginContainer/VBox/DemolishButton

var _current_cell:     Vector2i = Vector2i(-1, -1)
var _current_building: Building = null

func _ready() -> void:
	visible = false
	add_to_group("ui_panels")
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_deselected.connect(_on_building_deselected)
	EventBus.house_info_requested.connect(_on_house_info_requested)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_demolish_button.pressed.connect(_on_demolish_pressed)
	_occupants_label.visible = false
	_occupants_list.visible  = false

# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_building_selected(building_data: BuildingData, cell: Vector2i) -> void:
	_current_cell = cell
	var gs: GridSystem = GameManager.grid_system
	_current_building  = gs.get_building_at(cell) if gs != null else null

	_name_label.text   = building_data.display_name
	_level_label.text  = "Nivel: %d / %d" % [
		_current_building.current_level if _current_building != null else 1,
		building_data.max_level
	]
	_income_label.text = "Ingresos: %d"       % building_data.income_per_tick
	_upkeep_label.text = "Mantenimiento: %d"  % building_data.upkeep_per_tick
	_pop_label.text    = "Vivienda: %d"        % building_data.population_capacity
	_jobs_label.text   = "Empleos: %d"         % building_data.jobs_provided

	# Reset occupants section — it will be filled by house_info_requested.
	_occupants_label.visible = false
	_occupants_list.visible  = false

	_upgrade_button.disabled = _current_building == null \
		or not _current_building.can_upgrade()
	visible = true

	# For residential buildings: request occupants immediately so the list
	# appears on the same click without waiting for HouseOccupancy's signal.
	if building_data.population_capacity > 0:
		var pop: PopulationSystem = GameManager.get_system("population")
		if pop != null and pop.house_occupancy != null:
			var origin: Vector2i = _current_building.cell \
				if _current_building != null else cell
			var occupants: Array = pop.house_occupancy.get_occupants(origin)
			_fill_occupants(occupants)

func _on_building_deselected() -> void:
	visible = false
	_current_cell     = Vector2i(-1, -1)
	_current_building = null
	_occupants_label.visible = false
	_occupants_list.visible  = false

## Always accepted — no cell filter so multiple houses work correctly.
func _on_house_info_requested(_house_cell: Vector2i, occupants: Array) -> void:
	if not visible:
		return
	_fill_occupants(occupants)

# ─── Occupants display ────────────────────────────────────────────────────────

func _fill_occupants(occupants: Array) -> void:
	_occupants_label.visible = true
	_occupants_list.visible  = true
	_occupants_label.text    = "Habitantes:"

	if occupants.is_empty():
		_occupants_list.text = "  (vacío)"
		return

	var lines: PackedStringArray = []
	for citizen in occupants:
		if not is_instance_valid(citizen) or citizen.stats == null:
			continue
		var icon:        String = "♂" if citizen.stats.gender == "male" else "♀"
		var child_tag:   String = " [niño]" if citizen.is_child else ""
		var partner_tag: String = ""
		if citizen.partner != null and is_instance_valid(citizen.partner) \
				and citizen.partner.stats != null:
			partner_tag = " ❤ %s" % citizen.partner.stats.citizen_name
		lines.append("  %s %s  edad %d%s%s" % [
			icon,
			citizen.stats.citizen_name,
			citizen.stats.age,
			child_tag,
			partner_tag
		])
	_occupants_list.text = "\n".join(lines)

# ─── Buttons ─────────────────────────────────────────────────────────────────

func _on_upgrade_pressed() -> void:
	if _current_building == null:
		return
	_current_building.upgrade()
	_upgrade_button.disabled = not _current_building.can_upgrade()

func _on_demolish_pressed() -> void:
	if _current_cell == Vector2i(-1, -1):
		return
	GameManager.grid_system.remove_building(_current_cell)
	visible = false
	_current_cell     = Vector2i(-1, -1)
	_current_building = null