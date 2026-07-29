class_name GameState
extends RefCounted

## Mutable run state, mirroring fresh-routes-mvp.html's top-level `let`s.

var day := 1
var balance := GameBalance.STARTING_FUNDS

## ---------- day clock (LOOP-07) ----------
## `auto_run` on (the default) means the day advances by itself: the clock
## counts `day_time_left` down from GameBalance.DAY_LENGTH_SEC at
## DAY_SPEEDS[speed_index], simulates the day at zero, and restarts. Off, the
## clock is frozen and a day only runs when the player asks for it, which is
## the older manual loop. `clock_paused` is the player's temporary hold on an
## otherwise auto-running clock.
var auto_run := true
var clock_paused := false
var speed_index := 0
var day_time_left := GameBalance.DAY_LENGTH_SEC

## ---------- order book (DEV-01) ----------
## Which demand lines have opened so far: node_id -> {food_id: day_opened}.
## A settlement's NodeData.demand is what it will EVENTUALLY want; only the
## lines recorded here are simulated, scored or drawn. Seeded with the map's
## opening line and extended one at a time by the player accepting an offer,
## so the region's demand develops instead of landing whole on day 1.
var active_orders: Dictionary = {}

## Lines the player has ever delivered in full: "node_id|food_id" -> true.
## Latched -- proving a line once proves it for good, so a later bad day can
## never un-open an order. Filling a line for the first time is what earns a
## draw. See OrderBook.
var filled_lines: Dictionary = {}

## The offers currently on the table (0 or OrderBook.OFFER_COUNT of them), as
## {node_id, food_id, difficulty}. The player takes one by tapping its
## settlement; the other goes back in the pool.
var offers: Array[Dictionary] = []

## Draws owed but not yet dealt. Filling a second line while a pair is still
## outstanding queues the draw rather than putting four plaques on the map.
var pending_draws := 0

## The run's offer sequence. Same seed plus the same choices replays the same
## offers, which is what keeps the game reproducible now that nothing else in
## the simulation is random. 0 means "not seeded yet" -- OrderBook.initialize
## rolls a real one. Set it before initialize() to pin a run (the dev checks
## do exactly that).
var run_seed := 0
var rng_state := 0

var best_score := -INF
var best_grade := ""
var score_history: Array[Dictionary] = [] # {day, score, grade, profit}

## Vector2i -> cell Dictionary:
##   route:   {kind:"route", level:"dirt"/"paved"/"main"} (each level renders
##            as one symmetric mesh, the same regardless of shape or facing --
##            see Main._add_route_block and tools/asset_gen/generate_blocks.py)
##   storage: {kind:"storage", stype:GameEnums.StorageType}
##   hub:     {kind:"hub", htype:GameEnums.HubType}
var grid: Dictionary = {}

## Last simulated day's results, kept for hover popups (SPEC.md §17 step 13).
var last_flows: Array[Dictionary] = [] # {food, path:Array[Vector2i], delivered, rejected, settlement, source, fresh}
var last_settlement_status: Dictionary = {} # settlement_id -> {food_id: {requested, delivered, rejected, fresh_sum}}
var last_source_status: Dictionary = {} # source_id -> {food_id: {produced, used}}
var last_congestion: Array[Dictionary] = [] # {pos:Vector2i, over:bool}

## Explicit player-drawn links between orthogonally-adjacent cells (built
## tile <-> built tile, or built tile <-> node): Vector2i -> Dictionary[Vector2i,
## bool], a symmetric adjacency-set. Physical adjacency alone never implies
## connectivity anywhere in SimulationEngine (pathfinding, hub forks, route
## shape, upkeep discount) -- only an edge recorded here does. Added v0.5:
## previously any two touching tiles were automatically part of the same
## network, which forced side-by-side but otherwise-independent routes to
## merge; now the player must drag across a boundary to link it (see
## Main._commit_drag).
##
## NOTE: the accessor methods below are named add_connection/has_connection/
## remove_connections, NOT connect/is_connected/disconnect -- Object (which
## RefCounted extends) already defines connect()/is_connected()/disconnect()
## for signal wiring, and overriding them here with an incompatible signature
## makes GDScript fail to parse ANY script that calls them ("Could not
## resolve external class member"), breaking the whole game at load time.
var connections: Dictionary = {}

func add_connection(a: Vector2i, b: Vector2i) -> void:
	connections.get_or_add(a, {})[b] = true
	connections.get_or_add(b, {})[a] = true

func has_connection(a: Vector2i, b: Vector2i) -> bool:
	return connections.has(a) and connections[a].has(b)

## Drops the single edge between `a` and `b` from both sides, leaving every
## other edge on either cell intact. Used when a tile survives a bulldoze but
## loses one road through it -- clearing a bridge takes down its deck links
## while the road underneath keeps running (Main._clear_cell).
func remove_connection(a: Vector2i, b: Vector2i) -> void:
	if connections.has(a):
		connections[a].erase(b)
	if connections.has(b):
		connections[b].erase(a)

## Removes every edge touching `pos` (both its own entry and the reverse
## entry on each neighbor it was linked to) -- call when a tile is bulldozed
## so no dangling edge points at a cell that no longer exists.
func remove_connections(pos: Vector2i) -> void:
	if not connections.has(pos):
		return
	for other in connections[pos].keys():
		if connections.has(other):
			connections[other].erase(pos)
	connections.erase(pos)
