class_name GameBalance

## Gameplay constants, ported 1:1 from fresh-routes-mvp.html so the Godot
## build behaves identically to the reference MVP (see SPEC.md v0.3).

const STARTING_FUNDS := 1500.0
const ROUTE_BUILD_COST := 8.0
const ROUTE_BASE_UPKEEP := 2.0
const BRIDGE_COST := 40.0
const HUB_CAP_PER_NETWORK := 2
const HUB_REGIONAL_UPGRADE_COST := 200.0
const GRID_SIZE := Vector2i(21, 14)
const RIVER_COL := 10

## level id ("dirt"/"paved"/"main") -> stats. "next" is "" at max level.
const ROUTE_LEVELS := {
	"dirt": {"cap": 60.0, "upkeep_mult": 1.0, "upgrade_cost": 0.0, "next": "paved", "label": "Dirt"},
	"paved": {"cap": 160.0, "upkeep_mult": 1.6, "upgrade_cost": 6.0, "next": "main", "label": "Paved"},
	"main": {"cap": 400.0, "upkeep_mult": 2.5, "upgrade_cost": 12.0, "next": "", "label": "Main"},
}

const STORAGE_TYPES := {
	GameEnums.StorageType.NORMAL: {"name": "Normal Storage", "build": 80.0, "upkeep": 10.0, "capacity": 150.0, "protection": 4, "mult": 0.70, "color": Color("8B7355")},
	GameEnums.StorageType.COOL: {"name": "Cool Storage", "build": 180.0, "upkeep": 35.0, "capacity": 100.0, "protection": 8, "mult": 0.35, "color": Color("5B8FA8")},
	GameEnums.StorageType.FREEZE: {"name": "Freeze Storage", "build": 400.0, "upkeep": 80.0, "capacity": 70.0, "protection": 14, "mult": 0.10, "color": Color("6E7FB8")},
}

const HUB_TYPES := {
	GameEnums.HubType.SMALL: {"name": "Small Hub", "build": 150.0, "upkeep": 25.0, "discount": 0.15, "flow_capacity": 250.0, "color": Color("D98E4A")},
	GameEnums.HubType.REGIONAL: {"name": "Regional Hub", "build": 350.0, "upkeep": 60.0, "discount": 0.25, "flow_capacity": 600.0, "color": Color("B9631E")},
}

static func food_types() -> Dictionary:
	return {
		"grain": _food("grain", "Grain", 3.0, 0.5, 0.0, Color("D9C36A")),
		"bread": _food("bread", "Bread", 5.0, 1.5, 4.0, Color("C89A5B")),
		"vegetables": _food("vegetables", "Vegetables", 6.0, 2.5, 8.0, Color("6FA85A")),
		"milk": _food("milk", "Milk", 8.0, 4.0, 10.0, Color("EDEFE6")),
		"seafood": _food("seafood", "Seafood", 10.0, 6.0, 0.0, Color("5B8FA8")),
	}

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

static func _food(id: String, name: String, value: float, decay: float, freeze_penalty: float, color: Color) -> FoodData:
	var food := FoodData.new()
	food.food_id = id
	food.display_name = name
	food.base_value = value
	food.decay_per_tile = decay
	food.freeze_penalty = freeze_penalty
	food.color = color
	return food
