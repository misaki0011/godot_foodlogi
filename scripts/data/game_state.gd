class_name GameState
extends RefCounted

## Mutable run state, mirroring fresh-routes-mvp.html's top-level `let`s.

var day := 1
var balance := GameBalance.STARTING_FUNDS
var best_score := -INF
var best_grade := ""
var score_history: Array[Dictionary] = [] # {day, score, grade, profit}

## Vector2i -> cell Dictionary:
##   route:   {kind:"route", level:"dirt"/"paved"/"main", needs_hub:bool, hub_capped:bool}
##   storage: {kind:"storage", stype:GameEnums.StorageType}
##   hub:     {kind:"hub", htype:GameEnums.HubType}
var grid: Dictionary = {}

## Last simulated day's results, kept for hover popups (SPEC.md §17 step 13).
var last_flows: Array[Dictionary] = [] # {food, path:Array[Vector2i], delivered, rejected, settlement, source, fresh}
var last_settlement_status: Dictionary = {} # settlement_id -> {food_id: {requested, delivered, rejected, fresh_sum}}
var last_congestion: Array[Dictionary] = [] # {pos:Vector2i, over:bool}
