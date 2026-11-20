extends Control

# N08-4 鈴婆婆 and her bell - compact illustration, display only.
# No sound, storage, signals or gameplay calls; the owner decides when to ring().
#
# Art comes from existing sprites: 鈴婆婆 is the pixel character frame used in
# the world (characters.png, column 4, facing down, with her usual tint) and
# the bell is the cracked dock bell item icon. The grass and plants come from
# the village map atlases.
#
# Ringing: the bell swings on its cord with a damped sway while short ringing
# lines pulse on both sides (~1.2s), then settles hanging straight with a few
# sparkles left beside it. With reduced_motion ring() jumps straight to that
# settled picture and nothing ever animates.
#
# API:
#   static make(reduce_motion: bool) -> Control
#   ring() -> void
#   rang: bool    true as soon as ring() has been called

const CHARACTERS := preload("res://assets/life-art/characters.png")
const BELL := preload("res://assets/ui-inventory/cracked-dock-bell.png")
const GROUND := preload("res://assets/village-preview/terrain.png")
const PLANTS := preload("res://assets/village-preview/props.png")

const HEIGHT := 100.0
const MIN_WIDTH := 220.0
const PIXEL := 2                       # sprites are drawn at 2x, nearest filter
const FRAME := Vector2(48, 48)
const FRAME_ORIGIN := Vector2(192, 96) # 鈴婆婆 turns towards the bell.
const SPRITE_TINT := Color(0.86, 0.82, 0.92)
const GROUND_Y := 92.0
const BEAM_Y := 6.0
const BEAM_H := 6.0
const CORD_LENGTH := 10.0

const RING_SECONDS := 1.2
const LINES_SECONDS := 0.8
const MAX_SWING := 0.42                # radians
const SWING_SPEED := 22.0
const SWING_DAMPING := 3.2

const C_BEAM := Color("61402f")
const C_BEAM_LIGHT := Color("b48a50")
const C_CORD := Color("c9a66b")
const C_SHADOW := Color(0, 0, 0, 0.25)
const C_RING := Color("fff2b0")
const C_SPARKLE := Color("f4d27a")

## True immediately after ring(), and stays true.
var rang := false

var _reduce_motion := false
var _time := RING_SECONDS    # seconds since ring(); RING_SECONDS = settled


static func make(reduce_motion: bool) -> Control:
	var scene := new()
	scene._reduce_motion = reduce_motion
	return scene


func _init() -> void:
	name = "LingpopoBellScene"
	custom_minimum_size = Vector2(MIN_WIDTH, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	resized.connect(queue_redraw)
	set_process(false)


func ring() -> void:
	rang = true
	if _reduce_motion:
		_time = RING_SECONDS
		set_process(false)
	else:
		_time = 0.0
		set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _time >= RING_SECONDS:
		_time = RING_SECONDS
		set_process(false)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var width := maxf(size.x, MIN_WIDTH)
	_draw_backdrop(width)
	_draw_lingpopo(width)
	_draw_bell(width)


func _draw_backdrop(width: float) -> void:
	for y in range(0,int(HEIGHT),32):
		for x in range(0,ceili(width),32):
			draw_texture_rect_region(GROUND,Rect2(x,y,32,32),Rect2(0,0,32,32),Color("c4caa2"))
	draw_texture_rect_region(PLANTS,Rect2(0,-42,128,128),Rect2(0,0,64,64))
	draw_texture_rect_region(PLANTS,Rect2(width-144,-26,128,128),Rect2(128,0,64,64))
	draw_texture_rect_region(PLANTS,Rect2(width*0.18,40,64,64),Rect2(0,64,64,64))
	draw_texture_rect_region(PLANTS,Rect2(width*0.76,44,64,64),Rect2(64,64,64,64))
	var post_x:=_bell_pivot(width).x+43.0
	draw_rect(Rect2(post_x,BEAM_Y,8,GROUND_Y-BEAM_Y),C_BEAM)
	draw_rect(Rect2(post_x,BEAM_Y,3,GROUND_Y-BEAM_Y),C_BEAM_LIGHT)
	draw_rect(Rect2(post_x-65,BEAM_Y,76,BEAM_H),C_BEAM)
	draw_rect(Rect2(post_x-65,BEAM_Y,76,2),C_BEAM_LIGHT)
	draw_rect(Rect2(0,0,width,HEIGHT),C_BEAM,false,2.0)


func _lingpopo_foot(width: float) -> Vector2:
	return Vector2(roundf(width * 0.44), GROUND_Y - 2.0)


func _bell_pivot(width: float) -> Vector2:
	return Vector2(roundf(width * 0.62), BEAM_Y + BEAM_H + CORD_LENGTH)


func _draw_lingpopo(width: float) -> void:
	var foot := _lingpopo_foot(width)
	var top_left := foot - Vector2(24, 44) * PIXEL
	draw_rect(Rect2(foot.x - 20, foot.y - 2, 40, 4), C_SHADOW)
	draw_texture_rect_region(CHARACTERS, Rect2(top_left, FRAME * PIXEL), Rect2(FRAME_ORIGIN, FRAME), SPRITE_TINT)


func _swing_angle() -> float:
	if not rang or _time >= RING_SECONDS:
		return 0.0
	return MAX_SWING * exp(-SWING_DAMPING * _time) * sin(SWING_SPEED * _time)


func _draw_bell(width: float) -> void:
	var pivot := _bell_pivot(width)
	var bell_size := BELL.get_size() * PIXEL
	var angle := _swing_angle()
	# cord from the beam to the pivot, then the bell rotates around that point
	draw_rect(Rect2(pivot.x - 1, BEAM_Y + BEAM_H, 2, CORD_LENGTH), C_CORD)
	draw_set_transform(pivot, angle, Vector2.ONE)
	draw_texture_rect(BELL, Rect2(Vector2(-bell_size.x * 0.5, -4), bell_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var center := pivot + Vector2(0, bell_size.y * 0.5)
	if _time < LINES_SECONDS and rang and not _reduce_motion:
		_draw_ring_lines(center, bell_size.y * 0.5)
	elif rang:
		_draw_settled_result(center, bell_size)


## Short dashes fanning out on both sides of the bell, pulsing while they fade.
func _draw_ring_lines(center: Vector2, reach: float) -> void:
	var fade := 1.0 - _time / LINES_SECONDS
	var pulse := int(_time * 14.0) % 2
	for side in [-1.0, 1.0]:
		for i in 3:
			var tilt := (i - 1) * 0.45
			var dir := Vector2(side * cos(tilt), sin(tilt))
			var start := center + dir * (reach + 6.0 + pulse * 3.0)
			var color := C_RING
			color.a = fade
			draw_line(start, start + dir * 8.0, color, 2.0)


## Small calm result once the bell has rung: a few sparkles beside the bell.
func _draw_settled_result(center: Vector2, bell_size: Vector2) -> void:
	for spot in [Vector2(-0.8, -0.35), Vector2(0.85, -0.1), Vector2(-0.6, 0.3)]:
		var at := (center + Vector2(spot.x * bell_size.x, spot.y * bell_size.y)).round()
		draw_rect(Rect2(at.x - 1, at.y - 4, 2, 8), C_SPARKLE)
		draw_rect(Rect2(at.x - 4, at.y - 1, 8, 2), C_SPARKLE)
