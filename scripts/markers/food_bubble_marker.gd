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
## One per column, and what is left is deliberately small:
##
##   POP     scale, springing up from nothing -- a new order arriving (§6)
##   SHAKE   a horizontal wobble -- this settlement's worst line paid nothing
##   NAG     the same wobble, gentler -- that line is STILL paying nothing
##
## **A good day is now silent** (item 66). HOP and NUDGE marked the two paying
## tiers with a vertical bounce and a shallow lift, and both are retired: on a
## working network most settlements pay most days, so the two of them together
## meant the map moved on nearly every rollover, and motion that happens
## whenever nothing is wrong cannot mean "look here". What they said is said
## anyway and better -- the chip's colour is the tier, and the payout label
## (item 60) floats the actual figure at the moment it changes. Movement is now
## spent only on the two things a player should act on: a line paying nothing,
## and a new order arriving.
##
## That leaves one axis per meaning rather than an axis per tier: horizontal is
## "this did not pay", scale is "this is new". They can no longer be confused
## for amplitudes of one motion, because there is no longer a scale of anything.
##
## Item 30 kept the red halo static because on day one every settlement is red
## and a screen of pulsing bubbles is worse than no emphasis at all. These are
## one-shot and event-driven rather than idling, which is the distinction --
## but SHAKE is the one that most tests it, since red is also the resting
## state of anything not yet connected. See the note in SPEC.md item 59.
enum Flourish { NONE, POP, SHAKE, NAG }

## Springing from nearly nothing both lengthens the travel and deepens the
## overshoot: TRANS_BACK's kick is proportional to the range it interpolates.
const POP_FROM_SCALE := 0.18
const POP_SEC := 0.50

## Horizontal offsets map 1:1 onto screen X -- the camera has no yaw -- so the
## shake needs no compensation and reads at its stated size.
const SHAKE_OFFSET := 0.40
const SHAKE_STEP_SEC := 0.075
const SHAKE_SWINGS := 4
const SHAKE_DECAY := 0.62

## The reminder is the same gesture at roughly half the amplitude and one
## swing fewer. It has to be recognisably the day-end shake -- it is the same
## complaint -- while being quiet enough to live with, because unlike the
## day-end version it repeats for as long as the problem does.
const NAG_OFFSET := 0.22
const NAG_STEP_SEC := 0.085
const NAG_SWINGS := 3

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
## requested, freshness_pct and earned; `bonus_freshness` places the bar's
## one mark, the point at which the line starts paying its bonus.
##
## The canvas is shifted right by exactly half the width it gained, so the
## glyph cell lands where the collapsed chips were and the panel appears to
## unfurl around a glyph that does not move.
func setup_settlement_column(entries: Array, bonus_freshness: float) -> void:
	var rows: Array = []
	for e in entries:
		rows.append({
			"food_id": e.food_id,
			"color": e.color,
			"status": e.status,
			"amount_text": _ratio_text(e.delivered, e.requested),
			"freshness_pct": e.freshness_pct,
			"threshold": bonus_freshness / 100.0,
			"earned": e.get("earned", 0.0),
		})
	_apply(BubbleCanvas.column_size(rows.size(), true), BubbleCanvas.column_x_shift(rows.size()))
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
		Flourish.SHAKE:
			_shake(SHAKE_OFFSET, SHAKE_STEP_SEC, SHAKE_SWINGS)
		Flourish.NAG:
			_shake(NAG_OFFSET, NAG_STEP_SEC, NAG_SWINGS)

func _pop() -> void:
	scale = Vector3.ONE * POP_FROM_SCALE
	create_tween().tween_property(self, "scale", Vector3.ONE, POP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A damped left-right wobble, each swing shorter than the last so it reads as
## settling rather than stopping dead.
func _shake(offset: float, step_sec: float, swings: int) -> void:
	var rest := position
	var tween := create_tween()
	var swing := offset
	for i in swings:
		var dir := 1.0 if i % 2 == 0 else -1.0
		tween.tween_property(self, "position", rest + Vector3(swing * dir, 0.0, 0.0), step_sec) \
			.set_trans(Tween.TRANS_SINE)
		swing *= SHAKE_DECAY
	tween.tween_property(self, "position", rest, step_sec).set_trans(Tween.TRANS_SINE)

func _ratio_text(current: float, max_amount: float) -> String:
	return "%d/%d" % [roundi(current), roundi(max_amount)]

func _bake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
