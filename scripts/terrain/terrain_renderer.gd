class_name TerrainRenderer
extends GridMap

## Renders a MapData's terrain grid into GridMap cells. Item ids are
## resolved from mesh_library by name at render time (not hardcoded),
## since MeshLibrary item ids aren't stable across rebakes.

const TERRAIN_MESH_NAMES := {
	GameEnums.TerrainType.PLAINS: "Block_Grass",
	GameEnums.TerrainType.FOREST: "Block_Grass",
	GameEnums.TerrainType.MOUNTAIN: "Block_Stone",
	GameEnums.TerrainType.RIVER: "Block_Ice",
	GameEnums.TerrainType.SNOW: "Block_Snow",
}

const FOREST_PROP_PATHS := [
	"res://assets/Environment/glTF/Tree_1.gltf",
	"res://assets/Environment/glTF/Tree_2.gltf",
	"res://assets/Environment/glTF/Tree_3.gltf",
	"res://assets/Environment/glTF/Bush.gltf",
]
const FOREST_PROP_CHANCE := 0.35
const FOREST_PROP_SEED := 1

var _item_ids_by_name: Dictionary = {}

func render(map_data: MapData) -> void:
	clear()
	for prop in get_children():
		prop.queue_free()
	_cache_item_ids()

	var render_forest_props := not OS.has_feature("web_android") and not OS.has_feature("web_ios")
	var rng := RandomNumberGenerator.new()
	rng.seed = FOREST_PROP_SEED
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			var terrain: GameEnums.TerrainType = map_data.get_terrain(x, y)
			_place_terrain_cell(x, y, terrain)
			if render_forest_props and terrain == GameEnums.TerrainType.FOREST and rng.randf() < FOREST_PROP_CHANCE:
				_scatter_forest_prop(x, y, rng)

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

func _scatter_forest_prop(x: int, y: int, rng: RandomNumberGenerator) -> void:
	var scene_path: String = FOREST_PROP_PATHS[rng.randi_range(0, FOREST_PROP_PATHS.size() - 1)]
	var prop_scene: PackedScene = load(scene_path)
	var prop := prop_scene.instantiate()
	add_child(prop)
	var jitter := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
	prop.position = map_to_local(Vector3i(x, 0, y)) + Vector3(0, 1.0, 0) + jitter
