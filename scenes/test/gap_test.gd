extends Node3D

## Temporary diagnostic scene: places 4 raw Block_Grass.glb instances by
## hand (no GridMap involved) in a 2x2 grid, edge to edge, and prints each
## one's exact world position + world-space AABB so the numbers are
## verifiable, not just eyeballed from a screenshot. Not part of the game.

const BLOCK := preload("res://assets/Blocks/glTF/Block_Grass.glb")

func _ready() -> void:
	# Each block's raw mesh footprint is exactly 1x1 in local X/Z (verified:
	# AABB position (-0.5,-3.0,-0.5), size (1.0,3.61,1.0)), centered at its
	# own origin. Placing instance N's origin at world (x,0,z) makes it span
	# world X:[x-0.5, x+0.5], Z:[z-0.5, z+0.5] -- so centers at (0.5,0.5),
	# (0.5,1.5), (1.5,0.5), (1.5,1.5) give the requested 2x2, edge-to-edge,
	# 1-unit-cube layout: block A (0,0)-(1,1), block B (0,1)-(1,2) sharing
	# A's edge, block C (1,0)-(2,1), block D (1,1)-(2,2).
	var centers := {
		"A": Vector3(0.5, 0, 0.5),
		"B": Vector3(0.5, 0, 1.5),
		"C": Vector3(1.5, 0, 0.5),
		"D": Vector3(1.5, 0, 1.5),
	}
	for label in centers:
		var block: Node3D = BLOCK.instantiate()
		block.name = "Block_%s" % label
		add_child(block)
		block.position = centers[label]
		var mesh_instance := _find_mesh(block)
		var local_aabb := mesh_instance.mesh.get_aabb()
		var world_aabb := AABB(local_aabb.position + block.position, local_aabb.size)
		print("Block %s: origin=%s  world AABB: x=[%.2f,%.2f] z=[%.2f,%.2f]" % [
			label, block.position,
			world_aabb.position.x, world_aabb.position.x + world_aabb.size.x,
			world_aabb.position.z, world_aabb.position.z + world_aabb.size.z,
		])

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var f := _find_mesh(c)
		if f:
			return f
	return null
