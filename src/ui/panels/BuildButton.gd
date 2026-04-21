## BuildButton.gd
## A button in the BuildMenu showing icon, name and cost of a building.
## setup() must be called after the node is added to the scene tree.
extends Button

func setup(bd_raw: Dictionary) -> void:
	var lbl_name:     Label       = get_node_or_null("HBoxContainer/VBox/NameLabel")
	var lbl_cost:     Label       = get_node_or_null("HBoxContainer/VBox/CostLabel")
	var icon_texture: TextureRect = get_node_or_null("HBoxContainer/Icon")

	if lbl_name: lbl_name.text = bd_raw.get("display_name", "?")
	if lbl_cost: lbl_cost.text = "💰 %d" % bd_raw.get("build_cost", 0)

	var icon_path: String = bd_raw.get("icon_path", "")
	if icon_texture and not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_texture.texture = load(icon_path)

	tooltip_text = bd_raw.get("description", "")

	var cost: int = bd_raw.get("build_cost", 0)
	if GameManager.economy_system and not GameManager.economy_system.can_afford(cost):
		modulate = Color(0.6, 0.6, 0.6, 1.0)