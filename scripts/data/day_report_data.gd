class_name DayReportData
extends RefCounted

## Mirrors the report object returned by fresh-routes-mvp.html's runDay().

var day: int
## Total paid out, bonuses included.
var income := 0.0
## The freshness bonus portion of `income` -- what the green settlement
## bubbles earned over and above an ordinary full delivery.
var bonus_income := 0.0
## What the red bubbles cost: income that short deliveries would have
## earned had the whole order arrived. Not part of `income`.
var withheld_income := 0.0
var route_upkeep := 0.0
var storage_upkeep := 0.0
var hub_upkeep := 0.0
var total_upkeep := 0.0
var spoilage_cost := 0.0
var profit := 0.0
var avg_freshness_overall := 0.0
var waste_pct := 0.0
var avg_happiness := 0.0
var grade := "D"
var grade_score := 0.0
## Array of {settlement:NodeData, fulfill_rate, avg_fresh, waste_rate, sat}
var settlement_scores: Array[Dictionary] = []
var capacity_blocked := 0.0
var is_personal_best := false
