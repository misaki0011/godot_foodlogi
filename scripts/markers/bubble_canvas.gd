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

var _icon_color: Color = Color.WHITE
var _amount_text: String = "0"

func set_content(icon_color: Color, amount_text: String) -> void:
	_icon_color = icon_color
	_amount_text = amount_text
	queue_redraw()

func _draw() -> void:
	var bubble_rect := Rect2(Vector2(3, 3), Vector2(size.x - 6, size.y - TAIL_HEIGHT - 6))

	var shadow_box := StyleBoxFlat.new()
	shadow_box.bg_color = Color(0, 0, 0, 0.18)
	shadow_box.set_corner_radius_all(int(bubble_rect.size.y * 0.35))
	draw_style_box(shadow_box, Rect2(bubble_rect.position + Vector2(0, 2), bubble_rect.size))

	var box := StyleBoxFlat.new()
	box.bg_color = BUBBLE_COLOR
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
	draw_colored_polygon(tail, BUBBLE_COLOR)
	draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), BORDER_COLOR, 2.0, true)

	var icon_r := bubble_rect.size.y * 0.30
	var icon_center := Vector2(bubble_rect.position.x + icon_r + 10, bubble_rect.position.y + bubble_rect.size.y * 0.5)
	draw_circle(icon_center, icon_r, _icon_color)
	draw_arc(icon_center, icon_r, 0, TAU, 32, BORDER_COLOR, 2.0, true)

	var font := ThemeDB.fallback_font
	var font_size := int(bubble_rect.size.y * 0.5)
	var text_x := icon_center.x + icon_r + 10
	var text_width := bubble_rect.end.x - text_x - 8
	var text_pos := Vector2(text_x, bubble_rect.position.y + bubble_rect.size.y * 0.5 + font_size * 0.35)
	draw_string(font, text_pos, _amount_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size, TEXT_COLOR)
