@tool
class_name NodeSpawner
extends Node3D

## Instantiates a marker scene per fixed source/settlement node, positioned
## via the GridMap's own map_to_local() so markers align exactly to terrain
## cells without manual grid math. Player-built route/storage/hub tiles are
## rendered separately (see Main._render_grid) since they live in
## GameState.grid, not MapData.node_placements. Supply/demand speech
## bubbles are rendered by Main._render_supply_bubbles instead, since they
## need to be rebuilt every simulated day, not just once at spawn time.

const MARKER_SCENES := {
	GameEnums.NodeType.SOURCE: preload("res://scenes/markers/source_marker.tscn"),
	GameEnums.NodeType.SETTLEMENT: preload("res://scenes/markers/settlement_marker.tscn"),
}

func spawn(map_data: MapData, gridmap: GridMap) -> void:
	for child in get_children():
		child.queue_free()
	for node_data in map_data.node_placements:
		var scene: PackedScene = MARKER_SCENES.get(node_data.node_type)
		if scene == null:
			push_warning("NodeSpawner: no marker scene for node_type %s" % node_data.node_type)
			continue
		var marker: NodeMarker = scene.instantiate()
		add_child(marker)
		var cell := Vector3i(node_data.grid_position.x, 0, node_data.grid_position.y)
		marker.position = gridmap.map_to_local(cell) + Vector3(0, 1.0, 0)
		marker.setup(node_data, MarkerColors.node_color(node_data))
