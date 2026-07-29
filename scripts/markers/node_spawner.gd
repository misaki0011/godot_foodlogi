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
		# One marker per occupied cell (DEV-02), so a 2x1 Town and a 2x2 City
		# read as bigger places AND show exactly which tiles they take up --
		# which the player needs, since those tiles cannot be built on. A
		# single stretched marker would look like one building while quietly
		# blocking four cells. Bespoke Town/City meshes are the follow-up;
		# this is the footprint made honest with the art that exists.
		for cell_2d in node_data.cells():
			var marker: NodeMarker = scene.instantiate()
			add_child(marker)
			var cell := Vector3i(cell_2d.x, 0, cell_2d.y)
			marker.position = gridmap.map_to_local(cell) + Vector3(0, 1.0, 0)
			marker.setup(node_data, MarkerColors.node_color(node_data))
