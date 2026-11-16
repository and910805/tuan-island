@static_unload
extends RefCounted
## Tianwei cooperative flower nursery world scene (display only).
## Static drawing helpers used by world_view.gd's tianwei branch. Everything is
## composed from already-delivered formal art: village-preview terrain/props,
## tea-ceramics building sheet (green-roof shed), FlowerSceneArt props/market,
## FlowerResidentArt (A-Lei), FlowerArt crop growth sheet and the Lanyang
## gardener (星禾). No new assets and no geometric stand-ins for furniture.
## Geometry comes from FlowerNursery; nothing here changes collision or routing.

const Flower=preload("res://scripts/flower_nursery.gd")
const SceneArt=preload("res://scripts/flower_scene_art.gd")
const ResidentArt=preload("res://scripts/flower_resident_art.gd")
const FlowerArt=preload("res://scripts/flower_art.gd")
const LanyangLifeArt=preload("res://scripts/lanyang_life_art.gd")
const Terrain=preload("res://assets/village-preview/terrain.png")
const Props=preload("res://assets/village-preview/props.png")
const BuildingsPath:="res://assets/tea-ceramics/buildings.png"

## Interaction sites in the same order main.gd merges FlowerUI.interaction_points.
const SITES:=["farmer","seed","dye","market","garden","xinghe"]
const SITE_LABELS:={"farmer":"阿蕾","seed":"留種台","dye":"染色桌","market":"花卉市集","garden":"公共花園","xinghe":"星禾","transfer":"花圃接駁點"}
const RESIDENT_SITES:=["farmer","xinghe"]
const RADIUS:=3.2

## Paths (cells inside LAND): the arrival lane, the station walk and two links.
const MAIN_LANE:=Rect2i(8,26,34,1)
const STATION_WALK:=Rect2i(15,19,22,1)
const WEST_LINK:=Rect2i(15,19,1,8)
const EAST_LINK:=Rect2i(34,19,1,8)
## Gravel apron around the beds and the garden.
const BED_APRON:=Rect2i(17,21,10,5)
const GARDEN_APRON:=Rect2i(35,22,5,4)
## Static decorative props: [cell, village props index]. Cells are free ground
## near the edges, never station/bed/garden/path cells.
const DECOR:=[
	[Vector2i(9,13),4],[Vector2i(12,13),5],[Vector2i(29,13),4],[Vector2i(33,13),5],[Vector2i(37,13),4],[Vector2i(40,14),7],
	[Vector2i(9,20),5],[Vector2i(10,23),4],[Vector2i(28,23),5],[Vector2i(29,28),7],[Vector2i(24,28),4],
	[Vector2i(40,20),4],[Vector2i(40,28),5],[Vector2i(18,28),5],
	[Vector2i(33,24),10],
]
## Tree line just outside the land, read as the windbreak around the nursery.
const TREES:=[Vector2i(9,11),Vector2i(14,11),Vector2i(20,11),Vector2i(27,11),Vector2i(31,11),Vector2i(36,11),Vector2i(41,11),
	Vector2i(7,15),Vector2i(7,20),Vector2i(42,16),Vector2i(42,22)]

static var buildings:Texture2D

## Float centre column of the 3-wide garden (Rect2i.get_center() rounds down).
static func garden_mid()->float:
	return Flower.GARDEN.position.x+Flower.GARDEN.size.x/2.0

## Low hedge along the non-walkable ring around LAND (bottom row and both sides).
static func hedge_row(canvas:CanvasItem,origin:Vector2,y:int)->void:
	var left:=Flower.LAND.position.x-1
	var right:=Flower.LAND.end.x
	if y==Flower.LAND.end.y:
		for x in range(left,right+1,2):prop(canvas,origin+Vector2(x,y)*32,[5,7,4][absi(x)%3],0.7)
	elif y>=Flower.LAND.position.y and y<Flower.LAND.end.y and y%2==0:
		for x in [left,right]:
			if Vector2i(x,y) in TREES:continue
			prop(canvas,origin+Vector2(x,y)*32,[7,5][absi(y/2)%2],0.7)

static func site_cell(site:String)->Vector2i:
	match site:
		"farmer":return Flower.FARMER
		"seed":return Flower.SEED_TABLE
		"dye":return Flower.DYE_TABLE
		"market":return Flower.MARKET
		"garden":return Flower.GARDEN_CELL
		"xinghe":return Flower.XINGHE
		"transfer":return Flower.TRANSFER
	return Vector2i(-1,-1)

## Same rule as main.gd _interact for tianwei: flower sites first, then transit
## stops, then interactive objects; strict nearest within 3.2 tiles.
static func focus(position:Vector2,transit_points:Dictionary,objects:Dictionary,object_types:Array)->String:
	var points:Dictionary={}
	for site in SITES:points["flower:"+site]=Vector2(site_cell(site))+Vector2(0.5,0.5)
	for gate in transit_points:points["transit:"+str(gate)]=Vector2(transit_points[gate].cell)+Vector2(0.5,0.5)
	for key in objects:
		if objects[key].get("type","") in object_types:
			var parts:=str(key).split(",")
			if parts.size()==2:points[key]=Vector2(int(parts[0]),int(parts[1]))+Vector2(0.5,0.5)
	var closest:=""
	var distance:=RADIUS
	for key in points:
		var candidate:=position.distance_to(points[key])
		if candidate<distance:
			distance=candidate
			closest=key
	return closest

static func garden_complete(data:Dictionary)->bool:
	var nursery=data.get("flower_nursery",{})
	if not nursery is Dictionary:return false
	var garden=nursery.get("garden",{})
	return garden is Dictionary and bool(garden.get("complete",false))

static func own_record(data:Dictionary)->Dictionary:
	var nursery=data.get("flower_nursery",{})
	if not nursery is Dictionary:return {}
	var own=nursery.get("own",{})
	if not own is Dictionary:return {}
	var record=own.get("own_record",{})
	return record if record is Dictionary else {}

# ---------------------------------------------------------------- ground

static func terrain(canvas:CanvasItem,at:Vector2,index:int,tint:=Color.WHITE)->void:
	canvas.draw_texture_rect_region(Terrain,Rect2(at,Vector2(32,32)),Rect2((index%4)*32,(index>>2)*32,32,32),tint)

static func path_cell(p:Vector2i)->bool:
	return MAIN_LANE.has_point(p) or STATION_WALK.has_point(p) or WEST_LINK.has_point(p) or EAST_LINK.has_point(p)

## One ground cell. `land` = FlowerNursery.land(p) (walkable area).
static func ground(canvas:CanvasItem,at:Vector2,p:Vector2i,land:bool)->void:
	var h:=absi(p.x*7127+p.y*19391)
	if not land:
		# Neighbouring flower fields beyond the windbreak hedge: not walkable.
		var ring:=Rect2i(Flower.LAND.position-Vector2i.ONE,Flower.LAND.size+Vector2i(2,2)).has_point(p)
		if ring:
			terrain(canvas,at,13,Color("8fa874"))
		elif p.y>Flower.LAND.end.y:
			terrain(canvas,at,15 if p.y%2==0 else 12,Color("c9b48f") if p.y%2==0 else Color("d6dcb0"))
		else:
			terrain(canvas,at,1 if h%3 else 13,Color("a9b98a"))
		return
	if Flower.NURSERY_BEDS.has_point(p):
		terrain(canvas,at,15,Color("e8cfae"))
		return
	if Flower.GARDEN.has_point(p):
		terrain(canvas,at,6,Color("d8c0a0"))
		return
	if Flower.SHED.has_point(p):
		terrain(canvas,at,10,Color("d9c3a3"))
		return
	if path_cell(p):
		terrain(canvas,at,11 if p.y==MAIN_LANE.position.y else 4,Color("efdcc0") if p.y==MAIN_LANE.position.y else Color("f0d6b4"))
		return
	if BED_APRON.has_point(p) or GARDEN_APRON.has_point(p) or (p.y in [17,18] and p.x>=18 and p.x<=35):
		terrain(canvas,at,14,Color("f2e3c8"))
		return
	var index:=0 if h%5 else 3
	if h%11==0:index=12
	terrain(canvas,at,index,Color("f4f0d6"))

# ---------------------------------------------------------------- props

static func prop(canvas:CanvasItem,at:Vector2,index:int,scale_value:=1.0)->void:
	var size:=Vector2(64,64)*scale_value
	var pos:=(at+Vector2(16-size.x/2,29-size.y)).round()
	canvas.draw_texture_rect_region(Props,Rect2(pos,size),Rect2((index%4)*64,(index>>2)*64,64,64))

## Draws a FlowerSceneArt prop with its bottom-centre anchor on the cell feet.
static func scene_prop(canvas:CanvasItem,feet:Vector2,id:String)->void:
	var texture:=SceneArt.prop_texture(id)
	if texture==null:return
	var anchor:=Vector2(SceneArt.prop_anchor(id))
	canvas.draw_texture(texture,(feet-anchor).round())

static func shed(canvas:CanvasItem,origin:Vector2)->void:
	# Green-roof potting shed from the delivered tea-ceramics building sheet
	# (seedling trays on the porch), plus storage props on the rest of SHED.
	if buildings==null and ResourceLoader.exists(BuildingsPath):buildings=load(BuildingsPath) as Texture2D
	var base:=origin+Vector2(Flower.SHED.position)*32
	if buildings:canvas.draw_texture_rect_region(buildings,Rect2(base+Vector2(0,-36),Vector2(128,128)),Rect2(0,0,128,128))
	prop(canvas,base+Vector2(4.5,2)*32,10)
	prop(canvas,base+Vector2(6.5,2)*32,11)

## Tall props and residents that sit on row `y`, in feet order. Returns the
## labels to place as [anchor, site] pairs.
static func draw_row(canvas:CanvasItem,origin:Vector2,y:int,data:Dictionary,elapsed:float,reduced_motion:bool)->Array:
	var labels:Array=[]
	for tree in TREES:
		if tree.y==y:prop(canvas,origin+Vector2(tree)*32,[0,2,0,1][absi(tree.x)%4])
	for item in DECOR:
		if item[0].y==y:prop(canvas,origin+Vector2(item[0])*32,item[1],0.75)
	if y==Flower.SHED.end.y-1:shed(canvas,origin)
	hedge_row(canvas,origin,y)
	var feet_of:=func(cell:Vector2i)->Vector2:return origin+Vector2(cell)*32+Vector2(16,30)
	if y==Flower.TRANSFER.y:
		scene_prop(canvas,feet_of.call(Flower.TRANSFER)+Vector2(-12,0),"nursery_shuttle_shelter")
		labels.append([feet_of.call(Flower.TRANSFER)+Vector2(0,-74),"transfer"])
	if y==Flower.FARMER.y:
		var alei:=ResidentArt.resident_texture()
		var feet:Vector2=feet_of.call(Flower.FARMER)
		if alei:canvas.draw_texture(alei,(feet-Vector2(ResidentArt.RESIDENT_FEET)).round())
		labels.append([feet+Vector2(0,-50),"farmer"])
	if y==Flower.SEED_TABLE.y:
		var feet:Vector2=feet_of.call(Flower.SEED_TABLE)
		scene_prop(canvas,feet,"seed_saving_table")
		job_icon(canvas,feet+Vector2(14,-62),own_record(data).get("saving",{}),data)
		labels.append([feet+Vector2(0,-58),"seed"])
	if y==Flower.DYE_TABLE.y:
		var feet:Vector2=feet_of.call(Flower.DYE_TABLE)
		scene_prop(canvas,feet,"dye_table")
		job_icon(canvas,feet+Vector2(14,-62),own_record(data).get("dyeing",{}),data,"blue_dye")
		labels.append([feet+Vector2(0,-58),"dye"])
	if y==Flower.XINGHE.y:
		LanyangLifeArt.draw_person(canvas,origin+Vector2(Flower.XINGHE)*32)
		labels.append([feet_of.call(Flower.XINGHE)+Vector2(0,-50),"xinghe"])
	if y==Flower.MARKET.y:
		var texture:=SceneArt.market_texture(garden_complete(data))
		var feet:Vector2=feet_of.call(Flower.MARKET)
		if texture:canvas.draw_texture(texture,(feet-Vector2(SceneArt.market_anchor())).round())
		labels.append([feet+Vector2(0,-66),"market"])
	if y>=Flower.GARDEN.position.y and y<Flower.GARDEN.end.y:
		garden_row(canvas,origin,y,garden_complete(data))
		if y==Flower.GARDEN.end.y-1:labels.append([origin+Vector2(garden_mid(),Flower.GARDEN.end.y)*32+Vector2(0,-66),"garden"])
	return labels

## Public garden: before completion an honest bare bed with young sprouts;
## after completion the delivered flowering trellis plus blooming beds.
static func garden_row(canvas:CanvasItem,origin:Vector2,y:int,complete:bool)->void:
	var kinds:=["bluebell","orange_blossom","chime_herb"]
	var back:=y==Flower.GARDEN.position.y
	if complete and not back:
		# The trellis stands on the middle column; front blooms overlap its feet.
		scene_prop(canvas,origin+Vector2(garden_mid(),Flower.GARDEN.end.y)*32+Vector2(0,-3),"community_flower_trellis")
	for x in range(Flower.GARDEN.position.x,Flower.GARDEN.end.x):
		var middle:=x==Flower.GARDEN.position.x+1
		if middle and (complete or back):continue
		var texture:=FlowerArt.crop_texture(kinds[(x+y)%3],FlowerArt.MATURE if complete else 0)
		if texture:canvas.draw_texture_rect(texture,Rect2(origin+Vector2(x,y)*32,Vector2(32,32)),false)

static func job_icon(canvas:CanvasItem,at:Vector2,job:Variant,data:Dictionary,item:="")->void:
	if not job is Dictionary or job.is_empty():return
	var id:=item if not item.is_empty() else str(job.get("kind",""))+"_seed"
	var texture:=FlowerArt.item_texture(id)
	if texture==null:return
	var ready:=float(data.get("time",0.0))>=float(job.get("ready",INF))
	canvas.draw_texture_rect(texture,Rect2(at.round(),Vector2(16,16)),false,Color.WHITE if ready else Color(1,1,1,0.5))
