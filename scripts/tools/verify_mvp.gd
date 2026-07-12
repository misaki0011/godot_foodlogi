extends SceneTree

func _initialize() -> void:
	_test_route_formulas()
	_test_storage_preservation()
	_test_daily_simulation()
	print("MVP simulation checks passed.")
	quit()

func _test_route_formulas() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres")
	var path: Array[Vector2i] = [Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2)]
	var cost := SimulationEngine.route_build_cost(map, path)
	var expected := GameBalance.ROUTE_BUILD_COST * 2.5 + GameBalance.BRIDGE_SURCHARGE + GameBalance.ROUTE_BUILD_COST
	assert(is_equal_approx(cost, expected), "River routes must include terrain cost and bridge surcharge")
	var route := _route("formula", "a", "b", 4, GameEnums.TerrainType.PLAINS)
	assert(is_equal_approx(SimulationEngine.route_upkeep(route), 8.0))
	var milk: FoodData = GameBalance.food_types().milk
	assert(is_equal_approx(SimulationEngine.route_freshness(route, milk).freshness, 84.0))

func _test_storage_preservation() -> void:
	var milk: FoodData = GameBalance.food_types().milk
	var first := _route("first", "dairy_farm", "cool", 3, GameEnums.TerrainType.PLAINS)
	var second := _route("second", "cool", "town_b", 3, GameEnums.TerrainType.PLAINS)
	var before := SimulationEngine.route_freshness(first, milk)
	var storage := GameBalance.storage_data(GameEnums.StorageType.COOL, "cool")
	var after := SimulationEngine.route_freshness(second, milk, before.freshness, {"distance": storage.protection_distance, "multiplier": storage.freshness_loss_multiplier})
	var direct := _route("direct", "dairy_farm", "town_b", 6, GameEnums.TerrainType.PLAINS)
	assert(after.freshness > SimulationEngine.route_freshness(direct, milk).freshness)
	assert(after.freshness <= before.freshness, "Storage preserves but never restores freshness")

func _test_daily_simulation() -> void:
	var map: MapData = load("res://data/maps/region_1_map.tres").duplicate(true)
	var state := GameState.new()
	state.funds = GameBalance.STARTING_FUNDS
	state.routes = [
		_route("farm_village", "vegetable_farm", "village_a", 4, GameEnums.TerrainType.PLAINS),
		_route("bakery_village", "bakery", "village_a", 3, GameEnums.TerrainType.PLAINS),
	]
	var report := SimulationEngine.simulate_day(state, map)
	assert(report.delivered["village_a:grain"].amount == 30.0)
	assert(report.delivered["village_a:bread"].amount == 20.0)
	assert(report.food_income > 0.0)
	assert(report.route_upkeep > 0.0)
	assert(state.day == 2)
	assert(state.last_report == report)

func _route(id: String, from: String, to: String, length: int, terrain: GameEnums.TerrainType) -> RouteSegmentData:
	var route := RouteSegmentData.new()
	route.route_id = id
	route.from_node = from
	route.to_node = to
	route.length = length
	route.capacity = GameBalance.ROUTE_LEVELS[0].capacity
	route.base_upkeep = GameBalance.ROUTE_BASE_UPKEEP
	for i in length:
		route.terrain_profile.append(terrain)
	return route
