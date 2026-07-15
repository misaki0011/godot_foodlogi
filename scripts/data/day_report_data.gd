class_name DayReportData
extends RefCounted

## Mirrors the report object returned by fresh-routes-mvp.html's runDay().

var day: int
var income := 0.0
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
