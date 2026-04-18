## SaveManager.gd
## Handles saving and loading game state to JSON files in user://saves/
extends Node

const SAVE_DIR  := "user://saves/"
const SLOT_COUNT := 5

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ── Public API ────────────────────────────────────────────────────

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

func save_game(slot: int) -> void:
	var data: Dictionary = {}
	if GameManager.economy_system:
		data["economy"] = GameManager.economy_system.serialize()
	if GameManager.population_system:
		data["population"] = GameManager.population_system.serialize()
	if GameManager.grid_system:
		data["grid"] = GameManager.grid_system.serialize()
	data["game_time"] = GameManager.game_time.serialize()

	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Cannot open slot %d for writing." % slot)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	EventBus.emit_signal("game_saved", slot)
	print("SaveManager: Game saved to slot %d." % slot)

func load_game(slot: int) -> void:
	if not slot_exists(slot):
		push_warning("SaveManager: Slot %d does not exist." % slot)
		return
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		push_error("SaveManager: Cannot open slot %d for reading." % slot)
		return
	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SaveManager: Failed to parse slot %d." % slot)
		return
	var data: Dictionary = json.data
	if GameManager.economy_system and data.has("economy"):
		GameManager.economy_system.deserialize(data["economy"])
	if GameManager.population_system and data.has("population"):
		GameManager.population_system.deserialize(data["population"])
	if GameManager.grid_system and data.has("grid"):
		GameManager.grid_system.deserialize(data["grid"])
	if data.has("game_time"):
		GameManager.game_time.deserialize(data["game_time"])
	EventBus.emit_signal("game_loaded", slot)
	print("SaveManager: Game loaded from slot %d." % slot)

func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ── Internal ──────────────────────────────────────────────────────

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot
