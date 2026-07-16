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

const ROUTE_LEVEL_COLORS := {"dirt": Color("B99A6B"), "paved": Color("9C8F7A"), "main": Color("6E6252")}
const BRIDGE_COLOR := Color("8FB9D8")
const GRADE_COLORS := {"S": Color("C9A227"), "A": Color("5C8A5C"), "B": Color("5B8FA8"), "C": Color("D98E4A"), "D": Color("C4573A")}
const STORAGE_TOOLS := {"normal": GameEnums.StorageType.NORMAL, "cool": GameEnums.StorageType.COOL, "freeze": GameEnums.StorageType.FREEZE}
const ZOOM_MIN := 14.0
const ZOOM_MAX := 60.0
const ZOOM_SPEED := 24.0 # camera.size units/sec while a zoom button is held
const PAN_SPEED := 16.0 # world units/sec at the default zoom level, scales with zoom
const PAN_MAP_MARGIN := 10.0 # world units of empty space pannable past the map edge
const TOOL_HINTS := {
	"route": "Click an empty tile adjacent to a node or existing route to extend your network.",
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
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D

var _map_data: MapData
var _state := GameState.new()
var _tool := "route"
var _nodes_by_pos: Dictionary = {}
var _nodes_by_id: Dictionary = {}
var _grid_visuals: Node3D

var _funds_label: Label
var _day_label: Label
var _best_grade_label: Label
var _best_score_label: Label
var _avg_score_label: Label
var _hint_label: Label
var _toast: Label
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

func _ready() -> void:
	_apply_web_mobile_rendering_limits()
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

func _apply_web_mobile_rendering_limits() -> void:
	# Mobile browsers have much smaller WebGL memory budgets than native apps.
	# High-DPI rendering is disabled in project settings, and shadows are the
	# largest remaining off-screen allocation in this scene.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_directional_light.shadow_enabled = false

func _unhandled_input(event: InputEvent) -> void:
	if _report_overlay.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(_screen_to_cell(event.position), event.position)
	elif event is InputEventMouseMotion:
		_update_tip(_screen_to_cell(event.position), event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_click(_screen_to_cell(event.position), event.position)

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

func _do_build_route(cell: Vector2i) -> void:
	if _state.grid.has(cell):
		_show_toast("Already built here.", true)
		return
	if not _adjacent_to_network(cell):
		_show_toast("Route must connect to a node or existing route.", true)
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
			var color: Color = BRIDGE_COLOR if _map_data.is_river(pos.x, pos.y) else ROUTE_LEVEL_COLORS[cell.level]
			_add_tile_box(world_pos, color, 0.16)
			if cell.get("needs_hub", false):
				_add_warning_ring(world_pos, Color("C4573A"))
			elif cell.get("hub_capped", false):
				_add_warning_ring(world_pos, Color("8B6B9C"))
		elif cell.kind == "storage":
			var marker: NodeMarker = STORAGE_SCENE.instantiate()
			_grid_visuals.add_child(marker)
			marker.position = world_pos
			marker.apply_tint(MarkerColors.storage_color(cell.stype), GameBalance.STORAGE_TYPES[cell.stype].name)
		elif cell.kind == "hub":
			var marker: NodeMarker = HUB_SCENE.instantiate()
			_grid_visuals.add_child(marker)
			marker.position = world_pos
			marker.apply_tint(MarkerColors.hub_color(cell.htype), GameBalance.HUB_TYPES[cell.htype].name)
	for c in _state.last_congestion:
		var world_pos: Vector3 = _terrain.map_to_local(Vector3i(c.pos.x, 0, c.pos.y)) + Vector3(0, 1.35, 0)
		_add_congestion_marker(world_pos, c.over)

func _add_tile_box(pos: Vector3, color: Color, height: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.55, height, 1.55)
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
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == tool
	_hint_label.text = TOOL_HINTS.get(tool, "")

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
	_add_pan_button(pan_grid, "▲", Vector2(0, 1))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "◀", Vector2(-1, 0))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "▶", Vector2(1, 0))
	pan_grid.add_child(_pan_spacer())
	_add_pan_button(pan_grid, "▼", Vector2(0, -1))
	pan_grid.add_child(_pan_spacer())

func _pan_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(34, 34)
	return spacer

func _add_pan_button(parent: Container, text: String, dir: Vector2) -> void:
	_add_hold_button(parent, text, func() -> void: _pan_dir += dir, func() -> void: _pan_dir -= dir)

func _add_hold_button(parent: Container, text: String, on_press: Callable, on_release: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 34)
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
	_tool_buttons[tool] = button

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
