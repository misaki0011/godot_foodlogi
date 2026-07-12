class_name SimulationEngine

static func simulate_day(state: GameState, map_data: MapData) -> DayReportData:
	var report := DayReportData.new()
	report.day = state.day
	var foods := GameBalance.food_types()
	var supplies: Dictionary = GameBalance.source_supplies().duplicate(true)
	var demands: Dictionary = GameBalance.settlement_demands()
	var nodes := _node_index(map_data.node_placements)
	var route_remaining: Dictionary = {}
	var node_remaining: Dictionary = {}
	for route in state.routes:
		route_remaining[route.route_id] = GameBalance.ROUTE_LEVELS[route.route_level].capacity
	for node in map_data.node_placements:
		if node.linked_resource is StorageData:
			node_remaining[node.node_id] = node.linked_resource.capacity
		elif node.linked_resource is HubData:
			node_remaining[node.node_id] = node.linked_resource.flow_capacity

	var ordered_demands: Array[Dictionary] = []
	for settlement_id in demands:
		for demand in demands[settlement_id]:
			ordered_demands.append({"settlement": settlement_id, "demand": demand})
			report.demanded_amount += demand.amount_required
	ordered_demands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.demand.minimum_freshness > b.demand.minimum_freshness
	)

	var settlement_stats: Dictionary = {}
	for entry in ordered_demands:
		var settlement_id: String = entry.settlement
		var demand: SettlementDemandData = entry.demand
		var food: FoodData = foods[demand.food_id]
		var delivered := 0.0
		var freshness := 0.0
		var freshness_total := 0.0
		var amount_remaining: float = demand.amount_required
		while amount_remaining > 0.001:
			var best := _best_supply_path(demand.food_id, settlement_id, supplies, state.routes, nodes, food, route_remaining, node_remaining)
			if best.is_empty():
				break
			var available: float = supplies[best.source][demand.food_id]
			var capacity := _path_capacity(best.path, route_remaining, node_remaining, nodes)
			var shipped: float = min(amount_remaining, available, capacity)
			if shipped <= 0.001:
				break
			_consume_capacity(best.path, shipped, route_remaining, node_remaining, nodes)
			supplies[best.source][demand.food_id] = available - shipped
			freshness = best.freshness
			amount_remaining -= shipped
			if freshness >= demand.minimum_freshness:
				delivered += shipped
				freshness_total += shipped * freshness
				var income := shipped * food.base_value * GameBalance.freshness_multiplier(freshness) * GameBalance.settlement_price(settlement_id)
				report.food_income += income
				report.delivered_amount += shipped
				report.delivered_freshness_total += shipped * freshness
			else:
				report.wasted_amount += shipped
				report.spoilage_cost += shipped * GameBalance.SPOILAGE_COST_PER_UNIT
		if delivered > 0.0:
			freshness = freshness_total / delivered
		var key := "%s:%s" % [settlement_id, demand.food_id]
		report.delivered[key] = {"amount": delivered, "freshness": freshness, "required": demand.amount_required}
		if not settlement_stats.has(settlement_id):
			settlement_stats[settlement_id] = {"score": 0.0, "weight": 0.0}
		var fulfillment: float = clamp(delivered / demand.amount_required, 0.0, 1.0)
		var freshness_score: float = clamp(freshness / demand.bonus_freshness, 0.0, 1.0) if delivered > 0.0 else 0.0
		var satisfaction := 60.0 * fulfillment + 40.0 * freshness_score
		settlement_stats[settlement_id].score += satisfaction * demand.amount_required
		settlement_stats[settlement_id].weight += demand.amount_required

	_calculate_upkeep(state, map_data, report, nodes)
	for stats in settlement_stats.values():
		var happiness: float = stats.score / max(stats.weight, 1.0)
		report.average_happiness += happiness
	for settlement_id in settlement_stats:
		report.settlement_happiness[settlement_id] = settlement_stats[settlement_id].score / max(settlement_stats[settlement_id].weight, 1.0)
	report.average_happiness /= max(settlement_stats.size(), 1)
	report.average_freshness = report.delivered_freshness_total / max(report.delivered_amount, 1.0)
	report.waste_percent = 100.0 * report.wasted_amount / max(report.demanded_amount, 1.0)
	report.profit = report.food_income - report.route_upkeep - report.storage_upkeep - report.hub_upkeep - report.spoilage_cost
	state.funds += report.profit
	if report.profit > 0.0:
		state.positive_profit_streak += 1
	else:
		state.positive_profit_streak = 0
	report.won = report.average_happiness >= 80.0 and report.average_freshness >= 70.0 and report.waste_percent < 20.0 and state.positive_profit_streak >= 3
	state.won = report.won
	report.grade = _grade(report)
	state.last_report = report
	state.day += 1
	return report

static func route_build_cost(map_data: MapData, path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		var terrain := map_data.get_terrain(path[i].x, path[i].y)
		total += GameBalance.ROUTE_BUILD_COST * GameBalance.TERRAIN_COST[terrain]
		if terrain == GameEnums.TerrainType.RIVER:
			total += GameBalance.BRIDGE_SURCHARGE
	return total

static func route_upkeep(route: RouteSegmentData) -> float:
	var multiplier: float = GameBalance.ROUTE_LEVELS[route.route_level].upkeep
	var total := 0.0
	for terrain in route.terrain_profile:
		total += GameBalance.ROUTE_BASE_UPKEEP * GameBalance.TERRAIN_COST[terrain] * multiplier
	return total

static func route_freshness(route: RouteSegmentData, food: FoodData, starting := 100.0, protection := {}) -> Dictionary:
	var freshness := starting
	var remaining: int = protection.get("distance", 0)
	var multiplier: float = protection.get("multiplier", 1.0)
	for terrain in route.terrain_profile:
		var applied := multiplier if remaining > 0 else 1.0
		freshness -= food.decay_per_tile * GameBalance.terrain_decay(terrain, food.food_id) * applied
		remaining = maxi(remaining - 1, 0)
	return {"freshness": maxf(freshness, 0.0), "distance": remaining, "multiplier": multiplier}

static func _best_supply_path(food_id: String, destination: String, supplies: Dictionary, routes: Array[RouteSegmentData], nodes: Dictionary, food: FoodData, route_remaining: Dictionary, node_remaining: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for source_id in supplies:
		if not supplies[source_id].has(food_id) or supplies[source_id][food_id] <= 0.0:
			continue
		for path in _all_paths(source_id, destination, routes):
			if _path_capacity(path, route_remaining, node_remaining, nodes) <= 0.001:
				continue
			var result := _path_freshness(path, food, nodes)
			var upkeep := 0.0
			for step in path:
				upkeep += route_upkeep(step.route)
			if best.is_empty() or result.freshness > best.freshness or (is_equal_approx(result.freshness, best.freshness) and upkeep < best.upkeep):
				best = {"source": source_id, "path": path, "freshness": result.freshness, "upkeep": upkeep}
	return best

static func _all_paths(from_id: String, to_id: String, routes: Array[RouteSegmentData]) -> Array[Array]:
	var adjacency: Dictionary = {}
	for route in routes:
		adjacency.get_or_add(route.from_node, []).append({"route": route, "to": route.to_node})
		adjacency.get_or_add(route.to_node, []).append({"route": route, "to": route.from_node})
	var results: Array[Array] = []
	_walk_paths(from_id, to_id, adjacency, {from_id: true}, [], results)
	return results

static func _walk_paths(current: String, target: String, adjacency: Dictionary, visited: Dictionary, path: Array, results: Array[Array]) -> void:
	if current == target:
		results.append(path.duplicate())
		return
	if path.size() >= 12:
		return
	for step in adjacency.get(current, []):
		if visited.has(step.to):
			continue
		visited[step.to] = true
		path.append(step)
		_walk_paths(step.to, target, adjacency, visited, path, results)
		path.pop_back()
		visited.erase(step.to)

static func _path_freshness(path: Array, food: FoodData, nodes: Dictionary) -> Dictionary:
	var result := {"freshness": 100.0, "distance": 0, "multiplier": 1.0}
	for step in path:
		result = route_freshness(step.route, food, result.freshness, result)
		var node: NodeData = nodes.get(step.to)
		if node and node.linked_resource is StorageData:
			var storage: StorageData = node.linked_resource
			if storage.storage_type == GameEnums.StorageType.FREEZE:
				result.freshness = maxf(result.freshness - food.freeze_penalty, 0.0)
			result.distance = storage.protection_distance
			result.multiplier = storage.freshness_loss_multiplier
	return result

static func _path_capacity(path: Array, route_remaining: Dictionary, node_remaining: Dictionary, nodes: Dictionary) -> float:
	var capacity := INF
	for step in path:
		capacity = minf(capacity, route_remaining[step.route.route_id])
		var node: NodeData = nodes.get(step.to)
		if node and node.node_type in [GameEnums.NodeType.STORAGE, GameEnums.NodeType.HUB]:
			capacity = minf(capacity, node_remaining[node.node_id])
	return capacity

static func _consume_capacity(path: Array, amount: float, route_remaining: Dictionary, node_remaining: Dictionary, nodes: Dictionary) -> void:
	for step in path:
		route_remaining[step.route.route_id] -= amount
		var node: NodeData = nodes.get(step.to)
		if node and node.node_type in [GameEnums.NodeType.STORAGE, GameEnums.NodeType.HUB]:
			node_remaining[node.node_id] -= amount

static func _calculate_upkeep(state: GameState, map_data: MapData, report: DayReportData, nodes: Dictionary) -> void:
	for route in state.routes:
		var base := route_upkeep(route)
		var discount := 0.0
		for node_id in [route.from_node, route.to_node]:
			var node: NodeData = nodes.get(node_id)
			if node and node.linked_resource is HubData:
				discount = maxf(discount, node.linked_resource.route_discount)
		report.hub_savings += base * discount
		report.route_upkeep += base * (1.0 - discount)
	for node in map_data.node_placements:
		if node.linked_resource is StorageData:
			report.storage_upkeep += node.linked_resource.daily_upkeep
		elif node.linked_resource is HubData:
			report.hub_upkeep += node.linked_resource.daily_upkeep

static func _node_index(nodes: Array[NodeData]) -> Dictionary:
	var result := {}
	for node in nodes:
		result[node.node_id] = node
	return result

static func _grade(report: DayReportData) -> String:
	var score := report.average_freshness * 0.35 + report.average_happiness * 0.35 + (100.0 - report.waste_percent) * 0.2
	if report.profit > 0:
		score += 10.0
	if score >= 92:
		return "S"
	if score >= 82:
		return "A"
	if score >= 70:
		return "B"
	if score >= 55:
		return "C"
	return "D"
