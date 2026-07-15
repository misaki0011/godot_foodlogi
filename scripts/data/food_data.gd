class_name FoodData
extends Resource

@export var food_id: String
@export var display_name: String
@export var base_value: float
@export var decay_per_tile: float
## Quality lost if any tile of the route uses Freeze Storage protection.
@export var freeze_penalty: float
@export var color: Color = Color.WHITE
