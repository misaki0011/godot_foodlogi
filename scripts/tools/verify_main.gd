extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated and
## that clicking behaves like fresh-routes-mvp.html (single-tile placement,
## tapping a source/settlement shows its info tip instead of building or
## opening a dialog).
## Run via: godot --headless --script res://scripts/tools/verify_main.gd

var _main: Node
var _frame := 0

func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/main/Main.tscn")
	_main = main_scene.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_report()
	return true

func _report() -> void:
	var terrain: GridMap = _main.get_node("TerrainMap")
	var markers: Node3D = _main.get_node("NodeMarkers")
	var map_data: MapData = load("res://data/maps/region_1_map.tres")

	var used_cells := terrain.get_used_cells()
	var expected_cells: int = map_data.grid_size.x * map_data.grid_size.y
	print("Terrain cells populated: %d (expected %d for %dx%d)" % [used_cells.size(), expected_cells, map_data.grid_size.x, map_data.grid_size.y])
	assert(used_cells.size() == expected_cells)
	print("Node markers spawned: %d (expected %d)" % [markers.get_child_count(), map_data.node_placements.size()])
	assert(markers.get_child_count() == map_data.node_placements.size())
	assert(_main.get_node_or_null("GridVisuals") != null)
	var ui_root: Control = _main.get_node("UILayer/GameUI")
	assert(ui_root.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	var camera: Camera3D = _main.get_node("Camera3D")
	var farm: NodeData = _node_by_id(map_data, "farm")
	var village_a: NodeData = _node_by_id(map_data, "villageA")
	var farm_screen := camera.unproject_position(terrain.map_to_local(Vector3i(farm.grid_position.x, 0, farm.grid_position.y)) + Vector3.UP)
	var village_screen := camera.unproject_position(terrain.map_to_local(Vector3i(village_a.grid_position.x, 0, village_a.grid_position.y)) + Vector3.UP)
	assert(_main.call("_screen_to_cell", farm_screen) == farm.grid_position)
	assert(_main.call("_screen_to_cell", village_screen) == village_a.grid_position)

	# Route tool: a single click places exactly one tile, adjacent to a node.
	_main.call("_set_tool", "route")
	var state: GameState = _main.get("_state")
	var starting_balance: float = state.balance
	var build_cell: Vector2i = farm.grid_position + Vector2i(1, 0)
	_main.call("_handle_click", build_cell)
	assert(state.grid.size() == 1, "A single click must place exactly one route tile")
	assert(state.grid[build_cell].kind == "route")
	assert(is_equal_approx(state.balance, starting_balance - GameBalance.ROUTE_BUILD_COST), "Route build cost must be deducted")

	# Storage tool: only buildable on an existing route tile.
	_main.call("_set_tool", "cool")
	_main.call("_handle_click", build_cell)
	assert(state.grid[build_cell].kind == "storage")
	assert(state.grid[build_cell].stype == GameEnums.StorageType.COOL)

	# Bulldoze: removes the tile with no refund.
	_main.call("_set_tool", "remove")
	var balance_before_bulldoze: float = state.balance
	_main.call("_handle_click", build_cell)
	assert(not state.grid.has(build_cell))
	assert(is_equal_approx(state.balance, balance_before_bulldoze), "Bulldoze must not refund")

	# Tapping a settlement (any tool) shows its info tip, not a dialog.
	var tip_panel: PanelContainer = _main.get("_tip_panel")
	assert(not tip_panel.visible)
	_main.call("_handle_click", village_a.grid_position)
	assert(tip_panel.visible, "Tapping a settlement must show the info tip")
	assert(state.grid.size() == 0, "Tapping a settlement must not attempt to build there")

	_check_day_clock(_main.get("_state"))

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)
	print("verify_main checks passed.")

## LOOP-07: the auto-run day clock. Drives the countdown to zero directly
## rather than waiting a real minute, and checks each mode's contract: auto
## runs the day and rolls the calendar over without a modal, pause freezes the
## countdown, and manual mode goes back to the report-then-continue loop.
func _check_day_clock(state: GameState) -> void:
	var summary_panel: PanelContainer = _main.get("_summary_panel")
	var report_overlay: Control = _main.get("_report_overlay")
	assert(state.auto_run, "The day clock must auto-run by default")
	assert(not report_overlay.visible)
	# A couple of frames have already elapsed by now, so the clock has started
	# draining -- it just must not have expired or overrun a full day.
	assert(state.day_time_left > 0.0 and state.day_time_left <= GameBalance.DAY_LENGTH_SEC, "The day clock must start full and drain downward")
	assert(state.day == 1, "The clock must not have run a day within the first frames")

	# Auto-run: the clock reaching zero simulates the day by itself, advances
	# the calendar, restarts the clock, and reports via the summary card only.
	var day_before: int = state.day
	state.day_time_left = 0.01
	_main.call("_tick_day_clock", 0.05)
	assert(state.day == day_before + 1, "An expired auto-run clock must advance the day")
	assert(is_equal_approx(state.day_time_left, GameBalance.DAY_LENGTH_SEC), "The clock must restart after an auto-run day")
	assert(not report_overlay.visible, "An auto-run day must not open the blocking report")
	assert(summary_panel.visible, "An auto-run day must show the non-blocking summary card")
	assert(_main.get("_last_report") != null)

	# Pausing freezes the countdown; resuming resumes it.
	_main.call("_toggle_pause")
	assert(state.clock_paused)
	_main.call("_tick_day_clock", 5.0)
	assert(is_equal_approx(state.day_time_left, GameBalance.DAY_LENGTH_SEC), "A paused clock must not drain")
	_main.call("_toggle_pause")
	assert(not state.clock_paused)
	_main.call("_tick_day_clock", 1.0)
	assert(state.day_time_left < GameBalance.DAY_LENGTH_SEC, "A resumed clock must drain again")

	# Speed multiplies the drain rate.
	state.day_time_left = GameBalance.DAY_LENGTH_SEC
	_main.call("_cycle_speed")
	_main.call("_tick_day_clock", 1.0)
	var drained: float = GameBalance.DAY_LENGTH_SEC - state.day_time_left
	assert(is_equal_approx(drained, GameBalance.DAY_SPEEDS[state.speed_index]), "Clock drain must scale with the selected speed")

	# Manual mode: nothing runs on its own, and a day run opens the report
	# whose Continue button is what advances the calendar.
	_main.call("_toggle_auto_run", false)
	assert(not state.auto_run)
	day_before = state.day
	_main.call("_tick_day_clock", 999.0)
	assert(is_equal_approx(state.day_time_left, GameBalance.DAY_LENGTH_SEC), "A manual clock must not drain")
	assert(state.day == day_before, "Manual mode must never run a day on its own")
	_main.call("_run_day")
	assert(report_overlay.visible, "A manual day run must open the report")
	assert(state.day == day_before, "run_day itself must not advance the day in manual mode")
	_main.call("_close_report")
	assert(not report_overlay.visible)
	assert(state.day == day_before + 1, "Closing the end-of-day report advances the day")

	# Reviewing the last report afterwards must not advance the day again.
	_main.call("_toggle_auto_run", true)
	day_before = state.day
	_main.call("_review_report")
	assert(report_overlay.visible)
	_main.call("_close_report")
	assert(state.day == day_before, "Reviewing a past report must not advance the day")
	print("Day clock (LOOP-07) checks passed.")

func _node_by_id(map_data: MapData, node_id: String) -> NodeData:
	for node in map_data.node_placements:
		if node.node_id == node_id:
			return node
	return null
