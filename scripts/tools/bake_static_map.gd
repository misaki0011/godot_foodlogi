extends SceneTree

## Bakes the terrain and node markers into a standalone, script-free scene
## (scenes/main/MapPreview.tscn) so the map is visible in the Godot
## editor's 3D viewport just by opening that scene -- no Play needed, and
## no risk to Main.tscn (whose own main.gd script builds a lot of runtime
## UI/game state that has no business being frozen into a saved file).
##
## Mirrors Main.tscn's WorldEnvironment/DirectionalLight3D/Camera3D setup
## so the preview looks like the real game. Re-run any time map data or
## block art changes -- it always regenerates terrain/markers from scratch
## via the same TerrainRenderer/NodeSpawner scripts the real game uses, so
## the preview can't drift from actual gameplay rendering.
##
## Player-built route/storage/hub tiles are intentionally never baked here;
## they live in GameState.grid, not MapData, and only exist once a game
## session actually builds them.
##
## Run via: godot --headless --script res://scripts/tools/bake_static_map.gd

const OUTPUT_SCENE_PATH := "res://scenes/main/MapPreview.tscn"
const REGION_MAP_PATH := "res://data/maps/region_1_map.tres"

func _initialize() -> void:
	var preview := Node3D.new()
	preview.name = "MapPreview"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.85, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1, 1)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	preview.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.position = Vector3(10, 20, 10)
	light.rotation = Vector3(-0.95, 0.6, 0)
	light.shadow_enabled = false
	preview.add_child(light)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(21.833, 36.641, 34.833)
	camera.rotation = Vector3(-1.047198, 0, 0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34.0
	camera.near = 0.1
	camera.far = 200.0
	camera.current = true
	preview.add_child(camera)

	var terrain := GridMap.new()
	terrain.name = "TerrainMap"
	terrain.set_script(load("res://scripts/terrain/terrain_renderer.gd"))
	preview.add_child(terrain)
	var map_data: MapData = load(REGION_MAP_PATH)
	terrain.render(map_data)

	var spawner := Node3D.new()
	spawner.name = "NodeMarkers"
	spawner.set_script(load("res://scripts/markers/node_spawner.gd"))
	preview.add_child(spawner)
	spawner.spawn(map_data, terrain)

	_claim_ownership(preview, preview)

	var packed := PackedScene.new()
	var pack_result := packed.pack(preview)
	if pack_result != OK:
		printerr("bake_static_map: pack() failed with error %d" % pack_result)
		quit(1)
		return

	var save_result := ResourceSaver.save(packed, OUTPUT_SCENE_PATH)
	if save_result != OK:
		printerr("bake_static_map: ResourceSaver.save() failed with error %d" % save_result)
		quit(1)
		return

	print("bake_static_map: baked terrain + markers into %s" % OUTPUT_SCENE_PATH)
	quit()

func _claim_ownership(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_claim_ownership(child, owner)
