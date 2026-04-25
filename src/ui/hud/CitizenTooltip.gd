## CitizenTooltip.gd
## Floating panel that appears under the cursor while hovering a citizen.
## Reads all stat labels from game_settings.json["citizen_ui"]["tooltip_stats"]
## so adding a new stat only requires a config entry.
##
## Scene tree (CitizenTooltip.tscn):
##   CanvasLayer
##     CitizenTooltip (Control) <- this script
##       Panel
##         MarginContainer
##           VBoxContainer
##             TitleLabel     (Label)
##             StatsContainer (VBoxContainer)  <- stat rows injected here at runtime
##
## Add this node to the "ui_panels" group so GameWorld._is_mouse_over_ui()
## counts the tooltip as UI and does not fire building placement through it.
class_name CitizenTooltip
extends Control

const TOOLTIP_OFFSET := Vector2(14.0, 14.0)

@onready var _title_label:     Label         = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var _stats_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/StatsContainer

## stat_id -> Label, built once from config in _ready().
var _stat_labels: Dictionary = {}
var _citizen: Citizen = null

func _ready() -> void:
	add_to_group("ui_panels")
	_build_stat_rows()
	hide()
	EventBus.citizen_hovered.connect(_on_citizen_hovered)
	EventBus.citizen_unhovered.connect(_on_citizen_unhovered)

func _process(_delta: float) -> void:
	if not visible:
		return
	if _citizen != null and is_instance_valid(_citizen):
		_refresh_stats()
	# Position tooltip just below and to the right of the cursor.
	var pos: Vector2 = get_viewport().get_mouse_position() + TOOLTIP_OFFSET
	# Clamp to viewport so it never clips off screen.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	pos.x = minf(pos.x, vp.x - size.x - 4.0)
	pos.y = minf(pos.y, vp.y - size.y - 4.0)
	global_position = pos

# --- EventBus handlers -------------------------------------------------------

func _on_citizen_hovered(citizen: Object) -> void:
	if not (citizen is Citizen):
		return
	_citizen = citizen as Citizen
	_refresh_title()
	_refresh_stats()
	show()

func _on_citizen_unhovered() -> void:
	_citizen = null
	hide()

# --- Content -----------------------------------------------------------------

func _refresh_title() -> void:
	if _citizen == null or _citizen.stats == null:
		return
	_title_label.text = "%s  Age %d" % [
		_citizen.stats.gender.capitalize(),
		_citizen.stats.age
	]

func _refresh_stats() -> void:
	if _citizen == null or _citizen.stats == null:
		return
	var values: Dictionary = _stat_snapshot(_citizen.stats)
	for stat_id in _stat_labels:
		if stat_id in values:
			(_stat_labels[stat_id] as Label).text = "%s: %s" % [
				_display_name(stat_id),
				_format_value(stat_id, values[stat_id])
			]

## Builds one Label row per stat listed in config, in config order.
## Config is the single source of truth -- no stat names are hardcoded.
func _build_stat_rows() -> void:
	var stat_ids: Array = ConfigLoader.game_settings \
		.get("citizen_ui", {}).get("tooltip_stats", _fallback_stat_list())
	for stat_id in stat_ids:
		var lbl := Label.new()
		lbl.name = "Stat_" + str(stat_id)
		_stats_container.add_child(lbl)
		_stat_labels[str(stat_id)] = lbl

## Returns current stat values from a CitizenStats instance as a flat dictionary.
## New stats only need to be added here and in config -- nothing else changes.
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

func _display_name(stat_id: String) -> String:
	var overrides: Dictionary = ConfigLoader.game_settings \
		.get("citizen_ui", {}).get("stat_display_names", {})
	return str(overrides.get(stat_id, stat_id.capitalize()))

func _format_value(stat_id: String, value: Variant) -> String:
	match stat_id:
		"happiness":
			return "%.0f%%" % (float(value) * 100.0)
		"speed", "sight":
			return "%.1f" % float(value)
		"health", "hunger", "thirst", "strength", "stamina":
			return "%.0f / %.0f" % [float(value),
				float(ConfigLoader.game_settings.get("citizen_stats", {})
					.get("max_" + stat_id, 50.0))]
		_:
			return str(value)

func _fallback_stat_list() -> Array:
	return ["health", "hunger", "thirst", "happiness",
			"speed", "strength", "stamina", "sight"]
