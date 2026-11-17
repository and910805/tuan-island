extends Control

const Table=preload("res://assets/ui-inventory/tea-arrangement-tables.png")
const Set=preload("res://assets/ui-inventory/basic-tea-set.png")
var axis:=""
var cups:=0

func _ready() -> void:
	custom_minimum_size=Vector2(0,170)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	if axis.is_empty():return
	var top:=Vector2(floorf(size.x/2)-64,16)
	var vertical:=axis=="vertical"
	draw_texture_rect_region(Table,Rect2(top,Vector2(128,128)),Rect2(32 if vertical else 0,0,32,32))
	var places:Array=[Vector2(16,9),Vector2(16,17)] if vertical else [Vector2(10,13),Vector2(22,13)]
	for index in cups:
		var cup:Vector2=top+places[index]*4-Vector2(12,12)
		draw_texture_rect_region(Set,Rect2(cup,Vector2(21,24)),Rect2(9+9*index,8,7,8))
