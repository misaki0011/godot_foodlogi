class_name FoodFlowData
extends Resource

## SPEC.md §16 FoodFlow.

@export var flow_id: String
@export var food_id: String
@export var source_node: String
@export var destination_node: String
@export var path: Array[String] = []
@export var amount_per_day: float
@export var current_freshness: float
