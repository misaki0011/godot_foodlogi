class_name FoodGlyphs

## One silhouette per food, drawn from primitives onto any CanvasItem.
##
## Colour alone cannot identify a food on this map. A bubble carries no food
## NAME at all (see bubble_canvas.gd's set_settlement), so before this the
## only thing saying "this is milk and not grain" was a coloured dot -- and
## the palette does not support that job:
##
##   * Milk (#EDEFE6) against the cream bubble body (#F7F0DE) is a contrast
##     ratio of about 1.02:1. The dot and the bubble are the same colour;
##     the milk dot was effectively invisible.
##   * Grain (#D9C36A) and Bread (#C89A5B) are adjacent mid-golds --
##     separable side by side, much less so alone at map zoom.
##
## Shape has to carry the identity, so each food gets a silhouette that
## survives being small, and the SAME silhouette is used everywhere the food
## appears (source sign, settlement bubble, glyph strip), which is what makes
## it learnable rather than decorative: the mark on the Harbor's sign is the
## mark on City E's bubble.
##
## Three rules keep them legible at map zoom:
##
##   1. Solid silhouette, no interior detail -- anything relying on an
##      internal line is the first thing to disappear.
##   2. Every glyph is stroked in ink as well as filled. This is what
##      rescues milk: a near-white bottle on cream is still legible by its
##      edge when the fill is not.
##   3. Distinct at a glance in outline alone -- a tall chevroned ear, a
##      wide dome, a round tuft, a necked bottle, a tailed fish.
##
## Drawn from polygons rather than typeset from a font, for the same reason
## bubble_canvas.gd draws its check/cross by hand: the fallback font is not
## guaranteed to carry any of these, and a row of tofu boxes would be worse
## than no glyph at all.

## Unit-space outlines, in a roughly [-1, 1] box with +Y pointing DOWN (Godot
## 2D convention). Scaled by the requested radius at draw time.
##
## `static var` rather than `const`: a PackedVector2Array built from Vector2
## literals is not a constant expression in GDScript 4, so these are
## initialised once on first class access instead.
## An ear of wheat: pointed at BOTH ends and widest in the middle, with the
## grains angled up and out.
##
## The first attempt had the lobes widening downward into a narrow stem,
## which is precisely a conifer -- it rendered as a Christmas tree and not as
## grain at all. Losing the stem and making the envelope a lens is what fixes
## it: nothing tapers to a trunk, so there is no tree to read.
static var _GRAIN := PackedVector2Array([
	Vector2(0.00, -1.00),
	Vector2(0.30, -0.62), Vector2(0.10, -0.50),
	Vector2(0.38, -0.16), Vector2(0.10, -0.04),
	Vector2(0.34, 0.30), Vector2(0.10, 0.42),
	Vector2(0.00, 1.00),
	Vector2(-0.10, 0.42), Vector2(-0.34, 0.30),
	Vector2(-0.10, -0.04), Vector2(-0.38, -0.16),
	Vector2(-0.10, -0.50), Vector2(-0.30, -0.62),
])

static var _MILK := PackedVector2Array([
	Vector2(-0.20, -1.00), Vector2(0.20, -1.00),
	Vector2(0.20, -0.58), Vector2(0.48, -0.26),
	Vector2(0.48, 0.92), Vector2(-0.48, 0.92),
	Vector2(-0.48, -0.26), Vector2(-0.20, -0.58),
])

static var _SEAFOOD := PackedVector2Array([
	Vector2(0.98, 0.02),
	Vector2(0.55, -0.34), Vector2(0.05, -0.46), Vector2(-0.38, -0.30), Vector2(-0.62, -0.12),
	Vector2(-0.98, -0.62), Vector2(-0.80, 0.02), Vector2(-0.98, 0.62),
	Vector2(-0.62, 0.14), Vector2(-0.38, 0.32), Vector2(0.05, 0.48), Vector2(0.55, 0.36),
])

## A carrot: the only glyph in the set that tapers DOWNWARD to a point, which
## is what keeps it clear of the wheat ear's lens and the loaf's dome.
##
## It replaces a round root with two leaves either side, which rendered as
## unmistakably a cat's face -- two symmetric triangles on a circle are ears,
## whatever they were meant to be. Three fronds rather than two is most of
## the fix: an odd number spread across the top reads as a tuft, where a
## symmetric pair reads as a head.
static var _VEG_BODY := PackedVector2Array([
	Vector2(-0.54, -0.26), Vector2(0.54, -0.26),
	Vector2(0.30, 0.42), Vector2(0.00, 1.00), Vector2(-0.30, 0.42),
])
## One chunky tuft rather than three thin fronds. The three-frond version
## rendered as pure outline at strip size: each frond was about 4px across
## while the ink stroke is 3px, so the stroke ate the whole shape and the
## glyph came out a pale spiky blob with no food colour left in it. Nothing
## in this set may be thinner than a few multiples of the stroke.
static var _VEG_TUFT := PackedVector2Array([
	Vector2(-0.24, -0.22), Vector2(-0.20, -0.86), Vector2(0.00, -0.52),
	Vector2(0.20, -0.86), Vector2(0.24, -0.22),
])

## How thick the ink outline is, relative to the glyph radius. Kept low
## deliberately: the stroke is drawn ON the fill's edge, so half of it eats
## inward, and a heavy stroke on a small glyph leaves no food colour showing
## at all -- which is how the first carrot ended up a white spiky blob.
const INK_WIDTH_RATIO := 0.11
## Floor so the outline never vanishes entirely -- it is what makes a pale
## fill (milk) readable against cream, so it has to survive the shrink.
const MIN_INK_WIDTH := 1.2

## Draws `food_id`'s silhouette centred on `center`, sized so it fits inside
## a circle of radius `r`. `fill` is normally the food's own colour and `ink`
## the surrounding surface's text colour.
static func draw_glyph(ci: CanvasItem, food_id: String, center: Vector2, r: float, fill: Color, ink: Color) -> void:
	var w := maxf(r * INK_WIDTH_RATIO, MIN_INK_WIDTH)
	match food_id:
		"grain":
			_poly(ci, _GRAIN, center, r, fill, ink, w)
		"bread":
			_poly(ci, _loaf(), center, r, fill, ink, w)
		"vegetables":
			_poly(ci, _VEG_TUFT, center, r, fill, ink, w)
			# Body last, so its outline closes over where the fronds meet it
			# rather than three seams crossing the carrot's shoulder.
			_poly(ci, _VEG_BODY, center, r, fill, ink, w)
		"milk":
			_poly(ci, _MILK, center, r, fill, ink, w)
		"seafood":
			_poly(ci, _SEAFOOD, center, r, fill, ink, w)
		_:
			# An unknown food still has to render as *something* identifiable
			# rather than vanishing: a plain disc is the old dot, which is
			# exactly the right fallback.
			ci.draw_circle(center, r * 0.72, fill)
			ci.draw_arc(center, r * 0.72, 0.0, TAU, 24, ink, w, true)

## A loaf: flat base, domed top. Generated rather than written out so the
## dome stays smooth at any size.
static func _loaf() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-0.88, 0.56)])
	var steps := 14
	for i in steps + 1:
		var a: float = PI - PI * (float(i) / float(steps))
		pts.append(Vector2(cos(a) * 0.88, 0.06 - sin(a) * 0.72))
	pts.append(Vector2(0.88, 0.56))
	return pts

static func _poly(ci: CanvasItem, unit: PackedVector2Array, center: Vector2, r: float, fill: Color, ink: Color, ink_width: float) -> void:
	var pts := PackedVector2Array()
	for p in unit:
		pts.append(center + p * r)
	ci.draw_colored_polygon(pts, fill)
	# Closed polyline rather than draw_polygon's own outline: this keeps the
	# stroke exactly on the fill's edge at every size.
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, ink, ink_width, true)
