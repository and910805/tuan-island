extends Control

# T066 N05-1 阿潮打不開的繩結 - compact procedural pixel-art diagram.
# Display only: no storage, no actions, no signals, no child nodes.
#
# Three physically distinct sections of twisted mooring line hang from a pier
# beam in front of weathered planks, left to right: bow (0), middle (1),
# stern (2). Each has its own colour, a wrap-lashing while it is still bound,
# and a tag with one notch at the stern, two in the middle, three at the bow.
# A picked section is drawn released: thinner, sagging, un-lashed and frayed
# open at the tip. Only a section that extends the correct prefix of
# [2, 1, 0] plays a short, non-looping settle animation (~0.5s). With
# reduced_motion the art is always static.
#
# API:
#   static make(reduced_motion: bool) -> Control
#   sync(picks: Array) -> void      ([] resets; [2, 1, 0] = completion mode)

const Goals = preload("res://scripts/resident_goals.gd")
const ORDER: Array = Goals.GOALS.achao[1].order
const NATIVE := Vector2i(152, 60)
const SCALE := 2
const ANIM_SECONDS := 0.5

const ROPE_TOP := 11
const ROPE_END_TIGHT := 45
const ROPE_END_SLACK := 51

const C_PLANK := Color("6b4a30")
const C_PLANK_DARK := Color("4a3220")
const C_PLANK_LIGHT := Color("82603f")
const C_BEAM := Color("3a2718")
const C_BEAM_LIGHT := Color("5a3f28")
const C_NAIL := Color("2a1c12")
const C_TAG := Color("d9c9a0")
const C_TAG_EDGE := Color("8a7650")
const C_NOTCH := Color("3a2718")
const C_TAG_DONE := Color("9fc58a")
const C_TAG_FLASH := Color("fff2b0")

# Per section: base, dark, light (bow tan, middle sea-green, stern rust red).
const ROPE_COLORS: Array = [
	[Color("c9a66b"), Color("7a5f35"), Color("ecd7a0")],
	[Color("7fa38c"), Color("3f6552"), Color("b5d6bf")],
	[Color("b8644a"), Color("6e3324"), Color("e39a7e")],
]

var _reduced_motion := false
var _picks: Array[int] = []
var _prefix := 0
var _anim_section := -1
var _anim_t := 1.0


static func make(reduced_motion: bool) -> Control:
	var art := new()
	art._reduced_motion = reduced_motion
	return art


func _init() -> void:
	custom_minimum_size = Vector2(NATIVE.x * SCALE, NATIVE.y * SCALE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(false)


func sync(picks: Array) -> void:
	var clean: Array[int] = []
	for v in picks:
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			continue
		var i := int(v)
		if i < 0 or i > 2 or clean.has(i):
			continue
		clean.append(i)
	var new_prefix := 0
	while new_prefix < clean.size() and new_prefix < ORDER.size() and clean[new_prefix] == ORDER[new_prefix]:
		new_prefix += 1
	var advanced := new_prefix > _prefix
	if clean == _picks:return
	_picks = clean
	_prefix = new_prefix
	if advanced and not _reduced_motion:
		_anim_section = ORDER[new_prefix - 1]
		_anim_t = 0.0
		set_process(true)
	else:
		_anim_section = -1
		_anim_t = 1.0
		set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_anim_t += delta / ANIM_SECONDS
	if _anim_t >= 1.0:
		_anim_t = 1.0
		_anim_section = -1
		set_process(false)
	queue_redraw()

func released_count() -> int:
	return _picks.size()

func is_animating() -> bool:
	return _anim_section>=0


# ---------------------------------------------------------------- drawing

func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x * SCALE, y * SCALE, w * SCALE, h * SCALE), c)


func _draw() -> void:
	_draw_backdrop()
	for s in 3:
		var slack := 1.0 if _picks.has(s) else 0.0
		var flash := 0.0
		if s == _anim_section:
			var t := clampf(_anim_t, 0.0, 1.0)
			slack = 1.0 - pow(1.0 - t, 3.0)
			flash = 1.0 - t
		_draw_rope(s, slack)
		_draw_tag(s, flash)


func board_width() -> int:
	return maxi(NATIVE.x,int(size.x)/SCALE)

func section_x(section:int) -> int:
	return roundi(float(board_width())*(2*section+1)/6.0)

func _draw_backdrop() -> void:
	var width:=board_width()
	_r(0, 0, width, NATIVE.y, C_PLANK)
	var y := 0
	var row := 0
	while y < NATIVE.y:
		_r(0, y, width, 1, C_PLANK_LIGHT)
		_r(0, y + 9, width, 1, C_PLANK_DARK)
		for seam in range(14+(row*37)%60,width-4,60):
			_r(seam, y + 1, 1, 8, C_PLANK_DARK)
			_r(seam + 3, y + 3, 1, 1, C_NAIL)
		y += 10
		row += 1
	# pier beam the lines hang from
	_r(0, 6, width, 5, C_BEAM)
	_r(0, 6, width, 1, C_BEAM_LIGHT)
	for x in range(4,width-3,30):
		_r(x, 8, 1, 1, C_NAIL)
	# side posts
	_r(0, 0, 3, NATIVE.y, C_BEAM)
	_r(width - 3, 0, 3, NATIVE.y, C_BEAM)


func _draw_rope(s: int, slack: float) -> void:
	var cx := section_x(s)
	var base: Color = ROPE_COLORS[s][0]
	var dark: Color = ROPE_COLORS[s][1]
	var light: Color = ROPE_COLORS[s][2]
	var w := int(round(lerpf(8.0, 5.0, slack)))
	var y_end := int(round(lerpf(ROPE_END_TIGHT, ROPE_END_SLACK, slack)))
	var amp := 6.0 * slack
	var period := 4 + int(round(2.0 * slack))
	var span := float(y_end - ROPE_TOP)
	# the bow line is the thickest, the stern the thinnest: distinct silhouettes
	var extra := 1 if s == 0 else 0
	var shadow_dx := 2
	for y in range(ROPE_TOP, y_end + 1):
		var t := float(y - ROPE_TOP) / span
		var off := int(round(amp * sin(t * PI * 1.4 + 0.5 * slack) * t))
		var rw := w + extra
		var left := cx - rw / 2 + off
		# soft shadow on the planks
		_r(left + shadow_dx, y, rw, 1, Color(0, 0, 0, 0.22))
		_r(left, y, rw, 1, dark)
		_r(left + 1, y, rw - 2, 1, base)
		# diagonal twist: dark groove + highlight
		var k := (y + s) % period
		var gx := left + 1 + (k * (rw - 2)) / period
		_r(gx, y, 1, 1, dark)
		if gx + 1 < left + rw - 1:
			_r(gx + 1, y, 1, 1, light)
	var end_off := int(round(amp * sin(1.0 * PI * 1.4 + 0.5 * slack)))
	var end_left := cx - (w + extra) / 2 + end_off
	var end_w := w + extra
	if slack > 0.5:
		# open, frayed tip: strands spread apart
		for i in 4:
			_r(end_left - i, y_end + 1 + i / 2, 1, 1, light)
			_r(end_left + end_w - 1 + i, y_end + 1 + i / 2, 1, 1, base)
			_r(end_left + end_w / 2 + (i % 2) * 2 - 1, y_end + 1 + i / 2, 1, 1, dark)
	else:
		# whipped, tight end
		_r(end_left, y_end - 2, end_w, 2, dark)
		_r(end_left + 1, y_end - 2, end_w - 2, 1, light)
		# lashing wraps that bind the section while it is still closed
		for wy in [22, 26, 30]:
			_r(cx - (w + extra) / 2 - 1, wy, w + extra + 2, 2, dark)
			_r(cx - (w + extra) / 2, wy, w + extra, 1, base.darkened(0.15))
		# The tied loop narrows back into the line below the wraps.
		var stem := cx+(w+extra)/2-1
		_r(stem,23,6,3,dark)
		_r(stem+5,25,3,8,dark)
		_r(stem+3,32,4,4,dark)
		_r(stem-2,34,6,3,dark)
		_r(stem+1,24,4,1,light)
		_r(stem+6,26,1,6,base)
		_r(stem,35,4,1,base)
	# anchor lump where the line meets the beam
	_r(cx - (w + extra) / 2 - 1, ROPE_TOP - 1, w + extra + 2, 2, dark)


func _draw_tag(s: int, flash: float) -> void:
	var cx := section_x(s)
	var n := ORDER.find(s)+1
	var done := _picks.has(s)
	var face := C_TAG_DONE if done else C_TAG
	if flash > 0.0:
		face = face.lerp(C_TAG_FLASH, flash)
	_r(cx - 10, 53, 20, 6, C_TAG_EDGE)
	_r(cx - 9, 54, 18, 4, face)
	# n vertical notches, 2 wide, 2 gap
	var total := n * 2 + (n - 1) * 2
	var sx := cx - total / 2
	for i in n:
		_r(sx + i * 4, 54, 2, 4, C_NOTCH)
