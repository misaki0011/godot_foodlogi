extends Node3D

const REGION_MAP_PATH := "res://data/maps/region_1_map.tres"
const ROUTE_COLOR := [Color("b88a55"), Color("c4c9cf"), Color("d8b44a")]
const PREVIEW_VALID := Color(0.2, 0.9, 0.65, 0.65)
const PREVIEW_INVALID := Color(0.95, 0.25, 0.25, 0.65)

@onready var _terrain: TerrainRenderer = $TerrainMap
@onready var _node_spawner: NodeSpawner = $NodeMarkers
@onready var _camera: Camera3D = $Camera3D
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D

var _map_data: MapData
var _base_nodes: Array[NodeData] = []
var _state := GameState.new()
var _tool := "inspect"
var _route_drawing := false
var _route_path: Array[Vector2i] = []
var _route_counter := 0
var _building_counter := 0
var _route_visuals: Node3D
var _preview_visuals: Node3D
var _selected_route: RouteSegmentData
var _selected_node: NodeData

var _funds_label: Label
var _day_label: Label
var _tool_label: Label
var _planning_text: RichTextLabel
var _inspect_text: RichTextLabel
var _preview_text: Label
var _toast: Label
var _action_box: HBoxContainer
var _report_overlay: Control
var _report_text: RichTextLabel
var _report_title: Label
var _tool_buttons: Dictionary = {}

func _ready() -> void:
	_apply_web_mobile_rendering_limits()
	_map_data = load(REGION_MAP_PATH)
	_configure_static_nodes()
	_base_nodes.assign(_map_data.node_placements)
	_state.funds = GameBalance.STARTING_FUNDS
	_terrain.render(_map_data)
	_node_spawner.spawn(_map_data, _terrain)
	_route_visuals = Node3D.new()
	_route_visuals.name = "RouteVisuals"
	add_child(_route_visuals)
	_preview_visuals = Node3D.new()
	_preview_visuals.name = "RoutePreview"
	add_child(_preview_visuals)
	_build_ui()
	_update_ui()

func _apply_web_mobile_rendering_limits() -> void:
	# Mobile browsers have much smaller WebGL memory budgets than native apps.
	# High-DPI rendering is disabled in project settings, and shadows are the
	# largest remaining off-screen allocation in this scene.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_directional_light.shadow_enabled = false

func _configure_static_nodes() -> void:
	var supplies := GameBalance.source_supplies()
	var demands := GameBalance.settlement_demands()
	for node in _map_data.node_placements:
		if node.node_type == GameEnums.NodeType.SOURCE:
			var source := SourceData.new()
			source.source_id = node.node_id
			source.daily_supply = supplies.get(node.node_id, {}).duplicate(true)
			node.linked_resource = source
		elif node.node_type == GameEnums.NodeType.SETTLEMENT:
			var settlement := SettlementData.new()
			settlement.settlement_id = node.node_id
			settlement.settlement_type = GameBalance.settlement_type(node.node_id)
			settlement.price_modifier = GameBalance.settlement_price(node.node_id)
			settlement.demands.assign(demands.get(node.node_id, []))
			node.linked_resource = settlement

func _unhandled_input(event: InputEvent) -> void:
	if _report_overlay.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_pressed(event.position)
		else:
			_pointer_released(event.position)
	elif event is InputEventMouseMotion and _route_drawing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pointer_dragged(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pointer_pressed(event.position)
		else:
			_pointer_released(event.position)
	elif event is InputEventScreenDrag and _route_drawing:
		_pointer_dragged(event.position)

func _pointer_pressed(screen_position: Vector2) -> void:
	var cell := _screen_to_cell(screen_position)
	if not _cell_in_bounds(cell):
		return
	match _tool:
		"route":
			if _route_drawing:
				_append_path_to(cell)
				_update_route_preview()
				return
			if _node_at(cell) == null:
				_show_toast("Start a route on a source, settlement, storage, or hub.", true)
				return
			_route_drawing = true
			_route_path = [cell]
			_update_route_preview()
		"normal", "cool", "freeze", "hub":
			_place_building(cell, _tool)
		"bulldoze":
			_bulldoze_at(cell)
		_:
			_inspect_at(cell)

func _pointer_dragged(screen_position: Vector2) -> void:
	var cell := _screen_to_cell(screen_position)
	if not _cell_in_bounds(cell) or _route_path.is_empty() or cell == _route_path.back():
		return
	_append_path_to(cell)
	_update_route_preview()

func _pointer_released(screen_position: Vector2) -> void:
	if not _route_drawing:
		return
	var cell := _screen_to_cell(screen_position)
	if _cell_in_bounds(cell):
		_append_path_to(cell)
	if _route_path.size() <= 1 or _node_at(_route_path.back()) == null:
		_route_drawing = true
		_update_route_preview()
		return
	_finish_route()

func _append_path_to(target: Vector2i) -> void:
	var current: Vector2i = _route_path.back()
	while current != target:
		var next: Vector2i = current
		if current.x != target.x:
			next.x += signi(target.x - current.x)
		else:
			next.y += signi(target.y - current.y)
		if _route_path.size() > 1 and next == _route_path[-2]:
			_route_path.pop_back()
		elif next in _route_path:
			break
		else:
			_route_path.append(next)
		current = next

func _finish_route() -> void:
	_route_drawing = false
	var validation := _validate_route(_route_path)
	if not validation.valid:
		_show_toast(validation.message, true)
		_route_path.clear()
		_clear_children(_preview_visuals)
		_preview_text.text = ""
		_preview_text.visible = false
		return
	var cost := SimulationEngine.route_build_cost(_map_data, _route_path)
	if cost > _state.funds:
		_show_toast("Not enough funds. Route costs %d." % roundi(cost), true)
	else:
		var route := RouteSegmentData.new()
		route.route_id = "route_%d" % _route_counter
		_route_counter += 1
		route.from_node = _node_at(_route_path.front()).node_id
		route.to_node = _node_at(_route_path.back()).node_id
		route.length = _route_path.size() - 1
		route.tile_path.assign(_route_path)
		route.capacity = GameBalance.ROUTE_LEVELS[0].capacity
		route.base_upkeep = GameBalance.ROUTE_BASE_UPKEEP
		route.build_cost = cost
		for i in range(1, _route_path.size()):
			route.terrain_profile.append(_map_data.get_terrain(_route_path[i].x, _route_path[i].y))
		_state.routes.append(route)
		_state.funds -= cost
		_show_toast("Route built for %d." % roundi(cost))
	_route_path.clear()
	_clear_children(_preview_visuals)
	_preview_text.text = ""
	_preview_text.visible = false
	_render_routes()
	_update_ui()

func _validate_route(path: Array[Vector2i]) -> Dictionary:
	if path.size() < 2:
		return {"valid": false, "message": "Drag to a different destination node."}
	var from := _node_at(path.front())
	var to := _node_at(path.back())
	if from == null or to == null or from == to:
		return {"valid": false, "message": "A route must end on a different node."}
	for i in range(1, path.size() - 1):
		if _node_at(path[i]) != null:
			return {"valid": false, "message": "A route stops at the first node it reaches."}
		if _route_at(path[i]) != null:
			return {"valid": false, "message": "Routes may meet only at node endpoints."}
	for route in _state.routes:
		if (route.from_node == from.node_id and route.to_node == to.node_id) or (route.from_node == to.node_id and route.to_node == from.node_id):
			return {"valid": false, "message": "Those nodes are already connected."}
	for node in [from, to]:
		if node.linked_resource is HubData and _connected_routes(node.node_id) >= node.linked_resource.link_capacity:
			return {"valid": false, "message": "%s has no free links." % node.display_name}
	return {"valid": true, "message": ""}

func _place_building(cell: Vector2i, kind: String) -> void:
	if _node_at(cell) != null or _route_at(cell) != null:
		_show_toast("That tile is occupied.", true)
		return
	if _map_data.get_terrain(cell.x, cell.y) == GameEnums.TerrainType.RIVER:
		_show_toast("Buildings cannot be placed in the river.", true)
		return
	var node := NodeData.new()
	node.grid_position = cell
	var cost := 0.0
	if kind == "hub":
		node.node_type = GameEnums.NodeType.HUB
		node.node_id = "small_hub_%d" % _building_counter
		node.display_name = "Small Hub"
		node.linked_resource = GameBalance.hub_data(GameEnums.HubType.SMALL, node.node_id)
		cost = GameBalance.hub_cost(GameEnums.HubType.SMALL)
	else:
		node.node_type = GameEnums.NodeType.STORAGE
		var type: GameEnums.StorageType = {"normal": GameEnums.StorageType.NORMAL, "cool": GameEnums.StorageType.COOL, "freeze": GameEnums.StorageType.FREEZE}[kind]
		node.node_id = "%s_storage_%d" % [kind, _building_counter]
		node.display_name = "%s Storage" % kind.capitalize()
		node.linked_resource = GameBalance.storage_data(type, node.node_id)
		cost = GameBalance.storage_cost(type)
	if cost > _state.funds:
		_show_toast("Not enough funds. %s costs %d." % [node.display_name, roundi(cost)], true)
		return
	_building_counter += 1
	_state.funds -= cost
	_state.placed_nodes.append(node)
	_map_data.node_placements.append(node)
	_node_spawner.spawn(_map_data, _terrain)
	_show_toast("%s built for %d." % [node.display_name, roundi(cost)])
	_update_ui()

func _bulldoze_at(cell: Vector2i) -> void:
	var route := _route_at(cell)
	if route:
		_remove_route(route)
		return
	var node := _node_at(cell)
	if node == null or node not in _state.placed_nodes:
		_show_toast("Only player-built infrastructure can be removed.", true)
		return
	var connected := _state.routes.filter(func(r: RouteSegmentData) -> bool: return r.from_node == node.node_id or r.to_node == node.node_id)
	for connected_route in connected:
		_state.routes.erase(connected_route)
	var refund := _building_value(node) * 0.5
	_state.funds += refund
	_state.placed_nodes.erase(node)
	_map_data.node_placements.erase(node)
	_node_spawner.spawn(_map_data, _terrain)
	_render_routes()
	_update_ui()
	_show_toast("Removed %s. Refund: %d." % [node.display_name, roundi(refund)])

func _inspect_at(cell: Vector2i) -> void:
	_selected_node = _node_at(cell)
	_selected_route = _route_at(cell)
	_clear_children(_action_box)
	if _selected_node:
		_inspect_text.text = _node_details(_selected_node)
		if _selected_node.linked_resource is HubData and _selected_node in _state.placed_nodes and _selected_node.linked_resource.hub_type == GameEnums.HubType.SMALL:
			_add_action_button("Upgrade Hub (200)", _upgrade_hub)
	elif _selected_route:
		_inspect_text.text = _route_details(_selected_route)
		if _selected_route.route_level < 2:
			var cost: float = GameBalance.ROUTE_LEVELS[_selected_route.route_level + 1].upgrade_cost
			_add_action_button("Upgrade (%d)" % roundi(cost), _upgrade_route)
		_add_action_button("Remove", _remove_selected_route)
	else:
		_inspect_text.text = "[b]Inspector[/b]\nTap a node or route to view details."

func _upgrade_route() -> void:
	if _selected_route == null or _selected_route.route_level >= 2:
		return
	var next_level := _selected_route.route_level + 1
	var cost: float = GameBalance.ROUTE_LEVELS[next_level].upgrade_cost
	if cost > _state.funds:
		_show_toast("Not enough funds for this upgrade.", true)
		return
	_state.funds -= cost
	_selected_route.route_level = next_level
	_selected_route.capacity = GameBalance.ROUTE_LEVELS[next_level].capacity
	_render_routes()
	_update_ui()
	_inspect_at(_selected_route.tile_path[_selected_route.tile_path.size() / 2])

func _upgrade_hub() -> void:
	if _selected_node == null or not (_selected_node.linked_resource is HubData):
		return
	var cost := 200.0
	if cost > _state.funds:
		_show_toast("Not enough funds for Regional Hub.", true)
		return
	_state.funds -= cost
	_selected_node.linked_resource = GameBalance.hub_data(GameEnums.HubType.REGIONAL, _selected_node.node_id)
	_selected_node.display_name = "Regional Hub"
	_node_spawner.spawn(_map_data, _terrain)
	_update_ui()
	_inspect_at(_selected_node.grid_position)

func _remove_selected_route() -> void:
	if _selected_route:
		_remove_route(_selected_route)

func _remove_route(route: RouteSegmentData) -> void:
	_state.funds += route.build_cost * 0.5
	_state.routes.erase(route)
	_selected_route = null
	_render_routes()
	_update_ui()
	_inspect_text.text = "[b]Inspector[/b]\nRoute removed."
	_clear_children(_action_box)

func _end_day() -> void:
	if _state.routes.is_empty():
		_show_toast("Build at least one route before ending the day.", true)
		return
	var report := SimulationEngine.simulate_day(_state, _map_data)
	_show_report(report)
	_update_ui()

func _show_report(report: DayReportData) -> void:
	_report_title.text = "Region Complete" if report.won else "Day %d Report" % report.day
	var delivery_lines := ""
	for key in report.delivered:
		var item: Dictionary = report.delivered[key]
		if item.amount > 0:
			delivery_lines += "%s: %.0f / %.0f at %.0f%%\n" % [key.replace(":", " - ").capitalize(), item.amount, item.required, item.freshness]
	if delivery_lines.is_empty():
		delivery_lines = "No accepted deliveries.\n"
	_report_text.text = "[b]Deliveries[/b]\n%s\n[b]Network results[/b]\nAverage freshness: %.1f%%\nWaste: %.1f%%\nSettlement happiness: %.1f%%\n\n[b]Economy[/b]\nFood income: %d\nRoute upkeep: -%d\nStorage upkeep: -%d\nHub upkeep: -%d\nHub savings: +%d\nSpoilage: -%d\n[b]Profit: %s%d[/b]\n\nEfficiency grade: [b]%s[/b]\nPositive-profit streak: %d / 3%s" % [delivery_lines, report.average_freshness, report.waste_percent, report.average_happiness, roundi(report.food_income), roundi(report.route_upkeep), roundi(report.storage_upkeep), roundi(report.hub_upkeep), roundi(report.hub_savings), roundi(report.spoilage_cost), "+" if report.profit >= 0 else "", roundi(report.profit), report.grade, _state.positive_profit_streak, "\n\n[b]You built a fresh, profitable region.[/b]" if report.won else ""]
	_report_overlay.visible = true

func _close_report() -> void:
	_report_overlay.visible = false

func _new_game() -> void:
	_state = GameState.new()
	_state.funds = GameBalance.STARTING_FUNDS
	_map_data.node_placements.assign(_base_nodes)
	_node_spawner.spawn(_map_data, _terrain)
	_route_counter = 0
	_building_counter = 0
	_selected_node = null
	_selected_route = null
	_report_overlay.visible = false
	_render_routes()
	_update_ui()

func _set_tool(tool: String) -> void:
	_tool = tool
	_route_drawing = false
	_route_path.clear()
	_clear_children(_preview_visuals)
	_preview_text.text = ""
	_preview_text.visible = false
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == tool
	_tool_label.text = "Tool: %s" % tool.capitalize()

func _render_routes() -> void:
	_clear_children(_route_visuals)
	for route in _state.routes:
		for i in range(1, route.tile_path.size() - 1):
			var cell := route.tile_path[i]
			var terrain := _map_data.get_terrain(cell.x, cell.y)
			var color: Color = Color("5c8fa3") if terrain == GameEnums.TerrainType.RIVER else ROUTE_COLOR[route.route_level]
			_add_tile_visual(_route_visuals, cell, color, 0.16)

func _update_route_preview() -> void:
	_clear_children(_preview_visuals)
	_preview_text.visible = true
	var validation := _validate_route(_route_path)
	var color := PREVIEW_VALID if validation.valid or _route_path.size() == 1 else PREVIEW_INVALID
	for i in range(_route_path.size()):
		_add_tile_visual(_preview_visuals, _route_path[i], color, 0.20)
	var cost := SimulationEngine.route_build_cost(_map_data, _route_path)
	var terrain_profile: Array[GameEnums.TerrainType] = []
	for i in range(1, _route_path.size()):
		terrain_profile.append(_map_data.get_terrain(_route_path[i].x, _route_path[i].y))
	var temp := RouteSegmentData.new()
	temp.terrain_profile = terrain_profile
	var freshness := []
	for food in GameBalance.food_types().values():
		freshness.append("%s %.0f%%" % [food.display_name, SimulationEngine.route_freshness(temp, food).freshness])
	_preview_text.text = "Tiles %d  |  Build %d  |  Upkeep %.1f/day\n%s" % [maxi(_route_path.size() - 1, 0), roundi(cost), SimulationEngine.route_upkeep(temp), "  ".join(freshness)]

func _add_tile_visual(parent: Node3D, cell: Vector2i, color: Color, height: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.55, height, 1.55)
	mesh_instance.mesh = mesh
	mesh_instance.position = _terrain.map_to_local(Vector3i(cell.x, 0, cell.y)) + Vector3(0, 1.08, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)

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
	for node in _map_data.node_placements:
		if node.grid_position == cell:
			return node
	return null

func _route_at(cell: Vector2i) -> RouteSegmentData:
	for route in _state.routes:
		if cell in route.tile_path:
			return route
	return null

func _connected_routes(node_id: String) -> int:
	var count := 0
	for route in _state.routes:
		if route.from_node == node_id or route.to_node == node_id:
			count += 1
	return count

func _building_value(node: NodeData) -> float:
	if node.linked_resource is StorageData:
		return GameBalance.storage_cost(node.linked_resource.storage_type)
	if node.linked_resource is HubData:
		return GameBalance.hub_cost(node.linked_resource.hub_type)
	return 0.0

func _node_details(node: NodeData) -> String:
	var text := "[b]%s[/b]\n" % node.display_name
	if node.node_type == GameEnums.NodeType.SOURCE:
		text += "Daily supply:\n"
		for food_id in GameBalance.source_supplies().get(node.node_id, {}):
			text += "  %s: %.0f\n" % [food_id.capitalize(), GameBalance.source_supplies()[node.node_id][food_id]]
	elif node.node_type == GameEnums.NodeType.SETTLEMENT:
		text += "Daily demand:\n"
		for demand in GameBalance.settlement_demands().get(node.node_id, []):
			text += "  %s: %.0f (min %.0f%%)\n" % [demand.food_id.capitalize(), demand.amount_required, demand.minimum_freshness]
	elif node.linked_resource is StorageData:
		var storage: StorageData = node.linked_resource
		text += "Capacity: %.0f/day\nProtection: %d tiles at %.0f%% decay\nUpkeep: %.0f/day" % [storage.capacity, storage.protection_distance, storage.freshness_loss_multiplier * 100, storage.daily_upkeep]
	elif node.linked_resource is HubData:
		var hub: HubData = node.linked_resource
		text += "Links: %d / %d\nFlow: %.0f/day\nRoute discount: %.0f%%\nUpkeep: %.0f/day" % [_connected_routes(node.node_id), hub.link_capacity, hub.flow_capacity, hub.route_discount * 100, hub.daily_upkeep]
	return text

func _route_details(route: RouteSegmentData) -> String:
	return "[b]%s Route[/b]\n%s to %s\nLength: %d tiles\nCapacity: %.0f/day\nUpkeep: %.1f/day\nBuild value: %.0f" % [GameBalance.ROUTE_LEVELS[route.route_level].name, route.from_node.capitalize(), route.to_node.capitalize(), route.length, GameBalance.ROUTE_LEVELS[route.route_level].capacity, SimulationEngine.route_upkeep(route), route.build_cost]

func _update_ui() -> void:
	if _funds_label == null:
		return
	_funds_label.text = "Funds  %d" % roundi(_state.funds)
	_day_label.text = "Day  %d" % _state.day
	var route_upkeep := 0.0
	var storage_upkeep := 0.0
	var hub_upkeep := 0.0
	var hub_savings := 0.0
	var nodes := {}
	for node in _map_data.node_placements:
		nodes[node.node_id] = node
		if node.linked_resource is StorageData:
			storage_upkeep += node.linked_resource.daily_upkeep
		elif node.linked_resource is HubData:
			hub_upkeep += node.linked_resource.daily_upkeep
	for route in _state.routes:
		var base := SimulationEngine.route_upkeep(route)
		var discount := 0.0
		for id in [route.from_node, route.to_node]:
			var node: NodeData = nodes.get(id)
			if node and node.linked_resource is HubData:
				discount = maxf(discount, node.linked_resource.route_discount)
		hub_savings += base * discount
		route_upkeep += base * (1.0 - discount)
	var supplies := ""
	for source_id in GameBalance.source_supplies():
		var items := []
		for food_id in GameBalance.source_supplies()[source_id]:
			items.append("%s %.0f" % [food_id.capitalize(), GameBalance.source_supplies()[source_id][food_id]])
		supplies += "%s: %s\n" % [source_id.replace("_", " ").capitalize(), ", ".join(items)]
	var demands := ""
	for settlement_id in GameBalance.settlement_demands():
		var items := []
		for demand in GameBalance.settlement_demands()[settlement_id]:
			items.append("%s %.0f" % [demand.food_id.capitalize(), demand.amount_required])
		demands += "%s: %s\n" % [settlement_id.replace("_", " ").capitalize(), ", ".join(items)]
	_planning_text.text = "[b]SUPPLY[/b]\n%s\n[b]DEMAND[/b]\n%s\n[b]PROJECTED DAILY COST[/b]\nRoutes %.0f  Storage %.0f  Hubs %.0f\nHub savings %.0f" % [supplies, demands, route_upkeep, storage_upkeep, hub_upkeep, hub_savings]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	var root := Control.new()
	root.name = "GameUI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58
	top.add_theme_stylebox_override("panel", _panel_style(Color("18242b"), 0.96))
	root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 24)
	top.add_child(top_row)
	var title := Label.new()
	title.text = "FRESH ROUTES"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)
	_day_label = Label.new()
	top_row.add_child(_day_label)
	_funds_label = Label.new()
	top_row.add_child(_funds_label)
	_tool_label = Label.new()
	top_row.add_child(_tool_label)
	var end_day := Button.new()
	end_day.text = "End Day"
	end_day.pressed.connect(_end_day)
	top_row.add_child(end_day)

	var tools := PanelContainer.new()
	tools.position = Vector2(12, 72)
	tools.size = Vector2(190, 500)
	tools.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.94))
	root.add_child(tools)
	var tool_box := VBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 6)
	tools.add_child(tool_box)
	var tools_title := Label.new()
	tools_title.text = "BUILD TOOLS"
	tools_title.add_theme_font_size_override("font_size", 16)
	tool_box.add_child(tools_title)
	_add_tool_button(tool_box, "Inspect", "inspect")
	_add_tool_button(tool_box, "Route", "route")
	_add_tool_button(tool_box, "Normal Storage  80", "normal")
	_add_tool_button(tool_box, "Cool Storage  180", "cool")
	_add_tool_button(tool_box, "Freeze Storage  400", "freeze")
	_add_tool_button(tool_box, "Small Hub  150", "hub")
	_add_tool_button(tool_box, "Bulldoze / Refund", "bulldoze")

	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -330
	side.offset_top = 72
	side.offset_right = -12
	side.offset_bottom = -12
	side.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 0.94))
	root.add_child(side)
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 10)
	side.add_child(side_box)
	_planning_text = RichTextLabel.new()
	_planning_text.bbcode_enabled = true
	_planning_text.custom_minimum_size = Vector2(290, 360)
	_planning_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_planning_text.add_theme_font_size_override("normal_font_size", 14)
	side_box.add_child(_planning_text)
	var separator := HSeparator.new()
	side_box.add_child(separator)
	_inspect_text = RichTextLabel.new()
	_inspect_text.bbcode_enabled = true
	_inspect_text.custom_minimum_size = Vector2(290, 145)
	_inspect_text.text = "[b]Inspector[/b]\nTap a node or route to view details."
	side_box.add_child(_inspect_text)
	_action_box = HBoxContainer.new()
	side_box.add_child(_action_box)

	_preview_text = Label.new()
	_preview_text.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_preview_text.offset_left = 220
	_preview_text.offset_right = -350
	_preview_text.offset_top = -78
	_preview_text.offset_bottom = -14
	_preview_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_text.add_theme_stylebox_override("normal", _panel_style(Color("142027"), 0.9))
	_preview_text.visible = false
	root.add_child(_preview_text)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-220, 68)
	_toast.size = Vector2(440, 42)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("normal", _panel_style(Color("19312c"), 0.96))
	_toast.visible = false
	root.add_child(_toast)

	_report_overlay = ColorRect.new()
	_report_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_overlay.color = Color(0.02, 0.04, 0.05, 0.78)
	_report_overlay.visible = false
	root.add_child(_report_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_overlay.add_child(center)
	var report_panel := PanelContainer.new()
	report_panel.custom_minimum_size = Vector2(620, 590)
	report_panel.add_theme_stylebox_override("panel", _panel_style(Color("203039"), 1.0))
	center.add_child(report_panel)
	var report_box := VBoxContainer.new()
	report_box.add_theme_constant_override("separation", 12)
	report_panel.add_child(report_box)
	_report_title = Label.new()
	_report_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_title.add_theme_font_size_override("font_size", 26)
	report_box.add_child(_report_title)
	_report_text = RichTextLabel.new()
	_report_text.bbcode_enabled = true
	_report_text.custom_minimum_size = Vector2(570, 460)
	_report_text.add_theme_font_size_override("normal_font_size", 16)
	report_box.add_child(_report_text)
	var report_actions := HBoxContainer.new()
	report_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	report_box.add_child(report_actions)
	var continue_button := Button.new()
	continue_button.text = "Continue Planning"
	continue_button.pressed.connect(_close_report)
	report_actions.add_child(continue_button)
	var restart_button := Button.new()
	restart_button.text = "New Game"
	restart_button.pressed.connect(_new_game)
	report_actions.add_child(restart_button)
	_set_tool("inspect")

func _add_tool_button(parent: VBoxContainer, text: String, tool: String) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size.y = 42
	button.tooltip_text = "Press a node, drag across tiles, and release on another node." if tool == "route" else text
	button.pressed.connect(_set_tool.bind(tool))
	parent.add_child(button)
	_tool_buttons[tool] = button

func _add_action_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	_action_box.add_child(button)

func _panel_style(color: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	color.a = alpha
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
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
