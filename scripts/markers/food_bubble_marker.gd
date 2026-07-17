class_name FoodBubbleMarker
extends Node3D

## A speech bubble floated above a node showing a food-colored icon and a
## quantity: a source's daily supply (always visible, node_spawner.gd), or
## a settlement's unmet demand for the last simulated day (main.gd's
## _render_food_need_bubbles). The bubble is drawn once into a SubViewport
## and displayed on a billboard Sprite3D -- baking the whole thing (shape,
## icon, number) into one texture avoids Label3D sorting behind the bubble
## mesh, and reads far crisper than stacked 3D primitives at this scale.

@onready var _canvas: BubbleCanvas = $SubViewport/BubbleCanvas
@onready var _viewport: SubViewport = $SubViewport
@onready var _sprite: Sprite3D = $Sprite3D

func _ready() -> void:
	_sprite.texture = _viewport.get_texture()

func setup(food: FoodData, amount: float) -> void:
	_canvas.set_content(food.color, str(roundi(amount)))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
