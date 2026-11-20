extends RefCounted
## Red terracotta tile inventory icon and matching 32 px roof surface.

const TILE_ICON := preload("res://assets/ui-inventory/terracotta-roof-tile.png")
const ROOF_SURFACE := preload("res://assets/ui-life/terracotta-roof-surface.png")
# The dimensions also define the roof's fade and occlusion bounds.
const ROOF_OFFSET := Vector2(0, -8)
const ROOF_SIZE := Vector2(32, 32)

static func draw_roof(canvas: CanvasItem, at: Vector2, alpha := 1.0) -> void:
	canvas.draw_texture(ROOF_SURFACE, at + ROOF_OFFSET, Color(1, 1, 1, alpha))

static func tile_icon() -> Texture2D:
	return TILE_ICON
