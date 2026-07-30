class_name BubbleCanvas
extends Control

## Draws the speech-bubble variants FoodBubbleMarker bakes into a
## SubViewport texture. Composing a whole bubble as one flat 2D drawing --
## instead of a separate 3D box + icon mesh + Label3D stacked in front of
## each other -- sidesteps Godot's per-object transparency sort placing
## the number behind the bubble, and reads crisper than the old low-poly
## primitives.
##
## Two variants remain:
##
##   GLYPH_COLUMN      a vertical stack of chips, one per open order: a food
##                     glyph on a status-coloured background. This is the
##                     map's default layer, and all a SOURCE ever draws.
##   SETTLEMENT        a cream speech balloon: dark text, big corner
##                     radius, triangular tail, a status-coloured border,
##                     and a freshness bar along the bottom. Drawn only for
##                     the settlement the player is inspecting.
##
## The dark slate sign on a post that sources used to draw is gone: a source
## is now always its big food glyph, so the sign had no remaining caller.
## Its used/produced figure moved to the hover tip (main.gd's _update_tip),
## which is the only place that number now lives.
##
## Status rides the body's tint, the border, the tail, the bar and a glyph.
## The glyph is what keeps the three states distinguishable by shape alone,
## for players who cannot separate the red and green hues -- that guarantee
## predates the tint and outlives it.
##
## A map where every node floats a full balloon is unreadable once more than
## a couple of orders are open -- the bubbles crowd each other and bury the
## roads, terrain and route overlay underneath them. The column answers the
## two questions worth asking at a glance (what does this place want, is it
## all right) in a fraction of the space, and the balloon -- numbers,
## freshness bar and all -- comes back the moment the player hovers or taps
## the node. See main.gd's BubblesMode.

## The balloon shares the chip's palette: a dark, status-TINTED ground with
## light text, rather than the cream body it used to have. Collapsed and
## expanded are then obviously the same object at two levels of detail,
## which is the whole point of one expanding into the other.
##
## Going dark is also what lets the status colour be strong here. Item 30
## kept status off the cream body because a saturated ground under DARK text
## forces every status pale enough to read on, which is what made red and
## green converge at map distance. Inverting to light-on-dark removes that
## constraint entirely -- the tint can be as saturated as the chip's.
const TEXT_COLOR := Color(0.96, 0.96, 0.94)
const SUBTEXT_COLOR := Color(0.74, 0.77, 0.78)

## Vertical room reserved below the bubble body for a settlement's tail.
## The tail is what reads first at map distance, so it gets a generous
## strip: a mean little nub under the bubble barely registers from any way
## off.
const TAIL_HEIGHT := 20.0
const TAIL_HALF_WIDTH := 14.0
## How far the tail's base is tucked up inside the body, so the body's
## border closes over it and the tail appears to grow out from under.
const TAIL_OVERLAP := 12.0

## Corner radius as a fraction of body height.
const SETTLEMENT_CORNER_RATIO := 0.34

const SETTLEMENT_BORDER_WIDTH := 3
## A settled (green) settlement outlines thinner than one still asking for
## something, so a map full of solved towns recedes and the problems catch
## the eye. This is the whole of green's de-emphasis now that the collapsed
## "All fresh" summary is gone.
const GREEN_BORDER_WIDTH := 2

## A source that has given up its whole daily produce fades in place: its
## glyph goes grey instead of taking the food's colour. Dropping saturation
## rather than hiding the glyph keeps it obviously the same object -- it must
## still read as that source, only a spent one.
const MUTED_ICON_COLOR := Color(0.46, 0.47, 0.49)

## Status accents. These are fully saturated -- they are only ever used
## for borders, tails, bars and glyphs, never as a background under text.
## They also differ in *lightness*, not just hue, so they stay separable
## at map distance and in a screenshot desaturated to grey.
const RED_COLOR := Color("d64545")
const AMBER_COLOR := Color("e8a33d")
const GREEN_COLOR := Color("3fa34d")

## Red draws an extra translucent halo behind the body. It is static
## rather than animated: on day one every settlement is red, and a screen
## of pulsing bubbles is worse than no emphasis at all.
const HALO_GROW := 6.0
const HALO_ALPHA := 0.22

## Status glyph radius as a fraction of body height. This is the one part
## of a settlement bubble that survives being colourblind, so it is sized
## as a peer of the food dot rather than as a badge tucked in the corner
## -- it has to be legible before the numbers are.
const STATUS_GLYPH_RATIO := 0.19
const STATUS_GLYPH_MARGIN := 13.0

## Freshness bar along the bottom of a settlement bubble, with a tick at
## the settlement's own bonus threshold -- the line the bar has to cross
## to turn the bubble green. Without it "78%" means nothing until you
## remember whether this particular town wanted 80 or 90.
const BAR_INSET := 22.0
const BAR_HEIGHT := 9.0
const BAR_BOTTOM_MARGIN := 18.0
const BAR_TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.17)
const BAR_TICK_COLOR := Color(1.0, 1.0, 1.0, 0.62)
const BAR_TICK_WIDTH := 3.0

## The bar only takes the status colour once the full requested amount has
## arrived. Short of that the delivery earns nothing whatever its
## freshness was, so colouring a long bar red -- or worse, green -- would
## dress up a line that is not paying. Grey says "measured, but it does
## not count yet".
const BAR_INERT_COLOR := Color(1.0, 1.0, 1.0, 0.34)

## _draw_fitted shrinks the font to fit rather than letting text overflow
## the bubble; this is the floor so it never shrinks past readable.
const MIN_FONT_SIZE := 14

## ---------- glyph column (the map's default layer) ----------
##
## One CHIP per open order, stacked VERTICALLY. Horizontal was tried first
## and a five-order City spanned three-plus tiles sideways, straight across
## whichever neighbour happened to sit beside it -- and settlements crowd
## each other horizontally far more than vertically, because the space above
## a node is usually empty map.
##
## A settlement chip and a source chip are deliberately different objects,
## the same way the retired balloon and sign were:
##
##   SETTLEMENT   heavily rounded, with a status-TINTED dark fill and a
##                saturated status border. The coloured background is what
##                carries the verdict at a glance.
##   SOURCE       near-square corners, neutral slate, no status anything --
##                a source has no delivery to be judged on.
##
## Note the tint may be strong here in a way item 30 ruled out for the
## balloon *body*: that rule exists because a saturated ground under DARK
## TEXT forces every status pale enough to read on, which is what made red
## and green converge. A chip carries no text, so the constraint does not
## apply and the status colour can be as saturated as it likes.
const CHIP_SLATE := Color(0.18, 0.20, 0.23, 0.92)
const CHIP_SLATE_BORDER := Color(0.80, 0.82, 0.85, 0.42)
const CHIP_BORDER_WIDTH := 7
## How far the chip's fill is pulled from slate toward its status colour.
## Enough to read as a red/amber/green object at map distance, but still
## dark enough that any food glyph -- including pale milk and green
## vegetables on a green chip -- keeps its contrast against it.
const CHIP_STATUS_TINT := 0.42
const SETTLEMENT_CHIP_CORNER_RATIO := 0.34
const SOURCE_CHIP_CORNER_RATIO := 0.09
## Ink the food glyphs are outlined in on a chip -- light, because a chip is
## always dark. This is the inverse of the balloon, where the ink is dark.
const CHIP_GLYPH_INK := Color(0.93, 0.94, 0.96, 0.94)
## 4x the radius the strip shipped with (19). At the original size a chip
## came to roughly ten screen pixels on a phone-width view of the whole
## region, below the point where any silhouette resolves -- the glyphs were
## unreadable in exactly the situation they exist for.
##
## The size is native rather than a sprite scale: setup_glyph_column sizes
## the SubViewport to fit, so a bigger glyph is drawn at a bigger resolution
## and stays crisp instead of magnifying a small texture.
const CHIP_GLYPH_RADIUS := 76.0
const CHIP_PADDING := 20.0
const CHIP_GAP := 12.0
## Slack around the column so chip borders and drop shadows are not clipped
## by the viewport edge.
const CHIP_MARGIN := 8.0
## The status mark rides the chip's lower-right corner. The tinted background
## already says red/amber/green, but the mark is what keeps the three states
## separable by SHAPE, which is item 30's colourblind guarantee -- so it stays
## even though it is now the second channel rather than the only one.
const CHIP_STATUS_RATIO := 0.40
const CHIP_STATUS_BACKING := Color(0.08, 0.09, 0.11, 0.92)

## Outer size of one chip, including its padding.
static func chip_size() -> float:
	return CHIP_GLYPH_RADIUS * 2.0 + CHIP_PADDING * 2.0

## Viewport size a column of `count` chips needs. Sized to content, so a
## one-chip source does not carry a texture tall enough for five.
static func glyph_column_size(count: int) -> Vector2i:
	var n := maxi(count, 1)
	var chip := chip_size()
	return Vector2i(
		ceili(chip + CHIP_MARGIN * 2.0),
		ceili(n * chip + (n - 1) * CHIP_GAP + CHIP_MARGIN * 2.0),
	)

var _kind: FoodBubbleMarker.Kind = FoodBubbleMarker.Kind.GLYPH_COLUMN
var _icon_color: Color = Color.WHITE
## Which silhouette identifies the food (see FoodGlyphs). Empty falls back to
## the plain disc the bubbles used before glyphs existed.
var _food_id: String = ""
## GLYPH_COLUMN only: one {food_id, color, status} per open order, already
## sorted worst-first by main.gd.
var _glyph_entries: Array = []
var _amount_text: String = "0"
var _status: FoodBubbleMarker.Status = FoodBubbleMarker.Status.DEFAULT
## Settlement only: average freshness, or -1 when nothing has arrived and
## freshness is therefore meaningless. Drives both the bar and the small
## percentage under the amount.
var _freshness_pct: int = -1
## Settlement only: this settlement's bonus_freshness, as the 0..1 point
## on the bar where the tick goes.
var _threshold: float = 0.0

static func status_color(status: FoodBubbleMarker.Status) -> Color:
	match status:
		FoodBubbleMarker.Status.RED:
			return RED_COLOR
		FoodBubbleMarker.Status.AMBER:
			return AMBER_COLOR
		FoodBubbleMarker.Status.GREEN:
			return GREEN_COLOR
	# DEFAULT/MUTED: a source, which has no delivery verdict. Callers use
	# _is_delivery_status to avoid tinting anything with this.
	return CHIP_SLATE_BORDER

func set_settlement(food_id: String, icon_color: Color, amount_text: String, status: FoodBubbleMarker.Status, freshness_pct: int, threshold: float) -> void:
	_kind = FoodBubbleMarker.Kind.SETTLEMENT
	_food_id = food_id
	_icon_color = icon_color
	_amount_text = amount_text
	_status = status
	_freshness_pct = freshness_pct
	_threshold = threshold
	queue_redraw()

## `entries` is one {food_id, color, status} per open order, worst-first.
func set_glyph_column(entries: Array) -> void:
	_kind = FoodBubbleMarker.Kind.GLYPH_COLUMN
	_glyph_entries = entries
	queue_redraw()

func _draw() -> void:
	match _kind:
		FoodBubbleMarker.Kind.SETTLEMENT:
			_draw_settlement()
		_:
			_draw_glyph_column()

# --- variants ---------------------------------------------------------

func _draw_settlement() -> void:
	var accent := status_color(_status)
	var green := _status == FoodBubbleMarker.Status.GREEN
	var rect := _body_rect()
	var radius := int(rect.size.y * SETTLEMENT_CORNER_RATIO)

	if _status == FoodBubbleMarker.Status.RED:
		_draw_halo(rect, radius, accent)

	# Same fill formula as a chip (see CHIP_STATUS_TINT), so the balloon a
	# hover expands into is visibly the chip it grew from.
	var fill := CHIP_SLATE.lerp(Color(accent.r, accent.g, accent.b, CHIP_SLATE.a), CHIP_STATUS_TINT)
	var border_width := GREEN_BORDER_WIDTH if green else SETTLEMENT_BORDER_WIDTH

	_draw_tail(rect, accent)
	_draw_body(rect, radius, fill, accent, border_width)

	# The bar sits in the bottom strip, so the icon/text row centres on
	# what is left above it rather than on the whole body.
	var row_cy := rect.position.y + (rect.size.y - BAR_BOTTOM_MARGIN - BAR_HEIGHT) * 0.5

	var icon_r := rect.size.y * 0.26
	var icon_center := Vector2(rect.position.x + 14.0 + icon_r, row_cy)
	# Stroked in the chip's light ink: this outline is the only thing
	# separating a pale milk bottle -- or a green carrot on a green-tinted
	# body -- from the ground behind it (FoodGlyphs), so it cannot be a hint.
	FoodGlyphs.draw_glyph(self, _food_id, icon_center, icon_r, _icon_color, CHIP_GLYPH_INK)

	var glyph_r := rect.size.y * STATUS_GLYPH_RATIO
	var glyph_center := Vector2(rect.end.x - STATUS_GLYPH_MARGIN - glyph_r, row_cy)
	_draw_status_glyph(glyph_center, glyph_r, accent)

	var text_x := icon_center.x + icon_r + 12.0
	var text_w := glyph_center.x - glyph_r - 10.0 - text_x
	if _freshness_pct >= 0:
		_draw_fitted(_amount_text, text_x, text_w, row_cy - 14.0, int(rect.size.y * 0.40), TEXT_COLOR)
		_draw_fitted("%d%%" % _freshness_pct, text_x, text_w, row_cy + 24.0, int(rect.size.y * 0.20), SUBTEXT_COLOR)
	else:
		_draw_fitted(_amount_text, text_x, text_w, row_cy, int(rect.size.y * 0.42), TEXT_COLOR)

	_draw_freshness_bar(rect, accent)

## The default map layer: one food glyph per open order on a small dark
## plate, sized to its contents and centred in the canvas so the surrounding
## transparent margin costs nothing on screen. No numbers and no freshness
## bar -- those are what the hover/tap balloon is for.
func _draw_glyph_column() -> void:
	if _glyph_entries.is_empty():
		return

	var r := CHIP_GLYPH_RADIUS
	var chip := chip_size()
	var x := (size.x - chip) * 0.5
	var y := CHIP_MARGIN
	for entry in _glyph_entries:
		var rect := Rect2(Vector2(x, y), Vector2(chip, chip))
		var status: FoodBubbleMarker.Status = entry.status
		var judged := _is_delivery_status(status)

		# A settlement chip takes its status colour as a background; a source
		# chip stays neutral slate with near-square corners, because a source
		# has no delivery to be judged on and must not look like it does.
		var accent := status_color(status)
		var fill := CHIP_SLATE.lerp(Color(accent.r, accent.g, accent.b, CHIP_SLATE.a), CHIP_STATUS_TINT) if judged else CHIP_SLATE
		var border := accent if judged else CHIP_SLATE_BORDER
		var ratio := SETTLEMENT_CHIP_CORNER_RATIO if judged else SOURCE_CHIP_CORNER_RATIO
		_draw_body(rect, int(chip * ratio), fill, border, CHIP_BORDER_WIDTH)

		var center := rect.position + rect.size * 0.5
		FoodGlyphs.draw_glyph(self, entry.food_id, center, r, entry.color, CHIP_GLYPH_INK)

		# The tinted background already says red/amber/green; this keeps the
		# three separable by SHAPE too, which is item 30's colourblind
		# guarantee. Its own backing disc holds it legible where it overlaps
		# the glyph.
		if judged:
			var sr := chip * CHIP_STATUS_RATIO * 0.5
			var sc := rect.end - Vector2(sr, sr) - Vector2(CHIP_BORDER_WIDTH, CHIP_BORDER_WIDTH)
			draw_circle(sc, sr * 1.06, CHIP_STATUS_BACKING)
			_draw_status_mark(status, sc, sr, accent)
		y += chip + CHIP_GAP

## Whether a status is a settlement's delivery verdict rather than a source's
## stock level. DEFAULT/MUTED belong to sources, which are never judged.
static func _is_delivery_status(status: FoodBubbleMarker.Status) -> bool:
	return status == FoodBubbleMarker.Status.RED \
		or status == FoodBubbleMarker.Status.AMBER \
		or status == FoodBubbleMarker.Status.GREEN

# --- shared pieces ----------------------------------------------------

## The bubble body, excluding the tail/stem strip along the bottom.
func _body_rect() -> Rect2:
	return Rect2(Vector2(3, 3), Vector2(size.x - 6, size.y - TAIL_HEIGHT - 6))

func _draw_body(rect: Rect2, radius: int, fill: Color, border: Color, border_width: int) -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.18)
	shadow.set_corner_radius_all(radius)
	draw_style_box(shadow, Rect2(rect.position + Vector2(0, 2), rect.size))

	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(border_width)
	draw_style_box(box, rect)

func _draw_halo(rect: Rect2, radius: int, accent: Color) -> void:
	var halo := StyleBoxFlat.new()
	halo.bg_color = Color(accent.r, accent.g, accent.b, HALO_ALPHA)
	halo.set_corner_radius_all(radius + int(HALO_GROW))
	draw_style_box(halo, rect.grow(HALO_GROW))

## Drawn before the body so the body's border closes off the joint; the
## triangle's base therefore starts well inside the body outline.
func _draw_tail(rect: Rect2, accent: Color) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - TAIL_HALF_WIDTH, rect.end.y - TAIL_OVERLAP),
		Vector2(cx + TAIL_HALF_WIDTH, rect.end.y - TAIL_OVERLAP),
		Vector2(cx, rect.end.y + TAIL_HEIGHT - 2.0),
	]), accent)

func _draw_freshness_bar(rect: Rect2, accent: Color) -> void:
	var y := rect.end.y - BAR_BOTTOM_MARGIN
	var track := Rect2(
		Vector2(rect.position.x + BAR_INSET, y),
		Vector2(rect.size.x - BAR_INSET * 2.0, BAR_HEIGHT),
	)
	var radius := int(BAR_HEIGHT * 0.5)

	var track_box := StyleBoxFlat.new()
	track_box.bg_color = BAR_TRACK_COLOR
	track_box.set_corner_radius_all(radius)
	draw_style_box(track_box, track)

	var filled := 0.0 if _freshness_pct < 0 else clampf(_freshness_pct / 100.0, 0.0, 1.0)
	if filled > 0.0:
		# Never draw a fill narrower than it is tall -- a rounded box
		# thinner than its own corner radius renders as a smear.
		var fill_box := StyleBoxFlat.new()
		fill_box.bg_color = BAR_INERT_COLOR if _status == FoodBubbleMarker.Status.RED else accent
		fill_box.set_corner_radius_all(radius)
		draw_style_box(fill_box, Rect2(track.position, Vector2(maxf(track.size.x * filled, BAR_HEIGHT), BAR_HEIGHT)))

	# Drawn over the fill so it stays readable whichever side of the
	# threshold the bar has reached.
	var mark := clampf(_threshold, 0.0, 1.0)
	if mark > 0.0 and mark < 1.0:
		var x := track.position.x + track.size.x * mark
		draw_line(Vector2(x, track.position.y - 1.0), Vector2(x, track.end.y + 1.0), BAR_TICK_COLOR, BAR_TICK_WIDTH)

## Returns the font size actually used, after shrink-to-fit.
func _draw_fitted(text: String, x: float, max_width: float, center_y: float, start_size: int, color: Color) -> int:
	var font := ThemeDB.fallback_font
	var font_size := start_size
	while font_size > MIN_FONT_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		font_size -= 1
	draw_string(font, Vector2(x, center_y + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, max_width, font_size, color)
	return font_size

# --- glyphs -----------------------------------------------------------
#
# Drawn from primitives rather than typeset from the fallback font: the
# font is not guaranteed to carry check/cross glyphs, and a tofu box in
# the corner of every bubble would be worse than no glyph at all.

func _draw_status_glyph(center: Vector2, r: float, color: Color) -> void:
	_draw_status_mark(_status, center, r, color)

## Takes the status explicitly, because the glyph strip draws one mark per
## entry rather than one for the whole canvas.
func _draw_status_mark(status: FoodBubbleMarker.Status, center: Vector2, r: float, color: Color) -> void:
	match status:
		FoodBubbleMarker.Status.GREEN:
			_draw_check(center, r, color)
		FoodBubbleMarker.Status.AMBER:
			_draw_bang(center, r, color)
		_:
			_draw_cross(center, r, color)

func _draw_check(center: Vector2, r: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([
		center + Vector2(-r * 0.65, r * 0.02),
		center + Vector2(-r * 0.18, r * 0.50),
		center + Vector2(r * 0.68, -r * 0.55),
	]), color, r * 0.28, true)

func _draw_cross(center: Vector2, r: float, color: Color) -> void:
	var a := r * 0.55
	draw_line(center + Vector2(-a, -a), center + Vector2(a, a), color, r * 0.28, true)
	draw_line(center + Vector2(-a, a), center + Vector2(a, -a), color, r * 0.28, true)

## Stroked heavier than the cross and check: a bare vertical bar covers
## far less area than they do at the same weight, and read as the faint
## one of the three sitting side by side on the map.
func _draw_bang(center: Vector2, r: float, color: Color) -> void:
	draw_line(center + Vector2(0, -r * 0.72), center + Vector2(0, r * 0.16), color, r * 0.34, true)
	draw_circle(center + Vector2(0, r * 0.66), r * 0.19, color)
