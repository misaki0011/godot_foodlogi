class_name RouteSegmentData
extends Resource

## SPEC.md §16 RouteSegment.

@export var route_id: String
@export var from_node: String
@export var to_node: String
@export var length: int
@export var terrain_profile: Array[GameEnums.TerrainType] = []
@export var capacity: float
@export var base_upkeep: float
@export var tile_path: Array[Vector2i] = []
@export var route_level: int = 0
@export var build_cost: float
