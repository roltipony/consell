## HUD.gd
## In-game heads-up display: gold, population, citizens, happiness, food, time and notifications.
##
## Scene tree expected:
##   CanvasLayer
##     HUD (Control) ← this script
##       TopBar (HBoxContainer)
##         GoldLabel      (Label)
##         PopLabel       (Label)
##         CitizensLabel  (Label)
##         HappyLabel     (Label)
##         FoodLabel      (Label)
##         TimeLabel      (Label)
##       NotificationContainer (VBoxContainer)
extends Control

@onready var lbl_gold:        Label         = $TopBar/GoldLabel
@onready var lbl_pop:         Label         = $TopBar/PopLabel
@onready var lbl_citizens:    Label         = $TopBar/CitizensLabel
@onready var lbl_happy:       Label         = $TopBar/HappyLabel
@onready var lbl_food:        Label         = $TopBar/FoodLabel
@onready var lbl_time:        Label         = $TopBar/TimeLabel
@onready var notif_container: VBoxContainer = $NotificationContainer

const NOTIFICATION_SCENE := "res://scenes/ui/Notification.tscn"

var _citizen_count: int = 0

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.happiness_changed.connect(_on_happiness_changed)
	EventBus.new_day.connect(_on_new_day)
	EventBus.hud_notification.connect(_on_notification)
	EventBus.citizen_spawned.connect(_on_citizen_spawned)
	EventBus.citizen_despawned.connect(_on_citizen_despawned)
	EventBus.resource_changed.connect(_on_resource_changed)

func _on_gold_changed(amount: int) -> void:
	if lbl_gold: lbl_gold.text = "💰 %d" % amount

func _on_population_changed(pop: int) -> void:
	if lbl_pop: lbl_pop.text = "👥 %d" % pop

func _on_happiness_changed(value: float) -> void:
	if lbl_happy: lbl_happy.text = "😊 %.0f%%" % (value * 100.0)

func _on_new_day(day: int, month: int, year: int) -> void:
	if lbl_time: lbl_time.text = "📅 %d/%d/%d" % [day, month, year]

func _on_citizen_spawned(_citizen: Object, _cell: Vector2i) -> void:
	_citizen_count += 1
	_update_citizens_label()

func _on_citizen_despawned(_citizen: Object, _cell: Vector2i) -> void:
	_citizen_count = maxi(_citizen_count - 1, 0)
	_update_citizens_label()

func _update_citizens_label() -> void:
	if lbl_citizens: lbl_citizens.text = "🚶 %d" % _citizen_count

func _on_resource_changed(resource_id: String, amount: float) -> void:
	if resource_id == "food":
		if lbl_food: lbl_food.text = "🌾 %d" % int(amount)

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