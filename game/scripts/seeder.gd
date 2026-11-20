extends RefCounted

const REACH:=3.2
const COOLDOWN:=0.8
const Shapes=preload("res://scripts/tiller.gd")

# One authoritative plan also drives the cursor, including limited seed stock.
static func plan(world,token:String,center:Vector2i,kind:String,offsets:Array=Shapes.SQUARE,hand_tool:bool=false) -> Dictionary:
	var result:Dictionary={"cells":[],"eligible":[],"skipped":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty() or not world.CROPS.has(kind):return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	var candidates:Array[Vector2i]=[]
	for offset:Vector2i in offsets:
		var tile:=center+offset
		var key:String=world.key(tile)
		var crop:Dictionary=world.state.crops.get(key,{})
		var reason:=""
		var blocked_by_roof:bool=world.state.roofs.has(key) and not (hand_tool and world.has_glass_roof(key))
		if center_far or origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>REACH:reason="距離太遠"
		elif not world.is_land(tile) or world.water(tile) or world.protected(tile):reason="不可耕作的地面"
		elif crop.is_empty():reason="先整地"
		elif crop.get("owner","")!=token:reason="他人的農田"
		elif crop.get("kind","")!="":reason="已有作物"
		else:
			reason=world.planting_problem(kind,tile)
			if reason.is_empty() and (world.state.objects.has(key) or world.state.ground.has(key) or blocked_by_roof or world.resource(tile)!=""):reason="先移開障礙"
		if reason.is_empty():candidates.append(tile)
		else:result.skipped[key]=reason
	if hand_tool and center not in candidates:return result
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var da:=a.distance_squared_to(center)
		var db:=b.distance_squared_to(center)
		if da!=db:return da<db
		return a.y<b.y if a.y!=b.y else a.x<b.x
	)
	var stock:int=int(person.get("inventory",{}).get(kind+"_seed",0))
	for tile in candidates:
		var key:String=world.key(tile)
		result.eligible.append(key)
		if result.cells.size()<stock:result.cells.append(key)
		else:result.skipped[key]="種子不足"
	return result
