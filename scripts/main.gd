extends Node3D

const REGION_MAP_PATH := "res://data/maps/region_1_map.tres"

@onready var _terrain: TerrainRenderer = $TerrainMap
@onready var _node_spawner: NodeSpawner = $NodeMarkers

func _ready() -> void:
	var map_data: MapData = load(REGION_MAP_PATH)
	_terrain.render(map_data)
	_node_spawner.spawn(map_data, _terrain)
