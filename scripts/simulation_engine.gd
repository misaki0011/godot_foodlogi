class_name SimulationEngine

## Ported 1:1 from fresh-routes-mvp.html's grid/graph/simulation functions,
## since extended past it. The world is a plain tile grid (GameState.grid,
## Vector2i -> cell) plus a fixed set of source/settlement nodes -- not a
## node-to-node route-segment graph. Connectivity is never implied by mere
## tile adjacency: only an explicit GameState.connections edge (drawn by
## dragging, see Main._commit_drag) links two cells, so side-by-side but
## unconnected routes stay separate networks (v0.5). A Small Hub can be built
## on any existing route tile (Main._do_build_hub), capped per connected
## network -- see network_at_hub_cap and SPEC.md §4.4 (v0.5 revision). A Bridge
## can likewise be placed on a straight route tile, letting a second route cross
## over the first without joining it -- see the lane block below, which is why
## every traversal here works in (tile, lane) vertices rather than plain tiles.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## ---------- bridges: lanes, and why a graph vertex isn't just a tile ----------
## A bridge tile (Main._do_build_bridge) is an ordinary route tile carrying a
## raised deck: its cell keeps kind "route" and gains `bridge_axis`, the axis
## the DECK runs along. The road it crosses runs along the perpendicular axis.
## The two share the cell and must never share a network.
##
## So connectivity is a property of a (tile, lane) pair rather than of a tile,
## and that pair -- packed as Vector3i(pos.x, pos.y, lane) -- is the graph
## vertex used by every traversal below:
##   LANE_GROUND: the ordinary surface. Every tile and every node has one.
##   LANE_DECK:   the raised deck. Bridge tiles only.
## Which lane you land on is pure geometry: step onto a bridge ALONG its
## bridge_axis and you're on the deck, step onto it ACROSS that axis and you're
## on the road below (lane_for_step). From either you may only leave the way you
## came in -- straight through, same lane (exits). That single rule is the whole
## mechanism: two routes cross a shared cell without merging, with no second
## grid layer and no second connection set. GameState.connections stays exactly
## as it was, a flat symmetric set of tile<->tile edges.
const LANE_GROUND := 0
const LANE_DECK := 1

static func is_bridge(state: GameState, pos: Vector2i) -> bool:
	var cell = state.grid.get(pos)
	return cell != null and cell.has("bridge_axis")

## The axis a bridge tile's deck runs along -- Vector2i(1, 0) or (0, 1), or
## ZERO for any tile that isn't a bridge.
static func bridge_axis(state: GameState, pos: Vector2i) -> Vector2i:
	var cell = state.grid.get(pos)
	if cell == null or not cell.has("bridge_axis"):
		return Vector2i.ZERO
	return cell.bridge_axis

## Whether the cardinal `step` runs along `axis` rather than across it.
static func _is_along(axis: Vector2i, step: Vector2i) -> bool:
	return (axis.x != 0) == (step.x != 0)

## Which lane of `to` you arrive on after moving one cell in direction `step`.
## Everything that isn't a bridge has only LANE_GROUND to arrive on.
static func lane_for_step(state: GameState, to: Vector2i, step: Vector2i) -> int:
	var axis := bridge_axis(state, to)
	if axis == Vector2i.ZERO:
		return LANE_GROUND
	return LANE_DECK if _is_along(axis, step) else LANE_GROUND

static func vertex(pos: Vector2i, lane: int) -> Vector3i:
	return Vector3i(pos.x, pos.y, lane)

static func vertex_pos(v: Vector3i) -> Vector2i:
	return Vector2i(v.x, v.y)

## The lanes a tile actually has: two for a bridge, one for anything else.
static func _lanes_at(state: GameState, pos: Vector2i) -> Array[int]:
	var lanes: Array[int] = [LANE_GROUND]
	if is_bridge(state, pos):
		lanes.append(LANE_DECK)
	return lanes

## The graph vertices reachable in one step from `v`, over EXPLICIT
## connections only (v0.5) -- physical adjacency still never implies a link.
## On a bridge vertex the outgoing steps are filtered to the vertex's own lane,
## which is what keeps a deck and the road beneath it from ever interchanging.
static func exits(state: GameState, v: Vector3i) -> Array[Vector3i]:
	var pos := vertex_pos(v)
	var axis := bridge_axis(state, pos)
	var out: Array[Vector3i] = []
	for n in state.connections.get(pos, {}).keys():
		var step: Vector2i = n - pos
		if axis != Vector2i.ZERO and _is_along(axis, step) != (v.z == LANE_DECK):
			continue
		out.append(vertex(n, lane_for_step(state, n, step)))
	return out

## Connected components over BUILT TILES ALONE (route/storage/hub), traversed
## via EXPLICIT connections only (v0.5) -- nodes are NOT transit vertices,
## since a delivery can never pass through a source/settlement (§4.7), and an
## unconnected-but-adjacent tile is never traversed either. Two road groups
## that touch only a shared node, or that simply sit next to each other
## without a dragged connection, are therefore SEPARATE networks. Used for
## hub-cap/formation (each road network gets its own hub budget) and, via
## established_route_cells, the overlay.
##
## Keyed by GRAPH VERTEX (Vector3i, see the lane block above), not by tile: a
## bridge tile appears twice, once for its deck and once for the road beneath,
## and those two entries normally land in DIFFERENT components -- which is
## exactly what "the two routes never merge" means here.
static func road_components(state: GameState) -> Dictionary:
	var comp_of := {}
	var comp_id := 0
	for start_pos in state.grid:
		for lane in _lanes_at(state, start_pos):
			var start := vertex(start_pos, lane)
			if comp_of.has(start):
				continue
			var queue: Array[Vector3i] = [start]
			comp_of[start] = comp_id
			while not queue.is_empty():
				var u: Vector3i = queue.pop_front()
				for v in exits(state, u):
					if state.grid.has(vertex_pos(v)) and not comp_of.has(v):
						comp_of[v] = comp_id
						queue.append(v)
			comp_id += 1
	return comp_of

## The set (Vector2i -> true) of built tiles on some complete source->
## settlement path -- a path that starts at a source, so a road network no
## source can reach is never included (used for main.gd's established-route
## overlay).
##
## A delivery path can never pass through a node (a source/settlement is a
## pure endpoint, §4.7), so connectivity is computed over built tiles ALONE,
## via EXPLICIT connections only (v0.5): two roads link only when the player
## has dragged a connection between them, never merely because they're
## orthogonally adjacent. A road network qualifies only when it touches at
## least one source AND at least one settlement (through a dragged tile<->node
## connection) -- this is what keeps a settlement-to-settlement road
## (reachable from no source) out, even when some unrelated source sits
## elsewhere on the map. Within a qualifying network, dead-end stubs are
## pruned: a tile survives only while it still links to 2+ things (another
## kept tile, or a node it's connected to), leaving the through-paths that run
## from a source to a settlement.
## Works in graph vertices throughout (so a bridge's deck can be established
## while the road under it isn't, and vice versa); established_route_cells
## flattens the result back to tiles for callers that only need to shade a map
## cell.
static func established_route_vertices(state: GameState, nodes_by_pos: Dictionary, only_source_id := "") -> Dictionary:
	var comp_of := road_components(state)
	# Which road networks touch a source / a settlement (a dragged tile<->node
	# connection, not mere adjacency).
	var comp_has_source := {}
	var comp_has_settlement := {}
	for pos in state.grid:
		for lane in _lanes_at(state, pos):
			var v := vertex(pos, lane)
			var comp = comp_of[v]
			for w in exits(state, v):
				var node: NodeData = nodes_by_pos.get(vertex_pos(w))
				if node == null:
					continue
				if node.node_type == GameEnums.NodeType.SOURCE:
					if only_source_id == "" or node.node_id == only_source_id:
						comp_has_source[comp] = true
				else:
					comp_has_settlement[comp] = true
	var kept := {}
	for pos in state.grid:
		for lane in _lanes_at(state, pos):
			var v := vertex(pos, lane)
			var comp = comp_of[v]
			if comp_has_source.get(comp, false) and comp_has_settlement.get(comp, false):
				kept[v] = true
	# Iteratively prune dead-end vertices. One survives only while it links to
	# 2+ things (kept vertices or nodes) -- i.e. it's mid-path, not a stub tip.
	var changed := true
	while changed:
		changed = false
		for v in kept.keys():
			var degree := 0
			for w in exits(state, v):
				if kept.has(w) or _counts_as_route_end(nodes_by_pos.get(vertex_pos(w)), only_source_id):
					degree += 1
			if degree <= 1:
				kept.erase(v)
				changed = true
	return kept

static func established_route_cells(state: GameState, nodes_by_pos: Dictionary, only_source_id := "") -> Dictionary:
	var cells := {}
	for v in established_route_vertices(state, nodes_by_pos, only_source_id):
		cells[vertex_pos(v)] = true
	return cells

## Whether `node` anchors an end of a route being traced for `only_source_id`.
## Settlements always do. A source does too -- but when tracing one specific
## source, every OTHER source stops counting, which is what makes the pruning
## pass drop the spurs that only some other source feeds: with its far end no
## longer anchored, such a spur unravels tile by tile.
static func _counts_as_route_end(node: NodeData, only_source_id: String) -> bool:
	if node == null:
		return false
	if node.node_type != GameEnums.NodeType.SOURCE:
		return true
	return only_source_id == "" or node.node_id == only_source_id

## True when `pos`'s connected road network (see road_components) already has
## HUB_CAP_PER_NETWORK built hubs, so Main._do_build_hub must refuse a new one
## there. A hub can be built on any route tile (v0.5 revision -- no more
## completed-route-fork requirement); this cap is the only remaining
## constraint, and it's checked live rather than cached on the cell.
static func network_at_hub_cap(state: GameState, pos: Vector2i) -> bool:
	return hubs_on_network(state, pos) >= GameBalance.HUB_CAP_PER_NETWORK

## The count behind network_at_hub_cap. Separate because a route drag can now
## queue a junction of its own (Main._recompute_drag_validity, v0.7 item 77) and
## has to know how much of the budget is left, not merely whether any is.
static func hubs_on_network(state: GameState, pos: Vector2i) -> int:
	var comp_of := road_components(state)
	# Hubs are never built on a bridge tile (Main._do_build_hub refuses), so
	# ground lanes are the only ones that can carry or host one.
	var comp = comp_of.get(vertex(pos, LANE_GROUND), -1)
	var count := 0
	for p in state.grid.keys():
		if state.grid[p].kind == "hub" and comp_of.get(vertex(p, LANE_GROUND), -2) == comp:
			count += 1
	return count

## True when the road network `pos` sits on already carries
## GameBalance.BRIDGE_CAP_PER_NETWORK bridges, so Main._do_build_bridge must
## refuse another one there. `pos` is the tile the new bridge would go on, so
## the network in question is the one its road is part of right now -- its
## ground lane.
##
## An existing bridge counts against BOTH networks it serves (the road beneath
## it and the deck across it): a crossing is infrastructure for each of them,
## and counting it once would let a player keep the budget clear by always
## approaching from the other side.
static func network_at_bridge_cap(state: GameState, pos: Vector2i) -> bool:
	return bridges_on_network(state, pos) >= GameBalance.BRIDGE_CAP_PER_NETWORK

## The count behind network_at_bridge_cap, for the same reason hubs_on_network
## exists: one drag may now queue several crossings and must not queue past the
## budget just because none of them is in the grid yet.
static func bridges_on_network(state: GameState, pos: Vector2i) -> int:
	var comp_of := road_components(state)
	var comp = comp_of.get(vertex(pos, LANE_GROUND), -1)
	var count := 0
	for p in state.grid.keys():
		if not is_bridge(state, p):
			continue
		if comp_of.get(vertex(p, LANE_GROUND), -2) == comp or comp_of.get(vertex(p, LANE_DECK), -3) == comp:
			count += 1
	return count

## Dijkstra minimizing cumulative freshness-decay weight; ties broken
## naturally by whichever path accumulates less decay first. A delivery path
## may only touch a node at its two ends (start = source, end = settlement) --
## a source/settlement is a terminal endpoint, never a transit shortcut
## (§4.7), so any node reached mid-search is a dead end and is never expanded.
## Searches over graph VERTICES rather than tiles (see the lane block above),
## so a delivery that climbs a bridge deck is forced to carry straight on over
## it and can never drop onto the road underneath. Crossing a deck is weighted
## by GameBalance.BRIDGE_DECK_DECAY_MULT, matching what simulate_freshness will
## actually charge, so Dijkstra prefers a short detour over a needless climb.
## The returned path is flattened back to tiles, which stays lossless for every
## caller: the lane of each step is re-derivable from the step's own direction.
## A multi-tile node is one place, not several (DEV-02): a delivery may leave
## from ANY cell of its source's footprint and arrive at ANY cell of the
## settlement's, so the search is seeded with every origin cell at zero and
## stops at the first destination cell it reaches. Picking a corner for each
## would otherwise make a 2x2 City's reachability depend on which corner the
## map author happened to write down.
static func find_path(state: GameState, nodes_by_pos: Dictionary, from_pos: Vector2i, to_pos: Vector2i, food: FoodData) -> Array[Vector2i]:
	var from_node: NodeData = nodes_by_pos.get(from_pos)
	var to_node: NodeData = nodes_by_pos.get(to_pos)
	var goals := {}
	if to_node == null:
		goals[to_pos] = true
	else:
		for cell in to_node.cells():
			goals[cell] = true

	var dist := {}
	var prev := {}
	var visited := {}
	var frontier: Array = []
	var origins: Array[Vector2i] = [from_pos] if from_node == null else from_node.cells()
	for cell in origins:
		var v := vertex(cell, LANE_GROUND)
		dist[v] = 0.0
		frontier.append([0.0, v])

	var goal := Vector3i(-1, -1, -1)
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var top = frontier.pop_front()
		var d: float = top[0]
		var u: Vector3i = top[1]
		if visited.has(u):
			continue
		visited[u] = true
		var u_pos := vertex_pos(u)
		if goals.has(u_pos):
			goal = u
			break
		# A node other than the delivery's own source is an endpoint, not a
		# through-route: reach it if it's the destination, but never route past
		# it into its other adjacent roads. Compared by NODE, not by cell, so
		# a delivery can still cross between the cells of its own source
		# without that counting as routing through somebody.
		var u_node: NodeData = nodes_by_pos.get(u_pos)
		if u_node != null and u_node != from_node:
			continue
		for v in exits(state, u):
			if visited.has(v):
				continue
			var w: float = 0.01 if nodes_by_pos.has(vertex_pos(v)) else food.decay_per_tile
			if v.z == LANE_DECK:
				w *= GameBalance.BRIDGE_DECK_DECAY_MULT
			var nd := d + w
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				frontier.append([nd, v])
	if goal.x < 0:
		return []
	var path: Array[Vector2i] = []
	var cur := goal
	while true:
		path.append(vertex_pos(cur))
		# Origin vertices are the ones with no predecessor, which is what
		# terminates the walk now that a search can have several of them.
		if not prev.has(cur):
			break
		cur = prev[cur]
	path.reverse()
	return path

## Freshness at the end of `path` (path[0] is the source tile itself, so
## decay is only applied from path[1] onward, matching the HTML).
static func simulate_freshness(state: GameState, path: Array[Vector2i], food: FoodData) -> float:
	var fresh := 100.0
	var protection_left := 0
	var protection_mult := 1.0
	for i in range(1, path.size()):
		var pos: Vector2i = path[i]
		var cell = state.grid.get(pos)
		var mult := 1.0
		if protection_left > 0:
			mult = protection_mult
			protection_left -= 1
		var decay: float = food.decay_per_tile * mult
		# Climbing onto a bridge deck and back down costs an extra tile's worth
		# of decay. Only the route ON the deck pays it -- the road passing
		# underneath is untouched, which is why the lane has to be re-derived
		# from the step's own direction rather than read off the tile.
		if lane_for_step(state, pos, pos - path[i - 1]) == LANE_DECK:
			decay *= GameBalance.BRIDGE_DECK_DECAY_MULT
		if cell and cell.kind == "storage":
			decay = 0.0
			var st = GameBalance.STORAGE_TYPES[cell.stype]
			protection_left = st.protection
			protection_mult = st.mult
		fresh -= decay
	return clampf(fresh, 0.0, 100.0)

## Capacity belongs to the TILE, so the two routes crossing at a bridge share
## one budget rather than getting a lane each -- a crossing is a single piece of
## built infrastructure with a single throughput, and keeping it per-tile is
## what lets the congestion overlay and tile_usage stay tile-keyed.
static func tile_capacity(state: GameState, pos: Vector2i) -> float:
	var cell = state.grid.get(pos)
	if cell == null:
		return INF
	if cell.kind == "route":
		return GameBalance.ROUTE_LEVELS[cell.level].cap
	if cell.kind == "hub":
		# A hub is a junction, not a throughput of its own (v0.7 item 77): the
		# road it stands on carries what that road level carries, exactly as it
		# did before the hub was built. Its own figure used to be a flat 250,
		# which made a hub a cheap capacity UPGRADE on dirt (60 -> 250) and a
		# silent capacity CUT on a Main trunk (400 -> 250) -- a junction that
		# narrows the road it sits on is the opposite of what one is for, and
		# a §150 building that outperforms a §100 road upgrade is not a choice
		# anyone weighs twice. `level` is the road underneath, recorded when the
		# hub was built and handed back when it is cleared.
		return GameBalance.ROUTE_LEVELS[cell.get("level", "dirt")].cap
	if cell.kind == "storage":
		return GameBalance.STORAGE_TYPES[cell.stype].capacity
	return INF

static func route_build_cost(pos: Vector2i, map_data: MapData) -> float:
	var cost := GameBalance.ROUTE_BUILD_COST
	if map_data.is_river(pos.x, pos.y):
		cost += GameBalance.RIVER_BRIDGE_COST
	return cost

## Sums last-run delivered food through `pos`, grouped by originating
## source, so a hub tooltip can show what's actually splitting through it.
static func hub_split_summary(state: GameState, pos: Vector2i) -> Dictionary:
	var by_source := {}
	var total := 0.0
	for f in state.last_flows:
		if f.delivered <= 0.0:
			continue
		if not (pos in f.path):
			continue
		by_source[f.source] = by_source.get(f.source, 0.0) + f.delivered
		total += f.delivered
	return {"by_source": by_source, "total": total}

## Runs one full day: demand generation, demand-pull source
## assignment (best predicted freshness first, upkeep as an implicit
## tie-break via Dijkstra), capacity limits, freshness, storage
## preservation, hub discounts/upkeep, income/spoilage, satisfaction, and
## the efficiency grade/score chase. See SPEC.md §17.
static func run_day(state: GameState, nodes: Array[NodeData]) -> DayReportData:
	var report := DayReportData.new()
	report.day = state.day
	var foods := GameBalance.food_types()
	var nodes_by_pos := {}
	var sources: Array[NodeData] = []
	var settlements: Array[NodeData] = []
	for n in nodes:
		# One entry per occupied cell (DEV-02), so every "is there a node
		# here" test in the engine keeps working unchanged on a 2x2 City.
		for cell in n.cells():
			nodes_by_pos[cell] = n
		if n.node_type == GameEnums.NodeType.SOURCE:
			sources.append(n)
		else:
			settlements.append(n)

	var tile_usage := {}
	var supply_left := {}
	for s in sources:
		for food_id in s.produces:
			supply_left["%s|%s" % [s.node_id, food_id]] = s.supply_of(food_id)

	var flows: Array[Dictionary] = []
	var income := 0.0
	## Reported separately so the player can see what the delivery rule is
	## paying and what it is costing them, rather than only a net figure.
	var bonus_income := 0.0
	var withheld_income := 0.0
	var spoilage_cost := 0.0
	var delivered_total := 0.0
	var requested_total := 0.0
	var fresh_weighted_sum := 0.0
	var fresh_weight_total := 0.0
	var capacity_blocked := 0.0
	var settlement_food_status := {}
	var settlement_scores: Array[Dictionary] = []

	for settlement in settlements:
		# Only the demand lines whose orders have opened are simulated
		# (DEV-01). A settlement whose first order is still days out stands
		# on the map wanting nothing: it is not short-delivered, it costs no
		# withheld income, and -- critically -- it is not scored, since
		# averaging a settlement the player is not yet allowed to serve into
		# happiness would make the grade a measure of the calendar rather
		# than of the network. See OrderBook.
		var demand := OrderBook.active_demand(state, settlement)
		if demand.is_empty():
			settlement_food_status[settlement.node_id] = {}
			continue

		var fulfilled := 0.0
		var requested := 0.0
		var fresh_sum := 0.0
		var fresh_count := 0.0
		var rejected := 0.0
		var food_status := {}
		settlement_food_status[settlement.node_id] = food_status
		for food_id in demand:
			# A settlement asks for the same amount every day. The daily
			# ±15-25% wobble this used to apply was the only randomness in the
			# whole simulation, and it made every number on the map a moving
			# target: a bubble read 18/20 one day and 23/23 the next off the
			# same unchanged road, so the player could not tell an improvement
			# they had made from noise. Freshness was already deterministic
			# (simulate_freshness reads only the path), so with this the whole
			# day is: the same network delivers the same result, and a number
			# that moves means something the player did moved it.
			var need: float = maxf(1.0, roundf(demand[food_id]))
			requested += need
			requested_total += need
			# rejected_fresh_sum is amount-weighted like fresh_sum, but over the
			# cargo min_freshness turned away -- without it a short line cannot
			# say WHY it fell short, since fresh_sum only ever sees what was
			# accepted (see UI-04's rejected row).
			# `earned` is what this line actually paid and `withheld` what it
			# would have paid had the whole order arrived. Recorded here rather
			# than re-derived in the UI, so the number a row prints can never
			# drift from the number the treasury was credited (see UI-04).
			food_status[food_id] = {"requested": need, "delivered": 0.0, "rejected": 0.0, "fresh_sum": 0.0, "rejected_fresh_sum": 0.0, "earned": 0.0, "withheld": 0.0}
			var food: FoodData = foods[food_id]

			var candidates: Array[Dictionary] = []
			for src in sources:
				if not src.produces.has(food_id):
					continue
				var path := find_path(state, nodes_by_pos, src.grid_position, settlement.grid_position, food)
				if path.is_empty():
					continue
				candidates.append({"src": src, "path": path, "predicted": simulate_freshness(state, path, food)})
			candidates.sort_custom(func(a, b): return a.predicted > b.predicted)

			# Held back rather than banked as each cart lands: this line only
			# pays out if the settlement's whole order is met (see below).
			var line_income := 0.0

			for c in candidates:
				if need <= 0.0:
					break
				var sup_key: String = "%s|%s" % [c.src.node_id, food_id]
				var avail: float = supply_left.get(sup_key, 0.0)
				if avail <= 0.0:
					continue
				var path_cap := INF
				for pos in c.path:
					path_cap = minf(path_cap, tile_capacity(state, pos) - float(tile_usage.get(pos, 0.0)))
				if path_cap <= 0.0:
					capacity_blocked += minf(need, avail)
					continue
				var amt: float = minf(need, minf(avail, path_cap))
				if amt <= 0.0:
					continue
				var fresh: float = simulate_freshness(state, c.path, food)
				var mult: float = GameBalance.freshness_multiplier(fresh)
				var rejected_by_strictness: bool = fresh < settlement.min_freshness
				for pos in c.path:
					tile_usage[pos] = float(tile_usage.get(pos, 0.0)) + amt
				supply_left[sup_key] = avail - amt
				need -= amt

				if rejected_by_strictness or mult == 0.0:
					rejected += amt
					food_status[food_id].rejected += amt
					food_status[food_id].rejected_fresh_sum += fresh * amt
					spoilage_cost += amt * food.base_value * 0.5
					flows.append({"food": food_id, "path": c.path, "delivered": 0.0, "rejected": amt, "settlement": settlement.node_id, "source": c.src.node_id})
				else:
					fulfilled += amt
					delivered_total += amt
					food_status[food_id].delivered += amt
					food_status[food_id].fresh_sum += fresh * amt
					line_income += amt * food.base_value * mult
					fresh_sum += fresh * amt
					fresh_count += amt
					fresh_weighted_sum += fresh * amt
					fresh_weight_total += amt
					flows.append({"food": food_id, "path": c.path, "delivered": amt, "fresh": fresh, "settlement": settlement.node_id, "source": c.src.node_id})

			# Payout, matching the three states of this line's speech bubble
			# (Main._render_settlement_bubbles): red pays nothing, amber pays
			# the line, green pays the line plus FRESHNESS_BONUS_RATE again.
			# A short order is not a partial sale -- the settlement went
			# without, so the run earns nothing however fresh what did arrive
			# happened to be.
			# `line` aliases the food_status entry (Dictionaries are references),
			# so writing earned/withheld here records them on the line itself.
			var line: Dictionary = food_status[food_id]
			if line.delivered >= line.requested - 0.01 and line.delivered > 0.0:
				income += line_income
				line.earned = line_income
				if line.fresh_sum / line.delivered >= settlement.bonus_freshness:
					var bonus: float = line_income * GameBalance.FRESHNESS_BONUS_RATE
					income += bonus
					bonus_income += bonus
					line.earned += bonus
			else:
				withheld_income += line_income
				line.withheld = line_income
		var avg_fresh: float = fresh_sum / fresh_count if fresh_count > 0.0 else 0.0
		var fulfill_rate: float = fulfilled / requested if requested > 0.0 else 1.0
		var waste_rate: float = rejected / requested if requested > 0.0 else 0.0
		var sat: float = fulfill_rate * 60.0 + minf(1.0, avg_fresh / settlement.bonus_freshness) * 40.0 - waste_rate * 30.0
		sat = clampf(sat, 0.0, 100.0)
		settlement_scores.append({"settlement": settlement, "fulfill_rate": fulfill_rate, "avg_fresh": avg_fresh, "waste_rate": waste_rate, "sat": sat})

	var route_upkeep := 0.0
	var storage_upkeep := 0.0
	var hub_upkeep := 0.0
	var hub_tiles: Array[Vector2i] = []
	for pos in state.grid:
		var cell = state.grid[pos]
		if cell.kind == "hub":
			hub_tiles.append(pos)
			hub_upkeep += GameBalance.HUB_TYPES[cell.htype].upkeep
	for pos in state.grid:
		var cell = state.grid[pos]
		if cell.kind == "route":
			var up: float = GameBalance.ROUTE_BASE_UPKEEP * GameBalance.ROUTE_LEVELS[cell.level].upkeep_mult
			for h in hub_tiles:
				if state.has_connection(pos, h):
					up *= 1.0 - float(GameBalance.HUB_TYPES[state.grid[h].htype].discount)
					break
			# The deck is a structure, not road surface, so its upkeep is added
			# after the hub discount rather than being discounted along with the
			# road underneath.
			if cell.has("bridge_axis"):
				up += GameBalance.BRIDGE_UPKEEP
			route_upkeep += up
		elif cell.kind == "storage":
			storage_upkeep += GameBalance.STORAGE_TYPES[cell.stype].upkeep

	var total_upkeep := route_upkeep + storage_upkeep + hub_upkeep
	var profit := income - total_upkeep - spoilage_cost
	state.balance += profit

	var avg_freshness_overall: float = fresh_weighted_sum / fresh_weight_total if fresh_weight_total > 0.0 else 0.0
	var waste_pct: float = (requested_total - delivered_total) / requested_total * 100.0 if requested_total > 0.0 else 0.0
	var avg_happiness := 0.0
	for s in settlement_scores:
		avg_happiness += s.sat
	avg_happiness /= maxf(float(settlement_scores.size()), 1.0)

	var grade_score: float = avg_freshness_overall * 0.35 + avg_happiness * 0.35 + (100.0 - waste_pct) * 0.15 + clampf(profit / 10.0, 0.0, 100.0) * 0.15
	var grade := "D"
	if grade_score >= 88.0:
		grade = "S"
	elif grade_score >= 75.0:
		grade = "A"
	elif grade_score >= 60.0:
		grade = "B"
	elif grade_score >= 40.0:
		grade = "C"

	var is_personal_best: bool = grade_score > state.best_score
	if is_personal_best:
		state.best_score = grade_score
		state.best_grade = grade
	state.score_history.append({"day": state.day, "score": grade_score, "grade": grade, "profit": profit})

	var source_status := {}
	for s in sources:
		var food_status := {}
		for food_id in s.produces:
			var produced: float = s.supply_of(food_id)
			var left: float = supply_left.get("%s|%s" % [s.node_id, food_id], produced)
			food_status[food_id] = {"produced": produced, "used": produced - left}
		source_status[s.node_id] = food_status

	state.last_flows = flows
	state.last_settlement_status = settlement_food_status
	state.last_source_status = source_status
	state.last_congestion.clear()
	for pos in state.grid:
		var cap := tile_capacity(state, pos)
		if not is_finite(cap):
			continue
		var used: float = tile_usage.get(pos, 0.0)
		if used >= cap * 0.9:
			state.last_congestion.append({"pos": pos, "over": used >= cap})

	report.income = income
	report.bonus_income = bonus_income
	report.withheld_income = withheld_income
	report.route_upkeep = route_upkeep
	report.storage_upkeep = storage_upkeep
	report.hub_upkeep = hub_upkeep
	report.total_upkeep = total_upkeep
	report.spoilage_cost = spoilage_cost
	report.profit = profit
	report.avg_freshness_overall = avg_freshness_overall
	report.waste_pct = waste_pct
	report.avg_happiness = avg_happiness
	report.settlements_taking_orders = settlement_scores.size()
	report.settlements_total = settlements.size()
	report.grade = grade
	report.grade_score = grade_score
	report.settlement_scores = settlement_scores
	report.capacity_blocked = capacity_blocked
	report.is_personal_best = is_personal_best
	return report
