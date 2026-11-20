extends Control

const Table=preload("res://assets/ui-inventory/tea-arrangement-tables.png")
const Set=preload("res://assets/ui-inventory/basic-tea-set.png")
const CUP_TIME:=0.18
const DROP_PIXELS:=12.0

# true = static (default; blueprint reuse). Interactive root sets false to enable placement animation.
var reduced_motion:=true:
	set(value):
		reduced_motion=value
		if value:
			_stop_animation()

var axis:="":
	set(value):
		if value==axis:return
		axis=value
		_stop_animation() # direction switch / initial load never animates
		queue_redraw()

var cups:=0:
	set(value):
		value=clampi(value,0,2)
		if value==cups:return
		var old:=cups
		cups=value
		if value>old and not reduced_motion and not axis.is_empty() and is_inside_tree():
			for index in range(old,cups):
				_cup_time[index]=0.0
			set_process(true)
		elif value<=old:
			_stop_animation()
		queue_redraw()

var _cup_time:=PackedFloat32Array([-1.0,-1.0])

func _ready() -> void:
	custom_minimum_size.y=maxf(custom_minimum_size.y,170)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

# Simple query for tests: true only while a placement animation is running.
func is_animating() -> bool:
	return _cup_time[0]>=0.0 or _cup_time[1]>=0.0

func _stop_animation() -> void:
	_cup_time.fill(-1.0)
	set_process(false)
	queue_redraw()

func _process(delta:float) -> void:
	for index in cups:
		if _cup_time[index]<0.0:continue
		_cup_time[index]+=delta
		if _cup_time[index]>=CUP_TIME:_cup_time[index]=-1.0
	if not is_animating():set_process(false)
	queue_redraw()

func _draw() -> void:
	if axis.is_empty():return
	var top:=Vector2(floorf(size.x/2)-64,16)
	var vertical:=axis=="vertical"
	draw_texture_rect_region(Table,Rect2(top,Vector2(128,128)),Rect2(32 if vertical else 0,0,32,32))
	var places:Array=[Vector2(16,9),Vector2(16,17)] if vertical else [Vector2(10,13),Vector2(22,13)]
	for index in cups:
		var cup:Vector2=top+places[index]*4-Vector2(12,12)
		var spark:=-1.0
		if _cup_time[index]>=0.0:
			var t:=clampf(_cup_time[index]/CUP_TIME,0.0,1.0)
			var eased:=1.0-pow(1.0-t,3.0)
			# snap to whole pixels (2px steps) for a pixel-art feel
			cup.y-=roundf((1.0-eased)*DROP_PIXELS/2.0)*2.0
			spark=t
		draw_texture_rect_region(Set,Rect2(cup,Vector2(21,24)),Rect2(9+9*index,8,7,8))
		if spark>=0.6 and spark<1.0:
			_draw_sparkle(top+places[index]*4+Vector2(0,-16))

func _draw_sparkle(center:Vector2) -> void:
	var c:=Color(1,0.95,0.7,0.9)
	var p:=Vector2(floorf(center.x),floorf(center.y))
	draw_rect(Rect2(p+Vector2(-1,-5),Vector2(2,10)),c)
	draw_rect(Rect2(p+Vector2(-5,-1),Vector2(10,2)),c)
