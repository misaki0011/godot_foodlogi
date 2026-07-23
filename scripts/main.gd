extends Node3D

## Fresh Routes -- 3D isometric port of fresh-routes-mvp.html. The world is
## a tile grid (see GameState.grid / SimulationEngine): clicking places one
## tile at a time per the active tool, hubs auto-form at 3-way junctions,
## and hovering (desktop) or tapping (mobile, no dialog) any tile or node
## shows a live info tooltip. A top-left panel provides touch zoom/pan
## controls for exploring the map on mobile. See SPEC.md v0.3.

const REGION_MAP_PATH := "res://data/maps/region_1_map.tres"
const STORAGE_SCENE := preload("res://scenes/markers/storage_marker.tscn")
const HUB_SCENE := preload("res://scenes/markers/hub_marker.tscn")
const FOOD_BUBBLE_SCENE := preload("res://scenes/markers/food_bubble_marker.tscn")

const ROUTE_LEVEL_SCENES := {
	"dirt": preload("res://assets/Blocks/glTF/Block_Road_Dirt.glb"),
	"paved": preload("res://assets/Blocks/glTF/Block_Road_Paved.glb"),
	"main": preload("res://assets/Blocks/glTF/Block_Road_Main.glb"),
}
## Corner (L-shape) variants. Paved has none -- its existing block is 4
## symmetric corner stones that already read fine unrotated for any shape
## (see generate_blocks.py). Falls back to ROUTE_LEVEL_SCENES when absent.
const ROUTE_CORNER_SCENES := {
	"dirt": preload("res://assets/Blocks/glTF/Block_Road_Dirt_Corner.glb"),
	"main": preload("res://assets/Blocks/glTF/Block_Road_Main_Corner.glb"),
}
## Y-axis yaw for each facing. Straight blocks' tread already runs N-S at 0
## rotation (see generate_blocks.py), so "ud" needs none and "lr" needs a
## quarter turn. Corner blocks are authored connecting N+E ("ne") at 0
## rotation. A positive rotation_degrees.y is counter-clockwise as seen by
## this top-down camera (world +Z is south, so +Y points toward the viewer),
## so each quarter turn advances N+E counter-clockwise: 90 -> N+W ("nw"),
## 180 -> S+W ("sw"), 270 -> S+E ("se"). (Earlier "se"/"nw" were swapped,
## which rendered a down-right corner as an up-left one and vice versa.)
const ROUTE_FACING_YAW := {"ud": 0.0, "lr": 90.0, "ne": 0.0, "nw": 90.0, "sw": 180.0, "se": 270.0}
const ROUTE_LEVEL_HEIGHTS := {"dirt": 0.22, "paved": 0.22, "main": 0.24} # must match tools/asset_gen/generate_blocks.py

const ROUTE_LEVEL_COLORS := {"dirt": Color("B99A6B"), "paved": Color("9C8F7A"), "main": Color("6E6252")}
const BRIDGE_COLOR := Color("8FB9D8")
const GRADE_COLORS := {"S": Color("C9A227"), "A": Color("5C8A5C"), "B": Color("5B8FA8"), "C": Color("D98E4A"), "D": Color("C4573A")}
const STORAGE_TOOLS := {"normal": GameEnums.StorageType.NORMAL, "cool": GameEnums.StorageType.COOL, "freeze": GameEnums.StorageType.FREEZE}
const ZOOM_MIN := 14.0
const ZOOM_MAX := 60.0
const ZOOM_SPEED := 24.0 # camera.size units/sec while a zoom button is held
const PAN_SPEED := 16.0 # world units/sec at the default zoom level, scales with zoom
const PAN_MAP_MARGIN := 10.0 # world units of empty space pannable past the map edge
const HOLD_TO_DRAG_MSEC := 350 # how long a press must hold still before route drawing switches to drag mode
const TOOL_HINTS := {
	"route": "Tap an empty tile adjacent to a node or existing route to place one, or tap a built tile to flip its shape. Press and hold, then drag, to preview a whole path -- release to build it (nothing is built if the path isn't valid).",
	"upgrade": "Click a Dirt or Paved route tile to upgrade it.",
	"normal": "Click an existing route tile to build Normal Storage there (good for grain, bread).",
	"cool": "Click an existing route tile to build Cool Storage there (good for vegetables, milk).",
	"freeze": "Click an existing route tile to build Freeze Storage there (good for seafood -- some foods dislike freezing).",
	"hubRegional": "Click an existing Small Hub (formed at a 3-way junction) to upgrade it to Regional for §200.",
	"remove": "Click a built tile to bulldoze it (no refund).",
}

@onready var _terrain: TerrainRenderer = $TerrainMap
@onready var _node_spawner: NodeSpawner = $NodeMarkers
@onready var _camera: Camera3D = $Camera3D

var _map_data: MapData
var _state := GameState.new()
var _tool := "route"
var _nodes_by_pos: Dictionary = {}
var _nodes_by_id: Dictionary = {}
var _grid_visuals: Node3D
var _bubbles_visible := true

var _funds_label: Label
var _day_label: Label
var _best_grade_label: Label
var _best_score_label: Label
var _avg_score_label: Label
var _hint_label: Label
var _toast: Label
var _bubbles_button: Button
var _tool_buttons: Dictionary = {}
var _tip_panel: PanelContainer
var _tip_label: RichTextLabel
var _report_overlay: Control
var _report_sub: Label
var _report_text: RichTextLabel
var _report_banner: Label
var _default_camera_size: float
var _map_bounds_min: Vector2
var _map_bounds_max: Vector2
var _pan_dir := Vector2.ZERO
var _zoom_dir := 0.0

## ---------- route draw: tap-to-cycle vs. hold-and-drag ----------
## A press on a non-node cell while the "route" tool is active starts out
## eligible for hold-to-drag; _process() promotes it to _drag_active once
## held past HOLD_TO_DRAG_MSEC without releasing. A release before that
## threshold -- or a release without ever dragging to a second cell -- is a
## normal tap (dispatched to _handle_click as before). This is why a plain
## tap's build/cycle action now fires on release rather than on press --
## until release (or the hold threshold), there's no way to know whether
## the gesture will turn into a drag.
##
## While dragging, nothing is written to _state.grid: _drag_path just
## records every cell the pointer has crossed, _recompute_drag_validity()
## re-derives which of those are real new tiles to build (skipping nodes
## and already-built cells as harmless pass-through waypoints) and
## whether the whole path is affordable/connected/under the hub cap, and
## _update_drag_preview() draws a translucent line so the player can see
## the path (green) or why it's rejected (red) before committing anything.
## The actual tiles -- with their final, correct auto-tile shapes, since
## _render_grid() always recomputes those from the real grid -- are only
## written to _state.grid on release, and only if the whole path is valid;
## an invalid path builds nothing at all, matching ROUTE-01's single-tile
## transactional placement.
var _press_eligible := false
var _press_cell := Vector2i(-1, -1)
var _press_start_msec := 0
var _drag_active := false
var _drag_path: Array[Vector2i] = []
var _drag_new_cells: Array[Vector2i] = []
var _drag_valid := true
var _drag_invalid_reason := ""
var _drag_preview_visuals: Node3D

const DRAG_PREVIEW_VALID_COLOR := Color(0.4, 0.85, 0.45, 0.6)
const DRAG_PREVIEW_INVALID_COLOR := Color(0.85, 0.3, 0.3, 0.6)

## Overlay marking established (source->settlement) routes -- a bright, mostly
## opaque gold line floating just above the road surface (see
## _render_established_routes).
const ESTABLISHED_ROUTE_COLOR := Color(1.0, 0.83, 0.29, 0.9)
const ESTABLISHED_ROUTE_Y := 1.55

func _ready() -> void:
	_map_data = load(REGION_MAP_PATH)
	_state.balance = GameBalance.STARTING_FUNDS
	for node in _map_data.node_placements:
		_nodes_by_pos[node.grid_position] = node
		_nodes_by_id[node.node_id] = node
	_terrain.render(_map_data)
	_node_spawner.spawn(_map_data, _terrain)
	_grid_visuals = Node3D.new()
	_grid_visuals.name = "GridVisuals"
	add_child(_grid_visuals)
	_drag_preview_visuals = Node3D.new()
	_drag_preview_visuals.name = "DragPreviewVisuals"
	add_child(_drag_preview_visuals)
	_render_grid()
	_default_camera_size = _camera.size
	var min_corner: Vector3 = _terrain.map_to_local(Vector3i(0, 0, 0))
	var max_corner: Vector3 = _terrain.map_to_local(Vector3i(_map_data.grid_size.x - 1, 0, _map_data.grid_size.y - 1))
	_map_bounds_min = Vector2(min_corner.x, min_corner.z)
	_map_bounds_max = Vector2(max_corner.x, max_corner.z)
	_build_ui()
	_set_tool("route")
	_update_ui()

func _process(delta: float) -> void:
	if _report_overlay.visible:
		_pan_dir = Vector2.ZERO
		_zoom_dir = 0.0
		return
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
		_tip_panel.visible = false
		_drag_path = [_press_cell]
		_recompute_drag_validity()
		_update_drag_preview()

func _unhandled_input(event: InputEvent) -> void:
	if _report_overlay.visible:
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
			_update_tip(_screen_to_cell(event.position), event.position)

func _start_press(screen_position: Vector2) -> void:
	var cell := _screen_to_cell(screen_position)
	_press_cell = cell
	_press_start_msec = Time.get_ticks_msec()
	_drag_active = false
	# Only a route-tool press on a real, buildable (non-node) cell can turn
	# into a drag -- other tools and node taps behave exactly as a normal
	# click on release, same as before hold-to-drag existed.
	_press_eligible = _tool == "route" and _cell_in_bounds(cell) and _node_at(cell) == null

func _end_press(screen_position: Vector2) -> void:
	if _drag_active:
		_drag_active = false
		_press_eligible = false
		# A hold-then-release without ever dragging to a second cell is a
		# plain tap on the pressed cell (build, or cycle its shape) --
		# holding still shouldn't behave differently from tapping.
		if _drag_path.size() > 1:
			_commit_drag()
		else:
			_handle_click(_press_cell)
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

## Re-derives, from scratch, which cells in _drag_path are real new tiles to
## build (_drag_new_cells) and whether the whole path is valid: every new
## cell must connect to the existing network or an earlier tile already
## queued in this same drag, none may push a junction past the hub cap, and
## the total cost must fit the current treasury. Node cells and cells
## already built are harmless pass-through waypoints, not failures. Runs
## against a scratch grid copy, matching would_exceed_hub_cap's own
## preview-without-mutating pattern -- _state.grid is never touched here.
func _recompute_drag_validity() -> void:
	_drag_valid = true
	_drag_invalid_reason = ""
	_drag_new_cells.clear()
	var temp_grid: Dictionary = _state.grid.duplicate()
	var temp_state := GameState.new()
	temp_state.grid = temp_grid
	var total_cost := 0.0
	for cell in _drag_path:
		if _node_at(cell) or temp_grid.has(cell):
			continue
		var adjacent := false
		for n in _neighbor_cells(cell):
			if temp_grid.has(n) or _nodes_by_pos.has(n):
				adjacent = true
				break
		if not adjacent:
			_drag_valid = false
			_drag_invalid_reason = "That path isn't connected -- try dragging more slowly."
			break
		if SimulationEngine.would_exceed_hub_cap(temp_state, _nodes_by_pos, cell):
			_drag_valid = false
			_drag_invalid_reason = "That path would need a hub beyond the network's cap."
			break
		total_cost += SimulationEngine.route_build_cost(cell, _map_data)
		temp_grid[cell] = {"kind": "route", "level": "dirt"}
		_drag_new_cells.append(cell)
	if _drag_valid and total_cost > _state.balance:
		_drag_valid = false
		_drag_invalid_reason = "Not enough treasury for the whole path (§%d needed)." % roundi(total_cost)

## Writes every queued new tile from a valid drag path to _state.grid in one
## batch, then runs the usual post-build pass once for the whole gesture
## (hub formation, re-render -- which recomputes each tile's shape from its
## final real adjacency, so the path renders with correct shapes exactly as
## if each tile had been tapped individually). An invalid path, or one with
## nothing new to build, places nothing at all.
func _commit_drag() -> void:
	if not _drag_valid:
		_show_toast(_drag_invalid_reason if _drag_invalid_reason != "" else "That path is invalid -- nothing built.", true)
		return
	if _drag_new_cells.is_empty():
		_show_toast("Nothing new to build along that path.", true)
		return
	for cell in _drag_new_cells:
		_state.balance -= SimulationEngine.route_build_cost(cell, _map_data)
		_state.grid[cell] = {"kind": "route", "level": "dirt"}
	_show_toast("Route drawn: %d tile%s." % [_drag_new_cells.size(), "" if _drag_new_cells.size() == 1 else "s"])
	_after_action()

func _clear_drag_preview() -> void:
	_clear_children(_drag_preview_visuals)
	_drag_path.clear()
	_drag_new_cells.clear()

## Translucent green (valid) or red (invalid) boxes on every crossed cell,
## connected by thin bars between orthogonal neighbors, so the path reads
## as a continuous line rather than disconnected dots. Purely visual --
## _state.grid isn't touched until _commit_drag().
func _update_drag_preview() -> void:
	_clear_children(_drag_preview_visuals)
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
func _add_established_marker(pos: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.1, 0.34)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _drag_preview_material(ESTABLISHED_ROUTE_COLOR)
	_grid_visuals.add_child(mesh_instance)

## A thin gold bar joining two adjacent established points (tile-tile or
## tile-node); `a` and `b` are one grid step apart, so it's axis-aligned.
func _add_established_segment(a: Vector3, b: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var diff := b - a
	mesh.size = Vector3(absf(diff.x) + 0.18, 0.08, absf(diff.z) + 0.18) if absf(diff.x) > absf(diff.z) else Vector3(0.18, 0.08, absf(diff.z) + 0.18)
	mesh_instance.mesh = mesh
	mesh_instance.position = (a + b) * 0.5
	mesh_instance.material_override = _drag_preview_material(ESTABLISHED_ROUTE_COLOR)
	_grid_visuals.add_child(mesh_instance)

func _handle_click(cell: Vector2i, screen_position := Vector2.ZERO) -> void:
	if not _cell_in_bounds(cell):
		return
	var n := _node_at(cell)
	if n:
		# Sources and settlements are informational, not buildable -- tapping
		# (mobile has no hover) shows the same info tip a mouse hover would.
		_update_tip(cell, screen_position)
		return
	_tip_panel.visible = false
	match _tool:
		"route":
			_do_build_route(cell)
		"upgrade":
			_do_upgrade_route(cell)
		"normal", "cool", "freeze":
			_do_build_storage(cell)
		"hubRegional":
			_do_upgrade_hub(cell)
		"remove":
			_do_bulldoze(cell)
	_after_action()

const FACING_LABELS := {"lr": "Left-Right", "ud": "Up-Down", "ne": "corner (North-East)", "se": "corner (South-East)", "sw": "corner (South-West)", "nw": "corner (North-West)"}

func _do_build_route(cell: Vector2i) -> void:
	if _state.grid.has(cell):
		var cell_data = _state.grid[cell]
		if cell_data.kind == "route" and SimulationEngine.is_shape_ambiguous(cell, _state, _nodes_by_pos):
			var facing: String = SimulationEngine.cycle_shape_facing(cell, _state, _nodes_by_pos)
			cell_data.facing = facing
			_show_toast("Flipped to %s." % FACING_LABELS.get(facing, facing))
			return
		_show_toast("Already built here.", true)
		return
	if not _adjacent_to_network(cell):
		_show_toast("Route must connect to a node or existing route.", true)
		return
	if SimulationEngine.would_exceed_hub_cap(_state, _nodes_by_pos, cell):
		_show_toast("Can't place this road: it would need a 3rd hub, but each connected network can only support %d. Try routing around this junction." % GameBalance.HUB_CAP_PER_NETWORK, true)
		return
	var cost := SimulationEngine.route_build_cost(cell, _map_data)
	if _state.balance < cost:
		_show_toast("Not enough treasury (§%d needed)." % roundi(cost), true)
		return
	_state.balance -= cost
	_state.grid[cell] = {"kind": "route", "level": "dirt"}
	_show_toast("Route built for §%d." % roundi(cost))

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

func _do_build_storage(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "route":
		_show_toast("Storage must be built on an existing route tile.", true)
		return
	var stype: GameEnums.StorageType = STORAGE_TOOLS[_tool]
	var st = GameBalance.STORAGE_TYPES[stype]
	if _state.balance < st.build:
		_show_toast("Not enough treasury (§%d needed)." % roundi(st.build), true)
		return
	_state.balance -= st.build
	_state.grid[cell] = {"kind": "storage", "stype": stype}
	_show_toast("%s built for §%d." % [st.name, roundi(st.build)])

func _do_upgrade_hub(cell: Vector2i) -> void:
	var cell_data = _state.grid.get(cell)
	if cell_data == null or cell_data.kind != "hub" or cell_data.htype != GameEnums.HubType.SMALL:
		_show_toast("Select an existing Small Hub to upgrade.", true)
		return
	var cost := GameBalance.HUB_REGIONAL_UPGRADE_COST
	if _state.balance < cost:
		_show_toast("Not enough treasury (§%d needed)." % roundi(cost), true)
		return
	_state.balance -= cost
	cell_data.htype = GameEnums.HubType.REGIONAL
	_show_toast("Upgraded to Regional Hub for §%d." % roundi(cost))

func _do_bulldoze(cell: Vector2i) -> void:
	if not _state.grid.has(cell):
		_show_toast("Nothing to remove here.", true)
		return
	_state.grid.erase(cell)
	_show_toast("Tile cleared.")

func _after_action() -> void:
	var messages := SimulationEngine.check_auto_hubs(_state, _nodes_by_pos)
	for m in messages:
		var sep := m.find(":")
		_show_toast(m.substr(sep + 1), not m.begins_with("ok:"))
	_render_grid()
	_update_ui()

func _end_day() -> void:
	var report := SimulationEngine.run_day(_state, _map_data.node_placements)
	_show_report(report)
	_render_grid()
	_update_ui()

func _close_report() -> void:
	_report_overlay.visible = false
	_state.day += 1
	_update_ui()

## ---------- hover tooltip ----------

func _update_tip(cell: Vector2i, mouse_pos: Vector2) -> void:
	if not _cell_in_bounds(cell):
		_tip_panel.visible = false
		return
	var n := _node_at(cell)
	var cell_data = _state.grid.get(cell)
	var text := ""
	if n:
		if n.node_type == GameEnums.NodeType.SOURCE:
			var parts := []
			for food_id in n.produces:
				parts.append("%s (%d/day)" % [GameBalance.food_types()[food_id].display_name, roundi(n.produces[food_id])])
			text = "[b]%s[/b]\nProduces: %s" % [n.display_name, ", ".join(parts)]
		else:
			text = _settlement_tip_text(n)
	elif cell_data:
		if cell_data.kind == "route":
			var lvl = GameBalance.ROUTE_LEVELS[cell_data.level]
			text = "[b]%s Route[/b]\nCapacity: %d/day\nUpkeep ×%.1f" % [lvl.label, roundi(lvl.cap), lvl.upkeep_mult]
			if cell_data.get("needs_hub", false):
				text += "\n[color=orange]⚠ 3-way junction -- needs a §150 hub, funds too low[/color]"
			elif cell_data.get("hub_capped", false):
				text += "\n[color=orange]⚠ 3-way junction -- this road already has %d hubs[/color]" % GameBalance.HUB_CAP_PER_NETWORK
		elif cell_data.kind == "storage":
			var st = GameBalance.STORAGE_TYPES[cell_data.stype]
			text = "[b]%s[/b]\nUpkeep: §%d/day\nProtects next %d tiles at %d%% decay" % [st.name, roundi(st.upkeep), st.protection, roundi(st.mult * 100)]
		elif cell_data.kind == "hub":
			var ht = GameBalance.HUB_TYPES[cell_data.htype]
			text = "[b]%s[/b]\nUpkeep: §%d/day\nDiscounts adjacent routes %d%%" % [ht.name, roundi(ht.upkeep), roundi(ht.discount * 100)]
			var split := SimulationEngine.hub_split_summary(_state, cell)
			if split.total > 0.0:
				var lines := []
				for src_id in split.by_source:
					var src: NodeData = _nodes_by_id.get(src_id)
					var pct := roundi(split.by_source[src_id] / split.total * 100.0)
					lines.append("%s: %d (%d%%)" % [src.display_name if src else src_id, roundi(split.by_source[src_id]), pct])
				text += "\n\n[b]Last run split (%d total):[/b]\n%s" % [roundi(split.total), "\n".join(lines)]
			else:
				text += "\n\n[i]No deliveries routed through here yet.[/i]"
		for c in _state.last_congestion:
			if c.pos == cell:
				text += ("\n[color=orange]! Hit 100%%+ capacity on the last run -- deliveries were capped here[/color]" if c.over
					else "\n[color=orange]! Ran 90%+ of capacity on the last run -- close to a bottleneck[/color]")
	elif _map_data.is_river(cell.x, cell.y):
		text = "[b]River[/b]\nBuilding here requires a bridge (+§%d)." % GameBalance.BRIDGE_COST
	if text == "":
		_tip_panel.visible = false
		return
	_tip_label.text = text
	_tip_panel.visible = true
	_tip_panel.position = mouse_pos + Vector2(16, 12)

## ---------- settlement tip ----------

func _settlement_tip_text(n: NodeData) -> String:
	var parts := []
	for food_id in n.demand:
		parts.append("%s %d" % [GameBalance.food_types()[food_id].display_name, roundi(n.demand[food_id])])
	var text := "[b]%s[/b] -- %s\nWants: %s\nMin freshness: %d%% · Bonus at: %d%%+\n" % [n.display_name, n.kind, ", ".join(parts), roundi(n.min_freshness), roundi(n.bonus_freshness)]
	var status = _state.last_settlement_status.get(n.node_id)
	if status == null:
		text += "\n[i]No deliveries yet -- run a day to see what's getting through.[/i]"
		return text
	text += "\n[b]Last delivery:[/b]\n"
	for food_id in n.demand:
		var s = status.get(food_id, {"requested": n.demand[food_id], "delivered": 0.0, "rejected": 0.0, "fresh_sum": 0.0})
		var done: bool = s.delivered >= s.requested - 0.5
		var partial: bool = not done and s.delivered > 0.0
		var icon := "✓" if done else ("◐" if partial else "✗")
		var color := "#5C8A5C" if done else ("#D98E4A" if partial else "#C4573A")
		var fresh_text := ""
		if s.delivered > 0.0:
			fresh_text = " · %d%% fresh" % roundi(s.fresh_sum / s.delivered)
		text += "[color=%s]%s[/color] %s: %d/%d%s\n" % [color, icon, GameBalance.food_types()[food_id].display_name, roundi(s.delivered), roundi(s.requested), fresh_text]
		if s.rejected > 0.0:
			text += "  [color=#C4573A]%d arrived too spoiled to accept[/color]\n" % roundi(s.rejected)
	return text

## ---------- daily report ----------

func _show_report(r: DayReportData) -> void:
	_report_sub.text = "Day %d" % _state.day
	var text := ""
	text += "Income: §%d\n" % roundi(r.income)
	text += "Route upkeep: −§%d\n" % roundi(r.route_upkeep)
	text += "Storage upkeep: −§%d\n" % roundi(r.storage_upkeep)
	text += "Hub upkeep: −§%d\n" % roundi(r.hub_upkeep)
	text += "Spoilage cost: −§%d\n" % roundi(r.spoilage_cost)
	text += "[b]Profit: %s§%d[/b]\n\n" % ["+" if r.profit >= 0 else "", roundi(r.profit)]
	text += "Average freshness delivered: %d%%\n" % roundi(r.avg_freshness_overall)
	text += "Waste (unmet + rejected demand): %d%%\n" % roundi(r.waste_pct)
	if r.capacity_blocked > 0.0:
		text += "[color=#C4573A]⚠ Blocked by route capacity: %d food[/color]\n" % roundi(r.capacity_blocked)
	text += "Settlement happiness: %d%%\n" % roundi(r.avg_happiness)
	var grade_color: String = GRADE_COLORS.get(r.grade, Color.WHITE).to_html(false)
	text += "Network efficiency grade: [b][color=#%s]%s[/color][/b] (score %d/100)\n\n" % [grade_color, r.grade, roundi(r.grade_score)]
	text += "[b]Per-settlement[/b]\n"
	for s in r.settlement_scores:
		text += "%s: %d%% happy · %d%% fresh\n" % [s.settlement.display_name, roundi(s.sat), roundi(s.avg_fresh)]
	_report_text.text = text
	if r.is_personal_best and _state.day > 1:
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
	for pos in _state.grid:
		var cell = _state.grid[pos]
		var world_pos: Vector3 = _terrain.map_to_local(Vector3i(pos.x, 0, pos.y)) + Vector3(0, 1.0, 0)
		if cell.kind == "route":
			if _map_data.is_river(pos.x, pos.y):
				_add_tile_box(world_pos, BRIDGE_COLOR, 0.16)
			else:
				var shape := SimulationEngine.route_shape(pos, _state, _nodes_by_pos)
				_add_route_block(world_pos, cell.level, shape.family, shape.facing)
			if cell.get("needs_hub", false):
				_add_warning_ring(world_pos, Color("C4573A"))
			elif cell.get("hub_capped", false):
				_add_warning_ring(world_pos, Color("8B6B9C"))
		elif cell.kind == "storage":
			var marker: NodeMarker = STORAGE_SCENE.instantiate()
			_grid_visuals.add_child(marker)
			marker.position = world_pos
			marker.apply_tint(MarkerColors.storage_color(cell.stype))
		elif cell.kind == "hub":
			var marker: NodeMarker = HUB_SCENE.instantiate()
			_grid_visuals.add_child(marker)
			marker.position = world_pos
			marker.apply_tint(MarkerColors.hub_color(cell.htype))
	for c in _state.last_congestion:
		var world_pos: Vector3 = _terrain.map_to_local(Vector3i(c.pos.x, 0, c.pos.y)) + Vector3(0, 1.35, 0)
		_add_congestion_marker(world_pos, c.over)
	_render_established_routes()
	if _bubbles_visible:
		_render_supply_bubbles()

## Continuously overlays a bright line along every tile that lies on a
## complete source->settlement path (an "established route"), so the player
## can see at a glance which roads actually link a source to a customer.
## Dead-end stubs -- roads that branch off but reach no settlement (or no
## source) -- are pruned out and left unmarked. Rebuilt every _render_grid,
## so it stays live as the network is edited or simulated.
func _render_established_routes() -> void:
	var established := _established_route_cells()
	if established.is_empty():
		return
	# Draw a dot on each established tile and a bar to each established
	# orthogonal neighbor (tile or node), so the marks read as one connected
	# line running through the road and into the source/settlement it links.
	for cell in established:
		var here: Vector3 = _terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, ESTABLISHED_ROUTE_Y, 0)
		_add_established_marker(here)
		for d in DIRECTIONS:
			var n: Vector2i = cell + d
			# One bar per undirected pair (only step east/south) toward another
			# established tile, or toward a node this established tile feeds.
			if d != Vector2i(1, 0) and d != Vector2i(0, 1):
				continue
			var links := established.has(n) or (_nodes_by_pos.has(n) and _feeds_established(n, established))
			if links:
				var there: Vector3 = _terrain.map_to_local(Vector3i(n.x, 0, n.y)) + Vector3(0, ESTABLISHED_ROUTE_Y, 0)
				_add_established_segment(here, there)

## The set (Vector2i -> true) of built tiles on some complete source->
## settlement path -- see SimulationEngine.established_route_cells for the
## exact rule (road-only connectivity that must start at a source).
func _established_route_cells() -> Dictionary:
	return SimulationEngine.established_route_cells(_state, _nodes_by_pos)

## True when node `node_pos` (a source/settlement) is adjacent to at least
## one kept established tile -- i.e. the overlay line should reach into it.
func _feeds_established(node_pos: Vector2i, established: Dictionary) -> bool:
	for d in DIRECTIONS:
		if established.has(node_pos + d):
			return true
	return false

## Always-on speech bubbles showing "current/max" for every source and
## settlement: a source's amount drawn today vs. its daily produce
## (SimulationEngine.run_day's last_source_status), muted once fully
## tapped out; a settlement's delivered vs. requested amount per food
## plus average freshness (last_settlement_status), colored red/amber/
## green by combined amount+freshness status (see
## _render_settlement_bubbles). Both read as "0/max" before the first
## simulated day, since neither dictionary has entries yet.
func _render_supply_bubbles() -> void:
	var foods := GameBalance.food_types()
	for pos in _nodes_by_pos:
		var n: NodeData = _nodes_by_pos[pos]
		if n.node_type == GameEnums.NodeType.SOURCE:
			_render_source_bubbles(n, pos, foods)
		elif n.node_type == GameEnums.NodeType.SETTLEMENT:
			_render_settlement_bubbles(n, pos, foods)

func _render_source_bubbles(n: NodeData, pos: Vector2i, foods: Dictionary) -> void:
	var status: Dictionary = _state.last_source_status.get(n.node_id, {})
	# The source's crate model is shorter than the settlement pin, so its
	# bubble sits a little lower than the settlement stack's start height.
	var base_pos: Vector3 = _terrain.map_to_local(Vector3i(pos.x, 0, pos.y)) + Vector3(0, 2.5, 0)
	var stack := 0
	for food_id in n.produces:
		var produced: float = n.produces[food_id]
		var used: float = 0.0
		if status.has(food_id):
			used = status[food_id].used
		var bubble_status := FoodBubbleMarker.Status.MUTED if used >= produced - 0.01 else FoodBubbleMarker.Status.DEFAULT
		var bubble: FoodBubbleMarker = FOOD_BUBBLE_SCENE.instantiate()
		_grid_visuals.add_child(bubble)
		bubble.position = base_pos + Vector3(0, stack * FoodBubbleMarker.STACK_SPACING, 0)
		bubble.setup(foods[food_id], used, produced, bubble_status)
		stack += 1

## A settlement can demand up to 3 foods (Town D, City E), and some
## settlements sit only 3 tiles from a neighbor -- stacking every bubble
## in a single tall column risked visually crowding the neighbor's own
## bubbles. A 2-column grid caps the stack at 2 rows regardless of how
## many foods are demanded.
## Combined amount+freshness status, "weakest link" rule: RED whenever
## nothing has arrived yet or what arrived came in below this
## settlement's own min_freshness (regardless of amount); GREEN only
## when the full requested amount arrived at bonus_freshness or above;
## AMBER for every other combination (partial amount, or full amount but
## sub-bonus freshness).
func _render_settlement_bubbles(n: NodeData, pos: Vector2i, foods: Dictionary) -> void:
	var status = _state.last_settlement_status.get(n.node_id, {})
	# NodeMarker puts the settlement pin's head at +2.1 (node_spawner.gd's
	# +1.0 root offset plus node_marker_base.tscn's local offset), so start
	# above it -- otherwise this billboard sits inside the pin head and the
	# two fuse into an unreadable blob.
	var base_pos: Vector3 = _terrain.map_to_local(Vector3i(pos.x, 0, pos.y)) + Vector3(0, 3.1, 0)
	var index := 0
	for food_id in n.demand:
		var requested: float = n.demand[food_id]
		var delivered: float = 0.0
		var avg_fresh: float = 0.0
		var s = status.get(food_id)
		if s != null:
			requested = s.requested
			delivered = s.delivered
			if delivered > 0.0:
				avg_fresh = s.fresh_sum / delivered

		var bubble_status: FoodBubbleMarker.Status
		var freshness_pct := -1
		if delivered <= 0.0:
			bubble_status = FoodBubbleMarker.Status.RED
		else:
			freshness_pct = roundi(avg_fresh)
			if avg_fresh < n.min_freshness:
				bubble_status = FoodBubbleMarker.Status.RED
			elif delivered >= requested - 0.01 and avg_fresh >= n.bonus_freshness:
				bubble_status = FoodBubbleMarker.Status.GREEN
			else:
				bubble_status = FoodBubbleMarker.Status.AMBER

		var row := index / 2
		var col := index % 2
		var col_offset: float = (col - 0.5) * FoodBubbleMarker.COLUMN_SPACING
		var bubble: FoodBubbleMarker = FOOD_BUBBLE_SCENE.instantiate()
		_grid_visuals.add_child(bubble)
		bubble.position = base_pos + Vector3(col_offset, row * FoodBubbleMarker.STACK_SPACING, 0)
		bubble.setup(foods[food_id], delivered, requested, bubble_status, freshness_pct)
		index += 1

func _add_route_block(pos: Vector3, level: String, family := "straight", facing := "ud") -> void:
	var scene: PackedScene = ROUTE_CORNER_SCENES.get(level) if family == "corner" else null
	if scene == null:
		scene = ROUTE_LEVEL_SCENES.get(level)
	if scene == null:
		_add_tile_box(pos, ROUTE_LEVEL_COLORS.get(level, Color.WHITE), 0.16)
		return
	var block: Node3D = scene.instantiate()
	_grid_visuals.add_child(block)
	block.position = pos + Vector3(0, ROUTE_LEVEL_HEIGHTS.get(level, 0.22) * 0.5, 0)
	# No scale needed: the block's footprint is authored at the real 2x2
	# world-space cell size already (see generate_blocks.py).
	if family != "junction":
		block.rotation_degrees.y = ROUTE_FACING_YAW.get(facing, 0.0)

func _add_tile_box(pos: Vector3, color: Color, height: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_terrain.cell_size.x, height, _terrain.cell_size.z)
	mesh_instance.mesh = mesh
	mesh_instance.position = pos + Vector3(0, height * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	_grid_visuals.add_child(mesh_instance)

func _add_warning_ring(pos: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.35
	mesh.outer_radius = 0.5
	mesh_instance.mesh = mesh
	mesh_instance.position = pos + Vector3(0, 0.3, 0)
	mesh_instance.rotation_degrees = Vector3(90, 0, 0)
	var material := StandardMaterial3D.new()
	color.a = 0.85
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	_grid_visuals.add_child(mesh_instance)

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

func _adjacent_to_network(cell: Vector2i) -> bool:
	for n in _neighbor_cells(cell):
		if _state.grid.has(n) or _nodes_by_pos.has(n):
			return true
	return false

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func _neighbor_cells(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		var n := cell + d
		if _cell_in_bounds(n):
			result.append(n)
	return result

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

func _on_bubbles_toggled(pressed: bool) -> void:
	_bubbles_visible = pressed
	_bubbles_button.text = "On" if pressed else "Off"
	_render_grid()

func _update_ui() -> void:
	if _funds_label == null:
		return
	_funds_label.text = "§ %d" % roundi(_state.balance)
	_day_label.text = "%d" % _state.day
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

	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -300
	side.offset_top = 12
	side.offset_right = -12
	side.offset_bottom = -12
	side.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.94))
	root.add_child(side)
	var side_scroll := ScrollContainer.new()
	side.add_child(side_scroll)
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 10)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_box)

	_add_section_title(side_box, "TREASURY -- DAY")
	var treasury_row := HBoxContainer.new()
	side_box.add_child(treasury_row)
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 14)
	treasury_row.add_child(_day_label)
	_funds_label = Label.new()
	_funds_label.add_theme_font_size_override("font_size", 20)
	_funds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	treasury_row.add_child(_funds_label)

	side_box.add_child(HSeparator.new())
	_add_section_title(side_box, "EFFICIENCY CHASE")
	_best_grade_label = _add_stat_row(side_box, "Best grade so far")
	_best_score_label = _add_stat_row(side_box, "Best day score")
	_avg_score_label = _add_stat_row(side_box, "Last 7-day average")

	side_box.add_child(HSeparator.new())
	_add_section_title(side_box, "BUILD -- INFRASTRUCTURE")
	_add_tool_button(side_box, "Draw Route  (§8/tile, +§40 bridge)", "route")
	_add_tool_button(side_box, "Upgrade Route  (Dirt→Paved→Main)", "upgrade")
	_add_section_title(side_box, "BUILD -- STORAGE")
	_add_tool_button(side_box, "Normal Storage  §80", "normal")
	_add_tool_button(side_box, "Cool Storage  §180", "cool")
	_add_tool_button(side_box, "Freeze Storage  §400", "freeze")
	_add_section_title(side_box, "BUILD -- HUBS")
	var hub_note := Label.new()
	hub_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	hub_note.text = "Hubs form automatically at 3-way forks (auto-charged, §150) -- each connected road network can only support %d hubs." % GameBalance.HUB_CAP_PER_NETWORK
	hub_note.add_theme_font_size_override("font_size", 11)
	side_box.add_child(hub_note)
	_add_tool_button(side_box, "Upgrade to Regional Hub  §%d" % roundi(GameBalance.HUB_REGIONAL_UPGRADE_COST), "hubRegional")
	_add_section_title(side_box, "BUILD -- OTHER")
	_add_tool_button(side_box, "Bulldoze  (remove a tile)", "remove")

	side_box.add_child(HSeparator.new())
	_add_section_title(side_box, "LEGEND")
	_add_legend_row(side_box, MarkerColors.SOURCE_COLOR, "Food source")
	_add_legend_row(side_box, MarkerColors.SETTLEMENT_COLOR, "Settlement")
	_add_legend_row(side_box, ROUTE_LEVEL_COLORS.dirt, "Dirt route")
	_add_legend_row(side_box, GameBalance.STORAGE_TYPES[GameEnums.StorageType.COOL].color, "Cool storage")
	_add_legend_row(side_box, GameBalance.STORAGE_TYPES[GameEnums.StorageType.FREEZE].color, "Freeze storage")
	_add_legend_row(side_box, GameBalance.HUB_TYPES[GameEnums.HubType.SMALL].color, "Hub (auto-forms at forks)")
	_add_legend_row(side_box, Color("C4573A"), "Junction needs a hub (low funds)")
	_add_legend_row(side_box, Color("8B6B9C"), "Junction over the hub cap")
	_add_legend_row(side_box, Color("D98E4A"), "! Tile near capacity (90%+, last run)")
	_add_legend_row(side_box, Color("C4573A"), "! Tile over capacity (last run)")
	_add_legend_row(side_box, BRIDGE_COLOR, "River / bridge")

	side_box.add_child(HSeparator.new())
	var run_day := Button.new()
	run_day.text = "Run the Day ▸"
	run_day.custom_minimum_size.y = 44
	run_day.pressed.connect(_end_day)
	side_box.add_child(run_day)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_left = 12
	_hint_label.offset_right = -312
	_hint_label.offset_top = -40
	_hint_label.offset_bottom = -12
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.add_theme_stylebox_override("normal", _panel_style(Color("142027"), 0.9))
	root.add_child(_hint_label)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-220, 12)
	_toast.size = Vector2(440, 42)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("normal", _panel_style(Color("19312c"), 0.96))
	_toast.visible = false
	root.add_child(_toast)

	_tip_panel = PanelContainer.new()
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_theme_stylebox_override("panel", _panel_style(Color("2c2418"), 0.95))
	_tip_panel.visible = false
	root.add_child(_tip_panel)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.custom_minimum_size = Vector2(210, 0)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_label)

	_build_map_controls(root)

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
	var continue_button := Button.new()
	continue_button.text = "Continue to next day"
	continue_button.custom_minimum_size.y = 40
	continue_button.pressed.connect(_close_report)
	report_box.add_child(continue_button)

## ---------- map controls (zoom/pan, top-left) ----------

func _build_map_controls(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.9))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_add_section_title(box, "MAP")

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	box.add_child(zoom_row)
	var zoom_label := Label.new()
	zoom_label.text = "Zoom"
	zoom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_row.add_child(zoom_label)
	_add_hold_button(zoom_row, "−", func() -> void: _zoom_dir = 1.0, func() -> void: _zoom_dir = 0.0)
	_add_hold_button(zoom_row, "+", func() -> void: _zoom_dir = -1.0, func() -> void: _zoom_dir = 0.0)

	var pan_grid := GridContainer.new()
	pan_grid.columns = 3
	box.add_child(pan_grid)
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
	bubbles_row.add_child(bubbles_label)
	_bubbles_button = Button.new()
	_bubbles_button.toggle_mode = true
	_bubbles_button.button_pressed = true
	_bubbles_button.text = "On"
	_bubbles_button.custom_minimum_size = Vector2(52, 36)
	_bubbles_button.toggled.connect(_on_bubbles_toggled)
	bubbles_row.add_child(_bubbles_button)

	# Shortcuts for the two most-used build tools, so drawing and erasing
	# routes don't require reaching over to the right-hand sidebar. These
	# register alongside the sidebar's own Draw Route / Bulldoze buttons (see
	# _add_tool_button), and _set_tool keeps every copy of a tool in sync.
	box.add_child(HSeparator.new())
	_add_section_title(box, "BUILD")
	var build_row := HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 4)
	box.add_child(build_row)
	_add_controller_tool_button(build_row, "Route", "route")
	_add_controller_tool_button(build_row, "Erase", "remove")

const CONTROLLER_BUTTON_SIZE := Vector2(52, 52)
const CONTROLLER_FONT_SIZE := 24

func _pan_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = CONTROLLER_BUTTON_SIZE
	return spacer

func _add_pan_button(parent: Container, text: String, dir: Vector2) -> void:
	_add_hold_button(parent, text, func() -> void: _pan_dir += dir, func() -> void: _pan_dir -= dir)

## A compact toggle button on the top-left controller panel that selects a
## build tool, mirroring the right-hand sidebar's tool button for the same
## tool (both register in _tool_buttons, so _set_tool keeps them in sync).
func _add_controller_tool_button(parent: Container, text: String, tool: String) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(52, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_set_tool.bind(tool))
	parent.add_child(button)
	_tool_buttons.get_or_add(tool, []).append(button)

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

func _add_stat_row(parent: VBoxContainer, label_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = "—"
	row.add_child(value)
	return value

func _add_tool_button(parent: VBoxContainer, text: String, tool: String) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size.y = 36
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
