class_name NodeData
extends Resource

## A fixed food source or settlement, matching fresh-routes-mvp.html's NODES.
## Sources and settlements are placed once at map-build time and never
## created or removed by the player (only routes/storage/hubs are).

@export var node_id: String
@export var node_type: GameEnums.NodeType
@export var grid_position: Vector2i
@export var display_name: String
## Settlement-only descriptive label, e.g. "Village", "Town", "City (late objective)".
@export var kind: String = ""
## Source-only: food_id -> daily supply.
@export var produces: Dictionary = {}
## Settlement-only: food_id -> daily demand (before wobble).
@export var demand: Dictionary = {}
## Settlement-only: reject deliveries below this freshness.
@export var min_freshness: float = 0.0
## Settlement-only: freshness at/above which delivery earns the bonus tier.
@export var bonus_freshness: float = 0.0
