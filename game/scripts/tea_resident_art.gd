@static_unload
extends RefCounted

const PORTRAITS:Texture2D=preload("res://assets/tea-ceramics/portraits.png")
const RESIDENTS:Texture2D=preload("res://assets/tea-ceramics/residents.png")
const COLUMNS:={"host":0,"potter":1}
const PORTRAIT_SIZE:=Vector2(64,64)
const RESIDENT_SIZE:=Vector2(32,48)
static var portraits:Dictionary={}
static var residents:Dictionary={}

static func clear_cache()->void:
	portraits.clear()
	residents.clear()

static func portrait(site:String)->Texture2D:
	return atlas_cell(portraits,PORTRAITS,site,PORTRAIT_SIZE)

static func draw_resident(canvas:CanvasItem,feet:Vector2,site:String)->void:
	var texture:=atlas_cell(residents,RESIDENTS,site,RESIDENT_SIZE)
	if texture:
		var top_left:=feet.round()-Vector2(RESIDENT_SIZE.x*0.5,RESIDENT_SIZE.y)
		canvas.draw_texture_rect(texture,Rect2(top_left,RESIDENT_SIZE),false)

static func atlas_cell(cache:Dictionary,sheet:Texture2D,site:String,cell_size:Vector2)->Texture2D:
	if cache.has(site):return cache[site]
	if not COLUMNS.has(site):return null
	var atlas:=AtlasTexture.new()
	atlas.atlas=sheet
	atlas.region=Rect2(Vector2(COLUMNS[site]*cell_size.x,0),cell_size)
	atlas.filter_clip=true
	cache[site]=atlas
	return atlas
