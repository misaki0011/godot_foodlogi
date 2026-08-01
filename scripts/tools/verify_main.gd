extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated;
## that route creation is drag-only (v0.5), can only start from a source or
## a built hub and must end at a hub or a settlement (v0.5 item 19), and
## explicitly connects every new tile to what it extends from, never merely
## by adjacency; and that tapping a source/settlement focuses it instead of
## building or opening any panel.
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
	# A SOURCE gets one marker per occupied cell (DEV-02) -- its art is a single
	# crate, so a 2x1 source is two crates and the footprint reads off them. A
	# SETTLEMENT gets exactly one, whatever its size: its model is authored at
	# its footprint's real extent and covers those cells itself.
	var expected_markers := 0
	for node in map_data.node_placements:
		expected_markers += 1 if node.node_type == GameEnums.NodeType.SETTLEMENT else node.cells().size()
	print("Node markers spawned: %d (expected %d for %d nodes)" % [
		markers.get_child_count(), expected_markers, map_data.node_placements.size(),
	])
	assert(markers.get_child_count() == expected_markers)
	_test_settlement_markers(map_data, markers, terrain)
	assert(_main.get_node_or_null("GridVisuals") != null)
	var ui_root: Control = _main.get_node("UILayer/GameUI")
	assert(ui_root.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	_test_multi_tile_settlement_draws_one_stack(map_data)
	_test_glyph_column_collapses_and_expands(map_data)
	_test_flourishes_fire_once(map_data)
	_test_new_orders_arrive_late(map_data)
	_test_tile_placement_pops_once(map_data)
	_test_columns_never_overlap(map_data)

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
	# Sources stand on 2x1 (DEV-03), so a route leaves from the far end of the
	# building -- grid_position + (1,0) is the Farm's own second tile.
	var farm_exit: Vector2i = farm.far_cell()
	var mid_cell: Vector2i = farm_exit + Vector2i(1, 0)
	_main.call("_handle_click", mid_cell)
	assert(state.grid.is_empty(), "A plain tap on empty ground must never place a tile")
	assert(is_equal_approx(state.balance, starting_balance), "A plain tap must never charge the player")

	# A drag that stops short of a hub or a settlement is invalid and builds
	# nothing at all (v0.5 item 19) -- even though the anchor (farm, a source)
	# is perfectly valid, farm -> mid_cell alone doesn't reach a hub/settlement.
	var short_path: Array[Vector2i] = [farm_exit, mid_cell]
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
	var second_cell: Vector2i = farm_exit + Vector2i(2, 0)
	var third_cell: Vector2i = Vector2i(village_a.grid_position.x, farm_exit.y)
	var full_path: Array[Vector2i] = [farm_exit, mid_cell, second_cell, third_cell, village_a.grid_position]
	_main.set("_drag_path", full_path)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag that ends at a settlement must be valid")
	_main.call("_commit_drag")
	assert(state.grid.size() == 3, "A drag from source to settlement must place exactly the 3 empty tiles it crosses")
	assert(state.grid[mid_cell].kind == "route")
	assert(state.has_connection(farm_exit, mid_cell), "Dragging from a node must record an explicit connection to the new tile")
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
	var reuse_path: Array[Vector2i] = [farm_exit, mid_cell, village_a.grid_position]
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

	# A drag from an unestablished route tile directly to a SETTLEMENT is
	# valid too, not just to another unestablished route tile -- ROUTE-14's
	# relaxed start rule and ROUTE-11's settlement end rule combine freely.
	var village_c: NodeData = _node_by_id(map_data, "villageC")
	var route_to_settlement_b: Vector2i = Vector2i(14, 4)
	var route_to_settlement_c: Vector2i = Vector2i(13, 4)
	var route_to_settlement_path: Array[Vector2i] = [unfinished_b, route_to_settlement_b, route_to_settlement_c, village_c.grid_position]
	_main.set("_drag_path", route_to_settlement_path)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag from an unestablished route tile directly to a settlement must be valid")
	_main.call("_commit_drag")
	assert(state.has_connection(route_to_settlement_c, village_c.grid_position), "Dragging from an unestablished route tile onto a settlement must record the connection")

	_check_route_source_attribution(state, mid_cell, unfinished_a, farm)

	_check_tool_sweeps(state, camera, terrain, route_to_settlement_b, route_to_settlement_c)

	_check_bridge_tool(state, camera, terrain)

	# Storage tool: only buildable on an existing route tile, and it remembers
	# the road it covered so it can be drawn over it and hand it back.
	_main.call("_set_tool", "cool")
	_main.call("_handle_click", mid_cell)
	assert(state.grid[mid_cell].kind == "storage")
	assert(state.grid[mid_cell].stype == GameEnums.StorageType.COOL)
	assert(state.grid[mid_cell].get("level", "") == "dirt", "Storage must remember the level of the road it was built on")
	_check_structure_renders_on_its_road(terrain, mid_cell)

	# Bulldoze takes the BUILDING off first, leaving the road it stood on -- a
	# storage tile follows the same rule as a hub or a bridge. Clearing the road
	# itself is a second click. Neither refunds.
	_main.call("_set_tool", "remove")
	var balance_before_bulldoze: float = state.balance
	_main.call("_handle_click", mid_cell)
	assert(state.grid.has(mid_cell), "Bulldozing storage must leave the road it was built on behind")
	assert(state.grid[mid_cell].kind == "route" and state.grid[mid_cell].level == "dirt", "A bulldozed storage tile must hand its road back at the level it was")
	_main.call("_handle_click", mid_cell)
	assert(not state.grid.has(mid_cell), "A second bulldoze must clear the bare road tile")
	assert(is_equal_approx(state.balance, balance_before_bulldoze), "Bulldoze must not refund")

	# Tapping a node (any tool) never builds there, and no longer opens a text
	# panel of any kind: the brown detail tip is retired for sources, routes,
	# storage, hubs and the river alike (v0.6 item 55). What a tap does now is
	# focus the node, which is what swaps a settlement's glyph column for its
	# full rows.
	var grid_size_before_tip := state.grid.size()
	assert(_main.get("_tip_panel") == null, "The detail tip panel must be gone, not merely hidden")
	_main.call("_handle_click", village_a.grid_position)
	assert(_main.get("_focused_node_id") == village_a.node_id, "Tapping a settlement must focus it, expanding its rows")
	assert(state.grid.size() == grid_size_before_tip, "Tapping a settlement must not attempt to build there")

	# A source is focusable the same way, but never expands -- it has no
	# delivery to detail. Its drawn/produced figure lives on its chip.
	_main.call("_handle_click", farm.grid_position)
	assert(_main.get("_focused_node_id") == farm.node_id, "Tapping a source must focus it")
	_main.call("_handle_click", Vector2i(0, 0))
	assert(_main.get("_focused_node_id") == "", "Tapping empty ground must clear the focus")

	_check_day_clock(state)
	_check_day_cycle(state)

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)
	_test_ground_vegetation(map_data, terrain, state)
	# Last, because it spends the treasury and permanently doubles the
	# Garden: everything above still expects the map it started with.
	_test_source_upgrade()
	print("verify_main checks passed.")

## ROUTE-16: every route tile is attributed to the source(s) its network is
## explicitly connected to, which is what Main tints the tile by. A road
## dragged from the farm reports the farm; one connected to no source at all
## reports nothing and stays untinted.
func _check_route_source_attribution(state: GameState, farm_road: Vector2i, sourceless_road: Vector2i, farm: NodeData) -> void:
	# Keyed by graph vertex since bridges landed (a crossing's deck and the road
	# under it are attributed separately); plain road only ever has a ground lane.
	var by_vertex: Dictionary = _main.call("_established_sources_by_vertex")
	var farm_vertex := SimulationEngine.vertex(farm_road, SimulationEngine.LANE_GROUND)
	var sourceless_vertex := SimulationEngine.vertex(sourceless_road, SimulationEngine.LANE_GROUND)
	assert(by_vertex.get(farm_vertex, []) == [farm.node_id], "A road delivering from the farm must be attributed to the farm")
	assert(by_vertex.get(sourceless_vertex, []).is_empty(), "A road on no source's delivery path must be attributed to none")
	# The overlay colour follows what the source produces, not the shared
	# source-marker colour -- that's the whole point of colouring by source.
	var grain_color: Color = GameBalance.food_types()["grain"].color
	assert(_main.call("_source_food_color", farm.node_id).is_equal_approx(grain_color), "The farm's line colour must be its grain colour")
	# Lanes: one source runs down the middle of the road, two straddle it.
	assert(is_equal_approx(_main.call("_lane_offset", 0, 1), 0.0), "A lone source's line must run down the middle")
	var two_a: float = _main.call("_lane_offset", 0, 2)
	var two_b: float = _main.call("_lane_offset", 1, 2)
	assert(two_a < 0.0 and two_b > 0.0 and is_equal_approx(two_a, -two_b), "Two sources sharing a road must straddle its centre evenly")
	assert(_main.call("_shared_source_ids", ["farm", "dairy"], ["dairy", "harbor"]) == ["dairy"], "A shared stretch carries exactly the sources both tiles have")
	print("Route source attribution (ROUTE-16) checks passed.")

## ROUTE-17: the Bridge tool, end to end through the real UI. A bridge is a
## PLACED STRUCTURE -- the player builds a road, clicks the Bridge tool on a
## straight run of it, and only then may a second route be dragged straight
## over the deck. Works in an empty corner of the map (column 17, rows 9-13,
## clear of every node placement) so nothing here disturbs the earlier checks.
func _check_bridge_tool(state: GameState, camera: Camera3D, terrain: GridMap) -> void:
	var road: Array[Vector2i] = [Vector2i(17, 9), Vector2i(17, 10), Vector2i(17, 11), Vector2i(17, 12), Vector2i(17, 13)]
	for cell in road:
		assert(not state.grid.has(cell), "The bridge checks need a clear stretch of map to work in")
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	for i in range(1, road.size()):
		state.add_connection(road[i - 1], road[i])
	var bridge: Vector2i = road[2]
	# Two tiles are paid up past Dirt, so the bulldoze checks below can prove a
	# cleared structure hands its road back at the level it actually was.
	state.grid[bridge].level = "paved"
	state.grid[road[3]].level = "main"

	_main.call("_set_tool", "bridgeBuild")
	# A dead end isn't a straight run: there's no "across" to span.
	var balance_before: float = state.balance
	_main.call("_handle_click", road[4])
	assert(not SimulationEngine.is_bridge(state, road[4]), "A bridge must be refused on a tile that isn't a straight through-run of road")
	assert(is_equal_approx(state.balance, balance_before), "A refused bridge must not charge the player")

	# The mid-run tile does qualify, and the deck spans ACROSS the road: the
	# road here runs north-south, so the deck runs east-west.
	_main.call("_handle_click", bridge)
	assert(SimulationEngine.is_bridge(state, bridge), "The Bridge tool must convert a straight run of route tile into a crossing")
	assert(SimulationEngine.bridge_axis(state, bridge) == Vector2i(1, 0), "A deck must run across the road it crosses, not along it")
	assert(is_equal_approx(state.balance, balance_before - GameBalance.BRIDGE_BUILD_COST), "Building a bridge must cost BRIDGE_BUILD_COST")
	assert(state.grid[bridge].kind == "route", "A bridge tile stays a route tile -- the road underneath keeps running")

	# A bridge tile carries two roads already: nothing else can go on it, and
	# no drag may anchor to it.
	for tool in ["hubBuild", "cool"]:
		_main.call("_set_tool", tool)
		_main.call("_handle_click", bridge)
		assert(state.grid[bridge].kind == "route", "Nothing may be built on top of a bridge tile (tool: %s)" % tool)
	var bridge_screen := camera.unproject_position(terrain.map_to_local(Vector3i(bridge.x, 0, bridge.y)) + Vector3.UP)
	_main.call("_set_tool", "route")
	_main.call("_start_press", bridge_screen)
	assert(not _main.get("_press_eligible"), "Pressing on a bridge must not start a route drag -- a crossing is passed over, never anchored to")

	# Now the crossing route itself: two unfinished stubs either side, dragged
	# straight over the deck. This is the ONE case where a drag may run over a
	# cell that already exists.
	var west := Vector2i(15, 11)
	var east := Vector2i(19, 11)
	for cell in [west, east]:
		state.grid[cell] = {"kind": "route", "level": "dirt"}
	var across: Array[Vector2i] = [west, Vector2i(16, 11), bridge, Vector2i(18, 11), east]
	_main.set("_drag_path", across)
	_main.call("_recompute_drag_validity")
	assert(_main.get("_drag_valid"), "A drag straight over a bridge deck must be valid: %s" % _main.get("_drag_invalid_reason"))
	var balance_before_cross: float = state.balance
	_main.call("_commit_drag")
	assert(state.grid.has(Vector2i(16, 11)) and state.grid.has(Vector2i(18, 11)), "The crossing drag must build the fresh ground either side of the deck")
	assert(is_equal_approx(state.balance, balance_before_cross - 2 * GameBalance.ROUTE_BUILD_COST), "A crossing drag pays only for the new tiles, never again for the bridge it crosses")

	# The whole point: two routes through one cell, still two networks.
	var comp_of := SimulationEngine.road_components(state)
	assert(comp_of[SimulationEngine.vertex(road[1], SimulationEngine.LANE_GROUND)] != comp_of[SimulationEngine.vertex(Vector2i(16, 11), SimulationEngine.LANE_GROUND)],
		"Two routes crossing at a bridge must stay separate connected networks")
	assert(comp_of[SimulationEngine.vertex(bridge, SimulationEngine.LANE_GROUND)] == comp_of[SimulationEngine.vertex(road[1], SimulationEngine.LANE_GROUND)],
		"A bridge's ground lane belongs to the road running underneath it")
	assert(comp_of[SimulationEngine.vertex(bridge, SimulationEngine.LANE_DECK)] == comp_of[SimulationEngine.vertex(Vector2i(16, 11), SimulationEngine.LANE_GROUND)],
		"A bridge's deck belongs to the route crossing over it")

	# Straight over, or not at all: no turning on the deck, no stopping on it.
	var turns: Array[Vector2i] = [west, Vector2i(16, 11), bridge, road[3]]
	_main.set("_drag_path", turns)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag must not turn a corner on a bridge deck")
	var stops: Array[Vector2i] = [west, Vector2i(16, 11), bridge]
	_main.set("_drag_path", stops)
	_main.call("_recompute_drag_validity")
	assert(not _main.get("_drag_valid"), "A drag must not stop on a bridge deck")

	# The per-network cap: a second bridge is fine, a third is refused.
	_main.call("_set_tool", "bridgeBuild")
	_main.call("_handle_click", road[1])
	assert(SimulationEngine.is_bridge(state, road[1]), "A road network under its bridge cap must accept another bridge")
	var balance_at_cap: float = state.balance
	_main.call("_handle_click", road[3])
	assert(not SimulationEngine.is_bridge(state, road[3]), "A road network at BRIDGE_CAP_PER_NETWORK (%d) must refuse another bridge" % GameBalance.BRIDGE_CAP_PER_NETWORK)
	assert(is_equal_approx(state.balance, balance_at_cap), "A bridge refused by the cap must not charge the player")

	# Bulldozing a bridge takes the STRUCTURE away, not the road it was built
	# on: the tile survives as a route tile AT ITS OWN LEVEL, still carrying the
	# road that ran underneath, while the route that crossed over is cut.
	# Merging the two instead would silently join the networks the crossing was
	# keeping apart, and resetting to dirt would bin paving nobody asked to lose.
	_main.call("_set_tool", "remove")
	var balance_before_clear: float = state.balance
	_main.call("_handle_click", bridge)
	assert(state.grid.has(bridge), "Bulldozing a bridge must leave the road it was built on behind")
	assert(not SimulationEngine.is_bridge(state, bridge), "Bulldozing a bridge must remove the deck")
	assert(state.grid[bridge].kind == "route", "A bulldozed bridge must leave a route tile")
	assert(state.grid[bridge].level == "paved", "A bulldozed bridge must hand its road back at the level it was, not reset it to dirt")
	assert(state.has_connection(bridge, road[1]) and state.has_connection(bridge, road[3]), "The road under a bulldozed bridge must stay connected")
	assert(not state.has_connection(bridge, Vector2i(16, 11)) and not state.has_connection(bridge, Vector2i(18, 11)),
		"Bulldozing a bridge must cut the route that crossed over it, not merge it into the road below")
	var comp_after := SimulationEngine.road_components(state)
	assert(comp_after[SimulationEngine.vertex(bridge, SimulationEngine.LANE_GROUND)] != comp_after[SimulationEngine.vertex(Vector2i(16, 11), SimulationEngine.LANE_GROUND)],
		"The two roads must stay separate networks after the bridge between them is cleared")
	assert(is_equal_approx(state.balance, balance_before_clear), "Bulldoze must not refund")

	# Same rule for a hub: the structure goes, the road stays at its own level.
	# A hub cell replaces the route cell outright, so the level has to survive
	# on the hub cell itself for this to be possible at all.
	_main.call("_set_tool", "hubBuild")
	_main.call("_handle_click", road[3])
	assert(state.grid[road[3]].kind == "hub", "The hub checks need a hub on the road first")
	assert(state.grid[road[3]].get("level", "") == "main", "A hub must remember the level of the road it was built on")
	_check_structure_renders_on_its_road(terrain, road[3])
	_main.call("_set_tool", "remove")
	_main.call("_handle_click", road[3])
	assert(state.grid.has(road[3]), "Bulldozing a hub must leave the road it was built on behind")
	assert(state.grid[road[3]].kind == "route", "A bulldozed hub must leave a route tile")
	assert(state.grid[road[3]].level == "main", "A bulldozed hub must hand its road back at the level it was, not reset it to dirt")
	assert(state.has_connection(road[3], road[2]) and state.has_connection(road[3], road[4]), "The road under a bulldozed hub must stay connected")
	assert(not SimulationEngine.network_at_hub_cap(state, road[3]), "Bulldozing a hub must free its slot in the per-network cap")

	# Clear up so the later tool checks see the map they expect.
	for cell in state.grid.keys():
		if cell.x >= 15 and cell.y >= 9:
			state.grid.erase(cell)
			state.remove_connections(cell)
	_main.call("_set_tool", "route")
	print("Bridge tool (ROUTE-17) checks passed.")

## A hub or storage building renders ON a road, not instead of one: the road
## block it was built on is drawn underneath and the marker stands on top of it,
## rather than the marker replacing the road and leaving a gap in the network.
func _check_structure_renders_on_its_road(terrain: GridMap, cell: Vector2i) -> void:
	var grid_visuals: Node3D = _main.get_node("GridVisuals")
	var world_pos: Vector3 = terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, 1.0, 0)
	var marker: Node3D = null
	var road: Node3D = null
	for child in grid_visuals.get_children():
		if absf(child.position.x - world_pos.x) > 0.01 or absf(child.position.z - world_pos.z) > 0.01:
			continue
		if child is NodeMarker:
			marker = child
		# GridVisuals also carries the established-route overlay, which floats
		# well above the tile at the same x/z -- the road block is whatever sits
		# lowest, right on the tile surface.
		elif road == null or child.position.y < road.position.y:
			road = child
	assert(road != null, "A built-on tile must still draw the road underneath it")
	assert(marker != null, "A built-on tile must draw its building marker")
	# Every road piece is drawn centred on its own height, so the block's offset
	# above the tile gives back the height the marker has to clear. Marker scenes
	# are authored with their origin at their base (hub_marker.tscn).
	var road_height := 2.0 * (road.position.y - world_pos.y)
	assert(road_height > 0.0, "The road block under a building must have real height")
	assert(is_equal_approx(marker.position.y, world_pos.y + road_height), "A building marker must stand on top of its road block, not sink into it")

## ROUTE-15: bulldoze and upgrade also work as a drag, applying to every tile
## the sweep crosses. Drives real press/drag/release gestures over two
## adjacent route tiles: upgrade sweeps both a level, bulldoze sweeps both
## away (with their connections). A single tap must still do the one-tile
## action it always did.
func _check_tool_sweeps(state: GameState, camera: Camera3D, terrain: GridMap, cell_a: Vector2i, cell_b: Vector2i) -> void:
	assert(state.grid.has(cell_a) and state.grid.has(cell_b), "The sweep checks need two built route tiles")
	assert(state.grid[cell_a].level == "dirt" and state.grid[cell_b].level == "dirt")
	var a_screen := _cell_screen(camera, terrain, cell_a)
	var b_screen := _cell_screen(camera, terrain, cell_b)
	var upgrade_cost: float = GameBalance.ROUTE_LEVELS.dirt.upgrade_cost

	# Upgrade sweep: one drag, both tiles, both charged.
	_main.call("_set_tool", "upgrade")
	var balance_before: float = state.balance
	_main.call("_start_press", a_screen)
	assert(_main.get("_drag_active"), "A sweep tool must start dragging on press, with no hold delay")
	assert(_main.get("_drag_kind") == "sweep")
	_main.call("_extend_drag_path", cell_b)
	_main.call("_end_press", b_screen)
	assert(state.grid[cell_a].level == "paved" and state.grid[cell_b].level == "paved", "An upgrade sweep must upgrade every tile it crossed")
	assert(is_equal_approx(state.balance, balance_before - upgrade_cost * 2.0), "Each swept upgrade must be charged")

	# An upgrade sweep the treasury can't cover applies to nothing at all.
	var poor_balance: float = GameBalance.ROUTE_LEVELS.paved.upgrade_cost * 1.5
	state.balance = poor_balance
	_main.call("_start_press", a_screen)
	_main.call("_extend_drag_path", cell_b)
	assert(not _main.get("_drag_valid"), "A sweep that outruns the treasury must be invalid")
	_main.call("_end_press", b_screen)
	assert(state.grid[cell_a].level == "paved" and state.grid[cell_b].level == "paved", "An unaffordable sweep must upgrade nothing")
	assert(is_equal_approx(state.balance, poor_balance), "An unaffordable sweep must charge nothing")
	state.balance = balance_before

	# A single tap with a sweep tool still does the one-tile action.
	_main.call("_start_press", a_screen)
	_main.call("_end_press", a_screen)
	assert(state.grid[cell_a].level == "main", "A tap with the upgrade tool must still upgrade that one tile")
	assert(state.grid[cell_b].level == "paved", "A tap must not touch any other tile")

	# Bulldoze sweep: one drag clears every tile it crossed, connections and all.
	_main.call("_set_tool", "remove")
	assert(state.has_connection(cell_a, cell_b), "The two tiles must be connected before the bulldoze sweep")
	_main.call("_start_press", a_screen)
	_main.call("_extend_drag_path", cell_b)
	_main.call("_end_press", b_screen)
	assert(not state.grid.has(cell_a) and not state.grid.has(cell_b), "A bulldoze sweep must clear every tile it crossed")
	assert(not state.has_connection(cell_a, cell_b), "A bulldoze sweep must drop the cleared tiles' connections")
	print("Tool sweeps (ROUTE-15) checks passed.")

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

## LOOP-08: the sun cycle rides the day clock. Checks the shape of the curve
## rather than exact colours: midday is the brightest moment and night the
## dimmest, the sun sits highest at midday and near the horizon at dawn and
## sunset, and the cycle joins up across the day rollover instead of snapping.
func _check_day_cycle(state: GameState) -> void:
	var midday := DayCycle.sample(0.40)
	var night := DayCycle.sample(0.95)
	var dawn := DayCycle.sample(0.0)
	var sunset := DayCycle.sample(0.76)
	assert(midday.energy > dawn.energy and midday.energy > night.energy, "Midday must be the brightest moment of the day")
	assert(night.energy < dawn.energy, "Night must be dimmer than dawn")
	assert(night.ambient_energy > 0.0, "Night must keep some ambient light, or the map goes pure black")
	assert(midday.pitch < dawn.pitch and midday.pitch < sunset.pitch, "The sun must sit highest at midday and low at dawn/sunset")
	assert(DayCycle.label(0.40) == "Midday" and DayCycle.label(0.80) == "Sunset" and DayCycle.label(0.0) == "Dawn")

	# Wall clock: a day opens at 5:00 am, midday reads noon, and the clock
	# wraps back round rather than running past 24h at the rollover.
	assert(DayCycle.clock_text(0.0) == "5:00 am", "A day must open at 5:00 am, got %s" % DayCycle.clock_text(0.0))
	assert(DayCycle.clock_text(0.40) == "12:00 pm", "Midday must read 12:00 pm, got %s" % DayCycle.clock_text(0.40))
	assert(DayCycle.clock_text(0.76) == "6:30 pm", "Sunset must read 6:30 pm, got %s" % DayCycle.clock_text(0.76))
	assert(DayCycle.clock_text(0.95) == "11:00 pm", "Night must read 11:00 pm, got %s" % DayCycle.clock_text(0.95))
	assert(DayCycle.clock_text(0.9999).ends_with("am"), "The last moment of a day must have wrapped past midnight")
	assert(midday.minutes > dawn.minutes and night.minutes > sunset.minutes, "The wall clock must run forward through the day")

	# The sun sweeps a full turn, which is what makes shadows travel, and it
	# lands on the same orientation it started at (-282 == +78 mod 360).
	assert(absf(DayCycle.sample(0.9999).yaw - (dawn.yaw - 360.0)) < 1.0, "The sun's sweep must land back where it started, one turn on")
	assert(midday.shadow > night.shadow, "Shadows must be strongest by day and faintest under moonlight")

	# Shadows are actually on in the scene, or none of the above is visible.
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	# Shadows are off on web by design (a browser drops the WebGL context if
	# the GPU budget is overrun), so what's asserted is that the scene follows
	# that decision -- and, since these checks run on desktop, that desktop
	# does get them.
	assert(DayCycle.shadows_available(), "These checks run on desktop, where shadows must be available")
	assert(sun.shadow_enabled == DayCycle.shadows_available(), "The sun must cast shadows exactly where the build can afford them")
	# The range has to reach past the deepest view the camera can pull back to
	# (ZOOM_MAX of 60 over a ~60-degree tilt is roughly 69 units of ground), or
	# shadows visibly cut off partway across a zoomed-out map. It is otherwise
	# kept as tight as possible: a wider range spreads the same shadow map over
	# more ground, and the grass tufts start aliasing into a hatch.
	assert(sun.directional_shadow_max_distance >= 69.0, "The shadow range must cover the map at full zoom-out")

	# Continuity across the rollover: the last moment of a day and the first
	# moment of the next must be the same light, or the sky visibly snaps.
	var end_of_day := DayCycle.sample(0.9999)
	var start_of_next := DayCycle.sample(0.0)
	assert(absf(end_of_day.energy - start_of_next.energy) < 0.05, "The sun cycle must join up across the day rollover")
	var sky_gap: float = maxf(maxf(absf(end_of_day.sky.r - start_of_next.sky.r), absf(end_of_day.sky.g - start_of_next.sky.g)), absf(end_of_day.sky.b - start_of_next.sky.b))
	assert(sky_gap < 0.05, "The sky must not snap at the day rollover")

	# The phase follows the clock, and a stopped clock holds the light still.
	state.day_time_left = GameBalance.DAY_LENGTH_SEC
	assert(is_equal_approx(_main.call("_day_phase"), 0.0), "A full clock means the start of the day")
	state.day_time_left = 0.0
	assert(is_equal_approx(_main.call("_day_phase"), 1.0), "An expired clock means the end of the day")
	state.day_time_left = GameBalance.DAY_LENGTH_SEC * 0.5
	assert(is_equal_approx(_main.call("_day_phase"), 0.5), "Half the clock left means half the day gone")
	print("Day cycle lighting (LOOP-08) checks passed.")

## A multi-tile settlement speaks once, not once per tile (DEV-02).
##
## The bubble renderer used to walk Main._nodes_by_pos, which holds an entry
## per OCCUPIED CELL -- so the moment City E became 2x2 that loop would have
## drawn its whole stack four times, stacked exactly on top of itself. It is
## invisible in a screenshot and doubles the bubble count on the busiest node
## on the map, so it gets a check rather than an eyeball.
func _test_multi_tile_settlement_draws_one_stack(map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var city := _node_by_id(map_data, "cityE")
	assert(city.cells().size() == 4, "This check is only meaningful while City E is 2x2")

	# Open exactly one order at City E and re-render.
	state.active_orders[city.node_id] = {"seafood": 1}
	_main.call("_render_grid")

	var visuals: Node3D = _main.get_node("GridVisuals")
	var centre: Vector3 = _main.call("_node_center", city)
	var stacks := 0
	for child in visuals.get_children():
		if child is FoodBubbleMarker and Vector2(child.position.x, child.position.z).distance_to(Vector2(centre.x, centre.z)) < 1.0:
			stacks += 1
	assert(stacks == 1, "A 2x2 City with one open order must draw one bubble, got %d" % stacks)

	state.active_orders.erase(city.node_id)
	_main.call("_render_grid")
	print("Multi-tile bubbles (DEV-02): City E draws 1 stack across 4 cells.")

## A settlement draws ONE column marker whatever its state, and the collapsed
## and expanded columns are the same height so their rows line up (UI-04). Both halves are invisible to a screenshot taken at
## the wrong moment, and the collapse is the whole point of the feature -- a
## regression that quietly drew balloons again would just look like the old
## build.
##
## The severity sort is checked here too, because it decides which chip is
## at the TOP of the column and which balloon leads an expanded stack, and nothing else would catch it
## silently reverting to dictionary order.
func _test_glyph_column_collapses_and_expands(map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var city := _node_by_id(map_data, "cityE")
	var centre: Vector3 = _main.call("_node_center", city)

	# Three open orders, deliberately spanning all three statuses: seafood
	# gets nothing (red), grain arrives in full but dull (amber), bread
	# arrives in full and fresh (green).
	state.active_orders[city.node_id] = {"seafood": 10, "grain": 10, "bread": 10}
	state.last_settlement_status[city.node_id] = {
		"seafood": {"requested": 10.0, "delivered": 0.0, "fresh_sum": 0.0},
		"grain": {"requested": 10.0, "delivered": 10.0, "fresh_sum": 500.0},
		"bread": {"requested": 10.0, "delivered": 10.0, "fresh_sum": 1000.0},
	}

	# Wide enough to take in the column, and far short of the nearest other
	# node (Harbor is 8 world units away).
	var span := 2.5

	_main.set("_focused_node_id", "")
	_main.call("_render_grid")
	assert(_count_bubbles_at(centre, span) == 1,
		"A settlement draws ONE column marker, got %d" % _count_bubbles_at(centre, span))
	var collapsed: Vector2i = _column_viewport_at(centre, span)

	_main.set("_focused_node_id", city.node_id)
	_main.call("_render_grid")
	assert(_count_bubbles_at(centre, span) == 1,
		"Expanding must still be ONE marker, not one per order, got %d" % _count_bubbles_at(centre, span))
	var expanded: Vector2i = _column_viewport_at(centre, span)

	# The whole point of the layout: collapsed and expanded are the same
	# column at two widths. Equal heights mean row i sits at the same screen
	# height in both, so a hover widens the panel around glyphs that do not
	# move. If these ever diverge the transition stops reading as one object
	# unfurling and becomes a swap, which is invisible in a static screenshot.
	assert(collapsed.y == expanded.y,
		"Collapsed and expanded columns must be the same height (%d vs %d)" % [collapsed.y, expanded.y])
	assert(expanded.x > collapsed.x,
		"Expanding must widen the column (%d vs %d)" % [collapsed.x, expanded.x])
	assert(is_equal_approx(BubbleCanvas.column_x_shift(3), (expanded.x - collapsed.x) * 0.5),
		"The expanded column must be nudged right by half the width it gained, or the glyphs slide")

	# Severity order: red, then amber, then green.
	var entries := [
		{"status": FoodBubbleMarker.Status.GREEN, "requested": 10.0, "delivered": 10.0},
		{"status": FoodBubbleMarker.Status.RED, "requested": 10.0, "delivered": 0.0},
		{"status": FoodBubbleMarker.Status.AMBER, "requested": 10.0, "delivered": 10.0},
	]
	entries.sort_custom(Callable(_main, "_worse_first"))
	assert(entries[0].status == FoodBubbleMarker.Status.RED, "Red sorts first")
	assert(entries[1].status == FoodBubbleMarker.Status.AMBER, "Amber sorts above green")
	assert(entries[2].status == FoodBubbleMarker.Status.GREEN, "Green sorts last")

	# Within a tier, the bigger shortfall as a FRACTION of what was asked
	# for comes first -- a village 5 short of 10 is closer to failing than a
	# city 5 short of 40.
	var tied := [
		{"status": FoodBubbleMarker.Status.RED, "requested": 40.0, "delivered": 35.0},
		{"status": FoodBubbleMarker.Status.RED, "requested": 10.0, "delivered": 5.0},
	]
	tied.sort_custom(Callable(_main, "_worse_first"))
	assert(is_equal_approx(tied[0].requested, 10.0), "The proportionally worse shortfall sorts first")

	_main.set("_focused_node_id", "")
	state.active_orders.erase(city.node_id)
	state.last_settlement_status.erase(city.node_id)
	_main.call("_render_grid")
	print("Glyph column (UI-04): one marker either way, same height collapsed and expanded, sorted worst-first.")

## No two nodes\' columns may overlap on screen, at their WORST case: every
## demand line open at once.
##
## This is a distance rule derived from the chip geometry rather than guessed.
## Columns are billboards, so their extent in the camera plane is exactly
## pixels * pixel_size -- and the camera is orthographic with no yaw, so a
## world point\'s position in that plane is just its dot product with the
## camera basis. Two columns collide when those rectangles intersect.
##
## It failed before MAX_COLUMN_ROWS existed: a five-chip City E column stood
## 7.62 units tall and needed 4.4 tiles of clear space above it, where Town D
## sits 3.5 away and Village C is 3 above Town D. Capping the rows bounds the
## height at 4.68 and the map clears it. The check matters most for the region
## roster (§12.1) -- a new map can be authored into this the moment two
## settlements are placed a few tiles apart.
func _test_columns_never_overlap(map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var camera: Camera3D = _main.get_node("Camera3D")
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var pixel := FoodBubbleMarker.BASE_PIXEL_SIZE * FoodBubbleMarker.COLUMN_SCALE

	# Worst case: every authored line open at every settlement.
	var saved := state.active_orders.duplicate(true)
	for node in map_data.node_placements:
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			state.active_orders[node.node_id] = node.demand.duplicate()
	_main.call("_render_grid")

	var rects: Array[Dictionary] = []
	for node in map_data.node_placements:
		var count := 1
		if node.node_type == GameEnums.NodeType.SETTLEMENT:
			count = node.demand.size()
		var is_source := node.node_type == GameEnums.NodeType.SOURCE
		var px: Vector2i = BubbleCanvas.column_size(count, false, is_source)
		var base: Vector3 = _main.call("_node_center", node)
		base.y += 2.5 if is_source else 3.1
		# Billboards face the camera, so the sprite spans exactly px * pixel
		# in the camera plane, anchored by its bottom edge.
		var u := base.dot(right)
		var v := base.dot(up)
		rects.append({
			"id": node.node_id,
			"rect": Rect2(u - px.x * pixel * 0.5, v, px.x * pixel, px.y * pixel),
		})

	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Dictionary = rects[i]
			var b: Dictionary = rects[j]
			assert(not (a.rect as Rect2).intersects(b.rect),
				"%s and %s overlap on screen at full demand: %s vs %s -- move them apart or lower MAX_COLUMN_ROWS" % [
					a.id, b.id, a.rect, b.rect,
				])

	state.active_orders = saved
	_main.call("_render_grid")
	print("Column spacing: all %d nodes clear of each other with every line open (max %d rows)." % [
		rects.size(), BubbleCanvas.MAX_COLUMN_ROWS,
	])

## Each status plays its own flourish exactly once on the render after a day,
## and a new order's pop suppresses all of them (items 57-59).
##
## The pop is a tween on a marker that _render_grid destroys and rebuilds on
## every hover change, day and build -- so the thing that can silently break
## is not the animation but its bookkeeping: a pending pop that is never
## cleared would re-fire on every subsequent render, leaving the map twitching
## whenever the pointer crosses a node. Neither failure shows up in a
## screenshot.
func _test_flourishes_fire_once(map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var city := _node_by_id(map_data, "cityE")
	var centre: Vector3 = _main.call("_node_center", city)
	state.active_orders[city.node_id] = {"seafood": 10}

	var pops: Dictionary = _main.get("_pending_pops")
	pops[city.node_id] = true
	_main.call("_render_grid")
	var marker := _column_marker_at(centre, 2.5)
	assert(marker != null, "The popping settlement must have drawn a column")
	assert(marker.scale.x < 1.0,
		"A popped column must start scaled down, got %.2f" % marker.scale.x)
	assert(_main.get("_pending_pops").is_empty(),
		"A render must consume every pending pop, or it re-fires on the next hover")

	# The very next render draws the same column at rest.
	_main.call("_render_grid")
	var settled := _column_marker_at(centre, 2.5)
	assert(settled != null and is_equal_approx(settled.scale.x, 1.0),
		"A column must not pop again on a later render")

	# A pop the player could not have seen is spent, not banked.
	_main.set("_bubbles_mode", 2)  # BubblesMode.OFF
	var off_pops: Dictionary = _main.get("_pending_pops")
	off_pops[city.node_id] = true
	_main.call("_render_grid")
	assert(_main.get("_pending_pops").is_empty(),
		"A pop must be cleared even when bubbles are off, not saved up")
	_main.set("_bubbles_mode", 0)  # BubblesMode.GLYPHS

	# Only red moves on the render after a day (item 66). The two paying tiers
	# are the ones a working network hits nearly every day, so marking them made
	# the map move on almost every rollover -- the opposite of emphasis. Their
	# tier is still on the chip's colour and their money still floats as a
	# label, so a silent green is not a green that went unreported.
	#
	# Asserted on what the marker was ASKED to play, not on its transform: a
	# tween applies nothing until it processes, so the column is still exactly
	# at rest on the frame it was told to shake. (An earlier version of this
	# check compared position.y against the node centre rather than the
	# marker's real rest height of centre + 3.1, so it passed no matter what.)
	for probe in [
		{"fresh": 1000.0, "delivered": 10.0, "want": FoodBubbleMarker.Flourish.NONE, "label": "green must stay still"},
		{"fresh": 500.0, "delivered": 10.0, "want": FoodBubbleMarker.Flourish.NONE, "label": "amber must stay still"},
		{"fresh": 0.0, "delivered": 0.0, "want": FoodBubbleMarker.Flourish.SHAKE, "label": "red must shake"},
	]:
		state.last_settlement_status[city.node_id] = {
			"seafood": {"requested": 10.0, "delivered": probe.delivered, "fresh_sum": probe.fresh,
				"rejected": 0.0, "rejected_fresh_sum": 0.0, "earned": 0.0, "withheld": 0.0},
		}
		_main.set("_day_just_ran", true)
		_main.call("_render_grid")
		var m := _column_marker_at(centre, 3.0)
		assert(m != null, "%s -- no column drawn" % probe.label)
		assert(m.played == probe.want, "%s, got %d" % [probe.label, m.played])
		assert(not _main.get("_day_just_ran"),
			"The render must consume _day_just_ran, or every hover re-plays the map")

	# The payout label lives outside GridVisuals, or _render_grid would destroy
	# it mid-flight the first time the pointer moved. It also only appears for
	# a settlement that actually earned: "+§0" would say nothing the shake has
	# not already said.
	state.last_settlement_status[city.node_id] = {
		"seafood": {"requested": 10.0, "delivered": 10.0, "fresh_sum": 1000.0,
			"rejected": 0.0, "rejected_fresh_sum": 0.0, "earned": 125.0, "withheld": 0.0},
	}
	var fx: Node3D = _main.get_node("Effects")
	_clear_children(fx)
	_main.set("_day_just_ran", true)
	_main.call("_render_grid")
	assert(fx.get_child_count() > 0, "A paying settlement must float a payout label")
	assert(fx.get_child(0).text.begins_with("+§"), "The payout label must read as money, got '%s'" % fx.get_child(0).text)
	_main.call("_render_grid")
	assert(fx.get_child_count() > 0, "A re-render must not destroy a payout label in flight")

	_clear_children(fx)
	state.last_settlement_status[city.node_id] = {
		"seafood": {"requested": 10.0, "delivered": 0.0, "fresh_sum": 0.0,
			"rejected": 0.0, "rejected_fresh_sum": 0.0, "earned": 0.0, "withheld": 100.0},
	}
	_main.set("_day_just_ran", true)
	_main.call("_render_grid")
	assert(fx.get_child_count() == 0, "A settlement that earned nothing must not float a label")
	_clear_children(fx)

	# The reminder: only settlements whose worst line earned nothing are
	# recorded for it, and it shakes their markers directly rather than
	# re-rendering the whole map to move a few of them.
	state.last_settlement_status[city.node_id] = {
		"seafood": {"requested": 10.0, "delivered": 0.0, "fresh_sum": 0.0,
			"rejected": 0.0, "rejected_fresh_sum": 0.0, "earned": 0.0, "withheld": 100.0},
	}
	_main.call("_render_grid")
	var nagging: Array = _main.get("_nagging_nodes")
	assert(nagging.has(city.node_id), "A settlement earning nothing must be recorded for the reminder")
	var by_node: Dictionary = _main.get("_columns_by_node")
	assert(by_node.has(city.node_id), "The reminder needs the column it is going to shake")

	# Firing it plays the gentler NAG, never the day-end SHAKE.
	_main.set("_reminder_elapsed", 999.0)
	_main.call("_tick_reminder", 0.0)
	assert(by_node[city.node_id].played == FoodBubbleMarker.Flourish.NAG,
		"The reminder must play NAG, not the day-end SHAKE")
	assert(_main.get("_reminder_elapsed") < 1.0, "Firing must reset the reminder's clock")

	# A paying settlement is never nagged.
	state.last_settlement_status[city.node_id] = {
		"seafood": {"requested": 10.0, "delivered": 10.0, "fresh_sum": 1000.0,
			"rejected": 0.0, "rejected_fresh_sum": 0.0, "earned": 125.0, "withheld": 0.0},
	}
	_main.call("_render_grid")
	assert(not (_main.get("_nagging_nodes") as Array).has(city.node_id),
		"A settlement that paid must not be nagged")

	# Without a day behind it, a render plays nothing at all.
	_main.call("_render_grid")
	var quiet := _column_marker_at(centre, 3.0)
	assert(quiet != null and quiet.played == FoodBubbleMarker.Flourish.NONE,
		"A render with no day behind it must play nothing")

	# Should a pop and a day-end shake ever land on one render, the pop still
	# wins -- one flourish per column, never both. Item 66 separated them in
	# practice (the shake plays as the day resolves, the pop half a second later
	# on the reveal render), so this is now the tie-break holding rather than
	# the everyday path.
	var both: Dictionary = _main.get("_pending_pops")
	both[city.node_id] = true
	_main.set("_day_just_ran", true)
	_main.call("_render_grid")
	var popped := _column_marker_at(centre, 3.0)
	assert(popped != null and popped.played == FoodBubbleMarker.Flourish.POP,
		"A pending pop must outrank the delivery flourish")
	assert(popped.scale.x < 1.0, "A popped column must start scaled down")

	state.active_orders.erase(city.node_id)
	state.last_settlement_status.erase(city.node_id)
	_main.call("_render_grid")
	print("Flourishes (items 57-61, 66): only red moves at day end, the pop fires once, the payout label survives a re-render, and only unpaid settlements get the recurring nag.")

## Item 66: an order opened by the day just simulated is held out of the map
## until that day's own results have been read, then arrives with a pop.
##
## The part worth checking is that the chip is GENUINELY deferred rather than
## merely animated late. Filling an order opens the next immediately (DEV-01),
## so without the hold the new chip is drawn by the very render reporting the
## delivery that earned it -- and, being undelivered and therefore red, sorted
## straight to the top of the column above the lines that actually resolved. A
## pop alone would not fix that; the chip has to be absent and then arrive.
func _test_new_orders_arrive_late(map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var city := _node_by_id(map_data, "cityE")
	var centre: Vector3 = _main.call("_node_center", city)

	var lines: Array = []
	for food_id in city.demand:
		lines.append(food_id)
		if lines.size() == 2:
			break
	assert(lines.size() == 2, "this check needs a settlement with two demand lines")
	state.active_orders[city.node_id] = {lines[0]: state.day, lines[1]: state.day}

	_main.call("_render_grid")
	var full := _column_viewport_at(centre, 3.0)

	# Held back: the column is genuinely shorter, not merely still.
	var deferred: Dictionary = _main.get("_deferred_orders")
	deferred[city.node_id] = [lines[1]]
	_main.call("_render_grid")
	var held := _column_viewport_at(centre, 3.0)
	assert(held.y < full.y,
		"a held-back order must be left out of the column, got %s against %s" % [held, full])
	assert(_column_marker_at(centre, 3.0).played == FoodBubbleMarker.Flourish.NONE,
		"a column must not pop for a chip it is not showing yet")

	# The reveal brings it in, on a render of its own, popping the column.
	_main.call("_reveal_new_orders")
	assert((_main.get("_deferred_orders") as Dictionary).is_empty(),
		"the reveal must release every held-back order")
	var revealed := _column_viewport_at(centre, 3.0)
	assert(revealed == full,
		"a revealed order must restore the full column, got %s against %s" % [revealed, full])
	var marker := _column_marker_at(centre, 3.0)
	assert(marker != null and marker.played == FoodBubbleMarker.Flourish.POP,
		"a new chip must arrive with a pop")
	assert((_main.get("_pending_pops") as Dictionary).is_empty(),
		"the reveal's render must consume its own pops")

	# Idempotent, so the real-time timer firing after an early reveal cannot pop
	# the map a second time. With nothing pending it returns before rendering at
	# all, so what has to be checked is that nothing was re-armed for the NEXT
	# render -- the marker still on screen is the one that already popped.
	_main.call("_reveal_new_orders")
	assert((_main.get("_pending_pops") as Dictionary).is_empty(),
		"a reveal with nothing pending must arm nothing")
	_main.call("_render_grid")
	assert(_column_marker_at(centre, 3.0).played == FoodBubbleMarker.Flourish.NONE,
		"a second reveal must not pop the column again")

	state.active_orders.erase(city.node_id)
	_main.call("_render_grid")
	print("New orders (item 66): a day's new chip is held out of the column, then arrives on a render of its own with a pop.")

## Item 64: a placed tile presses up out of the ground, and what a bulldoze
## takes away squashes flat and goes.
##
## The interpolation is Godot's. Two things around it are not, and neither
## shows up in a screenshot. The first is the bookkeeping the column pops
## already get wrong once -- _render_grid rebuilds every tile on every hover,
## day and build, so a pending pop left behind leaves the whole network flexing
## whenever the pointer crosses a node. The second is a rule this effect adds:
## only the part that actually ARRIVED pops. Building a hub puts a marker on a
## road that was already there, so popping the road under it would announce a
## tile the player never placed -- and the failure is invisible in a still.
##
## Runs before the drag suite and hands the map back as it found it -- empty
## grid, untouched treasury, no source expanded -- since every later check
## starts from that.
func _test_tile_placement_pops_once(_map_data: MapData) -> void:
	var state: GameState = _main.get("_state")
	var fx: Node3D = _main.get_node("Effects")
	var balance_before: float = state.balance
	# Open ground well clear of every node and of the river column.
	var run: Array[Vector2i] = [Vector2i(15, 2), Vector2i(15, 3), Vector2i(15, 4)]
	for cell in run:
		assert(not state.grid.has(cell), "the pop check needs empty ground at %s" % cell)

	# One pop per new tile, on the ROAD, staggered in the order the player drew.
	# Checked on the arming step rather than after _commit_drag, which renders
	# before it returns and so consumes its own pops on the way out.
	_main.call("_arm_placement_pops", run)
	var armed: Dictionary = _main.get("_pending_tile_pops")
	assert(armed.size() == 3, "a drag must arm one pop per new tile, got %d" % armed.size())
	var previous := -1.0
	for cell in run:
		assert(armed[cell].part == 0, "a dragged tile must pop its ROAD, not a structure")
		assert(armed[cell].delay > previous,
			"pops must stagger along the drag order, got %.3f after %.3f" % [armed[cell].delay, previous])
		previous = armed[cell].delay
	assert(is_zero_approx(armed[run[0]].delay), "the first tile of a drag must not wait")
	armed.clear()

	# End to end: a committed drag builds its run and leaves every tile of it
	# mid-pop, with nothing pending for the next render to re-fire.
	var connections: Array[Array] = []
	_main.set("_drag_valid", true)
	_main.set("_drag_new_cells", run)
	_main.set("_drag_new_connections", connections)
	_main.call("_commit_drag")
	assert(state.grid.size() == 3, "the drag must have built its run, got %d tiles" % state.grid.size())
	assert(_squashed_tiles() == 3, "every dragged tile must start squashed, got %d" % _squashed_tiles())
	assert((_main.get("_pending_tile_pops") as Dictionary).is_empty(),
		"a render must consume every pending tile pop, or it re-fires on the next hover")
	_main.call("_render_grid")
	assert(_squashed_tiles() == 0, "a tile must not pop again on a later render")

	# A hub pops its MARKER alone -- the road underneath it is not new.
	var hub_cell: Vector2i = run[1]
	_main.call("_do_build_hub", hub_cell)
	var hub_armed: Dictionary = _main.get("_pending_tile_pops")
	assert(hub_armed.has(hub_cell) and hub_armed[hub_cell].part == 1,
		"building a hub must arm the STRUCTURE, not the road it stands on")
	_main.call("_render_grid")
	var squashed := _squashed_nodes()
	assert(squashed.size() == 1, "a hub must pop exactly one thing, got %d" % squashed.size())
	assert(squashed[0] is NodeMarker, "a hub must pop its marker, not the road under it")
	# The punch is squash and stretch, so the two axes must start in OPPOSITION
	# -- flattened and spread. A splat that shrank on every axis at once would
	# read as the building falling away from the camera rather than landing.
	assert(squashed[0].scale.y < 0.5 and squashed[0].scale.x > 1.0,
		"a landing structure must start flat and spread, got %s" % squashed[0].scale)

	# Upgrading a route swaps the block outright -- Dirt, Paved and Main are
	# three different meshes -- so what the player is left looking at is new.
	var paved_cell: Vector2i = run[0]
	_main.call("_do_upgrade_route", paved_cell)
	assert(state.grid[paved_cell].level == "paved", "the upgrade must have gone through")
	var upgrade_armed: Dictionary = _main.get("_pending_tile_pops")
	assert(upgrade_armed.has(paved_cell) and upgrade_armed[paved_cell].part == 0,
		"upgrading a route must land its new block")
	_main.call("_render_grid")
	assert(_squashed_tiles() == 1, "an upgraded tile must pop, and only it")
	_main.call("_render_grid")
	assert(_squashed_tiles() == 0, "an upgrade must not re-pop on a later render")

	# Expanding a source is the one construction that is not a grid cell: its
	# markers live in NodeMarkers, which _render_grid never rebuilds, so they are
	# popped directly and must survive the renders that follow. Uses the Harbor
	# and hands it straight back, because the DEV-03 check below expects a map
	# nothing has expanded yet.
	var source: NodeData = _node_by_id(_map_data, "harbor")
	var markers: Node3D = _main.get_node("NodeMarkers")
	state.balance = GameBalance.SOURCE_UPGRADE_COST
	_main.call("_do_upgrade_source", source)
	assert(source.upgraded, "the source upgrade must have gone through")
	var landed := 0
	for marker in markers.get_children():
		if marker is NodeMarker and marker.node_data != null and marker.node_data.node_id == source.node_id:
			assert(not is_equal_approx(marker.scale.y, 1.0),
				"an expanded source's markers must land, got scale %s" % marker.scale)
			landed += 1
	assert(landed == source.cells().size(),
		"every cell of an expanded source must land, got %d of %d" % [landed, source.cells().size()])
	_main.call("_render_grid")
	for marker in markers.get_children():
		if marker is NodeMarker and marker.node_data != null and marker.node_data.node_id == source.node_id:
			assert(not is_equal_approx(marker.scale.y, 1.0),
				"a re-render must not cancel a source marker's landing -- it is not in GridVisuals")
			marker.scale = Vector3.ONE
	source.upgraded = false
	for food_id in source.produces:
		source.produces[food_id] /= GameBalance.SOURCE_UPGRADE_SUPPLY_MULT

	# Bulldozing is the inverse, and its copy lives on Effects -- parented to
	# GridVisuals it would be destroyed by the render that immediately follows.
	_clear_children(fx)
	_main.call("_do_bulldoze", hub_cell)
	assert(fx.get_child_count() == 1, "a bulldoze must leave one removal ghost on Effects")
	var ghost: Node3D = fx.get_child(0)
	assert(ghost.get_child_count() == 1,
		"a removed hub's ghost must be the marker alone -- the road it stood on stays")
	assert(ghost.get_child(0) is NodeMarker, "a removed hub must squash its marker")
	_main.call("_render_grid")
	assert(fx.get_child_count() == 1, "a re-render must not destroy a removal ghost in flight")
	assert(state.grid[hub_cell].kind == "route", "bulldozing a hub must hand its road back")
	assert(_squashed_tiles() == 0, "a bulldoze must not pop the road it leaves behind")

	_clear_children(fx)
	for cell in run:
		state.grid.erase(cell)
		state.remove_connections(cell)
	state.balance = balance_before
	_main.call("_render_grid")
	print("Construction pop (items 64-65): routes, upgrades, hubs and expanded sources all land, each once and in draw order, splatting flat and spread before they stretch; a bulldoze crushes on the Effects layer.")

## Grid children currently mid-flourish. Nothing else in GridVisuals is ever
## scaled (the route overlay and the bubble columns size themselves by mesh and
## viewport instead), so an unexpected one here is a pop that did not clear.
## SETT-05: each settlement draws one bespoke model, sized to its own
## footprint and centred on it.
##
## Two things worth pinning down. A settlement's model must be CENTRED on its
## footprint, because that is what makes the plaza cover exactly the cells the
## place blocks -- a City centred on its top-left corner would sit a tile and a
## half off its own ground. And the marker must be left self-coloured: the
## shared tint flattens every mesh under "Visual" to one colour, which is right
## for a hub and would turn a settlement's walls, roofs, plaza and tree all the
## same red.
func _test_settlement_markers(map_data: MapData, markers: Node3D, terrain: GridMap) -> void:
	var seen := {}
	for marker in markers.get_children():
		if marker is NodeMarker and marker.node_data != null and marker.node_data.node_type == GameEnums.NodeType.SETTLEMENT:
			assert(not seen.has(marker.node_data.node_id), "%s drew more than one model" % marker.node_data.node_id)
			seen[marker.node_data.node_id] = marker
	var by_type := {}
	for node in map_data.node_placements:
		if node.node_type != GameEnums.NodeType.SETTLEMENT:
			continue
		var marker: NodeMarker = seen.get(node.node_id)
		assert(marker != null, "%s drew no model at all" % node.node_id)
		assert(marker.self_coloured, "%s must keep its own palette, not be tinted flat" % node.node_id)
		var near: Vector3 = terrain.map_to_local(Vector3i(node.grid_position.x, 0, node.grid_position.y))
		var far_cell := node.far_cell()
		var far: Vector3 = terrain.map_to_local(Vector3i(far_cell.x, 0, far_cell.y))
		var want: Vector3 = (near + far) * 0.5 + Vector3(0, 1.0, 0)
		assert(marker.position.is_equal_approx(want), "%s is not centred on its footprint" % node.node_id)
		by_type[node.settlement_type] = by_type.get(node.settlement_type, 0) + 1
	assert(by_type.size() == 3, "the map should exercise all three settlement sizes")
	print("Settlement models (SETT-05): %d places, one model each, centred on their footprints across %d sizes." % [seen.size(), by_type.size()])

## TERR-09: the scattered trees and bushes. Four properties, and the first two
## are the ones that would quietly rot: the scatter must be the SAME on every
## render (Main rebuilds the grid on each hover, so a re-rolled scatter makes
## the forest crawl), and it must leave a clearing around every node (a prop is
## tall enough to cut across a node's order chips). The other two are the
## contract with building: a prop gets out of the way of what the player
## builds, and comes back when it is bulldozed.
func _test_ground_vegetation(map_data: MapData, terrain: GridMap, state: GameState) -> void:
	var decor: Dictionary = terrain.get("_decor_by_cell")
	assert(not decor.is_empty(), "The terrain must scatter some vegetation over open ground")

	var blocked := {}
	for node in map_data.node_placements:
		for node_cell in node.cells():
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					blocked[node_cell + Vector2i(dx, dy)] = true
	var eligible := 0
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			if map_data.get_terrain(x, y) == GameEnums.TerrainType.PLAINS and not blocked.has(Vector2i(x, y)):
				eligible += 1
	for cell in decor:
		assert(not map_data.is_river(cell.x, cell.y), "Nothing may grow in the river at %s" % cell)
		assert(not blocked.has(cell), "%s is inside a node's one-cell clearing and must stay bare" % cell)
	var share := float(decor.size()) / float(maxi(eligible, 1))
	assert(share > 0.1 and share < 0.6, "Vegetation should dress open ground, not carpet or barely touch it (got %.2f)" % share)

	# The same map must grow the same trees in the same places, however many
	# times it is rendered.
	var first := decor.keys()
	terrain.call("render", map_data)
	var second: Dictionary = terrain.get("_decor_by_cell")
	assert(second.size() == first.size(), "A re-render must scatter the same number of props")
	for cell in first:
		assert(second.has(cell), "A re-render moved the prop that was on %s" % cell)

	# Building clears the ground under it; bulldozing grows it back.
	var built_cell: Vector2i = first[0]
	state.grid[built_cell] = {"kind": "route", "level": "dirt"}
	_main.call("_render_grid")
	assert(not (second[built_cell] as Node3D).visible, "A prop must hide under a tile built on its cell")
	state.grid.erase(built_cell)
	_main.call("_render_grid")
	assert((second[built_cell] as Node3D).visible, "Bulldozing a tile must grow its vegetation back")
	print("Ground vegetation (TERR-09): %d props on %d open cells, stable across renders, clear of every node, hidden under what is built." % [decor.size(), eligible])

func _squashed_nodes() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in (_main.get_node("GridVisuals") as Node3D).get_children():
		if child is Node3D and not is_equal_approx((child as Node3D).scale.y, 1.0):
			found.append(child)
	return found

func _squashed_tiles() -> int:
	return _squashed_nodes().size()

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()

func _column_marker_at(centre: Vector3, radius: float) -> FoodBubbleMarker:
	var visuals: Node3D = _main.get_node("GridVisuals")
	for child in visuals.get_children():
		if child is FoodBubbleMarker and Vector2(child.position.x, child.position.z).distance_to(Vector2(centre.x, centre.z)) < radius:
			return child
	return null

## The SubViewport size of the single column marker near `centre`.
func _column_viewport_at(centre: Vector3, radius: float) -> Vector2i:
	var visuals: Node3D = _main.get_node("GridVisuals")
	for child in visuals.get_children():
		if child is FoodBubbleMarker and Vector2(child.position.x, child.position.z).distance_to(Vector2(centre.x, centre.z)) < radius:
			return (child.get_node("SubViewport") as SubViewport).size
	return Vector2i.ZERO

func _count_bubbles_at(centre: Vector3, radius: float) -> int:
	var visuals: Node3D = _main.get_node("GridVisuals")
	var count := 0
	for child in visuals.get_children():
		if child is FoodBubbleMarker and Vector2(child.position.x, child.position.z).distance_to(Vector2(centre.x, centre.z)) < radius:
			count += 1
	return count

## The Upgrade tool spends money to double a source's output (DEV-03). The
## footprint does not change -- a source already stands on 2x1 -- so nothing
## about the map moves.
func _test_source_upgrade() -> void:
	var state: GameState = _main.get("_state")
	var map_data: MapData = _main.get("_map_data")
	var garden: NodeData = _node_by_id(map_data, "garden")
	var saved_balance: float = state.balance
	var footprint := garden.cells()
	assert(footprint.size() == 2, "A source should stand on 2 tiles, got %d" % footprint.size())

	var supply_before: float = garden.produces.vegetables
	state.balance = GameBalance.SOURCE_UPGRADE_COST
	_main.call("_set_tool", "upgrade")
	_main.call("_handle_click", garden.grid_position)
	assert(is_equal_approx(garden.produces.vegetables, supply_before * GameBalance.SOURCE_UPGRADE_SUPPLY_MULT), "Upgrading must double output")
	assert(is_equal_approx(state.balance, 0.0), "The upgrade must cost SOURCE_UPGRADE_COST")
	assert(garden.cells() == footprint, "Upgrading must not move or resize a source")
	assert(not garden.can_upgrade(), "An expanded source must not offer another upgrade")

	# Tapping the source's OTHER cell must work too -- every cell of a
	# footprint resolves to the same node (DEV-02).
	state.balance = GameBalance.SOURCE_UPGRADE_COST
	_main.call("_handle_click", garden.far_cell())
	assert(is_equal_approx(state.balance, GameBalance.SOURCE_UPGRADE_COST), "A second upgrade must not charge")

	# The Upgrade tool must still refuse a settlement.
	var village: NodeData = _node_by_id(map_data, "villageA")
	assert(not village.can_upgrade(), "A settlement is never upgradeable")
	_main.call("_handle_click", village.grid_position)
	assert(is_equal_approx(state.balance, GameBalance.SOURCE_UPGRADE_COST), "Tapping a settlement with Upgrade must not charge")

	print("Source upgrade (DEV-03): Garden %d -> %d, footprint %s unchanged." % [
		roundi(supply_before), roundi(garden.produces.vegetables), garden.size,
	])
	state.balance = saved_balance
	_main.call("_set_tool", "route")

## Screen position of a grid cell's centre, for driving real press/drag
## gestures through Main's input entry points.
func _cell_screen(camera: Camera3D, terrain: GridMap, cell: Vector2i) -> Vector2:
	return camera.unproject_position(terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3.UP)

func _node_by_id(map_data: MapData, node_id: String) -> NodeData:
	for node in map_data.node_placements:
		if node.node_id == node_id:
			return node
	return null
