## MainMenu.gd
## Entry-point menu: New Game, Load Game, Settings, Quit.
extends Control

const GAME_WORLD_SCENE := "res://scenes/main/GameWorld.tscn"

@onready var btn_new_game:  Button = $VBoxContainer/NewGameButton
@onready var btn_load_game: Button = $VBoxContainer/LoadGameButton
@onready var btn_settings:  Button = $VBoxContainer/SettingsButton
@onready var btn_quit:      Button = $VBoxContainer/QuitButton
@onready var lbl_version:   Label  = $VersionLabel

func _ready() -> void:
	if lbl_version:   lbl_version.text     = "v" + ProjectSettings.get_setting("application/config/version", "?")
	if btn_new_game:  btn_new_game.pressed.connect(_on_new_game)
	if btn_load_game:
		btn_load_game.pressed.connect(_on_load_game)
		btn_load_game.disabled = not SaveManager.slot_exists(0)
	if btn_settings:  btn_settings.pressed.connect(_on_settings)
	if btn_quit:      btn_quit.pressed.connect(_on_quit)

func _on_new_game() -> void:
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)

func _on_load_game() -> void:
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)

func _on_settings() -> void:
	EventBus.emit_signal("panel_open_requested", "settings", {})

func _on_quit() -> void:
	get_tree().quit()
