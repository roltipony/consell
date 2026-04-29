## RockObject.gd
## A placeable rock/ore deposit. Workers from a Quarry travel here to mine it,
## yielding stone.
class_name RockObject
extends ResourceObject

func _build_mesh() -> Mesh:
	# Low, wide box to suggest a rock on the ground
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.55, 0.9)
	return bm

func _get_color() -> Color:
	return Color(0.48, 0.48, 0.50)  # Grey rock

func _get_half_height() -> float:
	return 0.275

func _setup_visuals() -> void:
	super._setup_visuals()
	# Add a small secondary boulder on top for visual interest
	var top := MeshInstance3D.new()
	top.name = "TopBoulder"
	var bm   := BoxMesh.new()
	bm.size  = Vector3(0.55, 0.35, 0.50)
	top.mesh = bm
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.40, 0.42)
	mat.roughness    = 0.95
	top.material_override = mat
	top.position.y = 0.45
	add_child(top)
