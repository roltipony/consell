## Notification.gd
## Toast notification that auto-dismisses after a duration.
extends PanelContainer

const COLORS: Dictionary = {
	"info":    Color(0.2, 0.5, 0.9),
	"success": Color(0.2, 0.75, 0.3),
	"warning": Color(0.95, 0.7, 0.1),
	"error":   Color(0.9, 0.2, 0.2),
}
const DISPLAY_SECONDS := 3.5

@onready var label:    Label           = $MarginContainer/Label
@onready var animator: AnimationPlayer = $AnimationPlayer

func show_message(message: String, type: String = "info") -> void:
	if label: label.text = message
	var col: Color = COLORS.get(type, COLORS["info"])
	add_theme_stylebox_override("panel", _make_style(col))
	if animator:
		animator.play("fade_in_out")
	else:
		await get_tree().create_timer(DISPLAY_SECONDS).timeout
		queue_free()

func _make_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.content_margin_left   = 12
	style.content_margin_right  = 12
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	return style

func _on_animation_finished(_anim_name: String) -> void:
	queue_free()
