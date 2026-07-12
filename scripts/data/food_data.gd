class_name FoodData
extends Resource

@export var food_id: String
@export var display_name: String
@export var category: String
@export var base_value: float
@export var decay_per_tile: float
@export var preferred_storage: GameEnums.StorageType
@export var allowed_storage: Array[GameEnums.StorageType] = []
@export var minimum_accepted_freshness: float
@export var freeze_penalty: float

