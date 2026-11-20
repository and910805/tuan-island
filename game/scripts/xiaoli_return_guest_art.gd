extends Control
## Standalone cameo: 米露 walks up to the real market stall holding a jam jar. Presentation only:
## no audio, no actions, no input. Drawn in native pixels at a uniform 1.5x with nearest filtering
## (~100px tall). Reduced motion settles at the booth immediately.

const StallArt=preload("res://scripts/flower_scene_art.gd")
const DecorArt=preload("res://scripts/market_decor_art.gd")
const SpriteArt=preload("res://scripts/character_sprite_art.gd")
const ATLAS=preload("res://assets/life-art/characters.png")
const JAM=preload("res://assets/ui-inventory/strawberry-jam.png")
const GROUND=preload("res://assets/village-preview/terrain.png")
const PLANTS=preload("res://assets/village-preview/props.png")
const SCALE:=1.5
const NATIVE:=Vector2(150,66)
const STALL_POS:=Vector2(84,0)
const START_X:=-10.0
const END_X:=56.0
const FOOT_Y:=62.0
const DURATION:=1.4

var played:=false
var reduced:=false
var progress:=0.0
var elapsed:=0.0

static func make(reduced_motion:bool)->Control:
	var cameo:=new()
	cameo.reduced=reduced_motion
	cameo.progress=1.0 if reduced_motion else 0.0
	return cameo

func _init()->void:
	custom_minimum_size=NATIVE*SCALE
	size=custom_minimum_size
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	name="XiaoliReturnGuest"
	clip_contents=true
	resized.connect(queue_redraw)
	set_process(false)

func play()->void:
	played=true
	if reduced:
		progress=1.0
		set_process(false)
	else:
		progress=0.0
		elapsed=0.0
		set_process(true)
	queue_redraw()

func _process(delta:float)->void:
	elapsed+=delta
	progress=clampf(elapsed/DURATION,0.0,1.0)
	if progress>=1.0:set_process(false)
	queue_redraw()

func _draw()->void:
	for y in range(0,ceili(size.y),32):
		for x in range(0,ceili(size.x),32):
			var source:=Rect2(0 if y<32 else 32,0 if y<32 else 32,32,32)
			draw_texture_rect_region(GROUND,Rect2(x,y,32,32),source,Color("dfd8ba"))
	draw_texture_rect_region(PLANTS,Rect2(18,-30,128,128),Rect2(0,0,64,64))
	draw_texture_rect_region(PLANTS,Rect2(size.x-99,31,64,64),Rect2(0,64,64,64))
	var origin:=Vector2(roundf((size.x-NATIVE.x*SCALE)*0.5),0)
	draw_set_transform(origin,0.0,Vector2(SCALE,SCALE))
	var stall:=StallArt.market_texture(false)
	if stall!=null:draw_texture(stall,STALL_POS)
	DecorArt.draw(self,STALL_POS,{"cloth":"chestnut","sign":"chestnut_badge"})
	var eased:=1.0-pow(1.0-progress,3.0)
	var walking:=progress<1.0
	var x:=roundf(lerpf(START_X,END_X,eased))
	var bob:=-1.0 if walking and int(elapsed*8.0)%2==1 else 0.0
	var foot:=Vector2(x,FOOT_Y+bob)
	var facing:=Vector2i.RIGHT if walking else Vector2i.DOWN
	var frame:=SpriteArt.frame_selection("milu",facing,0.0,false,true)
	draw_texture_rect_region(ATLAS,Rect2(foot-Vector2(SpriteArt.FOOT),Vector2(SpriteArt.FRAME_SIZE)),Rect2(Vector2(frame*SpriteArt.FRAME_SIZE),Vector2(SpriteArt.FRAME_SIZE)))
	var jar_pos:=foot+Vector2(8,-20)
	draw_texture_rect(JAM,Rect2(jar_pos,Vector2(14,14)),false)
