extends SceneTree

## One-shot dev check (not part of the game): exercises SimulationEngine
## against the tile-grid model ported from fresh-routes-mvp.html.
## Run via: godot --headless --script res://scripts/tools/verify_mvp.gd

func _initialize() -> void:
	_test_route_build_cost()
	_test_storage_preservation()
	_test_daily_simulation()
	_test_hub_auto_formation_and_cap()
	_test_route_shape()
	_test_established_route_cells()
	_test_hub_only_on_completed_route_fork()
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
	for cell in [Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3)]:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	var report := SimulationEngine.run_day(state, map.node_placements)
	var grain_status: Dictionary = state.last_settlement_status[village_a.node_id].grain
	print("Village A grain: %.1f / %.1f delivered" % [grain_status.delivered, grain_status.requested])
	assert(grain_status.delivered > 0.0, "Grain should reach Village A over a short, fresh dirt route")
	assert(is_equal_approx(grain_status.delivered, grain_status.requested), "Ample supply/capacity should fully cover Village A's grain demand")
	assert(report.income > 0.0)
	assert(report.route_upkeep > 0.0)
	assert(state.day == 1, "run_day must not itself advance the day counter (Main._close_report does)")

func _test_hub_auto_formation_and_cap() -> void:
	# A completed route: a source feeds a horizontal spine that runs to a
	# settlement (E), with three branches dropping to three more settlements.
	# Each branch parent is a genuine 3-road fork ON the finished route, so a
	# hub forms there -- capped at HUB_CAP_PER_NETWORK per road network.
	var state := GameState.new()
	var nodes_by_pos := {}
	nodes_by_pos[Vector2i(1, 10)] = _make_node(GameEnums.NodeType.SOURCE)      # S, west of spine
	nodes_by_pos[Vector2i(8, 10)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # E, east of spine
	var spine: Array[Vector2i] = [Vector2i(2, 10), Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10)]
	for cell in spine:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	var forks: Array[Vector2i] = [Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10)]
	for parent in forks:
		var branch := parent + Vector2i(0, 1)
		state.grid[branch] = {"kind": "route", "level": "dirt"}
		nodes_by_pos[branch + Vector2i(0, 1)] = _make_node(GameEnums.NodeType.SETTLEMENT)

	var starting_balance := state.balance
	SimulationEngine.check_auto_hubs(state, nodes_by_pos)

	var hub_count := 0
	var capped_count := 0
	for parent in forks:
		var cell = state.grid[parent]
		if cell.kind == "hub":
			hub_count += 1
		elif cell.get("hub_capped", false):
			capped_count += 1
	print("Hubs formed: %d, capped junctions: %d (cap is %d)" % [hub_count, capped_count, GameBalance.HUB_CAP_PER_NETWORK])
	assert(hub_count == GameBalance.HUB_CAP_PER_NETWORK, "Exactly HUB_CAP_PER_NETWORK hubs should auto-form on one connected network")
	assert(capped_count == forks.size() - GameBalance.HUB_CAP_PER_NETWORK, "Any further completed-route fork must be rejected as hub_capped, not silently formed")
	assert(is_equal_approx(state.balance, starting_balance - GameBalance.HUB_CAP_PER_NETWORK * GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build))

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
	var shape_d := SimulationEngine.route_shape(Vector2i(5, 13), state_d, {})
	assert(shape_d.family == "corner" and shape_d.facing == "ne", "Away from any node, a stored override must win over the naturally-matching straight shape")
	assert(SimulationEngine.is_shape_ambiguous(Vector2i(5, 13), state_d, {}), "A tile with no node touching it must always be tappable, even with 2 real connections")
	# With nothing stored yet, the same tile still defaults sensibly to its
	# real connections instead of an arbitrary shape.
	var state_d_default := GameState.new()
	state_d_default.grid[Vector2i(4, 13)] = {"kind": "route", "level": "dirt"}
	state_d_default.grid[Vector2i(5, 13)] = {"kind": "route", "level": "dirt"}
	state_d_default.grid[Vector2i(6, 13)] = {"kind": "route", "level": "dirt"}
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
	var shape_g := SimulationEngine.route_shape(tile_by_source, state_g, nodes_by_pos)
	assert(shape_g.family == "straight" and shape_g.facing == "lr", "A route neighbor to the east must default to a left-right straight tile, ignoring the source to the west")

	var tile_by_settlement := village_a.grid_position + Vector2i(0, 1) # settlement north, route west
	var state_h := GameState.new()
	state_h.grid[tile_by_settlement] = {"kind": "route", "level": "dirt"}
	state_h.grid[tile_by_settlement + Vector2i(-1, 0)] = {"kind": "route", "level": "dirt"}
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
	for cell in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]: # S -> A path
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	state.grid[Vector2i(1, 2)] = {"kind": "route", "level": "dirt"} # dead-end stub
	for cell in [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)]: # B <-> C, no source
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	for cell in [Vector2i(8, 1), Vector2i(8, 2)]: # from D, reaches no settlement
		state.grid[cell] = {"kind": "route", "level": "dirt"}

	var est := SimulationEngine.established_route_cells(state, nodes_by_pos)
	assert(est.has(Vector2i(0, 1)) and est.has(Vector2i(0, 2)) and est.has(Vector2i(0, 3)), "The whole source->settlement path must be established")
	assert(not est.has(Vector2i(1, 2)), "A dead-end stub off the path must be pruned out")
	assert(not est.has(Vector2i(5, 1)) and not est.has(Vector2i(5, 2)) and not est.has(Vector2i(5, 3)), "A settlement-to-settlement road with no source must not be established")
	assert(not est.has(Vector2i(8, 1)) and not est.has(Vector2i(8, 2)), "A source-fed road that reaches no settlement must not be established")
	assert(est.size() == 3, "Only the three source->settlement tiles should be established")

func _test_hub_only_on_completed_route_fork() -> void:
	# Case 1: a plain straight completed route (source -> settlement) with
	# nothing branching off it forms no hub -- no tile reaches 3 branches.
	var n1 := {}
	n1[Vector2i(0, 0)] = _make_node(GameEnums.NodeType.SOURCE)      # west of (1,0)
	n1[Vector2i(4, 0)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # east of (3,0)
	var s1 := GameState.new()
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		s1.grid[cell] = {"kind": "route", "level": "dirt"}
	SimulationEngine.check_auto_hubs(s1, n1)
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		assert(s1.grid[cell].kind == "route", "A straight completed route with no branch must not form a hub")

	# Case 2: a source feeding a tile that splits toward two settlements IS a
	# hub -- the source's delivery fans out (the adjacent source counts as a
	# branch alongside the two roads). The start/end tiles are not hubs.
	var n2 := {}
	n2[Vector2i(5, 1)] = _make_node(GameEnums.NodeType.SOURCE)      # below the fork
	n2[Vector2i(3, 0)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # west end
	n2[Vector2i(7, 0)] = _make_node(GameEnums.NodeType.SETTLEMENT)  # east end
	var s2 := GameState.new()
	for cell in [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]:
		s2.grid[cell] = {"kind": "route", "level": "dirt"}
	SimulationEngine.check_auto_hubs(s2, n2)
	assert(s2.grid[Vector2i(5, 0)].kind == "hub", "A source feeding a tile that splits toward two roads must form a hub")
	assert(s2.grid[Vector2i(4, 0)].kind == "route" and s2.grid[Vector2i(6, 0)].kind == "route", "A route's start/end tiles (beside a node, one road) are not hubs")

	# Case 3: a 3-road fork that reaches no settlement (an unfinished route)
	# forms no hub -- hubs only appear on completed source->settlement routes.
	var only_source := {Vector2i(10, 10): _make_node(GameEnums.NodeType.SOURCE)}
	var incomplete := GameState.new()
	incomplete.grid[Vector2i(10, 11)] = {"kind": "route", "level": "dirt"} # touches the source
	incomplete.grid[Vector2i(11, 11)] = {"kind": "route", "level": "dirt"}
	incomplete.grid[Vector2i(9, 11)] = {"kind": "route", "level": "dirt"}
	incomplete.grid[Vector2i(10, 12)] = {"kind": "route", "level": "dirt"}
	SimulationEngine.check_auto_hubs(incomplete, only_source)
	assert(incomplete.grid[Vector2i(10, 11)].kind == "route", "A 3-road fork that reaches no settlement must not form a hub")

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
	assert(SimulationEngine.find_path(state, nodes, Vector2i(0, 0), Vector2i(0, 4), grain).is_empty(), "A delivery must not route through an intermediate settlement/source node")
	# The source still reaches the settlement it connects to over clear road.
	assert(not SimulationEngine.find_path(state, nodes, Vector2i(0, 0), Vector2i(0, 2), grain).is_empty(), "A source must still reach a settlement over a clear road path")

func _make_node(type: GameEnums.NodeType) -> NodeData:
	var n := NodeData.new()
	n.node_type = type
	return n

func _node(map: MapData, node_id: String) -> NodeData:
	for node in map.node_placements:
		if node.node_id == node_id:
			return node
	return null
