class_name GameState
extends RefCounted

## Mutable run state, mirroring fresh-routes-mvp.html's top-level `let`s.

var day := 1
var balance := GameBalance.STARTING_FUNDS

## ---------- day clock (LOOP-07) ----------
## `auto_run` on (the default) means the day advances by itself: the clock
## counts `day_time_left` down from GameBalance.DAY_LENGTH_SEC at
## DAY_SPEEDS[speed_index], simulates the day at zero, and restarts. Off, the
## clock is frozen and the day only runs when the player asks for it, which
## is the pre-v0.5 manual loop. `clock_paused` is the player's temporary
## hold on an otherwise auto-running clock.
var auto_run := true
var clock_paused := false
var speed_index := 0
var day_time_left := GameBalance.DAY_LENGTH_SEC
var best_score := -INF
var best_grade := ""
var score_history: Array[Dictionary] = [] # {day, score, grade, profit}

## Vector2i -> cell Dictionary:
##   route:   {kind:"route", level:"dirt"/"paved"/"main", needs_hub:bool, hub_capped:bool,
##             facing:String (optional, player-chosen shape when connections are ambiguous --
##             see SimulationEngine.route_shape())}
##   storage: {kind:"storage", stype:GameEnums.StorageType}
##   hub:     {kind:"hub", htype:GameEnums.HubType}
var grid: Dictionary = {}

## Last simulated day's results, kept for hover popups (SPEC.md §17 step 13).
var last_flows: Array[Dictionary] = [] # {food, path:Array[Vector2i], delivered, rejected, settlement, source, fresh}
var last_settlement_status: Dictionary = {} # settlement_id -> {food_id: {requested, delivered, rejected, fresh_sum}}
var last_source_status: Dictionary = {} # source_id -> {food_id: {produced, used}}
var last_congestion: Array[Dictionary] = [] # {pos:Vector2i, over:bool}
