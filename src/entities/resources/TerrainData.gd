## TerrainData.gd
## Typed resource holding static data for a terrain tile type.
class_name TerrainData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var buildable: bool = true
@export var movement_cost: float = 1.0
@export var tile_atlas_coords: Vector2i = Vector2i.ZERO
@export var happiness_modifier: float = 0.0
@export var resource_yield: Dictionary = {}   # resource_id → amount per tick
@export var farm_yield_bonus: float = 1.0

static func from_dict(data: Dictionary) -> TerrainData:
	var td := TerrainData.new()
	td.id                = data.get("id",                "")
	td.display_name      = data.get("display_name",      "")
	td.buildable         = data.get("buildable",         true)
	td.movement_cost     = data.get("movement_cost",     1.0)
	td.happiness_modifier = data.get("happiness_modifier", 0.0)
	td.resource_yield    = data.get("resource_yield",    {})
	td.farm_yield_bonus  = data.get("farm_yield_bonus",  1.0)
	var coords: Array    = data.get("tile_atlas_coords", [0, 0])
	td.tile_atlas_coords = Vector2i(coords[0], coords[1])
	return td
