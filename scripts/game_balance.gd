class_name GameBalance

## Gameplay constants, ported 1:1 from fresh-routes-mvp.html so the Godot
## build behaves identically to the reference MVP (see SPEC.md v0.3).

const STARTING_FUNDS := 1500.0
const ROUTE_BUILD_COST := 8.0
const ROUTE_BASE_UPKEEP := 2.0
## Surcharge for drawing a route tile onto the river column -- an automatic,
## free-standing river crossing, nothing to do with the placed BRIDGE_* deck
## below (which crosses a ROAD, not water).
const RIVER_BRIDGE_COST := 40.0
## Built hubs allowed on one connected road network (v0.7 item 76: 2 -> 10).
##
## The cap is a backstop, not the brake. A hub costs §150 up front and §25/day
## forever, against a discount of 15% on the upkeep of the road tiles directly
## connected to it -- at most four of them, so at most §1.20/day back on dirt
## and §3/day on Main. A hub has never paid for itself out of the discount, and
## a tenth one costs exactly what the first did: the treasury is what stops hub
## spam, and it stops it well before ten.
const HUB_CAP_PER_NETWORK := 10

## How many foods a settlement may ever demand, by type (DEV-04). A budget
## the map is authored against rather than anything computed at runtime: the
## order book only ever opens lines that already exist in a settlement's
## demand, so the cap's job is to keep the map honest -- MapData.validate()
## rejects a settlement authored past it.
##
## A City is 5 rather than the 8 the design first asked for, because there
## are only five foods in the game and a settlement cannot want the same one
## twice. City E wanting ALL of them is the real late-game objective; 8 would
## be an unreachable number written down.
const DEMAND_CAP := {
	GameEnums.SettlementType.VILLAGE: 2,
	GameEnums.SettlementType.TOWN: 4,
	GameEnums.SettlementType.CITY: 5,
}

## Source upgrade (DEV-03). A one-off purchase that doubles a source's daily
## output and widens it to 2x1 on the map -- capital, not a subscription, so
## it carries no upkeep: a per-day charge on a source would bleed the player
## for owning infrastructure rather than for running it, which is what route
## upkeep is already for.
##
## Priced well above a hub (150) because it is the answer to a harder problem.
## Vegetables are over-subscribed on region 1 the moment every line opens --
## Village B 25 + Village C 20 + Town D 30 + City E 35 = 110 against the
## Garden's 90 -- so the Garden upgrade is not a luxury, it is the only way
## that demand is ever fully served.
const SOURCE_UPGRADE_COST := 300.0

## Each upgrade adds this many BASE units of daily output, so the ramp is
## linear (1x, 2x, 3x ...) rather than compounding. The first upgrade is still
## the doubling the tool has always promised; five compounding doublings would
## be 32x, which is a number running away rather than a decision the player is
## making. One step is also exactly one produce model on the source's yard, so
## the pile in the map IS the supply figure.
const SOURCE_UPGRADE_SUPPLY_STEP := 1.0

## How many times one source may be expanded. The cost does not escalate: the
## treasury and the region's own demand do the limiting, since a source already
## out-supplying every line it feeds earns nothing from the next upgrade.
const SOURCE_UPGRADE_MAX := 5

## ---------- bridges: road-over-road crossings (placed structure) ----------
## Built with the Bridge tool onto one existing route tile, turning it into a
## crossing: the road already there keeps running underneath, and a raised deck
## across it lets a SECOND route pass straight over without the two ever
## joining networks (see SimulationEngine's lane rules).
##
## A bridge is the single, deliberate, paid exception to "a new route can never
## cross an existing tile", and what keeps it one is the price rather than the
## cap (v0.7 item 76: 2 -> 10): at §60 plus §6/day it loses to a detour of up to
## ~7 tiles, and the deck costs an extra tile's worth of freshness to climb, so
## going around stays the right answer most of the time whatever the cap says.
## The cap is now a backstop against a map of interchanges, not the everyday
## brake -- and the geometry is its own limit, since no two bridges may sit side
## by side and each needs a straight run with room to land on both sides.
##
## An existing bridge counts against BOTH networks it serves (see
## SimulationEngine.network_at_bridge_cap), so ten is ten crossings *touching*
## a network, not ten built from it.
const BRIDGE_BUILD_COST := 60.0
const BRIDGE_UPKEEP := 6.0
const BRIDGE_CAP_PER_NETWORK := 10
## Freshness decay multiplier for the tile a delivery spends ON the deck --
## ramping up and back down costs roughly one extra tile of decay, so an
## overpass is a genuine trade-off against going around rather than a strictly
## better road.
const BRIDGE_DECK_DECAY_MULT := 2.0
const GRID_SIZE := Vector2i(21, 14)
const RIVER_COL := 10

## The coastline in the map's south-east corner (TERR-10). Open sea: no route
## may be built on it at any price, so it is a shape the player routes AROUND
## rather than a toll they pay.
##
## Placed so the Harbor at (18, 9) stands ON the coast rather than inland,
## which is where a harbor belongs and which makes the seafood run start at the
## water's edge. Deliberately clear of every node footprint and of City E at
## (14, 9); MapData.validate() enforces both, and that nothing is walled in.
## The rectangles STEP, rather than squaring off the corner: the shoreline runs
## diagonally out from under City E, so the land narrows toward the point
## instead of stopping at a wall. A square block of water reads as a chunk
## deleted from the board; a stepped one reads as a coast.
const SEA_RECTS: Array[Rect2i] = [
	Rect2i(20, 9, 1, 1),   # the cell east of the Harbor, so it has water on two sides
	Rect2i(18, 10, 3, 1),  # the row directly south of the Harbor
	Rect2i(18, 11, 3, 1),  # x 18-20
	Rect2i(17, 12, 4, 2),  # x 17-20 / y 12-13, the open corner
]

## ---------- day clock (LOOP-07) ----------
## Real-time seconds one in-game day lasts while the auto-run clock is
## ticking. The player keeps building while it counts down; when it hits
## zero the day simulates itself and the next one starts, so the normal loop
## never stops for a "Run the Day" click.
const DAY_LENGTH_SEC := 60.0
## Selectable clock multipliers, cycled by the speed button.
const DAY_SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const DAY_SPEED_LABELS: Array[String] = ["1x", "2x", "4x"]
## Countdown thresholds (in unscaled seconds) where the timer turns amber
## and then red, so the last stretch of a day reads at a glance.
const DAY_CLOCK_WARN_SEC := 15.0
const DAY_CLOCK_URGENT_SEC := 5.0
## How long the non-blocking end-of-day summary card stays on screen.
const DAY_SUMMARY_HOLD_SEC := 5.0

## level id ("dirt"/"paved"/"main") -> stats. "next" is "" at max level.
const ROUTE_LEVELS := {
	"dirt": {"cap": 60.0, "upkeep_mult": 1.0, "upgrade_cost": 0.0, "next": "paved", "label": "Dirt"},
	"paved": {"cap": 160.0, "upkeep_mult": 1.6, "upgrade_cost": 6.0, "next": "main", "label": "Paved"},
	"main": {"cap": 400.0, "upkeep_mult": 2.5, "upgrade_cost": 12.0, "next": "", "label": "Main"},
}

const STORAGE_TYPES := {
	GameEnums.StorageType.NORMAL: {"name": "Normal Storage", "build": 80.0, "upkeep": 10.0, "capacity": 150.0, "protection": 4, "mult": 0.70, "color": Color("8B7355")},
	GameEnums.StorageType.COOL: {"name": "Cool Storage", "build": 180.0, "upkeep": 35.0, "capacity": 100.0, "protection": 8, "mult": 0.35, "color": Color("5B8FA8")},
}

const HUB_TYPES := {
	GameEnums.HubType.SMALL: {"name": "Small Hub", "build": 150.0, "upkeep": 25.0, "discount": 0.15, "flow_capacity": 250.0, "color": Color("D98E4A")},
}

static func food_types() -> Dictionary:
	return {
		"grain": _food("grain", "Grain", 3.0, 0.5, Color("D9C36A")),
		"bread": _food("bread", "Bread", 5.0, 1.5, Color("C89A5B")),
		"vegetables": _food("vegetables", "Vegetables", 6.0, 2.5, Color("6FA85A")),
		"milk": _food("milk", "Milk", 8.0, 4.0, Color("EDEFE6")),
		"seafood": _food("seafood", "Seafood", 10.0, 6.0, Color("5B8FA8")),
	}

## A food line pays nothing at all unless the settlement's whole requested
## amount arrived (see SimulationEngine.run_day): a half-filled order is
## not a half sale, it is a settlement that went without. On top of that,
## a line that arrived at the settlement's own bonus_freshness or better
## pays this much again as a bonus -- the difference between the amber and
## green speech bubbles on the map.
const FRESHNESS_BONUS_RATE := 0.25

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

static func _food(id: String, name: String, value: float, decay: float, color: Color) -> FoodData:
	var food := FoodData.new()
	food.food_id = id
	food.display_name = name
	food.base_value = value
	food.decay_per_tile = decay
	food.color = color
	return food
