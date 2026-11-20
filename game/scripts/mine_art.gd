extends RefCounted
const TERRAIN=preload("res://assets/village-preview/terrain.png")
const FLOOR_ATLAS=preload("res://assets/mine/floor-atlas.png")
const CAVERN=preload("res://assets/mine/cavern.png")
const GOLD_SAMPLE=preload("res://assets/mine/gold-sample.png")
const PATH="res://assets/mine/props.png"
static var props:Texture2D
static var horizontal_track:Texture2D
static var rock_region:=Rect2()
const GOLD_ORE=preload("res://assets/mine/gold-ore.png")
const FREIGHT=preload("res://assets/mine/freight.png")
const MineLayout=preload("res://scripts/mine_layout.gd")
const CHAMBER := MineLayout.BASE_RECT
const ROUGH_EARTH := 6
const SIDE_FLOOR := [[5,4],[6,5],[6,4],[5,6],[11,6]]
const WALL_NORMALS := [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]
const MUD_PIXELS := [
	".....00000......","...001111100....","..01122222110...","..01223232210...","..01223232210...",
	".0122433342210..","012221212122210.","012211222112210.","012222222222210.","00111111111100..",
	"..0000000000....",
]
const MUD_COLORS := [Color("44322f"),Color("775043"),Color("aa7960"),Color("514137"),Color("e3a781")]

static func draw_mudling(canvas:CanvasItem,at:Vector2,seconds:float,reduced_motion:bool) -> void:
	var rise:=0 if reduced_motion else roundi(sin(seconds*2.6)*2.0)
	for y in MUD_PIXELS.size():
		var row:String=MUD_PIXELS[y]
		for x in row.length():
			if row[x]!=".":
				canvas.draw_rect(Rect2(at+Vector2(x*2,8+y*2+rise),Vector2(2,2)),MUD_COLORS[int(row[x])])
static var perimeters:Dictionary={}
const FLOOR_TINT := [
	Color("aaa09a"),Color("aaa4a0"),Color("909b9e"),Color("9f9287"),Color("8b8582"),
]
# Face depths in pixels, sampled from west to east or north to south.
const WALL_PROFILES := [
	[[54,66,46,34,55,44,37,62],[39,27,36,53,38,24,31],[48,34,57,31],[38,25,48,36]],
	[[67,76,61,48,75,71,54,65],[35,54,46,63,44,38,53],[62,49,39,62],[50,38,58,69]],
	[[51,40,58,61,42,69,76,54],[44,38,55,32,26,54,68],[45,52,35,52],[61,75,62,48]],
	[[49,43,47,41,50,45,52,43],[33,25,35,42,28,37,34],[46,36,45,32],[48,40,47,42]],
	[[77,55,80,69,92,75,63,86],[65,59,36,51,63,72,54],[75,63,48,71],[66,87,73,53]],
]
const SUPPORTS := [[14,22,36],[20,34],[17,27],[11,19,27,35],[14,32,36]]
const ROCK_TINT := [
	Color("b2a69b"),Color("a19792"),Color("8d9eaa"),Color("a9927d"),Color("a29a8b"),
]

## T067: B6–B15 reuse the B1–B5 art row named by the catalog layout_template
## (same cave shape as mine_layout.side_caves) and add a per-zone colour wash.
const ZONE_WASH := {"rust_vein":Color("e6b9a2"),"seep_geode":Color("b4cfd8"),"warm_rock":Color("eec08e"),"lantern_hall":Color("f3dfa4")}

static func art_index(depth:int) -> int:
	if depth<=FLOOR_TINT.size():return depth-1
	return int(preload("res://scripts/mine_expansion_catalog.gd").entry(depth).get("layout_template",1))-1

static func zone_wash(depth:int) -> Color:
	if depth<=FLOOR_TINT.size():return Color.WHITE
	return ZONE_WASH.get(preload("res://scripts/mine_expansion_catalog.gd").zone_of(depth),Color.WHITE)

static func ground(canvas:CanvasItem,at:Vector2,p:Vector2i,walkable:bool,depth:int) -> void:
	var tint:Color=FLOOR_TINT[art_index(depth)]*zone_wash(depth)
	if not walkable:
		var outside:=maxi(maxi(CHAMBER.position.x-p.x,p.x-CHAMBER.end.x+1),maxi(CHAMBER.position.y-p.y,p.y-CHAMBER.end.y+1))
		draw_tile(canvas,at,ROUGH_EARTH,tint.darkened(minf(0.58+outside*0.085,0.92)))
		return

	if not CHAMBER.has_point(p):
		var material:int=SIDE_FLOOR[art_index(depth)][1 if posmod(p.x*13+p.y*7,7)>4 else 0]
		var edge_count:=0
		for normal:Vector2i in WALL_NORMALS:
			if not MineLayout.land(p+normal,depth):edge_count+=1
		draw_tile(canvas,at,material,tint.darkened(0.10+edge_count*0.09))
		return

	var atlas_cell:=p-CHAMBER.position+Vector2i(0,art_index(depth)*CHAMBER.size.y)
	var region:=Rect2(Vector2(atlas_cell)*32,Vector2(32,32))
	canvas.draw_texture_rect_region(FLOOR_ATLAS,Rect2(at,Vector2(32,32)),region,zone_wash(depth))

static func draw_tile(canvas:CanvasItem,at:Vector2,index:int,tint:Color) -> void:
	var region:=Rect2((index%4)*32,floori(index/4.0)*32,32,32)
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),region,tint)

static func draw_track(canvas:CanvasItem,at:Vector2,p:Vector2i,depth:int) -> void:
	var horizontal:bool=(depth==4 and p.y==21 and p.x in range(13,38)) or (depth==5 and p.y==21 and p.x in range(29,36))
	var vertical:bool=depth==2 and p.x==18 and p.y in range(17,25)
	if horizontal:
		if horizontal_track==null:
			var sprite:=CAVERN.get_image().get_region(Rect2i(151,17,23,39))
			sprite.rotate_90(CLOCKWISE)
			horizontal_track=ImageTexture.create_from_image(sprite)
		canvas.draw_texture_rect(horizontal_track,Rect2(at+Vector2(0,5),Vector2(32,22)),false,Color("b8ad9e"))
	elif vertical:
		canvas.draw_texture_rect_region(CAVERN,Rect2(at+Vector2(5,0),Vector2(22,32)),Rect2(151,17,23,39),Color("b8ad9e"))

static func draw_perimeter(canvas:CanvasItem,origin:Vector2,depth:int,elapsed:float,reduced_motion:bool) -> void:
	if not perimeters.has(depth):perimeters[depth]=build_perimeter(depth)
	var perimeter:Dictionary=perimeters[depth]
	for piece:Dictionary in perimeter.pieces:
		var dest:Rect2=piece.dest
		dest.position+=origin
		canvas.draw_texture_rect_region(CAVERN,dest,piece.source,piece.tint)
	var light:=1.0 if reduced_motion else 1.0+sin(elapsed*1.7)*0.035
	for position:Vector2 in perimeter.supports:
		var at:=origin+position
		canvas.draw_texture_rect_region(CAVERN,Rect2(at,Vector2(64,64)),Rect2(64,0,64,64),Color(light,light,light))

static func build_perimeter(depth:int) -> Dictionary:
	var index:=art_index(depth)
	var tint:Color=ROCK_TINT[index]*zone_wash(depth)
	var extent:=MineLayout.bounds(depth)
	if not rock_region.has_area():rock_region=Rect2(CAVERN.get_image().get_region(Rect2i(0,0,64,64)).get_used_rect())
	var floor_rects:Array[Rect2i]=[CHAMBER]
	for span:Rect2i in MineLayout.side_caves(depth):
		floor_rects.append(span)
	var floor_pixels:Array[Rect2]=[]
	for rect:Rect2i in floor_rects:
		floor_pixels.append(Rect2(Vector2(rect.position)*32,Vector2(rect.size)*32))
	var pieces:Array[Dictionary]=[]
	for rear:bool in [true,false]:
		for side in range(4):
			var horizontal:=side<2
			var normal:Vector2i=WALL_NORMALS[side]
			var rows:=range(extent.position.y,extent.end.y) if horizontal else range(extent.position.x,extent.end.x)
			var first:=extent.position.x if horizontal else extent.position.y
			var last:=extent.end.x if horizontal else extent.end.y
			var band_tint:=tint.darkened(0.47 if rear else 0.07*side)
			for row:int in rows:
				var start:=first
				for column in range(first,last+1):
					var cell:=Vector2i(column,row) if horizontal else Vector2i(row,column)
					if column<last and MineLayout.land(cell,depth) and not MineLayout.land(cell+normal,depth):continue
					if column>start:
						var bounds:=Rect2(start*32,row*32,(column-start)*32,32) if horizontal else Rect2(row*32,start*32,32,(column-start)*32)
						add_wall_band(pieces,bounds,side,WALL_PROFILES[index][side],band_tint,rear,floor_pixels)
					start=column+1
	var supports:Array[Vector2]=[]
	for x:int in SUPPORTS[index]:
		var at:=Vector2(x,CHAMBER.position.y-2)*32
		var support:=Rect2(at,Vector2(64,64))
		if not floor_pixels.any(func(floor_rect:Rect2):return floor_rect.intersects(support)):
			supports.append(at)
	return {"pieces":pieces,"supports":supports}

static func add_wall_band(pieces:Array[Dictionary],bounds:Rect2,side:int,profile:Array,tint:Color,rear:bool,floor_pixels:Array[Rect2]) -> void:
	var horizontal:=side<2
	var length:=bounds.size.x if horizontal else bounds.size.y
	var start:=-43 if rear else -26
	var piece:=0
	while start<length+26:
		var width:=54+posmod(piece*17+side*7,29)
		var sample:=clampf((start+width*0.5)/length,0.0,1.0)*(profile.size()-1)
		var i:=floori(sample)
		var face:=roundi(lerpf(profile[i],profile[mini(i+1,profile.size()-1)],sample-i))
		var setback:=face-10 if rear else posmod(piece*11+side*3,10)
		var thickness:=44 if rear else face-setback
		var pos:=bounds.position
		match side:
			0:pos+=Vector2(start,-setback-thickness)
			1:pos+=Vector2(start,bounds.size.y+setback)
			2:pos+=Vector2(-setback-thickness,start)
			3:pos+=Vector2(bounds.size.x+setback,start)
		var size:=Vector2(width,thickness) if horizontal else Vector2(thickness,width)
		var shade:=0.05*posmod(piece*7+side,4)
		var mirror:=piece%2==0
		add_wall_piece(pieces,Rect2(pos,size),tint.darkened(shade),mirror,floor_pixels)
		start+=width-19
		piece+=1

static func add_wall_piece(pieces:Array[Dictionary],dest:Rect2,tint:Color,mirror:bool,floor_pixels:Array[Rect2]) -> void:
	# Overlap neighboring stones at corners, clipping the overhang against the floor plan.
	var fragments:Array[Rect2]=[dest]
	for floor_rect:Rect2 in floor_pixels:
		var remaining:Array[Rect2]=[]
		for fragment:Rect2 in fragments:
			var overlap:=fragment.intersection(floor_rect)
			if not overlap.has_area():
				remaining.append(fragment)
				continue
			if overlap.position.y>fragment.position.y:
				remaining.append(Rect2(fragment.position.x,fragment.position.y,fragment.size.x,overlap.position.y-fragment.position.y))
			if overlap.end.y<fragment.end.y:
				remaining.append(Rect2(fragment.position.x,overlap.end.y,fragment.size.x,fragment.end.y-overlap.end.y))
			if overlap.position.x>fragment.position.x:
				remaining.append(Rect2(fragment.position.x,overlap.position.y,overlap.position.x-fragment.position.x,overlap.size.y))
			if overlap.end.x<fragment.end.x:
				remaining.append(Rect2(overlap.end.x,overlap.position.y,fragment.end.x-overlap.end.x,overlap.size.y))
		fragments=remaining
	for fragment:Rect2 in fragments:
		var offset:=(fragment.position-dest.position)/dest.size
		var fraction:=fragment.size/dest.size
		if mirror:
			offset.x=1.0-offset.x-fraction.x
			fragment.size.x=-fragment.size.x
		var source:=Rect2(rock_region.position+offset*rock_region.size,fraction*rock_region.size)
		pieces.append({"dest":fragment,"source":source,"tint":tint})

static func draw_prop(canvas:CanvasItem,at:Vector2,index:int) -> void:
	if props==null and ResourceLoader.exists(PATH):props=load(PATH)
	if props==null:return
	canvas.draw_texture_rect_region(props,Rect2(at+Vector2(0,-8),Vector2(32,40)),Rect2(index*32,0,32,40))

## T067 hoist cage (升降台) for B6–B15. Code-drawn on the 32px grid; like draw_prop
## it occupies the tile at `at` and rises 8px above it (32×40 footprint).
static func draw_lift(canvas:CanvasItem,at:Vector2) -> void:
	var o:=at.floor()
	var wood:=Color("6b4a32")
	var wood_light:=Color("8a6342")
	var iron:=Color("7c807b")
	var iron_dark:=Color("4f5351")
	canvas.draw_rect(Rect2(o+Vector2(2,29),Vector2(28,3)),Color(0,0,0,0.28))
	# Headframe posts and beam.
	for x in [2,27]:
		canvas.draw_rect(Rect2(o+Vector2(x,-8),Vector2(3,38)),wood)
		canvas.draw_rect(Rect2(o+Vector2(x,-8),Vector2(1,38)),wood_light)
	canvas.draw_rect(Rect2(o+Vector2(1,-8),Vector2(30,4)),Color("5a3d29"))
	canvas.draw_rect(Rect2(o+Vector2(1,-8),Vector2(30,1)),wood_light)
	# Sheave wheel and cable.
	canvas.draw_rect(Rect2(o+Vector2(13,-7),Vector2(6,6)),Color("c9a15a"))
	canvas.draw_rect(Rect2(o+Vector2(15,-5),Vector2(2,2)),Color("4b3a2a"))
	canvas.draw_rect(Rect2(o+Vector2(15,-1),Vector2(2,6)),Color("d8cfb8"))
	# Cage: roof, side frame, bars, floor plate.
	canvas.draw_rect(Rect2(o+Vector2(7,5),Vector2(18,2)),Color("a3a6a0"))
	canvas.draw_rect(Rect2(o+Vector2(7,7),Vector2(18,19)),Color("2f2b2a"))
	canvas.draw_rect(Rect2(o+Vector2(7,7),Vector2(2,19)),iron)
	canvas.draw_rect(Rect2(o+Vector2(23,7),Vector2(2,19)),iron_dark)
	for x in [11,15,19]:
		canvas.draw_rect(Rect2(o+Vector2(x,7),Vector2(1,19)),iron)
	canvas.draw_rect(Rect2(o+Vector2(9,15),Vector2(14,1)),iron_dark)
	canvas.draw_rect(Rect2(o+Vector2(6,26),Vector2(20,3)),Color("4a4d4c"))
	canvas.draw_rect(Rect2(o+Vector2(6,26),Vector2(20,1)),Color("8d918c"))
	# Hanging lantern inside the cage.
	canvas.draw_rect(Rect2(o+Vector2(16,9),Vector2(2,3)),Color("ffd27a"))
	canvas.draw_rect(Rect2(o+Vector2(15,10),Vector2(4,1)),Color("f3b858",0.8))

static func draw_pool(canvas:CanvasItem,at:Vector2) -> void:
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),Rect2(32,64,32,32),Color("86acb5"))

static func ore_icon() -> Texture2D:
	return GOLD_ORE

static func freight_icon(kind:String) -> Texture2D:
	var icon:=AtlasTexture.new()
	icon.atlas=FREIGHT
	icon.region=Rect2(int({"cart":0,"loaded":1,"crate":2,"post":3}.get(kind,0))*32,0,32,32)
	return icon

static func draw_freight(canvas:CanvasItem,at:Vector2,kind:String,departure_age:float,reduced_motion:bool,extent:int=32) -> void:
	var frame:=int({"cart":0,"loaded":1,"crate":2,"post":3}.get(kind,0))
	if departure_age>=0.0 and departure_age<0.8:
		frame=4 if not reduced_motion and int(departure_age*12.0)%2==1 else 1
	canvas.draw_texture_rect_region(FREIGHT,Rect2(at,Vector2(extent,extent)),Rect2(frame*32,0,32,32))

static func refined_sample_icon() -> Texture2D:
	return GOLD_SAMPLE

static func draw_strike(canvas:CanvasItem,at:Vector2,age:float,reduced_motion:bool) -> void:
	var fade:=1.0-age/0.7
	var drift:=0.0 if reduced_motion else roundf(age*14.0)
	var tint:=Color(1,0.86,0.57,fade)
	for offset in [Vector2(4,9),Vector2(23,4),Vector2(27,15)]:
		canvas.draw_texture_rect_region(TERRAIN,Rect2(at+offset-Vector2(0,drift),Vector2(5,5)),Rect2(33,33,5,5),tint)
