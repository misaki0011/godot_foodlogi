class_name OrderBook

## Which of a settlement's demand lines are actually live, and when the next
## one opens (DEV-01).
##
## A settlement's NodeData.demand is its *eventual* appetite -- every food it
## will ever ask for. It does not all switch on at once: MapData
## .order_schedule lists those lines in the order the region should learn
## them, and this class decides which have opened by the current day. A line
## that has not opened is simply not simulated: SimulationEngine skips it, so
## it costs nothing, scores nothing and draws no bubble.
##
## Nothing on the map ever appears or disappears -- all five settlements and
## all five sources stand there from day 1, so the player can see the whole
## region and plan against it. What develops is the demand, and the road
## network the player lays down to meet it. A settlement is never "founded"
## or "upgraded" and never changes size: it simply starts placing orders.
## That framing is deliberate. A village visibly mutating into a city reads
## as a city-builder; this is a logistics game, and the thing that should
## visibly grow is the network the player drew.
##
## The problem it solves is concrete. Before this, every settlement demanded
## from day 1: twelve red bubbles on the opening screen (bubble_canvas.gd
## already noted "on day one every settlement is red, and a screen of pulsing
## bubbles is worse than no emphasis at all"), and a happiness score averaged
## over five settlements the player could not possibly have connected yet.
##
## Kept free of node references (like DayCycle) so the whole progression can
## be stepped and asserted headlessly in the dev checks.

## An order only opens once the player is on top of the ones they already
## have: every settlement currently taking orders has to have held READY_SAT
## happiness for READY_STREAK consecutive days.
##
## Day gates alone are the wrong tool in both directions -- they drop a new
## order on a player who is already drowning, and they make a player who has
## solved the map wait out the calendar. `earliest_day` in the schedule is
## therefore only a floor on the pacing; the streak is the brake.
const READY_SAT := 70.0
const READY_STREAK := 2

## Never open two orders on the same rollover, however far behind the
## schedule has fallen -- one new thing per day is the whole point.
const MAX_OPENED_PER_DAY := 1

## How far ahead the countdown plaque appears over the settlement next in
## line (Main._render_settlement_bubbles). An order that arrives unannounced
## is red on arrival, which is the exact day-1 wall this feature exists to
## remove; announced two days out, the player has time to lay the road and
## the order's first day is green.
const PREVIEW_DAYS := 2

## Seeds the book with everything the map opens on the starting day. This is
## the authored opening position rather than a rollover, so it ignores both
## the readiness gate (no day has been simulated yet, so there is nothing to
## prove) and MAX_OPENED_PER_DAY.
static func initialize(state: GameState, map_data: MapData) -> void:
	state.active_orders.clear()
	state.ready_streak = 0
	for order in map_data.order_schedule:
		if _earliest_day(order) <= state.day:
			_open(state, order)

## The subset of `settlement.demand` whose orders have opened -- what the
## simulation, the bubbles and the tip all work from.
##
## Iterates the settlement's own demand rather than the open-line record, so
## the authored food order is preserved (bubbles stay in a stable position
## from day to day) and a schedule entry naming a food the settlement never
## wanted cannot conjure demand out of nothing.
static func active_demand(state: GameState, settlement: NodeData) -> Dictionary:
	var open_lines: Dictionary = state.active_orders.get(settlement.node_id, {})
	var result := {}
	for food_id in settlement.demand:
		if open_lines.has(food_id):
			result[food_id] = settlement.demand[food_id]
	return result

static func has_active_orders(state: GameState, settlement: NodeData) -> bool:
	return not state.active_orders.get(settlement.node_id, {}).is_empty()

## Folds the day just simulated into the readiness streak. A day where every
## settlement taking orders held READY_SAT extends it; anything less resets
## it to zero, so the schedule stalls until the player recovers.
##
## Call once per simulated day, before the calendar rolls over. A report with
## no scored settlements (nobody is taking orders yet) extends the streak
## rather than resetting it -- there is nothing being neglected.
static func record_day(state: GameState, report: DayReportData) -> void:
	for score in report.settlement_scores:
		if score.sat < READY_SAT:
			state.ready_streak = 0
			return
	state.ready_streak += 1

## Opens whatever the new day allows, and returns the orders opened so the
## caller can announce them. Call once per day rollover, AFTER GameState.day
## has advanced.
static func open_due_orders(state: GameState, map_data: MapData) -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	if state.ready_streak < READY_STREAK:
		return opened
	for order in map_data.order_schedule:
		if opened.size() >= MAX_OPENED_PER_DAY:
			break
		if _is_open(state, order):
			continue
		# The schedule is sorted by earliest_day (MapData.validate enforces
		# it), so the first entry that isn't due yet ends the scan -- nothing
		# behind it can be due either, and skipping past it would let a later
		# order jump the queue.
		if _earliest_day(order) > state.day:
			break
		_open(state, order)
		opened.append(order)
	if not opened.is_empty():
		# Earning an order spends the streak: the player has to hold the
		# now-larger network steady for another READY_STREAK days before the
		# next one lands. Without this a good run would unlock the whole
		# region in a week, one order per day, which is the wall again.
		state.ready_streak = 0
	return opened

## The next line in the schedule that has not opened yet, or {} once the
## region has run out of orders.
static func next_pending(state: GameState, map_data: MapData) -> Dictionary:
	for order in map_data.order_schedule:
		if not _is_open(state, order):
			return order
	return {}

## The day `order` is currently on track to open, taking both gates into
## account. This slides later while the player is behind and settles as they
## recover -- which is what the plaque should show, rather than a fixed date
## the game may not keep.
##
## The soonest possible rollover is the one into tomorrow (an order opens at
## a rollover, never mid-day), hence the floor of 1 even when the streak is
## already long enough.
static func projected_day(state: GameState, order: Dictionary) -> int:
	var days_to_ready: int = maxi(1, READY_STREAK - state.ready_streak)
	return maxi(_earliest_day(order), state.day + days_to_ready)

## The order to show a countdown plaque for right now: the next pending one,
## but only once it is within PREVIEW_DAYS of opening. Everything further out
## stays off the map entirely -- a grey "later" plaque over all five
## settlements from day 1 would just be the twelve-bubble wall in another
## colour.
static func preview_order(state: GameState, map_data: MapData) -> Dictionary:
	var order := next_pending(state, map_data)
	if order.is_empty():
		return {}
	if projected_day(state, order) - state.day > PREVIEW_DAYS:
		return {}
	return order

static func _earliest_day(order: Dictionary) -> int:
	return int(order.get("earliest_day", 1))

static func _is_open(state: GameState, order: Dictionary) -> bool:
	var lines: Dictionary = state.active_orders.get(order.get("node_id", ""), {})
	return lines.has(order.get("food_id", ""))

static func _open(state: GameState, order: Dictionary) -> void:
	state.active_orders.get_or_add(order.get("node_id", ""), {})[order.get("food_id", "")] = state.day
