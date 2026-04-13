## BuildButton.gd
## A button in the BuildMenu showing icon, name and cost of a building.
extends Button

@onready var icon_texture: TextureRect = $HBoxContainer/Icon
@onready var lbl_name:     Label       = $HBoxContainer/VBox/NameLabel
@onready var lbl_cost:     Label       = $HBoxContainer/VBox/CostLabel

func setup(bd_raw: Dictionary) -> void:
	if lbl_name: lbl_name.text = bd_raw.get("display_name", "?")
	if lbl_cost: lbl_cost.text = "💰 %d" % bd_raw.get("build_cost", 0)

	var icon_path: String = bd_raw.get("icon_path", "")
	if icon_texture and not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_texture.texture = load(icon_path)

	tooltip_text = bd_raw.get("description", "")

	var cost: int = bd_raw.get("build_cost", 0)
	if GameManager.economy_system and not GameManager.economy_system.can_afford(cost):
		modulate = Color(0.6, 0.6, 0.6, 1.0)
