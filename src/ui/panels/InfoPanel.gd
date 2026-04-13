## InfoPanel.gd
## Displays the stats of the currently selected building.
extends PanelContainer

@onready var lbl_name:        Label  = $MarginContainer/VBox/NameLabel
@onready var lbl_description: Label  = $MarginContainer/VBox/DescLabel
@onready var lbl_level:       Label  = $MarginContainer/VBox/LevelLabel
@onready var lbl_income:      Label  = $MarginContainer/VBox/IncomeLabel
@onready var lbl_upkeep:      Label  = $MarginContainer/VBox/UpkeepLabel
@onready var lbl_population:  Label  = $MarginContainer/VBox/PopLabel
@onready var lbl_jobs:        Label  = $MarginContainer/VBox/JobsLabel
@onready var btn_upgrade:     Button = $MarginContainer/VBox/UpgradeButton
@onready var btn_demolish:    Button = $MarginContainer/VBox/DemolishButton

var _selected_building: Building = null

func _ready() -> void:
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_deselected.connect(_on_building_deselected)
	if btn_upgrade:  btn_upgrade.pressed.connect(_on_upgrade_pressed)
	if btn_demolish: btn_demolish.pressed.connect(_on_demolish_pressed)
	visible = false

func _on_building_selected(building_data: BuildingData, cell: Vector2i) -> void:
	_selected_building = GameManager.grid_system.get_building_at(cell)
	_refresh(building_data)
	visible = true

func _on_building_deselected() -> void:
	_selected_building = null
	visible = false

func _refresh(bd: BuildingData) -> void:
	if lbl_name:        lbl_name.text        = bd.display_name
	if lbl_description: lbl_description.text = bd.description
	if lbl_level:
		var lvl: int = _selected_building.current_level if _selected_building else 1
		lbl_level.text = "Level: %d / %d" % [lvl, bd.max_level]
	if lbl_income:     lbl_income.text     = "Income:  +%d / tick" % bd.income_per_tick
	if lbl_upkeep:     lbl_upkeep.text     = "Upkeep:  -%d / tick" % bd.upkeep_per_tick
	if lbl_population: lbl_population.text = "Housing: %d"         % bd.population_capacity
	if lbl_jobs:       lbl_jobs.text       = "Jobs:    %d"         % bd.jobs_provided

	if btn_upgrade:
		btn_upgrade.visible = bd.max_level > 1
		if _selected_building and _selected_building.can_upgrade():
			var lvl_idx: int = _selected_building.current_level - 1
			var cost: int = bd.upgrade_costs[lvl_idx] if lvl_idx < bd.upgrade_costs.size() else 0
			btn_upgrade.text     = "Upgrade  💰%d" % cost
			btn_upgrade.disabled = not GameManager.economy_system.can_afford(cost)
		else:
			btn_upgrade.text     = "Max Level"
			btn_upgrade.disabled = true

	if btn_demolish:
		btn_demolish.text = "Demolish (+%d 💰)" % bd.demolish_refund

func _on_upgrade_pressed() -> void:
	if _selected_building == null: return
	var bd: BuildingData = _selected_building.data
	var lvl_idx: int = _selected_building.current_level - 1
	if lvl_idx >= bd.upgrade_costs.size(): return
	var cost: int = bd.upgrade_costs[lvl_idx]
	if GameManager.economy_system.spend_gold(cost):
		_selected_building.upgrade()
		_refresh(bd)

func _on_demolish_pressed() -> void:
	if _selected_building == null: return
	var bd: BuildingData = _selected_building.data
	GameManager.economy_system.add_gold(bd.demolish_refund)
	GameManager.grid_system.remove_building(_selected_building.cell)
	_selected_building = null
	visible = false
