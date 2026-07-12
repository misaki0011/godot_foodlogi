extends SceneTree

## One-shot dev tool: bakes resources/terrain/blocks.meshlib from the Block
## glTF set and authors data/maps/region_1_map.tres (the MVP region layout).
## Run via: godot --headless --script res://scripts/tools/build_resources.gd
## Re-run any time the block set or map layout changes.

const BLOCKS_DIR := "res://assets/Blocks/glTF"
const MESHLIB_OUT := "res://resources/terrain/blocks.meshlib"
const REGION_MAP_OUT := "res://data/maps/region_1_map.tres"

func _initialize() -> void:
	_build_mesh_library()
	_build_region_map()
	quit()

func _build_mesh_library() -> void:
	var mesh_library := MeshLibrary.new()
	var dir := DirAccess.open(BLOCKS_DIR)
	var files := dir.get_files()
	files.sort()
	var next_id := 0
	for file_name in files:
		if not file_name.ends_with(".gltf"):
			continue
		var scene: PackedScene = load("%s/%s" % [BLOCKS_DIR, file_name])
		var instance := scene.instantiate()
		var mesh_instance := _find_mesh_instance(instance)
		if mesh_instance == null:
			push_warning("build_resources: no MeshInstance3D found in %s" % file_name)
			instance.free()
			continue
		var item_name := file_name.get_basename()
		mesh_library.create_item(next_id)
		mesh_library.set_item_name(next_id, item_name)
		mesh_library.set_item_mesh(next_id, mesh_instance.mesh)
		next_id += 1
		instance.free()
	var err := ResourceSaver.save(mesh_library, MESHLIB_OUT)
	if err != OK:
		push_error("build_resources: failed to save blocks.meshlib (%s)" % err)
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
	map.grid_size = Vector2i(18, 12)
	map.terrain_rows = PackedStringArray([
		".........R...SSSSS",
		".........R...SSSSS",
		".........R...SSSSS",
		".........R...SSSSS",
		".........R..MMMMMM",
		".........R..MMMMMM",
		".........R..MMMMMM",
		".........R..MMMMMM",
		"FFFFF....R..MMMMMM",
		"FFFFF....R........",
		"FFFFF....R........",
		"FFFFF....R........",
	])

	var hub_small: HubData = load("res://data/nodes/hub_small_1.tres")
	var storage_cool: StorageData = load("res://data/nodes/storage_cool_1.tres")

	var placements: Array[NodeData] = [
		_node("vegetable_farm", GameEnums.NodeType.SOURCE, Vector2i(2, 2), "Vegetable Farm"),
		_node("bakery", GameEnums.NodeType.SOURCE, Vector2i(2, 5), "Bakery"),
		_node("dairy_farm", GameEnums.NodeType.SOURCE, Vector2i(6, 9), "Dairy Farm"),
		_node("small_hub", GameEnums.NodeType.HUB, Vector2i(5, 5), "Small Hub", hub_small),
		_node("village_a", GameEnums.NodeType.SETTLEMENT, Vector2i(7, 3), "Village A"),
		_node("riverside_village", GameEnums.NodeType.SETTLEMENT, Vector2i(7, 8), "Riverside Village"),
		_node("town_b", GameEnums.NodeType.SETTLEMENT, Vector2i(11, 5), "Town B"),
		_node("cool_storage", GameEnums.NodeType.STORAGE, Vector2i(12, 4), "Cool Storage", storage_cool),
		_node("mountain_village", GameEnums.NodeType.SETTLEMENT, Vector2i(14, 6), "Mountain Village"),
		_node("city_c", GameEnums.NodeType.SETTLEMENT, Vector2i(16, 2), "City C"),
	]
	map.node_placements = placements

	var err := ResourceSaver.save(map, REGION_MAP_OUT)
	if err != OK:
		push_error("build_resources: failed to save region_1_map.tres (%s)" % err)
	else:
		print("build_resources: saved region_1_map.tres with %d node placements" % placements.size())

func _node(id: String, type: GameEnums.NodeType, pos: Vector2i, display_name: String, linked: Resource = null) -> NodeData:
	var data := NodeData.new()
	data.node_id = id
	data.node_type = type
	data.grid_position = pos
	data.display_name = display_name
	data.linked_resource = linked
	return data
