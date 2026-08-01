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

const SOURCE_SCENE := preload("res://scenes/markers/source_marker.tscn")

## A settlement is one bespoke model per SIZE of place, authored at that
## footprint's real world extent -- a Village on 1x1, a Town on 2x1, a City on
## 2x2 (see NodeData.size and generate_blocks.py's build_settlement_*).
const SETTLEMENT_SCENES := {
	GameEnums.SettlementType.VILLAGE: preload("res://scenes/markers/settlement_village_marker.tscn"),
	GameEnums.SettlementType.TOWN: preload("res://scenes/markers/settlement_town_marker.tscn"),
	GameEnums.SettlementType.CITY: preload("res://scenes/markers/settlement_city_marker.tscn"),
}

func spawn(map_data: MapData, gridmap: GridMap) -> void:
	for child in get_children():
		child.queue_free()
	for node_data in map_data.node_placements:
		if node_data.node_type == GameEnums.NodeType.SETTLEMENT:
			_spawn_settlement(node_data, gridmap)
		else:
			_spawn_source(node_data, gridmap)

## ONE marker, spanning the whole footprint.
##
## The per-cell markers this replaces (DEV-02) existed to keep a multi-tile
## place honest: those cells cannot be built on, and a single un-stretched
## marker would have looked like one building while quietly blocking four
## cells. The bespoke models are the follow-up that comment promised, and they
## keep the promise a different way -- each stands on a plaza authored at its
## footprint's real extent, so a City still visibly covers its four tiles,
## with three identical duplicate buildings no longer standing on them.
func _spawn_settlement(node_data: NodeData, gridmap: GridMap) -> void:
	var scene: PackedScene = SETTLEMENT_SCENES.get(node_data.settlement_type)
	if scene == null:
		push_warning("NodeSpawner: no settlement scene for type %s" % node_data.settlement_type)
		return
	var marker: NodeMarker = scene.instantiate()
	add_child(marker)
	marker.position = _footprint_center(node_data, gridmap) + Vector3(0, 1.0, 0)
	marker.setup(node_data, MarkerColors.node_color(node_data))

## Sources keep one marker per occupied cell: their art is a single crate, so a
## 2x1 source is two crates and the footprint reads straight off them.
func _spawn_source(node_data: NodeData, gridmap: GridMap) -> void:
	for cell_2d in node_data.cells():
		var marker: NodeMarker = SOURCE_SCENE.instantiate()
		add_child(marker)
		var cell := Vector3i(cell_2d.x, 0, cell_2d.y)
		marker.position = gridmap.map_to_local(cell) + Vector3(0, 1.0, 0)
		marker.setup(node_data, MarkerColors.node_color(node_data))

## Lights every marker's windows for the current moment of the day (LOOP-08).
## Markers with no window mesh ignore it, so this stays one sweep over the
## children rather than a per-type dispatch.
func apply_window_glow(amount: float) -> void:
	for marker in get_children():
		if marker is NodeMarker:
			marker.set_window_glow(amount)

## The middle of a node's footprint, as the midpoint of its two corner cells --
## the same point Main._node_center floats a node's order chips over, so a
## settlement's model and its chips share an axis.
func _footprint_center(node_data: NodeData, gridmap: GridMap) -> Vector3:
	var near: Vector3 = gridmap.map_to_local(Vector3i(node_data.grid_position.x, 0, node_data.grid_position.y))
	var far_cell := node_data.far_cell()
	var far: Vector3 = gridmap.map_to_local(Vector3i(far_cell.x, 0, far_cell.y))
	return (near + far) * 0.5
