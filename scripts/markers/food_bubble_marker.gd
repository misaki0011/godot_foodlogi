class_name FoodBubbleMarker
extends Node3D

## A speech bubble floated above a node showing a food-colored icon and a
## "current/max" quantity: a source's amount drawn today vs. its daily
## produce, or a settlement's delivered amount vs. its daily demand (both
## from main.gd, refreshed each time the grid re-renders). The bubble is
## drawn once into a SubViewport and displayed on a billboard Sprite3D --
## baking the whole thing (shape, icon, numbers) into one texture avoids
## Label3D sorting behind the bubble mesh, and reads far crisper than
## stacked 3D primitives at this scale.

## World-space height of the baked sprite (SubViewport size.y * Sprite3D
## pixel_size in food_bubble_marker.tscn). Callers stacking multiple
## bubbles above one node (main.gd) must space them at least this far
## apart vertically, or consecutive bubbles overlap.
const WORLD_HEIGHT := 0.75
const STACK_SPACING := WORLD_HEIGHT + 0.15

@onready var _canvas: BubbleCanvas = $SubViewport/BubbleCanvas
@onready var _viewport: SubViewport = $SubViewport
@onready var _sprite: Sprite3D = $Sprite3D

func _ready() -> void:
	_sprite.texture = _viewport.get_texture()

## grayed_out mutes the bubble's color -- used by a source once it has
## given away its entire daily produce, so a glance shows it's tapped out.
## show_checkbox/checked draw a checkbox before the food icon (settlements
## only) marking whether that food's demand is currently fully met.
func setup(food: FoodData, current: float, max_amount: float, grayed_out: bool = false, show_checkbox: bool = false, checked: bool = false) -> void:
	var text := "%d/%d" % [roundi(current), roundi(max_amount)]
	_canvas.set_content(food.color, text, grayed_out, show_checkbox, checked)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
