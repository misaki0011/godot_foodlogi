@tool
class_name MapData
extends Resource

## Single source of truth for a region's terrain + node layout, matching
## fresh-routes-mvp.html's map: an open grid with a single river column
## (bridges auto-build when a route crosses it) and fixed source/settlement
## placements. Both TerrainRenderer and NodeSpawner read this resource.

@export var grid_size: Vector2i
@export var river_col: int = -1
@export var node_placements: Array[NodeData] = []

func get_terrain(x: int, _y: int) -> GameEnums.TerrainType:
	return GameEnums.TerrainType.RIVER if x == river_col else GameEnums.TerrainType.PLAINS

func is_river(x: int, _y: int) -> bool:
	return x == river_col
