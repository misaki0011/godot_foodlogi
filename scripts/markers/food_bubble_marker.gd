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

## World-space size of the baked sprite (SubViewport size * Sprite3D
## pixel_size in food_bubble_marker.tscn).
const WORLD_WIDTH := 1.178
const WORLD_HEIGHT := 0.57

## Main.tscn's Camera3D is pitched -60 deg (rotation.x = -1.047198) and
## looks straight down that axis with no yaw/roll, so its "right" vector
## is exactly world +X (unrotated) but its "up" vector is
## (0, cos60, -sin60) = (0, 0.5, -0.866). A billboard sprite always
## renders at its full configured size on screen regardless of view
## angle (that's the point of billboarding) -- but stacking bubbles
## apart along world Y only buys 0.5x that distance in actual screen
## separation, since the other 0.866x of a Y-axis camera-up step lands
## in world Z instead. Spacing rows by only WORLD_HEIGHT (as if the
## camera were level) therefore left rows visually overlapping on
## screen even though they were correctly separated in world space;
## rows need double the gap to end up with WORLD_HEIGHT of *screen*
## separation. Columns don't have this problem: the camera has no yaw,
## so world-X offsets map 1:1 onto screen-X with no compression.
const CAMERA_VERTICAL_COMPENSATION := 2.0
const STACK_SPACING := WORLD_HEIGHT * CAMERA_VERTICAL_COMPENSATION + 0.1
const COLUMN_SPACING := WORLD_WIDTH + 0.1

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
