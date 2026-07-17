@tool
class_name TerrainRenderer
extends GridMap

## Renders a MapData's terrain grid. Each cell's actual visible geometry is
## a directly-instanced child of the matching block glTF (assets/Blocks/glTF),
## placed at this GridMap's own map_to_local() position with no scale --
## every block glTF is authored at its real, final 2x2 world-space footprint
## (matching cell_size exactly, see tools/asset_gen/generate_blocks.py), so
## no transform beyond position is ever needed.
##
## GridMap itself is used only for its cell bookkeeping and coordinate math
## (map_to_local/local_to_map, get_used_cells/get_cell_item) -- its own
## automatic per-item cell_size scaling is never exercised, since the
## MeshLibrary items here intentionally carry no mesh (see
## _build_mesh_library). That scaling was the original suspected cause of a
## visible seam between tiles; placing real, already-full-size meshes
## directly removes it from the picture entirely rather than relying on the
## scale math cancelling out correctly.
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
var _visuals: Node3D

func render(map_data: MapData) -> void:
	clear()
	if _visuals:
		_visuals.free()
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	mesh_library = _build_mesh_library()
	_cache_item_ids()
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			_place_terrain_cell(x, y, map_data.get_terrain(x, y))

## Named-but-meshless items -- used only for GridMap's own cell bookkeeping
## (get_used_cells/get_cell_item/get_item_name), not for rendering. See the
## class doc comment for why the actual visible block is a separately
## instanced child instead of a MeshLibrary-rendered cell.
func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var id := 0
	for terrain in TERRAIN_MESH_NAMES:
		library.create_item(id)
		library.set_item_name(id, TERRAIN_MESH_NAMES[terrain])
		id += 1
	return library

func _place_terrain_cell(x: int, y: int, terrain: GameEnums.TerrainType) -> void:
	var mesh_name: String = TERRAIN_MESH_NAMES.get(terrain, "Block_Grass")
	var item_id: int = _item_ids_by_name.get(mesh_name, -1)
	if item_id == -1:
		push_warning("TerrainRenderer: no MeshLibrary item named '%s'" % mesh_name)
		return
	var cell := Vector3i(x, 0, y)
	set_cell_item(cell, item_id)
	var scene: PackedScene = TERRAIN_BLOCK_SCENES.get(terrain, TERRAIN_BLOCK_SCENES[GameEnums.TerrainType.PLAINS])
	var block: Node3D = scene.instantiate()
	_visuals.add_child(block)
	block.position = map_to_local(cell)

func _cache_item_ids() -> void:
	_item_ids_by_name.clear()
	if mesh_library == null:
		push_warning("TerrainRenderer: no mesh_library assigned")
		return
	for id in mesh_library.get_item_list():
		_item_ids_by_name[mesh_library.get_item_name(id)] = id
