extends SceneTree

## One-shot dev check (not part of the game): loads Main.tscn, lets it run
## _ready() for one frame, and asserts terrain + markers were populated.
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

	var used_cells := terrain.get_used_cells()
	print("Terrain cells populated: %d (expected 216 for 18x12)" % used_cells.size())
	print("Node markers spawned: %d (expected 9)" % markers.get_child_count())
	assert(used_cells.size() == 216)
	assert(markers.get_child_count() == 9)
	assert(_main.get_node_or_null("RouteVisuals") != null)
	assert(_main.get_node_or_null("RoutePreview") != null)
	var starting_funds: float = _main.get("_state").funds
	_main.call("_place_building", Vector2i(4, 4), "normal")
	assert(_main.get("_state").placed_nodes.size() == 1)
	assert(_main.get("_state").funds == starting_funds - 80.0)
	var path: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(7, 3)]
	_main.set("_route_path", path)
	_main.call("_finish_route")
	assert(_main.get("_state").routes.size() == 1)
	_main.call("_new_game")
	assert(_main.get("_state").routes.is_empty())
	assert(_main.get("_state").placed_nodes.is_empty())

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)

	for marker in markers.get_children():
		print("  marker %s @ %s (label=%s)" % [marker.node_data.node_id, marker.position, marker.get_node("Label3D").text])
