class_name NodeData
extends Resource

## SPEC.md §16 Node + display/linkage fields needed to place it on the map.

@export var node_id: String
@export var node_type: GameEnums.NodeType
@export var grid_position: Vector2i
@export var display_name: String
## Holds a StorageData or HubData instance when node_type is STORAGE or HUB.
## Left null for SOURCE and SETTLEMENT nodes in this MVP.
@export var linked_resource: Resource
