extends RefCounted

const World=preload("res://scripts/world.gd")
const STRIDE:=0.90
const SURFACES:=["grass","soil","wood","stone","sand"]

var context:Array=[]
var previous:=Vector2.INF
var travelled:=0.0
var foot:=0

func reset()->void:
	context.clear()
	previous=Vector2.INF
	travelled=0.0
	foot=0

func advance(snapshot:Dictionary,id:String,position:Vector2,walking:bool)->String:
	var person:Dictionary=snapshot.get("players",{}).get(id,{})
	if not walking or person.is_empty() or not position.is_finite():
		reset()
		return ""
	var region:=str(snapshot.get("region_id",World.REGIONS.HOME))
	var current:=[id,region,person.get("travel_epoch",0),person.get("peer",0)]
	if current!=context:
		context=current
		previous=position
		travelled=STRIDE*0.50
		return ""
	var distance:=previous.distance_to(position)
	previous=position
	if distance>=STRIDE:
		travelled=0.0
		return ""
	travelled+=distance
	if travelled<STRIDE:return ""
	travelled-=STRIDE
	foot=1-foot
	return surface(snapshot,region,person,position)

static func surface(snapshot:Dictionary,region:String,person:Dictionary,position:Vector2)->String:
	var tile:=Vector2i(position.floor())
	var key:=World.key(tile)
	match snapshot.get("ground",{}).get(key,{}).get("type",""):
		"floor":return "wood"
		"path","spring_pebble_path","stone_floor":return "stone"
	if snapshot.get("crops",{}).has(key):return "soil"
	if region==World.REGIONS.HOME:
		var coast:=World.WANGAN_COAST
		if (World.STONE_WORKSHOP.bridge_open(snapshot) and tile.x in [55,56] and tile.y in range(29,32)) or coast.boardwalk(tile) or (snapshot.get("wangan_star_walk",false) and coast.star_boardwalk(tile)):
			return "wood"
		if coast.shore_cell(tile) or coast.star_shore(tile):return "sand"
		if World.VILLAGE_LAYOUT.path_at(position):return "soil"
	elif region==World.WARM_SPRINGS.REGION and World.WARM_SPRINGS.in_inn(person):return "wood"
	elif region in World.MINES.IDS or region in [World.REGIONS.JINGUASHI,World.PARTY_CART.REGION]:return "stone"
	elif region==World.SALT_PAN.REGION:return "sand"
	return "grass"
