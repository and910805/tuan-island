extends RefCounted
## Wall-mounted wind chime with a temporary local ring effect.
const TEXTURE=preload("res://assets/ui-life/water-listening-chime.png")
const SIZE:=Vector2(22,32)
const RING_SECONDS:=1.2
const NOTE_SECONDS:=0.9

## Horizontal sway in whole pixels. Reduced motion (and photo mode) never sways.
static func sway(age:float,reduced:bool) -> float:
	if reduced or age<0.0 or age>=RING_SECONDS:return 0.0
	return roundf(sin(age*13.0)*2.5*(1.0-age/RING_SECONDS))

## 0..1 opacity of the brief note mark, 0 when idle. Shown in every motion mode.
static func note_alpha(age:float) -> float:
	if age<0.0 or age>=NOTE_SECONDS:return 0.0
	return 1.0-smoothstep(0.35,1.0,age/NOTE_SECONDS)

## `at` is the fixture cell's top-left; `age` is seconds since the last ring (-1 when idle).
static func draw(canvas:CanvasItem,at:Vector2,age:float=-1.0,reduced:bool=false,tint:Color=Color.WHITE) -> void:
	var origin:=at+Vector2(5,-32)
	var shift:=Vector2(sway(age,reduced),0)
	canvas.draw_texture(TEXTURE,origin+shift,tint)
	var alpha:=note_alpha(age)
	if alpha>0.0:
		var ink:=Color(0.96,0.88,0.58,alpha)
		var top:=origin+Vector2(SIZE.x+1,2.0-(0.0 if reduced else roundf(age*6.0)))
		canvas.draw_rect(Rect2(top+Vector2(2,0),Vector2(1,5)),ink)
		canvas.draw_rect(Rect2(top+Vector2(0,4),Vector2(3,2)),ink)

static func draw_thumbnail(canvas:CanvasItem,origin:Vector2) -> void:
	canvas.draw_texture(TEXTURE,origin+Vector2(5,6))
