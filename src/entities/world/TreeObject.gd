## TreeObject.gd
## A placeable tree. Workers from a Sawmill travel here to chop it, yielding wood.
class_name TreeObject
extends ResourceObject

func _build_mesh() -> Mesh:
	# Trunk: thin cylinder + canopy: sphere stacked on top
	# Since we can only return one mesh from _build_mesh, we build a composite
	# by using a CylinderMesh for the trunk. The canopy is added as a second
	# MeshInstance3D child in _setup_visuals override.
	var cm := CylinderMesh.new()
	cm.top_radius    = 0.12
	cm.bottom_radius = 0.16
	cm.height        = 1.0
	return cm

func _get_color() -> Color:
	return Color(0.42, 0.26, 0.10)  # Brown trunk

func _get_half_height() -> float:
	return 0.5

func _setup_visuals() -> void:
	super._setup_visuals()
	# Add green canopy sphere on top of trunk
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	var sm    := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	canopy.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.52, 0.10)
	mat.roughness    = 0.95
	canopy.material_override = mat
	canopy.position.y = 1.3
	add_child(canopy)
