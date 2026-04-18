## BuildMenu.gd
## Bottom-centered bar showing all available buildings grouped by category.
extends PanelContainer

@onready var category_tabs: TabBar        = $VBox/CategoryTabs
@onready var btn_row:       HBoxContainer = $VBox/Scroll/BtnRow
@onready var lbl_selected:  Label         = $VBox/BottomRow/SelectedLabel
@onready var btn_rotate:    Button        = $VBox/BottomRow/RotateButton
@onready var btn_cancel:    Button        = $VBox/BottomRow/CancelButton

const BUILD_BUTTON_SCENE := "res://scenes/ui/BuildButton.tscn"

var _categories: Array[String] = []
var _buildings_by_cat: Dictionary = {}
var _active_cat: int = 0
var _selected_id: String = ""

func _ready() -> void:
	add_to_group("ui_panels")

	EventBus.build_mode_entered.connect(_on_build_mode_entered)
	EventBus.build_mode_exited.connect(_on_build_mode_exited)
	EventBus.panel_open_requested.connect(_on_panel_open)
	EventBus.panel_close_requested.connect(_on_panel_close)

	if btn_rotate:    btn_rotate.pressed.connect(_on_rotate_pressed)
	if btn_cancel:    btn_cancel.pressed.connect(_on_cancel_pressed)
	if category_tabs: category_tabs.tab_changed.connect(_on_tab_changed)

	_build_category_data()
	_populate_tabs()
	_show_category(0)
	visible = true

func _build_category_data() -> void:
	_buildings_by_cat.clear()
	_categories.clear()
	for building_id in ConfigLoader.buildings:
		var bd: Dictionary = ConfigLoader.buildings[building_id]
		var cat: String = bd.get("category", "misc")
		if not _buildings_by_cat.has(cat):
			_buildings_by_cat[cat] = []
			_categories.append(cat)
		_buildings_by_cat[cat].append(bd)

func _populate_tabs() -> void:
	if not category_tabs: return
	while category_tabs.tab_count > 0:
		category_tabs.remove_tab(0)
	for cat in _categories:
		category_tabs.add_tab(cat.capitalize())

func _show_category(cat_index: int) -> void:
	if not btn_row: return
	for child in btn_row.get_children():
		child.queue_free()
	if cat_index < 0 or cat_index >= _categories.size():
		return
	_active_cat = cat_index
	var cat: String = _categories[cat_index]
	for bd_raw in _buildings_by_cat.get(cat, []):
		btn_row.add_child(_create_button(bd_raw))

func _create_button(bd_raw: Dictionary) -> Node:
	var btn_scene: PackedScene = load(BUILD_BUTTON_SCENE)
	if btn_scene:
		var btn: Node = btn_scene.instantiate()
		btn.setup(bd_raw)
		btn.pressed.connect(func(): _on_building_selected(bd_raw["id"]))
		return btn
	var btn := Button.new()
	btn.text = "%s  💰%d" % [bd_raw.get("display_name", "?"), bd_raw.get("build_cost", 0)]
	btn.pressed.connect(func(): _on_building_selected(bd_raw["id"]))
	return btn

func _on_building_selected(building_id: String) -> void:
	_selected_id = building_id
	_update_selected_label()
	EventBus.emit_signal("build_mode_entered", building_id)

func _on_rotate_pressed() -> void:
	if _selected_id.is_empty(): return
	EventBus.emit_signal("build_mode_rotate")

func _on_cancel_pressed() -> void:
	_selected_id = ""
	_update_selected_label()
	EventBus.emit_signal("build_mode_exited")

func _update_selected_label() -> void:
	if not lbl_selected: return
	if _selected_id.is_empty():
		lbl_selected.text = "Selecciona un edificio"
		return
	var raw: Dictionary = ConfigLoader.get_building(_selected_id)
	lbl_selected.text = "📐 %s  —  R para rotar" % raw.get("display_name", _selected_id)

func _on_tab_changed(tab: int) -> void:
	_show_category(tab)

func _on_build_mode_entered(_id: String) -> void:
	pass

func _on_build_mode_exited() -> void:
	_selected_id = ""
	_update_selected_label()

func _on_panel_open(panel_id: String, _data: Dictionary) -> void:
	if panel_id == "build_menu": visible = true

func _on_panel_close(panel_id: String) -> void:
	if panel_id == "build_menu": visible = false