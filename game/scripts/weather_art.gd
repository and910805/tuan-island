extends RefCounted
## Presentation-only weather helpers. Reads weather through weather.gd (owned by
## the core worker) and never writes snapshot/state. All sampling is a pure
## function of (index, elapsed, camera, view size) so frames are reproducible and
## no per-frame nodes or growing buffers are needed.

const WeatherRules=preload("res://scripts/weather.gd")
const TILE:=32.0
## Fixed particle cap for falling drops on screen.
const MAX_DROPS:=40
## Cap for static puddle marks when reduced motion is on.
const MAX_STATIC_MARKS:=24
const SNOW_FLAKES:=34
const WIND_FLECKS:=15
## One static mark per this many outdoor cells (deterministic by cell hash).
const STATIC_EVERY:=13
## Fraction of each drop cycle spent falling; the rest is a small landing ripple.
const FALL_PART:=0.78125 # 25/32: exact in Vector3's float32 phase at landing.
const FALL_DISTANCE:=44.0
const SLANT:=6.0
const PERIOD_MIN:=0.85
const DROP_COLOR:=Color(0.86,0.93,0.98,0.55)
const RIPPLE_COLOR:=Color(0.88,0.95,1.0,0.42)

static func current(snapshot:Dictionary) -> Dictionary:
	if snapshot.is_empty():return {}
	var info:Dictionary=WeatherRules.at(float(snapshot.get("time",0.0)),str(snapshot.get("region_id","home")))
	return info

static func label(info:Dictionary) -> String:
	return str(info.get("label",""))

static func weather_id(info:Dictionary) -> String:
	return str(info.get("id",""))

## Only sunny weather may use the sun atlas icon; everything else uses the
## neutral calendar icon so a sun is never shown during rain/cloud/indoors.
static func icon_id(info:Dictionary) -> String:
	return "weather" if weather_id(info)=="sunny" else "calendar"

static func rains(info:Dictionary) -> bool:
	return bool(info.get("raining",false)) and weather_id(info)!="indoor"

## Very light readability-safe tint; transparent for sunny/indoor/unknown.
static func tint(info:Dictionary) -> Color:
	if rains(info):return Color(0.26,0.34,0.46,0.08)
	if weather_id(info)=="cloudy":return Color(0.32,0.38,0.46,0.05)
	if weather_id(info)=="snowy":return Color(0.66,0.77,0.85,0.10)
	return Color(0,0,0,0)

static func mix(a:int,b:int) -> int:
	var h:int=(a*374761393+b*668265263+0x5bd1e995)&0x7fffffff
	h=((h^(h>>13))*1274126177)&0x7fffffff
	return (h^(h>>16))&0x7fffffff

## Returns Vector3(screen_x, screen_y, phase) for drop `index` in view-local
## (pre-zoom) units. The landing point is world-anchored: camera movement keeps
## a drop over the same ground until it wraps out of the margin window.
static func drop(index:int,elapsed:float,camera:Vector2,view_size:Vector2) -> Vector3:
	var h0:int=mix(index,7)
	var period:float=PERIOD_MIN+float(h0%40)/100.0
	var t:float=maxf(elapsed,0.0)/period+float(h0%97)/97.0
	var cycle:int=floori(t)
	var phase:float=t-float(cycle)
	var h:int=mix(index,cycle)
	var span:Vector2=Vector2(ceilf(view_size.x/TILE)+2.0,ceilf(view_size.y/TILE)+2.0)*TILE
	var base:Vector2=(camera/TILE).floor()*TILE-Vector2(TILE,TILE)
	var raw:Vector2=Vector2(float(h%65521),float((h>>15)%65521))
	var world:Vector2=base+Vector2(fposmod(raw.x-base.x,span.x),fposmod(raw.y-base.y,span.y))
	var land:Vector2=(world-camera).round()
	return Vector3(land.x,land.y,phase)

## Streak head position while falling (phase < FALL_PART).
static func streak_head(sample:Vector3) -> Vector2:
	var remaining:float=1.0-clampf(sample.z/FALL_PART,0.0,1.0)
	return (Vector2(sample.x-SLANT*remaining,sample.y-FALL_DISTANCE*remaining)).round()

static func ripple_strength(sample:Vector3) -> float:
	if sample.z<FALL_PART:return 0.0
	return clampf(1.0-(sample.z-FALL_PART)/(1.0-FALL_PART),0.0,1.0)

## Static puddle offset inside a tile, or Vector2(-1,-1) when the cell has none.
static func static_mark(cell:Vector2i) -> Vector2:
	var h:int=mix(cell.x*92821+cell.y*31,3)
	if h%STATIC_EVERY!=0:return Vector2(-1,-1)
	return Vector2(7+(h>>4)%18,9+(h>>9)%16)

static func draw_streak(canvas:CanvasItem,head:Vector2) -> void:
	canvas.draw_rect(Rect2(head,Vector2(1,3)),DROP_COLOR)
	canvas.draw_rect(Rect2(head+Vector2(-1,-3),Vector2(1,3)),Color(DROP_COLOR,DROP_COLOR.a*0.6))

static func drift(index:int,elapsed:float,camera:Vector2,view_size:Vector2,snow:bool) -> Vector3:
	var sample:=drop(index,elapsed*(0.19 if snow else 0.30),camera,view_size)
	var spread:=Vector2(22,55) if snow else Vector2(74,11)
	var at:=(Vector2(sample.x,sample.y)+(sample.z-0.5)*spread).round()
	return Vector3(at.x,at.y,sin(PI*sample.z))

static func draw_drift(canvas:CanvasItem,at:Vector2,intensity:float,snow:bool) -> void:
	if snow:
		var snow_color:=Color(0.92,0.97,1.0,0.85*intensity)
		canvas.draw_rect(Rect2(at+Vector2(-2,0),Vector2(5,1)),snow_color)
		canvas.draw_rect(Rect2(at+Vector2(0,-2),Vector2(1,5)),snow_color)
		return
	canvas.draw_rect(Rect2(at,Vector2(3,2)),Color(0.83,0.79,0.43,0.68*intensity))
	canvas.draw_rect(Rect2(at+Vector2(3,-1),Vector2(2,1)),Color(0.91,0.87,0.52,0.70*intensity))

static func draw_ripple(canvas:CanvasItem,at:Vector2,strength:float) -> void:
	if strength<=0.0:return
	var color:=Color(RIPPLE_COLOR,RIPPLE_COLOR.a*strength)
	var w:int=2 if strength>0.5 else 3
	canvas.draw_rect(Rect2(at+Vector2(-w,0),Vector2(1,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(w,0),Vector2(1,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(-w+1,-1),Vector2(2*w-1,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(-w+1,1),Vector2(2*w-1,1)),color)
