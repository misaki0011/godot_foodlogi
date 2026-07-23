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
	_test_node_adjacency_counts_toward_hub_degree()
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
	var state := GameState.new()
	var nodes_by_pos := {} # Empty margin area far from any real node/river.
	var spine: Array[Vector2i] = [Vector2i(4, 12), Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12), Vector2i(8, 12), Vector2i(9, 12)]
	for cell in spine:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	var forks: Array[Vector2i] = [Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12)]
	for parent in forks:
		var branch := parent + Vector2i(0, 1)
		state.grid[branch] = {"kind": "route", "level": "dirt"}

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
	assert(capped_count == forks.size() - GameBalance.HUB_CAP_PER_NETWORK, "Any further 3-way junction must be rejected as hub_capped, not silently formed")
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

func _test_node_adjacency_counts_toward_hub_degree() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var nodes_by_pos := {}
	for node in map.node_placements:
		nodes_by_pos[node.grid_position] = node
	var farm := _node(map, "farm")
	var village_a := _node(map, "villageA")

	# A route tile with a road branch north and south that also sits beside
	# Farm (a source) is a tile where the source's delivery fans out to two
	# roads: the adjacent node DOES count toward hub-formation degree (revised
	# in v0.4), so this reads as a 3-way junction and auto-forms a Small Hub.
	var mid_source := farm.grid_position + Vector2i(1, 0) # east of Farm
	var state_source := GameState.new()
	state_source.grid[mid_source + Vector2i(0, -1)] = {"kind": "route", "level": "dirt"} # north
	state_source.grid[mid_source] = {"kind": "route", "level": "dirt"}
	state_source.grid[mid_source + Vector2i(0, 1)] = {"kind": "route", "level": "dirt"} # south
	assert(SimulationEngine.tile_degree(mid_source, state_source, nodes_by_pos) == 3, "A source beside a tile MUST count toward its hub-formation degree")
	SimulationEngine.check_auto_hubs(state_source, nodes_by_pos)
	assert(state_source.grid[mid_source].kind == "hub", "A tile branching a source's delivery to two roads must auto-form a hub")

	# Same scenario, but the adjacent node is a settlement (Village A) instead
	# of a source -- behaves identically, since the player wants a hub wherever
	# a delivery fans out, regardless of which endpoint kind sits beside it.
	var mid_settlement := village_a.grid_position + Vector2i(1, 0) # east of Village A
	var state_settlement := GameState.new()
	state_settlement.grid[mid_settlement + Vector2i(0, -1)] = {"kind": "route", "level": "dirt"}
	state_settlement.grid[mid_settlement] = {"kind": "route", "level": "dirt"}
	state_settlement.grid[mid_settlement + Vector2i(0, 1)] = {"kind": "route", "level": "dirt"}
	assert(SimulationEngine.tile_degree(mid_settlement, state_settlement, nodes_by_pos) == 3, "A settlement beside a tile MUST count toward its hub-formation degree")
	SimulationEngine.check_auto_hubs(state_settlement, nodes_by_pos)
	assert(state_settlement.grid[mid_settlement].kind == "hub", "A tile branching toward a settlement plus two roads must auto-form a hub")

func _node(map: MapData, node_id: String) -> NodeData:
	for node in map.node_placements:
		if node.node_id == node_id:
			return node
	return null
