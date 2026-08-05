class_name DayReportData
extends RefCounted

## Mirrors the report object returned by fresh-routes-mvp.html's runDay().

var day: int
## Total paid out, bonuses included.
var income := 0.0
## The freshness bonus portion of `income` -- what the green settlement
## bubbles earned over and above the same delivery arriving amber.
var bonus_income := 0.0
var route_upkeep := 0.0
var storage_upkeep := 0.0
var hub_upkeep := 0.0
var total_upkeep := 0.0
var profit := 0.0
var avg_freshness_overall := 0.0
var waste_pct := 0.0
var avg_happiness := 0.0
## How many settlements had at least one open order today, out of how many
## exist on the map (DEV-01). `avg_happiness` averages over the former only
## -- a settlement nobody is allowed to deliver to yet must not be scored as
## an unhappy one -- so the report prints the denominator rather than leaving
## a percentage that quietly changes meaning as the region opens up.
var settlements_taking_orders := 0
var settlements_total := 0
var grade := "D"
var grade_score := 0.0
## Array of {settlement:NodeData, fulfill_rate, avg_fresh, waste_rate, sat}
var settlement_scores: Array[Dictionary] = []
var capacity_blocked := 0.0
var is_personal_best := false
