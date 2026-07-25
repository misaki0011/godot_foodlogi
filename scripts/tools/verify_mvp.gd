extends SceneTree

## One-shot dev check (not part of the game): exercises SimulationEngine
## against the tile-grid model ported from fresh-routes-mvp.html.
## Run via: godot --headless --script res://scripts/tools/verify_mvp.gd

func _initialize() -> void:
	_test_route_build_cost()
	_test_storage_preservation()
	_test_daily_simulation()
	_test_hub_cap_per_network()
	_test_route_shape()
	_test_established_route_cells()
	_test_hub_buildable_on_any_route_tile()
	_test_delivery_does_not_transit_nodes()
	print("MVP simulation checks passed.")
	quit()

func _test_route_build_cost() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var plains_cost := SimulationEngine.route_build_cost(Vector2i(4, 4), map)
	assert(is_equal_approx(plains_cost, GameBalance.ROUTE_BUILD_COST))
	var river_cost := SimulationEngine.route_build_cost(Vector2i(GameBalance.RIVER_COL, 4), map)
	assert(is_equal_approx(river_cost, GameBalance.ROUTE_BUILD_COST + GameBalance.BRIDGE_COST), "River tiles must add the bridge surcharge")

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

func _test_route_shape() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var nodes_by_pos := {}
	for node in map.node_placements:
		nodes_by_pos[node.grid_position] = node
	var farm := _node(map, "farm")

	# A lone stub built directly east of Farm with no real route neighbor at
	# all (only the source node to its west): nodes no longer influence shape,
	# so it defaults to a plain "lr" straight rather than bending toward the
	# source it happens to sit beside.
	var stub_by_node := farm.grid_position + Vector2i(1, 0)
	var state_a := GameState.new()
	state_a.grid[stub_by_node] = {"kind": "route", "level": "dirt"}
	var shape_a := SimulationEngine.route_shape(stub_by_node, state_a, nodes_by_pos)
	assert(shape_a.family == "straight" and shape_a.facing == "lr", "A stub with no real route neighbor must default to a plain straight, ignoring any adjacent source/settlement")

	# A lone stub next to another route tile (not a node) should default to
	# straight instead.
	var state_b := GameState.new()
	state_b.grid[Vector2i(2, 13)] = {"kind": "route", "level": "dirt"}
	state_b.grid[Vector2i(3, 13)] = {"kind": "route", "level": "dirt"}
	state_b.add_connection(Vector2i(2, 13), Vector2i(3, 13))
	var shape_b := SimulationEngine.route_shape(Vector2i(2, 13), state_b, {})
	assert(shape_b.family == "straight" and shape_b.facing == "lr", "A stub adjacent only to another route tile should default to straight")

	# Adjacent to a node (Farm) with two opposite real connections and a stored
	# override: nodes no longer force or lock a shape, so this behaves exactly
	# like a tile out in the open -- the stored "ne" override wins and the tile
	# stays tappable.
	var mid_by_node := farm.grid_position + Vector2i(1, 0) # east of Farm
	var state_c := GameState.new()
	state_c.grid[mid_by_node + Vector2i(0, -1)] = {"kind": "route", "level": "dirt"} # north
	state_c.grid[mid_by_node] = {"kind": "route", "level": "dirt", "facing": "ne"} # stored override, must win
	state_c.grid[mid_by_node + Vector2i(0, 1)] = {"kind": "route", "level": "dirt"} # south
	state_c.add_connection(mid_by_node, mid_by_node + Vector2i(0, -1))
	state_c.add_connection(mid_by_node, mid_by_node + Vector2i(0, 1))
	var shape_c := SimulationEngine.route_shape(mid_by_node, state_c, nodes_by_pos)
	assert(shape_c.family == "corner" and shape_c.facing == "ne", "A node-adjacent tile's stored override must win -- nodes no longer force a shape")
	assert(SimulationEngine.is_shape_ambiguous(mid_by_node, state_c, nodes_by_pos), "A node-adjacent tile must be tappable -- nodes no longer lock a shape")

	# The same two-opposite-connections shape, but nowhere near a node: no
	# longer forced -- a stored override must now be honored instead of the
	# shape that matches its real connections (the new v0.4 "any shape via
	# tap" rule for tiles that aren't adjacent to a source/settlement).
	var state_d := GameState.new()
	state_d.grid[Vector2i(4, 13)] = {"kind": "route", "level": "dirt"}
	state_d.grid[Vector2i(5, 13)] = {"kind": "route", "level": "dirt", "facing": "ne"}
	state_d.grid[Vector2i(6, 13)] = {"kind": "route", "level": "dirt"}
	state_d.add_connection(Vector2i(4, 13), Vector2i(5, 13))
	state_d.add_connection(Vector2i(5, 13), Vector2i(6, 13))
	var shape_d := SimulationEngine.route_shape(Vector2i(5, 13), state_d, {})
	assert(shape_d.family == "corner" and shape_d.facing == "ne", "Away from any node, a stored override must win over the naturally-matching straight shape")
	assert(SimulationEngine.is_shape_ambiguous(Vector2i(5, 13), state_d, {}), "A tile with no node touching it must always be tappable, even with 2 real connections")
	# With nothing stored yet, the same tile still defaults sensibly to its
	# real connections instead of an arbitrary shape.
	var state_d_default := GameState.new()
	state_d_default.grid[Vector2i(4, 13)] = {"kind": "route", "level": "dirt"}
	state_d_default.grid[Vector2i(5, 13)] = {"kind": "route", "level": "dirt"}
	state_d_default.grid[Vector2i(6, 13)] = {"kind": "route", "level": "dirt"}
	state_d_default.add_connection(Vector2i(4, 13), Vector2i(5, 13))
	state_d_default.add_connection(Vector2i(5, 13), Vector2i(6, 13))
	var shape_d_default := SimulationEngine.route_shape(Vector2i(5, 13), state_d_default, {})
	assert(shape_d_default.family == "straight" and shape_d_default.facing == "lr", "With nothing tapped yet, a non-node tile still defaults to the shape matching its real connections")

	# Cycling all the way around the full 6-shape cycle returns to the start,
	# for both a node-adjacent ambiguous stub and an ordinary mid-network one.
	var state_e := GameState.new()
	var lone := Vector2i(11, 13)
	state_e.grid[lone] = {"kind": "route", "level": "dirt"}
	var start_facing: String = SimulationEngine.route_shape(lone, state_e, {}).facing
	var facing := start_facing
	for _i in range(6):
		facing = SimulationEngine.cycle_shape_facing(lone, state_e, {})
		state_e.grid[lone].facing = facing
	assert(facing == start_facing, "Cycling through all 6 shapes must return to the starting facing")

	# Regression: a route tile with a node on one side (west) and a real
	# route tile continuing on an *adjacent* side (south) must NOT be forced
	# by the node -- shape ignores nodes entirely, so the tile stays freely
	# tappable all the way to "ud".
	var stub_by_node_and_route := farm.grid_position + Vector2i(1, 0) # node to the west
	var state_f := GameState.new()
	state_f.grid[stub_by_node_and_route] = {"kind": "route", "level": "dirt"}
	state_f.grid[stub_by_node_and_route + Vector2i(0, 1)] = {"kind": "route", "level": "dirt"} # route to the south
	state_f.add_connection(stub_by_node_and_route, stub_by_node_and_route + Vector2i(0, 1))
	assert(SimulationEngine.is_shape_ambiguous(stub_by_node_and_route, state_f, nodes_by_pos), "A node beside a tile must never force its shape, even with a real route neighbor on an adjacent side")
	var reachable_ud := false
	for _i in range(6):
		facing = SimulationEngine.cycle_shape_facing(stub_by_node_and_route, state_f, nodes_by_pos)
		state_f.grid[stub_by_node_and_route].facing = facing
		if facing == "ud":
			reachable_ud = true
			break
	assert(reachable_ud, "A node-adjacent ambiguous tile must be able to cycle all the way to a straight up-down facing")

	# A tile's default shape reflects only its real route neighbors, never an
	# adjacent node: a single real route neighbor always reads as a straight
	# running along that side, regardless of which side a source/settlement
	# happens to sit on.
	var village_a := _node(map, "villageA")
	var tile_by_source := farm.grid_position + Vector2i(1, 0) # source west, route east
	var state_g := GameState.new()
	state_g.grid[tile_by_source] = {"kind": "route", "level": "dirt"}
	state_g.grid[tile_by_source + Vector2i(1, 0)] = {"kind": "route", "level": "dirt"}
	state_g.add_connection(tile_by_source, tile_by_source + Vector2i(1, 0))
	var shape_g := SimulationEngine.route_shape(tile_by_source, state_g, nodes_by_pos)
	assert(shape_g.family == "straight" and shape_g.facing == "lr", "A route neighbor to the east must default to a left-right straight tile, ignoring the source to the west")

	var tile_by_settlement := village_a.grid_position + Vector2i(0, 1) # settlement north, route west
	var state_h := GameState.new()
	state_h.grid[tile_by_settlement] = {"kind": "route", "level": "dirt"}
	state_h.grid[tile_by_settlement + Vector2i(-1, 0)] = {"kind": "route", "level": "dirt"}
	state_h.add_connection(tile_by_settlement, tile_by_settlement + Vector2i(-1, 0))
	var shape_h := SimulationEngine.route_shape(tile_by_settlement, state_h, nodes_by_pos)
	assert(shape_h.family == "straight" and shape_h.facing == "lr", "A single route neighbor to the west must default to a left-right straight, ignoring the settlement to the north")

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

## Connects each consecutive pair in `cells` -- mirrors what a real drag
## gesture would link, since state.grid[cell] = ... no longer implies
## connectivity on its own (v0.5).
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
