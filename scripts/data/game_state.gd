class_name GameState
extends RefCounted

## Mutable run state, mirroring fresh-routes-mvp.html's top-level `let`s.

var day := 1
var balance := GameBalance.STARTING_FUNDS
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
