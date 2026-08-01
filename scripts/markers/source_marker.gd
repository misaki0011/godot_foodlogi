@tool
class_name SourceMarker
extends NodeMarker

## A food source: a 2x1 yard with one PRODUCE MODEL on it per base unit of
## daily output -- one to begin with, and one more for every upgrade bought
## (NodeData.upgrade_level, capped at GameBalance.SOURCE_UPGRADE_MAX).
##
## The pile is the supply figure. GameBalance.SOURCE_UPGRADE_SUPPLY_STEP is one
## base unit per upgrade, so a Garden showing four carrots is producing four
## times what the map authored, and a player can read a source's output off the
## map without opening anything. That only holds while the two stay in step,
## which is what `_test_source_models` guards.
##
## The models are the chip glyphs in three dimensions (FoodGlyphs' rule: the
## same silhouette everywhere a food appears, so the mark on a settlement's
## chip is the mark on the source that fills it). They carry their own
## colours -- hence `self_coloured` on the scene -- because flattening them to
## one tint is exactly what would destroy the identification.

const FOOD_SCENES := {
	"grain": preload("res://assets/Environment/glTF/Food_Grain.glb"),
	"bread": preload("res://assets/Environment/glTF/Food_Bread.glb"),
	"vegetables": preload("res://assets/Environment/glTF/Food_Vegetables.glb"),
	"milk": preload("res://assets/Environment/glTF/Food_Milk.glb"),
	"seafood": preload("res://assets/Environment/glTF/Food_Seafood.glb"),
}

## Where the yard's produce stands, in the order the slots fill.
##
## Front row (+Z, toward the camera) before the back row, so a source with one
## model puts it where nothing can hide it; and centre before the sides within
## each row, so an un-upgraded source is centred on its own yard rather than
## sitting off in a corner. Filling reaches symmetry at 3 and again at 6.
##
## Six slots is SOURCE_UPGRADE_MAX + 1 and must stay that way -- a seventh
## upgrade would have nowhere to stand.
const SLOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.42),
	Vector3(-1.16, 0.0, 0.42),
	Vector3(1.16, 0.0, 0.42),
	Vector3(0.0, 0.0, -0.44),
	Vector3(-1.16, 0.0, -0.44),
	Vector3(1.16, 0.0, -0.44),
]

## Height of the yard's top face, where the produce stands. Mirrors
## PLAZA_TOP_Y in tools/asset_gen/generate_blocks.py.
const YARD_TOP_Y := 0.18

## A little turn per slot so six identical models are not six identical
## silhouettes. Fixed per slot rather than random: the marker is rebuilt on
## every upgrade, and a re-rolled angle would spin the whole yard each time.
const SLOT_YAW := [0.0, 0.5, -0.42, 0.28, -0.66, 0.75]

var _produce: Node3D

func setup(data: NodeData, tint: Color) -> void:
	super.setup(data, tint)
	refresh_produce()

## Rebuilds the yard's produce for `node_data`'s current upgrade level. Called
## at spawn and again by Main after every upgrade -- cheap enough to redo
## wholesale (six instances at most) that tracking which slot is new would be
## more bookkeeping than it saves.
func refresh_produce() -> void:
	if _produce == null:
		_produce = Node3D.new()
		_produce.name = "Produce"
		add_child(_produce)
	for child in _produce.get_children():
		child.free()
	if node_data == null or node_data.produces.is_empty():
		return
	# One food per source in the MVP region; a source producing several fills
	# its slots by cycling through them, so the yard still shows everything it
	# makes rather than only the first thing.
	var foods: Array = node_data.produces.keys()
	var count: int = mini(node_data.upgrade_level + 1, SLOTS.size())
	for i in count:
		var scene: PackedScene = FOOD_SCENES.get(foods[i % foods.size()])
		if scene == null:
			continue
		var model: Node3D = scene.instantiate()
		_produce.add_child(model)
		model.position = SLOTS[i] + Vector3(0, YARD_TOP_Y, 0)
		model.rotation.y = SLOT_YAW[i]

## How many produce models the yard is currently showing, for the dev checks.
func produce_count() -> int:
	return 0 if _produce == null else _produce.get_child_count()
