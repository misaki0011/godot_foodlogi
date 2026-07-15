class_name NodeMarker
extends Node3D

## Shared behavior for all node/tile marker scenes. Per-type scenes provide
## their own visual mesh(es) under a child named "Visual"; this script just
## labels and tints them. Used both for fixed source/settlement nodes
## (setup) and for player-built storage/hub grid tiles (apply_tint).

@export var node_data: NodeData

func setup(data: NodeData, tint: Color) -> void:
	node_data = data
	_apply(data.display_name, tint)

func apply_tint(color: Color, label_text: String = "") -> void:
	_apply(label_text, color)

func _apply(label_text: String, tint: Color) -> void:
	if label_text != "":
		var label: Label3D = get_node_or_null("Label3D")
		if label:
			label.text = label_text
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
