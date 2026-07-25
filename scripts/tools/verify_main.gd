extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated;
## that route creation is drag-only (v0.5) and explicitly connects the new
## tile to the anchor it was dragged from, never merely by adjacency; and
## that tapping a source/settlement shows its info tip instead of building or
## opening a dialog.
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

	# Route tool: tap-only creation is retired (v0.5) -- a plain click on
	# empty ground must build nothing.
	_main.call("_set_tool", "route")
	var state: GameState = _main.get("_state")
	var starting_balance: float = state.balance
	var build_cell: Vector2i = farm.grid_position + Vector2i(1, 0)
	_main.call("_handle_click", build_cell)
	assert(state.grid.is_empty(), "A plain tap on empty ground must never place a tile")
	assert(is_equal_approx(state.balance, starting_balance), "A plain tap must never charge the player")

	# Dragging from the farm node to an adjacent empty cell builds exactly one
	# new tile AND records an explicit connection back to the node -- mere
	# adjacency is never enough (see GameState.connections).
	var drag_path: Array[Vector2i] = [farm.grid_position, build_cell]
	_main.set("_drag_path", drag_path)
	_main.call("_recompute_drag_validity")
	_main.call("_commit_drag")
	assert(state.grid.size() == 1, "A drag from an existing anchor must place exactly one route tile")
	assert(state.grid[build_cell].kind == "route")
	assert(state.has_connection(farm.grid_position, build_cell), "Dragging from a node must record an explicit connection to the new tile")
	assert(is_equal_approx(state.balance, starting_balance - GameBalance.ROUTE_BUILD_COST), "Route build cost must be deducted")

	# Route drag can only START from a source or a built hub (v0.5 revision) --
	# pressing on a settlement or a plain (non-hub) route tile must not begin
	# a drag, even though a drag from a valid anchor can still cross and link
	# to either one.
	var build_cell_screen := camera.unproject_position(terrain.map_to_local(Vector3i(build_cell.x, 0, build_cell.y)) + Vector3.UP)
	_main.call("_start_press", build_cell_screen)
	assert(not _main.get("_press_eligible"), "Pressing on a plain route tile must not start a route drag")
	_main.call("_start_press", village_screen)
	assert(not _main.get("_press_eligible"), "Pressing on a settlement must not start a route drag")
	_main.call("_start_press", farm_screen)
	assert(_main.get("_press_eligible"), "Pressing on a source must start a route drag")

	# Build a hub on the freshly-dragged route tile, then confirm a press on
	# that hub tile now becomes a valid drag-start anchor too.
	var hub_cell: Vector2i = farm.grid_position + Vector2i(-1, 0)
	var hub_drag_path: Array[Vector2i] = [farm.grid_position, hub_cell]
	_main.set("_drag_path", hub_drag_path)
	_main.call("_recompute_drag_validity")
	_main.call("_commit_drag")
	_main.call("_do_build_hub", hub_cell)
	assert(state.grid[hub_cell].kind == "hub", "Build Hub must work on any existing route tile, not just a flagged fork")
	var hub_cell_screen := camera.unproject_position(terrain.map_to_local(Vector3i(hub_cell.x, 0, hub_cell.y)) + Vector3.UP)
	_main.call("_start_press", hub_cell_screen)
	assert(_main.get("_press_eligible"), "Pressing on a built hub must start a route drag")

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
	_main.call("_handle_click", hub_cell)
	assert(not state.grid.has(hub_cell))

	# Tapping a settlement (any tool) shows its info tip, not a dialog.
	var tip_panel: PanelContainer = _main.get("_tip_panel")
	assert(not tip_panel.visible)
	_main.call("_handle_click", village_a.grid_position)
	assert(tip_panel.visible, "Tapping a settlement must show the info tip")
	assert(state.grid.size() == 0, "Tapping a settlement must not attempt to build there")

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)
	print("verify_main checks passed.")

func _node_by_id(map_data: MapData, node_id: String) -> NodeData:
	for node in map_data.node_placements:
		if node.node_id == node_id:
			return node
	return null
