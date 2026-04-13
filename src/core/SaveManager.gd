## SaveManager.gd
## Handles serialisation and deserialisation of the full game state.
## Save slots are stored under user://saves/slot_N.json
extends Node

const SAVE_DIR  := "user://saves/"
const SLOT_COUNT := 5

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ─── Public API ───────────────────────────────────────────────────
func save_game(slot: int) -> void:
	assert(slot >= 0 and slot < SLOT_COUNT, "Invalid save slot")
	var data := _collect_state()
	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	EventBus.emit_signal("game_saved", slot)

func load_game(slot: int) -> void:
	assert(slot >= 0 and slot < SLOT_COUNT, "Invalid save slot")
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_error("SaveManager: No save file at slot %d" % slot)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	_apply_state(json.data)
	EventBus.emit_signal("game_loaded", slot)

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ─── Internals ────────────────────────────────────────────────────
func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot

func _collect_state() -> Dictionary:
	return {
		"version":    ProjectSettings.get_setting("application/config/version"),
		"time":       GameManager.game_time.to_dict(),
		"economy":    GameManager.economy_system.serialize()    if GameManager.economy_system    else {},
		"population": GameManager.population_system.serialize() if GameManager.population_system else {},
		"grid":       GameManager.grid_system.serialize()       if GameManager.grid_system       else {},
	}

func _apply_state(data: Dictionary) -> void:
	GameManager.game_time.from_dict(data.get("time", {}))
	if GameManager.economy_system    and data.has("economy"):
		GameManager.economy_system.deserialize(data["economy"])
	if GameManager.population_system and data.has("population"):
		GameManager.population_system.deserialize(data["population"])
	if GameManager.grid_system       and data.has("grid"):
		GameManager.grid_system.deserialize(data["grid"])
