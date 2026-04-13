## ConfigLoader.gd
## Autoload that reads all JSON configuration files from res://config/
## and exposes them as typed dictionaries.  Nothing is hardcoded here;
## every numeric constant lives in a JSON file.
extends Node

const CONFIG_DIR := "res://config/"

var buildings: Dictionary = {}
var terrain_types: Dictionary = {}
var resources: Dictionary = {}
var events: Dictionary = {}
var game_settings: Dictionary = {}
var zone_rules: Dictionary = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	buildings     = _load_json("buildings.json")
	terrain_types = _load_json("terrain_types.json")
	resources     = _load_json("resources.json")
	events        = _load_json("events.json")
	game_settings = _load_json("game_settings.json")
	zone_rules    = _load_json("zone_rules.json")

func _load_json(filename: String) -> Dictionary:
	var path := CONFIG_DIR + filename
	if not FileAccess.file_exists(path):
		push_warning("ConfigLoader: '%s' not found, returning empty dict." % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ConfigLoader: Failed to parse '%s': %s" % [path, json.get_error_message()])
		return {}
	return json.data

## Returns the raw dict for a single building by its id.
func get_building(building_id: String) -> Dictionary:
	return buildings.get(building_id, {})

## Returns the raw dict for a single resource by its id.
func get_resource(resource_id: String) -> Dictionary:
	return resources.get(resource_id, {})

## Hot-reload all configs (useful during development).
func reload() -> void:
	_load_all()
	print("ConfigLoader: All configs reloaded.")
