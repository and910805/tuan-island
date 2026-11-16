extends RefCounted

const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const ICON_ATLAS=preload("res://assets/ui-life/icons.png")
const LETTER:=Rect2(128,64,32,32)

static func draw_landmark(canvas:CanvasItem,at:Vector2) -> void:
	if Furniture.draw_sprite(canvas,at,"chest"):
		canvas.draw_texture_rect_region(ICON_ATLAS,Rect2(at+Vector2(10,15),Vector2(12,12)),LETTER)
