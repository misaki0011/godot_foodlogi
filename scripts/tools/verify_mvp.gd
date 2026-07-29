extends SceneTree

## One-shot dev check (not part of the game): exercises SimulationEngine
## against the tile-grid model ported from fresh-routes-mvp.html.
## Run via: godot --headless --script res://scripts/tools/verify_mvp.gd

func _initialize() -> void:
	_test_route_build_cost()
	_test_storage_preservation()
	_test_daily_simulation()
	_test_hub_cap_per_network()
	_test_established_route_cells()
	_test_hub_buildable_on_any_route_tile()
	_test_delivery_does_not_transit_nodes()
	_test_bridge_keeps_crossing_routes_separate()
	_test_bridge_cap_per_network()
	_test_bridge_deck_costs_extra_freshness()
	_test_map_is_sound()
	_test_days_alone_open_nothing()
	_test_filling_offers_a_choice()
	_test_accepting_returns_the_other_to_the_pool()
	_test_offers_stay_within_reach()
	_test_offers_are_seeded()
	_test_dormant_settlements_are_not_scored()
	_test_demand_and_freshness_are_stable()
	print("MVP simulation checks passed.")
	quit()

func _test_route_build_cost() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var plains_cost := SimulationEngine.route_build_cost(Vector2i(4, 4), map)
	assert(is_equal_approx(plains_cost, GameBalance.ROUTE_BUILD_COST))
	var river_cost := SimulationEngine.route_build_cost(Vector2i(GameBalance.RIVER_COL, 4), map)
	assert(is_equal_approx(river_cost, GameBalance.ROUTE_BUILD_COST + GameBalance.RIVER_BRIDGE_COST), "River tiles must add the bridge surcharge")

func _test_storage_preservation() -> void:
	var state := GameState.new()
	var milk: FoodData = GameBalance.food_types().milk
	# 3 plain tiles, then a Cool Storage tile, then 3 more plain tiles.
	state.grid[Vector2i(1, 0)] = {"kind": "route", "level": "dirt"}
	state.grid[Vector2i(2, 0)] = {"kind": "route", "level": "dirt"}
	state.grid[Vector2i(3, 0)] = {"kind": "storage", "stype": GameEnums.StorageType.COOL}
	state.grid[Vector2i(4, 0)] = {"kind": "route", "level": "dirt"}
	state.grid[Vector2i(5, 0)] = {"kind": "route", "level": "dirt"}
	var protected_path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	var direct_path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	for i in range(3):
		direct_path.append(Vector2i(3 + i, 1))
	var protected_fresh := SimulationEngine.simulate_freshness(state, protected_path, milk)
	var direct_fresh := SimulationEngine.simulate_freshness(state, direct_path, milk)
	assert(protected_fresh > direct_fresh, "Cool Storage must slow decay for the tiles after it")
	assert(protected_fresh <= 100.0, "Storage preserves but never restores freshness")

func _test_daily_simulation() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	var state := GameState.new()
	var farm := _node(map, "farm")
	var village_a := _node(map, "villageA")
	# A short dirt-route path connecting Farm to Village A.
	var route_path: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3)]
	for cell in route_path:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(farm.grid_position, route_path[0])
	_connect_chain(state, route_path)
	state.add_connection(route_path[-1], village_a.grid_position)
	# Grain at Village A is one of the map's opening orders (DEV-01); this test
	# only lays road to Village A, so grain is the only line that can arrive.
	OrderBook.initialize(state, map)
	var report := SimulationEngine.run_day(state, map.node_placements)
	var grain_status: Dictionary = state.last_settlement_status[village_a.node_id].grain
	print("Village A grain: %.1f / %.1f delivered" % [grain_status.delivered, grain_status.requested])
	assert(grain_status.delivered > 0.0, "Grain should reach Village A over a short, fresh dirt route")
	assert(is_equal_approx(grain_status.delivered, grain_status.requested), "Ample supply/capacity should fully cover Village A's grain demand")
	assert(report.income > 0.0)
	assert(report.route_upkeep > 0.0)
	assert(state.day == 1, "run_day must not itself advance the day counter (Main._close_report does)")

func _test_hub_cap_per_network() -> void:
	# A hub can be built on ANY route tile (v0.5 revision -- no completed-
	# route-fork requirement); the only remaining constraint is the per-
	# network cap, checked live via SimulationEngine.network_at_hub_cap
	# rather than a precomputed per-cell flag.
	var state := GameState.new()
	var spine: Array[Vector2i] = [Vector2i(2, 10), Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10)]
	for cell in spine:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	_connect_chain(state, spine)

	var hub_cost: float = GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build
	for i in range(GameBalance.HUB_CAP_PER_NETWORK):
		assert(not SimulationEngine.network_at_hub_cap(state, spine[i]), "Network must accept hubs up to the cap")
		state.grid[spine[i]] = {"kind": "hub", "htype": GameEnums.HubType.SMALL}
		state.balance -= hub_cost

	var capped_count := 0
	for cell in spine:
		if state.grid[cell].kind != "hub":
			assert(SimulationEngine.network_at_hub_cap(state, cell), "Any remaining route tile on a network already at its hub cap must refuse a new hub")
			capped_count += 1
	print("Hubs built: %d, capped tiles: %d (cap is %d)" % [GameBalance.HUB_CAP_PER_NETWORK, capped_count, GameBalance.HUB_CAP_PER_NETWORK])
	assert(capped_count == spine.size() - GameBalance.HUB_CAP_PER_NETWORK, "Every non-hub tile on an at-cap network must refuse a new hub")

func _test_established_route_cells() -> void:
	# Synthetic layout (col,row): a source S at (0,0) linked by a vertical road
	# down to settlement A at (0,4); a dead-end stub off the middle; a
	# settlement-to-settlement road (B..C) with no source anywhere on it; and a
	# source-fed road (from D) that reaches no settlement.
	var nodes_by_pos := {}
	nodes_by_pos[Vector2i(0, 0)] = _make_node(GameEnums.NodeType.SOURCE)      # S
	nodes_by_pos[Vector2i(0, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # A
	nodes_by_pos[Vector2i(5, 0)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # B
	nodes_by_pos[Vector2i(5, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # C
	nodes_by_pos[Vector2i(8, 0)] = _make_node(GameEnums.NodeType.SOURCE)      # D

	var state := GameState.new()
	var s_to_a: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)] # S -> A path
	for cell in s_to_a:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(Vector2i(0, 0), s_to_a[0])
	_connect_chain(state, s_to_a)
	state.add_connection(s_to_a[-1], Vector2i(0, 4))
	state.grid[Vector2i(1, 2)] = {"kind": "route", "level": "dirt"} # dead-end stub
	state.add_connection(Vector2i(0, 2), Vector2i(1, 2))
	var b_to_c: Array[Vector2i] = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)] # B <-> C, no source
	for cell in b_to_c:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(Vector2i(5, 0), b_to_c[0])
	_connect_chain(state, b_to_c)
	state.add_connection(b_to_c[-1], Vector2i(5, 4))
	var from_d: Array[Vector2i] = [Vector2i(8, 1), Vector2i(8, 2)] # from D, reaches no settlement
	for cell in from_d:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(Vector2i(8, 0), from_d[0])
	_connect_chain(state, from_d)

	var est := SimulationEngine.established_route_cells(state, nodes_by_pos)
	assert(est.has(Vector2i(0, 1)) and est.has(Vector2i(0, 2)) and est.has(Vector2i(0, 3)), "The whole source->settlement path must be established")
	assert(not est.has(Vector2i(1, 2)), "A dead-end stub off the path must be pruned out")
	assert(not est.has(Vector2i(5, 1)) and not est.has(Vector2i(5, 2)) and not est.has(Vector2i(5, 3)), "A settlement-to-settlement road with no source must not be established")
	assert(not est.has(Vector2i(8, 1)) and not est.has(Vector2i(8, 2)), "A source-fed road that reaches no settlement must not be established")
	assert(est.size() == 3, "Only the three source->settlement tiles should be established")

func _test_hub_buildable_on_any_route_tile() -> void:
	# v0.5 revision: a hub no longer requires a completed-route fork -- any
	# built route tile qualifies, even a plain straight run, an isolated stub
	# with no node nearby, or one that reaches no settlement at all. The only
	# remaining constraint is the per-network hub cap (tested separately in
	# _test_hub_cap_per_network).
	var isolated := GameState.new()
	isolated.grid[Vector2i(0, 0)] = {"kind": "route", "level": "dirt"}
	assert(not SimulationEngine.network_at_hub_cap(isolated, Vector2i(0, 0)), "An isolated route tile with no hubs on its network must be buildable")

	var straight := GameState.new()
	var chain: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	for cell in chain:
		straight.grid[cell] = {"kind": "route", "level": "dirt"}
	_connect_chain(straight, chain)
	for cell in chain:
		assert(not SimulationEngine.network_at_hub_cap(straight, cell), "Every tile of a plain straight route (no branch) must be a valid hub site")

func _test_delivery_does_not_transit_nodes() -> void:
	# S -- road -- M(settlement) -- road -- D(settlement), all in a line. The
	# only road chain from S to D would have to pass THROUGH settlement M, which
	# a delivery may never do (a node is a start/end point, never a transit
	# shortcut), so D is unreachable from S.
	var grain: FoodData = GameBalance.food_types().grain
	var nodes := {}
	nodes[Vector2i(0, 0)] = _make_node(GameEnums.NodeType.SOURCE)      # S
	nodes[Vector2i(0, 2)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # M, in the middle
	nodes[Vector2i(0, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # D, the target
	var state := GameState.new()
	state.grid[Vector2i(0, 1)] = {"kind": "route", "level": "dirt"}
	state.grid[Vector2i(0, 3)] = {"kind": "route", "level": "dirt"}
	state.add_connection(Vector2i(0, 0), Vector2i(0, 1))
	state.add_connection(Vector2i(0, 1), Vector2i(0, 2))
	state.add_connection(Vector2i(0, 2), Vector2i(0, 3))
	state.add_connection(Vector2i(0, 3), Vector2i(0, 4))
	assert(SimulationEngine.find_path(state, nodes, Vector2i(0, 0), Vector2i(0, 4), grain).is_empty(), "A delivery must not route through an intermediate settlement/source node")
	# The source still reaches the settlement it connects to over clear road.
	assert(not SimulationEngine.find_path(state, nodes, Vector2i(0, 0), Vector2i(0, 2), grain).is_empty(), "A source must still reach a settlement over a clear road path")

## The whole point of a bridge: two routes share one cell and stay separate
## networks. Layout -- a north-south road from source S down to settlement A,
## bridged at its midpoint, and an east-west road from source E that crosses
## over the deck on its way to settlement W.
##
##            S                     W --- [X] --- E     (X = the bridge tile)
##            |                            |
##           [X]  <- same tile             A
##            |
##            A
func _test_bridge_keeps_crossing_routes_separate() -> void:
	var grain: FoodData = GameBalance.food_types().grain
	var bridge := Vector2i(2, 2)
	var nodes := {}
	nodes[Vector2i(2, 0)] = _make_node(GameEnums.NodeType.SOURCE)      # S, north
	nodes[Vector2i(2, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # A, south
	nodes[Vector2i(4, 2)] = _make_node(GameEnums.NodeType.SOURCE)      # E, east
	nodes[Vector2i(0, 2)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # W, west

	var state := GameState.new()
	for cell in [Vector2i(2, 1), Vector2i(2, 3), Vector2i(1, 2), Vector2i(3, 2)]:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	# The north-south road came first, so the deck runs east-west across it.
	state.grid[bridge] = {"kind": "route", "level": "dirt", "bridge_axis": Vector2i(1, 0)}
	var north_south: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), bridge, Vector2i(2, 3), Vector2i(2, 4)]
	var east_west: Array[Vector2i] = [Vector2i(4, 2), Vector2i(3, 2), bridge, Vector2i(1, 2), Vector2i(0, 2)]
	_connect_chain(state, north_south)
	_connect_chain(state, east_west)

	# Each road still works end to end straight through the crossing.
	assert(not SimulationEngine.find_path(state, nodes, Vector2i(2, 0), Vector2i(2, 4), grain).is_empty(), "The road under a bridge must still run straight through it")
	assert(not SimulationEngine.find_path(state, nodes, Vector2i(4, 2), Vector2i(0, 2), grain).is_empty(), "The deck must carry its own route straight over the bridge")
	# But neither can turn onto the other: that's the whole feature.
	assert(SimulationEngine.find_path(state, nodes, Vector2i(2, 0), Vector2i(0, 2), grain).is_empty(), "A delivery must never turn off the road below onto the deck")
	assert(SimulationEngine.find_path(state, nodes, Vector2i(4, 2), Vector2i(2, 4), grain).is_empty(), "A delivery must never drop off the deck onto the road below")
	# Two separate networks, despite physically sharing a cell.
	var comp_of := SimulationEngine.road_components(state)
	assert(comp_of[SimulationEngine.vertex(Vector2i(2, 1), SimulationEngine.LANE_GROUND)] != comp_of[SimulationEngine.vertex(Vector2i(1, 2), SimulationEngine.LANE_GROUND)],
		"Roads crossing at a bridge must stay separate connected networks")
	# Both crossings are live routes, so the overlay lights up both lanes.
	var est := SimulationEngine.established_route_vertices(state, nodes)
	assert(est.has(SimulationEngine.vertex(bridge, SimulationEngine.LANE_GROUND)), "The road under a live bridge must be established")
	assert(est.has(SimulationEngine.vertex(bridge, SimulationEngine.LANE_DECK)), "The deck of a live bridge must be established")

func _test_bridge_cap_per_network() -> void:
	# One straight road with enough tiles to bridge every other one. A bridge
	# counts against the network of the road it sits on, so the cap bites once
	# BRIDGE_CAP_PER_NETWORK of them exist -- even though nothing has been
	# drawn across any of them yet.
	var state := GameState.new()
	var spine: Array[Vector2i] = []
	for x in range(1, 10):
		var cell := Vector2i(x, 5)
		spine.append(cell)
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	_connect_chain(state, spine)

	for i in range(GameBalance.BRIDGE_CAP_PER_NETWORK):
		var cell: Vector2i = spine[i * 2 + 1]
		assert(not SimulationEngine.network_at_bridge_cap(state, cell), "A network under its bridge cap must accept another bridge")
		state.grid[cell]["bridge_axis"] = Vector2i(0, 1)
	for cell in spine:
		if not SimulationEngine.is_bridge(state, cell):
			assert(SimulationEngine.network_at_bridge_cap(state, cell), "Every remaining tile on an at-cap network must refuse a new bridge")

	# A second, unconnected road gets its own budget.
	var other := Vector2i(1, 9)
	state.grid[other] = {"kind": "route", "level": "dirt"}
	assert(not SimulationEngine.network_at_bridge_cap(state, other), "An unconnected road network must have its own bridge budget")

func _test_bridge_deck_costs_extra_freshness() -> void:
	# The same straight run, once as plain road and once with its middle tile
	# bridged. Crossing the deck must cost strictly more freshness -- that's
	# what stops an overpass from being a free upgrade over going around.
	var milk: FoodData = GameBalance.food_types().milk
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var plain := GameState.new()
	var bridged := GameState.new()
	for cell in path:
		plain.grid[cell] = {"kind": "route", "level": "dirt"}
		bridged.grid[cell] = {"kind": "route", "level": "dirt"}
	# Deck runs east-west, i.e. along the path -- so this path IS on the deck.
	bridged.grid[Vector2i(2, 0)]["bridge_axis"] = Vector2i(1, 0)
	var over_deck := SimulationEngine.simulate_freshness(bridged, path, milk)
	assert(over_deck < SimulationEngine.simulate_freshness(plain, path, milk), "Crossing a bridge deck must cost extra freshness decay")

	# The road passing UNDERNEATH pays nothing extra: same tile, other axis.
	var under: Array[Vector2i] = [Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1)]
	var under_plain: Array[Vector2i] = [Vector2i(5, -1), Vector2i(5, 0), Vector2i(5, 1)]
	for cell in under_plain:
		bridged.grid[cell] = {"kind": "route", "level": "dirt"}
	assert(is_equal_approx(SimulationEngine.simulate_freshness(bridged, under, milk), SimulationEngine.simulate_freshness(bridged, under_plain, milk)),
		"The road under a bridge must decay exactly like plain road")

## Connects each consecutive pair in `cells` -- mirrors what a real drag
## gesture would link, since state.grid[cell] = ... no longer implies
## connectivity on its own (v0.5).
## ---------- gradual demand: offers (DEV-01) ----------

func _test_map_is_sound() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var problems := map.validate()
	for problem in problems:
		push_error("region_1_map: %s" % problem)
	assert(problems.is_empty(), "region_1_map must be internally consistent")

	# The map opens with its authored lines and nothing else -- far short of
	# the twelve-bubble wall this feature exists to remove, but more than the
	# single order that was over in one short road.
	var state := GameState.new()
	OrderBook.initialize(state, map)
	var open_lines := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			open_lines += OrderBook.active_demand(state, node).size()
	assert(open_lines == map.opening_lines.size(),
		"The map must open with exactly its opening_lines, got %d of %d" % [open_lines, map.opening_lines.size()])
	assert(open_lines == 3, "The opening is meant to be three orders, got %d" % open_lines)
	assert(state.offers.is_empty(), "No offer is on the table before anything is filled")

	# The opening must stay gentle: nothing in it may be harder than the
	# median line on the map.
	var ranked := map.demand_lines()
	ranked.sort_custom(func(a, b): return a.difficulty < b.difficulty)
	var median: float = ranked[ranked.size() / 2].difficulty
	for line in map.opening_lines:
		for ranked_line in ranked:
			if ranked_line.node_id == line.node_id and ranked_line.food_id == line.food_id:
				assert(ranked_line.difficulty <= median,
					"Opening line %s/%s is harder than the map's median" % [line.node_id, line.food_id])

	# Difficulty has to rank the region, or the eligibility pool is noise.
	# Grain at Village A is four steps from the Farm at 0.5 decay; City E's
	# vegetables are a 16-step haul at 2.5 into a 90% bonus line.
	var lines := map.demand_lines()
	lines.sort_custom(func(a, b): return a.difficulty < b.difficulty)
	assert(lines[0].node_id == "villageA" and lines[0].food_id == "grain",
		"Village A grain must rank easiest, got %s/%s" % [lines[0].node_id, lines[0].food_id])
	assert(lines[-1].node_id == "cityE" and lines[-1].food_id == "vegetables",
		"City E vegetables must rank hardest, got %s/%s" % [lines[-1].node_id, lines[-1].food_id])
	print("Difficulty ranking: easiest %s/%s (%.1f), hardest %s/%s (%.1f)." % [
		lines[0].node_id, lines[0].food_id, lines[0].difficulty,
		lines[-1].node_id, lines[-1].food_id, lines[-1].difficulty,
	])

## The whole point of the rewrite: the calendar no longer moves progression.
func _test_days_alone_open_nothing() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := GameState.new()
	OrderBook.initialize(state, map)
	# Fifty days pass with nothing delivered -- no roads, no fills.
	for _day in range(50):
		state.day += 1
		OrderBook.record_day(state, map.node_placements)
		OrderBook.draw_offers(state, map)
	assert(state.offers.is_empty(), "Idle days must not put an offer on the table")
	assert(state.pending_draws == 0, "Idle days must not owe a draw")
	var open_lines := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			open_lines += OrderBook.active_demand(state, node).size()
	assert(open_lines == map.opening_lines.size(),
		"After 50 idle days the map must still hold only its opening orders, got %d" % open_lines)
	print("50 idle days opened nothing.")

func _test_filling_offers_a_choice() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := _state_with_villageA_grain_filled(map)

	assert(state.pending_draws == 1, "Filling a line must earn exactly one draw")
	var offers := OrderBook.draw_offers(state, map)
	assert(offers.size() == 2, "A draw must put two offers on the table, got %d" % offers.size())
	assert(state.offers.size() == 2)

	# One deepen (another food for a settlement already taking orders), one
	# expand (a settlement taking none yet) -- the choice has to be between
	# two different KINDS of move, not two flavours of the same one. Which
	# settlements count as "already served" has to be read BEFORE the offers
	# are accepted, so classify against a snapshot.
	var served := {}
	for node_id in state.active_orders:
		if not state.active_orders[node_id].is_empty():
			served[node_id] = true
	var deepen := 0
	var expand := 0
	for offer in offers:
		if served.has(offer.node_id):
			deepen += 1
		else:
			expand += 1
	assert(deepen == 1 and expand == 1,
		"The pair must be one deepen and one expand, got %d/%d (%s)" % [deepen, expand, offers])

	# Filling again while the player is still deciding queues the draw rather
	# than crowding the map.
	state.pending_draws += 1
	assert(OrderBook.draw_offers(state, map).is_empty(), "A second pair must not deal while one is outstanding")
	assert(state.offers.size() == 2, "The table still holds exactly one pair")

func _test_accepting_returns_the_other_to_the_pool() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := _state_with_villageA_grain_filled(map)
	var offers := OrderBook.draw_offers(state, map)
	var taken: Dictionary = offers[0]
	var passed_over: Dictionary = offers[1]

	assert(OrderBook.accept_offer(state, taken), "Accepting an offer on the table must succeed")
	assert(state.offers.is_empty(), "Accepting clears the table")
	assert(state.active_orders.get(taken.node_id, {}).has(taken.food_id), "The accepted line must be open")
	assert(not state.active_orders.get(passed_over.node_id, {}).has(passed_over.food_id),
		"The offer not taken must NOT open")

	# The one passed over is not gone -- with only twelve lines on the map,
	# discarding one per choice would mean a run never sees half its content.
	var pool := OrderBook.eligible_lines(state, map)
	var found := false
	for line in pool:
		if line.node_id == passed_over.node_id and line.food_id == passed_over.food_id:
			found = true
	assert(found, "The offer not taken must return to the pool")

	assert(not OrderBook.accept_offer(state, passed_over), "An offer no longer on the table cannot be accepted")

## Offers must stay near the gentle end of what is left, so a first choice can
## never be City E's vegetables -- a 16-step haul at 2.5 decay into a 90%
## bonus line, which is a wall, not a decision.
func _test_offers_stay_within_reach() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := _state_with_villageA_grain_filled(map)

	var remaining := OrderBook.eligible_lines(state, map)
	var median: float = remaining[remaining.size() / 2].difficulty
	for offer in OrderBook.draw_offers(state, map):
		assert(offer.difficulty <= median,
			"%s/%s at difficulty %.1f is harder than the median of what is left (%.1f)" % [
				offer.node_id, offer.food_id, offer.difficulty, median,
			])

## Same seed and same choices replay the same offers -- the simulation has no
## other randomness left, and a run that cannot be reproduced cannot be
## debugged.
func _test_offers_are_seeded() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var first: Array[String] = []
	var second: Array[String] = []
	for run in [first, second]:
		var state := _state_with_villageA_grain_filled(map, 12345)
		for offer in OrderBook.draw_offers(state, map):
			run.append(OrderBook.offer_key(offer))
	assert(first == second, "The same seed must deal the same pair: %s vs %s" % [first, second])

	var other := _state_with_villageA_grain_filled(map, 999)
	var differs: Array[String] = []
	for offer in OrderBook.draw_offers(other, map):
		differs.append(OrderBook.offer_key(offer))
	print("Seeded offers: seed 12345 -> %s, seed 999 -> %s." % [first, differs])

## A GameState with Village A's grain line delivered in full, which is what
## earns the first draw.
func _state_with_villageA_grain_filled(map: MapData, seed_value := 4242) -> GameState:
	var state := GameState.new()
	state.run_seed = seed_value
	OrderBook.initialize(state, map)
	# Amber is the bar: the full amount arrived, freshness is irrelevant
	# beyond the settlement's own minimum (which run_day already enforces by
	# rejecting anything under it before it counts as delivered).
	state.last_settlement_status = {
		"villageA": {"grain": {"requested": 20.0, "delivered": 20.0, "rejected": 0.0, "fresh_sum": 20.0 * 40.0}},
	}
	var filled := OrderBook.record_day(state, map.node_placements)
	assert(filled == 1, "The fixture must fill exactly one line, got %d" % filled)
	# Latched: refilling the same line must not earn a second draw.
	assert(OrderBook.record_day(state, map.node_placements) == 0, "A refilled line must not earn another draw")
	return state

func _test_dormant_settlements_are_not_scored() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := GameState.new()
	OrderBook.initialize(state, map)
	var report := SimulationEngine.run_day(state, map.node_placements)
	# Three of the five settlements are not taking orders on day 1. Scoring
	# them would make happiness a measure of the calendar rather than of the
	# network the player built.
	assert(report.settlements_total == 5, "Every settlement stays on the map from day 1")
	assert(report.settlements_taking_orders == 2, "Only settlements with an open order may be scored, got %d" % report.settlements_taking_orders)
	assert(report.settlement_scores.size() == 2, "Dormant settlements must not appear in the per-settlement scores")
	print("Day 1 scores %d of %d settlements." % [report.settlements_taking_orders, report.settlements_total])

## An unchanged network must produce an unchanged day. Demand no longer
## wobbles and freshness never did, so this is the whole simulation's
## determinism in one assertion: if a number on the map moves, the player
## moved it.
func _test_demand_and_freshness_are_stable() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var village_a := _node(map, "villageA")
	var first := {}
	var runs: Array[Dictionary] = []
	for _run in range(3):
		var state := GameState.new()
		OrderBook.initialize(state, map)
		var farm := _node(map, "farm")
		var route_path: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3)]
		for cell in route_path:
			state.grid[cell] = {"kind": "route", "level": "dirt"}
		state.add_connection(farm.grid_position, route_path[0])
		_connect_chain(state, route_path)
		state.add_connection(route_path[-1], village_a.grid_position)
		var report := SimulationEngine.run_day(state, map.node_placements)
		var line: Dictionary = state.last_settlement_status[village_a.node_id].grain
		runs.append({
			"requested": line.requested,
			"delivered": line.delivered,
			"fresh": line.fresh_sum / line.delivered,
			"income": report.income,
		})

	first = runs[0]
	# The order is for the settlement's stated amount, not a wobbled one.
	assert(is_equal_approx(first.requested, village_a.demand.grain),
		"A settlement must ask for exactly its stated demand, got %.1f of %.1f" % [first.requested, village_a.demand.grain])
	for run in runs:
		for key in first:
			assert(is_equal_approx(run[key], first[key]),
				"The same network must give the same '%s' every run: %.4f vs %.4f" % [key, run[key], first[key]])
	print("Stable day: Village A asks %.0f grain, gets %.0f at %.1f%% fresh, every run." % [
		first.requested, first.delivered, first.fresh,
	])

func _connect_chain(state: GameState, cells: Array[Vector2i]) -> void:
	for i in range(1, cells.size()):
		state.add_connection(cells[i - 1], cells[i])

func _make_node(type: GameEnums.NodeType) -> NodeData:
	var n := NodeData.new()
	n.node_type = type
	return n

func _node(map: MapData, node_id: String) -> NodeData:
	for node in map.node_placements:
		if node.node_id == node_id:
			return node
	return null
