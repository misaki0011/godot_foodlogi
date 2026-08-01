@tool
class_name MapData
extends Resource

## Single source of truth for a region's terrain + node layout, matching
## fresh-routes-mvp.html's map: an open grid with a single river column
## (bridges auto-build when a route crosses it) and fixed source/settlement
## placements. Both TerrainRenderer and NodeSpawner read this resource.

@export var grid_size: Vector2i
@export var river_col: int = -1

## Rectangles of OPEN SEA -- ground no route may ever be built on, at any
## price (TERR-10). Distinct from the river, which is a wall you can pay §40 to
## get through: the sea is one you go around.
##
## Authored as rectangles rather than a cell list because a coastline is a
## region, and a list of forty Vector2i in a .tres is unreadable and unedita-
## ble by hand. Rectangles also make the two rules a sea has to satisfy easy to
## check: nothing may stand on it, and nothing may be walled in by it.
##
## This is a stop-gap shape for the same data TERR-06 will hold per cell. When
## that lands, these become SEA entries in the terrain array and this field
## goes away.
@export var sea_rects: Array[Rect2i] = []
@export var node_placements: Array[NodeData] = []

## The demand lines the map opens with (DEV-01), each {node_id, food_id}.
## Every other line is opened by the player choosing it from an offer, so this
## is the only piece of progression the map authors.
##
## Three of them, not one. A single opening order is over in a day -- one
## short road from the nearest source and the map is solved -- which teaches
## the drag gesture and nothing else. Three gives the player something to
## weigh from the first minute (which town first, is one trunk road enough)
## while still being far from the twelve-bubble wall this feature exists to
## remove. They are the three easiest lines on the board, so the opening is
## still gentle.
@export var opening_lines: Array[Dictionary] = []

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
			# Footprint to footprint (DEV-02): a 2x2 City is a tile closer to
			# everything than its top-left corner suggests.
			nearest = minf(nearest, float(node.grid_distance_to(settlement)))
	if nearest == INF:
		# No source makes this food, so the line can never be filled at all.
		# validate() reports it; rank it hardest so it is never offered.
		return INF
	return settlement.bonus_freshness - (100.0 - nearest * decay)

## Checks the map can actually run: every opening line must be a real demand
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

	if opening_lines.is_empty():
		problems.append("opening_lines is empty -- the map would open with nothing to deliver")
	var seen := {}
	for line in opening_lines:
		var node_id: String = line.get("node_id", "")
		var food_id: String = line.get("food_id", "")
		var opening_node: NodeData = settlements.get(node_id)
		if opening_node == null:
			problems.append("opening_lines names unknown settlement '%s'" % node_id)
		elif not opening_node.demand.has(food_id):
			problems.append("opening_lines opens '%s' at %s, which demands no such food" % [food_id, node_id])
		var key := "%s|%s" % [node_id, food_id]
		if seen.has(key):
			problems.append("opening_lines opens %s twice" % key)
		seen[key] = true

	for node_id in settlements:
		var settlement: NodeData = settlements[node_id]
		for food_id in settlement.demand:
			if is_inf(difficulty_of(settlement, food_id)):
				problems.append("%s demands '%s' but no source produces it" % [node_id, food_id])
		# The demand budget for this settlement's type (DEV-04). Nothing
		# enforces it at runtime -- the order book only opens lines that are
		# already authored -- so this is the only thing keeping a Village
		# from being written with a City's appetite.
		var cap := settlement.demand_cap()
		if settlement.demand.size() > cap:
			problems.append("%s is a %s and may hold %d demand lines, but %d are authored" % [
				node_id, GameEnums.SettlementType.keys()[settlement.settlement_type], cap, settlement.demand.size(),
			])

	# Footprints (DEV-02) must stay on the map and must not overlap: two nodes
	# sharing a cell would make Main._nodes_by_pos resolve that cell to
	# whichever was placed last, silently hiding one of them from every build
	# guard and every path.
	var owner_of := {}
	for node in node_placements:
		if node.size.x < 1 or node.size.y < 1:
			problems.append("%s has a non-positive size %s" % [node.node_id, node.size])
			continue
		for cell in node.cells():
			if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
				problems.append("%s occupies %s, which is off the %s grid" % [node.node_id, cell, grid_size])
			if owner_of.has(cell):
				problems.append("%s and %s both occupy %s" % [owner_of[cell], node.node_id, cell])
			owner_of[cell] = node.node_id

	problems.append_array(_sea_problems(owner_of))
	return problems

## The two ways a coastline can break a map (TERR-10).
##
## A node STANDING on sea is the obvious one. The other is the one that would
## actually ship: a node whose every orthogonal neighbour is sea or off-map can
## never be connected to anything, while the order book goes on offering lines
## against it forever -- a run that cannot be finished and gives no sign why.
## Cheap to check here, invisible until someone plays it.
func _sea_problems(owner_of: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for rect in sea_rects:
		if rect.size.x <= 0 or rect.size.y <= 0:
			problems.append("sea_rects holds an empty rectangle %s" % rect)
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > grid_size.x or rect.end.y > grid_size.y:
			problems.append("sea rectangle %s runs off the %s grid" % [rect, grid_size])
	for cell in owner_of:
		if is_sea(cell.x, cell.y):
			problems.append("%s occupies %s, which is open sea" % [owner_of[cell], cell])
	for node in node_placements:
		var reachable := false
		for cell in node.cells():
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var side: Vector2i = cell + step
				if side.x < 0 or side.y < 0 or side.x >= grid_size.x or side.y >= grid_size.y:
					continue
				if not owner_of.has(side) and is_buildable(side.x, side.y):
					reachable = true
		if not reachable:
			problems.append("%s is walled in -- no buildable cell touches its footprint" % node.node_id)
	return problems

## Sea is tested BEFORE the river column, so a coastline drawn across the
## river's mouth is sea rather than a crossable channel. Nothing on region 1
## overlaps today; the order is what stops a future map from authoring a
## crossing it never meant to offer.
func get_terrain(x: int, y: int) -> GameEnums.TerrainType:
	if is_sea(x, y):
		return GameEnums.TerrainType.SEA
	return GameEnums.TerrainType.RIVER if x == river_col else GameEnums.TerrainType.PLAINS

func is_river(x: int, y: int) -> bool:
	return x == river_col and not is_sea(x, y)

func is_sea(x: int, y: int) -> bool:
	for rect in sea_rects:
		if rect.has_point(Vector2i(x, y)):
			return true
	return false

## Whether a route tile may exist here at all. Plains and river both qualify --
## the river simply costs more (TERR-05) -- and the sea never does.
func is_buildable(x: int, y: int) -> bool:
	return not is_sea(x, y)
