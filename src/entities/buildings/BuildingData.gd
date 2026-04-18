## BuildingData.gd
## Resource that holds all static data for a building type.
class_name BuildingData
extends Resource

# ─── Identity ─────────────────────────────────────────────────────
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var category: String = ""
@export var icon_path: String = ""
@export var scene_path: String = ""

# ─── Grid ─────────────────────────────────────────────────────────
@export var size: Vector2i = Vector2i(1, 1)

# ─── Cost & Upkeep ────────────────────────────────────────────────
@export var build_cost: int = 0
@export var demolish_refund: int = 0
@export var upkeep_per_tick: int = 0

# ─── Production / Effects ─────────────────────────────────────────
@export var income_per_tick: int = 0
@export var population_capacity: int = 0
@export var jobs_provided: int = 0
@export var happiness_modifier: float = 0.0
@export var resource_production: Dictionary = {}
@export var resource_consumption: Dictionary = {}

# ─── Requirements ─────────────────────────────────────────────────
@export var requires_road: bool = false
@export var requires_power: bool = false
@export var requires_water: bool = false
@export var unlock_level: int = 0

# ─── Upgrades ─────────────────────────────────────────────────────
@export var max_level: int = 1
@export var upgrade_costs: Array[int] = []

# ─── 3D Visual ────────────────────────────────────────────────────
@export var mesh_config: Dictionary = {}

# ─── Factory ──────────────────────────────────────────────────────
static func from_dict(data: Dictionary) -> BuildingData:
	var bd := BuildingData.new()
	bd.id                   = data.get("id",                   "")
	bd.display_name         = data.get("display_name",         "")
	bd.description          = data.get("description",          "")
	bd.category             = data.get("category",             "")
	bd.icon_path            = data.get("icon_path",            "")
	bd.scene_path           = data.get("scene_path",           "")
	var sz: Array           = data.get("size",                 [1, 1])
	bd.size                 = Vector2i(sz[0], sz[1])
	bd.build_cost           = data.get("build_cost",           0)
	bd.demolish_refund      = data.get("demolish_refund",      0)
	bd.upkeep_per_tick      = data.get("upkeep_per_tick",      0)
	bd.income_per_tick      = data.get("income_per_tick",      0)
	bd.population_capacity  = data.get("population_capacity",  0)
	bd.jobs_provided        = data.get("jobs_provided",        0)
	bd.happiness_modifier   = data.get("happiness_modifier",   0.0)
	bd.resource_production  = data.get("resource_production",  {})
	bd.resource_consumption = data.get("resource_consumption", {})
	bd.requires_road        = data.get("requires_road",        false)
	bd.requires_power       = data.get("requires_power",       false)
	bd.requires_water       = data.get("requires_water",       false)
	bd.unlock_level         = data.get("unlock_level",         0)
	bd.max_level            = data.get("max_level",            1)
	var raw_costs: Array    = data.get("upgrade_costs",        [])
	bd.upgrade_costs.assign(raw_costs)
	bd.mesh_config          = data.get("mesh",                 {})
	return bd
