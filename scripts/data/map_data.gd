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

## The one demand line the map opens with (DEV-01), as {node_id, food_id}.
## Every other line is opened by the player choosing it from an offer, so this
## is the only piece of progression the map authors: a known, gentle first
## beat, at a moment when nothing is built and a choice would be noise.
@export var opening_line: Dictionary = {}

## Every settlement demand line on the map, as {node_id, food_id, difficulty}.
## This is the pool OrderBook draws offers from -- there is no authored order
## any more, only the map's own contents ranked by how hard each line is.
func demand_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for node in node_placements:
		if node.node_type != GameEnums.NodeType.SETTLEMENT:
			continue
		for food_id in node.demand:
			lines.append({
				"node_id": node.node_id,
				"food_id": food_id,
				"difficulty": difficulty_of(node, food_id),
			})
	return lines

## How hard a line is, derived from the map rather than authored: how far the
## freshness falls short of what the settlement rewards.
##
##     difficulty = bonus_freshness - (100 - distance * decay_per_tile)
##
## Distance is straight-line grid steps to the nearest source producing that
## food, so this ignores the roads the player has actually built, any storage
## protecting the cargo, and the river. That is deliberate -- it is a ranking
## of the problems the map poses, not a prediction of any particular run.
##
## Negative means comfortable (Village A is 4 steps from the Farm and grain
## barely decays, so grain there lands well above the bonus line). Positive
## means the direct route cannot reach the reward and the player needs
## storage, a hub or a shorter path -- which is exactly the lesson those
## lines exist to teach. Ranking the region this way reproduces the hand
## written teaching order for free, and re-derives it if a source ever moves.
func difficulty_of(settlement: NodeData, food_id: String) -> float:
	var decay: float = GameBalance.food_types()[food_id].decay_per_tile
	var nearest := INF
	for node in node_placements:
		if node.node_type == GameEnums.NodeType.SOURCE and node.produces.has(food_id):
			var delta: Vector2i = node.grid_position - settlement.grid_position
			nearest = minf(nearest, float(absi(delta.x) + absi(delta.y)))
	if nearest == INF:
		# No source makes this food, so the line can never be filled at all.
		# validate() reports it; rank it hardest so it is never offered.
		return INF
	return settlement.bonus_freshness - (100.0 - nearest * decay)

## Checks the map can actually run: the opening line must be a real demand
## line, and every demand line must have some source producing its food (one
## that does not could be offered, accepted and then never filled, stalling
## the run for good).
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

	var opening_node: NodeData = settlements.get(opening_line.get("node_id", ""))
	if opening_node == null:
		problems.append("opening_line names unknown settlement '%s'" % opening_line.get("node_id", ""))
	elif not opening_node.demand.has(opening_line.get("food_id", "")):
		problems.append("opening_line opens '%s' at %s, which demands no such food" % [
			opening_line.get("food_id", ""), opening_line.get("node_id", ""),
		])

	for node_id in settlements:
		var settlement: NodeData = settlements[node_id]
		for food_id in settlement.demand:
			if is_inf(difficulty_of(settlement, food_id)):
				problems.append("%s demands '%s' but no source produces it" % [node_id, food_id])
	return problems

func get_terrain(x: int, _y: int) -> GameEnums.TerrainType:
	return GameEnums.TerrainType.RIVER if x == river_col else GameEnums.TerrainType.PLAINS

func is_river(x: int, _y: int) -> bool:
	return x == river_col
