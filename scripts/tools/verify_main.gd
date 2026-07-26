extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated;
## that route creation is drag-only (v0.5), can only start from a source or
## a built hub and must end at a hub or a settlement (v0.5 item 19), and
## explicitly connects every new tile to what it extends from, never merely
## by adjacency; and that tapping a source/settlement shows its info tip
## instead of building or opening a dialog.
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
	var mid_cell: Vector2i = farm.grid_position + Vector2i(1, 0)
	_main.call("_handle_click", mid_cell)
	assert(state.grid.is_empty(), "A plain tap on empty ground must never place a tile")
	assert(is_equal_approx(state.balance, starting_balance), "A plain tap must never charge the player")

	# A drag that stops short of a hub or a settlement is invalid and builds
	# nothing at all (v0.5 item 19) -- even though the anchor (farm, a source)
	# is perfectly valid, farm -> mid_cell alone doesn't reach a hub/settlement.
	var short_path: Array[Vector2i] = [farm.grid_position, mid_cell]
	_main.set("_drag_path", short_path)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag that doesn't end at a hub or a settlement must be invalid")
	_main.call("_commit_drag")
	assert(state.grid.is_empty(), "An invalid (short) drag must build nothing")
	assert(is_equal_approx(state.balance, starting_balance), "An invalid (short) drag must not charge the player")

	# A full drag from the source all the way to the settlement is valid: it
	# builds every empty cell it crosses as a new route tile AND records an
	# explicit connection for every consecutive pair, including the final
	# tile-to-node link -- mere adjacency is never enough (see GameState.connections).
	var second_cell: Vector2i = farm.grid_position + Vector2i(2, 0)
	var third_cell: Vector2i = Vector2i(village_a.grid_position.x, farm.grid_position.y)
	var full_path: Array[Vector2i] = [farm.grid_position, mid_cell, second_cell, third_cell, village_a.grid_position]
	_main.set("_drag_path", full_path)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag that ends at a settlement must be valid")
	_main.call("_commit_drag")
	assert(state.grid.size() == 3, "A drag from source to settlement must place exactly the 3 empty tiles it crosses")
	assert(state.grid[mid_cell].kind == "route")
	assert(state.has_connection(farm.grid_position, mid_cell), "Dragging from a node must record an explicit connection to the new tile")
	assert(state.has_connection(third_cell, village_a.grid_position), "Dragging onto a settlement must record an explicit connection to it")
	assert(is_equal_approx(state.balance, starting_balance - 3 * GameBalance.ROUTE_BUILD_COST), "Route build cost must be deducted for each new tile")

	# Route drag can only START from a source or a built hub (v0.5 revision) --
	# pressing on a settlement or an already-ESTABLISHED route tile must not
	# begin a drag (mid_cell is part of the established farm->villageA route
	# by this point), even though a drag from a valid anchor can still cross
	# and link to either one.
	assert(_main.call("_established_route_cells").has(mid_cell), "mid_cell must be part of the established farm->villageA route by this point")
	var mid_cell_screen := camera.unproject_position(terrain.map_to_local(Vector3i(mid_cell.x, 0, mid_cell.y)) + Vector3.UP)
	_main.call("_start_press", mid_cell_screen)
	assert(not _main.get("_press_eligible"), "Pressing on an established route tile must not start a route drag")
	_main.call("_start_press", village_screen)
	assert(not _main.get("_press_eligible"), "Pressing on a settlement must not start a route drag")
	_main.call("_start_press", farm_screen)
	assert(_main.get("_press_eligible"), "Pressing on a source must start a route drag")

	# Build a hub on one of the freshly-dragged route tiles (any route tile
	# qualifies, v0.5 item 17), then confirm a press on that hub tile now
	# becomes a valid drag-start anchor too.
	_main.call("_do_build_hub", second_cell)
	assert(state.grid[second_cell].kind == "hub", "Build Hub must work on any existing route tile, not just a flagged fork")
	var hub_cell_screen := camera.unproject_position(terrain.map_to_local(Vector3i(second_cell.x, 0, second_cell.y)) + Vector3.UP)
	_main.call("_start_press", hub_cell_screen)
	assert(_main.get("_press_eligible"), "Pressing on a built hub must start a route drag")

	# A drag starting from the hub still needs to END at a hub or settlement --
	# stopping at a plain route tile is invalid even when the start is valid.
	var hub_short_path: Array[Vector2i] = [second_cell, mid_cell]
	_main.set("_drag_path", hub_short_path)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag from a hub that doesn't end at a hub or a settlement must be invalid")

	# A new route can never cross or reuse an already-built tile in its
	# interior (v0.5 item 20) -- even though mid_cell is a perfectly real,
	# already-built route tile, a fresh drag can't pass through it partway.
	var reuse_path: Array[Vector2i] = [farm.grid_position, mid_cell, village_a.grid_position]
	_main.set("_drag_path", reuse_path)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag that crosses an already-built tile in its interior must be invalid")

	# A drag from the hub through FRESH ground to the settlement is valid --
	# it must not reuse third_cell (already built by the earlier drag).
	var fresh_interior_cell: Vector2i = second_cell + Vector2i(0, 1)
	var hub_to_settlement_path: Array[Vector2i] = [second_cell, fresh_interior_cell, village_a.grid_position]
	_main.set("_drag_path", hub_to_settlement_path)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag from a hub to a settlement over empty ground must be valid")

	# ROUTE-14: a drag may also start or end on a route tile that ISN'T part
	# of an established route yet. Every drag-built route under the OTHER
	# rules is established by construction (it always starts at a source or
	# ends at a settlement/hub), so a genuinely unfinished network -- one
	# touching no source or settlement at all -- is simulated here via direct
	# state manipulation, standing in for what a bulldoze that splits an
	# established network off from its source or settlement would leave
	# behind.
	var unfinished_a: Vector2i = Vector2i(15, 2)
	var unfinished_b: Vector2i = Vector2i(15, 4)
	state.grid[unfinished_a] = {"kind": "route", "level": "dirt"}
	state.grid[unfinished_b] = {"kind": "route", "level": "dirt"}
	var established_now: Dictionary = _main.call("_established_route_cells")
	assert(not established_now.has(unfinished_a) and not established_now.has(unfinished_b), "A route touching no source or settlement must not be established")

	var unfinished_a_screen := camera.unproject_position(terrain.map_to_local(Vector3i(unfinished_a.x, 0, unfinished_a.y)) + Vector3.UP)
	_main.call("_start_press", unfinished_a_screen)
	assert(_main.get("_press_eligible"), "Pressing on an unestablished route tile must start a route drag")

	# Ending on brand-new empty ground is still invalid -- ROUTE-14 only
	# allows ending on a route tile that already exists, not creating a
	# fresh one as the terminus.
	var never_built_cell: Vector2i = Vector2i(16, 2)
	var dead_end_path: Array[Vector2i] = [unfinished_a, never_built_cell]
	_main.set("_drag_path", dead_end_path)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag can't end on brand-new empty ground, even starting from an unestablished route tile")

	# A drag from one unestablished route tile, over fresh ground, to a
	# DIFFERENT unestablished route tile is valid -- "route construction from
	# a route tile to a different route tile if a path is not established".
	var between_unfinished: Vector2i = Vector2i(15, 3)
	var unfinished_to_unfinished_path: Array[Vector2i] = [unfinished_a, between_unfinished, unfinished_b]
	_main.set("_drag_path", unfinished_to_unfinished_path)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag between two unestablished route tiles over empty ground must be valid")
	_main.call("_commit_drag")
	assert(state.grid[between_unfinished].kind == "route", "The fresh interior cell must be built")
	assert(state.has_connection(unfinished_a, between_unfinished) and state.has_connection(between_unfinished, unfinished_b), "Both new connections along an unfinished-to-unfinished drag must be recorded")

	# Storage tool: only buildable on an existing route tile.
	_main.call("_set_tool", "cool")
	_main.call("_handle_click", mid_cell)
	assert(state.grid[mid_cell].kind == "storage")
	assert(state.grid[mid_cell].stype == GameEnums.StorageType.COOL)

	# Bulldoze: removes the tile with no refund.
	_main.call("_set_tool", "remove")
	var balance_before_bulldoze: float = state.balance
	_main.call("_handle_click", mid_cell)
	assert(not state.grid.has(mid_cell))
	assert(is_equal_approx(state.balance, balance_before_bulldoze), "Bulldoze must not refund")

	# Tapping a settlement (any tool) shows its info tip, not a dialog, and
	# never changes the grid.
	var grid_size_before_tip := state.grid.size()
	var tip_panel: PanelContainer = _main.get("_tip_panel")
	assert(not tip_panel.visible)
	_main.call("_handle_click", village_a.grid_position)
	assert(tip_panel.visible, "Tapping a settlement must show the info tip")
	assert(state.grid.size() == grid_size_before_tip, "Tapping a settlement must not attempt to build there")

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
