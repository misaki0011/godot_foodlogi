class_name BubbleCanvas
extends Control

## Draws the speech-bubble variants FoodBubbleMarker bakes into a
## SubViewport texture. Composing a whole bubble as one flat 2D drawing --
## instead of a separate 3D box + icon mesh + Label3D stacked in front of
## each other -- sidesteps Godot's per-object transparency sort placing
## the number behind the bubble, and reads crisper than the old low-poly
## primitives.
##
## Sources and settlements are told apart by *silhouette*, not colour,
## because colour is already carrying two other meanings on this map (the
## food's identity, and a settlement's delivery status):
##
##   SOURCE            a dark slate sign on a post: white text,
##                     near-square corners, a stem and foot down to the
##                     crate, and an outgoing-supply arrow. No progress
##                     bar -- the bar belongs to settlements alone.
##   SETTLEMENT        a cream speech balloon: dark text, big corner
##                     radius, triangular tail, a status-coloured border,
##                     and a freshness bar along the bottom.
##   SETTLEMENT_CLEAR  the collapsed summary drawn in place of a whole
##                     stack of green settlement bubbles.
##
## A settlement's status is deliberately kept off the bubble *body*: a
## saturated tint behind the text both fights the food-coloured icon dot
## and forces every status to stay pale enough to read dark text on, which
## is what made red and green hard to tell apart at map distance. Status
## instead rides on the border, the tail, the progress bar and a glyph --
## and the glyph makes the three states distinguishable by shape alone,
## for players who cannot separate the red and green hues.

const BUBBLE_COLOR := Color(0.97, 0.94, 0.87, 0.97)
const BORDER_COLOR := Color(0.15, 0.12, 0.08, 0.65)
const TEXT_COLOR := Color(0.14, 0.11, 0.08)
const SUBTEXT_COLOR := Color(0.34, 0.29, 0.24)

## Sources invert the settlement palette outright: a dark slate sign with
## white text against the settlements' cream balloon with dark text. That
## reads as two different things far sooner than the silhouette does, and
## it costs no colour meaning, since grey is the one hue on this map that
## is neither a food nor a status. The food dot ends up the brightest
## thing on the sign, which is what should be identifying the source
## anyway (all source markers share one colour -- see main.gd's
## _source_food_color).
const SOURCE_BUBBLE_COLOR := Color(0.20, 0.22, 0.25, 0.96)
const SOURCE_BORDER_COLOR := Color(0.80, 0.82, 0.85, 0.5)
const SOURCE_TEXT_COLOR := Color(0.97, 0.96, 0.94)
const SOURCE_GLYPH_INK := Color(0.70, 0.74, 0.78)

## Vertical room reserved below the bubble body for a settlement's tail /
## a source's stem. The tail and the post are what read first at map
## distance, so they get a generous strip: a mean little nub under each
## bubble makes the two variants look alike again from any way off.
const TAIL_HEIGHT := 20.0
const TAIL_HALF_WIDTH := 14.0
## How far the tail's base is tucked up inside the body, so the body's
## border closes over it and the tail appears to grow out from under.
const TAIL_OVERLAP := 12.0
const STEM_WIDTH := 8.0
const STEM_FOOT_WIDTH := 22.0
const STEM_FOOT_HEIGHT := 5.0

## Corner radius as a fraction of body height. The gap between the two is
## the primary source/settlement tell, so keep them far apart.
const SOURCE_CORNER_RATIO := 0.07
const SETTLEMENT_CORNER_RATIO := 0.34

## Settlements are where the player has to act, so they carry the heavier
## outline; sources are reference information and stay quiet.
const SOURCE_BORDER_WIDTH := 2
const SETTLEMENT_BORDER_WIDTH := 3
const CLEAR_BORDER_WIDTH := 2

## A source that has given up its whole daily produce fades in place: a
## lighter, flatter slate with dim ink and a grey dot. Dropping contrast
## rather than switching palette keeps it obviously the same kind of
## object -- it must still read as a source, only a spent one.
## Kept clearly darker than the map's grass: a mid-grey at the terrain's
## own luminance loses its edges into the ground and stops reading as a
## sign at all. The fade comes from the ink, not from lightening the body.
const MUTED_BUBBLE_COLOR := Color(0.28, 0.29, 0.31, 0.88)
const MUTED_BORDER_COLOR := Color(0.62, 0.63, 0.65, 0.4)
const MUTED_TEXT_COLOR := Color(0.62, 0.63, 0.64)
const MUTED_ICON_COLOR := Color(0.46, 0.47, 0.49)

## Status accents. These are fully saturated -- they are only ever used
## for borders, tails, bars and glyphs, never as a background under text.
## They also differ in *lightness*, not just hue, so they stay separable
## at map distance and in a screenshot desaturated to grey.
const RED_COLOR := Color("d64545")
const AMBER_COLOR := Color("e8a33d")
const GREEN_COLOR := Color("3fa34d")

## How much of the accent hue washes into the bubble body. Green washes
## less and outlines thinner than the others on purpose: a settlement that
## needs nothing should recede, so problems are what catch the eye.
const STATUS_WASH_ALPHA := 0.12
const GREEN_WASH_ALPHA := 0.05

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
const BAR_TRACK_COLOR := Color(0.15, 0.12, 0.08, 0.16)
const BAR_TICK_COLOR := Color(0.15, 0.12, 0.08, 0.55)
const BAR_TICK_WIDTH := 3.0

## _draw_fitted shrinks the font to fit rather than letting text overflow
## the bubble; this is the floor so it never shrinks past readable.
const MIN_FONT_SIZE := 14

var _kind: FoodBubbleMarker.Kind = FoodBubbleMarker.Kind.SOURCE
var _icon_color: Color = Color.WHITE
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
	return BORDER_COLOR

func set_source(icon_color: Color, amount_text: String, status: FoodBubbleMarker.Status) -> void:
	_kind = FoodBubbleMarker.Kind.SOURCE
	_icon_color = icon_color
	_amount_text = amount_text
	_status = status
	queue_redraw()

func set_settlement(icon_color: Color, amount_text: String, status: FoodBubbleMarker.Status, freshness_pct: int, threshold: float) -> void:
	_kind = FoodBubbleMarker.Kind.SETTLEMENT
	_icon_color = icon_color
	_amount_text = amount_text
	_status = status
	_freshness_pct = freshness_pct
	_threshold = threshold
	queue_redraw()

func set_all_clear(text: String) -> void:
	_kind = FoodBubbleMarker.Kind.SETTLEMENT_CLEAR
	_amount_text = text
	_status = FoodBubbleMarker.Status.GREEN
	queue_redraw()

func _draw() -> void:
	match _kind:
		FoodBubbleMarker.Kind.SETTLEMENT:
			_draw_settlement()
		FoodBubbleMarker.Kind.SETTLEMENT_CLEAR:
			_draw_settlement_clear()
		_:
			_draw_source()

# --- variants ---------------------------------------------------------

func _draw_source() -> void:
	var muted := _status == FoodBubbleMarker.Status.MUTED
	var fill := MUTED_BUBBLE_COLOR if muted else SOURCE_BUBBLE_COLOR
	var ink := MUTED_TEXT_COLOR if muted else SOURCE_TEXT_COLOR
	var icon := MUTED_ICON_COLOR if muted else _icon_color
	var border := MUTED_BORDER_COLOR if muted else SOURCE_BORDER_COLOR

	var rect := _body_rect()
	var radius := int(rect.size.y * SOURCE_CORNER_RATIO)

	# Post first, so the body and its border cover the joint. The foot at
	# the bottom is what sells "sign planted in the ground" rather than
	# "balloon with a skinny tail".
	var cx := rect.position.x + rect.size.x * 0.5
	var stem_top := rect.end.y - 6.0
	var stem_bottom := rect.end.y + TAIL_HEIGHT - STEM_FOOT_HEIGHT - 2.0
	var stem := Rect2(Vector2(cx - STEM_WIDTH * 0.5, stem_top), Vector2(STEM_WIDTH, stem_bottom - stem_top))
	var foot := Rect2(Vector2(cx - STEM_FOOT_WIDTH * 0.5, stem_bottom), Vector2(STEM_FOOT_WIDTH, STEM_FOOT_HEIGHT))
	for r in [stem, foot]:
		draw_rect(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.18))
	for r in [stem, foot]:
		draw_rect(r, fill)
		draw_rect(r, border, false, 2.0)

	_draw_body(rect, radius, fill, border, SOURCE_BORDER_WIDTH)

	var cy := rect.position.y + rect.size.y * 0.5
	var icon_r := rect.size.y * 0.23
	var icon_center := Vector2(rect.position.x + 14.0 + icon_r, cy)
	draw_circle(icon_center, icon_r, icon)
	draw_arc(icon_center, icon_r, 0, TAU, 32, border, 2.0, true)

	var glyph_r := rect.size.y * 0.155
	var glyph_center := Vector2(rect.end.x - 16.0 - glyph_r, cy)
	_draw_out_arrow(glyph_center, glyph_r, MUTED_ICON_COLOR if muted else SOURCE_GLYPH_INK)

	var text_x := icon_center.x + icon_r + 12.0
	var text_w := glyph_center.x - glyph_r - 12.0 - text_x
	_draw_fitted(_amount_text, text_x, text_w, cy, int(rect.size.y * 0.44), ink)

func _draw_settlement() -> void:
	var accent := status_color(_status)
	var green := _status == FoodBubbleMarker.Status.GREEN
	var rect := _body_rect()
	var radius := int(rect.size.y * SETTLEMENT_CORNER_RATIO)

	if _status == FoodBubbleMarker.Status.RED:
		_draw_halo(rect, radius, accent)

	var wash := GREEN_WASH_ALPHA if green else STATUS_WASH_ALPHA
	var fill := BUBBLE_COLOR.lerp(Color(accent.r, accent.g, accent.b, BUBBLE_COLOR.a), wash)
	var border_width := CLEAR_BORDER_WIDTH if green else SETTLEMENT_BORDER_WIDTH

	_draw_tail(rect, accent)
	_draw_body(rect, radius, fill, accent, border_width)

	# The bar sits in the bottom strip, so the icon/text row centres on
	# what is left above it rather than on the whole body.
	var row_cy := rect.position.y + (rect.size.y - BAR_BOTTOM_MARGIN - BAR_HEIGHT) * 0.5

	var icon_r := rect.size.y * 0.26
	var icon_center := Vector2(rect.position.x + 14.0 + icon_r, row_cy)
	draw_circle(icon_center, icon_r, _icon_color)
	draw_arc(icon_center, icon_r, 0, TAU, 32, BORDER_COLOR, 2.0, true)

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

func _draw_settlement_clear() -> void:
	var accent := GREEN_COLOR
	var rect := _body_rect()
	var radius := int(rect.size.y * SETTLEMENT_CORNER_RATIO)
	var fill := BUBBLE_COLOR.lerp(Color(accent.r, accent.g, accent.b, BUBBLE_COLOR.a), GREEN_WASH_ALPHA)

	_draw_tail(rect, accent)
	_draw_body(rect, radius, fill, accent, CLEAR_BORDER_WIDTH)

	var cy := rect.position.y + rect.size.y * 0.5
	var glyph_r := rect.size.y * 0.22
	var glyph_center := Vector2(rect.position.x + 16.0 + glyph_r, cy)
	_draw_check(glyph_center, glyph_r, accent)

	var text_x := glyph_center.x + glyph_r + 12.0
	var text_w := rect.end.x - 16.0 - text_x
	_draw_fitted(_amount_text, text_x, text_w, cy, int(rect.size.y * 0.34), SUBTEXT_COLOR)

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
		fill_box.bg_color = accent
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
	match _status:
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

## Outgoing supply: what this node hands out, as opposed to a
## settlement's incoming demand.
func _draw_out_arrow(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r * 0.78),
		center + Vector2(-r * 0.62, -r * 0.04),
		center + Vector2(r * 0.62, -r * 0.04),
	]), color)
	draw_line(center + Vector2(0, -r * 0.10), center + Vector2(0, r * 0.72), color, r * 0.34, true)
