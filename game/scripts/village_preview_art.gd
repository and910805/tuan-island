extends RefCounted
## Illustrated home terrain and props. Presentation only.
const World=preload("res://scripts/world.gd")
const Layout=preload("res://scripts/village_layout.gd")
const REGION:=Rect2i(Vector2i.ZERO,World.SIZE)
const SHORE_BOUNDS:=Rect2i(-1,-1,World.SIZE.x+2,World.SIZE.y+2)
const PATH_BOUNDS:=Rect2i(34,27,24,25)
const SIDES:=[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
const CHUNK_TILES:=16
const CHUNK_DIRECTORY:="res://assets/village-preview/terrain-chunks"
const PREFETCH_TILES:=5
const COASTAL_PROP_CELLS:=[Vector2i(51,59),Vector2i(55,32)]
var tiles:Array[Image]=[]
var tile_textures:Array[ImageTexture]=[]
var props:Array[ImageTexture]=[]
var ground_cache:Dictionary={}
static var decoration_rows:Dictionary[int,PackedByteArray]={}
var chunks:Dictionary={}
var pending_chunks:Dictionary={}
var unavailable_chunks:Dictionary={}
var use_chunks:=true
var visible_base_complete:=false

static func contains(p:Vector2i) -> bool:
	return REGION.has_point(p)

func setup() -> bool:
	# The headless dummy renderer cannot initialize textures from two threads.
	if DisplayServer.get_name()=="headless":use_chunks=false
	var terrain_texture:Texture2D=load("res://assets/village-preview/terrain.png")
	var props_texture:Texture2D=load("res://assets/village-preview/props.png")
	if terrain_texture==null or props_texture==null:return false
	var terrain_image:=terrain_texture.get_image()
	var props_image:=props_texture.get_image()
	if terrain_image.get_size()!=Vector2i(128,128) or props_image.get_size()!=Vector2i(256,256):return false
	for i in range(16):
		var tile:=terrain_image.get_region(Rect2i((i%4)*32,(i/4)*32,32,32))
		tiles.append(tile)
		tile_textures.append(ImageTexture.create_from_image(tile))
		var prop:=props_image.get_region(Rect2i((i%4)*64,(i/4)*64,64,64))
		props.append(ImageTexture.create_from_image(prop.get_region(prop.get_used_rect())))
	return true

static func noise_at(p:Vector2) -> float:
	return sin(p.x*4.3+p.y*1.7)*0.13+sin(p.x*1.1-p.y*3.4)*0.12

static func path_at(p:Vector2) -> bool:
	return Layout.path_at(p)

static func coast_distance(p:Vector2i) -> int:
	for radius in range(1,4):
		for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if not World.land(p+direction*radius):return radius
	return 4

static func wet_at(p:Vector2i,built_bridge:bool) -> bool:
	return World.home_water(p,built_bridge)

func draw_tile(canvas:Node2D,at:Vector2,index:int,tint:=Color.WHITE) -> void:
	if tile_textures.size()==16:canvas.draw_texture(tile_textures[index],at,tint)

func draw_terrain_tile(canvas:Node2D,at:Vector2,p:Vector2i,built_bridge:bool,star_walk:bool) -> void:
	if tiles.size()!=16:return
	if not SHORE_BOUNDS.has_point(p):
		draw_tile(canvas,at,8)
		return
	var key:=Vector3i(p.x,p.y,int(built_bridge and bridge_variant(p))+2*int(star_walk))
	var terrain:ImageTexture=ground_cache.get(key)
	if terrain==null:
		var wet:=wet_at(p,built_bridge)
		if wet and not borders_land(p,built_bridge):
			terrain=tile_textures[8]
		elif not wet and on_planks(p,star_walk):
			terrain=tile_textures[10]
		else:
			terrain=ImageTexture.create_from_image(compose_ground(p,built_bridge,star_walk))
		ground_cache[key]=terrain
	canvas.draw_texture(terrain,at)

static func bridge_variant(cell:Vector2i) -> bool:
	return Rect2i(54,28,4,5).has_point(cell)

static func chunk_at(cell:Vector2i) -> Vector2i:
	var offset:=cell-SHORE_BOUNDS.position
	return Vector2i(floori(float(offset.x)/CHUNK_TILES),floori(float(offset.y)/CHUNK_TILES))

static func chunk_cells(chunk:Vector2i) -> Rect2i:
	return SHORE_BOUNDS.intersection(Rect2i(SHORE_BOUNDS.position+chunk*CHUNK_TILES,Vector2i.ONE*CHUNK_TILES))

static func chunk_path(chunk:Vector2i) -> String:
	return "%s/%d-%d.png"%[CHUNK_DIRECTORY,chunk.x,chunk.y]

static func chunk_span(tiles_rect:Rect2i) -> Rect2i:
	var land:=tiles_rect.intersection(SHORE_BOUNDS)
	if not land.has_area():return Rect2i()
	var first:=chunk_at(land.position)
	var last:=chunk_at(land.end-Vector2i.ONE)
	return Rect2i(first,last-first+Vector2i.ONE)

func _collect_chunks(retention:Rect2i) -> void:
	for chunk:Vector2i in chunks.keys():
		if not retention.has_point(chunk):chunks.erase(chunk)
	for chunk:Vector2i in pending_chunks.keys():
		var path:String=pending_chunks[chunk]
		var status:=ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
		pending_chunks.erase(chunk)
		var texture:Texture2D
		if status!=ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			texture=ResourceLoader.load_threaded_get(path) as Texture2D
		if texture==null:
			unavailable_chunks[chunk]=true
		elif retention.has_point(chunk):
			chunks[chunk]=texture

func _request_chunks(span:Rect2i) -> void:
	for y in range(span.position.y,span.end.y):
		for x in range(span.position.x,span.end.x):
			var chunk:=Vector2i(x,y)
			if chunks.has(chunk) or pending_chunks.has(chunk) or unavailable_chunks.has(chunk):continue
			var path:=chunk_path(chunk)
			if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path,"Texture2D")==OK:
				pending_chunks[chunk]=path
			else:
				unavailable_chunks[chunk]=true

func release_chunks() -> void:
	_collect_chunks(Rect2i())

func finish_chunk_loads() -> void:
	# Each accepted request must be retrieved before this view is freed.
	for path:String in pending_chunks.values():
		if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	pending_chunks.clear()
	chunks.clear()

func draw_base(canvas:Node2D,camera:Vector2,visible:Rect2i) -> bool:
	if not use_chunks:
		release_chunks()
		return false
	var active:=chunk_span(visible)
	var ahead:=chunk_span(visible.grow(PREFETCH_TILES))
	_collect_chunks(active.grow(1) if active.has_area() else ahead)
	_request_chunks(active)
	_request_chunks(ahead)
	visible_base_complete=true
	var extent:=Vector2(visible.size*32)
	canvas.draw_texture_rect(tile_textures[8],Rect2(Vector2(visible.position*32)-camera,extent),true)
	for y in range(active.position.y,active.end.y):
		for x in range(active.position.x,active.end.x):
			var chunk:=Vector2i(x,y)
			if not chunks.has(chunk):
				visible_base_complete=false
				continue
			var cells:=chunk_cells(chunk)
			canvas.draw_texture(chunks[chunk],Vector2(cells.position*32)-camera)
	return true

func has_base_tile(cell:Vector2i) -> bool:
	return not SHORE_BOUNDS.has_point(cell) or chunks.has(chunk_at(cell))

## Offset the prop index by one so empty cells use zero.
static func ground_decoration_row(y:int) -> PackedByteArray:
	if y<SHORE_BOUNDS.position.y or y>=SHORE_BOUNDS.end.y:return PackedByteArray()
	if not decoration_rows.has(y):
		var row:=PackedByteArray()
		row.resize(SHORE_BOUNDS.size.x)
		for index in row.size():
			row[index]=decoration_index(Vector2i(SHORE_BOUNDS.position.x+index,y))+1
		decoration_rows[y]=row
	return decoration_rows[y]

static func borders_land(p:Vector2i,built_bridge:bool) -> bool:
	for side:Vector2i in SIDES:
		if not wet_at(p+side,built_bridge):return true
	return false

static func on_planks(p:Vector2i,star_walk:bool) -> bool:
	return p.x in [55,56] or star_walk or World.WANGAN_COAST.boardwalk(p) or World.WANGAN_COAST.ferry_walk(p)

static func decoration_index(p:Vector2i) -> int:
	if not World.land(p) or World.WANGAN_COAST.STAR_POOL.has_point(p) or on_planks(p,World.WANGAN_COAST.star_boardwalk(p)) or World.base_resource(p)!="":return -1
	if p in [Vector2i(40,29),Vector2i(43,29),Vector2i(38,29),Vector2i(44,31),Vector2i(45,34)]:return -1
	var center:=Vector2(p)+Vector2(0.5,0.5)
	if path_at(center):return -1
	var hash_value:=absi(p.x*197+p.y*73+p.x*p.y*17)
	# Flat flowers can be walked through. Never add fake walls to a buildable cell.
	if hash_value%9==0 or (p.y==27 and p.x in [35,36,45,46]):return 5
	if hash_value%7==0 and coast_distance(p)<=2:return 14
	return -1

func compose_ground(p:Vector2i,built_bridge:bool,star_walk:=false) -> Image:
	var wet:=wet_at(p,built_bridge)
	if wet and not borders_land(p,built_bridge):return tiles[8].duplicate()
	if not wet and on_planks(p,star_walk):return tiles[10].duplicate()
	var result:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	var coast:=4 if wet else coast_distance(p)
	var near_path:=PATH_BOUNDS.has_point(p)
	var shore_left:=wet and not wet_at(p+Vector2i.LEFT,built_bridge)
	var shore_right:=wet and not wet_at(p+Vector2i.RIGHT,built_bridge)
	var shore_up:=wet and not wet_at(p+Vector2i.UP,built_bridge)
	var shore_down:=wet and not wet_at(p+Vector2i.DOWN,built_bridge)
	var shore_cells:Array[Vector2i]=[]
	if not wet and coast<4:
		for dy in range(-2,3):
			for dx in range(-2,3):
				var neighbor:=p+Vector2i(dx,dy)
				if not World.land(neighbor):shore_cells.append(neighbor)
	for y in range(32):
		var world_y:=float(p.y)+float(y)/32.0
		var meadow_y:=cos(world_y*0.37)
		for x in range(32):
			var world_point:=Vector2(float(p.x)+float(x)/32.0,world_y)
			var color:Color
			if wet:
				# Shallow band and foam stay strictly on non-walkable water cells.
				var edge:=6+int(sin((p.x*32+x+p.y*32+y)*0.7)*2)
				var shore:=(shore_left and x<edge) or (shore_right and x>31-edge) or (shore_up and y<edge) or (shore_down and y>31-edge)
				color=tiles[9 if shore else 8].get_pixel(x,y)
			elif near_path and path_at(world_point):
				color=tiles[4].get_pixel(x,y)
			elif coast==3 and sin(world_point.x*2.2+world_point.y*1.6)>0.4:
				color=tiles[2].get_pixel(x,y)
			else:
				var patch:=sin(world_point.x*0.43)+meadow_y
				if patch<0.58:
					color=tiles[1].get_pixel(x,y)
					if patch>-0.20:color=color.lerp(tiles[0].get_pixel(x,y),smoothstep(-0.20,0.58,patch))
				else:
					color=tiles[0].get_pixel(x,y)
					if patch>1.19:color=color.lerp(tiles[3].get_pixel(x,y),smoothstep(1.19,1.71,patch))
			if not wet and not shore_cells.is_empty():
				var distance:=4.0
				for water_cell in shore_cells:
					var delta:=(world_point-Vector2(water_cell)-Vector2(0.5,0.5)).abs()-Vector2(0.5,0.5)
					distance=minf(distance,Vector2(maxf(delta.x,0),maxf(delta.y,0)).length())
				if distance<1.5+noise_at(world_point)*1.5:color=tiles[5].get_pixel(x,y)
			result.set_pixel(x,y,color)
	return result

func draw_coastal_prop(canvas:Node2D,at:Vector2,p:Vector2i) -> void:
	if p==COASTAL_PROP_CELLS[0] and not World.land(p):draw_prop(canvas,at,13)
	if p==COASTAL_PROP_CELLS[1]:draw_prop(canvas,at,13,0.8)

func draw_tree(canvas:Node2D,at:Vector2,p:Vector2i) -> void:
	var kind:=absi(p.x*17+p.y*31)%4
	draw_prop(canvas,at,kind)

func draw_shop_occluders(canvas:Node2D,at:Vector2) -> void:
	if props.size()!=16:return
	var texture:=props[8]
	var size:=Vector2(texture.get_size())
	var origin:=(at+Vector2(16-size.x/2,29-size.y)).round()
	var canopy:=floorf(size.y*0.25)
	var counter:=floorf(size.y*0.59)
	canvas.draw_texture_rect_region(texture,Rect2(origin,Vector2(size.x,canopy)),Rect2(Vector2.ZERO,Vector2(size.x,canopy)))
	canvas.draw_texture_rect_region(texture,Rect2(origin+Vector2(0,counter),Vector2(size.x,size.y-counter)),Rect2(Vector2(0,counter),Vector2(size.x,size.y-counter)))

func draw_prop(canvas:Node2D,at:Vector2,index:int,scale_value:=1.0) -> void:
	if props.size()!=16:return
	var texture:=props[index]
	var size:=Vector2(texture.get_size())*scale_value
	var pos:=(at+Vector2(16-size.x/2,29-size.y)).round()
	canvas.draw_texture_rect(texture,Rect2(pos,size),false)
