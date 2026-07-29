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

## Sources render smaller than settlements. A settlement is where the
## player has to act; a source is reference information, so it gives up
## the visual weight. Scaling pixel_size scales the sprite's authored
## offset with it, keeping the bubble anchored the same way.
const SOURCE_SCALE := 0.85

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
const SOURCE_STACK_SPACING := WORLD_HEIGHT * CAMERA_VERTICAL_COMPENSATION * SOURCE_SCALE + 0.1
const COLUMN_SPACING := WORLD_WIDTH + 0.1

## Which silhouette bubble_canvas.gd draws. SETTLEMENT_OFFER is one of the
## two orders on the table waiting to be picked (DEV-01, see OrderBook).
enum Kind { SOURCE, SETTLEMENT, SETTLEMENT_OFFER }

## DEFAULT is a source's plain food-on-beige look; MUTED grays a source
## out once it has given away its whole daily produce. RED/AMBER/GREEN are
## a settlement's status, used both for the combined amount+freshness
## verdict (main.gd's _render_settlement_bubbles) and, separately, for how
## the delivered freshness rates against that settlement's own thresholds.
enum Status { DEFAULT, MUTED, RED, AMBER, GREEN }

@onready var _canvas: BubbleCanvas = $SubViewport/BubbleCanvas
@onready var _viewport: SubViewport = $SubViewport
@onready var _sprite: Sprite3D = $Sprite3D

func _ready() -> void:
	_sprite.texture = _viewport.get_texture()

func setup_source(food: FoodData, used: float, produced: float, status: Status = Status.DEFAULT) -> void:
	_sprite.pixel_size = BASE_PIXEL_SIZE * SOURCE_SCALE
	_canvas.set_source(food.color, _ratio_text(used, produced), status)
	_bake()

## freshness_pct >= 0 fills the bar and prints the percentage; pass -1
## when nothing has arrived yet and an average freshness would be
## meaningless. bonus_freshness_pct places the tick the bar has to clear
## for this settlement to count as green -- it is per-settlement data, so
## the same 78% is a miss at a fussy city and a pass at a village.
func setup_settlement(food: FoodData, delivered: float, requested: float, status: Status, freshness_pct: int = -1, bonus_freshness_pct: float = 0.0) -> void:
	_sprite.pixel_size = BASE_PIXEL_SIZE
	_canvas.set_settlement(food.color, _ratio_text(delivered, requested), status, freshness_pct, bonus_freshness_pct / 100.0)
	_bake()

## One of the two orders on offer: the food it wants and how much of it per
## day. Full size, unlike the rest of the map's supporting information -- it
## is the one thing waiting on a decision.
func setup_offer(food: FoodData, amount: float) -> void:
	_sprite.pixel_size = BASE_PIXEL_SIZE
	_canvas.set_offer(food.color, food.display_name, "%d/day" % roundi(amount))
	_bake()

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
