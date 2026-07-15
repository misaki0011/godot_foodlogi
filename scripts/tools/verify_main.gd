extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated and
## that clicking behaves like fresh-routes-mvp.html (single-tile placement,
## settlement click opens the popup).
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

	# Clicking a settlement always opens its delivery popup, regardless of tool.
	var settlement_overlay: Control = _main.get("_settlement_overlay")
	assert(not settlement_overlay.visible)
	_main.call("_handle_click", village_a.grid_position)
	assert(settlement_overlay.visible, "Clicking a settlement must open its delivery popup")

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
