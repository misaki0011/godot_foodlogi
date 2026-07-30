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
	var x := 10.0
	for food_id in FOODS:
		# Settlement balloon: full amount, short of the bonus line (amber).
		var s := _canvas(Vector2(x, 6), Vector2(310, 150))
		s.set_settlement(food_id, foods[food_id].color, "12/25", FoodBubbleMarker.Status.AMBER, 72, 0.85)
		x += 222.0

	# Glyph strips: one, three and five orders, spanning all three statuses.
	var one := _strip(Vector2(10, 180), 1)
	one.set_glyph_strip([_e(foods, "milk", FoodBubbleMarker.Status.RED)])
	var three := _strip(Vector2(320, 180), 3)
	three.set_glyph_strip([
		_e(foods, "seafood", FoodBubbleMarker.Status.RED),
		_e(foods, "grain", FoodBubbleMarker.Status.AMBER),
		_e(foods, "bread", FoodBubbleMarker.Status.GREEN),
	])
	var five := _strip(Vector2(10, 400), 5)
	five.set_glyph_strip([
		_e(foods, "seafood", FoodBubbleMarker.Status.RED),
		_e(foods, "milk", FoodBubbleMarker.Status.RED),
		_e(foods, "vegetables", FoodBubbleMarker.Status.AMBER),
		_e(foods, "grain", FoodBubbleMarker.Status.GREEN),
		_e(foods, "bread", FoodBubbleMarker.Status.GREEN),
	])
	# A source's strip, spent (muted) and stocked.
	var spent := _strip(Vector2(1120, 180), 1)
	spent.set_glyph_strip([{
		"food_id": "grain",
		"color": BubbleCanvas.MUTED_ICON_COLOR,
		"status": FoodBubbleMarker.Status.MUTED,
	}])
	var stocked := _strip(Vector2(1330, 180), 1)
	stocked.set_glyph_strip([_e(foods, "vegetables", FoodBubbleMarker.Status.DEFAULT)])

func _e(foods: Dictionary, food_id: String, status: FoodBubbleMarker.Status) -> Dictionary:
	return {"food_id": food_id, "color": foods[food_id].color, "status": status}

func _canvas(pos: Vector2, size: Vector2) -> BubbleCanvas:
	var c := BubbleCanvas.new()
	c.position = pos
	c.size = size
	root.add_child(c)
	return c

## A strip canvas sized exactly the way FoodBubbleMarker sizes its viewport,
## so the preview shows the real proportions rather than a guess.
func _strip(pos: Vector2, count: int) -> BubbleCanvas:
	return _canvas(pos, Vector2(BubbleCanvas.glyph_strip_size(count)))

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var img := root.get_texture().get_image()
	img.save_png(OUT)
	print("wrote ", ProjectSettings.globalize_path(OUT))
	return true
