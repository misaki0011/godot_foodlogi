extends SceneTree

## Throwaway visual check for the food glyphs: renders every BubbleCanvas
## variant to a PNG so the silhouettes can actually be looked at, rather than
## trusted from their coordinates. Run under a virtual display:
##
##   xvfb-run -a godot --path . --script scripts/tools/preview_glyphs.gd

const FOODS := ["grain", "bread", "vegetables", "milk", "seafood"]
const OUT := "user://glyph_preview.png"

var _frame := 0

func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.42, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var foods := GameBalance.food_types()
	var three := [
		_e(foods, "seafood", FoodBubbleMarker.Status.RED, 0, 25, -1),
		_e(foods, "grain", FoodBubbleMarker.Status.AMBER, 20, 20, 72),
		_e(foods, "bread", FoodBubbleMarker.Status.GREEN, 30, 30, 94),
	]

	# The point of the layout: collapsed and expanded are the same column at
	# two widths. Drawn at a matching baseline here, every row must line up.
	# Both canvases lay rows out from their own left edge, so drawing them at
	# the same y with a clear gap is the alignment check: every row must sit
	# at the same height and the glyph the same distance in from the edge.
	# (In game the sprite is centre-anchored, which is what column_x_shift
	# compensates for -- that is arithmetic, not something to eyeball here.)
	_col(Vector2(30, 30), false).set_glyph_column(three, true)
	_col(Vector2(270, 30), true).set_settlement_column(_rows(three))

	var five := [
		_e(foods, "seafood", FoodBubbleMarker.Status.RED, 0, 35, -1),
		_e(foods, "milk", FoodBubbleMarker.Status.RED, 12, 30, 61),
		_e(foods, "vegetables", FoodBubbleMarker.Status.AMBER, 25, 25, 68),
		_e(foods, "grain", FoodBubbleMarker.Status.GREEN, 30, 30, 97),
		_e(foods, "bread", FoodBubbleMarker.Status.GREEN, 30, 30, 92),
	]
	_col(Vector2(760, 30), false).set_glyph_column(five, true)
	_col(Vector2(1000, 30), true).set_settlement_column(_rows(five))

	# Sources: near-square, neutral slate, no status mark and no tail.
	_col(Vector2(1500, 30), false).set_glyph_column([{
		"food_id": "grain", "color": BubbleCanvas.MUTED_ICON_COLOR,
		"status": FoodBubbleMarker.Status.MUTED,
	}], false)
	_col(Vector2(1500, 260), false).set_glyph_column(
		[_e(foods, "vegetables", FoodBubbleMarker.Status.DEFAULT, 0, 0, -1)], false)

	# Worst-case contrast: a food glyph on a row tinted its OWN hue.
	_col(Vector2(1500, 490), false).set_glyph_column([
		_e(foods, "vegetables", FoodBubbleMarker.Status.GREEN, 20, 20, 95),
		_e(foods, "grain", FoodBubbleMarker.Status.AMBER, 20, 20, 70),
	], true)

func _rows(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append({
			"food_id": e.food_id, "color": e.color, "status": e.status,
			"amount_text": "%d/%d" % [e.delivered, e.requested],
			"freshness_pct": e.freshness_pct, "threshold": 0.85,
		})
	return out

func _col(pos: Vector2, expanded: bool) -> BubbleCanvas:
	# Rows are laid out from the TOP of the canvas and the height is the same
	# either way, so drawing both at one y is exactly the alignment check.
	var c := BubbleCanvas.new()
	c.position = pos
	c.size = Vector2(BubbleCanvas.column_size(5, expanded))
	root.add_child(c)
	return c

func _e(foods: Dictionary, food_id: String, status: FoodBubbleMarker.Status, delivered: float, requested: float, fresh: int) -> Dictionary:
	return {
		"food_id": food_id, "color": foods[food_id].color, "status": status,
		"delivered": delivered, "requested": requested, "freshness_pct": fresh,
	}

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var img := root.get_texture().get_image()
	img.save_png(OUT)
	print("wrote ", ProjectSettings.globalize_path(OUT))
	return true
