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

	_check_day_clock(state)
	_check_day_cycle(state)

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)
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
	# on: the tile survives as plain dirt route, still carrying the road that
	# ran underneath, while the route that crossed over is cut. Merging the two
	# instead would silently join the networks the crossing was keeping apart.
	_main.call("_set_tool", "remove")
	var balance_before_clear: float = state.balance
	_main.call("_handle_click", bridge)
	assert(state.grid.has(bridge), "Bulldozing a bridge must leave the road it was built on behind")
	assert(not SimulationEngine.is_bridge(state, bridge), "Bulldozing a bridge must remove the deck")
	assert(state.grid[bridge].kind == "route" and state.grid[bridge].level == "dirt", "A bulldozed bridge must revert to a dirt route tile")
	assert(state.has_connection(bridge, road[1]) and state.has_connection(bridge, road[3]), "The road under a bulldozed bridge must stay connected")
	assert(not state.has_connection(bridge, Vector2i(16, 11)) and not state.has_connection(bridge, Vector2i(18, 11)),
		"Bulldozing a bridge must cut the route that crossed over it, not merge it into the road below")
	var comp_after := SimulationEngine.road_components(state)
	assert(comp_after[SimulationEngine.vertex(bridge, SimulationEngine.LANE_GROUND)] != comp_after[SimulationEngine.vertex(Vector2i(16, 11), SimulationEngine.LANE_GROUND)],
		"The two roads must stay separate networks after the bridge between them is cleared")
	assert(is_equal_approx(state.balance, balance_before_clear), "Bulldoze must not refund")

	# Same rule for a hub: the structure goes, the road stays as dirt.
	_main.call("_set_tool", "hubBuild")
	_main.call("_handle_click", road[3])
	assert(state.grid[road[3]].kind == "hub", "The hub checks need a hub on the road first")
	_main.call("_set_tool", "remove")
	_main.call("_handle_click", road[3])
	assert(state.grid.has(road[3]), "Bulldozing a hub must leave the road it was built on behind")
	assert(state.grid[road[3]].kind == "route" and state.grid[road[3]].level == "dirt", "A bulldozed hub must revert to a dirt route tile")
	assert(state.has_connection(road[3], road[2]) and state.has_connection(road[3], road[4]), "The road under a bulldozed hub must stay connected")
	assert(not SimulationEngine.network_at_hub_cap(state, road[3]), "Bulldozing a hub must free its slot in the per-network cap")

	# Clear up so the later tool checks see the map they expect.
	for cell in state.grid.keys():
		if cell.x >= 15 and cell.y >= 9:
			state.grid.erase(cell)
			state.remove_connections(cell)
	_main.call("_set_tool", "route")
	print("Bridge tool (ROUTE-17) checks passed.")

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

## Screen position of a grid cell's centre, for driving real press/drag
## gestures through Main's input entry points.
func _cell_screen(camera: Camera3D, terrain: GridMap, cell: Vector2i) -> Vector2:
	return camera.unproject_position(terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3.UP)

func _node_by_id(map_data: MapData, node_id: String) -> NodeData:
	for node in map_data.node_placements:
		if node.node_id == node_id:
			return node
	return null
