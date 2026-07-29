class_name OrderBook

## Which of a settlement's demand lines are live, and how the next one is
## chosen (DEV-01).
##
## A settlement's NodeData.demand is its *eventual* appetite -- every food it
## will ever ask for. It does not all switch on at once. Lines open one at a
## time, and which one opens is the player's decision:
##
##     fill an order  ->  two offers appear  ->  the player picks one
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
## the settlement will accept -- exactly the amber speech bubble, and exactly
## the point at which the line starts paying (SimulationEngine.run_day: red
## pays nothing, amber pays the line, green pays it plus a bonus). Freshness
## above that does one job only: it decides how well the player is paid, never
## whether they advance.
##
## `min_freshness` still bites, but implicitly and correctly: run_day rejects
## anything under it before it counts as delivered at all, so a line can never
## be filled on cargo that arrived too spoiled to accept.
##
## Filled is latched. Once the player has proven they can serve a line, that
## is proven for good -- a later bad day must not un-open an order.
##
## Kept free of node references (like DayCycle) so the whole progression can
## be stepped and asserted headlessly in the dev checks.

## How many offers a fill puts on the table. Two is the point of the feature:
## one offer is a notification, three is a menu.
const OFFER_COUNT := 2

## How many of the easiest remaining lines each side of the choice draws
## from. Eligibility is deliberately a RANK, not a distance in difficulty
## points: the map's difficulties are unevenly spaced (Village A's grain sits
## 3.5 points from the next line and 48 from the hardest), so any absolute
## reach is either too tight to offer a pair early or too loose to mean
## anything later. Taking the easiest few always yields a real choice, always
## offers the gentlest options available, and slides upward on its own as the
## player takes them -- no tuning, and no first pick that is a wall.
const OFFER_POOL_SIZE := 3

## Seeds the book with the map's opening order. One fixed line rather than a
## choice: on day 1 nothing is built and the two options would be noise, and a
## known first beat is worth a great deal for teaching.
static func initialize(state: GameState, map_data: MapData) -> void:
	state.active_orders.clear()
	state.filled_lines.clear()
	state.offers.clear()
	state.pending_draws = 0
	if state.run_seed == 0:
		state.run_seed = randi()
	state.rng_state = state.run_seed
	var opening := map_data.opening_line
	if not opening.is_empty():
		_open(state, opening)

## The subset of `settlement.demand` whose orders have opened -- what the
## simulation, the bubbles and the tip all work from.
##
## Iterates the settlement's own demand rather than the open-line record, so
## the authored food order is preserved (bubbles stay in a stable position
## from day to day) and an offer naming a food the settlement never wanted
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
## full is latched as filled, and each line filled for the FIRST time earns
## one draw. Refilling a line the player already proved earns nothing --
## otherwise a working network would spray offers every single day.
##
## Returns how many new lines were filled, so the caller can say so.
static func record_day(state: GameState, nodes: Array[NodeData]) -> int:
	var newly_filled := 0
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
			state.pending_draws += 1
			newly_filled += 1
	return newly_filled

## Puts the next pair of offers on the table if one is owed and none is
## outstanding. At most one pair is ever open: a second fill while the player
## is still deciding queues its draw rather than crowding the map with four
## plaques.
##
## Returns the offers drawn, empty when there was nothing to draw.
static func draw_offers(state: GameState, map_data: MapData) -> Array[Dictionary]:
	if state.pending_draws <= 0 or not state.offers.is_empty():
		return []
	var drawn := _pick_offers(state, map_data)
	if drawn.is_empty():
		# Nothing eligible -- every line is either open or out of reach. Keep
		# the draw owed rather than burning it: reach grows as the player
		# fills harder lines, so this can become drawable later.
		return []
	state.pending_draws -= 1
	state.offers = drawn
	return drawn

## Takes one of the outstanding offers. The other is NOT lost -- it returns to
## the pool and can be offered again. With only twelve lines on the map,
## discarding one per choice would mean a run never sees half its content; the
## choice is about what to do NEXT, not about giving something up. That is
## also what makes accepting safe as a single tap with no confirmation: the
## worst a mis-tap costs is ordering.
static func accept_offer(state: GameState, offer: Dictionary) -> bool:
	var key := offer_key(offer)
	var taken := false
	for candidate in state.offers:
		if offer_key(candidate) == key:
			taken = true
			break
	if not taken:
		return false
	_open(state, offer)
	state.offers.clear()
	return true

## The outstanding offer on `settlement`, or {} if it has none. Used both to
## draw its plaque and to resolve a tap on it.
static func offer_at(state: GameState, node_id: String) -> Dictionary:
	for offer in state.offers:
		if offer.get("node_id", "") == node_id:
			return offer
	return {}

## Whether a line has been opened already (or is currently on offer) -- either
## way it is not a candidate.
static func _is_taken(state: GameState, node_id: String, food_id: String) -> bool:
	if state.active_orders.get(node_id, {}).has(food_id):
		return true
	for offer in state.offers:
		if offer.get("node_id", "") == node_id and offer.get("food_id", "") == food_id:
			return true
	return false

## Every line still up for grabs, easiest first. A line already open, or
## already sitting on the table as the other half of the current choice, is
## not a candidate.
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

## Draws the pair, one DEEPEN and one EXPAND where both are available.
##
##   DEEPEN  another food for a settlement already taking orders -- reuses the
##           trunk road the player has built, but needs a second source to
##           reach the same place.
##   EXPAND  the first order at a settlement not yet served -- new road, new
##           upkeep, new territory.
##
## Two draws from one bucket often produce a hollow choice ("grain here or
## grain there"); one of each is the standing tension of a logistics game, and
## it stays meaningful every time it is asked. When a bucket is empty -- late
## on, once everything is expanded -- the pair falls back to two from the
## other, which is still a real choice between destinations.
static func _pick_offers(state: GameState, map_data: MapData) -> Array[Dictionary]:
	var pool := eligible_lines(state, map_data)
	if pool.is_empty():
		return []

	var picked: Array[Dictionary] = []
	var deepen := _bucket(state, pool, false)
	if not deepen.is_empty():
		picked.append(_take_random(state, deepen))
	var expand := _bucket(state, pool, true)
	if not expand.is_empty():
		picked.append(_take_random(state, expand))

	# One bucket was empty -- early on nothing has a second food worth adding,
	# late on everything is already expanded into. Top up with the easiest
	# candidates left over so the player still gets a choice of destination.
	if picked.size() < OFFER_COUNT:
		var taken := {}
		for line in picked:
			taken[offer_key(line)] = true
		var leftovers: Array[Dictionary] = []
		for line in pool:
			if taken.has(offer_key(line)):
				continue
			leftovers.append(line)
			if leftovers.size() >= OFFER_POOL_SIZE:
				break
		while picked.size() < OFFER_COUNT and not leftovers.is_empty():
			picked.append(_take_random(state, leftovers))
	return picked

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
## reproducible: same seed and same choices replay the same offers, which is
## what lets the dev checks assert an exact sequence and a bug report be
## re-run. GameState.rng_state is the whole of the generator's state.
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

static func offer_key(offer: Dictionary) -> String:
	return line_key(offer.get("node_id", ""), offer.get("food_id", ""))

static func _open(state: GameState, line: Dictionary) -> void:
	state.active_orders.get_or_add(line.get("node_id", ""), {})[line.get("food_id", "")] = state.day
