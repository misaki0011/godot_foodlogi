class_name NodeMarker
extends Node3D

## Shared behavior for all node marker scenes. Per-type scenes provide
## their own visual mesh(es) under a child named "Visual"; this script
## just labels and tints them.

@export var node_data: NodeData

func setup(data: NodeData, tint: Color) -> void:
	node_data = data
	var label: Label3D = get_node_or_null("Label3D")
	if label:
		label.text = data.display_name
	var visual := get_node_or_null("Visual")
	if visual:
		_tint_recursive(visual, tint)

func _tint_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		node.material_override = mat
	for child in node.get_children():
		_tint_recursive(child, color)
