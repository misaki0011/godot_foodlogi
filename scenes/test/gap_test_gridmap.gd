extends Node3D

## Same diagnostic goal as gap_test.gd, but places the 2x2 grass blocks
## through an actual GridMap (the same mechanism -- MultiMesh instancing,
## cell_size scaling -- Main.tscn's TerrainRenderer uses), instead of by
## hand. Isolates whether GridMap's own rendering path behaves any
## differently from individually-placed instances at shared edges.

func _ready() -> void:
	var terrain := GridMap.new()
	terrain.name = "TerrainMap"
	terrain.set_script(load("res://scripts/terrain/terrain_renderer.gd"))
	add_child(terrain)
	var map_data := MapData.new()
	map_data.grid_size = Vector2i(2, 2)
	map_data.river_col = -1
	terrain.render(map_data)

	print("cell_size: ", terrain.cell_size)
	for cell in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
		var center: Vector3 = terrain.map_to_local(cell)
		print("cell %s: center=%s" % [cell, center])
