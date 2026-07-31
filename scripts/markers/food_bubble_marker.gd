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

## A newly opened order pops its column in, once. Scaled about the marker's
## own origin, which sits at the node, so the column springs UP out of the
## settlement rather than inflating around its own middle.
##
## Item 30 ruled out animating the red halo, on the grounds that on day one
## every settlement is red and a screen of pulsing bubbles is worse than no
## emphasis at all. This is the opposite case and the distinction is the
## point: a pop marks a discrete, rare event -- one per order the player just
## earned -- and stops on its own. Nothing here ever repeats or idles.
## Starting smaller both enlarges the travel and deepens the overshoot:
## TRANS_BACK's kick is proportional to the interpolated range, so 0.30 peaks
## near 1.07 where 0.55 only reached about 1.045.
const POP_FROM_SCALE := 0.30
const POP_SEC := 0.42

## A settlement that delivered a line at bonus freshness hops, once, on the
## render that follows the day. Scale is the pop's verb and position is the
## jump's, so the two events never look like variants of each other.
##
## Height is in world units and the camera eats more than half of it: at a
## -60 degree pitch the up vector is (0, 0.5, -0.866), so a +0.5 world-Y step
## reads as 0.25 units of SCREEN rise -- about 18% of a 1.38-unit chip. Small,
## which is what was asked for, and what keeps five of them at once reading as
## a flourish rather than a disturbance.
const JUMP_HEIGHT := 0.5
const JUMP_UP_SEC := 0.16
const JUMP_DOWN_SEC := 0.22

@onready var _canvas: BubbleCanvas = $SubViewport/BubbleCanvas
@onready var _viewport: SubViewport = $SubViewport
@onready var _sprite: Sprite3D = $Sprite3D

func _ready() -> void:
	_sprite.texture = _viewport.get_texture()

## The map's default layer: one chip per open order (or, for a source, its
## single produced food), stacked vertically. `entries` is one
## {food_id, color, status} per chip, already sorted worst-first -- the
## column's TOP chip is the thing most worth doing something about.
func setup_glyph_column(entries: Array, is_settlement: bool) -> void:
	_apply(BubbleCanvas.column_size(entries.size(), false, not is_settlement), 0.0)
	_canvas.set_glyph_column(entries, is_settlement)
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
##
## BubbleCanvas is authored with NO anchors for that reason. Full-rect anchors
## would size it from the SubViewport on the next layout pass, which is a pass
## too late -- and setting its size anyway drew a "non-equal opposite anchors
## will have their size overridden" warning on every single marker built.
func _apply(px: Vector2i, shift_x: float) -> void:
	_viewport.size = px
	_canvas.size = Vector2(px)
	_sprite.pixel_size = BASE_PIXEL_SIZE * COLUMN_SCALE
	_sprite.offset = Vector2(shift_x, px.y * 0.5)

## Springs the column in from POP_FROM_SCALE with a slight overshoot. Called
## by main.gd on the one render that follows an order opening; a marker is
## rebuilt from scratch on every render, so there is nothing to reset and no
## way for two pops to stack on one marker.
func pop() -> void:
	scale = Vector3.ONE * POP_FROM_SCALE
	create_tween().tween_property(self, "scale", Vector3.ONE, POP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A small hop, up and back with a bounce on the landing. Like pop(), called
## on the one render that follows a day, on a marker rebuilt from scratch --
## so there is nothing to reset and no way for two to stack.
func jump() -> void:
	var rest := position
	var tween := create_tween()
	tween.tween_property(self, "position", rest + Vector3(0.0, JUMP_HEIGHT, 0.0), JUMP_UP_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", rest, JUMP_DOWN_SEC) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
