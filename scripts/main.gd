extends Node3D

## Fresh Routes -- 3D isometric port of fresh-routes-mvp.html. The world is
## a tile grid (see GameState.grid / SimulationEngine). Routes are drag-only
## (v0.5): press-and-hold on a source node, a built hub, or an unfinished
## (not-yet-established) route tile, drag over empty ground until the path
## reaches a hub, a settlement, or another unfinished route tile, then
## release to build and explicitly connect new tiles -- physical adjacency
## alone never implies a connection (see GameState.connections), a drag that
## doesn't reach a valid end point is rejected, and a drag can never cross or
## reuse an already-built tile along the way, so every committed drag is a
## genuinely complete, freestanding route. An already-established (live,
## delivering) route tile can only ever be reached through its own hub or
## settlement, never picked up again mid-network. Other tools (storage, hub,
## upgrade, bulldoze) remain a single tap on an existing route tile.
## A Small Hub can be built on any existing route tile with the Build Hub
## tool, capped at GameBalance.HUB_CAP_PER_NETWORK per connected road network
## (v0.5 revision -- see SPEC.md §4.4). The Bridge tool likewise converts a
## straight run of route tile into a road-over-road crossing, the one paid
## exception to the never-cross rule: a later drag may run straight over the
## deck without the two routes joining networks (see _do_build_bridge and
## SimulationEngine's lane rules). Hovering (desktop) or tapping (mobile,
## no dialog) any tile or node shows a live info tooltip. A top-left panel
## provides touch zoom/pan controls for exploring the map on mobile.

const REGION_MAP_PATH := "res://data/maps/region_1_map.tres"
const STORAGE_SCENE := preload("res://scenes/markers/storage_marker.tscn")
const HUB_SCENE := preload("res://scenes/markers/hub_marker.tscn")
const FOOD_BUBBLE_SCENE := preload("res://scenes/markers/food_bubble_marker.tscn")

## One symmetric design per route level -- each mesh reads identically under
## any rotation (see generate_blocks.py's build_dirt_road_block/
## build_paved_road_block/build_main_road_block), so the same scene is used
## regardless of a tile's shape (straight or corner) or facing. There is no
## separate corner mesh and no rotation to apply (v0.5 item 23).
const ROUTE_LEVEL_SCENES := {
	"dirt": preload("res://assets/Blocks/glTF/Block_Road_Dirt.glb"),
	"paved": preload("res://assets/Blocks/glTF/Block_Road_Paved.glb"),
	"main": preload("res://assets/Blocks/glTF/Block_Road_Main.glb"),
}
const ROUTE_LEVEL_HEIGHTS := {"dirt": 0.22, "paved": 0.22, "main": 0.24} # must match tools/asset_gen/generate_blocks.py
## Height of the flat slab drawn instead of a road block where a route tile
## crosses the river column (TERR-05's automatic water crossing).
const RIVER_CROSSING_HEIGHT := 0.16

const ROUTE_LEVEL_COLORS := {"dirt": Color("B99A6B"), "paved": Color("9C8F7A"), "main": Color("6E6252")}
const RIVER_BRIDGE_COLOR := Color("8FB9D8")

## ---------- bridge decks ----------
## A bridge tile draws its ordinary road block plus a raised deck slab running
## across it, flanked by two rails. The rails are what make the crossing read as
## a bridge from the fixed isometric camera rather than as a floating slab, and
## the deck sits high enough above the road surface to leave the tile underneath
## clearly visible -- the whole point of the structure is that the player can
## see two roads there, not one.
const BRIDGE_DECK_HEIGHT := 0.62
const BRIDGE_DECK_THICKNESS := 0.14
const BRIDGE_DECK_WIDTH_RATIO := 0.5 # of the tile, across the deck's axis
const BRIDGE_RAIL_HEIGHT := 0.22
const BRIDGE_RAIL_THICKNESS := 0.09
const BRIDGE_DECK_COLOR := Color("C7B79B")
const BRIDGE_RAIL_COLOR := Color("8A7758")
const GRADE_COLORS := {"S": Color("C9A227"), "A": Color("5C8A5C"), "B": Color("5B8FA8"), "C": Color("D98E4A"), "D": Color("C4573A")}
const STORAGE_TOOLS := {"normal": GameEnums.StorageType.NORMAL, "cool": GameEnums.StorageType.COOL}
const ZOOM_MIN := 14.0
const ZOOM_MAX := 60.0
const ZOOM_SPEED := 24.0 # camera.size units/sec while a zoom button is held
const PAN_SPEED := 16.0 # world units/sec at the default zoom level, scales with zoom
const PAN_MAP_MARGIN := 10.0 # world units of empty space pannable past the map edge
const HOLD_TO_DRAG_MSEC := 350 # how long a press must hold still before route drawing switches to drag mode
const TOOL_HINTS := {
	"route": "Press and hold on a source, a built hub, or an unfinished route tile, then drag over empty ground until you reach a hub, a settlement, or another unfinished route tile, and release to commit the whole path. A route can't cross or reuse an already-established tile.",
	"upgrade": "Click a Dirt or Paved route tile to upgrade it, or drag across several to upgrade the whole run at once (all or nothing -- the sweep needs to cover its full cost). Click a food source to expand it for §300 instead: it doubles its daily output, once.",
	"normal": "Click an existing route tile to build Normal Storage there (good for grain, bread).",
	"cool": "Click an existing route tile to build Cool Storage there (good for vegetables, milk).",
	"hubBuild": "Click an existing route tile to build a Small Hub there for §150.",
	"bridgeBuild": "Click a straight run of route tile to build a Bridge over it, so a second route can later cross without joining it. The crossing route still has to be drawn over the top afterwards.",
	"remove": "Click a built tile to bulldoze it, or drag across several to clear them all at once (no refund). A hub, storage or bridge leaves the road it was built on behind, at the level it already was -- clearing that road too is a second click.",
}

## Tools whose action can be swept across many tiles in one drag, rather than
## clicked one tile at a time. Route drawing is NOT one of them -- it traces a
## path with its own start/end rules (see _recompute_drag_validity).
const SWEEP_TOOLS := {"remove": true, "upgrade": true}

@onready var _terrain: TerrainRenderer = $TerrainMap
@onready var _node_spawner: NodeSpawner = $NodeMarkers
@onready var _camera: Camera3D = $Camera3D
@onready var _sun: DirectionalLight3D = $DirectionalLight3D
@onready var _world_environment: WorldEnvironment = $WorldEnvironment

var _map_data: MapData
var _state := GameState.new()
var _tool := "route"
var _nodes_by_pos: Dictionary = {}
var _nodes_by_id: Dictionary = {}
var _grid_visuals: Node3D
var _fx_layer: Node3D

## How much of a node's order book is drawn on the map at rest.
##
## GLYPHS is the default and the reason this enum exists: a full balloon per
## open order buries the map under its own UI once more than a couple are
## open (see the crowding a 5-line City produced). At rest a node now draws a
## compact glyph strip -- one food silhouette per order, each with a status
## mark -- and the balloons come back for whichever node the player is
## hovering or has tapped.
##
## ALL restores the old always-on balloons for every node, because the strip
## trades away the delivered/requested numbers and the freshness bar, and a
## player mid-optimisation may well want those on screen at once. Keeping
## both renderers costs almost nothing: they are the same scene.
enum BubblesMode { GLYPHS, ALL, OFF }
const BUBBLES_MODE_LABELS := {
	BubblesMode.GLYPHS: "Glyphs",
	BubblesMode.ALL: "All",
	BubblesMode.OFF: "Off",
}
var _bubbles_mode: BubblesMode = BubblesMode.GLYPHS
## Which node is showing its full balloons because the pointer is over it (or
## it was tapped). Empty when the pointer is on terrain. Only ever affects
## rendering -- nothing in the simulation knows about it.
var _focused_node_id: String = ""

## Settlements that opened an order this day and should pop their column in
## on the next render (item 57). Consumed by that render and cleared whole,
## so a pop fires exactly once per order and never re-fires on the many
## renders a hover or a build triggers afterwards.
var _pending_pops: Dictionary = {}

## ---------- tile placement pop (item 64) ----------
##
## Which PART of a cell a flourish belongs to. A cell is drawn as up to two
## things -- the road surface, and whatever stands on it -- and only one of
## them is ever the thing that just arrived: a route drag lays a road, while
## building a hub, storage or bridge adds a structure to a road that was
## already there. Popping the road under a new hub would announce something
## that did not change.
enum TilePart { ROAD, STRUCTURE }

## Cells whose newly placed part should pop in on the next render, as
## cell -> {"part": TilePart, "delay": float}. Same contract as _pending_pops
## and for the same reason: _render_grid rebuilds every tile on each hover, day
## and build, so an entry left behind would re-pop the tile every time the
## pointer crossed a node. Filled where the tile is placed, consumed and
## cleared whole by the next render.
##
## The delay is baked in at placement rather than derived at render time: a
## drag places its whole run at once and the stagger has to follow the order
## the player drew, which a Dictionary of cells no longer carries.
var _pending_tile_pops: Dictionary = {}

## True for exactly one render: the one _run_day triggers after simulating.
## A settlement holding a green line hops on that render (item 58). Kept as a
## flag rather than a second pending-set because the green test already exists
## inside _render_settlement_bubbles -- recomputing it here would be a second
## copy of a rule §9 owns, which is how a display starts disagreeing with the
## treasury.
var _day_just_ran := false

## ---------- the red reminder (item 61) ----------
##
## Settlements whose worst open line earned nothing shake again, gently, every
## REMINDER_SEC. Red is the only status worth repeating: amber and green are
## verdicts already delivered and saying them twice adds nothing, while red is
## a standing call to action -- and it is also the resting state of every
## settlement not yet reached, which is exactly the thing a player wants
## pointing at.
##
## Replaying ALL the flourishes on a timer was considered and rejected: at 6
## firings a day across five settlements the shake stops registering as a
## warning within a session, which is item 30's objection almost word for word
## -- a repeated alert is wallpaper.
##
## Timed in REAL seconds, unscaled by DAY_SPEEDS: this is a claim on the
## player's attention rather than an event in the simulation, so it should not
## come three times as often because they set the clock to 4x.
const REMINDER_SEC := 20.0
var _reminder_elapsed := 0.0
## node_id -> its column marker, rebuilt by each render. The reminder shakes
## these directly rather than re-rendering, which would rebuild every visual
## on the map to move five of them.
var _columns_by_node: Dictionary = {}
## Settlements whose worst open line came out red, recorded during the render
## that drew them -- so the reminder never re-derives a status rule §9 owns.
var _nagging_nodes: Array[String] = []

var _funds_label: Label
var _day_label: Label
var _best_grade_label: Label
var _best_score_label: Label
var _avg_score_label: Label
var _hint_label: Label
var _toast: Label
var _bubbles_button: Button
var _tool_buttons: Dictionary = {}
var _clock_day_label: Label
var _clock_time_label: Label
var _clock_bar: ProgressBar
var _clock_mode_label: Label
var _pause_button: Button
var _speed_button: Button
var _auto_button: Button
var _report_button: Button
var _summary_panel: PanelContainer
var _summary_label: RichTextLabel
var _summary_tween: Tween
var _clock_shown_sec := -1
var _last_report: DayReportData
## True while the open report modal is the end-of-day one, whose "Continue"
## rolls the calendar over. Reviewing an already-closed day's report (the
## clock panel's Report button) leaves it false, so closing just dismisses.
var _report_advances_day := false
var _report_overlay: Control
var _report_continue: Button
var _report_sub: Label
var _report_text: RichTextLabel
var _report_banner: Label
var _default_camera_size: float
var _map_bounds_min: Vector2
var _map_bounds_max: Vector2
var _pan_dir := Vector2.ZERO
var _zoom_dir := 0.0

## ---------- route draw: drag-to-build-and-connect only ----------
## v0.5: tile creation is drag-only -- tapping never places a new tile, and
## never does anything else either (the old tap-to-cycle-shape feature is
## retired, v0.5 item 21: a route is built by a drag and a release, full
## stop). Tapping a route tile (or empty ground) with the route tool just
## explains that a drag is needed.
## Connectivity is never implied by adjacency (GameState.connections):
## a press must start ON a source node, a built hub tile, or a route tile
## that ISN'T part of an established route yet, and the drag must end ON a
## hub tile, a settlement node, or likewise an unestablished route tile
## (v0.5 items 18-19, relaxed in item 22) -- an already-established (live,
## delivering) route tile can only ever be reached through its own hub or
## settlement, never picked up again mid-network, while unfinished
## infrastructure that isn't serving any delivery yet can be freely extended
## from or joined to at any of its own tiles. EVERY CELL IN BETWEEN those two
## ends must be empty ground (v0.5 item 20), with exactly one exception: a
## BRIDGE tile may be crossed, and only straight over, along the deck's own
## axis (_crosses_bridge_at). Otherwise a new route can never cross or reuse an
## already-built tile or a different node, it only ever runs over fresh grass.
## A drag can neither start nor stop on a bridge -- a crossing is something a
## route passes over, never somewhere it anchors.
## _process() promotes an eligible press to _drag_active once held past
## HOLD_TO_DRAG_MSEC without releasing. A release before that threshold --
## or a release without ever dragging to a second cell -- is a plain tap on
## the anchor itself: for a node that's the usual info tip, for an existing
## route tile that's just a hint that a drag is needed (see _do_tap_route),
## never a build.
##
## While dragging, nothing is written to _state.grid or .connections:
## _drag_path just records every cell the pointer has crossed (path[0] is
## always the pre-existing anchor), _recompute_drag_validity() re-derives,
## for every consecutive pair, whether the second cell is a genuinely new
## tile to build (_drag_new_cells) and records the pair as a connection to
## make (_drag_new_connections). _update_drag_preview() draws a translucent
## line so the player can see the path (green) or why it's rejected (red,
## for an unaffordable path, an interior cell that isn't empty ground, or an
## end that isn't a hub/settlement) before committing anything. Tiles and
## connections are only written on release, and only if the whole path is
## valid.
var _press_eligible := false
var _press_cell := Vector2i(-1, -1)
var _press_start_msec := 0
var _drag_active := false
var _drag_path: Array[Vector2i] = []
var _drag_new_cells: Array[Vector2i] = []
var _drag_new_connections: Array[Array] = [] # [[Vector2i, Vector2i], ...]
var _drag_valid := true
var _drag_invalid_reason := ""
var _drag_preview_visuals: Node3D

const DRAG_PREVIEW_VALID_COLOR := Color(0.4, 0.85, 0.45, 0.6)
const DRAG_PREVIEW_INVALID_COLOR := Color(0.85, 0.3, 0.3, 0.6)

## ---------- sweep drags (bulldoze / upgrade) ----------
## Bulldoze and Upgrade also work as a drag: sweeping across a run of tiles
## marks every one the pointer crosses and applies the tool to all of them on
## release, instead of demanding one click per tile. Unlike a route drag this
## has no path rules -- the crossed cells are just a set -- so it needs its
## own validity pass and preview (see _recompute_sweep / _commit_sweep).
##
## A sweep starts on press with no hold threshold, unlike the route drag: it
## only ever touches tiles that already exist, nothing is applied until
## release, and the preview shows exactly what will happen first -- so there
## is no accidental-build risk to protect against, and skipping the hold keeps
## the gesture off the mobile long-press that swallows it.
##
## The colour says what the tool will do (red = these get cleared, green =
## these get upgraded); gray means the sweep is blocked and will do nothing,
## which today only happens when an upgrade sweep outruns the treasury.
const SWEEP_REMOVE_COLOR := Color(0.85, 0.3, 0.3, 0.62)
const SWEEP_UPGRADE_COLOR := Color(0.4, 0.85, 0.45, 0.62)
const SWEEP_BLOCKED_COLOR := Color(0.55, 0.58, 0.62, 0.5)
## The line traced through every crossed cell, affected or not, so the gesture
## itself reads even where it passes over empty ground.
const SWEEP_TRACE_COLOR := Color(0.9, 0.93, 0.96, 0.3)

## Which gesture is in progress: "route" for a path-building drag, "sweep" for
## a bulldoze/upgrade sweep, "" when nothing is being dragged.
var _drag_kind := ""
var _sweep_cells: Array[Vector2i] = []
var _sweep_cost := 0.0

## Overlay marking established (source->settlement) routes -- a bright, mostly
## opaque gold line floating just above the road surface (see
## _render_established_routes), with a green arrow at the source end (pointing
## the way delivery actually flows) and a red bar at the settlement end.
const ESTABLISHED_ROUTE_COLOR := Color(1.0, 0.83, 0.29, 0.9)
const ESTABLISHED_START_COLOR := Color("5C8A5C") # matches the "done/fulfilled" green used elsewhere (e.g. settlement tips)
const ESTABLISHED_END_COLOR := Color("C4573A") # matches MarkerColors.SETTLEMENT_COLOR
const ESTABLISHED_ROUTE_Y := 1.55
## Rotation (degrees) that points a +Y-pointing cone toward each cardinal
## grid direction, given world +X = grid east and world +Z = grid south
## (matching how world Z increases with grid Y -- see map_to_local usage).
const ARROW_ROTATION_BY_DIR := {
	Vector2i(1, 0): Vector3(0, 0, -90),  # east
	Vector2i(-1, 0): Vector3(0, 0, 90),  # west
	Vector2i(0, 1): Vector3(90, 0, 0),   # south
	Vector2i(0, -1): Vector3(-90, 0, 0), # north
}

func _ready() -> void:
	# Duplicated because upgrading a source mutates its NodeData (DEV-03), and
	# load() hands back a shared cached resource -- mutating that would leak
	# one run's upgrades into the next, and into the dev checks.
	_map_data = load(REGION_MAP_PATH).duplicate(true)
	_state.balance = GameBalance.STARTING_FUNDS
	for node in _map_data.node_placements:
		_nodes_by_id[node.node_id] = node
	_rebuild_cell_index()
	# Seeds the demand lines the map opens with (DEV-01). Must run before the
	# first _render_grid, since it decides which bubbles exist at all.
	OrderBook.initialize(_state, _map_data)
	_terrain.render(_map_data)
	_node_spawner.spawn(_map_data, _terrain)
	_grid_visuals = Node3D.new()
	_grid_visuals.name = "GridVisuals"
	add_child(_grid_visuals)
	# One-shot effects live outside GridVisuals because _render_grid clears
	# that whole node on every hover, day and build -- a payout label parented
	# there would be destroyed mid-flight the moment the pointer moved. These
	# free themselves when their tween ends.
	_fx_layer = Node3D.new()
	_fx_layer.name = "Effects"
	add_child(_fx_layer)
	_drag_preview_visuals = Node3D.new()
	_drag_preview_visuals.name = "DragPreviewVisuals"
	add_child(_drag_preview_visuals)
	_render_grid()
	_default_camera_size = _camera.size
	var min_corner: Vector3 = _terrain.map_to_local(Vector3i(0, 0, 0))
	var max_corner: Vector3 = _terrain.map_to_local(Vector3i(_map_data.grid_size.x - 1, 0, _map_data.grid_size.y - 1))
	_map_bounds_min = Vector2(min_corner.x, min_corner.z)
	_map_bounds_max = Vector2(max_corner.x, max_corner.z)
	# Shadows are a desktop-only luxury -- see DayCycle.shadows_available().
	_sun.shadow_enabled = DayCycle.shadows_available()
	_apply_day_cycle()
	_build_ui()
	_set_tool("route")
	_update_ui()

func _process(delta: float) -> void:
	if _report_overlay.visible:
		# The report modal holds the whole game -- including the day clock --
		# so a player reading it never loses time off the running day.
		_pan_dir = Vector2.ZERO
		_zoom_dir = 0.0
		return
	_tick_day_clock(delta)
	_tick_reminder(delta)
	if _zoom_dir != 0.0:
		_camera.size = clampf(_camera.size + _zoom_dir * ZOOM_SPEED * delta, ZOOM_MIN, ZOOM_MAX)
	if _pan_dir != Vector2.ZERO:
		var right := _camera.global_transform.basis.x
		var forward := -_camera.global_transform.basis.z
		right.y = 0.0
		forward.y = 0.0
		var speed := PAN_SPEED * (_camera.size / _default_camera_size)
		var offset := (right.normalized() * _pan_dir.x + forward.normalized() * _pan_dir.y) * speed * delta
		var new_pos := _camera.position + offset
		new_pos.x = clampf(new_pos.x, _map_bounds_min.x - PAN_MAP_MARGIN, _map_bounds_max.x + PAN_MAP_MARGIN)
		new_pos.z = clampf(new_pos.z, _map_bounds_min.y - PAN_MAP_MARGIN, _map_bounds_max.y + PAN_MAP_MARGIN)
		_camera.position = new_pos
	if _press_eligible and not _drag_active and Time.get_ticks_msec() - _press_start_msec >= HOLD_TO_DRAG_MSEC:
		_drag_active = true
		_set_focused_node("")
		_drag_path = [_press_cell]
		_recompute_drag_validity()
		_update_drag_preview()

func _unhandled_input(event: InputEvent) -> void:
	if _report_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_press(event.position)
		else:
			_end_press(event.position)
	elif event is InputEventMouseMotion:
		if _drag_active:
			_extend_drag_path(_screen_to_cell(event.position))
		elif not _press_eligible:
			_update_hover(_screen_to_cell(event.position))

func _start_press(screen_position: Vector2) -> void:
	var cell := _screen_to_cell(screen_position)
	_press_cell = cell
	_press_start_msec = Time.get_ticks_msec()
	_drag_active = false
	# A route drag can start FROM a source node, a built hub tile, or a plain
	# route tile that ISN'T part of an established route (v0.5 item 22) --
	# never from empty ground, a settlement, or a route tile that's already
	# live (established_route_cells) -- so an already-delivering route can
	# only ever be extended through its own hub/settlement, while unfinished
	# infrastructure that isn't serving any delivery yet can be picked up and
	# continued from any of its own tiles. The drag can still cross and link
	# to any existing tile/node along the way; only the starting anchor is
	# restricted. Other tools behave exactly as a normal click on release.
	var node := _node_at(cell)
	var cell_data = _state.grid.get(cell)
	_drag_kind = ""
	_press_eligible = _tool == "route" and _cell_in_bounds(cell) and (
		(node != null and node.node_type == GameEnums.NodeType.SOURCE) or
		(cell_data != null and cell_data.kind == "hub") or
		(cell_data != null and cell_data.kind == "route" and not SimulationEngine.is_bridge(_state, cell) and not _established_route_cells().has(cell))
	)
	if _press_eligible:
		_drag_kind = "route"
		return
	# A bulldoze/upgrade sweep begins right away rather than waiting out the
	# hold threshold -- see the SWEEP_* comment block for why that's safe here.
	if SWEEP_TOOLS.has(_tool) and _cell_in_bounds(cell) and node == null:
		_drag_kind = "sweep"
		_drag_active = true
		_set_focused_node("")
		_drag_path = [cell]
		_recompute_sweep()
		_update_drag_preview()

func _end_press(screen_position: Vector2) -> void:
	if _drag_active:
		var kind := _drag_kind
		_drag_active = false
		_press_eligible = false
		_drag_kind = ""
		# A hold-then-release without ever dragging to a second cell is a
		# plain tap on the anchor (info tip for a node, a hint for an existing
		# route tile, the single-tile action for a sweep tool) -- holding
		# still shouldn't behave differently from tapping.
		if _drag_path.size() <= 1:
			_handle_click(_press_cell)
		elif kind == "sweep":
			_commit_sweep()
		else:
			_commit_drag()
		_clear_drag_preview()
		return
	_press_eligible = false
	_handle_click(_screen_to_cell(screen_position), screen_position)

## Grows the in-progress drag path with a newly-entered cell (duplicates of
## the current tail are ignored) and refreshes the preview. A fast drag only
## fires a mouse-motion event every few cells, so the pointer can jump more
## than one cell (or diagonally) between events; we fill in every orthogonal
## cell between the previous tail and the new one so the recorded path is
## always a continuous, orthogonally-connected line -- otherwise the skipped
## middle cells never get built and the route comes out with holes in it.
## Nothing is written to _state.grid here -- see the class-level comment above
## _press_eligible for why the whole path is only committed on release.
func _extend_drag_path(cell: Vector2i) -> void:
	if not _cell_in_bounds(cell) or (not _drag_path.is_empty() and _drag_path[-1] == cell):
		return
	if _drag_path.is_empty():
		_drag_path.append(cell)
	else:
		for step in _cells_between(_drag_path[-1], cell):
			_drag_path.append(step)
	if _drag_kind == "sweep":
		_recompute_sweep()
	else:
		_recompute_drag_validity()
	_update_drag_preview()

## The orthogonally-connected cells from `a` (exclusive) to `b` (inclusive):
## each returned cell is one grid step from the previous, so a jump of any
## length or direction is expanded into a gap-free line. Steps along the
## larger remaining axis first, matching how a finger usually traces a path.
func _cells_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var current := a
	while current != b:
		var dx := b.x - current.x
		var dy := b.y - current.y
		if absi(dx) >= absi(dy):
			current.x += signi(dx)
		else:
			current.y += signi(dy)
		result.append(current)
	return result

## Re-derives, from scratch, which consecutive pairs in _drag_path are new
## connections to make (_drag_new_connections) and which of their second
## cells are genuinely new tiles to build (_drag_new_cells), plus whether the
## whole path is affordable and properly bounded. path[0] is always a
## pre-existing anchor (see _start_press) and the last cell must likewise be
## pre-existing -- a hub, a settlement, or an unestablished route tile (see
## the end-point check below) -- every cell STRICTLY BETWEEN those two ends
## must be empty ground (v0.5 item 20): a new route can never cross or reuse
## an already-built tile, it only ever runs over fresh grass from its start
## anchor to its end anchor. This is what "every new route sits on a grass
## area" means -- two routes can only ever share infrastructure at an END,
## never a tile in the middle, so there's no way for a new drag to silently
## piggyback on infrastructure that already exists. An established (live,
## delivering) route tile is never a valid end, only its own hub/settlement
## is (v0.5 item 22). Runs against a scratch grid copy -- _state.grid/
## .connections are never touched here.
func _recompute_drag_validity() -> void:
	_drag_valid = true
	_drag_invalid_reason = ""
	_drag_new_cells.clear()
	_drag_new_connections.clear()
	var newly_built: Dictionary = {} # cells this same drag has already queued
	var total_cost := 0.0
	var last_index := _drag_path.size() - 1
	for i in range(1, _drag_path.size()):
		var prev: Vector2i = _drag_path[i - 1]
		var cell: Vector2i = _drag_path[i]
		if prev == cell:
			continue
		_drag_new_connections.append([prev, cell])
		if newly_built.has(cell):
			continue
		var pre_existing: bool = _node_at(cell) != null or _state.grid.has(cell)
		if pre_existing:
			if i == last_index or _crosses_bridge_at(i):
				continue
			if _drag_invalid_reason == "":
				_drag_valid = false
				_drag_invalid_reason = ("A bridge can only be crossed straight over, along the deck." if SimulationEngine.is_bridge(_state, cell)
					else "A new route can't cross or reuse an existing tile or node -- it can only run over empty ground between its two ends, or straight over a bridge.")
			continue
		total_cost += SimulationEngine.route_build_cost(cell, _map_data)
		newly_built[cell] = true
		_drag_new_cells.append(cell)
	if not _drag_valid:
		return
	if total_cost > _state.balance:
		_drag_valid = false
		_drag_invalid_reason = "Not enough treasury for the whole path (§%d needed)." % roundi(total_cost)
		return
	# A drag must end at a hub, a settlement, or a plain route tile that ISN'T
	# part of an established route yet (v0.5 items 19/22) -- this guarantees a
	# completed drag either reaches a genuine delivery destination, or joins
	# onto unfinished infrastructure that isn't serving any delivery yet.
	# An already-established route tile can only ever be reached through its
	# own hub or settlement, never picked up again mid-network.
	var end_cell: Vector2i = _drag_path[-1]
	var end_node := _node_at(end_cell)
	var end_cell_data = _state.grid.get(end_cell)
	var ends_at_hub: bool = end_cell_data != null and end_cell_data.kind == "hub"
	var ends_at_settlement: bool = end_node != null and end_node.node_type == GameEnums.NodeType.SETTLEMENT
	var ends_at_bridge: bool = SimulationEngine.is_bridge(_state, end_cell)
	var ends_at_unestablished_route: bool = end_cell_data != null and end_cell_data.kind == "route" and not ends_at_bridge and not _established_route_cells().has(end_cell)
	if not (ends_at_hub or ends_at_settlement or ends_at_unestablished_route):
		_drag_valid = false
		# Stopping ON a deck would leave a route hanging in mid-air over
		# somebody else's road, which is exactly the mess bridges are meant to
		# avoid -- a crossing is something you pass over, not somewhere you park.
		_drag_invalid_reason = ("A route can't stop on a bridge -- carry straight over and land on the far side."
			if ends_at_bridge
			else "A route must end at a hub, a settlement, or an unfinished route tile.")

## Whether _drag_path[i] is a bridge tile the drag is legitimately crossing:
## the one and only case where a route may run over a cell that already exists.
## It has to be a genuine crossing -- entered and left in the same direction,
## along the deck's own axis -- so a drag can neither turn a corner on top of
## somebody else's road nor sneak along the road underneath.
func _crosses_bridge_at(i: int) -> bool:
	var cell: Vector2i = _drag_path[i]
	if not SimulationEngine.is_bridge(_state, cell) or i + 1 >= _drag_path.size():
		return false
	var incoming: Vector2i = cell - _drag_path[i - 1]
	var outgoing: Vector2i = _drag_path[i + 1] - cell
	if incoming != outgoing:
		return false
	var axis := SimulationEngine.bridge_axis(_state, cell)
	return (axis.x != 0) == (incoming.x != 0)

## Writes every queued new tile and connection from a valid drag path in one
## batch, then runs the usual post-build pass once for the whole gesture
## (hub formation, re-render -- which recomputes each tile's shape from its
## final real connections, so the path renders with correct shapes exactly as
## if each tile had been dragged individually). An invalid path, or one with
## nothing new to build or connect, does nothing at all.
func _commit_drag() -> void:
	if not _drag_valid:
		_show_toast(_drag_invalid_reason if _drag_invalid_reason != "" else "That path is invalid -- nothing built.", true)
		return
	if _drag_new_cells.is_empty() and _drag_new_connections.is_empty():
		_show_toast("Nothing new to build or connect along that path.", true)
		return
	for cell in _drag_new_cells:
		_state.balance -= SimulationEngine.route_build_cost(cell, _map_data)
		_state.grid[cell] = {"kind": "route", "level": "dirt"}
	_arm_placement_pops(_drag_new_cells)
	for pair in _drag_new_connections:
		_state.add_connection(pair[0], pair[1])
	var parts: Array[String] = []
	if not _drag_new_cells.is_empty():
		parts.append("%d new tile%s" % [_drag_new_cells.size(), "" if _drag_new_cells.size() == 1 else "s"])
	if not _drag_new_connections.is_empty():
		parts.append("%d connection%s" % [_drag_new_connections.size(), "" if _drag_new_connections.size() == 1 else "s"])
	_show_toast("Built %s." % " and ".join(parts))
	_after_action()

## ---------- sweep drags: bulldoze / upgrade over a run of tiles ----------

## Re-derives which of the crossed cells the active sweep tool would actually
## act on (_sweep_cells) and what that costs. Cells the tool can't touch --
## empty ground, or a route already at Main for the upgrade tool -- are simply
## skipped rather than failing the sweep, so a slightly wobbly drag across a
## road still does the obvious thing. Only affordability can invalidate a
## sweep, and only for upgrades.
func _recompute_sweep() -> void:
	_sweep_cells.clear()
	_sweep_cost = 0.0
	_drag_valid = true
	_drag_invalid_reason = ""
	var seen: Dictionary = {}
	for cell in _drag_path:
		if seen.has(cell):
			continue
		seen[cell] = true
		var cell_data = _state.grid.get(cell)
		if cell_data == null:
			continue
		if _tool == "remove":
			_sweep_cells.append(cell)
		elif _tool == "upgrade" and cell_data.kind == "route":
			var lvl = GameBalance.ROUTE_LEVELS[cell_data.level]
			if lvl.next == "":
				continue
			_sweep_cells.append(cell)
			_sweep_cost += lvl.upgrade_cost
	# All-or-nothing, matching the route drag: a sweep that outruns the
	# treasury applies to nothing at all, and says so before release by
	# turning gray. Shortening the sweep is the fix.
	if _sweep_cost > _state.balance:
		_drag_valid = false
		_drag_invalid_reason = "Not enough treasury to upgrade all %d tiles (§%d needed)." % [_sweep_cells.size(), roundi(_sweep_cost)]

## Applies the sweep tool to every marked tile in one batch, then runs the
## usual post-action pass once for the whole gesture. An unaffordable sweep,
## or one that crossed nothing the tool can act on, does nothing at all.
func _commit_sweep() -> void:
	if not _drag_valid:
		_show_toast(_drag_invalid_reason, true)
		return
	if _sweep_cells.is_empty():
		_show_toast("Nothing to %s along that sweep." % ("clear" if _tool == "remove" else "upgrade"), true)
		return
	var count := _sweep_cells.size()
	var plural := "" if count == 1 else "s"
	if _tool == "remove":
		# Same rule as a single bulldoze (see _clear_cell): a swept hub,
		# storage or bridge leaves its road behind rather than taking it with it.
		var kept := 0
		# Staggered along the sweep exactly as a route drag pops along its run:
		# the two are the same gesture and should read as each other's inverse.
		var stagger: float = minf(TILE_POP_STAGGER, TILE_POP_STAGGER_BUDGET / float(maxi(count, 1)))
		for i in _sweep_cells.size():
			var cell: Vector2i = _sweep_cells[i]
			_spawn_removal_ghost(cell, _state.grid[cell], i * stagger)
			if _clear_cell(cell) != "tile":
				kept += 1
		if kept > 0:
			_show_toast("Cleared %d tile%s -- %d left as road." % [count, plural, kept])
		else:
			_show_toast("Cleared %d tile%s." % [count, plural])
	else:
		for cell in _sweep_cells:
			var cell_data = _state.grid[cell]
			var lvl = GameBalance.ROUTE_LEVELS[cell_data.level]
			_state.balance -= lvl.upgrade_cost
			cell_data.level = lvl.next
		_show_toast("Upgraded %d tile%s for §%d." % [count, plural, roundi(_sweep_cost)])
	_after_action()

## The crossed cells traced as a faint line (so the gesture reads even over
## empty ground), with a solid marker on every tile the tool will actually
## act on -- red for a bulldoze sweep, green for an upgrade, gray when the
## sweep is blocked and will do nothing.
func _update_sweep_preview() -> void:
	var world_positions: Array[Vector3] = []
	for cell in _drag_path:
		world_positions.append(_terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, 1.3, 0))
	for i in range(1, world_positions.size()):
		_add_drag_segment(world_positions[i - 1], world_positions[i], SWEEP_TRACE_COLOR)
	var color := SWEEP_BLOCKED_COLOR
	if _drag_valid:
		color = SWEEP_REMOVE_COLOR if _tool == "remove" else SWEEP_UPGRADE_COLOR
	for cell in _sweep_cells:
		_add_drag_marker(_terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, 1.3, 0), color)

func _clear_drag_preview() -> void:
	_clear_children(_drag_preview_visuals)
	_drag_path.clear()
	_drag_new_cells.clear()
	_drag_new_connections.clear()
	_sweep_cells.clear()
	_sweep_cost = 0.0

## Translucent green (valid) or red (invalid) boxes on every crossed cell,
## connected by thin bars between orthogonal neighbors, so the path reads
## as a continuous line rather than disconnected dots. Purely visual --
## _state.grid isn't touched until _commit_drag().
func _update_drag_preview() -> void:
	_clear_children(_drag_preview_visuals)
	if _drag_kind == "sweep":
		_update_sweep_preview()
		return
	var color := DRAG_PREVIEW_VALID_COLOR if _drag_valid else DRAG_PREVIEW_INVALID_COLOR
	var world_positions: Array[Vector3] = []
	for cell in _drag_path:
		world_positions.append(_terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, 1.3, 0))
	for i in range(world_positions.size()):
		_add_drag_marker(world_positions[i], color)
		if i > 0:
			_add_drag_segment(world_positions[i - 1], world_positions[i], color)

func _add_drag_marker(pos: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.14, 0.5)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _drag_preview_material(color)
	_drag_preview_visuals.add_child(mesh_instance)

## `a` and `b` are always orthogonal neighbors (one grid step apart), so the
## connecting bar is always axis-aligned and needs no rotation.
func _add_drag_segment(a: Vector3, b: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var diff := b - a
	mesh.size = Vector3(absf(diff.x) + 0.3, 0.1, absf(diff.z) + 0.3) if absf(diff.x) > absf(diff.z) else Vector3(0.3, 0.1, absf(diff.z) + 0.3)
	mesh_instance.mesh = mesh
	mesh_instance.position = (a + b) * 0.5
	mesh_instance.material_override = _drag_preview_material(color)
	_drag_preview_visuals.add_child(mesh_instance)

func _drag_preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

## A small gold node dot for the established-route overlay. Added to
## _grid_visuals so it's cleared and rebuilt on every _render_grid.
func _add_established_marker(pos: Vector3, color: Color = ESTABLISHED_ROUTE_COLOR) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.1, 0.34)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _drag_preview_material(color)
	_grid_visuals.add_child(mesh_instance)

## A thin bar joining two adjacent established points (tile-tile or
## tile-node); `a` and `b` are one grid step apart, so it's axis-aligned.
## Gold by default; the settlement end of a route uses ESTABLISHED_END_COLOR
## instead (see _render_established_routes).
func _add_established_segment(a: Vector3, b: Vector3, color: Color = ESTABLISHED_ROUTE_COLOR) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var diff := b - a
	mesh.size = Vector3(absf(diff.x) + 0.18, 0.08, absf(diff.z) + 0.18) if absf(diff.x) > absf(diff.z) else Vector3(0.18, 0.08, absf(diff.z) + 0.18)
	mesh_instance.mesh = mesh
	mesh_instance.position = (a + b) * 0.5
	mesh_instance.material_override = _drag_preview_material(color)
	_grid_visuals.add_child(mesh_instance)

## A green cone arrow marking where an established route begins at a source,
## pointing in the direction delivery actually flows (source -> first tile).
## Positioned at the midpoint of the source<->tile link, same spot a plain
## established_segment bar would sit, so it reads as replacing that bar with
## a directional marker rather than adding a separate decoration.
func _add_established_start_arrow(pos: Vector3, flow_dir: Vector2i) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.22
	mesh.height = 0.5
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = ARROW_ROTATION_BY_DIR.get(flow_dir, Vector3.ZERO)
	mesh_instance.material_override = _drag_preview_material(ESTABLISHED_START_COLOR)
	_grid_visuals.add_child(mesh_instance)

## Rebuilds the cell -> node lookup. Run at load; footprints are fixed, so
## nothing during a run invalidates it.
##
## `_nodes_by_pos` holds one entry per OCCUPIED cell (DEV-02). Everything that
## asks "is there a node at this cell" -- hit-testing, build guards, the
## established-route overlay, the engine's never-transit-a-node rule --
## resolves through it, so a multi-tile node needs no special case anywhere
## that works in cells. Anything that iterates NODES must iterate
## `_nodes_by_id`, or a 2x2 City gets processed four times.
func _rebuild_cell_index() -> void:
	_nodes_by_pos.clear()
	for node_id in _nodes_by_id:
		var node: NodeData = _nodes_by_id[node_id]
		for cell in node.cells():
			_nodes_by_pos[cell] = node

func _handle_click(cell: Vector2i, screen_position := Vector2.ZERO) -> void:
	if not _cell_in_bounds(cell):
		return
	var n := _node_at(cell)
	if n:
		# The Upgrade tool is the one tool that does anything to a node: it
		# widens a source and doubles its output (DEV-03). This is not the
		# discoverability trap the old tap-to-accept offer was -- there the
		# tap was passive and unprompted, here the player has already picked
		# a tool that says "upgrade what I touch".
		if _tool == "upgrade" and n.node_type == GameEnums.NodeType.SOURCE:
			_do_upgrade_source(n)
			return
		# Otherwise sources and settlements are informational, not buildable
		# -- tapping (mobile has no hover) focuses the node exactly as a mouse
		# hover does, expanding a settlement's column into its full rows.
		# Nothing on the map ever needs a tap to advance the game: orders
		# open themselves as deliveries land (DEV-01).
		_update_hover(cell)
		return
	_set_focused_node("")
	match _tool:
		"route":
			_do_tap_route(cell)
		"upgrade":
			_do_upgrade_route(cell)
		"normal", "cool":
			_do_build_storage(cell)
		"hubBuild":
			_do_build_hub(cell)
		"bridgeBuild":
			_do_build_bridge(cell)
		"remove":
			_do_bulldoze(cell)
	_after_action()

## A plain tap (no drag) with the route tool never does anything -- a route
## is built by a drag and a release, full stop (v0.5 item 21 retires the old
## tap-to-cycle-shape feature). Tapping just explains that a drag is needed,
## whether the cell is empty ground or an already-built tile.
func _do_tap_route(cell: Vector2i) -> void:
	if not _state.grid.has(cell):
		_show_toast("Press and hold on a source, a built hub, or an unfinished route tile, then drag here to build and connect a new one.", true)
		return
	_show_toast("Already built here. Press and hold on a source, a built hub, or an unfinished route tile, then drag to build or link a new route.", true)

func _do_upgrade_route(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "route":
		_show_toast("Select a route tile to upgrade.", true)
		return
	var lvl = GameBalance.ROUTE_LEVELS[cell_data.level]
	if lvl.next == "":
		_show_toast("Already at maximum level (Main).", true)
		return
	var cost: float = lvl.upgrade_cost
	if _state.balance < cost:
		_show_toast("Not enough treasury (§%d needed)." % roundi(cost), true)
		return
	_state.balance -= cost
	cell_data.level = lvl.next
	_show_toast("Upgraded to %s for §%d." % [GameBalance.ROUTE_LEVELS[cell_data.level].label, roundi(cost)])

## Doubles a source's daily output (DEV-03). The footprint does not change --
## a source already stands on its full 2x1 -- so the only thing this can fail
## for is money.
##
## Mutates the NodeData, which is safe because Main duplicates the map
## resource at load; the engine reads supply straight off `produces`, so the
## bigger output is live on the next simulated day with nothing to thread
## through, and the source's own bubble reads "0/180" instead of "0/90" as
## soon as the grid re-renders.
func _do_upgrade_source(n: NodeData) -> void:
	if not n.can_upgrade():
		_show_toast("%s is already expanded." % n.display_name, true)
		return
	var cost := GameBalance.SOURCE_UPGRADE_COST
	if _state.balance < cost:
		_show_toast("Not enough treasury to expand %s (§%d needed)." % [n.display_name, roundi(cost)], true)
		return

	_state.balance -= cost
	n.upgraded = true
	var gained := []
	for food_id in n.produces:
		n.produces[food_id] *= GameBalance.SOURCE_UPGRADE_SUPPLY_MULT
		gained.append("%s %d/day" % [GameBalance.food_types()[food_id].display_name, roundi(n.produces[food_id])])

	_render_grid()
	_update_ui()
	_show_toast("%s expanded for §%d — now %s." % [n.display_name, roundi(cost), ", ".join(gained)])

func _do_build_storage(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "route":
		_show_toast("Storage must be built on an existing route tile.", true)
		return
	if SimulationEngine.is_bridge(_state, cell):
		_show_toast("A bridge tile already carries two roads -- there's no room to build on it.", true)
		return
	var stype: GameEnums.StorageType = STORAGE_TOOLS[_tool]
	var st = GameBalance.STORAGE_TYPES[stype]
	if _state.balance < st.build:
		_show_toast("Not enough treasury (§%d needed)." % roundi(st.build), true)
		return
	_state.balance -= st.build
	# `level` is the road UNDERNEATH, carried along so the tile can be drawn
	# under the building and handed back when it's bulldozed -- same contract as
	# a hub cell (_do_build_hub, _clear_cell). Nothing dispatches on it while the
	# cell is storage; every consumer switches on `kind`.
	_state.grid[cell] = {"kind": "storage", "stype": stype, "level": cell_data.level}
	# The marker alone: the road it stands on was already built and paid for.
	_pending_tile_pops[cell] = {"part": TilePart.STRUCTURE, "delay": 0.0}
	_show_toast("%s built for §%d." % [st.name, roundi(st.build)])

## Any built route tile can become a Small Hub -- the player draws a route
## first, then picks the Build Hub tool and clicks the tile they want to
## convert (v0.5 revision: no more "must be a completed-route fork" gate).
## The per-network hub cap (GameBalance.HUB_CAP_PER_NETWORK) still applies,
## checked live against the tile's connected road network rather than a
## precomputed per-cell flag.
func _do_build_hub(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "route":
		_show_toast("Select a route tile to build a hub.", true)
		return
	if SimulationEngine.is_bridge(_state, cell):
		_show_toast("A bridge tile already carries two roads -- there's no room to build on it.", true)
		return
	if SimulationEngine.network_at_hub_cap(_state, cell):
		_show_toast("This road already has %d hub%s -- the cap is reached." % [GameBalance.HUB_CAP_PER_NETWORK, "" if GameBalance.HUB_CAP_PER_NETWORK == 1 else "s"], true)
		return
	var cost: float = GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build
	if _state.balance < cost:
		_show_toast("Not enough treasury (§%d needed)." % roundi(cost), true)
		return
	_state.balance -= cost
	# `level` is the road UNDERNEATH, carried along so bulldozing the hub can
	# hand it back (see _clear_cell). Nothing dispatches on it while the cell is
	# a hub -- every consumer switches on `kind` -- it is purely a memory of
	# what the player paved before building here.
	_state.grid[cell] = {"kind": "hub", "htype": GameEnums.HubType.SMALL, "level": cell_data.level}
	_pending_tile_pops[cell] = {"part": TilePart.STRUCTURE, "delay": 0.0}
	_show_toast("Small Hub built for §%d." % roundi(cost))

## Turns one existing route tile into a road-over-road crossing: the road
## already there keeps running underneath, and a raised deck across it lets a
## SECOND route be drawn straight over without the two ever joining networks
## (SimulationEngine's lane rules do the actual separating; this only places the
## structure and records the deck's axis).
##
## It is the single, deliberate, paid exception to "a new route can never cross
## an existing tile", so the gate is deliberately narrow -- the tile must be a
## plain straight through-run of road with room to land on both sides, no two
## bridges may touch, and a connected road network only ever supports
## GameBalance.BRIDGE_CAP_PER_NETWORK of them. Between that, the build cost up
## front and the deck's extra freshness cost, going around stays the right
## answer most of the time -- which is what keeps the map from filling up with
## interchanges.
func _do_build_bridge(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "route":
		_show_toast("A bridge must be built on an existing route tile.", true)
		return
	if SimulationEngine.is_bridge(_state, cell):
		_show_toast("There's already a bridge here.", true)
		return
	if _map_data.is_river(cell.x, cell.y):
		_show_toast("This tile already bridges the river -- a second deck can't be stacked on it.", true)
		return
	var axis := _deck_axis_for(cell)
	if axis == Vector2i.ZERO:
		_show_toast("A bridge needs a straight run of road to cross -- pick a tile with road connected on exactly two opposite sides.", true)
		return
	for step in [axis, -axis]:
		var landing: Vector2i = cell + step
		if not _cell_in_bounds(landing):
			_show_toast("A bridge needs room to land on both sides -- this one would run off the map.", true)
			return
		if _node_at(landing) != null:
			_show_toast("A bridge can't land on a source or settlement -- a delivery never passes through one.", true)
			return
		if SimulationEngine.is_bridge(_state, landing):
			_show_toast("Bridges can't sit side by side -- leave at least a tile of open road between them.", true)
			return
	if SimulationEngine.network_at_bridge_cap(_state, cell):
		_show_toast("This road network already has %d bridge%s -- the cap is reached." % [GameBalance.BRIDGE_CAP_PER_NETWORK, "" if GameBalance.BRIDGE_CAP_PER_NETWORK == 1 else "s"], true)
		return
	var cost: float = GameBalance.BRIDGE_BUILD_COST
	if _state.balance < cost:
		_show_toast("Not enough treasury (§%d needed)." % roundi(cost), true)
		return
	_state.balance -= cost
	cell_data["bridge_axis"] = axis
	# The deck alone, for the same reason a hub pops only its marker: the road
	# it crosses is the one that was already there, and stays.
	_pending_tile_pops[cell] = {"part": TilePart.STRUCTURE, "delay": 0.0}
	_show_toast("Bridge built for §%d -- draw a route straight over it to cross without joining the road below." % roundi(cost))

## The axis a bridge deck would run along at `cell`: across the road already
## there, so the deck is perpendicular to it. Only a straight through-run
## qualifies -- exactly two connections, pointing opposite ways -- which keeps
## bridges off corners, forks and dead ends, where "across" wouldn't mean
## anything and the result would read as a knot rather than a crossing.
## Vector2i.ZERO when the tile doesn't qualify.
func _deck_axis_for(cell: Vector2i) -> Vector2i:
	var links: Array[Vector2i] = []
	for d in DIRECTIONS:
		if _state.has_connection(cell, cell + d):
			links.append(d)
	if links.size() != 2 or links[0] != -links[1]:
		return Vector2i.ZERO
	return Vector2i(0, 1) if links[0].x != 0 else Vector2i(1, 0)

## Bulldozes one cell, and the rule depends on what's there. A hub, a storage
## building and a bridge are all things built ON TOP of an existing route tile,
## so removing one takes the structure away and hands back the road it was built
## on -- at the level that road was, not reset to dirt: the player paid for that
## paving separately and never asked to lose it. Clearing the road outright
## would additionally split the network in half. Only a plain route tile, with
## nothing standing on it, is removed outright, connections and all.
##
## So clearing a built-up tile takes two bulldozes: one to take the building
## off, one to take the road away. That's the point -- it makes removing a
## building a different act from removing the road, instead of one click
## silently doing both.
##
## A bridge additionally drops its DECK connections while keeping the road
## beneath it: the deck is the road that ceases to exist. Without that the two
## roads the crossing was deliberately keeping apart would silently merge into
## one network the moment it came down -- the exact opposite of what the player
## built it for.
##
## Returns "" when there was nothing there, "tile" when the cell itself was
## removed, and otherwise "<structure>|<level>" -- what came off and what road
## was handed back -- so the caller can say so.
func _clear_cell(cell: Vector2i) -> String:
	var cell_data = _state.grid.get(cell)
	if cell_data == null:
		return ""
	# A bridge tile IS a route tile (it kept its own level all along), so the
	# road comes back simply by dropping the deck.
	if SimulationEngine.is_bridge(_state, cell):
		var axis: Vector2i = cell_data.bridge_axis
		for step in [axis, -axis]:
			_state.remove_connection(cell, cell + step)
		cell_data.erase("bridge_axis")
		return "bridge|%s" % cell_data.level
	if cell_data.kind == "hub" or cell_data.kind == "storage":
		# A hub/storage cell replaced the route cell outright, so the level it
		# covered is the one recorded at build time (_do_build_hub /
		# _do_build_storage).
		var level: String = cell_data.get("level", "dirt")
		var structure: String = cell_data.kind
		_state.grid[cell] = {"kind": "route", "level": level}
		return "%s|%s" % [structure, level]
	_state.grid.erase(cell)
	_state.remove_connections(cell)
	return "tile"

func _do_bulldoze(cell: Vector2i) -> void:
	if not _state.grid.has(cell):
		_show_toast("Nothing to remove here.", true)
		return
	_spawn_removal_ghost(cell, _state.grid[cell], 0.0)
	var cleared := _clear_cell(cell).split("|")
	match cleared[0]:
		"bridge":
			_show_toast("Bridge removed. The road it crossed stays as %s route; the route that ran over it is cut." % GameBalance.ROUTE_LEVELS[cleared[1]].label)
		"hub":
			_show_toast("Hub removed. The tile stays as %s route." % GameBalance.ROUTE_LEVELS[cleared[1]].label)
		"storage":
			_show_toast("Storage removed. The tile stays as %s route." % GameBalance.ROUTE_LEVELS[cleared[1]].label)
		_:
			_show_toast("Tile cleared.")

func _after_action() -> void:
	_render_grid()
	_update_ui()

## ---------- auto-run day clock (LOOP-07) ----------
##
## The day is on a real-time countdown rather than a button: the player keeps
## building while the top-right clock drains, and when it reaches zero the day
## simulates itself, the calendar rolls over, and the clock restarts -- so the
## build/simulate loop never stops for a click. Because that loop can't afford
## a modal every day, an auto-run day reports through a small, non-blocking
## summary card instead (the full report stays one Report-button click away,
## and opening it freezes the clock via _process's early return).
##
## Turning Auto off restores the manual loop exactly: the clock stops, nothing
## runs on its own, and "Run Day Now" opens the blocking end-of-day report
## whose Continue button advances the day.

## Drains the current day and simulates it when it runs out. Called once per
## frame from _process, which is already skipped while the report modal is
## open, so the clock only ticks during actual play.
func _tick_day_clock(delta: float) -> void:
	if not _state.auto_run or _state.clock_paused:
		return
	_state.day_time_left -= delta * GameBalance.DAY_SPEEDS[_state.speed_index]
	if _state.day_time_left <= 0.0:
		_run_day()
	_apply_day_cycle()
	_update_clock_ui()

## Nudges every still-unpaid settlement, on the same guard as the day clock:
## a stopped clock means the game is not running, and nagging a player who has
## deliberately paused is just pestering.
func _tick_reminder(delta: float) -> void:
	if not _state.auto_run or _state.clock_paused or _bubbles_mode == BubblesMode.OFF:
		return
	_reminder_elapsed += delta
	if _reminder_elapsed < REMINDER_SEC:
		return
	_reminder_elapsed = 0.0
	for node_id in _nagging_nodes:
		var column = _columns_by_node.get(node_id)
		if is_instance_valid(column):
			column.play(FoodBubbleMarker.Flourish.NAG)

## ---------- time-of-day lighting (LOOP-08) ----------

## How far through the current day the clock is, 0 at its start and 1 as it
## rolls over -- the sun cycle's phase (see DayCycle). A stopped clock
## (paused, or manual mode) holds the light where it is, which is the point:
## time of day is the day clock, so freezing one freezes the other.
func _day_phase() -> float:
	return clampf(1.0 - _state.day_time_left / GameBalance.DAY_LENGTH_SEC, 0.0, 1.0)

func _apply_day_cycle() -> void:
	DayCycle.apply(_day_phase(), _sun, _world_environment.environment)

## Simulates one day, from either the clock hitting zero or the player asking
## for it early. Always restarts the clock, so an early run costs the rest of
## the day's build time rather than banking it.
func _run_day() -> void:
	var report := SimulationEngine.run_day(_state, _map_data.node_placements)
	_last_report = report
	# Latches whatever the day just filled and opens the next order for each
	# one (DEV-01). Deliberately not tied to the calendar rollover below:
	# delivering is what advances the region, so the new order lands the
	# moment the delivery does.
	for order in OrderBook.record_day(_state, _map_data, _map_data.node_placements):
		_announce_order(order)
		# Popped on the _render_grid at the end of this function, which is the
		# first render that will actually draw the new chip.
		_pending_pops[order.get("node_id", "")] = true
	_state.day_time_left = GameBalance.DAY_LENGTH_SEC
	_clock_shown_sec = -1
	if _state.auto_run:
		_advance_day()
		_show_day_summary(report)
	else:
		_report_advances_day = true
		_show_report(report)
	_day_just_ran = true
	_render_grid()
	_update_ui()

## Rolls the calendar over. Nothing about the order book happens here any
## more: progression answers to deliveries, not to the date (DEV-01). The day
## counter still drives the clock, the sun cycle and the report.
func _advance_day() -> void:
	_state.day += 1

func _announce_order(order: Dictionary) -> void:
	var settlement: NodeData = _nodes_by_id.get(order.get("node_id", ""))
	var food: FoodData = GameBalance.food_types().get(order.get("food_id", ""))
	if settlement == null or food == null:
		return
	_show_toast("New order — %s wants %s, %d/day." % [
		settlement.display_name,
		food.display_name,
		roundi(settlement.demand.get(order.get("food_id", ""), 0.0)),
	])

func _close_report() -> void:
	_report_overlay.visible = false
	if _report_advances_day:
		_report_advances_day = false
		_advance_day()
	_update_ui()

## Reopens the last simulated day's full report for review. The day has
## already rolled over by then, so closing it must not advance again.
func _review_report() -> void:
	if _last_report == null:
		return
	_report_advances_day = false
	_show_report(_last_report)

func _toggle_pause() -> void:
	if not _state.auto_run:
		return
	_state.clock_paused = not _state.clock_paused
	_update_clock_ui()

func _toggle_auto_run(pressed: bool) -> void:
	_state.auto_run = pressed
	# Leaving manual mode shouldn't drop the player straight into an
	# already-expired day, and a paused hold is meaningless once the clock is
	# stopped, so both reset on the way in and out.
	_state.clock_paused = false
	_state.day_time_left = GameBalance.DAY_LENGTH_SEC
	_clock_shown_sec = -1
	_update_clock_ui()
	_show_toast("Auto-run on -- the day advances by itself." if pressed else "Auto-run off -- run each day yourself.")

func _cycle_speed() -> void:
	_state.speed_index = (_state.speed_index + 1) % GameBalance.DAY_SPEEDS.size()
	_update_clock_ui()

func _update_clock_ui() -> void:
	if _clock_time_label == null:
		return
	var phase := _day_phase()
	_clock_day_label.text = "Day %d · %s" % [_state.day, DayCycle.clock_text(phase)]
	var remaining: float = maxf(_state.day_time_left, 0.0)
	# Only rewrite the countdown when the displayed second actually changes.
	var whole_sec := ceili(remaining)
	if whole_sec != _clock_shown_sec:
		_clock_shown_sec = whole_sec
		_clock_time_label.text = "%d:%02d" % [whole_sec / 60, whole_sec % 60]
	_clock_time_label.add_theme_color_override("font_color", _clock_color(remaining))
	_clock_bar.value = remaining / GameBalance.DAY_LENGTH_SEC * 100.0
	_pause_button.text = "Resume ▸" if _state.clock_paused else "Pause ||"
	_pause_button.disabled = not _state.auto_run
	_speed_button.text = GameBalance.DAY_SPEED_LABELS[_state.speed_index]
	_speed_button.disabled = not _state.auto_run
	_report_button.disabled = _last_report == null
	if not _state.auto_run:
		_clock_mode_label.text = "%s · manual -- run the day yourself" % DayCycle.label(phase)
	elif _state.clock_paused:
		_clock_mode_label.text = "%s · paused -- space or Resume" % DayCycle.label(phase)
	else:
		_clock_mode_label.text = "%s · day runs itself at 0:00" % DayCycle.label(phase)

func _clock_color(remaining: float) -> Color:
	if not _state.auto_run or _state.clock_paused:
		return Color("8FA3AD")
	if remaining <= GameBalance.DAY_CLOCK_URGENT_SEC:
		return Color("C4573A")
	if remaining <= GameBalance.DAY_CLOCK_WARN_SEC:
		return Color("D98E4A")
	return Color("EAF4EF")

## The auto-run loop's stand-in for the report modal: a compact card under the
## clock with the day's grade, profit and freshness, which fades on its own so
## the player never has to dismiss anything mid-build.
func _show_day_summary(r: DayReportData) -> void:
	var grade_color: String = GRADE_COLORS.get(r.grade, Color.WHITE).to_html(false)
	var profit_color := "#7FBF7F" if r.profit >= 0.0 else "#C4573A"
	var text := "[b]Day %d done[/b] · grade [color=#%s][b]%s[/b][/color] (%d)\n" % [r.day, grade_color, r.grade, roundi(r.grade_score)]
	text += "[color=%s]%s§%d[/color] · %d%% fresh · %d%% happy" % [profit_color, "+" if r.profit >= 0.0 else "−", absi(roundi(r.profit)), roundi(r.avg_freshness_overall), roundi(r.avg_happiness)]
	if r.is_personal_best and r.day > 1:
		text += "\n[color=#C9A227]New personal best score![/color]"
	elif r.capacity_blocked > 0.0:
		text += "\n[color=#C4573A]%d food blocked by route capacity[/color]" % roundi(r.capacity_blocked)
	_summary_label.text = text
	_summary_panel.visible = true
	if _summary_tween != null and _summary_tween.is_valid():
		_summary_tween.kill()
	_summary_tween = create_tween()
	_summary_tween.tween_interval(GameBalance.DAY_SUMMARY_HOLD_SEC)
	_summary_tween.tween_callback(func() -> void: _summary_panel.visible = false)

## ---------- hover tooltip ----------

## Which node the pointer is over, and nothing else. This used to also build
## and position a text panel describing whatever was under the cursor -- a
## source's produce, a route's capacity and upkeep, a hub's last-run split,
## storage protection, the river's crossing price. That panel is retired
## (v0.6 item 55): the map's own marks carry the state now, and a brown box
## following the cursor over a map this dense was covering the thing it was
## describing.
func _update_hover(cell: Vector2i) -> void:
	if not _cell_in_bounds(cell):
		_set_focused_node("")
		return
	var n := _node_at(cell)
	# Inspecting a settlement is what expands it from a glyph column into full
	# rows, so the same pointer that used to open the tip drives the map layer.
	_set_focused_node(n.node_id if n else "")

## Re-renders only when the focused node actually changes. _render_grid
## rebuilds every visual on the map, so calling it per mouse-motion event
## would be untenable -- but crossing into or out of a node's footprint is
## rare, and only that crossing changes what is drawn.
func _set_focused_node(node_id: String) -> void:
	if node_id == _focused_node_id:
		return
	_focused_node_id = node_id
	# In ALL or OFF mode nothing about a node's rendering depends on focus,
	# so the rebuild would be pure waste.
	if _bubbles_mode == BubblesMode.GLYPHS:
		_render_grid()

## ---------- daily report ----------

func _show_report(r: DayReportData) -> void:
	_report_sub.text = "Day %d" % r.day
	# Reviewing a past report (clock panel's Report button) just closes; only
	# the end-of-day report rolls the calendar over.
	_report_continue.text = "Continue to next day" if _report_advances_day else "Close"
	var text := ""
	text += "Income: §%d\n" % roundi(r.income)
	# Both lines only appear when they have something to say, so a clean
	# day's report stays as short as it was before the delivery rule.
	if r.bonus_income > 0.0:
		text += "[color=#3FA34D]  ...including freshness bonus: +§%d[/color]\n" % roundi(r.bonus_income)
	if r.withheld_income > 0.0:
		text += "[color=#D64545]  Lost to incomplete orders: §%d[/color]\n" % roundi(r.withheld_income)
	text += "Route upkeep: −§%d\n" % roundi(r.route_upkeep)
	text += "Storage upkeep: −§%d\n" % roundi(r.storage_upkeep)
	text += "Hub upkeep: −§%d\n" % roundi(r.hub_upkeep)
	text += "Spoilage cost: −§%d\n" % roundi(r.spoilage_cost)
	text += "[b]Profit: %s§%d[/b]\n\n" % ["+" if r.profit >= 0 else "", roundi(r.profit)]
	text += "Average freshness delivered: %d%%\n" % roundi(r.avg_freshness_overall)
	text += "Waste (unmet + rejected demand): %d%%\n" % roundi(r.waste_pct)
	if r.capacity_blocked > 0.0:
		text += "[color=#C4573A]⚠ Blocked by route capacity: %d food[/color]\n" % roundi(r.capacity_blocked)
	# The denominator is printed because it moves: happiness averages only
	# the settlements actually taking orders (DEV-01), so without it a
	# perfectly steady network would look like it had swung whenever the
	# region opened up a new one.
	text += "Settlement happiness: %d%% (%d of %d settlements taking orders)\n" % [
		roundi(r.avg_happiness), r.settlements_taking_orders, r.settlements_total,
	]
	var grade_color: String = GRADE_COLORS.get(r.grade, Color.WHITE).to_html(false)
	text += "Network efficiency grade: [b][color=#%s]%s[/color][/b] (score %d/100)\n\n" % [grade_color, r.grade, roundi(r.grade_score)]
	text += "[b]Per-settlement[/b]\n"
	for s in r.settlement_scores:
		text += "%s: %d%% happy · %d%% fresh\n" % [s.settlement.display_name, roundi(s.sat), roundi(s.avg_fresh)]
	_report_text.text = text
	if r.is_personal_best and r.day > 1:
		_report_banner.text = "🏆 New personal best score! Grade %s, %d/100. Can you clean the network up further?" % [r.grade, roundi(r.grade_score)]
		_report_banner.visible = true
	elif r.capacity_blocked > 0.0:
		_report_banner.text = "Routes maxed out today -- some deliveries couldn't get through. Consider a hub, an upgrade, or a second route through the bottleneck."
		_report_banner.visible = true
	else:
		_report_banner.visible = false
	_report_overlay.visible = true

## ---------- grid visuals ----------

func _render_grid() -> void:
	_clear_children(_grid_visuals)
	# Both are rebuilt by this render; the markers they point at are about to
	# be freed, so holding last frame's would be holding freed instances.
	_columns_by_node.clear()
	_nagging_nodes.clear()
	for pos in _state.grid:
		var parts := _build_cell_visuals(_grid_visuals, pos, _state.grid[pos])
		var pop = _pending_tile_pops.get(pos)
		if pop != null:
			var node: Node3D = parts[pop.part]
			# A structure pop with no structure drawn is not a state to guard
			# against elsewhere: bulldozing the hub in the same frame it was
			# built is a legal, if pointless, thing for a player to do.
			if node != null:
				_pop_tile(node, pop.delay)
	for c in _state.last_congestion:
		var world_pos: Vector3 = _terrain.map_to_local(Vector3i(c.pos.x, 0, c.pos.y)) + Vector3(0, 1.35, 0)
		_add_congestion_marker(world_pos, c.over)
	_render_established_routes()
	if _bubbles_mode != BubblesMode.OFF:
		_render_supply_bubbles()
	# Cleared whether or not anything drew: a flourish the player could not
	# have seen (bubbles off) is spent, not banked for whenever they turn
	# them back on.
	_pending_pops.clear()
	_pending_tile_pops.clear()
	_day_just_ran = false

## Builds one grid cell's whole visible stack under `parent` and hands back the
## nodes it is made of, keyed by TilePart, so a caller can animate either one
## without re-deriving where it went. TilePart.STRUCTURE is null on a plain
## route tile, which is most of them.
##
## The split is the placement rule as much as a drawing convenience: a route
## drag lays road, while a hub, storage or bridge is added to road that was
## already there -- so only one of the two is ever the thing that just arrived.
func _build_cell_visuals(parent: Node3D, pos: Vector2i, cell: Dictionary) -> Dictionary:
	var world_pos: Vector3 = _terrain.map_to_local(Vector3i(pos.x, 0, pos.y)) + Vector3(0, 1.0, 0)
	var surface := _add_road_surface(parent, world_pos, pos, cell.get("level", "dirt"))
	var structure: Node3D = null
	if cell.kind == "route":
		# A bridge tile keeps its ordinary road block -- the road underneath
		# stays fully visible -- and gains a deck floating across it.
		if cell.has("bridge_axis"):
			structure = _add_bridge_deck(parent, world_pos, cell.bridge_axis)
	else:
		# Storage and hubs are BUILDINGS ON a route tile, not replacements
		# for one: the road they were built on is drawn underneath and the
		# building stands on top of it, so the road reads as continuous
		# through the junction and its Dirt/Paved/Main level stays visible.
		# That's also what makes bulldozing one back to that same road look
		# like what it is (_clear_cell), rather than a tile appearing out of
		# nowhere.
		var is_storage: bool = cell.kind == "storage"
		var marker: NodeMarker = (STORAGE_SCENE if is_storage else HUB_SCENE).instantiate()
		parent.add_child(marker)
		marker.position = world_pos + Vector3(0, surface.height, 0)
		marker.apply_tint(MarkerColors.storage_color(cell.stype) if is_storage else MarkerColors.hub_color(cell.htype))
		structure = marker
	return {TilePart.ROAD: surface.node, TilePart.STRUCTURE: structure}

## ---------- tile placement pop (item 64) ----------
##
## A placed tile presses up out of the ground rather than appearing: it starts
## squashed flat and springs to full size with a small overshoot.
##
## Squashed, not uniformly small, because a road slab is 2.0 world units across
## and 0.22 tall (generate_blocks.py). A uniform scale-from-small is dominated
## by the FOOTPRINT growing, which reads as the tile sliding in from somewhere;
## flattening Y far harder than XZ makes height the thing that changes, which is
## what "placed" looks like. The road block's own origin sits at its mid-height,
## so a flattened slab has half its shrink below the grass cap it stands on and
## is occluded by the terrain plinth -- the tile emerges from the ground for
## free, with no pivot node to maintain. Markers are authored origin-at-base
## (see hub_marker.tscn), so they grow up out of the road instead.
##
## Scale is the verb the bubble columns reserve for POP, a new order opening
## (food_bubble_marker.gd). That vocabulary is about the billboards floating
## ABOVE nodes; this is the ground plane, a different object class that never
## flourishes for the same reason at the same moment, so the two cannot be
## confused for variants of each other. They are deliberately not the same
## motion either: a column springs from 0.18 over 0.50s, a tile from a squash
## over half that, because a tile is a smaller and far more frequent event.
const TILE_POP_FROM := Vector3(0.85, 0.3, 0.85)
const TILE_POP_SEC := 0.26

## Per-tile delay along a drag, and the ceiling on the whole run. A drag of 10
## finishes in 10 * 0.045 + 0.26 = 0.71s; the budget is what stops a 30-tile
## sweep across the map from becoming something the player waits out, by
## tightening the stagger instead of extending the gesture.
const TILE_POP_STAGGER := 0.045
const TILE_POP_STAGGER_BUDGET := 0.5

## Arms one road pop per newly built cell, staggered in the order given -- for a
## drag, the order the player drew.
##
## Kept separate from _commit_drag because that method renders before it
## returns, so the pops it arms are consumed by its own _after_action and there
## is no moment afterwards at which the decision it made can be observed.
func _arm_placement_pops(cells: Array[Vector2i]) -> void:
	var stagger: float = minf(TILE_POP_STAGGER, TILE_POP_STAGGER_BUDGET / float(maxi(cells.size(), 1)))
	for i in cells.size():
		_pending_tile_pops[cells[i]] = {"part": TilePart.ROAD, "delay": i * stagger}

## Bound to the tile rather than to Main, so the many renders that rebuild the
## grid mid-pop (every hover, day and build) take the tween with the node they
## free instead of leaving it animating a freed target. The tile the new render
## draws is simply at rest, which is the right answer for a pop that was cut
## short.
func _pop_tile(node: Node3D, delay: float) -> void:
	node.scale = TILE_POP_FROM
	var tween := node.create_tween()
	if delay > 0.0:
		# Held at its squashed scale for the delay rather than hidden: at this
		# height a flattened slab is already all but invisible against the road
		# it will become, and toggling visibility would make the stagger read as
		# tiles blinking on in sequence instead of rising in sequence.
		tween.tween_interval(delay)
	tween.tween_property(node, "scale", Vector3.ONE, TILE_POP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Squashed further than the pop starts from, and with no overshoot: coming
## back up is what a placement does, so a removal that eased out would read as
## a very fast pop played backwards rather than as the tile being crushed away.
const TILE_REMOVE_TO := Vector3(0.7, 0.05, 0.7)
const TILE_REMOVE_SEC := 0.2

## The inverse of the placement pop: what a bulldoze takes away squashes flat
## and goes, rather than blinking out.
##
## The real visual cannot be animated in place -- _clear_cell mutates the grid
## and the render that follows clears GridVisuals wholesale -- so a throwaway
## copy is built on the Effects layer, the same trick the payout label uses,
## and frees itself when its tween ends. Must be called BEFORE _clear_cell, or
## the cell it copies is already gone.
##
## Which part squashes is the placement rule read from the other side: clearing
## a hub, storage or bridge leaves the road it stood on (_clear_cell), so only
## the structure goes. The whole cell is built and the survivor discarded
## rather than building the one part, because a marker's height depends on the
## road surface underneath it.
func _spawn_removal_ghost(cell: Vector2i, cell_data: Dictionary, delay: float) -> void:
	var going: TilePart = TilePart.ROAD
	if cell_data.kind != "route" or cell_data.has("bridge_axis"):
		going = TilePart.STRUCTURE
	var ghost := Node3D.new()
	ghost.name = "RemovalGhost"
	_fx_layer.add_child(ghost)
	var parts := _build_cell_visuals(ghost, cell, cell_data)
	for part in parts:
		if part != going and parts[part] != null:
			parts[part].free()
	var node: Node3D = parts[going]
	if node == null:
		ghost.free()
		return
	var tween := node.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(node, "scale", TILE_REMOVE_TO, TILE_REMOVE_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)

## Continuously overlays a bright gold line along every tile that lies on a
## complete source->settlement path (an "established route"), so the player
## can see at a glance which roads actually link a source to a customer --
## capped with a green arrow at the source end (pointing the way delivery
## flows) and a red bar at the settlement end, so start and finish read at a
## glance too. Dead-end stubs -- roads that branch off but reach no
## settlement (or no source) -- are pruned out and left unmarked. Rebuilt
## every _render_grid, so it stays live as the network is edited or
## simulated.
## Lateral gap between two sources' lanes where they share a road. The tile is
## 2 world units across, so even five lanes stay on the road surface.
const ESTABLISHED_LANE_SPACING := 0.42

func _render_established_routes() -> void:
	var sources_here := _established_sources_by_vertex()
	if sources_here.is_empty():
		return
	# One lane per source. Each established tile carries a dot per source whose
	# deliveries run through it, and each link to an established neighbour
	# carries a bar per source SHARED with that neighbour -- so a colour joins
	# the road where its source does and peels off exactly where their paths
	# part. The node ends stay distinguished regardless of colour: a green
	# arrow at the source (pointing the way delivery flows) and a red bar at
	# the settlement.
	#
	# Iterated per GRAPH VERTEX rather than per tile (SimulationEngine's lane
	# rules), so at a bridge the deck and the road beneath it each get their own
	# lines -- drawn at their own heights, and only along their own axis. That's
	# what makes a crossing read as one route passing over another instead of
	# two colours meeting in a junction.
	for v in sources_here:
		var cell := SimulationEngine.vertex_pos(v)
		var ids: Array = sources_here[v]
		var here := _established_point(v)
		# Dots have no direction of their own, so they take their lane axis
		# from the tile's first established link. On a straight run that lines
		# the dots up with the bars exactly; on a corner it's the axis of one
		# of the two arms, which still reads as one continuous lane.
		var dot_axis := Vector3(0.0, 0.0, 1.0)
		for w in SimulationEngine.exits(_state, v):
			if sources_here.has(w) or _nodes_by_pos.has(SimulationEngine.vertex_pos(w)):
				dot_axis = _lane_axis(SimulationEngine.vertex_pos(w) - cell)
				break
		for i in range(ids.size()):
			_add_established_marker(here + dot_axis * _lane_offset(i, ids.size()), _source_food_color(ids[i]))
		for w in SimulationEngine.exits(_state, v):
			var n := SimulationEngine.vertex_pos(w)
			var d: Vector2i = n - cell
			var there := _established_point(w)
			if sources_here.has(w):
				# Tile<->tile: draw one bar per undirected pair (east/south only),
				# since the other tile will iterate and draw the matching half.
				if d == Vector2i(1, 0) or d == Vector2i(0, 1):
					var shared := _shared_source_ids(ids, sources_here[w])
					var axis := _lane_axis(d)
					for i in range(shared.size()):
						var offset := axis * _lane_offset(i, shared.size())
						_add_established_segment(here + offset, there + offset, _source_food_color(shared[i]))
			elif _nodes_by_pos.has(n):
				# Tile->node: a source/settlement isn't an established tile and
				# never iterates to draw its own half, so draw the marker from
				# ANY direction -- this is what makes the overlay actually
				# start from the source (and reach the settlement) instead of
				# stopping at the node-adjacent tile.
				var node: NodeData = _nodes_by_pos[n]
				if node.node_type == GameEnums.NodeType.SOURCE:
					# `d` points from the tile to the source; delivery flows
					# the opposite way, from the source into the tile.
					_add_established_start_arrow((here + there) * 0.5, -d)
				else:
					_add_established_segment(here, there, ESTABLISHED_END_COLOR)

## Where the overlay draws for a graph vertex: the tile's centre, lifted to the
## deck's height when the vertex is a bridge deck so the crossing line visibly
## rides over the one underneath.
func _established_point(v: Vector3i) -> Vector3:
	var cell := SimulationEngine.vertex_pos(v)
	var lift: float = BRIDGE_DECK_HEIGHT if v.z == SimulationEngine.LANE_DECK else 0.0
	return _terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, ESTABLISHED_ROUTE_Y + lift, 0)

## The horizontal axis lanes spread along, perpendicular to a link running in
## direction `d`.
func _lane_axis(d: Vector2i) -> Vector3:
	return Vector3(0.0, 0.0, 1.0) if d.x != 0 else Vector3(1.0, 0.0, 0.0)

## Lane `index` of `count`, centred on the road: a single source runs straight
## down the middle, two straddle it evenly, and so on.
func _lane_offset(index: int, count: int) -> float:
	return (float(index) - (count - 1) * 0.5) * ESTABLISHED_LANE_SPACING

## Source ids present on both tiles, in `a`'s order so a lane keeps its
## position along the whole shared stretch instead of swapping sides.
func _shared_source_ids(a: Array, b: Array) -> Array:
	var shared: Array = []
	for source_id in a:
		if b.has(source_id):
			shared.append(source_id)
	return shared

## Which sources' delivery paths each established tile lies on: Vector2i ->
## Array of source node_ids, in map order so lanes stay put frame to frame.
##
## Computed per source rather than per road network, so a tile is only
## attributed to the sources that can actually reach a settlement THROUGH it
## (see SimulationEngine.established_route_cells' only_source_id filter). Two
## sources feeding one shared trunk both colour the trunk, but neither
## colours the other's spur.
## Keyed by graph vertex, not tile, so a bridge's deck and the road beneath it
## are attributed independently -- one may be carrying deliveries while the
## other is a dead stub, and the overlay has to show exactly that.
func _established_sources_by_vertex() -> Dictionary:
	var result := {}
	for node_id in _nodes_by_id:
		var node: NodeData = _nodes_by_id[node_id]
		if node.node_type != GameEnums.NodeType.SOURCE:
			continue
		for v in SimulationEngine.established_route_vertices(_state, _nodes_by_pos, node.node_id):
			result.get_or_add(v, []).append(node.node_id)
	return result

## The set (Vector2i -> true) of built tiles on some complete source->
## settlement path -- see SimulationEngine.established_route_cells for the
## exact rule (road-only connectivity that must start at a source).
func _established_route_cells() -> Dictionary:
	return SimulationEngine.established_route_cells(_state, _nodes_by_pos)

## Always-on speech bubbles showing "current/max" for every source and
## settlement: a source's amount drawn today vs. its daily produce
## (SimulationEngine.run_day's last_source_status), muted once fully
## tapped out; a settlement's delivered vs. requested amount per food
## plus average freshness (last_settlement_status), flagged red/amber/
## green by combined amount+freshness status (see
## _render_settlement_bubbles). Both read as "0/max" before the first
## simulated day, since neither dictionary has entries yet. The two are
## told apart by shape, not colour -- sources are signs on a post,
## settlements are speech balloons (bubble_canvas.gd).
func _render_supply_bubbles() -> void:
	var foods := GameBalance.food_types()
	# By node, not by cell: iterating _nodes_by_pos would draw a 2x1 Town's
	# bubbles twice and a 2x2 City's four times, stacked on top of each other
	# (DEV-02).
	for node_id in _nodes_by_id:
		var n: NodeData = _nodes_by_id[node_id]
		if n.node_type == GameEnums.NodeType.SOURCE:
			_render_source_bubbles(n, foods)
		elif n.node_type == GameEnums.NodeType.SETTLEMENT:
			_render_settlement_bubbles(n, foods)

## Where a node's bubbles and marker anchor: the middle of its whole
## footprint, so a 2x2 City speaks from its centre rather than from the corner
## cell the map author happened to write down.
func _node_center(n: NodeData) -> Vector3:
	var near: Vector3 = _terrain.map_to_local(Vector3i(n.grid_position.x, 0, n.grid_position.y))
	var far_cell := n.far_cell()
	var far: Vector3 = _terrain.map_to_local(Vector3i(far_cell.x, 0, far_cell.y))
	return (near + far) * 0.5

## Whether this settlement draws its full balloons rather than the compact
## glyph strip: either the player is inspecting it, or they have asked for
## every balloon at once. Sources never consult this -- a source is always
## its big food glyph now (v0.6 item 48).
func _shows_full_bubbles(n: NodeData) -> bool:
	return _bubbles_mode == BubblesMode.ALL or _focused_node_id == n.node_id

## `is_settlement` decides the tail and the row width both -- a source row is
## wider, carrying its draw-down beside a full-size glyph rather than under a
## shrunken one (item 56).
func _spawn_glyph_column(base_pos: Vector3, entries: Array, is_settlement: bool, flourish := FoodBubbleMarker.Flourish.NONE) -> FoodBubbleMarker:
	if entries.is_empty():
		return null
	var column: FoodBubbleMarker = FOOD_BUBBLE_SCENE.instantiate()
	_grid_visuals.add_child(column)
	column.position = base_pos
	column.setup_glyph_column(entries, is_settlement)
	column.play(flourish)
	return column

func _render_source_bubbles(n: NodeData, foods: Dictionary) -> void:
	var status: Dictionary = _state.last_source_status.get(n.node_id, {})
	# The source's crate model is shorter than the settlement pin, so its
	# bubble sits a little lower than the settlement stack's start height.
	var base_pos: Vector3 = _node_center(n) + Vector3(0, 2.5, 0)
	# A source is ALWAYS its big food glyph, inspected or not. The dark slate
	# sign it used to expand into is retired: a source's identity is the food
	# it makes, and a glyph says that faster and smaller than a sign printing
	# "21/80" ever did. That used/produced figure moved to the hover tip,
	# which is now the only place it lives.
	var entries: Array = []
	for food_id in n.produces:
		var produced: float = n.produces[food_id]
		var used: float = 0.0
		if status.has(food_id):
			used = status[food_id].used
		var bubble_status := FoodBubbleMarker.Status.MUTED if used >= produced - 0.01 else FoodBubbleMarker.Status.DEFAULT
		# A source's glyph carries no status mark: MUTED/DEFAULT is "spent
		# today" vs "still has stock", which the glyph already says by going
		# grey, and a ✓ beside it would read as a delivery verdict this node
		# never has.
		entries.append({
			"food_id": food_id,
			"color": (BubbleCanvas.MUTED_ICON_COLOR if bubble_status == FoodBubbleMarker.Status.MUTED
				else foods[food_id].color),
			"status": bubble_status,
			# Drawn today out of the daily produce. This lived on the retired
			# sign, then the retired hover tip; the chip is now the only place
			# it can be, and the glyph going grey alone said whether anything
			# was left but never how much (v0.6 item 55).
			"amount_text": "%d/%d" % [roundi(used), roundi(produced)],
		})
	_spawn_glyph_column(base_pos, entries, false)

## A settlement can demand up to 3 foods (Town D, City E), and some
## settlements sit only 3 tiles from a neighbor -- stacking every bubble
## in a single tall column risked visually crowding the neighbor's own
## bubbles. A 2-column grid caps the stack at 2 rows regardless of how
## many foods are demanded.
## Status reads as one question asked twice: did it all get here, and was
## it fresh enough? GREEN is the full requested amount at this
## settlement's own bonus_freshness or above; AMBER is the full amount
## below that threshold; RED is anything short, down to nothing arriving.
## min_freshness is deliberately absent: SimulationEngine.run_day rejects
## anything under it before it ever counts as delivered, so a bubble can
## never see an average below that line and a rule testing for one would
## be dead.
## Every open order keeps its own bubble whatever its status. A settled
## settlement used to collapse its whole stack into one "All fresh" summary,
## which hid the very numbers the player had just worked to earn -- and with
## orders opening one at a time (DEV-01) the stacks it was decluttering are
## rare now anyway. Green bubbles already recede on their own: they wash
## lighter and outline thinner than amber and red (bubble_canvas.gd).
func _render_settlement_bubbles(n: NodeData, foods: Dictionary) -> void:
	var status = _state.last_settlement_status.get(n.node_id, {})
	# NodeMarker puts the settlement pin's head at +2.1 (node_spawner.gd's
	# +1.0 root offset plus node_marker_base.tscn's local offset), so start
	# above it -- otherwise this billboard sits inside the pin head and the
	# two fuse into an unreadable blob.
	var base_pos: Vector3 = _node_center(n) + Vector3(0, 3.1, 0)

	var entries: Array = []
	# Only the orders that have actually opened (DEV-01). A settlement with
	# none draws nothing at all -- the pin alone. It is not showing a grey
	# "later" placeholder either: five of those from day 1 would be the same
	# wall of bubbles this feature exists to remove, in a quieter colour.
	var demand := OrderBook.active_demand(_state, n)
	for food_id in demand:
		var requested: float = demand[food_id]
		var delivered: float = 0.0
		var avg_fresh: float = 0.0
		var rejected: float = 0.0
		var rejected_fresh: float = 0.0
		var earned: float = 0.0
		var withheld: float = 0.0
		var s = status.get(food_id)
		if s != null:
			requested = s.requested
			delivered = s.delivered
			if delivered > 0.0:
				avg_fresh = s.fresh_sum / delivered
			# Cargo min_freshness turned away. It still consumed the day's
			# demand (SimulationEngine drops `need` before deciding whether to
			# accept), so this is very often the whole reason a line came up
			# short -- and the delivered freshness above cannot show it,
			# averaging only what was let in.
			rejected = s.get("rejected", 0.0)
			if rejected > 0.0:
				rejected_fresh = s.get("rejected_fresh_sum", 0.0) / rejected
			# What the line paid, and what a short one gave up. The row's
			# colour has always encoded the payment tier (§9) and never said
			# so -- which is why a red row beside "90% fresh" read as a
			# freshness verdict rather than an earnings one.
			earned = s.get("earned", 0.0)
			withheld = s.get("withheld", 0.0)

		var bubble_status: FoodBubbleMarker.Status
		if delivered < requested - 0.01:
			bubble_status = FoodBubbleMarker.Status.RED
		elif avg_fresh >= n.bonus_freshness:
			bubble_status = FoodBubbleMarker.Status.GREEN
		else:
			bubble_status = FoodBubbleMarker.Status.AMBER

		entries.append({
			"food_id": food_id,
			"delivered": delivered,
			"requested": requested,
			"status": bubble_status,
			"freshness_pct": roundi(avg_fresh) if delivered > 0.0 else -1,
			"rejected": rejected,
			"rejected_freshness_pct": roundi(rejected_fresh) if rejected > 0.0 else -1,
			"earned": earned,
			"withheld": withheld,
		})

	# Worst first, so the leftmost glyph on the strip -- and the first
	# balloon in an expanded stack -- is the line most worth acting on. Red
	# before amber before green, ties broken by how far short the delivery
	# fell as a fraction of what was asked for. Without this the order was
	# whatever the demand dictionary happened to iterate.
	entries.sort_custom(_worse_first)

	# One marker either way. The collapsed chips and the expanded rows are the
	# same column at two widths (BubbleCanvas's shared column geometry), so a
	# hover widens the panel around glyphs that do not move -- which is only
	# possible because both are a single baked texture rather than a set of
	# separately-positioned billboards.
	var glyphs: Array = []
	for e in entries:
		glyphs.append({
			"food_id": e.food_id,
			"color": foods[e.food_id].color,
			"status": e.status,
			"delivered": e.delivered,
			"requested": e.requested,
			"freshness_pct": e.freshness_pct,
			"rejected": e.rejected,
			"rejected_freshness_pct": e.rejected_freshness_pct,
			"earned": e.earned,
			"withheld": e.withheld,
		})

	# One flourish per column, chosen by the same rule that decides which chip
	# sits on top: entries are sorted worst-first, so entries[0] is the line
	# most worth acting on and its status is what the column should express.
	# A new order outranks any delivery -- it is the larger event, and playing
	# both on one column would just read as a stumble.
	var flourish := FoodBubbleMarker.Flourish.NONE
	if _pending_pops.has(n.node_id):
		flourish = FoodBubbleMarker.Flourish.POP
	elif _day_just_ran and not entries.is_empty():
		flourish = _flourish_for(entries[0].status)

	# The day's takings for this settlement, summed from the same per-line
	# figures run_day recorded (item 54) rather than recomputed here.
	if _day_just_ran:
		var earned := 0.0
		for e in entries:
			earned += e.earned
		_spawn_payout(base_pos, earned)

	# Recorded for the reminder, which shakes these without re-deriving a
	# status: entries[0] is the worst line, the same one the column expresses.
	if not entries.is_empty() and entries[0].status == FoodBubbleMarker.Status.RED:
		_nagging_nodes.append(n.node_id)

	if not _shows_full_bubbles(n):
		_columns_by_node[n.node_id] = _spawn_glyph_column(base_pos, glyphs, true, flourish)
		return

	var column: FoodBubbleMarker = FOOD_BUBBLE_SCENE.instantiate()
	_grid_visuals.add_child(column)
	column.position = base_pos
	column.setup_settlement_column(glyphs, n.bonus_freshness, n.min_freshness)
	column.play(flourish)
	_columns_by_node[n.node_id] = column

## ---------- payout labels ----------
## What a settlement earned that day, floating up beside its column and
## fading. The row already prints per-line earnings when expanded (item 54),
## but that needs a hover; this is the at-a-glance version, and it appears at
## the one moment the number changes.
## Sized against the things beside it rather than picked: cap height on screen
## is font_size * pixel_size, so 128 * 0.0075 = 0.96 world units against a
## 1.38-unit chip and the row's own 0.47-unit amount text -- about 70% of a
## chip, and twice the text inside one. The first version came to 0.35,
## smaller than the number it was announcing, which is why it read as an
## afterthought. Kept as a large font at a small pixel_size rather
## than the reverse, since font_size is what the glyphs are rasterised at.
const PAYOUT_RISE := 2.3
const PAYOUT_SEC := 1.7
const PAYOUT_FONT_SIZE := 128
const PAYOUT_PIXEL_SIZE := 0.0075
const PAYOUT_OUTLINE_SIZE := 28
## A short scale-in so a label this size arrives rather than blinks on. It
## overlaps the first fifth of the rise, so the whole thing still reads as one
## movement.
const PAYOUT_PUNCH_FROM := 0.65
const PAYOUT_PUNCH_SEC := 0.22
const PAYOUT_COLOR := Color("9fd8a8")
const PAYOUT_OUTLINE := Color(0.06, 0.08, 0.07, 0.95)

## Offset from the column's centre, and the label is LEFT-aligned so it grows
## rightward from there. Centred text was tried first and the overlap scales
## with the amount: "+§187" cleared the chip but "+§1870" grew back over its
## right edge, because half of a longer string reaches further in. Anchoring
## the left edge just past the chip's half-width (208px * 0.0072 / 2 = 0.75)
## makes the clearance the same whatever the settlement earned.
const PAYOUT_OFFSET := Vector3(0.95, 0.8, 0.0)

func _spawn_payout(base_pos: Vector3, earned: float) -> void:
	# Nothing earned is not worth a label: that settlement is already shaking,
	# and "+§0" would be a second way of saying the same nothing.
	if earned <= 0.0:
		return
	var label := Label3D.new()
	label.text = "+§%d" % roundi(earned)
	label.font_size = PAYOUT_FONT_SIZE
	label.pixel_size = PAYOUT_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = PAYOUT_COLOR
	label.outline_size = PAYOUT_OUTLINE_SIZE
	label.outline_modulate = PAYOUT_OUTLINE
	# Drawn over whatever it passes in front of. A payout that disappears
	# behind a chip for half its flight reads as a glitch.
	label.no_depth_test = true
	label.render_priority = 4
	label.outline_render_priority = 3
	_fx_layer.add_child(label)
	label.position = base_pos + PAYOUT_OFFSET

	label.scale = Vector3.ONE * PAYOUT_PUNCH_FROM

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE, PAYOUT_PUNCH_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position", label.position + Vector3(0.0, PAYOUT_RISE, 0.0), PAYOUT_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, PAYOUT_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

## Which flourish a column plays for its worst line's status. The axis is the
## meaning: vertical says the line paid and its height says how well, while
## horizontal says it did not pay at all -- §9's real break is between red and
## the other two, not between amber and green.
static func _flourish_for(status: FoodBubbleMarker.Status) -> FoodBubbleMarker.Flourish:
	match status:
		FoodBubbleMarker.Status.GREEN:
			return FoodBubbleMarker.Flourish.HOP
		FoodBubbleMarker.Status.AMBER:
			return FoodBubbleMarker.Flourish.NUDGE
		FoodBubbleMarker.Status.RED:
			return FoodBubbleMarker.Flourish.SHAKE
	return FoodBubbleMarker.Flourish.NONE

## Severity order for a settlement's open lines: red, then amber, then
## green, with the biggest shortfall first inside a tier.
static func _worse_first(a: Dictionary, b: Dictionary) -> bool:
	var rank_a := _status_rank(a.status)
	var rank_b := _status_rank(b.status)
	if rank_a != rank_b:
		return rank_a < rank_b
	return _shortfall(a) > _shortfall(b)

static func _status_rank(status: FoodBubbleMarker.Status) -> int:
	match status:
		FoodBubbleMarker.Status.RED:
			return 0
		FoodBubbleMarker.Status.AMBER:
			return 1
	return 2

## As a fraction of what was asked for, so a village 5 short of 10 outranks a
## city 5 short of 40 -- the small order is the one closer to failing.
static func _shortfall(e: Dictionary) -> float:
	var requested: float = e.requested
	if requested <= 0.0:
		return 0.0
	return clampf((requested - e.delivered) / requested, 0.0, 1.0)

## Every route level's mesh is symmetric under rotation (see generate_blocks.py),
## so a route tile always uses the same unrotated scene regardless of its
## shape or facing -- there's no corner variant and nothing to rotate.
func _add_route_block(parent: Node3D, pos: Vector3, level: String) -> Node3D:
	var scene: PackedScene = ROUTE_LEVEL_SCENES.get(level)
	if scene == null:
		return _add_tile_box(parent, pos, ROUTE_LEVEL_COLORS.get(level, Color.WHITE), 0.16)
	var block: Node3D = scene.instantiate()
	parent.add_child(block)
	block.position = pos + Vector3(0, ROUTE_LEVEL_HEIGHTS.get(level, 0.22) * 0.5, 0)
	# No scale needed: the block's footprint is authored at the real 2x2
	# world-space cell size already (see generate_blocks.py).
	return block

## A source's colour is the colour of what it produces (one food each in the
## MVP region; averaged if a source ever produces several). All source
## markers share one colour (§16), so the food is what actually tells one
## source from another -- and it's the colour language the speech bubbles
## already use.
func _source_food_color(source_id: String) -> Color:
	var node: NodeData = _nodes_by_id.get(source_id)
	if node == null or node.produces.is_empty():
		return ESTABLISHED_ROUTE_COLOR
	var foods := GameBalance.food_types()
	var mixed := Color(0.0, 0.0, 0.0, 1.0)
	for food_id in node.produces:
		var color: Color = foods[food_id].color
		mixed.r += color.r
		mixed.g += color.g
		mixed.b += color.b
	var count := float(node.produces.size())
	return Color(mixed.r / count, mixed.g / count, mixed.b / count, 1.0)

## Draws a tile's road surface -- the ordinary level block, or the flat slab
## that stands in for it where the tile crosses the river -- and returns it as
## {node, height}. The height is what lets anything standing ON the tile (a hub)
## be lifted clear instead of sinking into it: marker scenes are authored with
## their origin at their base (see hub_marker.tscn), so it is exactly the lift
## needed. The node is what lets the surface be animated (_pop_tile).
func _add_road_surface(parent: Node3D, world_pos: Vector3, pos: Vector2i, level: String) -> Dictionary:
	if _map_data.is_river(pos.x, pos.y):
		return {
			"node": _add_tile_box(parent, world_pos, RIVER_BRIDGE_COLOR, RIVER_CROSSING_HEIGHT),
			"height": RIVER_CROSSING_HEIGHT,
		}
	return {
		"node": _add_route_block(parent, world_pos, level),
		"height": ROUTE_LEVEL_HEIGHTS.get(level, 0.22),
	}

## The raised deck of a bridge tile: a slab spanning the full cell along the
## deck's own axis (so it meets the road on either side rather than stopping
## short), narrowed across that axis and flanked by two rails, which is what
## makes it read as a crossing rather than a floating block from the fixed
## isometric camera. The road it crosses is drawn normally underneath and stays
## visible on both sides of the slab.
##
## Slab and rails hang off one container node placed at the deck's own centre,
## with their offsets expressed relative to it, so the deck can be scaled as a
## single object (_pop_tile) about the point it should pivot on. Positioning
## them absolutely under a container at the world origin would draw identically
## and scale catastrophically.
func _add_bridge_deck(parent: Node3D, pos: Vector3, axis: Vector2i) -> Node3D:
	var along := Vector3(1.0, 0.0, 0.0) if axis.x != 0 else Vector3(0.0, 0.0, 1.0)
	var across := Vector3(0.0, 0.0, 1.0) if axis.x != 0 else Vector3(1.0, 0.0, 0.0)
	var length: float = _terrain.cell_size.x if axis.x != 0 else _terrain.cell_size.z
	var span: float = _terrain.cell_size.z if axis.x != 0 else _terrain.cell_size.x
	var width: float = span * BRIDGE_DECK_WIDTH_RATIO
	var deck := Node3D.new()
	deck.name = "BridgeDeck"
	parent.add_child(deck)
	deck.position = pos + Vector3(0.0, BRIDGE_DECK_HEIGHT, 0.0)
	_add_box(deck, Vector3.ZERO, along * length + across * width + Vector3(0.0, BRIDGE_DECK_THICKNESS, 0.0), BRIDGE_DECK_COLOR)
	var rail_size := along * length + across * BRIDGE_RAIL_THICKNESS + Vector3(0.0, BRIDGE_RAIL_HEIGHT, 0.0)
	var rail_y := Vector3(0.0, (BRIDGE_DECK_THICKNESS + BRIDGE_RAIL_HEIGHT) * 0.5, 0.0)
	for side in [1.0, -1.0]:
		_add_box(deck, across * (width * 0.5 * side) + rail_y, rail_size, BRIDGE_RAIL_COLOR)
	return deck

func _add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_tile_box(parent: Node3D, pos: Vector3, color: Color, height: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_terrain.cell_size.x, height, _terrain.cell_size.z)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos + Vector3(0, height * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_congestion_marker(pos: Vector3, over: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("C4573A") if over else Color("D98E4A")
	mesh_instance.material_override = material
	_grid_visuals.add_child(mesh_instance)

## ---------- grid/graph helpers ----------

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func _screen_to_cell(screen_position: Vector2) -> Vector2i:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var hit = Plane(Vector3.UP, 2.0).intersects_ray(origin, direction)
	if hit == null:
		return Vector2i(-1, -1)
	var local_hit := _terrain.to_local(hit)
	var approximate := _terrain.local_to_map(local_hit)
	var nearest := approximate
	var nearest_distance := INF
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			var candidate := Vector3i(approximate.x + x_offset, 0, approximate.z + z_offset)
			var center := _terrain.map_to_local(candidate)
			var distance := Vector2(center.x, center.z).distance_squared_to(Vector2(local_hit.x, local_hit.z))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = candidate
	return Vector2i(nearest.x, nearest.z)

func _cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_data.grid_size.x and cell.y < _map_data.grid_size.y

func _node_at(cell: Vector2i) -> NodeData:
	return _nodes_by_pos.get(cell)

## ---------- UI ----------

func _set_tool(tool: String) -> void:
	_tool = tool
	# A tool can have more than one button (the sidebar copy plus a shortcut on
	# the top-left controller panel), so keep every button for the active tool
	# pressed and every other tool's buttons released.
	for key in _tool_buttons:
		for button in _tool_buttons[key]:
			button.button_pressed = key == tool
	_hint_label.text = TOOL_HINTS.get(tool, "")

## Three states rather than a checkbox, so the compact default and the old
## dense view are both reachable without a second control.
func _on_bubbles_pressed() -> void:
	_bubbles_mode = ((_bubbles_mode + 1) % BubblesMode.size()) as BubblesMode
	_bubbles_button.text = BUBBLES_MODE_LABELS[_bubbles_mode]
	_render_grid()

func _update_ui() -> void:
	if _funds_label == null:
		return
	_funds_label.text = "§ %d" % roundi(_state.balance)
	_day_label.text = "Day %d" % _state.day
	_update_clock_ui()
	if _state.best_grade != "":
		_best_grade_label.text = _state.best_grade
		_best_grade_label.add_theme_color_override("font_color", GRADE_COLORS.get(_state.best_grade, Color.WHITE))
	else:
		_best_grade_label.text = "—"
	_best_score_label.text = "%d" % roundi(_state.best_score) if _state.best_score > -INF else "—"
	if _state.score_history.size() > 0:
		var start := maxi(0, _state.score_history.size() - 7)
		var recent := _state.score_history.slice(start, _state.score_history.size())
		var avg := 0.0
		for h in recent:
			avg += h.score
		avg /= recent.size()
		_avg_score_label.text = "%d" % roundi(avg)
	else:
		_avg_score_label.text = "—"

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	var root := Control.new()
	root.name = "GameUI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_left = 12 + CONTROL_PANEL_WIDTH + 10
	_hint_label.offset_right = -12
	_hint_label.offset_top = -40
	_hint_label.offset_bottom = -12
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.add_theme_stylebox_override("normal", _panel_style(Color("142027"), 0.9))
	root.add_child(_hint_label)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Centered over the play area, which the left control panel eats into --
	# so the toast shifts right by half that panel's footprint to stay clear
	# of it and of the day clock in the opposite corner.
	_toast.position = Vector2(-220 + (12 + CONTROL_PANEL_WIDTH) * 0.5, 12)
	_toast.size = Vector2(440, 42)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("normal", _panel_style(Color("19312c"), 0.96))
	_toast.visible = false
	root.add_child(_toast)


	_build_control_panel(root)
	_build_day_clock(root)

	_report_overlay = ColorRect.new()
	_report_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_overlay.color = Color(0.02, 0.04, 0.05, 0.78)
	_report_overlay.visible = false
	root.add_child(_report_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_overlay.add_child(center)
	var report_panel := PanelContainer.new()
	report_panel.custom_minimum_size = Vector2(460, 560)
	report_panel.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 1.0))
	center.add_child(report_panel)
	var report_box := VBoxContainer.new()
	report_box.add_theme_constant_override("separation", 8)
	report_panel.add_child(report_box)
	var report_title := Label.new()
	report_title.text = "Daily Report"
	report_title.add_theme_font_size_override("font_size", 24)
	report_box.add_child(report_title)
	_report_sub = Label.new()
	report_box.add_child(_report_sub)
	_report_banner = Label.new()
	_report_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	_report_banner.add_theme_stylebox_override("normal", _panel_style(Color("C9A227"), 0.9))
	_report_banner.visible = false
	report_box.add_child(_report_banner)
	var report_scroll := ScrollContainer.new()
	report_scroll.custom_minimum_size = Vector2(430, 400)
	report_box.add_child(report_scroll)
	_report_text = RichTextLabel.new()
	_report_text.bbcode_enabled = true
	_report_text.fit_content = true
	_report_text.custom_minimum_size = Vector2(420, 0)
	report_scroll.add_child(_report_text)
	_report_continue = Button.new()
	_report_continue.text = "Continue to next day"
	_report_continue.custom_minimum_size.y = 40
	_report_continue.pressed.connect(_close_report)
	report_box.add_child(_report_continue)

## ---------- control panel (everything, left edge) ----------
##
## One panel carries the whole HUD: run stats, every build tool, the map
## zoom/pan controls, and the legend. It replaces the older split between a
## top-left map-controls panel and a 300px right-hand sidebar -- two panels
## ate both edges of the screen, and every build action meant crossing from
## one to the other, with the most-used tools duplicated on both to soften
## that. Only the day clock (§10.8) lives outside it, in the opposite corner.
##
## The panel is deliberately narrow, so tool buttons are short labels with the
## price attached; the full explanation of the selected tool lands in the
## bottom hint bar (TOOL_HINTS) and in each button's tooltip. The legend is
## collapsed by default -- it's reference material, not a control -- and the
## whole column scrolls, so nothing is unreachable on a short window.

const CONTROL_PANEL_WIDTH := 232.0
const CONTROL_PANEL_BOTTOM_MARGIN := 60.0 # clears the bottom hint bar
const CONTROLLER_BUTTON_SIZE := Vector2(36, 36)
const CONTROLLER_FONT_SIZE := 18

var _panel_scroll: ScrollContainer
var _legend_box: VBoxContainer
var _legend_button: Button

func _build_control_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 12 + CONTROL_PANEL_WIDTH
	panel.offset_bottom = -CONTROL_PANEL_BOTTOM_MARGIN
	panel.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.92))
	root.add_child(panel)
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_panel_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	_panel_scroll.add_child(box)

	_build_status_section(box)
	box.add_child(HSeparator.new())
	_build_tools_section(box)
	box.add_child(HSeparator.new())
	_build_map_section(box)
	box.add_child(HSeparator.new())
	_build_legend_section(box)

## Day, treasury, and the efficiency chase (LOOP-01/LOOP-06) in four numbers.
func _build_status_section(box: VBoxContainer) -> void:
	var treasury_row := HBoxContainer.new()
	box.add_child(treasury_row)
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 14)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	treasury_row.add_child(_day_label)
	_funds_label = Label.new()
	_funds_label.add_theme_font_size_override("font_size", 20)
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	treasury_row.add_child(_funds_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 4)
	box.add_child(stats_row)
	_best_grade_label = _add_stat_column(stats_row, "Grade", "Best grade so far")
	_best_score_label = _add_stat_column(stats_row, "Best", "Best day score")
	_avg_score_label = _add_stat_column(stats_row, "7-day", "Average score over the last 7 days")

func _build_tools_section(box: VBoxContainer) -> void:
	_add_section_title(box, "ROUTES")
	var route_grid := _add_tool_grid(box)
	_add_tool_button(route_grid, "Route  §%d" % roundi(GameBalance.ROUTE_BUILD_COST), "route", "Draw Route -- §%d per tile, +§%d to bridge the river. Drag from a source or hub to a hub or settlement." % [roundi(GameBalance.ROUTE_BUILD_COST), roundi(GameBalance.RIVER_BRIDGE_COST)])
	_add_tool_button(route_grid, "Upgrade", "upgrade", "Upgrade -- route Dirt to Paved (§%d) or Paved to Main (§%d); a food source to double its output (§%d)." % [roundi(GameBalance.ROUTE_LEVELS.dirt.upgrade_cost), roundi(GameBalance.ROUTE_LEVELS.paved.upgrade_cost), roundi(GameBalance.SOURCE_UPGRADE_COST)])

	_add_section_title(box, "STORAGE")
	var storage_grid := _add_tool_grid(box)
	for tool in ["normal", "cool"]:
		var st = GameBalance.STORAGE_TYPES[STORAGE_TOOLS[tool]]
		var label: String = st.name.replace(" Storage", "")
		_add_tool_button(storage_grid, "%s  §%d" % [label, roundi(st.build)], tool, "%s -- §%d to build, §%d/day upkeep, protects the next %d tiles at %d%% decay." % [st.name, roundi(st.build), roundi(st.upkeep), st.protection, roundi(st.mult * 100)])

	_add_section_title(box, "HUBS & CLEARING")
	var hub_grid := _add_tool_grid(box)
	_add_tool_button(hub_grid, "Hub  §%d" % roundi(GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build), "hubBuild", "Build a Small Hub on any existing route tile for §%d. Each connected road network supports %d hubs." % [roundi(GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].build), GameBalance.HUB_CAP_PER_NETWORK])
	_add_tool_button(hub_grid, "Bridge  §%d" % roundi(GameBalance.BRIDGE_BUILD_COST), "bridgeBuild", "Build a Bridge over a straight run of route tile for §%d, so a second route can be drawn straight over it without joining it. §%d/day extra upkeep, the deck costs %.0f× freshness decay to cross, and each connected road network supports %d." % [roundi(GameBalance.BRIDGE_BUILD_COST), roundi(GameBalance.BRIDGE_UPKEEP), GameBalance.BRIDGE_DECK_DECAY_MULT, GameBalance.BRIDGE_CAP_PER_NETWORK])
	_add_tool_button(hub_grid, "Bulldoze", "remove", "Remove a built tile, along with every connection touching it. A hub, storage or bridge only loses the structure -- the road it was built on stays, at the level it already was, so clearing that too is a second click. No refund.")

func _build_map_section(box: VBoxContainer) -> void:
	_add_section_title(box, "MAP")
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	box.add_child(zoom_row)
	var zoom_label := Label.new()
	zoom_label.text = "Zoom"
	zoom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zoom_row.add_child(zoom_label)
	_add_hold_button(zoom_row, "−", func() -> void: _zoom_dir = 1.0, func() -> void: _zoom_dir = 0.0)
	_add_hold_button(zoom_row, "+", func() -> void: _zoom_dir = -1.0, func() -> void: _zoom_dir = 0.0)

	var pan_row := HBoxContainer.new()
	pan_row.add_theme_constant_override("separation", 4)
	box.add_child(pan_row)
	var pan_label := Label.new()
	pan_label.text = "Pan"
	pan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pan_row.add_child(pan_label)
	var pan_grid := GridContainer.new()
	pan_grid.columns = 3
	pan_row.add_child(pan_grid)
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "^", Vector2(0, 1))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "<", Vector2(-1, 0))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, ">", Vector2(1, 0))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "v", Vector2(0, -1))
	pan_grid.add_child(_pan_spacer())

	var bubbles_row := HBoxContainer.new()
	bubbles_row.add_theme_constant_override("separation", 4)
	box.add_child(bubbles_row)
	var bubbles_label := Label.new()
	bubbles_label.text = "Bubbles"
	bubbles_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubbles_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubbles_row.add_child(bubbles_label)
	_bubbles_button = Button.new()
	_bubbles_button.text = BUBBLES_MODE_LABELS[_bubbles_mode]
	_bubbles_button.custom_minimum_size = Vector2(62, 32)
	_bubbles_button.pressed.connect(_on_bubbles_pressed)
	bubbles_row.add_child(_bubbles_button)

## Reference material, so it starts collapsed and the panel stays short.
func _build_legend_section(box: VBoxContainer) -> void:
	_legend_button = Button.new()
	_legend_button.text = "Legend  ▾"
	_legend_button.toggle_mode = true
	_legend_button.custom_minimum_size.y = 30
	_legend_button.add_theme_font_size_override("font_size", 12)
	_legend_button.toggled.connect(_on_legend_toggled)
	box.add_child(_legend_button)

	_legend_box = VBoxContainer.new()
	_legend_box.add_theme_constant_override("separation", 2)
	_legend_box.visible = false
	box.add_child(_legend_box)
	_add_legend_row(_legend_box, MarkerColors.SOURCE_COLOR, "Food source")
	_add_legend_row(_legend_box, MarkerColors.SETTLEMENT_COLOR, "Settlement")
	_add_legend_row(_legend_box, ROUTE_LEVEL_COLORS.dirt, "Dirt route")
	_add_legend_row(_legend_box, GameBalance.STORAGE_TYPES[GameEnums.StorageType.COOL].color, "Cool storage")
	_add_legend_row(_legend_box, GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].color, "Hub (build on any route tile)")
	_add_legend_row(_legend_box, Color("4FA8A0"), "Fork available -- Hub tool")
	_add_legend_row(_legend_box, Color("8B6B9C"), "Junction over the hub cap")
	_add_legend_row(_legend_box, Color("D98E4A"), "Tile near capacity (90%+)")
	_add_legend_row(_legend_box, Color("C4573A"), "Tile over capacity")
	_add_legend_row(_legend_box, RIVER_BRIDGE_COLOR, "River / river crossing")
	_add_legend_row(_legend_box, BRIDGE_DECK_COLOR, "Bridge deck -- routes cross, never join")

	# Which delivery line belongs to which supply (ROUTE-16). Built from the
	# map's own sources, so it can never drift from what's drawn out there.
	_add_section_title(_legend_box, "DELIVERY LINE BY SOURCE")
	var foods := GameBalance.food_types()
	for node in _map_data.node_placements:
		if node.node_type != GameEnums.NodeType.SOURCE:
			continue
		var food_names: Array[String] = []
		for food_id in node.produces:
			food_names.append(foods[food_id].display_name)
		_add_legend_row(_legend_box, _source_food_color(node.node_id), "%s (%s)" % [node.display_name, ", ".join(food_names)])

func _on_legend_toggled(pressed: bool) -> void:
	_legend_box.visible = pressed
	_legend_button.text = "Legend  ▴" if pressed else "Legend  ▾"
	if pressed:
		# The legend sits at the bottom of a panel that's taller than the
		# window once it's open, so scroll down to what the click just
		# revealed instead of making the player hunt for it. Two frames of
		# delay: one for the container to re-sort at its new height, one more
		# for the scrollbar's range to catch up -- setting the offset any
		# earlier just clamps it against the old, shorter range.
		await get_tree().process_frame
		await get_tree().process_frame
		_panel_scroll.scroll_vertical = roundi(_panel_scroll.get_v_scroll_bar().max_value)

func _pan_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = CONTROLLER_BUTTON_SIZE * 0.5
	return spacer

func _add_pan_button(parent: Container, text: String, dir: Vector2) -> void:
	_add_hold_button(parent, text, func() -> void: _pan_dir += dir, func() -> void: _pan_dir -= dir)

## Two-column row of build tools. Every tool button lives in one of these, so
## the eight tools take five rows instead of eight full-width bars.
func _add_tool_grid(parent: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid

## ---------- day clock (top-right) ----------

## The countdown to the next automatic day run, plus its transport controls
## (pause, speed, auto/manual) and the review button for the last report.
## Anchored to and grown leftward from the top-right corner, diagonally
## opposite the control panel so the two never crowd each other. The
## end-of-day summary card stacks directly beneath it.
const CLOCK_PANEL_WIDTH := 214.0
const CLOCK_PANEL_MARGIN := 12.0

func _build_day_clock(root: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_END
	column.offset_left = -CLOCK_PANEL_MARGIN
	column.offset_right = -CLOCK_PANEL_MARGIN
	column.offset_top = 12
	column.offset_bottom = 12
	column.custom_minimum_size.x = CLOCK_PANEL_WIDTH
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.92))
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	_clock_day_label = Label.new()
	_clock_day_label.text = "Day 1"
	_clock_day_label.add_theme_font_size_override("font_size", 15)
	_clock_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_clock_day_label)
	_clock_time_label = Label.new()
	_clock_time_label.text = "1:00"
	_clock_time_label.add_theme_font_size_override("font_size", 30)
	_clock_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_clock_time_label)

	_clock_bar = ProgressBar.new()
	_clock_bar.max_value = 100.0
	_clock_bar.value = 100.0
	_clock_bar.show_percentage = false
	_clock_bar.custom_minimum_size.y = 8
	box.add_child(_clock_bar)

	_clock_mode_label = Label.new()
	_clock_mode_label.add_theme_font_size_override("font_size", 11)
	_clock_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_clock_mode_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	box.add_child(controls)
	_pause_button = Button.new()
	_pause_button.text = "Pause ||"
	_pause_button.custom_minimum_size.y = 34
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.add_theme_font_size_override("font_size", 13)
	_pause_button.pressed.connect(_toggle_pause)
	controls.add_child(_pause_button)
	_speed_button = Button.new()
	_speed_button.text = GameBalance.DAY_SPEED_LABELS[0]
	_speed_button.custom_minimum_size = Vector2(46, 34)
	_speed_button.add_theme_font_size_override("font_size", 13)
	_speed_button.pressed.connect(_cycle_speed)
	controls.add_child(_speed_button)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	box.add_child(modes)
	_auto_button = Button.new()
	_auto_button.text = "Auto"
	_auto_button.toggle_mode = true
	_auto_button.button_pressed = _state.auto_run
	_auto_button.custom_minimum_size.y = 32
	_auto_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_button.add_theme_font_size_override("font_size", 13)
	_auto_button.toggled.connect(_toggle_auto_run)
	modes.add_child(_auto_button)
	_report_button = Button.new()
	_report_button.text = "Report"
	_report_button.custom_minimum_size.y = 32
	_report_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_button.add_theme_font_size_override("font_size", 13)
	_report_button.pressed.connect(_review_report)
	modes.add_child(_report_button)

	var run_now := Button.new()
	run_now.text = "Run Day Now ▸"
	run_now.custom_minimum_size.y = 34
	run_now.add_theme_font_size_override("font_size", 13)
	run_now.pressed.connect(_run_day)
	box.add_child(run_now)

	_summary_panel = PanelContainer.new()
	_summary_panel.add_theme_stylebox_override("panel", _panel_style(Color("19312c"), 0.94))
	_summary_panel.visible = false
	column.add_child(_summary_panel)
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.custom_minimum_size = Vector2(CLOCK_PANEL_WIDTH - 24, 0)
	_summary_label.add_theme_font_size_override("normal_font_size", 12)
	_summary_label.add_theme_font_size_override("bold_font_size", 12)
	_summary_panel.add_child(_summary_label)

func _add_hold_button(parent: Container, text: String, on_press: Callable, on_release: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = CONTROLLER_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", CONTROLLER_FONT_SIZE)
	button.button_down.connect(on_press)
	button.button_up.connect(on_release)
	parent.add_child(button)
	return button

func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)

## One captioned number in the status strip. Returns the value label, which
## _update_ui writes into.
func _add_stat_column(parent: HBoxContainer, caption: String, tooltip: String) -> Label:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.tooltip_text = tooltip
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", 15)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(value)
	return value

## A build-tool toggle. The short label keeps the panel narrow; the full
## explanation lives in the tooltip and, once selected, in the hint bar.
func _add_tool_button(parent: Container, text: String, tool: String, tooltip := "") -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_set_tool.bind(tool))
	parent.add_child(button)
	_tool_buttons.get_or_add(tool, []).append(button)

func _add_legend_row(parent: VBoxContainer, color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(13, 13)
	swatch.color = color
	row.add_child(swatch)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)

func _panel_style(color: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	color.a = alpha
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _show_toast(message: String, error := false) -> void:
	_toast.text = message
	_toast.add_theme_color_override("font_color", Color("ffc6bd") if error else Color("c8ffe3"))
	_toast.visible = true
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_callback(func() -> void: _toast.visible = false)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()
