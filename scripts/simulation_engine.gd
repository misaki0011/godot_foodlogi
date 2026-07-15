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

static func tile_degree(pos: Vector2i, state: GameState, nodes_by_pos: Dictionary) -> int:
	var count := 0
	for n in neighbors(pos, GameBalance.GRID_SIZE):
		if state.grid.has(n) or nodes_by_pos.has(n):
			count += 1
	return count

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

	state.last_flows = flows
	state.last_settlement_status = settlement_food_status
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
