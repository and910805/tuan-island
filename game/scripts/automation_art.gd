extends RefCounted

const PATH:="res://assets/automation/atlas.png"
const ITEM_IDS:=["reinforced_pick","copper_ore","copper_joint","sprinkler_kit"]
const SPRAY_DURATION:=1.2
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

static func draw_sprinkler(canvas:CanvasItem,at:Vector2,obj:Dictionary,age:float,reduced_motion:bool,kind:="sprinkler",tint:=Color.WHITE) -> void:
	if not load_atlas():return
	var offset:=32 if int(obj.get("water",0))>0 else 0
	if kind=="large_sprinkler":
		canvas.draw_texture(preload("res://assets/automation/large-sprinkler.png"),at+Vector2(0,-16),tint)
	else:
		var finish:=Color("b1ddff") if kind=="medium_sprinkler" else Color.WHITE
		canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),Vector2(32,48)),Rect2(offset,32,32,48),finish*tint)
	if reduced_motion or age<0.0 or age>=SPRAY_DURATION:return
	var reach:=32.0 if kind!="large_sprinkler" else 57.0
	var directions:=[Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	if kind!="sprinkler":
		directions.append_array([Vector2(-0.7,-0.7),Vector2(0.7,-0.7),Vector2(-0.7,0.7),Vector2(0.7,0.7)])
	for direction:Vector2 in directions:
		var landing:=at+Vector2(16,16)+direction*reach
		for pulse in range(3):
			var progress:=(age-0.19*pulse)/0.64
			if progress<0.0:continue
			if progress<1.0:
				var position:=(at+Vector2(16,-4)).lerp(landing,progress)
				position.y-=sin(PI*progress)*17.0
				canvas.draw_texture_rect_region(atlas,Rect2(position.round()-Vector2(2,4),Vector2(4,7)),Rect2(107,65,9,13))
			elif progress<1.24:
				var splash:=(progress-1.0)/0.24
				var spread:=Vector2(roundf(2.0+4.0*splash),0)
				var color:=Color(0.61,0.89,1.0,1.0-splash)
				canvas.draw_rect(Rect2((landing-spread).round(),Vector2(2,1)),color)
				canvas.draw_rect(Rect2((landing+spread).round(),Vector2(2,1)),color)

static func draw_copper(canvas:CanvasItem,at:Vector2,ready:bool) -> void:
	if not load_atlas():return
	var color:=Color.WHITE if ready else Color("938f8f")
	canvas.draw_texture_rect_region(atlas,Rect2(at,Vector2(32,32)),Rect2(64,48,32,32),color)
