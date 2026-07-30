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
	# One row per payment tier, which is what the colour has always encoded:
	# red earns nothing, amber earns the line, green earns the line + 25%.
	#
	# Every row is a state region 1 can actually reach. A line has one
	# candidate path per SOURCE PRODUCING THAT FOOD, and region 1 gives every
	# food exactly one source -- so a shipment is wholly accepted or wholly
	# rejected, and a row can never show a delivered amount AND spoiled cargo
	# at once. Row 1 is therefore short with nothing spoiled (supply ran out
	# or capacity capped it). Mixed accept/reject only becomes reachable on a
	# map giving one food two sources -- Cold Coast's two Harbors, when it
	# exists.
	var tiers := [
		_e(foods, "grain", FoodBubbleMarker.Status.RED, 25, 30, 90, 0, -1, 0, 90),
		_e(foods, "vegetables", FoodBubbleMarker.Status.AMBER, 25, 25, 68, 0, -1, 150, 0),
		_e(foods, "bread", FoodBubbleMarker.Status.GREEN, 30, 30, 94, 0, -1, 187, 0),
	]

	# The alignment check: collapsed and expanded are the same column at two
	# widths. Both lay rows out from their own left edge, so drawing them at
	# one y is exactly the test -- every row must sit at the same height with
	# the glyph the same distance in from the edge. (In game the sprite is
	# centre-anchored, which is what column_x_shift compensates for; that is
	# arithmetic, not something to eyeball here.)
	_col(Vector2(30, 30), false, 3).set_glyph_column(tiers, true)
	_col(Vector2(270, 30), true, 3).set_settlement_column(_rows(tiers))

	# A total rejection: nothing accepted, so no freshness line, and the
	# spoiled note carries the whole explanation.
	_col(Vector2(880, 30), true, 1).set_settlement_column(_rows([
		_e(foods, "seafood", FoodBubbleMarker.Status.RED, 0, 25, -1, 25, 18, 0, 250),
	]))

	# Worst-case contrast: a food glyph on a row tinted its OWN hue.
	_col(Vector2(880, 260), false, 2).set_glyph_column([
		_e(foods, "vegetables", FoodBubbleMarker.Status.GREEN, 20, 20, 95, 0, -1, 150, 0),
		_e(foods, "grain", FoodBubbleMarker.Status.AMBER, 20, 20, 70, 0, -1, 60, 0),
	], true)

	# Sources: near-square, neutral slate, no status mark and no tail, with
	# the day's draw-down printed under the glyph (item 55). The spent one
	# greys both glyph and figure.
	_col(Vector2(1130, 260), false, 1).set_glyph_column([{
		"food_id": "seafood", "color": foods["seafood"].color,
		"status": FoodBubbleMarker.Status.DEFAULT, "amount_text": "110/180",
	}], false)
	_col(Vector2(1370, 260), false, 1).set_glyph_column([{
		"food_id": "milk", "color": BubbleCanvas.MUTED_ICON_COLOR,
		"status": FoodBubbleMarker.Status.MUTED, "amount_text": "75/75",
	}], false)

func _rows(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append({
			"food_id": e.food_id, "color": e.color, "status": e.status,
			"amount_text": "%d/%d" % [e.delivered, e.requested],
			"freshness_pct": e.freshness_pct, "threshold": 0.85, "min_threshold": 0.35,
			"rejected": e.rejected, "rejected_freshness_pct": e.rejected_freshness_pct,
			"earned": e.earned, "withheld": e.withheld,
		})
	return out

func _col(pos: Vector2, expanded: bool, rows: int) -> BubbleCanvas:
	# Rows lay out from the TOP of the canvas and the height is the same
	# either way, so drawing a pair at one y is exactly the alignment check.
	var c := BubbleCanvas.new()
	c.position = pos
	c.size = Vector2(BubbleCanvas.column_size(rows, expanded))
	root.add_child(c)
	return c

func _e(foods: Dictionary, food_id: String, status: FoodBubbleMarker.Status, delivered: float, requested: float, fresh: int, rejected: float, rejected_fresh: int, earned: float, withheld: float) -> Dictionary:
	return {
		"food_id": food_id, "color": foods[food_id].color, "status": status,
		"delivered": delivered, "requested": requested, "freshness_pct": fresh,
		"rejected": rejected, "rejected_freshness_pct": rejected_fresh,
		"earned": earned, "withheld": withheld,
	}

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var img := root.get_texture().get_image()
	img.save_png(OUT)
	print("wrote ", ProjectSettings.globalize_path(OUT))
	return true
