class_name BubbleCanvas
extends Control

## Draws a rounded speech bubble (fill, border, drop shadow, tail, a
## food-colored icon dot, and an amount/freshness readout) into a Control
## that a SubViewport bakes to a texture for FoodBubbleMarker. Composing
## the whole bubble as one flat 2D drawing -- instead of a separate 3D
## box + icon mesh + Label3D stacked in front of each other -- sidesteps
## Godot's per-object transparency sort placing the number behind the
## bubble, and reads crisper than the old low-poly primitives.

const BUBBLE_COLOR := Color(0.97, 0.94, 0.87, 0.97)
const BORDER_COLOR := Color(0.15, 0.12, 0.08, 0.65)
const TEXT_COLOR := Color(0.14, 0.11, 0.08)
const TAIL_HEIGHT := 14.0

## A source that has given up its whole daily produce mutes the bubble to
## this palette instead of the normal food-colored one.
const MUTED_BUBBLE_COLOR := Color(0.82, 0.82, 0.79, 0.9)
const MUTED_ICON_COLOR := Color(0.58, 0.58, 0.55)
const MUTED_TEXT_COLOR := Color(0.42, 0.42, 0.4)

## Pastel, not fully saturated, so the same dark TEXT_COLOR stays legible
## on every status without a second text-color table per status.
const RED_COLOR := Color(0.93, 0.72, 0.68, 0.97)
const AMBER_COLOR := Color(0.96, 0.82, 0.55, 0.97)
const GREEN_COLOR := Color(0.74, 0.88, 0.72, 0.97)

## _draw() shrinks the font to fit longer settlement text (amount +
## freshness) rather than letting it overflow the bubble; this is the
## floor so it never shrinks to the point of being unreadable.
const MIN_FONT_SIZE := 14

var _icon_color: Color = Color.WHITE
var _amount_text: String = "0"
var _status: FoodBubbleMarker.Status = FoodBubbleMarker.Status.DEFAULT

func set_content(icon_color: Color, amount_text: String, status: FoodBubbleMarker.Status = FoodBubbleMarker.Status.DEFAULT) -> void:
	_icon_color = icon_color
	_amount_text = amount_text
	_status = status
	queue_redraw()

func _draw() -> void:
	var bubble_color := BUBBLE_COLOR
	var icon_color := _icon_color
	var text_color := TEXT_COLOR
	match _status:
		FoodBubbleMarker.Status.MUTED:
			bubble_color = MUTED_BUBBLE_COLOR
			icon_color = MUTED_ICON_COLOR
			text_color = MUTED_TEXT_COLOR
		FoodBubbleMarker.Status.RED:
			bubble_color = RED_COLOR
		FoodBubbleMarker.Status.AMBER:
			bubble_color = AMBER_COLOR
		FoodBubbleMarker.Status.GREEN:
			bubble_color = GREEN_COLOR

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

	var icon_r := bubble_rect.size.y * 0.30
	var icon_center := Vector2(bubble_rect.position.x + icon_r + 10, bubble_rect.position.y + bubble_rect.size.y * 0.5)
	draw_circle(icon_center, icon_r, icon_color)
	draw_arc(icon_center, icon_r, 0, TAU, 32, BORDER_COLOR, 2.0, true)

	var font := ThemeDB.fallback_font
	var text_x := icon_center.x + icon_r + 10
	var text_width := bubble_rect.end.x - text_x - 8
	var font_size := int(bubble_rect.size.y * 0.42)
	while font_size > MIN_FONT_SIZE and font.get_string_size(_amount_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width:
		font_size -= 1
	var text_pos := Vector2(text_x, bubble_rect.position.y + bubble_rect.size.y * 0.5 + font_size * 0.35)
	draw_string(font, text_pos, _amount_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size, text_color)
