extends SceneTree

## One-shot dev tool: bakes resources/terrain/blocks.meshlib from the (Python-
## generated, vertex-colored, self-contained) terrain block glTFs and
## authors data/maps/region_1_map.tres, matching fresh-routes-mvp.html's
## NODES/grid exactly (21x14, river at column 10, 5 food sources, 5
## settlements, nothing pre-built).
## Run via: godot --headless --script res://scripts/tools/build_resources.gd
## Re-run any time tools/asset_gen/generate_blocks.py or the map layout changes.

const BLOCKS_DIR := "res://assets/Blocks/glTF"
const TERRAIN_BLOCK_NAMES := ["Block_Grass", "Block_Ice"]
const MESHLIB_OUT := "res://resources/terrain/blocks.meshlib"
const REGION_MAP_OUT := "res://data/maps/region_1_map.tres"

func _initialize() -> void:
	_build_mesh_library()
	_build_region_map()
	quit()

func _build_mesh_library() -> void:
	var mesh_library := MeshLibrary.new()
	var next_id := 0
	for item_name in TERRAIN_BLOCK_NAMES:
		var scene: PackedScene = load("%s/%s.glb" % [BLOCKS_DIR, item_name])
		var instance := scene.instantiate()
		var mesh_instance := _find_mesh_instance(instance)
		if mesh_instance == null:
			push_warning("build_resources: no MeshInstance3D found in %s.glb" % item_name)
			instance.free()
			continue
		mesh_library.create_item(next_id)
		mesh_library.set_item_name(next_id, item_name)
		mesh_library.set_item_mesh(next_id, mesh_instance.mesh)
		next_id += 1
		instance.free()
	var mesh_err := ResourceSaver.save(mesh_library, MESHLIB_OUT)
	if mesh_err != OK:
		push_error("build_resources: failed to save blocks.meshlib (%s)" % mesh_err)
	else:
		print("build_resources: saved blocks.meshlib with %d items" % next_id)

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null

func _build_region_map() -> void:
	var map := MapData.new()
	map.grid_size = GameBalance.GRID_SIZE
	map.river_col = GameBalance.RIVER_COL
	map.node_placements = [
		_source("farm", Vector2i(3, 4), "Farm", {"grain": 80.0}),
		_source("garden", Vector2i(2, 6), "Garden", {"vegetables": 90.0}),
		_source("bakery", Vector2i(3, 9), "Bakery", {"bread": 80.0}),
		_source("dairy", Vector2i(17, 4), "Dairy", {"milk": 75.0}),
		_source("harbor", Vector2i(17, 9), "Harbor", {"seafood": 55.0}),

		_settlement("villageA", Vector2i(6, 3), "Village A", "Village", {"bread": 20.0, "grain": 20.0}, 35.0, 80.0),
		_settlement("villageB", Vector2i(6, 10), "Village B", "Village", {"vegetables": 25.0, "grain": 15.0}, 35.0, 80.0),
		_settlement("villageC", Vector2i(13, 3), "Village C", "Village", {"bread": 20.0, "vegetables": 20.0}, 35.0, 80.0),
		_settlement("townD", Vector2i(13, 6), "Town D", "Town", {"bread": 25.0, "vegetables": 30.0, "milk": 25.0}, 45.0, 85.0),
		_settlement("cityE", Vector2i(15, 9), "City E", "City (late objective)", {"milk": 30.0, "seafood": 25.0, "vegetables": 35.0}, 55.0, 90.0),
	]

	var err := ResourceSaver.save(map, REGION_MAP_OUT)
	if err != OK:
		push_error("build_resources: failed to save region_1_map.tres (%s)" % err)
	else:
		print("build_resources: saved region_1_map.tres with %d node placements" % map.node_placements.size())

func _source(id: String, pos: Vector2i, display_name: String, produces: Dictionary) -> NodeData:
	var data := NodeData.new()
	data.node_id = id
	data.node_type = GameEnums.NodeType.SOURCE
	data.grid_position = pos
	data.display_name = display_name
	data.produces = produces
	return data

func _settlement(id: String, pos: Vector2i, display_name: String, kind: String, demand: Dictionary, min_freshness: float, bonus_freshness: float) -> NodeData:
	var data := NodeData.new()
	data.node_id = id
	data.node_type = GameEnums.NodeType.SETTLEMENT
	data.grid_position = pos
	data.display_name = display_name
	data.kind = kind
	data.demand = demand
	data.min_freshness = min_freshness
	data.bonus_freshness = bonus_freshness
	return data
