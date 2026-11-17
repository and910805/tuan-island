extends RefCounted
## First-stage presentation only. Never reads or writes a player's persistent data.
const World=preload("res://scripts/world.gd")
const Layout=preload("res://scripts/village_layout.gd")
const REGION:=Rect2i(25,19,36,44)
var tiles:Array[Image]=[]
var tile_textures:Array[ImageTexture]=[]
var props:Array[ImageTexture]=[]
var ground_cache:Dictionary={}
var decoration_cache:Dictionary={}

static func contains(p:Vector2i) -> bool:
	return REGION.has_point(p)

func setup() -> void:
	var terrain_texture:Texture2D=load("res://assets/village-preview/terrain.png")
	var props_texture:Texture2D=load("res://assets/village-preview/props.png")
	if terrain_texture==null or props_texture==null:return
	var terrain_image:=terrain_texture.get_image()
	var props_image:=props_texture.get_image()
	for i in range(16):
		var tile:=terrain_image.get_region(Rect2i((i%4)*32,(i/4)*32,32,32))
		tiles.append(tile)
		tile_textures.append(ImageTexture.create_from_image(tile))
		var prop:=props_image.get_region(Rect2i((i%4)*64,(i/4)*64,64,64))
		props.append(ImageTexture.create_from_image(prop.get_region(prop.get_used_rect())))

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
	return not World.land(p) or (p.x in [55,56] and not (built_bridge and p.y>=29 and p.y<=31))

func draw_tile(canvas:Node2D,at:Vector2,index:int,tint:=Color.WHITE) -> void:
	if tile_textures.size()==16:canvas.draw_texture(tile_textures[index],at,tint)

func draw_ground(canvas:Node2D,at:Vector2,p:Vector2i,data:Dictionary) -> void:
	if tiles.size()!=16:return
	var built_bridge:bool=data.get("board",false)
	var star_walk:=World.WANGAN_COAST.star_boardwalk(p) and bool(data.get("wangan_star_walk",false))
	var key:=Vector3i(p.x,p.y,int(built_bridge)+2*int(star_walk))
	var terrain:ImageTexture=ground_cache.get(key)
	if terrain==null:
		terrain=ImageTexture.create_from_image(compose_ground(p,built_bridge,star_walk))
		ground_cache[key]=terrain
	canvas.draw_texture(terrain,at)
	if not decoration_cache.has(p):decoration_cache[p]=decoration_index(p)
	var prop:int=decoration_cache[p]
	if prop<0:return
	var k:=World.key(p)
	if data.ground.has(k) or data.crops.has(k) or data.objects.has(k) or data.get("forest",{}).has(k):return
	draw_prop(canvas,at,prop,0.5)

static func decoration_index(p:Vector2i) -> int:
	if not World.land(p) or p.x in [55,56] or World.base_resource(p)!="":return -1
	if p in [Vector2i(40,29),Vector2i(43,29),Vector2i(38,29),Vector2i(44,31),Vector2i(45,34)]:return -1
	var center:=Vector2(p)+Vector2(0.5,0.5)
	if path_at(center):return -1
	var hash_value:=absi(p.x*197+p.y*73+p.x*p.y*17)
	# Flat flowers can be walked through. Never add fake walls to a buildable cell.
	if hash_value%9==0 or (p.y==27 and p.x in [35,36,45,46]):return 5
	if hash_value%7==0 and coast_distance(p)<=2:return 14
	return -1

func compose_ground(p:Vector2i,built_bridge:bool,star_walk:=false) -> Image:
	var result:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	var wet:=wet_at(p,built_bridge)
	var coast:=coast_distance(p)
	var boardwalk:=not wet and (star_walk or World.WANGAN_COAST.boardwalk(p) or World.WANGAN_COAST.ferry_walk(p))
	var shore_left:=wet and not wet_at(p+Vector2i.LEFT,built_bridge)
	var shore_right:=wet and not wet_at(p+Vector2i.RIGHT,built_bridge)
	var shore_up:=wet and not wet_at(p+Vector2i.UP,built_bridge)
	var shore_down:=wet and not wet_at(p+Vector2i.DOWN,built_bridge)
	var shore_cells:Array[Vector2i]=[]
	if not wet and coast<4:
		for dy in range(-3,4):
			for dx in range(-3,4):
				var neighbor:=p+Vector2i(dx,dy)
				if not World.land(neighbor):shore_cells.append(neighbor)
	for y in range(32):
		for x in range(32):
			var world_point:=Vector2(p)+Vector2(x,y)/32.0
			var index:=0
			if wet:
				index=8
				# Shallow band and foam stay strictly on non-walkable water cells.
				var edge:=6+int(sin((p.x*32+x+p.y*32+y)*0.7)*2)
				var shore:=(shore_left and x<edge) or (shore_right and x>31-edge) or (shore_up and y<edge) or (shore_down and y>31-edge)
				if shore:index=9
			elif p.x in [55,56] and built_bridge:
				index=10
			elif path_at(world_point):
				index=4
			else:
				# Blend meadow varieties in broad patches, without square tile bands.
				var patch:=sin(world_point.x*0.43)+cos(world_point.y*0.37)
				index=0 if patch>0.2 else 1
				if patch>1.45:index=3
				if coast==3 and sin(world_point.x*2.2+world_point.y*1.6)>0.4:index=2
			if not wet and not shore_cells.is_empty():
				var distance:=4.0
				for water_cell in shore_cells:
					var delta:=(world_point-Vector2(water_cell)-Vector2(0.5,0.5)).abs()-Vector2(0.5,0.5)
					distance=minf(distance,Vector2(maxf(delta.x,0),maxf(delta.y,0)).length())
				if distance<1.5+noise_at(world_point)*1.5:index=5
			if boardwalk:index=10
			var color:=tiles[index].get_pixel(x,y)
			# Feather the review area's perimeter into untouched 0.5 terrain.
			var border:=minf(minf(world_point.x-REGION.position.x,REGION.end.x-world_point.x),minf(world_point.y-REGION.position.y,REGION.end.y-world_point.y))
			if border<2.0:
				var old_color:=Color("76b9b4") if (p.x+p.y)%3==0 else Color("7fc3ba")
				if not wet:old_color=Color("a8c88b") if absi(p.x*7127+p.y*19391)%3==0 else Color("acce8d")
				color=old_color.lerp(color,clampf(border/2.0,0,1))
			result.set_pixel(x,y,color)
	return result

func draw_coastal_prop(canvas:Node2D,at:Vector2,p:Vector2i) -> void:
	if p==Vector2i(51,59) and not World.land(p):draw_prop(canvas,at,13)
	if p==Vector2i(55,32):draw_prop(canvas,at,13,0.8)

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
