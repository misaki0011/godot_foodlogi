class_name GameBalance

const STARTING_FUNDS := 1500.0
const ROUTE_BUILD_COST := 8.0
const ROUTE_BASE_UPKEEP := 2.0
const BRIDGE_SURCHARGE := 40.0
const SPOILAGE_COST_PER_UNIT := 1.0

const ROUTE_LEVELS := [
	{"name": "Dirt", "capacity": 100.0, "upkeep": 1.0, "upgrade_cost": 0.0},
	{"name": "Paved", "capacity": 250.0, "upkeep": 1.6, "upgrade_cost": 120.0},
	{"name": "Main", "capacity": 500.0, "upkeep": 2.5, "upgrade_cost": 260.0},
]

const TERRAIN_COST := {
	GameEnums.TerrainType.PLAINS: 1.0,
	GameEnums.TerrainType.FOREST: 0.8,
	GameEnums.TerrainType.MOUNTAIN: 1.8,
	GameEnums.TerrainType.RIVER: 2.5,
	GameEnums.TerrainType.SNOW: 1.5,
}

const TERRAIN_DECAY := {
	GameEnums.TerrainType.PLAINS: 1.0,
	GameEnums.TerrainType.FOREST: 1.15,
	GameEnums.TerrainType.MOUNTAIN: 1.25,
	GameEnums.TerrainType.RIVER: 1.0,
}

static func food_types() -> Dictionary:
	return {
		"grain": _food("Grain", "dry", 3.0, 0.5, GameEnums.StorageType.NORMAL, 20.0, 0.0),
		"bread": _food("Bread", "dry", 5.0, 1.5, GameEnums.StorageType.NORMAL, 35.0, 5.0),
		"vegetables": _food("Vegetables", "fresh", 6.0, 2.5, GameEnums.StorageType.COOL, 40.0, 15.0),
		"milk": _food("Milk", "chilled", 8.0, 4.0, GameEnums.StorageType.COOL, 45.0, 10.0),
		"seafood": _food("Seafood", "frozen", 10.0, 6.0, GameEnums.StorageType.FREEZE, 45.0, 0.0),
	}

static func source_supplies() -> Dictionary:
	return {
		"vegetable_farm": {"grain": 80.0, "vegetables": 90.0},
		"bakery": {"bread": 80.0},
		"dairy_farm": {"milk": 75.0},
		"harbor": {"seafood": 55.0},
	}

static func settlement_demands() -> Dictionary:
	return {
		"village_a": [_demand("grain", 30, 20, 85), _demand("bread", 20, 35, 85)],
		"riverside_village": [_demand("vegetables", 35, 40, 85), _demand("seafood", 15, 45, 90)],
		"town_b": [_demand("bread", 30, 40, 85), _demand("vegetables", 30, 45, 85), _demand("milk", 20, 50, 88)],
		"mountain_village": [_demand("grain", 15, 30, 85), _demand("milk", 20, 55, 90)],
		"city_c": [_demand("vegetables", 40, 55, 90), _demand("milk", 35, 60, 92), _demand("seafood", 25, 60, 92)],
	}

static func settlement_type(id: String) -> GameEnums.SettlementType:
	return {
		"village_a": GameEnums.SettlementType.VILLAGE,
		"riverside_village": GameEnums.SettlementType.COASTAL_TOWN,
		"town_b": GameEnums.SettlementType.TOWN,
		"mountain_village": GameEnums.SettlementType.MOUNTAIN_VILLAGE,
		"city_c": GameEnums.SettlementType.CITY,
	}.get(id, GameEnums.SettlementType.VILLAGE)

static func settlement_price(id: String) -> float:
	return {
		"village_a": 1.0,
		"riverside_village": 1.1,
		"town_b": 1.1,
		"mountain_village": 1.1,
		"city_c": 1.3,
	}.get(id, 1.0)

static func storage_data(type: GameEnums.StorageType, id: String) -> StorageData:
	var data := StorageData.new()
	data.storage_id = id
	data.storage_type = type
	match type:
		GameEnums.StorageType.NORMAL:
			data.capacity = 150
			data.daily_upkeep = 10
			data.protection_distance = 4
			data.freshness_loss_multiplier = 0.70
			data.compatible_food_categories = PackedStringArray(["dry", "fresh"])
		GameEnums.StorageType.COOL:
			data.capacity = 100
			data.daily_upkeep = 35
			data.protection_distance = 8
			data.freshness_loss_multiplier = 0.35
			data.compatible_food_categories = PackedStringArray(["fresh", "chilled", "frozen"])
		GameEnums.StorageType.FREEZE:
			data.capacity = 70
			data.daily_upkeep = 80
			data.protection_distance = 14
			data.freshness_loss_multiplier = 0.10
			data.compatible_food_categories = PackedStringArray(["dry", "fresh", "chilled", "frozen"])
	return data

static func storage_cost(type: GameEnums.StorageType) -> float:
	return [80.0, 180.0, 400.0][type]

static func hub_data(type: GameEnums.HubType, id: String) -> HubData:
	var data := HubData.new()
	data.hub_id = id
	data.hub_type = type
	if type == GameEnums.HubType.SMALL:
		data.link_capacity = 4
		data.flow_capacity = 250
		data.route_discount = 0.15
		data.daily_upkeep = 25
	else:
		data.link_capacity = 8
		data.flow_capacity = 600
		data.route_discount = 0.25
		data.daily_upkeep = 60
	return data

static func hub_cost(type: GameEnums.HubType) -> float:
	return 150.0 if type == GameEnums.HubType.SMALL else 350.0

static func terrain_decay(terrain: GameEnums.TerrainType, food_id: String) -> float:
	if terrain == GameEnums.TerrainType.SNOW:
		return 1.3 if food_id in ["vegetables", "milk", "seafood"] else 1.1
	return TERRAIN_DECAY.get(terrain, 1.0)

static func freshness_multiplier(freshness: float) -> float:
	if freshness >= 90.0:
		return 1.25
	if freshness >= 60.0:
		return 1.0
	if freshness >= 40.0:
		return 0.6
	if freshness > 0.0:
		return 0.25
	return 0.0

static func _food(name: String, category: String, value: float, decay: float, preferred: GameEnums.StorageType, minimum: float, freeze_penalty: float) -> FoodData:
	var food := FoodData.new()
	food.food_id = name.to_lower()
	food.display_name = name
	food.category = category
	food.base_value = value
	food.decay_per_tile = decay
	food.preferred_storage = preferred
	food.allowed_storage = [GameEnums.StorageType.NORMAL, GameEnums.StorageType.COOL, GameEnums.StorageType.FREEZE]
	food.minimum_accepted_freshness = minimum
	food.freeze_penalty = freeze_penalty
	return food

static func _demand(food_id: String, amount: float, minimum: float, bonus: float) -> SettlementDemandData:
	var demand := SettlementDemandData.new()
	demand.food_id = food_id
	demand.amount_required = amount
	demand.minimum_freshness = minimum
	demand.bonus_freshness = bonus
	demand.overdelivery_tolerance = 0
	return demand
