extends RefCounted

# N09-4 Xiaoli shop - procedural pixel art, display only.
#   static scale_texture() -> Texture2D   32x32 brass counter scale, transparent
#   static sign_texture()  -> Texture2D   96x24 wood sign, transparent corners
# Both are generated once and cached. Use nearest-neighbour filtering and an
# integer scale. The sign's interior (4px border all round) is a flat plank
# surface with only faint grain, so a Label can sit on top of it.

const SCALE_SIZE := Vector2i(32, 32)
const SIGN_SIZE := Vector2i(96, 24)
const SIGN_BORDER := 5   # pixels of frame on every side; interior starts here

# Shared game palette (same wood and brass tones as the other pixel art).
const C_OUTLINE := Color("3a2718")
const C_PLANK := Color("6b4a30")
const C_PLANK_DARK := Color("4a3220")
const C_PLANK_LIGHT := Color("82603f")
const C_NAIL := Color("2a1c12")
const C_BRASS := Color("c9a66b")
const C_BRASS_DARK := Color("7a5f35")
const C_BRASS_LIGHT := Color("ecd7a0")
const C_PAPER := Color("d9c9a0")

static var _scale_tex: Texture2D = null
static var _sign_tex: Texture2D = null


static func scale_texture() -> Texture2D:
	if _scale_tex == null:
		_scale_tex = ImageTexture.create_from_image(_build_scale())
	return _scale_tex


static func sign_texture() -> Texture2D:
	if _sign_tex == null:
		_sign_tex = ImageTexture.create_from_image(_build_sign())
	return _sign_tex


# ---------------------------------------------------------------- scale

static func _build_scale() -> Image:
	var img := _blank(SCALE_SIZE)
	var o := C_OUTLINE

	# Base: stepped foot with outline, lit on the left, shaded on the right.
	_rect(img, 7, 28, 18, 3, o)
	_rect(img, 8, 28, 16, 2, C_BRASS)
	_rect(img, 8, 29, 16, 1, C_BRASS_DARK)
	_rect(img, 8, 28, 16, 1, C_BRASS_LIGHT)
	_rect(img, 10, 26, 12, 2, o)
	_rect(img, 11, 26, 10, 1, C_BRASS)
	_rect(img, 11, 27, 10, 1, C_BRASS_DARK)

	# Column: outlined, light stripe on the left, dark on the right.
	_rect(img, 14, 9, 4, 17, o)
	_rect(img, 15, 9, 2, 17, C_BRASS)
	_rect(img, 15, 9, 1, 17, C_BRASS_LIGHT)
	_rect(img, 16, 10, 1, 16, C_BRASS_DARK)
	# Collar rings on the column.
	_rect(img, 13, 15, 6, 1, o)
	_rect(img, 14, 15, 4, 1, C_BRASS_LIGHT)
	_rect(img, 13, 22, 6, 1, o)
	_rect(img, 14, 22, 4, 1, C_BRASS)

	# Finial ball on top and pivot cap.
	_rect(img, 14, 4, 4, 4, o)
	_rect(img, 15, 5, 2, 2, C_BRASS)
	_paint_pixel(img, 15, 5, C_BRASS_LIGHT)
	_paint_pixel(img, 16, 6, C_BRASS_DARK)
	_rect(img, 15, 8, 2, 1, o)

	# Beam: outlined bar across the top of the column with round end knobs.
	_rect(img, 3, 9, 26, 3, o)
	_rect(img, 4, 10, 24, 1, C_BRASS)
	_rect(img, 4, 10, 12, 1, C_BRASS_LIGHT)
	_rect(img, 16, 10, 12, 1, C_BRASS)
	_paint_pixel(img, 2, 10, o)
	_paint_pixel(img, 29, 10, o)
	_paint_pixel(img, 3, 10, C_BRASS_LIGHT)
	_paint_pixel(img, 28, 10, C_BRASS_DARK)
	# Pointer needle hanging under the pivot.
	_rect(img, 15, 12, 2, 2, o)
	_paint_pixel(img, 15, 12, C_BRASS_LIGHT)
	_paint_pixel(img, 16, 12, C_BRASS_DARK)

	# Pans hang from the beam ends on chains; the left pan carries a weight.
	_draw_pan(img, 5)
	_draw_pan(img, 26)
	# Weight block on the left pan.
	_rect(img, 3, 15, 5, 4, o)
	_rect(img, 4, 16, 3, 2, C_PLANK_DARK)
	_paint_pixel(img, 4, 16, C_PLANK_LIGHT)
	# Small brass goods (coins) on the right pan.
	_rect(img, 23, 17, 3, 2, o)
	_paint_pixel(img, 24, 17, C_BRASS_LIGHT)
	_paint_pixel(img, 24, 18, C_BRASS)
	_rect(img, 26, 18, 3, 1, o)
	_paint_pixel(img, 27, 18, C_BRASS_LIGHT)
	return img


# Chains run from the beam end (cx, 12) to the pan rim; pan is 10px wide.
static func _draw_pan(img: Image, cx: int) -> void:
	var o := C_OUTLINE
	var left := cx - 4
	var right := cx + 5
	_line(img, cx, 12, left, 20, C_BRASS_DARK)
	_line(img, cx, 12, right, 20, C_BRASS_DARK)
	_line(img, cx, 12, cx, 20, C_BRASS_LIGHT)
	# Bowl: rim row, then two narrowing rows, all outlined.
	_rect(img, left - 1, 20, 12, 1, o)
	_rect(img, left, 20, 10, 1, C_BRASS_LIGHT)
	_rect(img, left, 21, 10, 1, C_BRASS)
	_rect(img, left + 1, 22, 8, 1, C_BRASS_DARK)
	_rect(img, left, 21, 1, 1, o)
	_rect(img, right - 0, 21, 1, 1, o)
	_rect(img, left + 1, 23, 8, 1, o)
	_rect(img, left, 22, 1, 1, o)
	_rect(img, right, 22, 1, 1, o)


# ---------------------------------------------------------------- sign

static func _build_sign() -> Image:
	var img := _blank(SIGN_SIZE)
	var w := SIGN_SIZE.x
	var h := SIGN_SIZE.y
	for y in h:
		for x in w:
			var d := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			# Cut the four corner pixels for a softly rounded silhouette.
			if d == 0 and (x == 0 or x == w - 1) and (y == 0 or y == h - 1):
				continue
			if d == 0:
				_paint_pixel(img, x, y, C_OUTLINE)
			elif d == 1:
				_paint_pixel(img, x, y, C_PLANK_LIGHT)
			elif d <= 3:
				_paint_pixel(img, x, y, _frame_color(x, y, w, h, d))
			elif d == 4:
				_paint_pixel(img, x, y, C_PLANK_DARK)   # inner shadow edge
			else:
				_paint_pixel(img, x, y, _interior_color(x, y))

	# Nails in the four frame corners.
	for p in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, h - 4), Vector2i(w - 4, h - 4)]:
		_paint_pixel(img, p.x, p.y, C_NAIL)
		_paint_pixel(img, p.x - 1, p.y - 1, C_PLANK_LIGHT)

	# Brass corner caps and mid-top hanging ring for shop-sign character.
	for p in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		_paint_pixel(img, p.x, p.y, C_BRASS)
	_paint_pixel(img, 1, 1, C_BRASS_LIGHT)
	_rect(img, w / 2 - 1, 2, 3, 1, C_BRASS)
	_paint_pixel(img, w / 2, 3, C_BRASS_DARK)
	_rect(img, w / 2 - 1, h - 4, 3, 1, C_BRASS)
	_paint_pixel(img, w / 2, h - 3, C_BRASS_DARK)
	return img


# Frame planks with short dark grain ticks along the run of the wood.
static func _frame_color(x: int, y: int, w: int, h: int, d: int) -> Color:
	var horizontal := y == d or y == h - 1 - d
	var run := x if horizontal else y
	var base := C_PLANK
	if d == 3:
		base = C_PLANK.lerp(C_PLANK_DARK, 0.35)
	if (run * 5 + d * 3) % 13 == 0:
		return C_PLANK_DARK
	return base


# Flat plank surface, only very faint grain so label text stays readable.
static func _interior_color(x: int, y: int) -> Color:
	if y % 6 == 3 and (x * 7 + y * 3) % 11 < 4:
		return C_PLANK.lerp(C_PLANK_LIGHT, 0.2)
	return C_PLANK


# ---------------------------------------------------------------- helpers

static func _blank(size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _paint_pixel(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in h:
		for xx in w:
			_paint_pixel(img, x + xx, y + yy, c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		_paint_pixel(img, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
