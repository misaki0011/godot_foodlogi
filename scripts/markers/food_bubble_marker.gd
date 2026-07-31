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

## ---------- flourishes ----------
##
## One per column per day, and they form a vocabulary rather than three
## settings of one motion:
##
##   POP     scale, springing up from nothing -- a new order (§6)
##   HOP     a full vertical bounce -- a line paid its bonus
##   NUDGE   a shallow vertical lift -- a line paid, no bonus
##   SHAKE   a horizontal wobble -- a line paid nothing
##
## The axis carries the meaning. Vertical is "this paid", and its height says
## how well; horizontal is "this did not pay" and is the odd one out on
## purpose, because that is the categorical break in §9's tiers -- amber and
## green are neighbours, red is a different kind of day. Scale is reserved for
## POP so a new order never reads as a variant of a delivery.
##
## Item 30 kept the red halo static because on day one every settlement is red
## and a screen of pulsing bubbles is worse than no emphasis at all. These are
## one-shot and event-driven rather than idling, which is the distinction --
## but SHAKE is the one that most tests it, since red is also the resting
## state of anything not yet connected. See the note in SPEC.md item 59.
enum Flourish { NONE, POP, HOP, NUDGE, SHAKE }

## Springing from nearly nothing both lengthens the travel and deepens the
## overshoot: TRANS_BACK's kick is proportional to the range it interpolates.
const POP_FROM_SCALE := 0.18
const POP_SEC := 0.50

## Heights are world units and the camera eats more than half of each: at a
## -60 degree pitch the up vector is (0, 0.5, -0.866), so a +1.1 world-Y step
## reads as 0.55 units of SCREEN rise against a 1.38-unit chip -- about 40%.
## The nudge is deliberately well under half the hop, so "paid" and "paid
## well" are the same gesture at two amplitudes.
const HOP_HEIGHT := 1.1
const HOP_UP_SEC := 0.18
const HOP_DOWN_SEC := 0.26
const NUDGE_HEIGHT := 0.45
const NUDGE_UP_SEC := 0.14
const NUDGE_DOWN_SEC := 0.18

## Horizontal offsets map 1:1 onto screen X -- the camera has no yaw -- so the
## shake needs no compensation and reads at its stated size.
const SHAKE_OFFSET := 0.40
const SHAKE_STEP_SEC := 0.075
const SHAKE_SWINGS := 4
const SHAKE_DECAY := 0.62

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

## What play() was last asked for. Recorded because a tween applies nothing
## until it processes, so a marker's position is still at rest on the frame it
## was told to hop -- there is no synchronous way to observe the motion. The
## decision is the part that can break anyway (which flourish for which
## status, once only, pop first); the interpolation is Godot's.
var played: Flourish = Flourish.NONE

## Plays one flourish. Called by main.gd on the single render that follows a
## day or an order opening, on a marker rebuilt from scratch -- so there is
## nothing to reset and no way for two to stack on one marker.
func play(flourish: Flourish) -> void:
	played = flourish
	match flourish:
		Flourish.POP:
			_pop()
		Flourish.HOP:
			_rise(HOP_HEIGHT, HOP_UP_SEC, HOP_DOWN_SEC, Tween.TRANS_BOUNCE)
		Flourish.NUDGE:
			_rise(NUDGE_HEIGHT, NUDGE_UP_SEC, NUDGE_DOWN_SEC, Tween.TRANS_SINE)
		Flourish.SHAKE:
			_shake()

func _pop() -> void:
	scale = Vector3.ONE * POP_FROM_SCALE
	create_tween().tween_property(self, "scale", Vector3.ONE, POP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Up and back. The landing transition is what separates a hop from a nudge
## as much as the height does: BOUNCE lands with a little settle, SINE just
## sets the column back down.
func _rise(height: float, up_sec: float, down_sec: float, landing: Tween.TransitionType) -> void:
	var rest := position
	var tween := create_tween()
	tween.tween_property(self, "position", rest + Vector3(0.0, height, 0.0), up_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", rest, down_sec) \
		.set_trans(landing).set_ease(Tween.EASE_OUT)

## A damped left-right wobble, each swing shorter than the last so it reads as
## settling rather than stopping dead.
func _shake() -> void:
	var rest := position
	var tween := create_tween()
	var swing := SHAKE_OFFSET
	for i in SHAKE_SWINGS:
		var dir := 1.0 if i % 2 == 0 else -1.0
		tween.tween_property(self, "position", rest + Vector3(swing * dir, 0.0, 0.0), SHAKE_STEP_SEC) \
			.set_trans(Tween.TRANS_SINE)
		swing *= SHAKE_DECAY
	tween.tween_property(self, "position", rest, SHAKE_STEP_SEC).set_trans(Tween.TRANS_SINE)

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
