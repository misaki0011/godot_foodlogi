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

## The order in which settlements' demand lines open (DEV-01), earliest
## first. Each entry is {earliest_day:int, node_id:String, food_id:String}
## and names a line that already exists in that settlement's NodeData.demand
## -- the amount lives there, so this list only ever carries pacing, never
## balance.
##
## Must be sorted by earliest_day: OrderBook stops scanning at the first
## entry that isn't due yet. Run validate() (the dev checks do) after
## editing.
@export var order_schedule: Array[Dictionary] = []

## Checks the order schedule against the node placements: every scheduled
## line must exist as a real demand line, every demand line must be
## scheduled (an unscheduled one could never open, so the settlement would
## silently never want it), no line may be scheduled twice, and earliest_day
## must not go backwards.
##
## Returns the problems found, empty when the map is sound. Called from the
## dev checks (tools/verify_mvp.gd) rather than at runtime -- this is a
## content check on an authored resource, not a per-frame concern.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var settlements := {}
	for node in node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			settlements[node.node_id] = node

	var scheduled := {}
	var previous_day := 0
	for order in order_schedule:
		var node_id: String = order.get("node_id", "")
		var food_id: String = order.get("food_id", "")
		var earliest_day := int(order.get("earliest_day", 0))
		var settlement: NodeData = settlements.get(node_id)
		if settlement == null:
			problems.append("order_schedule names unknown settlement '%s'" % node_id)
		elif not settlement.demand.has(food_id):
			problems.append("order_schedule opens '%s' at %s, which demands no such food" % [food_id, node_id])
		if earliest_day < previous_day:
			problems.append("order_schedule is out of order: %s/%s at day %d follows day %d" % [node_id, food_id, earliest_day, previous_day])
		previous_day = maxi(previous_day, earliest_day)
		var key := "%s|%s" % [node_id, food_id]
		if scheduled.has(key):
			problems.append("order_schedule opens %s more than once" % key)
		scheduled[key] = true

	for node_id in settlements:
		for food_id in settlements[node_id].demand:
			if not scheduled.has("%s|%s" % [node_id, food_id]):
				problems.append("%s demands '%s' but no order ever opens it" % [node_id, food_id])
	return problems

func get_terrain(x: int, _y: int) -> GameEnums.TerrainType:
	return GameEnums.TerrainType.RIVER if x == river_col else GameEnums.TerrainType.PLAINS

func is_river(x: int, _y: int) -> bool:
	return x == river_col
