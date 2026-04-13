## HUD.gd
## Controls the heads-up display: gold counter, population, happiness,
## speed controls, and the notification toaster.
extends CanvasLayer

# ─── Node refs (set in scene) ─────────────────────────────────────
@onready var lbl_gold:               Label         = $TopBar/GoldLabel
@onready var lbl_population:         Label         = $TopBar/PopulationLabel
@onready var lbl_happiness:          Label         = $TopBar/HappinessLabel
@onready var lbl_date:               Label         = $TopBar/DateLabel
@onready var btn_pause:              Button        = $SpeedBar/PauseButton
@onready var btn_slow:               Button        = $SpeedBar/SlowButton
@onready var btn_normal:             Button        = $SpeedBar/NormalButton
@onready var btn_fast:               Button        = $SpeedBar/FastButton
@onready var notification_container: VBoxContainer = $NotificationContainer

const NOTIFICATION_SCENE := "res://scenes/ui/Notification.tscn"
const HAPPINESS_ICONS: Dictionary = {
	"great":    "😄",
	"good":     "🙂",
	"neutral":  "😐",
	"bad":      "😟",
	"terrible": "😢",
}

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.happiness_changed.connect(_on_happiness_changed)
	EventBus.hud_notification.connect(_on_notification)
	EventBus.new_day.connect(_on_new_day)

	if btn_pause:  btn_pause.pressed.connect(func():  GameManager.set_speed(GameManager.GameSpeed.PAUSED))
	if btn_slow:   btn_slow.pressed.connect(func():   GameManager.set_speed(GameManager.GameSpeed.SLOW))
	if btn_normal: btn_normal.pressed.connect(func(): GameManager.set_speed(GameManager.GameSpeed.NORMAL))
	if btn_fast:   btn_fast.pressed.connect(func():   GameManager.set_speed(GameManager.GameSpeed.FAST))

# ─── Signal Handlers ──────────────────────────────────────────────
func _on_gold_changed(amount: int) -> void:
	if lbl_gold: lbl_gold.text = "💰 %d" % amount

func _on_population_changed(pop: int) -> void:
	if lbl_population: lbl_population.text = "👥 %d" % pop

func _on_happiness_changed(value: float) -> void:
	if not lbl_happiness: return
	var icon := "neutral"
	if value >= 0.8:   icon = "great"
	elif value >= 0.6: icon = "good"
	elif value >= 0.4: icon = "neutral"
	elif value >= 0.2: icon = "bad"
	else:              icon = "terrible"
	lbl_happiness.text = HAPPINESS_ICONS[icon] + " %.0f%%" % (value * 100)

func _on_new_day(day: int, month: int, year: int) -> void:
	if lbl_date: lbl_date.text = "📅 Y%d M%02d D%02d" % [year, month, day]

func _on_notification(message: String, type: String) -> void:
	if not notification_container: return
	var notif_scene: PackedScene = load(NOTIFICATION_SCENE)
	if notif_scene == null:
		push_warning("HUD: Notification scene not found at " + NOTIFICATION_SCENE)
		return
	var notif: Node = notif_scene.instantiate()
	notification_container.add_child(notif)
	notif.show_message(message, type)
