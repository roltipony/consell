## Notification.gd
## Temporary toast notification shown in the HUD.
extends PanelContainer

@onready var lbl: Label = $MarginContainer/Label
@onready var anim: AnimationPlayer = $AnimationPlayer

const COLORS := {
	"info":    Color(0.2, 0.6, 1.0),
	"success": Color(0.2, 0.9, 0.3),
	"warning": Color(1.0, 0.8, 0.1),
	"error":   Color(1.0, 0.2, 0.2),
}

func show_message(message: String, type: String = "info") -> void:
	if lbl:
		lbl.text = message
		lbl.add_theme_color_override("font_color", COLORS.get(type, COLORS["info"]))
	visible = true
	if anim and anim.has_animation("fade_out"):
		anim.play("fade_out")
	else:
		# Fallback: auto-hide after 3 seconds via timer
		var t := get_tree().create_timer(3.0)
		t.timeout.connect(queue_free)
