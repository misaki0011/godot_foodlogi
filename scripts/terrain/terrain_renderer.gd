class_name TerrainRenderer
extends GridMap

## Renders a MapData's terrain grid into GridMap cells. Item ids are
## resolved from mesh_library by name at render time (not hardcoded),
## since MeshLibrary item ids aren't stable across rebakes.
##
## fresh-routes-mvp.html only has two terrain kinds -- open plains and a
## single river column (bridges auto-build when a route crosses it) -- so
## that's all this renders; see SPEC.md v0.3 §12.

const TERRAIN_MESH_NAMES := {
	GameEnums.TerrainType.PLAINS: "Block_Grass",
	GameEnums.TerrainType.RIVER: "Block_Ice",
}

var _item_ids_by_name: Dictionary = {}

func render(map_data: MapData) -> void:
	clear()
	_cache_item_ids()
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			_place_terrain_cell(x, y, map_data.get_terrain(x, y))

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
