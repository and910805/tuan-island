extends RefCounted

# Display-only bakery art. Source PNGs are high resolution; every texture handed
# out here is rebuilt in memory at native pixel size (nearest-neighbour) so UI
# buttons and world drawing stay at 32px scale. No World preload to avoid cycles.
const GROWTH_PATH:="res://assets/bakery/pumpkin-growth.png"
const ITEMS_PATH:="res://assets/bakery/items.png"
const MILL_PATH:="res://assets/bakery/mill.png"
const VILLAGE_MILL_PATHS:=["res://assets/bakery/village-mill-south.png", "res://assets/bakery/village-mill-west.png", "res://assets/bakery/village-mill-north.png", "res://assets/bakery/village-mill-east.png"]
const GROWTH_CELL:=627
const ITEM_CELL:=512
# items.png: 2 columns x 3 rows of 512px cells. Cell (1,2) is unused decoration.
const ITEMS:={"pumpkin":Vector2i(0,0),"pumpkin_seed":Vector2i(1,0),"flour":Vector2i(0,1),"pumpkin_pie":Vector2i(1,1),"mill_kit":Vector2i(0,2)}
const MILL_SIZE:=Vector2i(32,48)
const ICON_SIZE:=Vector2i(32,32)
const MillFeedback=preload("res://scripts/mill_feedback.gd")
static var cache:Dictionary={}

static func source_image(path:String) -> Image:
	if not ResourceLoader.exists(path):return null
	var texture:=load(path) as Texture2D
	if texture==null:return null
	var image:=texture.get_image()
	if image==null or image.is_empty():return null
	if image.is_compressed():
		if image.decompress()!=OK:return null
	if image.get_format()!=Image.FORMAT_RGBA8:image.convert(Image.FORMAT_RGBA8)
	return image

static func native(key:String,path:String,region:Rect2i,size:Vector2i) -> Texture2D:
	if cache.has(key):return cache[key]
	var image:=source_image(path)
	if image==null:return null
	var bounds:=Rect2i(Vector2i.ZERO,image.get_size())
	if not bounds.encloses(region):return null
	var cell:=image.get_region(region)
	cell.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
	var texture:=ImageTexture.create_from_image(cell)
	texture.set_meta("source_png",path)
	cache[key]=texture
	return texture

static func icon(id:String) -> Texture2D:
	if id=="mill":return mill_texture()
	if not ITEMS.has(id):return null
	var at:Vector2i=ITEMS[id]
	return native("item:"+id,ITEMS_PATH,Rect2i(at*ITEM_CELL,Vector2i(ITEM_CELL,ITEM_CELL)),ICON_SIZE)

static func mill_texture() -> Texture2D:
	return native("mill",MILL_PATH,Rect2i(0,0,1024,1536),MILL_SIZE)

static func village_mill_texture(facing: int) -> Texture2D:
	var path: String = VILLAGE_MILL_PATHS[clampi(facing,0,VILLAGE_MILL_PATHS.size()-1)]
	if not cache.has(path):cache[path] = load(path) as Texture2D
	return cache[path]

# Stage 0 seed/sprout, 1 vine, 2 flower/unripe, 3 mature (2x2 grid, row-major).
static func growth_texture(stage:int) -> Texture2D:
	var s:=clampi(stage,0,3)
	var region:=Rect2i(Vector2i(s%2,s/2)*GROWTH_CELL,Vector2i(GROWTH_CELL,GROWTH_CELL))
	return native("growth:%d"%s,GROWTH_PATH,region,ICON_SIZE)

static func draw_crop(canvas:CanvasItem,at:Vector2,stage:int,tint:=Color.WHITE) -> bool:
	var texture:=growth_texture(stage)
	if texture==null:return false
	canvas.draw_texture_rect(texture,Rect2(at,Vector2(ICON_SIZE)),false,tint)
	return true

# Aligned like standard 32x48 furniture: footprint tile at `at`, sprite rises 16px above.
static func draw_mill(canvas:CanvasItem,at:Vector2) -> bool:
	var texture:=mill_texture()
	if texture==null:return false
	canvas.draw_texture_rect(texture,Rect2(at+Vector2(0,-16),Vector2(MILL_SIZE)),false)
	return true

static func mill_label_bounds(at:Vector2,facing:int) -> Rect2:
	var size:=Vector2(MILL_SIZE)
	if facing>=0:
		var texture:=village_mill_texture(facing)
		if texture!=null:size=texture.get_size()
	# The ready badge rises above the sprite and may extend one pixel to its right.
	return Rect2(at+Vector2(0,-24),size+Vector2(2,8))

# Runtime world drawing: the formal mill PNG first (same placement as draw_mill),
# then tiny overlays described by MillFeedback from the AUTHORITATIVE object
# snapshot at world time `world_time`; `clock` is the presentation clock. Reads
# only; never writes the snapshot. If the PNG is missing nothing is drawn (no
# geometric stand-in) but the classification is still returned for captions.
static func draw_mill_runtime(canvas:CanvasItem,at:Vector2,obj:Dictionary,world_time:float,clock:float,reduced:bool,facing:=-1,entry_visible:=false) -> Dictionary:
	var status:Dictionary=MillFeedback.classify(obj,world_time)
	var origin:=at+Vector2(0,-16)
	if facing < 0:
		if not draw_mill(canvas,at):return status
	else:
		var art := village_mill_texture(facing)
		if art == null:return status
		canvas.draw_texture(art,origin,Color(1,1,1,0.55) if entry_visible else Color.WHITE)
		origin.x += 32
	var look:Dictionary=MillFeedback.sample(status,clock,reduced)
	if not look.progress.is_empty():
		canvas.draw_rect(Rect2(origin+look.progress.track.position,look.progress.track.size),Color(0.18,0.12,0.08,0.82))
		if look.progress.fill.size.x>0:
			canvas.draw_rect(Rect2(origin+look.progress.fill.position,look.progress.fill.size),Color("f3e2b6"))
	for pixel in look.pixels:
		canvas.draw_rect(Rect2(origin+pixel.rect.position,pixel.rect.size),pixel.color)
	var flour:=icon("flour")
	for badge in look.badges:
		var box:Rect2=badge.rect
		box.position+=origin
		var manual:bool=badge.kind=="manual_ready"
		var edge:=Color("f2c14e") if manual else (Color("b4553a") if badge.full else Color("4a3426"))
		canvas.draw_rect(box.grow(1),edge)
		canvas.draw_rect(box,Color("fff4dc") if manual else Color("d9c7a3"))
		var product:Texture2D=flour
		if badge.get("item","")=="feed":product=load("res://scripts/inventory_item_art.gd").icon("feed")
		if product:canvas.draw_texture_rect(product,box.grow(-1),false)
		for index in mini(int(badge.count),MillFeedback.MAX_PIPS):
			canvas.draw_rect(Rect2(box.position+Vector2(index*3,box.size.y+2),Vector2(2,2)),edge)
	return status
