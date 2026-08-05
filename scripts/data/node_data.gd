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

## Source-only (DEV-03): how many times this source has been expanded, 0 to
## GameBalance.SOURCE_UPGRADE_MAX. Authored 0 and raised at runtime on Main's
## private copy of the map.
##
## `produces` stays the AUTHORED BASE and is never mutated -- read the live
## figure through daily_supply()/supply_of(). Scaling the dictionary in place
## worked while there was exactly one upgrade and stops working the moment
## there are five: the base is unrecoverable afterwards, so every later step
## would have to be derived from an already-scaled number.
##
## Each upgrade adds ONE base unit of output rather than doubling what is
## already there, so the ramp is 1x, 2x, 3x ... 6x. The first upgrade is still
## a doubling, which is what the tool has always promised; compounding instead
## would put a five-times-upgraded source at 32x its authored supply, which is
## not a decision the player is making so much as a number running away. It
## also gives the yard's produce models something exact to say: one model is
## one base unit of daily output, so the pile IS the supply figure.
##
## The upgrade does NOT change the footprint. Sources stand on their full 2x1
## from day 1, so the second tile is simply part of the source rather than
## ground held back for it. Reserving a cell and drawing it as a ghost was
## tried first and read as a strange empty square nobody could identify --
## land the player cannot use is much clearer when it is visibly the building
## itself.
@export var upgrade_level: int = 0

@export var display_name: String
## Settlement-only descriptive label, e.g. "Village", "Town", "City (late
## objective)". Display only -- rules key off `settlement_type`, because a
## free-text label is no basis for a cap.
@export var kind: String = ""
## Settlement-only (DEV-04): how many demand lines this place may ever hold,
## via GameBalance.DEMAND_CAP. Authored alongside `size`, which it matches in
## spirit: a City is bigger on the map and hungrier on the ledger.
@export var settlement_type: GameEnums.SettlementType = GameEnums.SettlementType.VILLAGE
## Source-only: food_id -> daily supply AT THE AUTHORED BASE LEVEL. What the
## source actually produces today is daily_supply(), which scales this by the
## upgrades bought; nothing should read the raw figure except as a base.
@export var produces: Dictionary = {}
## Settlement-only: food_id -> daily demand, asked for in full every day.
## This is the settlement's EVENTUAL appetite -- only the lines whose orders
## have opened are actually demanded (see OrderBook).
@export var demand: Dictionary = {}
## Settlement-only, and RETIRED as a rule in v0.8: this used to be the
## freshness below which a settlement refused a delivery outright -- the cargo
## binned, the day's demand and the source's supply spent anyway, and a
## spoilage charge on top. Nothing reads it now; every delivery arrives and is
## paid what its freshness is worth (GameBalance.FRESHNESS_BONUS_RATE).
##
## The field stays because the authored maps still carry values for it and
## dropping it would rewrite every .tres for no gain, and because a later
## region may well want a "this place will not touch anything under X" rule
## again -- as a settlement's character rather than as the whole game's
## failure mode.
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

## How much this source puts out per day, as food_id -> amount, with every
## upgrade bought so far applied. Sources only; a settlement produces nothing.
func daily_supply() -> Dictionary:
	var out := {}
	for food_id in produces:
		out[food_id] = produces[food_id] * supply_multiplier()
	return out

## One food's live daily output, 0 if this node does not produce it.
func supply_of(food_id: String) -> float:
	return produces.get(food_id, 0.0) * supply_multiplier()

## What the upgrades bought so far multiply the authored base by: 1x
## un-upgraded, then one more base unit per upgrade. See `upgrade_level`.
func supply_multiplier() -> float:
	return 1.0 + float(upgrade_level) * GameBalance.SOURCE_UPGRADE_SUPPLY_STEP

## Whether this node still has an upgrade available (DEV-03). A source can be
## expanded up to GameBalance.SOURCE_UPGRADE_MAX times; settlements never can.
func can_upgrade() -> bool:
	return node_type == GameEnums.NodeType.SOURCE and upgrade_level < GameBalance.SOURCE_UPGRADE_MAX

## How many demand lines this settlement may hold (DEV-04). Sources have none.
func demand_cap() -> int:
	if node_type != GameEnums.NodeType.SETTLEMENT:
		return 0
	return GameBalance.DEMAND_CAP.get(settlement_type, 0)
