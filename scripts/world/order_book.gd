class_name OrderBook

## Which of a settlement's demand lines are live, and how the next one is
## chosen (DEV-01).
##
## A settlement's NodeData.demand is its *eventual* appetite -- every food it
## will ever ask for. It does not all switch on at once:
##
##     fill an order  ->  a new order opens, straight away
##
## No prompt and no confirmation. An earlier version put two offers on the
## table and had the player tap one, which bought a deepen-or-expand decision
## at the cost of stalling the whole region behind a tap that had to be
## noticed and understood. The region now keeps moving on its own, and the
## variety the choice used to provide is kept by alternating the two kinds of
## opening (see _next_line).
##
## Nothing on the map ever appears or disappears -- all five settlements and
## all five sources stand there from day 1, so the whole region is visible to
## plan against. What develops is the demand, and the road network the player
## lays down to meet it. A settlement is never founded, upgraded or resized:
## it simply starts placing orders. A village visibly mutating into a city
## reads as a city-builder; this is a logistics game, and the thing that
## should visibly grow is the network the player drew.
##
## PROGRESS, NOT DAYS
## ------------------
## Nothing here consults the calendar. An earlier version gated on
## `earliest_day` plus a "held 70% happiness for 2 consecutive days" streak,
## and both were really clocks -- the streak counted days too, just
## conditionally. The rule now is: idle for a hundred days and nothing opens,
## fill an order in an hour and the next choice is waiting. Time is the
## medium; delivering is the currency. GameState.day still drives the day
## clock, the sun and the report -- it just drives no progression.
##
## WHAT COUNTS AS FILLED
## ---------------------
## A line is filled when the whole requested amount arrives, at any freshness
## at all. Freshness has one job -- it decides how well the player is paid --
## and it never decides whether they advance.
##
## Since v0.8 this is the ONLY thing completing an order does. Delivering is
## what pays now, per unit as it lands, so a half-filled line is a half sale
## rather than nothing (see GameBalance.FRESHNESS_BONUS_RATE). That leaves
## "the whole order arrived" as the region's progress gate and nothing else,
## which is the right job for it: growth should wait on a settlement being
## properly served, while the player's income tracks what they actually moved
## today. It also keeps the pacing this book was built around -- a line that
## is nearly filled every day opens nothing, so the region does not run away
## from a network that cannot yet keep up with it.
##
## Filled is latched. Once the player has proven they can serve a line, that
## is proven for good -- a later bad day must not un-open an order.
##
## Kept free of node references (like DayCycle) so the whole progression can
## be stepped and asserted headlessly in the dev checks.

## How many of the easiest remaining lines each kind of opening draws from.
## Eligibility is deliberately a RANK, not a distance in difficulty
## points: the map's difficulties are unevenly spaced (Village A's grain sits
## 3.5 points from the next line and 48 from the hardest), so any absolute
## reach is either too tight to offer a pair early or too loose to mean
## anything later. Taking the easiest few always yields a real choice, always
## offers the gentlest options available, and slides upward on its own as they
## are taken -- no tuning, and no early opening that is a wall.
const OFFER_POOL_SIZE := 3

## Seeds the book with the map's opening orders. Fixed lines rather than a
## choice: on day 1 nothing is built and offers would be noise, and a known
## first beat is worth a great deal for teaching. See MapData.opening_lines
## for why there are three of them rather than one.
static func initialize(state: GameState, map_data: MapData) -> void:
	state.active_orders.clear()
	state.filled_lines.clear()
	state.next_prefers_expand = true
	if state.run_seed == 0:
		state.run_seed = randi()
	state.rng_state = state.run_seed
	for line in map_data.opening_lines:
		_open(state, line)

## The subset of `settlement.demand` whose orders have opened -- what the
## simulation, the bubbles and the tip all work from.
##
## Iterates the settlement's own demand rather than the open-line record, so
## the authored food order is preserved (bubbles stay in a stable position
## from day to day) and a schedule naming a food the settlement never wanted
## cannot conjure demand out of nothing.
static func active_demand(state: GameState, settlement: NodeData) -> Dictionary:
	var open_lines: Dictionary = state.active_orders.get(settlement.node_id, {})
	var result := {}
	for food_id in settlement.demand:
		if open_lines.has(food_id):
			result[food_id] = settlement.demand[food_id]
	return result

static func has_active_orders(state: GameState, settlement: NodeData) -> bool:
	return not state.active_orders.get(settlement.node_id, {}).is_empty()

## Folds the day just simulated into the book: every open line that came in
## full is latched as filled, and each line filled for the FIRST time opens a
## new one straight away. Refilling a line the player already proved opens
## nothing -- otherwise a working network would sprout an order every day.
##
## Returns the lines newly opened, so the caller can announce them.
static func record_day(state: GameState, map_data: MapData, nodes: Array[NodeData]) -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	for node in nodes:
		if node.node_type != GameEnums.NodeType.SETTLEMENT:
			continue
		var status: Dictionary = state.last_settlement_status.get(node.node_id, {})
		for food_id in status:
			var line: Dictionary = status[food_id]
			# The amber test, and deliberately a binary one: 99% delivered is
			# a red bubble, earns nothing, and does not advance the player.
			# A short order is not a partial sale (SPEC.md ECON-01).
			if line.delivered < line.requested - 0.01 or line.delivered <= 0.0:
				continue
			var key := line_key(node.node_id, food_id)
			if state.filled_lines.has(key):
				continue
			state.filled_lines[key] = true
			var next := _next_line(state, map_data)
			if not next.is_empty():
				_open(state, next)
				opened.append(next)
	return opened

## Whether a line has been opened already, in which case it is not a
## candidate.
static func _is_taken(state: GameState, node_id: String, food_id: String) -> bool:
	return state.active_orders.get(node_id, {}).has(food_id)

## Every line still unopened, easiest first.
static func eligible_lines(state: GameState, map_data: MapData) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for line in map_data.demand_lines():
		if not _is_taken(state, line.node_id, line.food_id):
			pool.append(line)
	pool.sort_custom(func(a, b): return a.difficulty < b.difficulty)
	return pool

## The easiest OFFER_POOL_SIZE candidates of one kind. `want_expand` true
## picks lines at settlements taking no orders yet, false picks further foods
## for settlements already being served.
static func _bucket(state: GameState, pool: Array[Dictionary], want_expand: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in pool:
		var is_expand: bool = state.active_orders.get(line.node_id, {}).is_empty()
		if is_expand != want_expand:
			continue
		out.append(line)
		if out.size() >= OFFER_POOL_SIZE:
			break
	return out

## Picks the single line to open next, alternating between the two kinds of
## growth so the region develops in both directions on its own:
##
##   DEEPEN  another food for a settlement already taking orders -- reuses the
##           trunk road the player has built, but needs a second source to
##           reach the same place.
##   EXPAND  the first order at a settlement not yet served -- new road, new
##           upkeep, new territory.
##
## Strict alternation rather than a coin flip: a run of one kind is the thing
## that makes progression feel arbitrary -- five expansions in a row leaves
## the player with five half-served towns and no reason for any of them.
## Alternating guarantees the network both widens and thickens. When the
## preferred kind has nothing left (early on nothing has a second food worth
## adding, late on everything is already expanded into) it falls through to
## the other, and the preference only flips when a line is actually opened,
## so a starved side never burns its turn.
static func _next_line(state: GameState, map_data: MapData) -> Dictionary:
	var pool := eligible_lines(state, map_data)
	if pool.is_empty():
		return {}

	var wanted := _bucket(state, pool, state.next_prefers_expand)
	if wanted.is_empty():
		wanted = _bucket(state, pool, not state.next_prefers_expand)
	if wanted.is_empty():
		return {}

	var chosen := _take_random(state, wanted)
	state.next_prefers_expand = not state.next_prefers_expand
	return chosen

## Removes and returns one entry, weighted toward the easier end so the ramp
## stays gentle while still reaching occasionally. Weight is the line's
## distance below the pool's hardest, plus one so the hardest is never
## impossible to draw.
static func _take_random(state: GameState, pool: Array[Dictionary]) -> Dictionary:
	var hardest := -INF
	for line in pool:
		hardest = maxf(hardest, line.difficulty)
	var weights: Array[float] = []
	var total := 0.0
	for line in pool:
		var weight: float = (hardest - line.difficulty) + 1.0
		weights.append(weight)
		total += weight

	var roll := _next_randf(state) * total
	var index := 0
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			index = i
			break
	var chosen: Dictionary = pool[index]
	pool.remove_at(index)
	return chosen

## A seeded xorshift, kept here rather than using randf() so a run is
## reproducible: the same seed and the same play replay the same openings,
## which is what lets the dev checks assert an exact sequence and a bug report
## be re-run. GameState.rng_state is the whole of the generator's state.
static func _next_randf(state: GameState) -> float:
	var x: int = state.rng_state
	if x == 0:
		x = 0x2545F491
	x ^= (x << 13) & 0x7FFFFFFF
	x ^= (x >> 7)
	x ^= (x << 17) & 0x7FFFFFFF
	state.rng_state = x & 0x7FFFFFFF
	return float(state.rng_state) / float(0x7FFFFFFF)

static func line_key(node_id: String, food_id: String) -> String:
	return "%s|%s" % [node_id, food_id]

static func line_id(line: Dictionary) -> String:
	return line_key(line.get("node_id", ""), line.get("food_id", ""))

static func _open(state: GameState, line: Dictionary) -> void:
	state.active_orders.get_or_add(line.get("node_id", ""), {})[line.get("food_id", "")] = state.day
