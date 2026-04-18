## HUD.gd
## In-game heads-up display: gold, population, happiness, time and notifications.
##
## Scene tree expected:
##   CanvasLayer
##     HUD (Control) ← this script
##       TopBar (HBoxContainer)
##         GoldLabel    (Label)
##         PopLabel     (Label)
##         HappyLabel   (Label)
##         TimeLabel    (Label)
##       NotificationContainer (VBoxContainer)
extends Control

@onready var lbl_gold:    Label         = $TopBar/GoldLabel
@onready var lbl_pop:     Label         = $TopBar/PopLabel
@onready var lbl_happy:   Label         = $TopBar/HappyLabel
@onready var lbl_time:    Label         = $TopBar/TimeLabel
@onready var notif_container: VBoxContainer = $NotificationContainer

const NOTIFICATION_SCENE := "res://scenes/ui/Notification.tscn"

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.happiness_changed.connect(_on_happiness_changed)
	EventBus.new_day.connect(_on_new_day)
	EventBus.hud_notification.connect(_on_notification)

func _on_gold_changed(amount: int) -> void:
	if lbl_gold: lbl_gold.text = "💰 %d" % amount

func _on_population_changed(pop: int) -> void:
	if lbl_pop: lbl_pop.text = "👥 %d" % pop

func _on_happiness_changed(value: float) -> void:
	if lbl_happy: lbl_happy.text = "😊 %.0f%%" % (value * 100.0)

func _on_new_day(day: int, month: int, year: int) -> void:
	if lbl_time: lbl_time.text = "📅 %d/%d/%d" % [day, month, year]

func _on_notification(message: String, type: String) -> void:
	if notif_container == null:
		return
	var scene: PackedScene = load(NOTIFICATION_SCENE)
	if scene == null:
		return
	var notif = scene.instantiate()
	notif_container.add_child(notif)
	if notif.has_method("show_message"):
		notif.show_message(message, type)
