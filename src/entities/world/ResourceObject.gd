## ResourceObject.gd
## Base class for placeable world objects that can be harvested (trees, rocks).
##
## Resource objects are NOT buildings — they don't use BuildingData and are
## tracked in a separate registry (ResourceObjectRegistry).
## They are placed by the player via a dedicated placement tool (same ghost
## preview flow as buildings, but via a separate action).
##
## When a worker arrives and calls harvest(), the object removes itself from
## the registry, adds the yield to the economy, and calls queue_free().
class_name ResourceObject
extends Node3D

# ─── Config (set before _ready by the registry) ───────────────────────────────
## Type identifier — must match a key in config/resource_objects.json.
var object_type: String = ""
## Grid cell this object occupies (1×1).
var cell: Vector2i = Vector2i.ZERO
## How many resource units are produced on harvest.
var yield_amount: float = 1.0
## Which economy resource id is produced.
var yield_resource_id: String = ""

# ─── Visuals ─────────────────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _selection_highlight: MeshInstance3D = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_visuals()

func initialize(type: String, grid_cell: Vector2i, cfg: Dictionary) -> void:
	object_type       = type
	cell              = grid_cell
	yield_amount      = float(cfg.get("yield_amount", 1.0))
	yield_resource_id = cfg.get("yield_resource_id", "wood")

# ─── Visuals (overridden by subclasses to customise mesh) ─────────────────────
func _setup_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = _build_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_color()
	mat.roughness    = 0.9
	_mesh_instance.material_override = mat
	_mesh_instance.position.y        = _get_half_height()
	add_child(_mesh_instance)

	_selection_highlight = MeshInstance3D.new()
	var hl_mesh := BoxMesh.new()
	hl_mesh.size = Vector3(1.8, 0.05, 1.8)
	_selection_highlight.mesh = hl_mesh
	var hl_mat := StandardMaterial3D.new()
	hl_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.6)
	hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_highlight.material_override = hl_mat
	_selection_highlight.position.y        = 0.03
	_selection_highlight.visible           = false
	add_child(_selection_highlight)

## Subclasses override to provide a distinct mesh.
func _build_mesh() -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.0, 0.6)
	return bm

func _get_color() -> Color:
	return Color(0.2, 0.6, 0.1)

func _get_half_height() -> float:
	return 0.5

# ─── Selection ────────────────────────────────────────────────────────────────
func select() -> void:
	if _selection_highlight:
		_selection_highlight.visible = true

func deselect() -> void:
	if _selection_highlight:
		_selection_highlight.visible = false

# ─── Harvest ─────────────────────────────────────────────────────────────────
## Called by a worker when they arrive and complete the harvest action.
## Adds resources to the economy and removes this object from the world.
func harvest() -> void:
	var eco: EconomySystem = GameManager.get_system("economy")
	if eco != null and yield_resource_id != "":
		eco.add_resource(yield_resource_id, yield_amount)
	EventBus.emit_signal("resource_object_removed", object_type, cell)
	queue_free()
