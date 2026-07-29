class_name NodeData
extends Resource

## A fixed food source or settlement, matching fresh-routes-mvp.html's NODES.
## Sources and settlements are placed once at map-build time and never
## created or removed by the player (only routes/storage/hubs are).

@export var node_id: String
@export var node_type: GameEnums.NodeType
## The footprint's top-left cell. A node occupies `size` cells from here, all
## of which are unbuildable and any of which a road may connect to.
@export var grid_position: Vector2i
## Footprint in grid cells (DEV-02). Villages and un-upgraded sources are 1x1;
## a Town is 2x1 and a City 2x2, so the map shows at a glance which places are
## big. Everything that asks "is there a node at this cell" resolves through
## Main._nodes_by_pos, which holds an entry per occupied cell -- so a footprint
## is mostly invisible to the rest of the game. The exceptions are delivery
## pathfinding (which may leave from or arrive at ANY of a node's cells) and
## anything that iterates nodes, which must iterate node IDs rather than cells
## or it will process a City four times.
@export var size: Vector2i = Vector2i.ONE
@export var display_name: String
## Settlement-only descriptive label, e.g. "Village", "Town", "City (late objective)".
@export var kind: String = ""
## Source-only: food_id -> daily supply.
@export var produces: Dictionary = {}
## Settlement-only: food_id -> daily demand, asked for in full every day.
## This is the settlement's EVENTUAL appetite -- only the lines whose orders
## have opened are actually demanded (see OrderBook).
@export var demand: Dictionary = {}
## Settlement-only: reject deliveries below this freshness.
@export var min_freshness: float = 0.0
## Settlement-only: freshness at/above which delivery earns the bonus tier.
@export var bonus_freshness: float = 0.0

## Every grid cell this node stands on.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in maxi(1, size.x):
		for dy in maxi(1, size.y):
			out.append(grid_position + Vector2i(dx, dy))
	return out

func occupies(cell: Vector2i) -> bool:
	var delta := cell - grid_position
	return delta.x >= 0 and delta.y >= 0 and delta.x < maxi(1, size.x) and delta.y < maxi(1, size.y)

## The footprint's far corner -- the cell diagonally opposite grid_position.
## Together the two corners give the span a marker or bubble centres on.
func far_cell() -> Vector2i:
	return grid_position + Vector2i(maxi(1, size.x) - 1, maxi(1, size.y) - 1)

## Grid distance from this node's footprint to `other`'s, measured between
## their nearest cells rather than their origins -- two 2x2 blocks a tile
## apart are a tile apart, however far their top-left corners are.
func grid_distance_to(other: NodeData) -> int:
	var best := 1 << 30
	for a in cells():
		for b in other.cells():
			best = mini(best, absi(a.x - b.x) + absi(a.y - b.y))
	return best
