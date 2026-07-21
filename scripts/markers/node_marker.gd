@tool
class_name NodeMarker
extends Node3D

## Shared behavior for all node/tile marker scenes. Per-type scenes provide
## their own visual mesh(es) under a child named "Visual"; this script just
## tints them. Used both for fixed source/settlement nodes (setup) and for
## player-built storage/hub grid tiles (apply_tint). No marker shows name
## text on the map: sources/settlements get speech bubbles instead
## (node_spawner.gd, main.gd), and storage/hub are distinguishable by tint
## and hover tooltip.

@export var node_data: NodeData

func setup(data: NodeData, tint: Color) -> void:
	node_data = data
	_tint_recursive_root(tint)

func apply_tint(color: Color) -> void:
	_tint_recursive_root(color)

func _tint_recursive_root(tint: Color) -> void:
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
