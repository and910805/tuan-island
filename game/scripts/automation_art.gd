extends RefCounted

const PATH:="res://assets/automation/atlas.png"
const ITEM_IDS:=["reinforced_pick","copper_ore","copper_joint","sprinkler_kit"]
static var atlas:Texture2D
static var icons:Dictionary={}

static func load_atlas() -> bool:
	if atlas==null and ResourceLoader.exists(PATH):
		atlas=load(PATH) as Texture2D
	return atlas!=null

static func icon(id:String) -> Texture2D:
	if icons.has(id):return icons[id]
	var column:=ITEM_IDS.find(id)
	if column<0 or not load_atlas():return null
	var entry:=AtlasTexture.new()
	entry.atlas=atlas
	entry.region=Rect2(column*32,0,32,32)
	entry.filter_clip=true
	icons[id]=entry
	return entry

static func draw_sprinkler(canvas:CanvasItem,at:Vector2,obj:Dictionary,time:float,reduced_motion:bool,medium:=false) -> void:
	if not load_atlas():return
	var offset:=32 if int(obj.get("water",0))>0 else 0
	var tint:=Color("b1ddff") if medium else Color.WHITE
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),Vector2(32,48)),Rect2(offset,32,32,48),tint)
	var last:=float(obj.get("last_water",-1))
	var age:=time-last
	if last<0 or age<0 or age>=0.7:return
	var step:=0 if reduced_motion else mini(2,floori(age*5.0))
	var drop:=Rect2(107,65,9,13)
	for sign_x in [-1,1]:
		var position:=at+Vector2(12+sign_x*(11+step*3),-9+step*4)
		canvas.draw_texture_rect_region(atlas,Rect2(position,Vector2(6,10)),drop)

static func draw_copper(canvas:CanvasItem,at:Vector2,ready:bool) -> void:
	if not load_atlas():return
	var color:=Color.WHITE if ready else Color("938f8f")
	canvas.draw_texture_rect_region(atlas,Rect2(at,Vector2(32,32)),Rect2(64,48,32,32),color)
