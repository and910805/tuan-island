extends RefCounted

const ATLAS_PATH:="res://assets/life-art/characters.png"
const FRAME_SIZE:=Vector2i(48,48)
const ATLAS_SIZE:=Vector2i(288,192)
const FOOT:=Vector2i(24,44)
var atlas:Texture2D
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

func draw_person(canvas:CanvasItem,foot:Vector2,shirt:Color,style:String,facing:Vector2i,phase:float,walking:bool,reduced_motion:bool) -> void:
	if atlas==null:return
	var frame:=frame_selection(style,facing,phase,walking,reduced_motion)
	var at:=foot.round()
	# 棉棉、阿潮、暖暖暫用米露、阿榆、小栗的圖格加染色以便區分；專用像素圖待做。
	var tint:Color={"mianmian":Color(0.80,0.92,1.0),"achao":Color(0.86,0.96,0.94),"nuannuan":Color(1.0,0.80,0.68),"luoluo":Color(1.0,0.93,0.72),"lingpopo":Color(0.86,0.82,0.92),"diandian":Color(0.84,0.96,0.82)}.get(style,Color.WHITE)
	canvas.draw_texture_rect_region(atlas,Rect2(at-Vector2(FOOT),Vector2(FRAME_SIZE)),Rect2(Vector2(frame*FRAME_SIZE),Vector2(FRAME_SIZE)),tint)
	if style=="guest":
		# Use a small ground-level color tag to identify guests without tinting sprite pixels.
		canvas.draw_rect(Rect2(at+Vector2(-4,3),Vector2(8,3)),Color("403d35"))
		canvas.draw_rect(Rect2(at+Vector2(-3,3),Vector2(6,2)),shirt)
