class_name MapData
extends Resource

## Single source of truth for a region's terrain + node layout.
## Both TerrainRenderer and NodeSpawner read this resource, so future
## gameplay systems (routes, node lookups) can query it too instead of
## re-deriving state from the scene tree.

const TERRAIN_CHARS := {
	".": GameEnums.TerrainType.PLAINS,
	"F": GameEnums.TerrainType.FOREST,
	"M": GameEnums.TerrainType.MOUNTAIN,
	"R": GameEnums.TerrainType.RIVER,
	"S": GameEnums.TerrainType.SNOW,
}

@export var grid_size: Vector2i
## One string per row (terrain_rows[y]), one character per column.
@export var terrain_rows: PackedStringArray = []
@export var node_placements: Array[NodeData] = []

func get_terrain(x: int, y: int) -> GameEnums.TerrainType:
	var row := terrain_rows[y]
	var ch := row.substr(x, 1)
	return TERRAIN_CHARS.get(ch, GameEnums.TerrainType.PLAINS)
