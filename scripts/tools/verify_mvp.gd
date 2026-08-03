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
	_test_multi_tile_nodes()
	_test_sources_are_two_tiles()
	_test_demand_caps()
	_test_source_upgrade_ramp()
	_test_delivery_reaches_any_footprint_cell()
	_test_days_alone_open_nothing()
	_test_filling_opens_the_next_order()
	_test_growth_alternates()
	_test_no_tap_is_needed()
	_test_openings_stay_within_reach()
	_test_openings_are_seeded()
	_test_dormant_settlements_are_not_scored()
	_test_demand_and_freshness_are_stable()
	_test_line_earnings_reconcile()
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
	# Sized from the cap rather than written out, so raising the cap re-runs
	# this check at the new value instead of indexing off the end of a spine
	# that was long enough for the old one. Four tiles of slack, so there are
	# always some non-hub tiles left over to prove the refusal on.
	var spine: Array[Vector2i] = []
	for x in range(2, 2 + GameBalance.HUB_CAP_PER_NETWORK + 4):
		spine.append(Vector2i(x, 10))
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
	nodes_by_pos[Vector2i(0, 0)] = _make_node(GameEnums.NodeType.SOURCE, Vector2i(0, 0))      # S
	nodes_by_pos[Vector2i(0, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(0, 4))  # A
	nodes_by_pos[Vector2i(5, 0)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(5, 0))  # B
	nodes_by_pos[Vector2i(5, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(5, 4))  # C
	nodes_by_pos[Vector2i(8, 0)] = _make_node(GameEnums.NodeType.SOURCE, Vector2i(8, 0))      # D

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
	nodes[Vector2i(0, 0)] = _make_node(GameEnums.NodeType.SOURCE, Vector2i(0, 0))      # S
	nodes[Vector2i(0, 2)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(0, 2))  # M, in the middle
	nodes[Vector2i(0, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(0, 4))  # D, the target
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
	nodes[Vector2i(2, 0)] = _make_node(GameEnums.NodeType.SOURCE, Vector2i(2, 0))      # S, north
	nodes[Vector2i(2, 4)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(2, 4))  # A, south
	nodes[Vector2i(4, 2)] = _make_node(GameEnums.NodeType.SOURCE, Vector2i(4, 2))      # E, east
	nodes[Vector2i(0, 2)] = _make_node(GameEnums.NodeType.SETTLEMENT, Vector2i(0, 2))  # W, west

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
	# Sized from the cap: bridges go on every other tile (no two may sit side by
	# side), so the run needs two tiles per bridge plus a couple to spare for
	# the tiles that must refuse one at the end.
	var state := GameState.new()
	var spine: Array[Vector2i] = []
	for x in range(1, 1 + GameBalance.BRIDGE_CAP_PER_NETWORK * 2 + 2):
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
		OrderBook.record_day(state, map, map.node_placements)
	var open_lines := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			open_lines += OrderBook.active_demand(state, node).size()
	assert(open_lines == map.opening_lines.size(),
		"After 50 idle days the map must still hold only its opening orders, got %d" % open_lines)
	print("50 idle days opened nothing.")

func _test_filling_opens_the_next_order() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var before := GameState.new()
	before.run_seed = 4242
	OrderBook.initialize(before, map)
	var opening := _open_line_count(before, map)

	var state := _state_with_villageA_grain_filled(map)
	assert(_open_line_count(state, map) == opening + 1,
		"Filling a line must open exactly one more, got %d from %d" % [_open_line_count(state, map), opening])

## The two kinds of growth alternate, so the region both widens and thickens
## instead of drifting into a run of one kind.
func _test_growth_alternates() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := GameState.new()
	state.run_seed = 77
	OrderBook.initialize(state, map)

	var kinds: Array[String] = []
	# Fill every open line, over and over, until the map runs out.
	for _round in range(20):
		var served_before := {}
		for node_id in state.active_orders:
			if not state.active_orders[node_id].is_empty():
				served_before[node_id] = true
		var status := {}
		for node in map.node_placements:
			if node.node_type != GameEnums.NodeType.SETTLEMENT:
				continue
			var lines := {}
			for food_id in OrderBook.active_demand(state, node):
				lines[food_id] = {"requested": 10.0, "delivered": 10.0, "rejected": 0.0, "fresh_sum": 500.0}
			if not lines.is_empty():
				status[node.node_id] = lines
		state.last_settlement_status = status
		for opened in OrderBook.record_day(state, map, map.node_placements):
			kinds.append("deepen" if served_before.has(opened.node_id) else "expand")

	assert(_open_line_count(state, map) == map.demand_lines().size(),
		"Filling everything repeatedly must eventually open every line, got %d of %d" % [
			_open_line_count(state, map), map.demand_lines().size(),
		])
	# Balance is not the invariant -- there are only five settlements and
	# fifteen lines, so once every place is served every remaining opening
	# MUST be a deepen. What matters is that the region widens EARLY rather
	# than pouring everything into one town first, which is what alternation
	# buys. Every settlement that is not in the opening should be reached
	# within the first few openings.
	var expands_early := 0
	for i in mini(4, kinds.size()):
		if kinds[i] == "expand":
			expands_early += 1
	assert(expands_early >= 2,
		"The region must widen early: only %d of the first 4 openings were expands (%s)" % [expands_early, kinds])
	var serving := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT and OrderBook.has_active_orders(state, node):
			serving += 1
	assert(serving == 5, "Every settlement should end up taking orders, got %d" % serving)
	print("Growth over a full run: %d deepen, %d expand, all %d settlements served." % [
		kinds.count("deepen"), kinds.count("expand"), serving,
	])

## Nothing the player has to press. An order opens itself the moment a
## delivery earns it -- there is no pending state to sit unnoticed.
func _test_no_tap_is_needed() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var state := _state_with_villageA_grain_filled(map)
	# The newly opened line is live immediately: it is in active_demand, so
	# the very next simulated day asks for it, with nothing to press first.
	var live := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			live += OrderBook.active_demand(state, node).size()
	assert(live == map.opening_lines.size() + 1, "The opened line must be live at once, got %d" % live)

## Multi-tile footprints (DEV-02). The invariant that keeps every cell-based
## rule in the game working untouched is that a node resolves from ANY of its
## cells, so this checks the fan-out and the things that depend on it.
func _test_multi_tile_nodes() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var town := _node(map, "townD")
	var city := _node(map, "cityE")
	assert(town.size == Vector2i(2, 1), "Town D should be 2x1, got %s" % town.size)
	assert(city.size == Vector2i(2, 2), "City E should be 2x2, got %s" % city.size)
	assert(town.cells().size() == 2 and city.cells().size() == 4)
	assert(city.occupies(Vector2i(15, 10)), "A City must own its far corner")
	assert(not city.occupies(Vector2i(16, 10)), "A City must not own the cell past it")

	# validate() catches overlapping and off-map footprints -- either would
	# make a cell resolve to whichever node was placed last, hiding the other
	# from every build guard and every path.
	assert(map.validate().is_empty(), "The shipped map's footprints must be legal")
	var clash: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	_node(clash, "cityE").grid_position = _node(clash, "townD").grid_position
	assert(not clash.validate().is_empty(), "Overlapping footprints must be reported")
	var offmap: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	_node(offmap, "cityE").grid_position = Vector2i(map.grid_size.x - 1, 0)
	assert(not offmap.validate().is_empty(), "A footprint running off the grid must be reported")

	# Distance is measured footprint to footprint, so a big place is as close
	# as its nearest cell.
	var harbor := _node(map, "harbor")
	assert(harbor.grid_distance_to(city) == 3,
		"Harbor (18,9) to City E's nearest cell (15,9) is 3 tiles, got %d" % harbor.grid_distance_to(city))

## Every source stands on 2x1 from the start (DEV-03), and is anchored so the
## wider building costs the player no distance -- the cell nearest its
## customers is the one it always had.
func _test_sources_are_two_tiles() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	assert(map.validate().is_empty(), "The shipped map must be legal")
	for node in map.node_placements:
		if node.node_type != GameEnums.NodeType.SOURCE:
			continue
		assert(node.size == Vector2i(2, 1), "%s should be 2x1, got %s" % [node.node_id, node.size])
		assert(node.cells().size() == 2)
		assert(node.can_upgrade(), "Every source starts un-upgraded")

	# The distances the difficulty ranking is built on are unchanged by the
	# wider footprints: each source's nearest cell to its customers is where
	# it always stood. The Garden is the one exception -- it had to extend
	# east to keep its bubble on screen, which brings vegetables a tile
	# closer to everyone (8 -> 7 here).
	var expected := {
		"farm|villageA": 4, "garden|villageB": 7, "bakery|villageA": 11,
		"dairy|townD": 6, "harbor|cityE": 3,
	}
	for key in expected:
		var parts: PackedStringArray = key.split("|")
		var got: int = _node(map, parts[0]).grid_distance_to(_node(map, parts[1]))
		assert(got == expected[key], "%s should stay %d tiles apart, got %d" % [key, expected[key], got])
	print("Sources: all 2x1, customer distances unchanged.")

## Upgrading adds one base unit of output, up to SOURCE_UPGRADE_MAX times. The
## footprint does not change -- a source is already 2x1 -- so the only things
## it costs are money and the cap.
func _test_source_upgrade_ramp() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	var garden := _node(map, "garden")
	var before: float = garden.produces.vegetables
	var footprint := garden.cells()

	garden.upgrade_level = 1
	assert(garden.cells() == footprint, "Upgrading must not move or resize a source")
	assert(garden.can_upgrade(), "One upgrade must not use up all %d" % GameBalance.SOURCE_UPGRADE_MAX)
	assert(is_equal_approx(garden.supply_of("vegetables"), before * 2.0),
		"The first upgrade must double output, got %.0f from %.0f" % [garden.supply_of("vegetables"), before])
	assert(is_equal_approx(garden.produces.vegetables, before),
		"`produces` is the authored base and must never be scaled in place")

	# Linear, not compounding: five upgrades are six base units, not 2^5 of
	# them. The ceiling matters as much as the step -- a compounding ramp puts
	# a maxed Garden at 2880/day against a region that demands 110.
	garden.upgrade_level = GameBalance.SOURCE_UPGRADE_MAX
	assert(is_equal_approx(garden.supply_of("vegetables"), before * (GameBalance.SOURCE_UPGRADE_MAX + 1)),
		"A maxed source should be %dx its base, got %.0f from %.0f" % [
			GameBalance.SOURCE_UPGRADE_MAX + 1, garden.supply_of("vegetables"), before,
		])
	assert(not garden.can_upgrade(), "A source at the cap must offer no further upgrade")

	# The Garden upgrade is the answer to region 1's one impossible food:
	# vegetables are over-subscribed at 110 against a base 90, and ONE upgrade
	# is what closes it -- the rest of the ramp is headroom, not the fix.
	var demanded := 0.0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			demanded += node.demand.get("vegetables", 0.0)
	assert(demanded > before, "Vegetables should be over-subscribed before the upgrade (%.0f vs %.0f)" % [demanded, before])
	garden.upgrade_level = 1
	assert(garden.supply_of("vegetables") >= demanded,
		"One Garden upgrade should cover the region's %.0f vegetables, supplies %.0f" % [demanded, garden.supply_of("vegetables")])
	print("Garden upgrade: %.0f base -> %.0f at one expansion, %.0f at the %d cap, against %.0f demanded." % [
		before, before * 2.0, before * (GameBalance.SOURCE_UPGRADE_MAX + 1), GameBalance.SOURCE_UPGRADE_MAX, demanded,
	])

## Demand caps by settlement type (DEV-04). Nothing enforces them at runtime,
## so validate() is the only thing keeping the map honest.
func _test_demand_caps() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	assert(map.validate().is_empty(), "The shipped map must be within its demand caps")

	var expected := {
		"villageA": [GameEnums.SettlementType.VILLAGE, 2],
		"villageB": [GameEnums.SettlementType.VILLAGE, 2],
		"villageC": [GameEnums.SettlementType.VILLAGE, 2],
		"townD": [GameEnums.SettlementType.TOWN, 4],
		"cityE": [GameEnums.SettlementType.CITY, 5],
	}
	for node_id in expected:
		var settlement := _node(map, node_id)
		assert(settlement.settlement_type == expected[node_id][0], "%s has the wrong settlement type" % node_id)
		assert(settlement.demand_cap() == expected[node_id][1],
			"%s should cap at %d, got %d" % [node_id, expected[node_id][1], settlement.demand_cap()])
		assert(settlement.demand.size() <= settlement.demand_cap(),
			"%s holds %d lines over a cap of %d" % [node_id, settlement.demand.size(), settlement.demand_cap()])

	# City E is the late objective, which with five foods in the game means
	# it wants all of them.
	assert(_node(map, "cityE").demand.size() == 5, "City E should demand every food")
	assert(_node(map, "townD").demand.size() == 4, "Town D should be at its Town cap of 4")

	# And validate() must actually bite.
	var over: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	_node(over, "villageA").demand["milk"] = 10.0
	assert(not over.validate().is_empty(), "A Village authored past its cap must be reported")
	print("Demand caps: %d lines total across 5 settlements." % map.demand_lines().size())

## A delivery may leave from any cell of its source and arrive at any cell of
## its destination -- otherwise a 2x2 City's reachability would depend on
## which corner the map author wrote down.
func _test_delivery_reaches_any_footprint_cell() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var city := _node(map, "cityE")
	var harbor := _node(map, "harbor")
	var nodes_by_pos := {}
	for node in map.node_placements:
		for cell in node.cells():
			nodes_by_pos[cell] = node

	var state := GameState.new()
	# Road from Harbor (18,9) to City E's (15,9) cell.
	var link: Array[Vector2i] = [Vector2i(17, 9), Vector2i(16, 9)]
	for cell in link:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(harbor.grid_position, link[0])
	state.add_connection(link[0], link[1])
	state.add_connection(link[1], Vector2i(15, 9))

	var seafood: FoodData = GameBalance.food_types().seafood
	var path := SimulationEngine.find_path(state, nodes_by_pos, harbor.grid_position, city.grid_position, seafood)
	assert(not path.is_empty(), "A road to any City cell must deliver to the City")
	assert(path[0] == harbor.grid_position, "The path must start at the source")
	assert(city.occupies(path[-1]), "The path must end on a City cell, got %s" % path[-1])
	print("Footprint delivery: Harbor -> City E, %d tiles, ends on %s." % [path.size(), path[-1]])

## An opening must stay near the gentle end of what is left, so the line after
## the tutorial can never be City E's vegetables -- a 16-step haul at 2.5
## decay into a 90% bonus line, which is a wall.
func _test_openings_stay_within_reach() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var before := GameState.new()
	before.run_seed = 4242
	OrderBook.initialize(before, map)
	var remaining := OrderBook.eligible_lines(before, map)
	var median: float = remaining[remaining.size() / 2].difficulty

	var state := _state_with_villageA_grain_filled(map)
	for line in map.demand_lines():
		if _is_opening_line(map, line):
			continue
		if not OrderBook.active_demand(state, _node(map, line.node_id)).has(line.food_id):
			continue
		assert(line.difficulty <= median,
			"%s/%s at difficulty %.1f is harder than the median of what was left (%.1f)" % [
				line.node_id, line.food_id, line.difficulty, median,
			])

## Same seed, same play, same openings -- the simulation has no other
## randomness left, and a run that cannot be reproduced cannot be debugged.
func _test_openings_are_seeded() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var first := _opened_line_ids(map, 12345)
	var second := _opened_line_ids(map, 12345)
	assert(first == second, "The same seed must open the same line: %s vs %s" % [first, second])
	print("Seeded opening: seed 12345 -> %s, seed 999 -> %s." % [first, _opened_line_ids(map, 999)])

## The lines open beyond the map's authored opening, for a run pinned to
## `seed_value`.
func _opened_line_ids(map: MapData, seed_value: int) -> Array[String]:
	var state := _state_with_villageA_grain_filled(map, seed_value)
	var ids: Array[String] = []
	for line in map.demand_lines():
		if _is_opening_line(map, line):
			continue
		if OrderBook.active_demand(state, _node(map, line.node_id)).has(line.food_id):
			ids.append(OrderBook.line_id(line))
	return ids

func _is_opening_line(map: MapData, line: Dictionary) -> bool:
	for opening in map.opening_lines:
		if opening.node_id == line.node_id and opening.food_id == line.food_id:
			return true
	return false

func _open_line_count(state: GameState, map: MapData) -> int:
	var total := 0
	for node in map.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			total += OrderBook.active_demand(state, node).size()
	return total

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
	var opened := OrderBook.record_day(state, map, map.node_placements)
	assert(opened.size() == 1, "The fixture must open exactly one new line, got %d" % opened.size())
	# Latched: refilling the same line must not open another.
	assert(OrderBook.record_day(state, map, map.node_placements).is_empty(),
		"A refilled line must not open another order")
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

## Every line's recorded `earned` must add up to the day's income, and a
## line's `withheld` must be non-zero exactly when it earned nothing.
##
## A row now PRINTS its earnings (UI-04), and the whole point of that number
## is that it explains the row's colour by naming the money the treasury
## actually took. If the per-line figures ever drift from `report.income` the
## row would confidently state a payment that never happened, which no
## screenshot could catch.
func _test_line_earnings_reconcile() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var village_a := _node(map, "villageA")
	var farm := _node(map, "farm")
	var state := GameState.new()
	OrderBook.initialize(state, map)
	var route_path: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3)]
	for cell in route_path:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.add_connection(farm.grid_position, route_path[0])
	_connect_chain(state, route_path)
	state.add_connection(route_path[-1], village_a.grid_position)
	var report := SimulationEngine.run_day(state, map.node_placements)

	var earned_total := 0.0
	var withheld_total := 0.0
	for settlement_id in state.last_settlement_status:
		for food_id in state.last_settlement_status[settlement_id]:
			var line: Dictionary = state.last_settlement_status[settlement_id][food_id]
			earned_total += line.earned
			withheld_total += line.withheld
			# A line either paid or it did not; it can never do both.
			assert(line.earned == 0.0 or line.withheld == 0.0,
				"%s/%s recorded both earnings (%.2f) and withheld income (%.2f)" % [settlement_id, food_id, line.earned, line.withheld])
			var short: bool = line.delivered < line.requested - 0.01
			assert(short == (line.earned == 0.0),
				"%s/%s: a short line must earn nothing and a full one must earn something" % [settlement_id, food_id])

	assert(is_equal_approx(earned_total, report.income),
		"Per-line earnings must sum to the day's income: %.2f vs %.2f" % [earned_total, report.income])
	assert(is_equal_approx(withheld_total, report.withheld_income),
		"Per-line withheld must sum to the report's: %.2f vs %.2f" % [withheld_total, report.withheld_income])
	print("Line earnings (UI-04): §%.0f earned and §%.0f withheld reconcile with the day report." % [earned_total, withheld_total])

func _connect_chain(state: GameState, cells: Array[Vector2i]) -> void:
	for i in range(1, cells.size()):
		state.add_connection(cells[i - 1], cells[i])

## A stand-in node for the synthetic layouts above. `pos` must match the cell
## it is filed under: a NodeData carries its own grid_position and footprint
## (DEV-02), and find_path derives a delivery's origin and destination cells
## from those rather than from the dictionary key -- so a fixture whose
## position disagrees with its key silently reroutes the search.
func _make_node(type: GameEnums.NodeType, pos: Vector2i) -> NodeData:
	var n := NodeData.new()
	n.node_type = type
	n.grid_position = pos
	return n

func _node(map: MapData, node_id: String) -> NodeData:
	for node in map.node_placements:
		if node.node_id == node_id:
			return node
	return null
