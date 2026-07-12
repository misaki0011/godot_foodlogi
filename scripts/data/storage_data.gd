class_name StorageData
extends Resource

## SPEC.md §16 Storage (see also §4.3 for suggested per-type values).

@export var storage_id: String
@export var storage_type: GameEnums.StorageType
@export var capacity: float
@export var daily_upkeep: float
@export var protection_distance: int
@export var freshness_loss_multiplier: float
@export var compatible_food_categories: PackedStringArray = []
