@static_unload
extends Control
## N07-1 field-notebook specimen plate: one growing plant in soil on warm parchment.
## Pure presentation. Call configure(kind, phase) BEFORE add_child (re-calling later is safe).
##   kind  : any World.CROPS id (bakery pumpkin, flowers, kitchen garden, regional, harvest
##           families all go through crop_sprite_art.gd); "" leaves the plate empty.
##   phase : "early" (growing stage 1) or "mature" (harvestable stage 3). Anything else = early.
## No text, no input, no state, no animation (stable still).

const CropArt := preload("res://scripts/crop_sprite_art.gd")
const World := preload("res://scripts/world.gd")

const MIN_SIZE := Vector2(200, 144)
const PARCHMENT := Color("efdcaa")
const PARCHMENT_LIGHT := Color("f6e8c0")
const PARCHMENT_SHADE := Color("d9c08a")
const INK := Color("8a6a3c")
const INK_SOFT := Color("c9ad77")
const SOIL := Color("6b4a2e")
const SOIL_DARK := Color("4f3420")
const SOIL_LIGHT := Color("8a6240")

## Draws the real crop sprite. crop_sprite_art.draw_crop needs a Node2D canvas.
class PlantCanvas extends Node2D:
	var art = null
	var crop: Dictionary = {}

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		if art != null and not crop.is_empty():
			art.draw_crop(self, Vector2.ZERO, crop, false, 0)

var _kind := ""
var _phase := "early"
static var _art: CropArt
var _canvas: PlantCanvas = null
var _sprite_ok := false

func configure(kind: String, phase: String) -> void:
	_kind = kind.strip_edges()
	_phase = "mature" if phase.strip_edges().to_lower() == "mature" else "early"
	_refresh()

func _init() -> void:
	custom_minimum_size = MIN_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _ready() -> void:
	_canvas = PlantCanvas.new()
	_canvas.name = "Plant"
	add_child(_canvas)
	resized.connect(_layout)
	_refresh()

func _refresh() -> void:
	_sprite_ok = false
	var crop := {}
	if _kind != "" and World.CROPS.has(_kind):
		if _art == null:
			_art = CropArt.new()
			_art.setup()
		var duration := float(World.CROPS[_kind].time)
		crop = {"kind": _kind, "growth": duration if _phase == "mature" else duration * 0.3}
		_sprite_ok = true
	if _canvas != null:
		_canvas.art = _art if _sprite_ok else null
		_canvas.crop = crop
		_canvas.visible = _sprite_ok
		_canvas.queue_redraw()
	_layout()
	queue_redraw()

func _geometry() -> Dictionary:
	var sz := Vector2(maxf(size.x, MIN_SIZE.x), maxf(size.y, MIN_SIZE.y))
	var soil_top := roundf(sz.y * 0.72)
	var s := clampi(floori((soil_top - 8.0) / 29.0), 1, 8)
	var foot := Vector2(roundf(sz.x * 0.5), soil_top + 2.0 * s)
	return {"size": sz, "soil_top": soil_top, "scale": s, "foot": foot}

func _layout() -> void:
	if _canvas == null:
		return
	var g := _geometry()
	var s: int = g.scale
	var foot: Vector2 = g.foot
	_canvas.scale = Vector2(s, s)
	_canvas.position = (foot - CropArt.FOOT * float(s)).round()

func _draw() -> void:
	var g := _geometry()
	var sz: Vector2 = g.size
	var soil_top: float = g.soil_top
	# Parchment plate with a pixel border and corner marks (no text).
	draw_rect(Rect2(Vector2.ZERO, sz), PARCHMENT)
	draw_rect(Rect2(Vector2(4, 4), sz - Vector2(8, 8)), PARCHMENT_LIGHT)
	draw_rect(Rect2(Vector2(4, 4), sz - Vector2(8, 8)), INK_SOFT, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), INK, false, 2.0)
	var y := 16.0
	while y < soil_top - 6.0:
		draw_rect(Rect2(Vector2(10, y), Vector2(sz.x - 20, 1)), PARCHMENT_SHADE)
		y += 12.0
	for corner: Vector2 in [Vector2(8, 8), Vector2(sz.x - 14, 8), Vector2(8, sz.y - 14), Vector2(sz.x - 14, sz.y - 14)]:
		draw_rect(Rect2(corner, Vector2(6, 2)), INK)
		var vertical_x := 0.0 if corner.x < sz.x * 0.5 else 4.0
		draw_rect(Rect2(corner + Vector2(vertical_x, 0), Vector2(2, 6)), INK)
	# Soil bed: deterministic speckle, no randomness.
	var bed := Rect2(Vector2(12, soil_top), Vector2(sz.x - 24, sz.y - soil_top - 10))
	draw_rect(bed, SOIL)
	draw_rect(Rect2(bed.position, Vector2(bed.size.x, 3)), SOIL_LIGHT)
	draw_rect(Rect2(bed.position + Vector2(0, bed.size.y - 3), Vector2(bed.size.x, 3)), SOIL_DARK)
	var i := 0
	var x := bed.position.x + 5.0
	while x < bed.end.x - 4.0:
		var yy := bed.position.y + 6.0 + float((i * 7) % 11)
		if yy < bed.end.y - 5.0:
			draw_rect(Rect2(Vector2(x, yy), Vector2(3, 2)), SOIL_DARK if i % 2 == 0 else SOIL_LIGHT)
		x += 9.0
		i += 1
