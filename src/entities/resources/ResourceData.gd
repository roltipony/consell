## ResourceData.gd
## Typed resource that holds static data for a single resource type.
## Instances are created from config/resources.json via ConfigLoader.
class_name ResourceData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var starting_amount: float = 0.0
@export var max_storage: float = 1000.0
@export var critical_threshold: float = 0.0
@export var happiness_penalty_per_unit_below_threshold: float = 0.0

static func from_dict(data: Dictionary) -> ResourceData:
	var rd := ResourceData.new()
	rd.id                                           = data.get("id", "")
	rd.display_name                                 = data.get("display_name", "")
	rd.description                                  = data.get("description", "")
	rd.icon_path                                    = data.get("icon_path", "")
	rd.starting_amount                              = data.get("starting_amount", 0.0)
	rd.max_storage                                  = data.get("max_storage", 1000.0)
	rd.critical_threshold                           = data.get("critical_threshold", 0.0)
	rd.happiness_penalty_per_unit_below_threshold   = data.get("happiness_penalty_per_unit_below_threshold", 0.0)
	return rd
