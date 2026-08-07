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
## Built hubs allowed on one connected road network (raised to 10 in v0.7 item
## 76, returned to 2 in item 78).
##
## At 2 the cap is the brake rather than a backstop, and it is felt: a network
## gets two junctions, and a third means keeping the roads physically separate
## or clearing one. That is the topology decision §4.4 exists to pose -- and
## since a route drag now buys a junction where it taps a live road (§4.1), the
## cap is also what stops a network from accumulating them by gesture.
const HUB_CAP_PER_NETWORK := 2

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
## cross an existing tile", so it is priced AND capped to stay one: at §60 plus
## §6/day it loses to a detour of up to ~7 tiles, the deck costs an extra tile's
## worth of freshness to climb, and a connected road network only ever supports
## BRIDGE_CAP_PER_NETWORK of them. Together those keep crossings rare and
## deliberate instead of letting the map fill with interchanges -- which matters
## more since a route drag can buy a deck by crossing (§4.1) rather than by a
## deliberate trip to the Bridge tool.
##
## An existing bridge counts against BOTH networks it serves (see
## SimulationEngine.network_at_bridge_cap), so two is two crossings *touching*
## a network, not two built from it. (Raised to 10 in v0.7 item 76, returned to
## 2 in item 78.)
const BRIDGE_BUILD_COST := 60.0
const BRIDGE_UPKEEP := 6.0
const BRIDGE_CAP_PER_NETWORK := 2
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
##
## `cap` is what a tile carries COMFORTABLY, not a wall (v0.8 item 80). Past it
## the road still carries everything handed to it -- see CONGESTION_* below.
const ROUTE_LEVELS := {
	"dirt": {"cap": 60.0, "upkeep_mult": 1.0, "upgrade_cost": 0.0, "next": "paved", "label": "Dirt"},
	"paved": {"cap": 160.0, "upkeep_mult": 1.6, "upgrade_cost": 6.0, "next": "main", "label": "Paved"},
	"main": {"cap": 400.0, "upkeep_mult": 2.5, "upgrade_cost": 12.0, "next": "", "label": "Main"},
}

## ---------- cold corridors: sorting the traffic (v0.8 item 82) ----------
## Every other thing the player can do to a road is a PURCHASE placed on a
## tile -- pave it, chill it, junction it. A designation is a different verb:
## it decides what BELONGS on that road, and the map answers back by sending
## everything else the long way round.
##
## A cold corridor admits only the fastest-decaying foods. What that buys is
## not speed, it is EXCLUSION: a Cool Storage carries 100/day (STORAGE_TYPES),
## and a chiller standing on a trunk that everything funnels down is swamped by
## cargo that did not need chilling. Keep grain and bread off it and the same
## §180 building covers the milk and seafood completely.
##
## The trade that makes it a decision rather than a free win: the excluded
## foods still have to get there, so a corridor costs a detour -- more road,
## more upkeep, more distance. Which is why the classification is BY DECAY
## RATE rather than authored per map. Grain loses 0.5 a tile and can go eight
## tiles out of its way for four points of freshness; seafood loses 6.0 and
## cannot go anywhere. The player's insight is meant to be exactly that: the
## toughest cargo takes the detour, and the food table is what tells them so.
##
## Derived rather than listed, so a sixth food classifies itself. At 3.0 the
## line falls between vegetables (2.5) and milk (4.0) -- two foods in, three
## out, on a five-food table.
const COLD_CORRIDOR_MIN_DECAY := 3.0

## Whether `food_id` may travel a cold corridor.
static func may_use_cold_corridor(food_id: String) -> bool:
	var food: FoodData = food_types().get(food_id)
	return food != null and food.decay_per_tile >= COLD_CORRIDOR_MIN_DECAY

## The foods a corridor admits, for the tool's own description -- so the button
## names them rather than making the player infer the threshold.
static func cold_corridor_foods() -> Array[String]:
	var out: Array[String] = []
	for food_id in food_types():
		if may_use_cold_corridor(food_id):
			out.append(food_id)
	return out

## ---------- congestion: what an overloaded road costs (v0.8 item 80) ----------
## Capacity used to be a HARD WALL: a tile with no room left contributed
## nothing, so a line whose path was full delivered exactly zero and earned
## exactly zero. Two things were wrong with that, and they compound.
##
## It made the tile upgrade COMPULSORY rather than optional. A player is meant
## to be paid for completing a route and for expanding a source; paving is the
## optional move that buys a better score. A wall inverts that -- until the
## trunk is paved, some settlement simply gets nothing, whatever else the
## player does.
##
## And it starved lines in DICTIONARY ORDER. Whichever line was simulated
## first drained the trunk and the rest got nothing, so a Town's foods failed
## in the order their ids happened to sort: Town D's bread and grain came up
## empty while its vegetables were served, because 'b' and 'g' sort before 'v'.
##
## A busy road now still carries everything, and charges for it in the one
## currency this game has: cargo on an overloaded tile decays faster, so a
## packed dirt trunk delivers in full but arrives dull, loses the freshness
## bonus, and drags the grade down. Paving it (60 -> 160) buys that back. The
## decision moves from "pave or go without" to "is this road's freshness worth
## §6 a tile and the upkeep" -- which is a decision rather than a toll.
##
## Multiplicative on the food's own decay rather than a flat surcharge, because
## congestion is TIME: a cart held up on a busy road spends longer holding its
## cargo, and an hour costs milk (4.0/tile) eight times what it costs grain
## (0.5). That is what makes a jam on the dairy run a problem worth paving and
## a jam on the grain run something to shrug at -- the food set doing work the
## roads alone cannot.
##
## The ramp starts at 0.9 rather than 1.0 so it lines up with the congestion
## markers the map already draws at 90% (Main._add_congestion_marker): the
## amber dot is now the first tile costing the player something, rather than a
## warning about a cliff further on.
const CONGESTION_FREE_LOAD := 0.9
## Extra decay multiplier per unit of load past CONGESTION_FREE_LOAD. At the
## nominal capacity (load 1.0) a tile decays 1.2x; half as much again, 1.9x.
const CONGESTION_DECAY_SLOPE := 2.0
## Ceiling on that multiplier -- reached at about 1.45x capacity, so a jam is
## bounded at twice the food's own decay however badly a tile is
## over-subscribed. Without a ceiling the penalty grows without limit and a
## trunk at ten times its figure is indistinguishable from no road at all.
##
## **Two rather than three, and the number is load-bearing.** At 3x, region 1's
## own worst case -- every one of Town D's four lines down a single dirt trunk,
## 167% loaded -- landed milk at exactly 0% and paid nothing for it. A
## completed route that earns zero is the failure this whole revision exists to
## remove, and it is no better arriving through traffic than through an unpaid
## order. At 2x the same run lands milk around 28% against 64% on paved: still
## a bad road, still obviously worth §6 a tile to fix, and still paying.
##
## What the ceiling does NOT promise: a long enough route lands cargo at 0%
## congested or not -- seafood at 6.0/tile runs out after 17 tiles on an empty
## road today. Congestion does not add that failure mode, and the answers to it
## are the ones already in the game: pave, shorten, or chill.
const CONGESTION_DECAY_MAX := 2.0

## The load at which a tile is worth reporting to the player, matching the
## overlay's own threshold.
static func is_congested(load_ratio: float) -> bool:
	return load_ratio >= CONGESTION_FREE_LOAD

## The decay multiplier a tile carrying `load_ratio` of its capacity applies.
## 1.0 anywhere below the threshold, so an uncongested map behaves exactly as
## it did before congestion existed.
static func congestion_decay_multiplier(load_ratio: float) -> float:
	if load_ratio <= CONGESTION_FREE_LOAD:
		return 1.0
	return minf(1.0 + (load_ratio - CONGESTION_FREE_LOAD) * CONGESTION_DECAY_SLOPE, CONGESTION_DECAY_MAX)

const STORAGE_TYPES := {
	GameEnums.StorageType.NORMAL: {"name": "Normal Storage", "build": 80.0, "upkeep": 10.0, "capacity": 150.0, "protection": 4, "mult": 0.70, "color": Color("8B7355")},
	GameEnums.StorageType.COOL: {"name": "Cool Storage", "build": 180.0, "upkeep": 35.0, "capacity": 100.0, "protection": 8, "mult": 0.35, "color": Color("5B8FA8")},
}

## `flow_capacity` is gone for the Small Hub (v0.7 item 77): a junction carries
## the road it stands on (SimulationEngine.tile_capacity reads the level
## underneath) rather than a figure of its own. The flat 250 made a §150 hub a
## cheaper capacity upgrade than paving on dirt, and a silent capacity CUT on a
## Main trunk. A future tier that genuinely carries more than its road brings
## the field back.
const HUB_TYPES := {
	GameEnums.HubType.SMALL: {"name": "Small Hub", "build": 150.0, "upkeep": 25.0, "discount": 0.15, "color": Color("D98E4A")},
}

static func food_types() -> Dictionary:
	return {
		"grain": _food("grain", "Grain", 3.0, 0.5, Color("D9C36A")),
		"bread": _food("bread", "Bread", 5.0, 1.5, Color("C89A5B")),
		"vegetables": _food("vegetables", "Vegetables", 6.0, 2.5, Color("6FA85A")),
		"milk": _food("milk", "Milk", 8.0, 4.0, Color("EDEFE6")),
		"seafood": _food("seafood", "Seafood", 10.0, 6.0, Color("5B8FA8")),
	}

## ---------- what a delivery pays (v0.8) ----------
## Two rules, and they are the whole economy:
##
##     paid  = amount delivered x base_value x (freshness / 100)
##     bonus = paid x FRESHNESS_BONUS_RATE, if the line's average freshness
##             reached the settlement's own bonus_freshness
##
## So a connected source and settlement always earn -- delivering IS being
## paid -- and freshness decides how well. That is the game stated in two
## sentences, which is what the old rules could not manage:
##
## GONE: the all-or-nothing gate. A line used to pay nothing whatsoever
## unless the settlement's whole requested amount arrived, so a player's
## first road could run perfectly and bank §0. It was not even reachable
## late: region 1's own totals out-run its sources on three foods (grain
## 85 vs the Farm's 80, bread 95 vs 80, vegetables 110 vs the Garden's 90),
## so once every line is open some of them cannot be filled at all until a
## source is upgraded. Paying per unit means the player earns the whole way
## up that ramp instead of only at the top of it. Filling the WHOLE order is
## still what opens the next one (OrderBook), so completion keeps a job --
## it decides progress rather than pay.
##
## GONE: the 1.25/1.0/0.6/0.25 tier table this replaced. The map shows three
## speech-bubble states and the tiers paid out six ways, so two lines both
## reading green could pay 1.25x and 1.5625x with nothing on screen saying
## why. A straight proportion has no cliffs -- 71% pays exactly 1% more than
## 70% -- and the number that pays is the number already printed on the
## bubble.
##
## GONE: settlement.min_freshness as a refusal, and the spoilage charge that
## came with it. Cargo under the floor was binned, still consumed the day's
## demand AND its source's supply, and then cost 0.5x its value -- one
## mistake punished four ways, with the goods destroyed. Under-fresh cargo
## now simply arrives and pays what it is worth.
##
## The rate stays at 0.25 rather than rising, because the proportion above
## already does the retired tiers' work: a green line at 85% pays
## 0.85 x 1.25 = 1.06x base against an amber line at 68% paying 0.68x, a
## 1.56x gap -- the same gap the tier table plus the bonus used to produce
## (1.25 x 1.25 = 1.5625). Same incentive to chase green, one mechanism
## instead of two.
const FRESHNESS_BONUS_RATE := 0.25

static func _food(id: String, name: String, value: float, decay: float, color: Color) -> FoodData:
	var food := FoodData.new()
	food.food_id = id
	food.display_name = name
	food.base_value = value
	food.decay_per_tile = decay
	food.color = color
	return food
