extends Control

signal beat_changed(index:int)

const Characters=preload("res://scripts/character_sprite_art.gd")
const TERRAIN=preload("res://assets/village-preview/terrain.png")
const PROPS=preload("res://assets/village-preview/props.png")
const DURATION:=2.3
const SCALE:=2.0
const LUOLUO_FOOT:=Vector2(-32,54)
const MILU_FOOT:=Vector2(34,54)

var characters:=Characters.new()
var envelope:Texture2D
var reduced:=false
var handed:=false
var elapsed:=DURATION
var beat:=0

func _init() -> void:
	name="LuoluoLetterScene"
	custom_minimum_size.y=132
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	characters.setup()
	resized.connect(queue_redraw)
	set_process(false)

func play() -> void:
	elapsed=DURATION if reduced else 0.0
	beat=2 if reduced else 0
	beat_changed.emit(beat)
	set_process(not reduced)
	queue_redraw()

func _process(delta:float) -> void:
	elapsed=minf(DURATION,elapsed+delta)
	var next:=2 if elapsed>=DURATION else (1 if elapsed>=0.68 else 0)
	if next!=beat:
		beat=next
		beat_changed.emit(beat)
	if elapsed>=DURATION:set_process(false)
	queue_redraw()

func _draw() -> void:
	var extent:=Vector2(ceili(size.x/SCALE),ceili(size.y/SCALE))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*SCALE)
	for y in range(0,ceili(extent.y),32):
		for x in range(0,ceili(extent.x),32):
			var source:=Rect2(32 if x==64 else 0,64,32,32)
			if x<64:source=Rect2(0 if (x+y)%64==0 else 32,32,32,32)
			draw_texture_rect_region(TERRAIN,Rect2(x,y,32,32),source)
	var pier_width:=ceili(extent.x*0.5+74.0)
	for x in range(0,pier_width,16):
		draw_texture_rect_region(TERRAIN,Rect2(x,33,16,29),Rect2(65,66,16,29))
	for x in [48,pier_width-8]:
		draw_rect(Rect2(x,31,5,34),Color("694c36"))
		draw_rect(Rect2(x+1,31,3,31),Color("b78b58"))
	draw_texture_rect_region(PROPS,Rect2(4,-23,64,64),Rect2(0,0,64,64))
	var middle:=Vector2(floorf(extent.x*0.5),0)
	draw_set_transform(middle*SCALE,0.0,Vector2.ONE*SCALE)
	var approach:=Vector2(roundf(lerpf(-9.0,0.0,clampf(elapsed/0.68,0.0,1.0))),0)
	var walking:=elapsed<0.68
	if walking:approach.y=-float(int(elapsed*10.0)%2)
	characters.draw_person(self,LUOLUO_FOOT+approach,Color.WHITE,"luoluo",Vector2i.RIGHT,elapsed*10.0,walking,reduced)
	characters.draw_person(self,MILU_FOOT,Color.WHITE,"milu",Vector2i.LEFT,0.0,false,reduced)
	var from:=LUOLUO_FOOT+Vector2(13,-18)+approach
	if handed:
		var progress:=clampf((elapsed-0.75)/0.9,0.0,1.0)
		var point:=from.lerp(MILU_FOOT+Vector2(-13,-18),progress)
		point.y-=roundf(sin(progress*PI)*8.0)
		if envelope!=null:draw_texture_rect(envelope,Rect2(point.round()-Vector2(9,9),Vector2(18,18)),false)
	elif envelope!=null:
		draw_texture_rect(envelope,Rect2(from.round()-Vector2(9,9),Vector2(18,18)),false)
		if beat==1:
			var wave:=floorf(clampf((elapsed-0.68)/0.9,0.0,1.0)*12.0)
			for i in range(3):
				draw_rect(Rect2(-8+i*7+wave,18+(i%2)*3,5,2),Color("fff0c3"))
