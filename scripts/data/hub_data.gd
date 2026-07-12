class_name HubData
extends Resource

## SPEC.md §16 Hub (see also §4.4 for suggested per-type values).

@export var hub_id: String
@export var hub_type: GameEnums.HubType
@export var link_capacity: int
@export var flow_capacity: float
@export var route_discount: float
@export var daily_upkeep: float
