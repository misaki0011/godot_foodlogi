@tool
class_name NodeSpawner
extends Node3D

## Instantiates a marker scene per fixed source/settlement node, positioned
## via the GridMap's own map_to_local() so markers align exactly to terrain
## cells without manual grid math. Player-built route/storage/hub tiles are
## rendered separately (see Main._render_grid) since they live in
## GameState.grid, not MapData.node_placements.

const MARKER_SCENES := {
	GameEnums.NodeType.SOURCE: preload("res://scenes/markers/source_marker.tscn"),
	GameEnums.NodeType.SETTLEMENT: preload("res://scenes/markers/settlement_marker.tscn"),
}
const FOOD_BUBBLE_SCENE := preload("res://scenes/markers/food_bubble_marker.tscn")

func spawn(map_data: MapData, gridmap: GridMap) -> void:
	for child in get_children():
		child.queue_free()
	var foods := GameBalance.food_types()
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
		if node_data.node_type == GameEnums.NodeType.SOURCE:
			_spawn_supply_bubble(marker, node_data, foods)

## Sources have exactly one produced food (FOOD-02), so a single always-on
## bubble -- unlike settlements' conditional shortfall bubbles (main.gd),
## which depend on the last simulated day -- shows its daily supply.
func _spawn_supply_bubble(marker: NodeMarker, node_data: NodeData, foods: Dictionary) -> void:
	for food_id in node_data.produces:
		var food: FoodData = foods.get(food_id)
		if food == null:
			continue
		var bubble: FoodBubbleMarker = FOOD_BUBBLE_SCENE.instantiate()
		add_child(bubble)
		bubble.position = marker.position + Vector3(0, 1.5, 0)
		bubble.setup(food, node_data.produces[food_id])
