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

## Freshness bar along the bottom of a settlement row, marked at BOTH of
## that settlement's own thresholds -- the floor cargo must clear to be
## accepted at all, and the line it has to cross to turn the row green.
## Without them "78%" means nothing until you remember whether this
## particular town refuses under 35 and pays a bonus over 80, or refuses
## under 55 and pays over 90.
## Sized for a 192px row. These were 9px tall in the old 310x150 balloon and
## were never rescaled when rows went 4x and pixel_size dropped 0.01 -> 0.0072
## -- which left the bar physically SMALLER on screen than before the
## redesign, inside a row four times the size.
const BAR_HEIGHT := 24.0
const BAR_BOTTOM_MARGIN := 22.0
## The track is a dark recess, not a pale wash. Both track and fill were
## translucent white after the light-on-dark inversion (item 49), 0.17 against
## 0.34, which is far too small a step to read as "filled" -- a 90% bar looked
## like an empty one. Cutting the track darker than the body and lifting the
## fill well clear of it puts real contrast between them.
const BAR_TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.30)
const BAR_TICK_COLOR := Color(1.0, 1.0, 1.0, 0.70)
const BAR_TICK_WIDTH := 5.0

## The settlement's min_freshness -- the floor cargo must clear to be accepted
## at all (SimulationEngine turns away anything under it, and the day's demand
## is spent either way). The bar used to mark only bonus_freshness, so it
## showed where the BONUS starts while saying nothing about where REFUSAL
## starts, which is the line spoiled cargo actually failed.
##
## Two marks of the same kind would be ambiguous, so the floor is drawn as a
## zone rather than only a line: a translucent red band over everything from
## the bar's left edge up to the threshold, closed by a crisp red edge. The
## band is what tells the two apart at a glance -- the mark with shading to
## its left is the floor, the bare pale tick is the bonus target. It is
## painted over the fill rather than under it, so it stays visible however
## full the bar is.
const BAR_MIN_ZONE_COLOR := Color(0.84, 0.27, 0.27, 0.30)
const BAR_MIN_TICK_COLOR := Color(1.0, 0.44, 0.44, 0.95)

## The bar only takes the status colour once the full requested amount has
## arrived. Short of that the delivery earns nothing whatever its
## freshness was, so colouring a long bar red -- or worse, green -- would
## dress up a line that is not paying. Grey says "measured, but it does
## not count yet".
const BAR_INERT_COLOR := Color(1.0, 1.0, 1.0, 0.58)

## Cargo turned away for arriving under min_freshness reads in the red accent
## whatever the row's own status is: it is the one number on the row that is
## unambiguously bad news, and on a row that IS red it is usually the whole
## explanation for why.
const REJECTED_TEXT_COLOR := Color("f08a8a")

## What the line paid. The row's colour has always BEEN the payment tier
## (§9: short pays nothing, full pays the line, full-and-fresh pays 25% more)
## and the row never said so -- which is why a red row next to "90% fresh"
## read as a verdict on freshness rather than on earnings. Printing the money
## answers "why this colour?" at the moment the question is asked.
const EARNED_TEXT_COLOR := Color("9fd8a8")
const UNPAID_TEXT_COLOR := Color("f0a0a0")

## A source chip prints how much of today's produce has been drawn, under its
## glyph -- "21/80". The retired sign carried this and item 48 moved it to the
## hover tip, which item 55 then retired outright; with no panel left, the
## chip is the only place it can live, and it belongs there anyway. Without it
## the map only distinguished a spent source from a stocked one by the glyph
## going grey, which says whether there is anything left but never how much.
const SOURCE_AMOUNT_COLOR := Color(0.90, 0.91, 0.93)
const SOURCE_SPENT_AMOUNT_COLOR := Color(0.60, 0.61, 0.63)
## The glyph shrinks and lifts to make room. Kept large enough that the
## silhouette still resolves at map zoom, which is the whole reason it is 4x
## in the first place.
## A source row is laid out like an EXPANDED settlement row -- full-size glyph
## in the leftmost square cell, figure to its right at the same size a
## settlement prints its amount -- rather than stacking the two inside a
## square chip.
##
## Stacking was tried first and cannot hold the figure at that size. The
## settlement amount is int(192 * 0.34) = 65px, at which "21/80" measures
## 174px and an upgraded source's "110/180" measures 248px, against a square
## chip's 168px interior. Anything stacked therefore had to shrink either the
## glyph (which is 4x for legibility, so shrinking it undoes the point) or the
## figure (which is the thing being matched). Widening instead keeps both at
## full size, and it makes a source row structurally the same object as the
## settlement row it sits beside.
## 468 is the exact fit -- "180/180", the widest figure an upgraded source can
## show, measures 248px at this font and the text band is 248px wide. Twelve
## more so font-metric variation cannot push the widest case into a shrink.
const SOURCE_ROW_WIDTH := 480.0

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

## ---------- shared column geometry ----------
##
## The collapsed chips and the expanded balloons are THE SAME COLUMN at two
## widths. Every row is the same height and sits at the same pitch in both,
## and the food glyph occupies the same cell at the left of a row either way,
## so expanding a node grows the panel rightward around a glyph that does not
## move. That is what makes a hover read as a chip unfurling rather than one
## object being swapped for another.
##
## This only works because BOTH are a single baked texture. While the
## balloons were separate world-space markers their row pitch had to fight
## the camera pitch -- a world-Y step buys only half its length in screen
## separation at -60 degrees -- so the two layouts were computed in unrelated
## units and could not be held in line. Folding the balloons into one canvas
## deletes that problem rather than compensating for it.

## Outer size of one row: a chip is exactly this square.
static func row_size() -> float:
	return CHIP_GLYPH_RADIUS * 2.0 + CHIP_PADDING * 2.0

## An expanded row is the same height, just wider -- room for the amount, the
## freshness percentage and the bar, to the right of the glyph cell.
## Widened from 420 to fit a rejected row's third line ("5 spoiled at 32%")
## at a readable size. The row has vertical room to spare and none
## horizontally, and this only affects the hovered node.
const BALLOON_ROW_WIDTH := 560.0
const ROW_TEXT_GAP := 10.0
const ROW_RIGHT_PAD := 18.0

static func column_width(expanded: bool, source := false) -> float:
	if source:
		return SOURCE_ROW_WIDTH + CHIP_MARGIN * 2.0
	return (BALLOON_ROW_WIDTH if expanded else row_size()) + CHIP_MARGIN * 2.0

## Canvas size for `count` rows. Height is deliberately independent of
## `expanded`, so a column occupies the same vertical space collapsed or not
## and row i lands at the same screen height in both.
static func column_size(count: int, expanded: bool, source := false) -> Vector2i:
	var n := maxi(count, 1)
	return Vector2i(
		ceili(column_width(expanded, source)),
		ceili(n * row_size() + (n - 1) * CHIP_GAP + CHIP_MARGIN * 2.0 + TAIL_HEIGHT),
	)

## How far right an expanded column must be nudged for its glyph cell to land
## exactly where the collapsed column's chips were. Both canvases are centred
## on the marker, so widening one would otherwise slide the glyphs left.
static func column_x_shift() -> float:
	return (column_width(true) - column_width(false)) * 0.5

## Centre of the glyph cell within a row, measured from the canvas's left
## edge. Identical in both states -- this is the anchor the whole layout is
## built around, and the tail hangs from it rather than from the panel's
## centre, so it keeps pointing at the node when the panel widens.
static func glyph_centre_x() -> float:
	return CHIP_MARGIN + row_size() * 0.5

## Kept as the name the rest of the code already uses for a chip column.
static func glyph_column_size(count: int) -> Vector2i:
	return column_size(count, false)

## Whether these entries belong to a source. Sources are never judged on a
## delivery, so DEFAULT/MUTED is the tell (see _is_delivery_status).
static func entries_are_source(entries: Array) -> bool:
	return not entries.is_empty() and not _is_delivery_status(entries[0].status)

## One {food_id, color, status} per open order, already sorted worst-first
## by main.gd. An expanded column's entries additionally carry amount_text,
## freshness_pct and threshold.
var _entries: Array = []
## Expanded rows are wider and carry the amount, freshness and bar. Row
## height, pitch, glyph cell and tail are identical either way.
var _expanded := false
## Settlements hang a tail off the column; sources do not.
var _has_tail := false

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

## The map's default layer. `entries` is one {food_id, color, status} per
## open order (or, for a source, its single produced food), worst-first.
## `is_settlement` decides both the tail (a settlement's tell, the way the
## post used to be a source's) and the row width -- one flag because they are
## two consequences of the same fact.
func set_glyph_column(entries: Array, is_settlement: bool) -> void:
	_entries = entries
	_expanded = false
	_has_tail = is_settlement
	queue_redraw()

## The inspected view: the same column, each row widened to carry
## amount_text, freshness_pct and threshold alongside the glyph.
func set_settlement_column(entries: Array) -> void:
	_entries = entries
	_expanded = true
	_has_tail = true
	queue_redraw()

func _draw() -> void:
	_draw_column()

# --- the column -------------------------------------------------------

## One column, drawn the same way collapsed or expanded. `_expanded` only
## widens each row and fills the extra space with the amount, the freshness
## percentage and the bar -- the row height, the pitch, the glyph cell and
## the tail are identical either way.
func _draw_column() -> void:
	if _entries.is_empty():
		return

	var row_h := row_size()
	var source := not _expanded and not _has_tail
	var row_w := column_width(_expanded, source) - CHIP_MARGIN * 2.0
	var glyph_r := CHIP_GLYPH_RADIUS
	# The glyph cell is always the leftmost row_h square of a row, so the
	# glyph lands at the same place in both states.
	var cell_cx := CHIP_MARGIN + row_h * 0.5

	var y := CHIP_MARGIN
	for entry in _entries:
		var rect := Rect2(Vector2(CHIP_MARGIN, y), Vector2(row_w, row_h))
		var status: FoodBubbleMarker.Status = entry.status
		var judged := _is_delivery_status(status)
		var accent := status_color(status)
		var radius := int(row_h * (SETTLEMENT_CHIP_CORNER_RATIO if judged else SOURCE_CHIP_CORNER_RATIO))

		if status == FoodBubbleMarker.Status.RED:
			_draw_halo(rect, radius, accent)

		# A settlement row takes its status colour as a background; a source
		# row stays neutral slate with near-square corners, because a source
		# has no delivery to be judged on and must not look like it does.
		var fill := CHIP_SLATE.lerp(Color(accent.r, accent.g, accent.b, CHIP_SLATE.a), CHIP_STATUS_TINT) if judged else CHIP_SLATE
		var border := accent if judged else CHIP_SLATE_BORDER
		var border_width := GREEN_BORDER_WIDTH if status == FoodBubbleMarker.Status.GREEN else CHIP_BORDER_WIDTH
		_draw_body(rect, radius, fill, border, border_width)

		var cell_centre := Vector2(cell_cx, y + row_h * 0.5)
		# Stroked in the chip's light ink: this outline is the only thing
		# separating a pale milk bottle -- or a green carrot on a green-tinted
		# row -- from the ground behind it (FoodGlyphs), so it cannot be a hint.
		FoodGlyphs.draw_glyph(self, entry.food_id, cell_centre, glyph_r, entry.color, CHIP_GLYPH_INK)

		# A source prints its draw-down beside the glyph, at exactly the size a
		# settlement prints its amount -- same expression, so the two cannot
		# drift apart.
		var amount: String = entry.get("amount_text", "")
		if source and amount != "":
			var spent: bool = status == FoodBubbleMarker.Status.MUTED
			var text_x := cell_cx + row_h * 0.5 + ROW_TEXT_GAP
			_draw_fitted(
				amount,
				text_x,
				rect.end.x - ROW_RIGHT_PAD - text_x,
				cell_centre.y,
				int(row_h * 0.34),
				SOURCE_SPENT_AMOUNT_COLOR if spent else SOURCE_AMOUNT_COLOR,
			)

		# The status mark stays pinned to the glyph cell in BOTH states rather
		# than moving to the far edge when the row widens -- the point of the
		# layout is that nothing the eye is tracking moves.
		if judged:
			var sr := row_h * CHIP_STATUS_RATIO * 0.5
			var sc := Vector2(cell_cx + row_h * 0.5, y + row_h) - Vector2(sr, sr) - Vector2(CHIP_BORDER_WIDTH, CHIP_BORDER_WIDTH)
			draw_circle(sc, sr * 1.06, CHIP_STATUS_BACKING)
			_draw_status_mark(status, sc, sr, accent)

		if _expanded:
			_draw_row_detail(entry, rect, cell_cx + row_h * 0.5, accent)
		y += row_h + CHIP_GAP

	# One tail for the whole column, hung from the glyph cell rather than the
	# panel's centre -- so it keeps pointing at the node when an expanded
	# panel widens to the right. Sources get none: a tail is a settlement's
	# tell, the way the post used to be a source's.
	if _has_tail:
		# The bottom row's colour, not the worst row's: the tail hangs off
		# that row and reads as part of it. Overall severity is already the
		# top chip's job.
		_draw_column_tail(y - CHIP_GAP, status_color(_entries[-1].status))

## The right-hand part of an expanded row: the amount, the freshness
## percentage under it, and the bar. Everything here lives in the space a
## collapsed chip simply does not have.
func _draw_row_detail(entry: Dictionary, rect: Rect2, cell_right: float, accent: Color) -> void:
	var text_x := cell_right + ROW_TEXT_GAP
	var text_w := rect.end.x - ROW_RIGHT_PAD - text_x
	var bar_y := rect.end.y - BAR_BOTTOM_MARGIN - BAR_HEIGHT
	var row_cy := rect.position.y + (rect.size.y - BAR_BOTTOM_MARGIN - BAR_HEIGHT) * 0.5
	var fresh: int = entry.get("freshness_pct", -1)

	var rejected: float = entry.get("rejected", 0.0)
	var rejected_fresh: int = entry.get("rejected_freshness_pct", -1)
	var earned: float = entry.get("earned", 0.0)
	var withheld: float = entry.get("withheld", 0.0)
	var sub := int(rect.size.y * 0.17)
	var paid := earned > 0.0

	# The third line is whichever piece of bad news this row has, in one
	# tone: what spoiled, or -- failing that -- what a short order gave up.
	# A row with neither has nothing to say there.
	var note := ""
	if rejected > 0.0:
		note = _rejected_text(rejected, rejected_fresh)
	elif withheld > 0.0:
		note = "§%d withheld" % roundi(withheld)

	# Three layouts, by how much there is to say. The rejected line matters
	# most on a RED row, where it is usually the entire reason the line came
	# up short: cargo under min_freshness is binned AND still consumes the
	# day's demand, and the delivered freshness above cannot show it because
	# it averages only what was accepted.
	# Freshness and money share a line: they are the two facts that between
	# them explain the row's colour, and pairing them is what stops the
	# freshness reading as the reason on its own.
	var money := "+§%d" % roundi(earned) if paid else "§0"
	var status_line := "%d%% fresh · %s" % [fresh, money] if fresh >= 0 else money

	if note != "":
		_draw_fitted(entry.amount_text, text_x, text_w, row_cy - 30.0, int(rect.size.y * 0.30), TEXT_COLOR)
		_draw_pair(status_line, money, text_x, text_w, row_cy + 14.0, sub, paid)
		_draw_fitted(note, text_x, text_w, row_cy + 48.0, sub, REJECTED_TEXT_COLOR)
	else:
		_draw_fitted(entry.amount_text, text_x, text_w, row_cy - 16.0, int(rect.size.y * 0.34), TEXT_COLOR)
		_draw_pair(status_line, money, text_x, text_w, row_cy + 30.0, sub, paid)

	_draw_freshness_bar(
		Rect2(Vector2(text_x, bar_y), Vector2(text_w, BAR_HEIGHT)),
		accent,
		fresh,
		entry.get("threshold", 0.0),
		entry.get("min_threshold", 0.0),
		entry.status,
	)

## Draws "94% fresh · +§300", tinting only the money half -- green when the
## line paid, red when it did not. Two draws rather than one so the money
## carries its own colour: it is the half that explains the row.
func _draw_pair(full: String, money: String, x: float, max_width: float, center_y: float, font_size: int, paid: bool) -> void:
	var money_ink := EARNED_TEXT_COLOR if paid else UNPAID_TEXT_COLOR
	# Nothing arrived, so the line is the money alone -- drawing the grey pass
	# under it would just double-strike the same glyphs.
	if full == money:
		_draw_fitted(money, x, max_width, center_y, font_size, money_ink)
		return
	var used := _draw_fitted(full, x, max_width, center_y, font_size, SUBTEXT_COLOR)
	var font := ThemeDB.fallback_font
	var money_w := font.get_string_size(money, HORIZONTAL_ALIGNMENT_LEFT, -1, used).x
	var full_w := font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, used).x
	draw_string(
		font,
		Vector2(x + full_w - money_w, center_y + used * 0.36),
		money,
		HORIZONTAL_ALIGNMENT_LEFT,
		money_w,
		used,
		money_ink,
	)

## "5 spoiled at 32%" -- the amount turned away and how fresh it actually
## was, which is what says whether the route is marginally too long or wildly
## so. Falls back to the amount alone if the freshness is somehow unknown.
static func _rejected_text(rejected: float, rejected_fresh: int) -> String:
	if rejected_fresh < 0:
		return "%d spoiled" % roundi(rejected)
	return "%d spoiled at %d%%" % [roundi(rejected), rejected_fresh]

func _draw_column_tail(bottom: float, accent: Color) -> void:
	var cx := glyph_centre_x()
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - TAIL_HALF_WIDTH, bottom - TAIL_OVERLAP),
		Vector2(cx + TAIL_HALF_WIDTH, bottom - TAIL_OVERLAP),
		Vector2(cx, bottom + TAIL_HEIGHT),
	]), accent)

## Whether a status is a settlement's delivery verdict rather than a source's
## stock level. DEFAULT/MUTED belong to sources, which are never judged.
static func _is_delivery_status(status: FoodBubbleMarker.Status) -> bool:
	return status == FoodBubbleMarker.Status.RED \
		or status == FoodBubbleMarker.Status.AMBER \
		or status == FoodBubbleMarker.Status.GREEN

# --- shared pieces ----------------------------------------------------

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

func _draw_freshness_bar(track: Rect2, accent: Color, freshness_pct: int, threshold: float, min_threshold: float, status: FoodBubbleMarker.Status) -> void:
	var radius := int(track.size.y * 0.5)

	var track_box := StyleBoxFlat.new()
	track_box.bg_color = BAR_TRACK_COLOR
	track_box.set_corner_radius_all(radius)
	draw_style_box(track_box, track)

	var filled := 0.0 if freshness_pct < 0 else clampf(freshness_pct / 100.0, 0.0, 1.0)
	if filled > 0.0:
		# Never draw a fill narrower than it is tall -- a rounded box
		# thinner than its own corner radius renders as a smear.
		var fill_box := StyleBoxFlat.new()
		fill_box.bg_color = BAR_INERT_COLOR if status == FoodBubbleMarker.Status.RED else accent
		fill_box.set_corner_radius_all(radius)
		draw_style_box(fill_box, Rect2(track.position, Vector2(maxf(track.size.x * filled, track.size.y), track.size.y)))

	# The refusal floor, over the fill so it reads however full the bar is.
	var floor_mark := clampf(min_threshold, 0.0, 1.0)
	if floor_mark > 0.0:
		var zone_box := StyleBoxFlat.new()
		zone_box.bg_color = BAR_MIN_ZONE_COLOR
		zone_box.set_corner_radius_all(radius)
		draw_style_box(zone_box, Rect2(track.position, Vector2(track.size.x * floor_mark, track.size.y)))
		var fx := track.position.x + track.size.x * floor_mark
		draw_line(Vector2(fx, track.position.y - 2.0), Vector2(fx, track.end.y + 2.0), BAR_MIN_TICK_COLOR, BAR_TICK_WIDTH)

	# The bonus target. Drawn last so it stays readable whichever side of the
	# threshold the bar has reached.
	var mark := clampf(threshold, 0.0, 1.0)
	if mark > 0.0 and mark < 1.0:
		var x := track.position.x + track.size.x * mark
		draw_line(Vector2(x, track.position.y - 2.0), Vector2(x, track.end.y + 2.0), BAR_TICK_COLOR, BAR_TICK_WIDTH)

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
