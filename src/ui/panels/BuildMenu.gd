## BuildMenu.gd
## Side panel listing all available buildings grouped by category.
extends PanelContainer

@onready var category_tabs: TabContainer = $TabContainer
@onready var btn_close:     Button       = $Header/CloseButton

const BUILD_BUTTON_SCENE := "res://scenes/ui/BuildButton.tscn"

func _ready() -> void:
	if btn_close: btn_close.pressed.connect(_close)
	_populate_menu()
	visible = false
	EventBus.panel_open_requested.connect(_on_panel_open)
	EventBus.panel_close_requested.connect(_on_panel_close)

func _populate_menu() -> void:
	if not category_tabs: return

	for child in category_tabs.get_children():
		child.queue_free()

	var categories: Dictionary = {}
	for building_id in ConfigLoader.buildings:
		var bd_raw: Dictionary = ConfigLoader.buildings[building_id]
		var cat: String = bd_raw.get("category", "misc")
		if not categories.has(cat):
			categories[cat] = []
		categories[cat].append(bd_raw)

	for cat in categories:
		var scroll := ScrollContainer.new()
		scroll.name = cat.capitalize()
		var vbox := VBoxContainer.new()
		scroll.add_child(vbox)
		category_tabs.add_child(scroll)

		for bd_raw in categories[cat]:
			var btn_scene: PackedScene = load(BUILD_BUTTON_SCENE)
			if btn_scene == null:
				_add_fallback_button(vbox, bd_raw)
				continue
			var btn: Node = btn_scene.instantiate()
			vbox.add_child(btn)
			btn.setup(bd_raw)
			btn.pressed.connect(func(): _on_building_selected(bd_raw["id"]))

func _add_fallback_button(parent: Node, bd_raw: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "%s  💰%d" % [bd_raw.get("display_name", "?"), bd_raw.get("build_cost", 0)]
	btn.pressed.connect(func(): _on_building_selected(bd_raw["id"]))
	parent.add_child(btn)

func _on_building_selected(building_id: String) -> void:
	EventBus.emit_signal("build_mode_entered", building_id)
	_close()

func _close() -> void:
	visible = false

func _on_panel_open(panel_id: String, _data: Dictionary) -> void:
	if panel_id == "build_menu": visible = true

func _on_panel_close(panel_id: String) -> void:
	if panel_id == "build_menu": visible = false
