## GameManager.gd
## Singleton that owns the top-level game state and coordinates all systems.
## Does NOT contain game logic itself — delegates to specialised systems.
extends Node

# ─── Constants ────────────────────────────────────────────────────
const SETTINGS_PATH := "user://settings.cfg"
const TICK_INTERVAL_SECONDS := 3.0  # Real-time seconds per game tick

# ─── Game Speed presets (multipliers over TICK_INTERVAL) ──────────
enum GameSpeed { PAUSED = 0, SLOW = 1, NORMAL = 2, FAST = 3 }

# ─── State ────────────────────────────────────────────────────────
var current_speed: GameSpeed = GameSpeed.NORMAL
var is_paused: bool = false
var game_time: GameTime = GameTime.new()

# ─── System references (populated by GameWorld scene) ──────────────
var economy_system: Node = null
var population_system: Node = null
var grid_system: Node = null
var event_system: Node = null

# ─── Internal ─────────────────────────────────────────────────────
var _tick_timer: float = 0.0
var _speed_multipliers: Dictionary = {
	GameSpeed.PAUSED: 0.0,
	GameSpeed.SLOW:   0.5,
	GameSpeed.NORMAL: 1.0,
	GameSpeed.FAST:   3.0,
}

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.game_speed_changed.connect(_on_game_speed_changed)

func _process(delta: float) -> void:
	if is_paused or current_speed == GameSpeed.PAUSED:
		return
	_tick_timer += delta * _speed_multipliers[current_speed]
	if _tick_timer >= TICK_INTERVAL_SECONDS:
		_tick_timer -= TICK_INTERVAL_SECONDS
		_process_game_tick()

# ─── Tick ─────────────────────────────────────────────────────────
func _process_game_tick() -> void:
	game_time.advance_tick()
	if economy_system:
		economy_system.process_tick()
	if population_system:
		population_system.process_tick()
	if event_system:
		event_system.process_tick()

# ─── Public API ───────────────────────────────────────────────────
func set_speed(speed: GameSpeed) -> void:
	current_speed = speed
	EventBus.emit_signal("game_speed_changed", _speed_multipliers[speed])

func pause(value: bool) -> void:
	is_paused = value
	EventBus.emit_signal("game_paused", value)

func register_system(system_name: String, node: Node) -> void:
	match system_name:
		"economy":    economy_system    = node
		"population": population_system = node
		"grid":       grid_system       = node
		"events":     event_system      = node
		_:
			push_warning("GameManager: Unknown system '%s'" % system_name)

# ─── Signal Handlers ──────────────────────────────────────────────
func _on_game_paused(paused: bool) -> void:
	is_paused = paused

func _on_game_speed_changed(_speed: float) -> void:
	pass  # Reserved for future use
