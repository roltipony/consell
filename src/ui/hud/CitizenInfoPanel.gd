## CitizenInfoPanel.gd
## Fixed panel anchored to the bottom-right of the screen.
## Shows full stats of the selected citizen and a "Stop Following" button.
##
## Scene tree (node inside HUD.tscn as CitizenInfoPanel):
##   CitizenInfoPanel (PanelContainer) <- this script
##     MarginContainer
##       VBoxContainer
##         HeaderRow (HBoxContainer)
##           TitleLabel   (Label)
##           CloseButton  (Button)  text="X"
##         Divider        (HSeparator)
##         StatsGrid      (GridContainer) columns=2
##         FollowButton   (Button)  text="Follow"
##
## This node must be in the "ui_panels" group.
class_name CitizenInfoPanel
extends PanelContainer

@onready var _title_label:  Label         = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var _close_btn:    Button        = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var _stats_grid:   GridContainer = $MarginContainer/VBoxContainer/StatsGrid
@onready var _follow_btn:   Button        = $MarginContainer/VBoxContainer/FollowButton

## stat_id -> value Label (the key Label is created alongside it).
var _value_labels: Dictionary = {}
var _citizen: Citizen = null
var _following: bool = false

func _ready() -> void:
	add_to_group("ui_panels")
	_build_stat_rows()
	_close_btn.pressed.connect(_on_close_pressed)
	_follow_btn.pressed.connect(_on_follow_pressed)
	hide()
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.citizen_deselected.connect(_on_citizen_deselected)
	EventBus.citizen_died.connect(_on_citizen_died_panel)

func _process(_delta: float) -> void:
	if not visible:
		return
	if _citizen != null and is_instance_valid(_citizen):
		_refresh_stats()

# --- EventBus handlers -------------------------------------------------------

func _on_citizen_selected(citizen: Object) -> void:
	if not (citizen is Citizen):
		return
	_citizen = citizen as Citizen
	_following = true
	_follow_btn.text = _follow_label(true)
	_refresh_title()
	_refresh_stats()
	show()

func _on_citizen_deselected() -> void:
	_citizen = null
	_following = false
	hide()

func _on_citizen_died_panel(citizen: Object, _cause: String) -> void:
	if citizen == _citizen:
		_citizen = null
		hide()

# --- Button callbacks --------------------------------------------------------

func _on_close_pressed() -> void:
	EventBus.emit_signal("citizen_deselected")

func _on_follow_pressed() -> void:
	_following = not _following
	_follow_btn.text = _follow_label(_following)
	var cam: CameraController = GameManager.get_system("camera") as CameraController
	if cam == null:
		return
	if _following and _citizen != null and is_instance_valid(_citizen):
		cam.follow(_citizen)
	else:
		cam.release_follow()

# --- Content -----------------------------------------------------------------

func _refresh_title() -> void:
	if _citizen == null or _citizen.stats == null:
		return
	_title_label.text = "Citizen  |  %s  Age %d" % [
		_citizen.stats.gender.capitalize(),
		_citizen.stats.age
	]

func _refresh_stats() -> void:
	if _citizen == null or _citizen.stats == null:
		return
	var values: Dictionary = _stat_snapshot(_citizen.stats)
	for stat_id in _value_labels:
		if stat_id in values:
			(_value_labels[stat_id] as Label).text = _format_value(stat_id, values[stat_id])

## Builds a two-column grid: key label on the left, value label on the right.
## Stat list and display names come entirely from config.
func _build_stat_rows() -> void:
	var stat_ids: Array = ConfigLoader.game_settings \
		.get("citizen_ui", {}).get("panel_stats", _fallback_stat_list())
	var display_names: Dictionary = ConfigLoader.game_settings \
		.get("citizen_ui", {}).get("stat_display_names", {})

	for stat_id in stat_ids:
		var key_lbl := Label.new()
		key_lbl.text = str(display_names.get(stat_id, str(stat_id).capitalize())) + ":"
		_stats_grid.add_child(key_lbl)

		var val_lbl := Label.new()
		val_lbl.name = "Val_" + str(stat_id)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(val_lbl)
		_value_labels[str(stat_id)] = val_lbl

func _stat_snapshot(s: CitizenStats) -> Dictionary:
	return {
		"health":    s.health,
		"hunger":    s.hunger,
		"thirst":    s.thirst,
		"happiness": s.happiness,
		"speed":     s.speed,
		"strength":  s.strength,
		"stamina":   s.stamina,
		"sight":     s.sight,
		"age":       s.age,
		"gender":    s.gender,
	}

func _format_value(stat_id: String, value: Variant) -> String:
	var cfg_stats: Dictionary = ConfigLoader.game_settings.get("citizen_stats", {})
	match stat_id:
		"happiness":
			return "%.0f%%" % (float(value) * 100.0)
		"speed", "sight":
			return "%.1f" % float(value)
		"health", "hunger", "thirst", "strength", "stamina":
			var max_val: float = float(cfg_stats.get("max_" + stat_id, 50.0))
			return "%.0f / %.0f" % [float(value), max_val]
		_:
			return str(value)

func _follow_label(following: bool) -> String:
	return "Unfollow" if following else "Follow"

func _fallback_stat_list() -> Array:
	return ["health", "hunger", "thirst", "happiness",
			"speed", "strength", "stamina", "sight", "age", "gender"]
