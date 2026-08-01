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

## ---------- vegetation scatter ----------
##
## The terrain blocks are deliberately featureless flat plates (see
## generate_blocks.py's build_grass_block), so open ground gets its character
## from props standing ON it rather than from anything modelled into the tile:
## a tree or a bush on roughly a third of the free plains cells, exactly the
## way the reference art dresses an otherwise-plain board.
##
## The scatter is a pure function of the cell coordinates (_cell_random), not
## of RandomNumberGenerator, and that matters for more than reproducibility:
## render() is the only thing that ever builds these, but Main re-renders the
## grid on every hover, day and build, so anything that re-rolled per frame
## would make the forest crawl. Deriving it from the cell means the same map
## always grows the same trees in the same places.
const DECOR_SCENES := [
	preload("res://assets/Environment/glTF/Tree_Round.glb"),
	preload("res://assets/Environment/glTF/Tree_Tall.glb"),
	preload("res://assets/Environment/glTF/Bush_Square.glb"),
	preload("res://assets/Environment/glTF/Bush_Rect.glb"),
]

## Share of eligible cells that grow something. High enough to read as
## countryside, low enough that the grid the player is drawing routes on is
## still legible through it.
const DECOR_DENSITY := 0.34

## How far a prop may wander from its cell's centre, and how much its size may
## vary. Both are small on purpose: a prop must stay clearly on ITS OWN cell,
## because the cell is what the player is about to build on.
const DECOR_JITTER := 0.34
const DECOR_SCALE_MIN := 0.78
const DECOR_SCALE_MAX := 1.04

## Height of a terrain block's top face in block-local space -- the surface
## everything on a tile stands on. Mirrors TILE_TOP_Y in generate_blocks.py
## and the +1.0 offset Main and NodeSpawner already apply.
const TERRAIN_SURFACE_Y := 1.0

var _item_ids_by_name: Dictionary = {}
var _visuals: Node3D
var _decor: Node3D
## cell (Vector2i) -> the prop standing on it, for hide_decor_on().
var _decor_by_cell: Dictionary = {}

func render(map_data: MapData) -> void:
	clear()
	if _visuals:
		_visuals.free()
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	_decor = Node3D.new()
	_decor.name = "Vegetation"
	add_child(_decor)
	_decor_by_cell.clear()
	mesh_library = _build_mesh_library()
	_cache_item_ids()
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			_place_terrain_cell(x, y, map_data.get_terrain(x, y))
	_scatter_vegetation(map_data)

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

## Grows a tree or a bush on a deterministic subset of the free plains cells.
##
## River cells are skipped (nothing grows in the water), and so is every cell a
## node stands on OR touches. A node marker and its floating order bubbles are
## the most important thing on the board, and a 1.7-unit tree in the next cell
## is exactly tall enough to cut across one from this camera's fixed angle --
## so the scatter keeps a one-cell clearing around every node rather than
## trusting the odds.
func _scatter_vegetation(map_data: MapData) -> void:
	var blocked := _cells_near_nodes(map_data)
	for y in range(map_data.grid_size.y):
		for x in range(map_data.grid_size.x):
			var cell := Vector2i(x, y)
			if map_data.get_terrain(x, y) != GameEnums.TerrainType.PLAINS or blocked.has(cell):
				continue
			if _cell_random(x, y, 1) >= DECOR_DENSITY:
				continue
			_place_decor(cell)

## Every cell occupied by a node, plus its eight neighbours.
func _cells_near_nodes(map_data: MapData) -> Dictionary:
	var blocked := {}
	for node in map_data.node_placements:
		for cell in node.cells():
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					blocked[cell + Vector2i(dx, dy)] = true
	return blocked

func _place_decor(cell: Vector2i) -> void:
	var scene: PackedScene = DECOR_SCENES[_cell_index(cell.x, cell.y, 2, DECOR_SCENES.size())]
	var prop: Node3D = scene.instantiate()
	_decor.add_child(prop)
	var offset := Vector3(
		(_cell_random(cell.x, cell.y, 3) - 0.5) * 2.0 * DECOR_JITTER,
		TERRAIN_SURFACE_Y,
		(_cell_random(cell.x, cell.y, 4) - 0.5) * 2.0 * DECOR_JITTER,
	)
	prop.position = map_to_local(Vector3i(cell.x, 0, cell.y)) + offset
	# Props are authored origin-at-base, so scaling them never lifts them off
	# the ground or sinks them into it (see generate_blocks.py).
	var scale_factor: float = lerpf(DECOR_SCALE_MIN, DECOR_SCALE_MAX, _cell_random(cell.x, cell.y, 5))
	prop.scale = Vector3.ONE * scale_factor
	prop.rotation.y = _cell_random(cell.x, cell.y, 6) * TAU
	_decor_by_cell[cell] = prop

## Hides the vegetation on every cell in `built` and shows it everywhere else.
##
## A prop stands on ground the player is free to build on, so it has to get out
## of the way of a road, and come back when that road is bulldozed. Doing it as
## one show/hide sweep rather than at the build/clear sites keeps this correct
## for free through every path that edits the grid -- a drag, a sweep, an
## upgrade -- and toggling `visible` on a few dozen nodes is cheap enough to run
## from Main's per-hover re-render.
func hide_decor_on(built: Dictionary) -> void:
	for cell in _decor_by_cell:
		var prop: Node3D = _decor_by_cell[cell]
		prop.visible = not built.has(cell)

## A stable pseudo-random float in [0, 1) for a cell, per `salt`. Integer hash
## rather than a seeded RNG so it can be asked for one cell out of order,
## without a generator to keep in step (see the DECOR_SCENES comment).
static func _cell_random(x: int, y: int, salt: int) -> float:
	return float(_cell_index(x, y, salt, 65536)) / 65536.0

static func _cell_index(x: int, y: int, salt: int, modulo: int) -> int:
	var h: int = x * 73856093 ^ y * 19349663 ^ salt * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h) % modulo

func _cache_item_ids() -> void:
	_item_ids_by_name.clear()
	if mesh_library == null:
		push_warning("TerrainRenderer: no mesh_library assigned")
		return
	for id in mesh_library.get_item_list():
		_item_ids_by_name[mesh_library.get_item_name(id)] = id
