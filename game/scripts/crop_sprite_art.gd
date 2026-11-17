extends RefCounted

const World = preload("res://scripts/world.gd")
const BakeryArt = preload("res://scripts/bakery_art.gd")
const FlowerArt = preload("res://scripts/flower_art.gd")
const ATLAS_PATH := "res://assets/life-art/crops.png"
const CELL := Vector2i(32, 32)
const FOOT := Vector2(16, 29)
const ROWS := ["radish", "lettuce", "wheat", "carrot", "potato", "tomato"]
const KITCHEN_GARDEN_PATH := "res://assets/life-art/crops-kitchen-garden.png"
const KITCHEN_GARDEN_ROWS := ["cauliflower","sweet_corn","strawberry","cucumber"]
const REGIONAL_PATH := "res://assets/life-art/crops-regional.png"
const REGIONAL_ROWS := ["rice","mist_tea","star_mushroom","sweet_potato"]
const HARVEST_PATH := "res://assets/life-art/crops-harvest.png"
const HARVEST_ROWS := ["cabbage","sugar_beet","eggplant","ginger","watermelon","cotton"]
const HARVESTABLE := 3

var atlas: Texture2D
var kitchen_garden:Texture2D
var regional:Texture2D
var harvest:Texture2D

func setup() -> bool:
	kitchen_garden=load(KITCHEN_GARDEN_PATH)
	regional=load(REGIONAL_PATH)
	harvest=load(HARVEST_PATH)
	if ResourceLoader.exists(ATLAS_PATH):
		atlas = load(ATLAS_PATH)
	if atlas != null and atlas.get_size() == Vector2(CELL.x * 4, CELL.y * ROWS.size()):
		return true
	atlas = null
	return false

static func stage_for(crop: Dictionary) -> int:
	var kind: String = crop.get("kind", "")
	if not World.CROPS.has(kind):
		return -1
	var growth := float(crop.get("growth", 0.0))
	var duration := float(World.CROPS[kind].time)
	if growth >= duration:
		return HARVESTABLE
	if growth >= duration * 0.65:
		return 2
	if growth >= duration * 0.25:
		return 1
	return 0

## 休眠中的作物（World.plot_dormant）：整株染成偏冷的灰藍，右上角加兩個小「z」。
## 只是呈現，成長階段仍照 growth 畫（休眠保留成長進度）。
const DORMANT_TINT := Color(0.70, 0.76, 0.88)
const DORMANT_MARK := Color("e4eefc")
const DORMANT_MARK_SHADE := Color("4a5a78")
## 兩個「z」的像素（相對於格子左上角）：大的 5×5 在 (22,2)，小的 3×3 在 (18,8)。
const DORMANT_PIXELS := [
	Vector2i(22,2),Vector2i(23,2),Vector2i(24,2),Vector2i(25,2),Vector2i(26,2),
	Vector2i(25,3),Vector2i(24,4),Vector2i(23,5),
	Vector2i(22,6),Vector2i(23,6),Vector2i(24,6),Vector2i(25,6),Vector2i(26,6),
	Vector2i(17,8),Vector2i(18,8),Vector2i(19,8),Vector2i(18,9),Vector2i(17,10),Vector2i(18,10),Vector2i(19,10),
]

static func draw_dormant_mark(canvas: CanvasItem, at: Vector2) -> void:
	for pixel: Vector2i in DORMANT_PIXELS:
		canvas.draw_rect(Rect2(at + Vector2(pixel) + Vector2(1, 1), Vector2.ONE), DORMANT_MARK_SHADE)
	for pixel: Vector2i in DORMANT_PIXELS:
		canvas.draw_rect(Rect2(at + Vector2(pixel), Vector2.ONE), DORMANT_MARK)

static func breeze_offset(t: float, tile: Vector2i) -> int:
	return roundi(sin(t * 2.1 + tile.x * 0.63 + tile.y * 0.37))

func draw_crop(canvas: Node2D, at: Vector2, crop: Dictionary, dormant := false, sway := 0) -> void:
	var stage := stage_for(crop)
	if stage < 0:
		return
	if stage == HARVESTABLE:
		dormant = false
	var tint := DORMANT_TINT if dormant else Color.WHITE
	_draw_plant(canvas, at, crop, stage, tint, sway if stage > 0 and not dormant else 0)
	if dormant:
		draw_dormant_mark(canvas, at)

func _draw_plant(canvas: Node2D, at: Vector2, crop: Dictionary, stage: int, tint: Color, sway: int) -> void:
	if crop.kind=="pumpkin":
		# Independent bakery atlas; does not depend on the legacy crops.png loading.
		if not BakeryArt.draw_crop(canvas, at, stage, tint):
			return
	elif FlowerArt.has_crop(crop.kind):
		# Tianwei flowers use their own growth sheet; a missing texture draws nothing
		# (never another crop's art).
		var texture := FlowerArt.crop_texture(crop.kind, stage)
		if texture == null:
			return
		canvas.draw_texture_rect(texture, Rect2(at, Vector2(CELL)), false, tint)
	else:
		var row:=KITCHEN_GARDEN_ROWS.find(crop.kind)
		var sheet:=kitchen_garden if row>=0 else atlas
		if row<0:
			row=REGIONAL_ROWS.find(crop.kind)
			if row>=0:
				sheet=regional
		if row<0:
			row=HARVEST_ROWS.find(crop.kind)
			if row>=0:
				sheet=harvest
		if sheet==null:
			return
		if row<0:row=ROWS.find(crop.kind)
		if row < 0:
			return
		var source := Rect2(Vector2(stage * CELL.x, row * CELL.y), Vector2(CELL))
		var sways:bool = sheet == harvest or sheet == kitchen_garden or (sheet == regional and crop.kind != "star_mushroom")
		var lean := Vector2(sway, 0) if sways else Vector2.ZERO
		canvas.draw_texture_rect_region(sheet, Rect2(at + lean, Vector2(CELL)), source, tint)
	if stage == HARVESTABLE:
		var hint := Color("ffe7a0")
		canvas.draw_rect(Rect2(at + Vector2(26, 2), Vector2(2, 6)), hint)
		canvas.draw_rect(Rect2(at + Vector2(24, 4), Vector2(6, 2)), hint)
