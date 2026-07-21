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

	# A lone stub built directly east of Farm: its only real connection is
	# the source node, so it should default to a corner, not straight.
	var farm := _node(map, "farm")
	var stub_by_node := farm.grid_position + Vector2i(1, 0)
	var state_a := GameState.new()
	state_a.grid[stub_by_node] = {"kind": "route", "level": "dirt"}
	var shape_a := SimulationEngine.route_shape(stub_by_node, state_a, nodes_by_pos)
	assert(shape_a.family == "corner" and shape_a.facing == "ne", "A stub adjacent only to a source/settlement should default to a corner")

	# A lone stub next to another route tile (not a node) should default to
	# straight instead.
	var state_b := GameState.new()
	state_b.grid[Vector2i(2, 13)] = {"kind": "route", "level": "dirt"}
	state_b.grid[Vector2i(3, 13)] = {"kind": "route", "level": "dirt"}
	var shape_b := SimulationEngine.route_shape(Vector2i(2, 13), state_b, {})
	assert(shape_b.family == "straight" and shape_b.facing == "lr", "A stub adjacent only to another route tile should default to straight")

	# Two opposite neighbors force straight on that axis, even overriding a
	# previously stored facing.
	var state_c := GameState.new()
	state_c.grid[Vector2i(4, 13)] = {"kind": "route", "level": "dirt"}
	state_c.grid[Vector2i(5, 13)] = {"kind": "route", "level": "dirt", "facing": "ud"}
	state_c.grid[Vector2i(6, 13)] = {"kind": "route", "level": "dirt"}
	var shape_c := SimulationEngine.route_shape(Vector2i(5, 13), state_c, {})
	assert(shape_c.family == "straight" and shape_c.facing == "lr", "Two opposite (E/W) connections must force a left-right straight tile")

	# Two adjacent neighbors force the matching corner, ignoring any stored facing.
	var state_d := GameState.new()
	state_d.grid[Vector2i(8, 13)] = {"kind": "route", "level": "dirt", "facing": "lr"}
	state_d.grid[Vector2i(9, 13)] = {"kind": "route", "level": "dirt"} # east of (8,13)
	state_d.grid[Vector2i(8, 12)] = {"kind": "route", "level": "dirt"} # north of (8,13)
	var shape_d := SimulationEngine.route_shape(Vector2i(8, 13), state_d, {})
	assert(shape_d.family == "corner" and shape_d.facing == "ne", "North+East connections must force the matching NE corner")

	# Cycling an ambiguous straight tile twice returns to its starting facing.
	var state_e := GameState.new()
	var lone := Vector2i(11, 13)
	state_e.grid[lone] = {"kind": "route", "level": "dirt"}
	var start_facing: String = SimulationEngine.route_shape(lone, state_e, {}).facing
	var once: String = SimulationEngine.cycle_shape_facing(lone, state_e, {})
	state_e.grid[lone].facing = once
	var twice: String = SimulationEngine.cycle_shape_facing(lone, state_e, {})
	assert(twice == start_facing, "Cycling a 2-way family (straight or corner-4) an even number of times for straight should return to the start")

	# Regression: a route tile with a node on one side (west) and a real
	# route tile continuing on an *adjacent* side (south) must NOT be forced
	# into a corner -- only route/storage/hub neighbors can force a shape.
	# It should default to a corner but stay tappable all the way to "ud".
	var stub_by_node_and_route := farm.grid_position + Vector2i(1, 0) # node to the west
	var state_f := GameState.new()
	state_f.grid[stub_by_node_and_route] = {"kind": "route", "level": "dirt"}
	state_f.grid[stub_by_node_and_route + Vector2i(0, 1)] = {"kind": "route", "level": "dirt"} # route to the south
	assert(SimulationEngine.is_shape_ambiguous(stub_by_node_and_route, state_f, nodes_by_pos), "A node beside a tile must never force its shape, even with a real route neighbor on an adjacent side")
	var reachable_ud := false
	var facing: String = SimulationEngine.route_shape(stub_by_node_and_route, state_f, nodes_by_pos).facing
	for _i in range(6):
		facing = SimulationEngine.cycle_shape_facing(stub_by_node_and_route, state_f, nodes_by_pos)
		state_f.grid[stub_by_node_and_route].facing = facing
		if facing == "ud":
			reachable_ud = true
			break
	assert(reachable_ud, "A node-adjacent ambiguous tile must be able to cycle all the way to a straight up-down facing")

func _node(map: MapData, node_id: String) -> NodeData:
	for node in map.node_placements:
		if node.node_id == node_id:
			return node
	return null
