extends RefCounted

const PATH:="res://assets/logistics/atlas.png"
static var atlas:Texture2D
static var kit:AtlasTexture
static var belt_textures:Dictionary={}

static func load_atlas() -> bool:
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH) as Texture2D
	return atlas!=null

static func icon(id:String) -> Texture2D:
	if id!="conveyor_kit" or not load_atlas():return null
	if kit==null:
		kit=AtlasTexture.new()
		kit.atlas=atlas
		kit.region=Rect2(0,0,32,32)
		kit.filter_clip=true
	return kit

static func belt_texture(direction:int,frame:int) -> Texture2D:
	var key:=direction*3+frame
	if not belt_textures.has(key):
		var image:=atlas.get_image().get_region(Rect2i(32+frame*32,0,32,32))
		for turn in range(posmod(direction-1,4)):image.rotate_90(CLOCKWISE)
		belt_textures[key]=ImageTexture.create_from_image(image)
	return belt_textures[key]

static func draw_belt(canvas:CanvasItem,at:Vector2,obj:Dictionary,time:float,reduced_motion:bool,blocked:=false) -> void:
	if not load_atlas():return
	var direction:=posmod(int(obj.get("dir",1)),4)
	var frame:=posmod(floori(time*6.0),3) if obj.get("enabled",false) and not reduced_motion and not blocked else 0
	canvas.draw_texture(belt_texture(direction,frame),at)
	if blocked:
		canvas.draw_rect(Rect2(at+Vector2(24,3),Vector2(5,5)),Color("5b382a"))
		canvas.draw_rect(Rect2(at+Vector2(25,4),Vector2(3,3)),Color("f5aa58"))
