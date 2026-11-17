extends RefCounted

const APRON_ATLAS=preload("res://assets/life-art/milu-apron.png")
const ATLAS_PATH:="res://assets/life-art/characters.png"
const FRAME_SIZE:=Vector2i(48,48)
const ATLAS_SIZE:=Vector2i(288,192)
const FOOT:=Vector2i(24,44)
var atlas:Texture2D
var blue_atlas:Texture2D
var animals:Texture2D

func setup() -> bool:
	if not ResourceLoader.exists(ATLAS_PATH):return false
	atlas=load(ATLAS_PATH) as Texture2D
	if atlas==null or Vector2i(atlas.get_size())!=ATLAS_SIZE:
		atlas=null
		return false
	if ResourceLoader.exists("res://assets/life-art/animals.png"):
		animals=load("res://assets/life-art/animals.png") as Texture2D
	return true

func draw_chicken(canvas:CanvasItem,foot:Vector2,reduced_motion:bool,elapsed:float) -> bool:
	if animals==null:return false
	var index:=1 if not reduced_motion and cos(elapsed*0.5)<0.0 else 0
	canvas.draw_texture_rect_region(animals,Rect2(foot.round()-Vector2(16,28),Vector2(32,32)),Rect2(index*32,0,32,32))
	return true

func draw_egg(canvas:CanvasItem,foot:Vector2) -> bool:
	if animals==null:return false
	canvas.draw_texture_rect_region(animals,Rect2(foot.round()-Vector2(16,28),Vector2(32,32)),Rect2(32,32,32,32))
	return true

static func frame_selection(style:String,facing:Vector2i,phase:float,walking:bool,reduced_motion:bool) -> Vector2i:
	var row:=0
	match facing:
		Vector2i.LEFT:row=1
		Vector2i.RIGHT:row=2
		Vector2i.UP:row=3
	var column:=0
	match style:
		"aru","achao","luoluo":column=3
		"milu","mianmian","lingpopo":column=4
		"xiaoli","nuannuan","diandian":column=5
		_:
			if walking:
				var stride:=sin(phase)
				var threshold:=0.45 if reduced_motion else 0.15
				if absf(stride)>threshold:column=1 if stride>0 else 2
	return Vector2i(column,row)

## T071 市集客人：玩家圖格加染色（透明度由 tint 帶入），不畫腳下色標。
func draw_tinted(canvas:CanvasItem,foot:Vector2,facing:Vector2i,phase:float,walking:bool,reduced_motion:bool,tint:Color) -> void:
	if atlas==null:return
	var frame:=frame_selection("",facing,phase,walking,reduced_motion)
	canvas.draw_texture_rect_region(atlas,Rect2(foot.round()-Vector2(FOOT),Vector2(FRAME_SIZE)),Rect2(Vector2(frame*FRAME_SIZE),Vector2(FRAME_SIZE)),tint)

func blue_workwear_atlas()->Texture2D:
	if blue_atlas!=null:return blue_atlas
	var pixels:=atlas.get_image()
	for row in 4:
		for column in 3:
			# Only replace the farmer's rust-coloured fabric around the torso.
			for y in range(26,37):
				for x in range(12,36):
					var p:=Vector2i(column*48+x,row*48+y)
					var c:=pixels.get_pixelv(p)
					if c.a>0.0 and c.r>c.g*1.45 and c.g>c.b*1.2 and c.h<0.09 and c.v>0.36:
						pixels.set_pixelv(p,Color.from_hsv(0.58,0.48,c.v,c.a))
	blue_atlas=ImageTexture.create_from_image(pixels)
	return blue_atlas

func draw_seated(canvas:CanvasItem,foot:Vector2,blue_workwear:bool,style:="") -> void:
	if atlas==null:return
	var texture:=blue_workwear_atlas() if blue_workwear else atlas
	var top:=foot.round()-Vector2(24,39)
	var source_x:=frame_selection(style,Vector2i.DOWN,0.0,false,false).x*FRAME_SIZE.x
	canvas.draw_texture_rect_region(texture,Rect2(top,Vector2(48,35)),Rect2(source_x,0,48,35))
	canvas.draw_texture_rect_region(texture,Rect2(top+Vector2(0,34),Vector2(48,9)),Rect2(source_x,38,48,9))

func draw_person(canvas:CanvasItem,foot:Vector2,shirt:Color,style:String,facing:Vector2i,phase:float,walking:bool,reduced_motion:bool,blue_workwear:=false,milu_apron:=false,cart_push:=0.0) -> void:
	if atlas==null:return
	var frame:=frame_selection(style,facing,phase,walking,reduced_motion)
	var at:=foot.round()
	# 棉棉、阿潮、暖暖暫用米露、阿榆、小栗的圖格加染色以便區分；專用像素圖待做。
	var tint:Color={"mianmian":Color(0.80,0.92,1.0),"achao":Color(0.86,0.96,0.94),"nuannuan":Color(1.0,0.80,0.68),"luoluo":Color(1.0,0.93,0.72),"lingpopo":Color(0.86,0.82,0.92),"diandian":Color(0.84,0.96,0.82)}.get(style,Color.WHITE)
	var texture:=blue_workwear_atlas() if blue_workwear and style in ["farmer","guest"] else atlas
	draw_person_frame(canvas,texture,at,frame,tint,facing,cart_push)
	if milu_apron and style in ["farmer","guest"]:
		draw_person_frame(canvas,APRON_ATLAS,at,frame,Color.WHITE,facing,cart_push)
	if style=="guest":
		# Use a small ground-level color tag to identify guests without tinting sprite pixels.
		canvas.draw_rect(Rect2(at+Vector2(-4,3),Vector2(8,3)),Color("403d35"))
		canvas.draw_rect(Rect2(at+Vector2(-3,3),Vector2(6,2)),shirt)

func draw_person_frame(canvas:CanvasItem,texture:Texture2D,foot:Vector2,frame:Vector2i,tint:Color,facing:Vector2i,cart_push:float) -> void:
	var top:=foot-Vector2(FOOT)
	var source:=Vector2(frame*FRAME_SIZE)
	if cart_push<=0.0:
		canvas.draw_texture_rect_region(texture,Rect2(top,Vector2(FRAME_SIZE)),Rect2(source,Vector2(FRAME_SIZE)),tint)
		return
	# Shift the torso in two steps while leaving boots on the original pixel grid.
	var lean:=(Vector2(facing)*cart_push).round()
	var shoulder_shift:=Vector2(lean.x,absf(lean.y))
	var waist_shift:=(Vector2(lean.x,0)*0.5).round()
	canvas.draw_texture_rect_region(texture,Rect2(top+shoulder_shift,Vector2(48,31)),Rect2(source,Vector2(48,31)),tint)
	canvas.draw_texture_rect_region(texture,Rect2(top+Vector2(0,31)+waist_shift,Vector2(48,7)),Rect2(source+Vector2(0,31),Vector2(48,7)),tint)
	canvas.draw_texture_rect_region(texture,Rect2(top+Vector2(0,38),Vector2(48,10)),Rect2(source+Vector2(0,38),Vector2(48,10)),tint)
