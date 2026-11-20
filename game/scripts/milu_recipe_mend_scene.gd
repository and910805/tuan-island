extends Control
## Milu N02-2 inline animation: three stained recipe fragments slide together,
## a flour puff covers the join, and a restored hand-written page remains.
##
## API:
##   var reduced_motion: bool   # set BEFORE add_child(); true = end pose, no process
##   func replay() -> void      # restart (or re-show end pose when reduced)
##   signal animation_finished  # emitted once per run when the end pose is reached
##   func is_finished() -> bool
##
## Pure _draw() pixel art on a 160x64 logical canvas, integer-scaled (2x at the
## default 320x128 minimum size), centered, clipped to bounds. No text, no assets.

signal animation_finished

const LOGICAL := Vector2i(160, 64)
const PAGE_POS := Vector2i(50, 8)
const PAGE_W := 60
const PAGE_H := 48
const FRAG_W := 20
const NOTCH := [0, 1, 2, 1, 0, 2, 1, 0]

const SLIDE_START := 0.35
const SLIDE_STAGGER := 0.12
const SLIDE_DUR := 0.9
const PUFF_START := 1.45
const PUFF_DUR := 0.7
const RESTORE_AT := 1.55
const END_TIME := 2.3

# Fragment start offsets (relative to final position); all stay inside the canvas.
const START_OFFSETS := [Vector2i(-44, -4), Vector2i(0, 22), Vector2i(46, -6)]

const C_TABLE := Color("5b3d2a")
const C_TABLE_DARK := Color("4a3022")
const C_PAPER := Color("efe0b8")
const C_PAPER_OLD := Color("dcc58f")
const C_EDGE := Color("f7ecd0")
const C_SHADOW := Color(0, 0, 0, 0.28)
const C_STAIN := Color(0.45, 0.27, 0.12, 0.55)
const C_STAIN_RING := Color(0.38, 0.2, 0.1, 0.7)
const C_INK := Color("3a2a4a")
const C_INK_FAINT := Color(0.23, 0.17, 0.29, 0.45)
const C_FLOUR := Color(0.98, 0.96, 0.9)

var reduced_motion: bool = false

var _t: float = 0.0
var _finished: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(320, 128)
	replay()


func replay() -> void:
	_finished = false
	if reduced_motion:
		_t = END_TIME
		_finished = true
		set_process(false)
	else:
		_t = 0.0
		set_process(true)
	queue_redraw()


func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	_t += delta
	if _t >= END_TIME:
		_t = END_TIME
		_finished = true
		set_process(false)
		animation_finished.emit()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_TABLE)
	var s: int = maxi(1, mini(int(size.x) / LOGICAL.x, int(size.y) / LOGICAL.y))
	var origin := Vector2(floorf((size.x - LOGICAL.x * s) * 0.5), floorf((size.y - LOGICAL.y * s) * 0.5))
	draw_set_transform(origin, 0.0, Vector2(s, s))
	# All art stays inside the 160x64 logical canvas; clip_contents bounds the rest.
	_draw_table()
	if _t < RESTORE_AT:
		_draw_fragments()
	else:
		_draw_restored()
	_draw_puff()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func _draw_table() -> void:
	for y in range(0, LOGICAL.y, 16):
		_r(0, y, LOGICAL.x, 1, C_TABLE_DARK)
	# a few wood-grain flecks
	for i in 10:
		_r((i * 37 + 11) % LOGICAL.x, (i * 13 + 5) % LOGICAL.y, 4 + i % 3, 1, C_TABLE_DARK)


func _ease_out(p: float) -> float:
	var q := 1.0 - clampf(p, 0.0, 1.0)
	return 1.0 - q * q * q


func _frag_offset(i: int) -> Vector2i:
	var p := (_t - SLIDE_START - SLIDE_STAGGER * i) / SLIDE_DUR
	var k := 1.0 - _ease_out(p)
	var o: Vector2i = START_OFFSETS[i]
	return Vector2i(roundi(o.x * k), roundi(o.y * k))


func _frag_span(i: int, y: int) -> Vector2i:
	var n: int = NOTCH[y % 8]
	var x0 := 0 if i == 0 else FRAG_W * i + n
	var x1 := FRAG_W * (i + 1) + (n if i < 2 else 0)
	return Vector2i(x0, x1)


func _draw_fragments() -> void:
	for i in 3:
		var off := _frag_offset(i)
		var b := PAGE_POS + off  # page-local (0,0) on canvas
		# shadow
		for y in PAGE_H:
			var sp := _frag_span(i, y)
			_r(b.x + sp.x + 1, b.y + y + 1, sp.y - sp.x, 1, C_SHADOW)
		# paper
		for y in PAGE_H:
			var sp := _frag_span(i, y)
			var col := C_PAPER_OLD if ((y / 6 + i) % 2 == 0) else C_PAPER
			_r(b.x + sp.x, b.y + y, sp.y - sp.x, 1, col)
			if i > 0:
				_r(b.x + sp.x, b.y + y, 1, 1, C_EDGE)
			if i < 2:
				_r(b.x + sp.y - 1, b.y + y, 1, 1, C_EDGE)
		_draw_icon(i, b)
		_draw_faint_lines(i, b)
		_draw_stains(i, b)


func _draw_icon(i: int, b: Vector2i) -> void:
	var cx := FRAG_W * i + 10
	var x := b.x + cx
	var y := b.y + 5
	match i:
		0: # wheat ear
			_r(x, y + 6, 1, 14, Color("7a8a3a"))
			var gold := Color("d9a22e")
			for k in 5:
				_r(x - 2, y + k * 3, 2, 2, gold)
				_r(x + 1, y + k * 3 + 1, 2, 2, gold)
			_r(x - 1, y - 2, 2, 2, gold)
		1: # apple
			var red := Color("c83a3a")
			_r(x - 4, y + 4, 9, 9, red)
			_r(x - 3, y + 3, 7, 1, red)
			_r(x - 3, y + 13, 7, 1, red)
			_r(x - 3, y + 5, 2, 2, Color("f08a7a"))
			_r(x, y, 1, 4, Color("5a3a1a"))
			_r(x + 1, y + 1, 3, 2, Color("4e9a3a"))
		2: # bread loaf
			var crust := Color("b9742f")
			_r(x - 6, y + 7, 13, 8, crust)
			_r(x - 4, y + 5, 9, 2, crust)
			_r(x - 5, y + 15, 11, 1, Color("8a521f"))
			var slit := Color("e6b366")
			_r(x - 3, y + 8, 1, 3, slit)
			_r(x, y + 7, 1, 3, slit)
			_r(x + 3, y + 8, 1, 3, slit)


func _draw_faint_lines(i: int, b: Vector2i) -> void:
	var x := b.x + FRAG_W * i + 4
	for r in 4:
		var y := b.y + 28 + r * 5
		var line_w := 12 - ((r + i) % 3) * 3
		_r(x, y, line_w, 1, C_INK_FAINT)


func _draw_stains(i: int, b: Vector2i) -> void:
	var x := b.x + FRAG_W * i
	match i:
		0:
			_r(x + 3, b.y + 24, 9, 6, C_STAIN)
			_r(x + 2, b.y + 26, 11, 3, C_STAIN)
			_r(x + 4, b.y + 38, 6, 5, C_STAIN)
		1:
			# tea ring
			var rc := C_STAIN_RING
			_r(x + 5, b.y + 30, 8, 1, rc)
			_r(x + 5, b.y + 39, 8, 1, rc)
			_r(x + 4, b.y + 31, 1, 8, rc)
			_r(x + 13, b.y + 31, 1, 8, rc)
			_r(x + 6, b.y + 33, 6, 3, C_STAIN)
		2:
			_r(x + 8, b.y + 22, 8, 7, C_STAIN)
			_r(x + 10, b.y + 29, 4, 3, C_STAIN)
			_r(x + 3, b.y + 40, 7, 4, C_STAIN)


func _draw_restored() -> void:
	var settle := 0
	if _t < PUFF_START + 0.3:
		settle = -1
	var b := PAGE_POS + Vector2i(0, settle)
	_r(b.x + 1, b.y + 1, PAGE_W, PAGE_H, C_SHADOW)
	_r(b.x, b.y, PAGE_W, PAGE_H, C_PAPER)
	_r(b.x, b.y, PAGE_W, 1, C_EDGE)
	_r(b.x, b.y, 1, PAGE_H, C_EDGE)
	_r(b.x + PAGE_W - 1, b.y, 1, PAGE_H, C_PAPER_OLD)
	_r(b.x, b.y + PAGE_H - 1, PAGE_W, 1, C_PAPER_OLD)
	for i in 3:
		_draw_icon(i, b)
	_r(b.x + 4, b.y + 26, PAGE_W - 8, 1, Color(0.6, 0.45, 0.25, 0.5))
	# hand-written scribble lines (illegible by design, no text)
	for r in 4:
		var y := b.y + 30 + r * 4
		var x := b.x + 4
		var end_x := b.x + PAGE_W - 4 - (r % 2) * 9
		var k := r
		while x < end_x:
			var seg := 3 + (k * 5 + r) % 4
			seg = mini(seg, end_x - x)
			_r(x, y + (k % 2), seg, 1, C_INK)
			if k % 3 == 0:
				_r(x + 1, y - 1 + (k % 2), 1, 1, C_INK)
			x += seg + 2
			k += 1
	if _finished:
		_draw_sparkle(b.x + PAGE_W - 5, b.y + 3)
		_draw_sparkle(b.x + 4, b.y + PAGE_H - 6)


func _draw_sparkle(x: int, y: int) -> void:
	var g := Color("ffe27a")
	_r(x, y - 2, 1, 5, g)
	_r(x - 2, y, 5, 1, g)
	_r(x, y, 1, 1, Color.WHITE)


func _draw_puff() -> void:
	var p := (_t - PUFF_START) / PUFF_DUR
	if p <= 0.0 or p >= 1.0:
		return
	var e := _ease_out(p)
	var center := PAGE_POS + Vector2i(PAGE_W / 2, PAGE_H / 2)
	var fade := 1.0 - p
	for k in 14:
		var ang := k * TAU / 14.0 + (k % 3) * 0.3
		var d := (6.0 + 22.0 * e) * (0.6 + 0.1 * (k % 4))
		var px := center.x + roundi(cos(ang) * d * 1.5)
		var py := center.y + roundi(sin(ang) * d * 0.8)
		var sz := 3 + (k % 3) * 2 + int(3.0 * p)
		var c := C_FLOUR
		c.a = 0.9 * fade
		_r(px - sz / 2, py - sz / 2, sz, sz, c)
	# dense core that dissolves quickly
	var core := C_FLOUR
	core.a = clampf(1.2 - p * 2.0, 0.0, 1.0) * 0.95
	if core.a > 0.0:
		var cs := 14 + int(12.0 * p)
		_r(center.x - cs, center.y - cs / 2, cs * 2, cs, core)
