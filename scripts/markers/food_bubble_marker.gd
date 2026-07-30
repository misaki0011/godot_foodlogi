class_name FoodBubbleMarker
extends Node3D

## A node's whole order column, floated above it: one row per open order,
## drawn once into a SubViewport and shown on a billboard Sprite3D. Baking
## the entire column -- shapes, glyphs, numbers, bars -- into ONE texture
## avoids Label3D sorting behind the shapes, reads far crisper than stacked
## 3D primitives at this scale, and is what lets the collapsed and expanded
## layouts line up exactly (see BubbleCanvas's shared column geometry).
##
## Sources and settlements share this scene but not their look: see
## bubble_canvas.gd for how a source row is told from a settlement row.

## Sprite3D.pixel_size as authored in food_bubble_marker.tscn.
const BASE_PIXEL_SIZE := 0.01

## What the map layer renders at. Collapsed and expanded use the SAME value,
## which is what lets a row land at the same screen height in both -- see
## BubbleCanvas's shared column geometry.
##
## An earlier design spaced expanded balloons as separate world-space markers
## and had to double every gap to fight the camera's -60 degree pitch (a
## world-Y step buys only half its length in screen separation). Drawing the
## whole column into one texture removed that problem outright, along with
## the STACK_SPACING / COLUMN_SPACING / CAMERA_VERTICAL_COMPENSATION
## constants that existed only to manage it.
const COLUMN_SCALE := 0.72

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

## The map's default layer: one chip per open order (or, for a source, its
## single produced food), stacked vertically. `entries` is one
## {food_id, color, status} per chip, already sorted worst-first -- the
## column's TOP chip is the thing most worth doing something about.
func setup_glyph_column(entries: Array, has_tail: bool) -> void:
	_apply(BubbleCanvas.column_size(entries.size(), false), 0.0)
	_canvas.set_glyph_column(entries, has_tail)
	_bake()

## The inspected view: the same column with every row widened to carry its
## amount, freshness and bar. `entries` additionally carry delivered,
## requested and freshness_pct; `bonus_freshness` and `min_freshness` place
## each bar's two marks -- the bonus target and the refusal floor.
##
## The canvas is shifted right by exactly half the width it gained, so the
## glyph cell lands where the collapsed chips were and the panel appears to
## unfurl around a glyph that does not move.
func setup_settlement_column(entries: Array, bonus_freshness: float, min_freshness: float) -> void:
	var rows: Array = []
	for e in entries:
		rows.append({
			"food_id": e.food_id,
			"color": e.color,
			"status": e.status,
			"amount_text": _ratio_text(e.delivered, e.requested),
			"freshness_pct": e.freshness_pct,
			"threshold": bonus_freshness / 100.0,
			"min_threshold": min_freshness / 100.0,
			"rejected": e.get("rejected", 0.0),
			"rejected_freshness_pct": e.get("rejected_freshness_pct", -1),
			"earned": e.get("earned", 0.0),
			"withheld": e.get("withheld", 0.0),
		})
	_apply(BubbleCanvas.column_size(rows.size(), true), BubbleCanvas.column_x_shift())
	_canvas.set_settlement_column(rows)
	_bake()

## Points the sprite at a viewport of `px` pixels, anchored by its bottom
## edge (offset = half the height, as food_bubble_marker.tscn authors it) and
## nudged right by `shift_x`. The canvas is resized alongside the viewport
## rather than left to the next layout pass, because the bake is immediate.
func _apply(px: Vector2i, shift_x: float) -> void:
	_viewport.size = px
	_canvas.size = Vector2(px)
	_sprite.pixel_size = BASE_PIXEL_SIZE * COLUMN_SCALE
	_sprite.offset = Vector2(shift_x, px.y * 0.5)

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
