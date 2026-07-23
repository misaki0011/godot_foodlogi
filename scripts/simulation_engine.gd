class_name SimulationEngine

## Ported 1:1 from fresh-routes-mvp.html's grid/graph/simulation functions.
## The world is a plain tile grid (GameState.grid, Vector2i -> cell) plus a
## fixed set of source/settlement nodes -- not a node-to-node route-segment
## graph. Hubs auto-form (and are capped per connected network) exactly as
## in the HTML; see checkAutoHubs there and SPEC.md §4.4.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func neighbors(pos: Vector2i, grid_size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		var n := pos + d
		if n.x >= 0 and n.y >= 0 and n.x < grid_size.x and n.y < grid_size.y:
			result.append(n)
	return result

## Hub-formation degree: how many of this tile's sides are neighbors that a
## delivery can flow to/from -- route/storage/hub tiles AND source/settlement
## nodes (see check_auto_hubs/would_exceed_hub_cap). Adjacent nodes DO count
## (revised in v0.4): a hub is any tile where a source's (or settlement's)
## delivery fans out to more than one path, and the player doesn't care
## whether one of those three-plus branches happens to be a node rather than
## another road -- a tile fed by a source that then splits toward two roads
## is exactly the branching junction a hub represents. (This reverses the
## earlier v0.4 rule that excluded nodes; see the changelog.)
static func tile_degree(pos: Vector2i, state: GameState, nodes_by_pos: Dictionary) -> int:
	var count := 0
	for d in DIRECTIONS:
		var n := pos + d
		if n.x < 0 or n.y < 0 or n.x >= GameBalance.GRID_SIZE.x or n.y >= GameBalance.GRID_SIZE.y:
			continue
		if state.grid.has(n) or nodes_by_pos.has(n):
			count += 1
	return count

const STRAIGHT_FACINGS: Array[String] = ["lr", "ud"]
const CORNER_FACINGS: Array[String] = ["ne", "se", "sw", "nw"]

## Which of this tile's sides are real route/storage/hub neighbors, used for
## auto-deriving visual shape in route_shape(). Source/settlement nodes are
## excluded here on purpose: a node has its own separate marker and shouldn't
## drive the road's rendered shape (unlike tile_degree(), which counts nodes
## for hub-formation). Keyed by compass side: (0,-1)=north, (1,0)=east,
## (0,1)=south, (-1,0)=west, matching how world Z increases with grid Y (see
## main.gd's map_to_local usage).
static func _grid_only_sides(pos: Vector2i, state: GameState) -> Dictionary:
	var sides := {"n": false, "e": false, "s": false, "w": false}
	var dir_keys := {Vector2i(0, -1): "n", Vector2i(1, 0): "e", Vector2i(0, 1): "s", Vector2i(-1, 0): "w"}
	for d in DIRECTIONS:
		var n := pos + d
		if n.x < 0 or n.y < 0 or n.x >= GameBalance.GRID_SIZE.x or n.y >= GameBalance.GRID_SIZE.y:
			continue
		if state.grid.has(n):
			sides[dir_keys[d]] = true
	return sides

## The shape that truthfully matches this tile's real connections, or {} if
## the count (0, 1, or 3+) doesn't uniquely determine one.
static func _natural_facing(sides: Dictionary) -> Dictionary:
	var count: int = int(sides.n) + int(sides.e) + int(sides.s) + int(sides.w)
	if count != 2:
		return {}
	if sides.n and sides.s:
		return {"family": "straight", "facing": "ud"}
	if sides.e and sides.w:
		return {"family": "straight", "facing": "lr"}
	for facing in CORNER_FACINGS:
		if sides[facing[0]] and sides[facing[1]]:
			return {"family": "corner", "facing": facing}
	return {}

## Every tappable facing. Order doesn't matter for the default (see
## _best_default_facing) -- it only determines what cycle_shape_facing()
## advances to next.
static func _shape_cycle() -> Array[String]:
	return STRAIGHT_FACINGS + CORNER_FACINGS

## The compass side of this tile's one real route/storage/hub neighbor, or
## "" if there isn't exactly one (0, 2, or 3+ real sides).
static func _single_real_side(sides: Dictionary) -> String:
	var found := ""
	var count := 0
	for side in ["n", "e", "s", "w"]:
		if sides[side]:
			count += 1
			found = side
	return found if count == 1 else ""

## Best-effort default facing for a tile whose shape isn't forced (see
## route_shape()) and has no stored tap override yet. Derived purely from the
## tile's real route/storage/hub neighbors -- adjacent source/settlement nodes
## are deliberately ignored so a road never bends toward or "connects to" a
## node it happens to sit beside (the node has its own marker; the road only
## traces real route geometry). A lone stub with one real route side reads as
## a straight running along that side; with nothing real to go on it falls
## back to a plain "lr". Any tile stays freely tap-cycleable to any of the 6
## shapes from here (see is_shape_ambiguous/cycle_shape_facing).
static func _best_default_facing(sides: Dictionary) -> String:
	var route_side := _single_real_side(sides)
	if route_side != "":
		return "ud" if (route_side == "n" or route_side == "s") else "lr"
	return "lr"

## Auto-derives a route tile's visual shape from its real connections (see
## AGENTS.md route-direction feature and the v0.4 "tap and hold to draw"
## changelog entry). Shape depends ONLY on real route/storage/hub neighbors --
## an adjacent source or settlement never forces, locks, or bends the tile
## (revised in v0.4: nodes were previously allowed to pull a road-stub toward
## themselves, which read as the road always "connecting" to the node it sat
## beside). Every route tile -- regardless of its real connection count and
## regardless of any neighboring node -- is always player-choosable by tap,
## defaulting to whatever shape matches its real route connections when
## nothing's been tapped yet, or the stored override once it has (see
## is_shape_ambiguous/cycle_shape_facing). `_nodes_by_pos` is kept on the
## signature for call-site stability but no longer influences the shape.
static func route_shape(pos: Vector2i, state: GameState, _nodes_by_pos: Dictionary) -> Dictionary:
	var sides := _grid_only_sides(pos, state)
	var cycle := _shape_cycle()
	var stored = state.grid.get(pos, {}).get("facing", "")
	if cycle.has(stored):
		return {"family": "corner" if CORNER_FACINGS.has(stored) else "straight", "facing": stored}
	var natural := _natural_facing(sides)
	if not natural.is_empty():
		return natural
	var facing: String = _best_default_facing(sides)
	return {"family": "corner" if CORNER_FACINGS.has(facing) else "straight", "facing": facing}

## True when tapping this route tile should cycle its shape instead of
## no-opping. Every route tile is now freely tappable regardless of its real
## connection count or any neighboring source/settlement -- nodes no longer
## lock a tile's shape (see route_shape()). `_state`/`_nodes_by_pos` are kept
## on the signature for call-site stability.
static func is_shape_ambiguous(_pos: Vector2i, _state: GameState, _nodes_by_pos: Dictionary) -> bool:
	return true

## Returns the next facing to store for an ambiguous route tile (caller
## should confirm is_shape_ambiguous(pos, state, nodes_by_pos) first --
## forced shapes aren't cycleable).
static func cycle_shape_facing(pos: Vector2i, state: GameState, nodes_by_pos: Dictionary) -> String:
	var current := route_shape(pos, state, nodes_by_pos)
	var cycle := _shape_cycle()
	var idx: int = cycle.find(current.facing)
	return cycle[(idx + 1) % cycle.size()]

## key -> [key, ...]; every built tile connects to adjacent built tiles or
## nodes, and every node connects to its adjacent built tiles (nodes never
## link directly to another node without a route tile between them).
static func build_graph(state: GameState, nodes_by_pos: Dictionary) -> Dictionary:
	var adj := {}
	for pos in state.grid.keys():
		for n in neighbors(pos, GameBalance.GRID_SIZE):
			if state.grid.has(n) or nodes_by_pos.has(n):
				adj.get_or_add(pos, []).append(n)
				adj.get_or_add(n, []).append(pos)
	for pos in nodes_by_pos.keys():
		for n in neighbors(pos, GameBalance.GRID_SIZE):
			if state.grid.has(n):
				adj.get_or_add(pos, []).append(n)
				adj.get_or_add(n, []).append(pos)
	return adj

static func compute_components(state: GameState, nodes_by_pos: Dictionary) -> Dictionary:
	var adj := build_graph(state, nodes_by_pos)
	var comp_of := {}
	var comp_id := 0
	for start in adj.keys():
		if comp_of.has(start):
			continue
		var queue: Array = [start]
		comp_of[start] = comp_id
		while not queue.is_empty():
			var u = queue.pop_front()
			for v in adj.get(u, []):
				if not comp_of.has(v):
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
## pure endpoint, §4.7), so connectivity is computed over built tiles ALONE:
## two roads link only when orthogonally adjacent, never "through" a node
## they both touch. A road network qualifies only when it touches at least
## one source AND at least one settlement -- this is what keeps a
## settlement-to-settlement road (reachable from no source) out, even when
## some unrelated source sits elsewhere on the map. Within a qualifying
## network, dead-end stubs are pruned: a tile survives only while it still
## links to 2+ things (another kept tile, or a node it anchors to), leaving
## the through-paths that run from a source to a settlement.
static func established_route_cells(state: GameState, nodes_by_pos: Dictionary) -> Dictionary:
	# Road-only connected components (nodes are not transit vertices).
	var comp_of := {}
	var comp_id := 0
	for start in state.grid:
		if comp_of.has(start):
			continue
		var queue: Array[Vector2i] = [start]
		comp_of[start] = comp_id
		while not queue.is_empty():
			var u: Vector2i = queue.pop_front()
			for d in DIRECTIONS:
				var v: Vector2i = u + d
				if state.grid.has(v) and not comp_of.has(v):
					comp_of[v] = comp_id
					queue.append(v)
		comp_id += 1
	# Which road networks touch a source / a settlement (adjacency to a node).
	var comp_has_source := {}
	var comp_has_settlement := {}
	for pos in state.grid:
		var comp = comp_of[pos]
		for d in DIRECTIONS:
			var node: NodeData = nodes_by_pos.get(pos + d)
			if node == null:
				continue
			if node.node_type == GameEnums.NodeType.SOURCE:
				comp_has_source[comp] = true
			else:
				comp_has_settlement[comp] = true
	var kept := {}
	for pos in state.grid:
		var comp = comp_of[pos]
		if comp_has_source.get(comp, false) and comp_has_settlement.get(comp, false):
			kept[pos] = true
	# Iteratively prune dead-end tiles. A tile survives only while it links to
	# 2+ things (kept tiles or nodes) -- i.e. it's mid-path, not a stub tip.
	var changed := true
	while changed:
		changed = false
		for pos in kept.keys():
			var degree := 0
			for d in DIRECTIONS:
				var n: Vector2i = pos + d
				if kept.has(n) or nodes_by_pos.has(n):
					degree += 1
			if degree <= 1:
				kept.erase(pos)
				changed = true
	return kept

## Read-only preview for main.gd's route-placement validation: would
## building a route tile at new_cell push some junction (the new tile
## itself, or an existing route tile newly connected through it) to 3+
## connections inside a network that's already at HUB_CAP_PER_NETWORK
## hubs? Only tiles whose degree actually changes because of this one
## placement are considered, so an already-hub_capped junction elsewhere
## doesn't block unrelated route building.
static func would_exceed_hub_cap(state: GameState, nodes_by_pos: Dictionary, new_cell: Vector2i) -> bool:
	if state.grid.has(new_cell):
		return false
	var temp_grid := state.grid.duplicate()
	temp_grid[new_cell] = {"kind": "route", "level": "dirt"}
	var temp_state := GameState.new()
	temp_state.grid = temp_grid

	var comp_of := compute_components(temp_state, nodes_by_pos)
	var hub_counts := {}
	for pos in state.grid.keys():
		var cell = state.grid[pos]
		if cell.kind == "hub":
			var c = comp_of.get(pos, -1)
			hub_counts[c] = hub_counts.get(c, 0) + 1

	var new_junctions: Array[Vector2i] = []
	if tile_degree(new_cell, temp_state, nodes_by_pos) >= 3:
		new_junctions.append(new_cell)
	for n in neighbors(new_cell, GameBalance.GRID_SIZE):
		var cell = state.grid.get(n)
		if cell == null or cell.kind != "route":
			continue
		if tile_degree(n, state, nodes_by_pos) < 3 and tile_degree(n, temp_state, nodes_by_pos) >= 3:
			new_junctions.append(n)

	for pos in new_junctions:
		var comp = comp_of.get(pos, -1)
		if hub_counts.get(comp, 0) >= GameBalance.HUB_CAP_PER_NETWORK:
			return true
	return false

## Mutates state.grid/state.balance: auto-forms a Small Hub on any route
## tile with 3+ connections, unless its connected network already has
## HUB_CAP_PER_NETWORK hubs (hub_capped) or funds are short (needs_hub).
## Returns "ok:<msg>" / "warn:<msg>" toast lines for newly-changed tiles.
static func check_auto_hubs(state: GameState, nodes_by_pos: Dictionary) -> Array[String]:
	var messages: Array[String] = []
	var comp_of := compute_components(state, nodes_by_pos)
	var hub_counts := {}
	for pos in state.grid.keys():
		var cell = state.grid[pos]
		if cell.kind == "hub":
			var c = comp_of.get(pos, -1)
			hub_counts[c] = hub_counts.get(c, 0) + 1
	for pos in state.grid.keys():
		var cell = state.grid[pos]
		if cell.kind != "route":
			continue
		var degree := tile_degree(pos, state, nodes_by_pos)
		if degree >= 3:
			var comp = comp_of.get(pos, -1)
			var count: int = hub_counts.get(comp, 0)
			if count >= GameBalance.HUB_CAP_PER_NETWORK:
				cell.needs_hub = false
				if not cell.get("hub_capped", false):
					messages.append("warn:Hub limit reached — this road already has %d hub%s. This junction stays capacity-limited." % [GameBalance.HUB_CAP_PER_NETWORK, "" if GameBalance.HUB_CAP_PER_NETWORK == 1 else "s"])
				cell.hub_capped = true
				continue
			cell.hub_capped = false
			var cost: float = GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build
			if state.balance >= cost:
				state.balance -= cost
				state.grid[pos] = {"kind": "hub", "htype": GameEnums.HubType.SMALL}
				hub_counts[comp] = count + 1
				messages.append("ok:Junction formed — Small Hub auto-built for §%d." % roundi(cost))
			else:
				cell.needs_hub = true
		else:
			cell.needs_hub = false
			cell.hub_capped = false
	return messages

## Dijkstra minimizing cumulative freshness-decay weight; ties broken
## naturally by whichever path accumulates less decay first.
static func find_path(state: GameState, nodes_by_pos: Dictionary, from_pos: Vector2i, to_pos: Vector2i, food: FoodData) -> Array[Vector2i]:
	var adj := build_graph(state, nodes_by_pos)
	if not adj.has(from_pos) or not adj.has(to_pos):
		return []
	var dist := {from_pos: 0.0}
	var prev := {}
	var visited := {}
	var frontier: Array = [[0.0, from_pos]]
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var top = frontier.pop_front()
		var d: float = top[0]
		var u: Vector2i = top[1]
		if visited.has(u):
			continue
		visited[u] = true
		if u == to_pos:
			break
		for v in adj.get(u, []):
			if visited.has(v):
				continue
			var w: float = 0.01 if nodes_by_pos.has(v) else food.decay_per_tile
			var nd := d + w
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				frontier.append([nd, v])
	if not dist.has(to_pos):
		return []
	var path: Array[Vector2i] = []
	var cur: Vector2i = to_pos
	while true:
		path.append(cur)
		if cur == from_pos:
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
	var used_freeze := false
	for i in range(1, path.size()):
		var cell = state.grid.get(path[i])
		var mult := 1.0
		if protection_left > 0:
			mult = protection_mult
			protection_left -= 1
		var decay: float = food.decay_per_tile * mult
		if cell and cell.kind == "storage":
			decay = 0.0
			var st = GameBalance.STORAGE_TYPES[cell.stype]
			protection_left = st.protection
			protection_mult = st.mult
			if cell.stype == GameEnums.StorageType.FREEZE:
				used_freeze = true
		fresh -= decay
	if used_freeze and food.freeze_penalty > 0.0:
		fresh -= food.freeze_penalty
	return clampf(fresh, 0.0, 100.0)

static func tile_capacity(state: GameState, pos: Vector2i) -> float:
	var cell = state.grid.get(pos)
	if cell == null:
		return INF
	if cell.kind == "route":
		return GameBalance.ROUTE_LEVELS[cell.level].cap
	if cell.kind == "hub":
		return GameBalance.HUB_TYPES[cell.htype].flow_capacity
	if cell.kind == "storage":
		return GameBalance.STORAGE_TYPES[cell.stype].capacity
	return INF

static func route_build_cost(pos: Vector2i, map_data: MapData) -> float:
	var cost := GameBalance.ROUTE_BUILD_COST
	if map_data.is_river(pos.x, pos.y):
		cost += GameBalance.BRIDGE_COST
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

## Runs one full day: demand generation + wobble, demand-pull source
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
		nodes_by_pos[n.grid_position] = n
		if n.node_type == GameEnums.NodeType.SOURCE:
			sources.append(n)
		else:
			settlements.append(n)

	var tile_usage := {}
	var supply_left := {}
	for s in sources:
		for food_id in s.produces:
			supply_left["%s|%s" % [s.node_id, food_id]] = s.produces[food_id]

	var flows: Array[Dictionary] = []
	var income := 0.0
	var spoilage_cost := 0.0
	var delivered_total := 0.0
	var requested_total := 0.0
	var fresh_weighted_sum := 0.0
	var fresh_weight_total := 0.0
	var capacity_blocked := 0.0
	var settlement_food_status := {}
	var settlement_scores: Array[Dictionary] = []

	for settlement in settlements:
		var fulfilled := 0.0
		var requested := 0.0
		var fresh_sum := 0.0
		var fresh_count := 0.0
		var rejected := 0.0
		var food_status := {}
		settlement_food_status[settlement.node_id] = food_status
		for food_id in settlement.demand:
			var wobble := 0.85 + randf() * 0.4
			var need: float = maxf(1.0, roundf(settlement.demand[food_id] * wobble))
			requested += need
			requested_total += need
			food_status[food_id] = {"requested": need, "delivered": 0.0, "rejected": 0.0, "fresh_sum": 0.0}
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
					spoilage_cost += amt * food.base_value * 0.5
					flows.append({"food": food_id, "path": c.path, "delivered": 0.0, "rejected": amt, "settlement": settlement.node_id, "source": c.src.node_id})
				else:
					fulfilled += amt
					delivered_total += amt
					food_status[food_id].delivered += amt
					food_status[food_id].fresh_sum += fresh * amt
					income += amt * food.base_value * mult
					fresh_sum += fresh * amt
					fresh_count += amt
					fresh_weighted_sum += fresh * amt
					fresh_weight_total += amt
					flows.append({"food": food_id, "path": c.path, "delivered": amt, "fresh": fresh, "settlement": settlement.node_id, "source": c.src.node_id})
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
				if absi(h.x - pos.x) + absi(h.y - pos.y) == 1:
					up *= 1.0 - float(GameBalance.HUB_TYPES[state.grid[h].htype].discount)
					break
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
			var produced: float = s.produces[food_id]
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
	report.route_upkeep = route_upkeep
	report.storage_upkeep = storage_upkeep
	report.hub_upkeep = hub_upkeep
	report.total_upkeep = total_upkeep
	report.spoilage_cost = spoilage_cost
	report.profit = profit
	report.avg_freshness_overall = avg_freshness_overall
	report.waste_pct = waste_pct
	report.avg_happiness = avg_happiness
	report.grade = grade
	report.grade_score = grade_score
	report.settlement_scores = settlement_scores
	report.capacity_blocked = capacity_blocked
	report.is_personal_best = is_personal_best
	return report
