@tool
class_name TerrainRenderer
extends GridMap

## Renders a MapData's terrain grid into GridMap cells. The MeshLibrary is
## built at runtime (see _build_mesh_library) straight from the block glTFs
## in assets/Blocks/glTF, so those .glb files are the single source of
## truth for what a terrain tile looks like -- there's no separate baked
## .meshlib to keep in sync by hand whenever a block's art changes.
##
## fresh-routes-mvp.html only has two terrain kinds -- open plains and a
## single river column (bridges auto-build when a route crosses it) -- so
## that's all this renders; see SPEC.md v0.3 §12.

const TERRAIN_BLOCK_SCENES := {
	GameEnums.TerrainType.PLAINS: preload("res://assets/Blocks/glTF/Block_Grass.glb"),
	GameEnums.TerrainType.RIVER: preload("res://assets/Blocks/glTF/Block_Ice.glb"),
}
const TERRAIN_MESH_NAMES := {
	GameEnums.TerrainType.PLAINS: "Block_Grass",
	GameEnums.TerrainType.RIVER: "Block_Ice",
}

var _item_ids_by_name: Dictionary = {}

func render(map_data: MapData) -> void:
	clear()
	mesh_library = _build_mesh_library()
	_cache_item_ids()
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			_place_terrain_cell(x, y, map_data.get_terrain(x, y))

## Builds a MeshLibrary from the block glTFs' baked meshes so GridMap
## placement (cell_size scaling, get_used_cells/get_cell_item, etc.) keeps
## working exactly as it did with a hand-baked .meshlib resource.
func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var id := 0
	for terrain in TERRAIN_BLOCK_SCENES:
		var mesh := _extract_mesh(TERRAIN_BLOCK_SCENES[terrain])
		if mesh == null:
			push_warning("TerrainRenderer: '%s' glTF has no mesh" % TERRAIN_MESH_NAMES[terrain])
			continue
		library.create_item(id)
		library.set_item_name(id, TERRAIN_MESH_NAMES[terrain])
		library.set_item_mesh(id, mesh)
		id += 1
	return library

func _extract_mesh(scene: PackedScene) -> Mesh:
	var instance := scene.instantiate()
	var mesh_instance := _find_mesh_instance(instance)
	var mesh: Mesh = mesh_instance.mesh if mesh_instance else null
	instance.free()
	return mesh

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null

func _place_terrain_cell(x: int, y: int, terrain: GameEnums.TerrainType) -> void:
	var mesh_name: String = TERRAIN_MESH_NAMES.get(terrain, "Block_Grass")
	var item_id: int = _item_ids_by_name.get(mesh_name, -1)
	if item_id == -1:
		push_warning("TerrainRenderer: no MeshLibrary item named '%s'" % mesh_name)
		return
	set_cell_item(Vector3i(x, 0, y), item_id)

func _cache_item_ids() -> void:
	_item_ids_by_name.clear()
	if mesh_library == null:
		push_warning("TerrainRenderer: no mesh_library assigned")
		return
	for id in mesh_library.get_item_list():
		_item_ids_by_name[mesh_library.get_item_name(id)] = id
