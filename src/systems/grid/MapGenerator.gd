## MapGenerator.gd
## Procedurally fills the TileMapLayer on game start.
class_name MapGenerator
extends Node

const CFG_KEY := "map_generator"
const TILE_SOURCE_ID := 0

const TERRAIN_ATLAS: Dictionary = {
	"grass":    Vector2i(0, 0),
	"fertile":  Vector2i(1, 0),
	"forest":   Vector2i(2, 0),
	"sand":     Vector2i(3, 0),
	"water":    Vector2i(4, 0),
	"mountain": Vector2i(5, 0),
}

var _noise: FastNoiseLite = FastNoiseLite.new()
var _seed:             int   = 0
var _water_thresh:     float = -0.35
var _mountain_thresh:  float = 0.55
var _forest_thresh:    float = 0.25
var _sand_thresh:      float = -0.20
var _fertile_thresh:   float = 0.10

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	_seed            = cfg.get("seed",               0)
	_water_thresh    = cfg.get("water_threshold",    _water_thresh)
	_mountain_thresh = cfg.get("mountain_threshold", _mountain_thresh)
	_forest_thresh   = cfg.get("forest_threshold",   _forest_thresh)
	_sand_thresh     = cfg.get("sand_threshold",     _sand_thresh)
	_fertile_thresh  = cfg.get("fertile_threshold",  _fertile_thresh)

func generate(tilemap: TileMapLayer, width: int, height: int) -> void:
	if tilemap == null:
		push_error("MapGenerator: tilemap is null")
		return
	if tilemap.tile_set == null:
		push_error("MapGenerator: TileMapLayer has no TileSet assigned. Assign one in the editor first.")
		return

	# Verify the atlas source exists
	if tilemap.tile_set.get_source_count() == 0:
		push_error("MapGenerator: TileSet has no atlas sources. Add grass.png as an atlas in the TileSet editor.")
		return

	_noise.seed       = _seed if _seed != 0 else randi()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency  = 0.05

	var cells_painted: int = 0
	for x in range(width):
		for y in range(height):
			var cell: Vector2i  = Vector2i(x, y)
			var terrain: String = _terrain_for(x, y)
			# Fallback to grass if terrain not in atlas yet
			var atlas: Vector2i = TERRAIN_ATLAS.get(terrain, Vector2i(0, 0))
			# Check source has this tile before setting
			var source_id: int = tilemap.tile_set.get_source_id(0)
			tilemap.set_cell(cell, source_id, atlas)
			cells_painted += 1

	print("MapGenerator: painted %d cells" % cells_painted)
	# Center camera hint
	var center_world: Vector2 = tilemap.map_to_local(Vector2i(width / 2, height / 2))
	print("MapGenerator: map center is at world pos %s — point your camera here" % str(center_world))

func _terrain_for(x: int, y: int) -> String:
	var v: float = _noise.get_noise_2d(float(x), float(y))
	if v < _water_thresh:    return "water"
	if v > _mountain_thresh: return "mountain"
	if v > _forest_thresh:   return "forest"
	if v < _sand_thresh:     return "sand"
	if v > _fertile_thresh:  return "fertile"
	return "grass"
