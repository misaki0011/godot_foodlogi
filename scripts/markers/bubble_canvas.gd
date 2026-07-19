class_name BubbleCanvas
extends Control

## Draws a rounded speech bubble (fill, border, drop shadow, tail, a
## food-colored icon dot, and an amount) into a Control that a SubViewport
## bakes to a texture for FoodBubbleMarker. Composing the whole bubble as
## one flat 2D drawing -- instead of a separate 3D box + icon mesh + Label3D
## stacked in front of each other -- sidesteps Godot's per-object
## transparency sort placing the number behind the bubble, and reads
## crisper than the old low-poly primitives.

const BUBBLE_COLOR := Color(0.97, 0.94, 0.87, 0.97)
const BORDER_COLOR := Color(0.15, 0.12, 0.08, 0.65)
const TEXT_COLOR := Color(0.14, 0.11, 0.08)
const TAIL_HEIGHT := 14.0

## A source that has given up its whole daily produce, or any other
## "nothing more to see here" state, mutes the bubble to this palette
## instead of the normal food-colored one.
const GRAYED_BUBBLE_COLOR := Color(0.82, 0.82, 0.79, 0.9)
const GRAYED_ICON_COLOR := Color(0.58, 0.58, 0.55)
const GRAYED_TEXT_COLOR := Color(0.42, 0.42, 0.4)

const CHECK_COLOR := Color(0.28, 0.5, 0.26)
const GRAYED_CHECK_COLOR := Color(0.5, 0.5, 0.48)
const GRAYED_CHECKBOX_FILL := Color(0.88, 0.88, 0.86)

var _icon_color: Color = Color.WHITE
var _amount_text: String = "0"
var _grayed_out: bool = false
var _show_checkbox: bool = false
var _checked: bool = false

## show_checkbox/checked add a checkbox before the food icon (settlement
## bubbles only, main.gd): checked once a food's delivered amount meets
## its requested amount, empty otherwise.
func set_content(icon_color: Color, amount_text: String, grayed_out: bool = false, show_checkbox: bool = false, checked: bool = false) -> void:
	_icon_color = icon_color
	_amount_text = amount_text
	_grayed_out = grayed_out
	_show_checkbox = show_checkbox
	_checked = checked
	queue_redraw()

func _draw() -> void:
	var bubble_color := GRAYED_BUBBLE_COLOR if _grayed_out else BUBBLE_COLOR
	var icon_color := GRAYED_ICON_COLOR if _grayed_out else _icon_color
	var text_color := GRAYED_TEXT_COLOR if _grayed_out else TEXT_COLOR

	var bubble_rect := Rect2(Vector2(3, 3), Vector2(size.x - 6, size.y - TAIL_HEIGHT - 6))

	var shadow_box := StyleBoxFlat.new()
	shadow_box.bg_color = Color(0, 0, 0, 0.18)
	shadow_box.set_corner_radius_all(int(bubble_rect.size.y * 0.35))
	draw_style_box(shadow_box, Rect2(bubble_rect.position + Vector2(0, 2), bubble_rect.size))

	var box := StyleBoxFlat.new()
	box.bg_color = bubble_color
	box.set_corner_radius_all(int(bubble_rect.size.y * 0.35))
	box.border_color = BORDER_COLOR
	box.set_border_width_all(2)
	draw_style_box(box, bubble_rect)

	var tail_cx := bubble_rect.position.x + bubble_rect.size.x * 0.5
	var tail := PackedVector2Array([
		Vector2(tail_cx - 8, bubble_rect.end.y - 2),
		Vector2(tail_cx + 8, bubble_rect.end.y - 2),
		Vector2(tail_cx, bubble_rect.end.y + TAIL_HEIGHT - 2),
	])
	draw_colored_polygon(tail, bubble_color)
	draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), BORDER_COLOR, 2.0, true)

	var content_x := bubble_rect.position.x + 10
	if _show_checkbox:
		var box_side := bubble_rect.size.y * 0.34
		var box_rect := Rect2(Vector2(content_x, bubble_rect.position.y + (bubble_rect.size.y - box_side) * 0.5), Vector2(box_side, box_side))
		draw_rect(box_rect, GRAYED_CHECKBOX_FILL if _grayed_out else Color.WHITE, true)
		draw_rect(box_rect, BORDER_COLOR, false, 2.0)
		if _checked:
			var tick := PackedVector2Array([
				box_rect.position + Vector2(box_side * 0.18, box_side * 0.55),
				box_rect.position + Vector2(box_side * 0.42, box_side * 0.8),
				box_rect.position + Vector2(box_side * 0.85, box_side * 0.2),
			])
			draw_polyline(tick, GRAYED_CHECK_COLOR if _grayed_out else CHECK_COLOR, 3.0, true)
		content_x = box_rect.end.x + 8

	var icon_r := bubble_rect.size.y * 0.30
	var icon_center := Vector2(content_x + icon_r, bubble_rect.position.y + bubble_rect.size.y * 0.5)
	draw_circle(icon_center, icon_r, icon_color)
	draw_arc(icon_center, icon_r, 0, TAU, 32, BORDER_COLOR, 2.0, true)

	var font := ThemeDB.fallback_font
	var font_size := int(bubble_rect.size.y * 0.42)
	var text_x := icon_center.x + icon_r + 10
	var text_width := bubble_rect.end.x - text_x - 8
	var text_pos := Vector2(text_x, bubble_rect.position.y + bubble_rect.size.y * 0.5 + font_size * 0.35)
	draw_string(font, text_pos, _amount_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size, text_color)
