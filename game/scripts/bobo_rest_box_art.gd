extends Control
## T066 N03-3 波波休息站便攜箱圖樣 — blueprint illustration.
##
## Depicts the shipped 便攜補給箱 (World.BUILD "supply_box"), drawn with the same
## texture the world uses (res://assets/bakery/supply-box.png, preloaded, not copied).
## Everything else is drawn with rects, lines, and text. The callouts label
## the illustrated parts and the two rules for using the placed box.
##
## Render semantics: a 250x120 logical canvas drawn at integer scale S =
## max(1, floor(width/250)); the canvas is centred at integer offsets, clipped if the
## Control is narrower than 250. The sprite is drawn at 3*S (integer) with nearest
## filtering. custom_minimum_size follows the width.
## Usage: BoboRestBoxArt.make() -> Control (name "BoboRestBoxArt").

const BOX_TEXTURE := preload("res://assets/bakery/supply-box.png")
const LOGICAL := Vector2i(250, 120)
const SPRITE_K := 3
const BG := Color(0.06, 0.17, 0.16)
const GRID := Color(0.30, 0.62, 0.52, 0.16)
const GRID_MAJOR := Color(0.40, 0.78, 0.64, 0.30)
const LINE := Color(0.66, 0.92, 0.80)
const TEXT := Color(0.86, 0.98, 0.92)
const WOOD := Color(0.78, 0.55, 0.30)
const WOOD_DARK := Color(0.52, 0.34, 0.18)
const FRAME := Color(0.40, 0.78, 0.64)

var _scale := 1

static func make() -> Control:
	var art := new()
	art.name = "BoboRestBoxArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = true
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.custom_minimum_size = Vector2(LOGICAL.x, LOGICAL.y)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return art

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var s := maxi(1, int(floor(size.x / LOGICAL.x)))
		_scale = s
		var want := float(LOGICAL.y * s)
		if not is_equal_approx(custom_minimum_size.y, want):
			custom_minimum_size.y = want
		queue_redraw()

func _draw() -> void:
	var s := _scale
	var origin := Vector2i(maxi(0, (int(size.x) - LOGICAL.x * s) / 2), maxi(0, (int(size.y) - LOGICAL.y * s) / 2))
	_r(origin, s, 0, 0, LOGICAL.x, LOGICAL.y, BG)
	for x in range(0, LOGICAL.x + 1, 10):
		_r(origin, s, x, 0, 1, LOGICAL.y, GRID_MAJOR if x % 50 == 0 else GRID)
	for y in range(0, LOGICAL.y + 1, 10):
		_r(origin, s, 0, y, LOGICAL.x, 1, GRID_MAJOR if y % 50 == 0 else GRID)
	_frame(origin, s)

	# Sprite: integer scale, centred, nearest filtering.
	var by := 17
	var fx := (LOGICAL.x - 32 * SPRITE_K) / 2  # 77
	var rect := Rect2(origin.x + fx * s, origin.y + by * s, 32 * SPRITE_K * s, 32 * SPRITE_K * s)
	# Warm wood corner brackets framing the box.
	_r(origin, s, fx - 3, by - 2, 8, 2, WOOD)
	_r(origin, s, fx - 3, by - 2, 2, 8, WOOD)
	_r(origin, s, fx + 91, by - 2, 8, 2, WOOD)
	_r(origin, s, fx + 97, by - 2, 2, 8, WOOD)
	_r(origin, s, fx - 3, by + 94, 8, 2, WOOD_DARK)
	_r(origin, s, fx - 3, by + 88, 2, 8, WOOD_DARK)
	_r(origin, s, fx + 91, by + 94, 8, 2, WOOD_DARK)
	_r(origin, s, fx + 97, by + 88, 2, 8, WOOD_DARK)
	draw_texture_rect(BOX_TEXTURE, rect, false)

	# Callouts (leader line + end dot + label). Sprite rows: lid ~8..14, front ~15..25 of 32.
	var lid_y := by + 33
	var front_y := by + 60
	var low_y := by + 70
	_callout(origin, s, fx + 14, lid_y, 36, lid_y, "箱蓋", false)
	_callout(origin, s, fx + 14, front_y, 36, front_y, "前板", false)
	_callout(origin, s, fx + 82, front_y, 178, front_y - 12, "僅本人存取", true)
	_callout(origin, s, fx + 82, low_y, 178, low_y + 4, "清空可拆回", true)

	_text(origin, s, 8, 16, "提燈休息站 · 波波", TEXT, 12)

func _frame(o: Vector2i, s: int) -> void:
	_r(o, s, 0, 0, LOGICAL.x, 1, FRAME)
	_r(o, s, 0, LOGICAL.y - 1, LOGICAL.x, 1, FRAME)
	_r(o, s, 0, 0, 1, LOGICAL.y, FRAME)
	_r(o, s, LOGICAL.x - 1, 0, 1, LOGICAL.y, FRAME)

func _callout(o: Vector2i, s: int, x0: int, y0: int, x1: int, y1: int, label: String, right: bool) -> void:
	# Stepped (pixel) leader: horizontal run, then vertical run, then label.
	var xa := mini(x0, x1)
	var xb := maxi(x0, x1)
	_r(o, s, xa, y0, xb - xa + 1, 1, LINE)
	var ya := mini(y0, y1)
	_r(o, s, x1, ya, 1, absi(y1 - y0) + 1, LINE)
	_r(o, s, x0 - 1, y0 - 1, 3, 3, LINE)
	if right:
		_text(o, s, x1 + 3, y1 + 4, label, TEXT, 12)
	else:
		_text(o, s, 6, y1 + 4, label, TEXT, 12)

func _r(o: Vector2i, s: int, x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(o.x + x * s, o.y + y * s, w * s, h * s), c)

func _text(o: Vector2i, s: int, x: int, baseline: int, text: String, c: Color, px: int) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	draw_string(font, Vector2(o.x + x * s, o.y + baseline * s), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px * s, c)
