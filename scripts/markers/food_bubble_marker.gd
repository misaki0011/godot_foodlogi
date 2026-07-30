class_name FoodBubbleMarker
extends Node3D

## A speech bubble floated above a node showing a food-colored icon and a
## "current/max" quantity: a source's amount drawn today vs. its daily
## produce, or a settlement's delivered amount vs. its daily demand plus
## average freshness (both from main.gd, refreshed each time the grid
## re-renders). The bubble is drawn once into a SubViewport and displayed
## on a billboard Sprite3D -- baking the whole thing (shape, icon,
## numbers) into one texture avoids Label3D sorting behind the bubble
## mesh, and reads far crisper than stacked 3D primitives at this scale.
##
## Sources and settlements share this scene but not their look: see
## bubble_canvas.gd for the two silhouettes and why status colour rides on
## a settlement's border/tail/bar rather than its body.

## World-space size of the baked sprite (SubViewport size * Sprite3D
## pixel_size in food_bubble_marker.tscn).
const WORLD_WIDTH := 3.1
const WORLD_HEIGHT := 1.5

## Sprite3D.pixel_size as authored in food_bubble_marker.tscn. Set
## explicitly on every setup rather than scaled in place, so re-running
## setup on a marker can't compound the source shrink.
const BASE_PIXEL_SIZE := 0.01

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

## The balloon's authored SubViewport size (food_bubble_marker.tscn). Set
## explicitly on every balloon setup, because setup_glyph_column resizes the
## viewport to its own contents and a marker must never inherit that.
const BALLOON_VIEWPORT := Vector2i(310, 150)

## How much smaller a glyph column renders than a settlement balloon. The
## column is the always-on layer over the whole map, so it has to sit well
## below a balloon's visual weight or it is just a differently-shaped
## version of the clutter it replaces.
const GLYPH_COLUMN_SCALE := 0.72

## Which variant bubble_canvas.gd draws. GLYPH_COLUMN is the map's default
## layer -- food glyphs plus status marks, no numbers -- and is all a SOURCE
## ever draws now that the sign is retired. SETTLEMENT is the full balloon,
## reserved for the settlement the player is inspecting (or the "All" bubbles
## mode). See main.gd's BubblesMode.
enum Kind { SETTLEMENT, GLYPH_COLUMN }

## DEFAULT is a source glyph in its food's own colour; MUTED greys it out
## once that source has given away its whole daily produce. RED/AMBER/GREEN are
## a settlement's status, used both for the combined amount+freshness
## verdict (main.gd's _render_settlement_bubbles) and, separately, for how
## the delivered freshness rates against that settlement's own thresholds.
enum Status { DEFAULT, MUTED, RED, AMBER, GREEN }

@onready var _canvas: BubbleCanvas = $SubViewport/BubbleCanvas
@onready var _viewport: SubViewport = $SubViewport
@onready var _sprite: Sprite3D = $Sprite3D

func _ready() -> void:
	_sprite.texture = _viewport.get_texture()

## The compact default layer: one chip per open order (or, for a source, its
## single produced food), stacked vertically. `entries` is one
## {food_id, color, status} per chip, already sorted worst-first -- the
## column's TOP chip is the thing most worth doing something about.
func setup_glyph_column(entries: Array) -> void:
	# Sized to its contents rather than reusing the balloon's 310x150 canvas:
	# the glyphs are drawn 4x bigger natively (BubbleCanvas.CHIP_GLYPH_RADIUS)
	# so they stay sharp instead of being a magnified small texture, and a
	# one-chip source does not carry a texture tall enough for five.
	_resize(BubbleCanvas.glyph_column_size(entries.size()))
	_sprite.pixel_size = BASE_PIXEL_SIZE * GLYPH_COLUMN_SCALE
	_canvas.set_glyph_column(entries)
	_bake()

## Points the sprite at a viewport of `px` pixels, keeping the marker anchored
## by its bottom edge the way food_bubble_marker.tscn authors it (offset =
## half the height). The canvas is resized alongside the viewport rather than
## left to the next layout pass, because the bake happens immediately.
func _resize(px: Vector2i) -> void:
	_viewport.size = px
	_canvas.size = Vector2(px)
	_sprite.offset = Vector2(0, px.y * 0.5)

## freshness_pct >= 0 fills the bar and prints the percentage; pass -1
## when nothing has arrived yet and an average freshness would be
## meaningless. bonus_freshness_pct places the tick the bar has to clear
## for this settlement to count as green -- it is per-settlement data, so
## the same 78% is a miss at a fussy city and a pass at a village.
func setup_settlement(food: FoodData, delivered: float, requested: float, status: Status, freshness_pct: int = -1, bonus_freshness_pct: float = 0.0) -> void:
	_resize(BALLOON_VIEWPORT)
	_sprite.pixel_size = BASE_PIXEL_SIZE
	_canvas.set_settlement(food.food_id, food.color, _ratio_text(delivered, requested), status, freshness_pct, bonus_freshness_pct / 100.0)
	_bake()

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
