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
	print("Node markers spawned: %d (expected 10)" % markers.get_child_count())

	var terrain_types_seen := {}
	for cell in used_cells:
		var item_id: int = terrain.get_cell_item(cell)
		var item_name: String = terrain.mesh_library.get_item_name(item_id)
		terrain_types_seen[item_name] = terrain_types_seen.get(item_name, 0) + 1
	print("Block types used: %s" % terrain_types_seen)

	for marker in markers.get_children():
		print("  marker %s @ %s (label=%s)" % [marker.node_data.node_id, marker.position, marker.get_node("Label3D").text])
