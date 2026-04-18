## Building.gd
## Base class for every building instance placed in the world.
class_name Building
extends Node3D

var data: BuildingData = null
var cell: Vector2i = Vector2i.ZERO
var current_level: int = 1
var is_operational: bool = true

var _mesh_instance: MeshInstance3D = null
var _selection_highlight: MeshInstance3D = null

func _ready() -> void:
	assert(data != null, "Building placed without BuildingData!")
	_setup_visuals()
	EventBus.new_day.connect(_on_new_day)

func initialize(building_data: BuildingData, grid_cell: Vector2i) -> void:
	data = building_data
	cell = grid_cell

func _setup_visuals() -> void:
	var mesh_cfg: Dictionary = data.mesh_config

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MeshInstance3D"
	_mesh_instance.mesh = _create_mesh(mesh_cfg)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(mesh_cfg.get("color", "#aaaaaa"))
	mat.roughness = 0.85
	mat.metallic = 0.0
	_mesh_instance.material_override = mat
	_mesh_instance.position.y = _get_half_height(mesh_cfg)
	add_child(_mesh_instance)

	# Highlight de selección
	_selection_highlight = MeshInstance3D.new()
	var hl_mesh := BoxMesh.new()
	var sz: Array = mesh_cfg.get("size", [1.8, 0.05, 1.8])
	hl_mesh.size = Vector3(float(sz[0]) + 0.12, 0.05, float(sz[2] if sz.size() > 2 else sz[0]) + 0.12)
	_selection_highlight.mesh = hl_mesh
	var hl_mat := StandardMaterial3D.new()
	hl_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.6)
	hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_highlight.material_override = hl_mat
	_selection_highlight.position.y = 0.03
	_selection_highlight.visible = false
	add_child(_selection_highlight)

func _create_mesh(cfg: Dictionary) -> Mesh:
	match cfg.get("type", "box"):
		"box":
			var bm := BoxMesh.new()
			var sz: Array = cfg.get("size", [1.8, 2.5, 1.8])
			bm.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2] if sz.size() > 2 else sz[0]))
			return bm
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius    = float(cfg.get("radius", 0.7))
			cm.bottom_radius = float(cfg.get("radius", 0.7))
			cm.height        = float(cfg.get("height", 3.0))
			return cm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = float(cfg.get("radius", 1.0))
			sm.height = float(cfg.get("radius", 1.0)) * 2.0
			return sm
		"prism":
			# Pirámide aproximada con PrismMesh
			var pm := PrismMesh.new()
			var sz: Array = cfg.get("size", [1.8, 2.0, 1.8])
			pm.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2] if sz.size() > 2 else sz[0]))
			return pm
	# fallback box
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 2.5, 1.8)
	return bm

func _get_half_height(cfg: Dictionary) -> float:
	match cfg.get("type", "box"):
		"box":
			var sz: Array = cfg.get("size", [1.8, 2.5, 1.8])
			return float(sz[1]) * 0.5
		"cylinder":
			return float(cfg.get("height", 3.0)) * 0.5
		"sphere":
			return float(cfg.get("radius", 1.0))
		"prism":
			var sz: Array = cfg.get("size", [1.8, 2.0, 1.8])
			return float(sz[1]) * 0.5
	return 1.25

func select() -> void:
	if _selection_highlight:
		_selection_highlight.visible = true
	EventBus.emit_signal("building_selected", data, cell)

func deselect() -> void:
	if _selection_highlight:
		_selection_highlight.visible = false
	EventBus.emit_signal("building_deselected")

func on_tick() -> void:
	pass

func _on_new_day(_day: int, _month: int, _year: int) -> void:
	on_tick()

func can_upgrade() -> bool:
	return current_level < data.max_level

func upgrade() -> void:
	if not can_upgrade():
		return
	current_level += 1
	_on_upgraded()
	EventBus.emit_signal("building_upgraded", data, cell)

func _on_upgraded() -> void:
	pass

func serialize() -> Dictionary:
	return {
		"building_id": data.id,
		"cell": [cell.x, cell.y],
		"level": current_level,
		"is_operational": is_operational,
	}

func deserialize(saved: Dictionary) -> void:
	current_level = saved.get("level", 1)
	is_operational = saved.get("is_operational", true)
	var c: Array = saved.get("cell", [0, 0])
	cell = Vector2i(c[0], c[1])
