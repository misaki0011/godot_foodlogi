class_name GameState
extends RefCounted

var day := 1
var funds := 1500.0
var routes: Array[RouteSegmentData] = []
var placed_nodes: Array[NodeData] = []
var positive_profit_streak := 0
var last_report: DayReportData
var won := false

