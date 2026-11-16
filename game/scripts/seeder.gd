extends RefCounted

const REACH:=3.2
const COOLDOWN:=0.8

# One authoritative plan also drives the cursor, including limited seed stock.
static func plan(world,token:String,center:Vector2i,kind:String) -> Dictionary:
	var result:Dictionary={"cells":[],"eligible":[],"skipped":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty() or not world.CROPS.has(kind):return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	var candidates:Array[Vector2i]=[]
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var tile:=Vector2i(x,y)
			var key:String=world.key(tile)
			var crop:Dictionary=world.state.crops.get(key,{})
			var reason:=""
			if center_far or origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>REACH:reason="距離太遠"
			elif not world.is_land(tile) or world.water(tile) or world.protected(tile):reason="不可耕作的地面"
			elif crop.is_empty():reason="先整地"
			elif crop.get("owner","")!=token:reason="他人的農田"
			elif crop.get("kind","")!="":reason="已有作物"
			elif not world.planting_problem(kind,tile).is_empty():reason=world.planting_problem(kind,tile)
			elif world.state.objects.has(key) or world.state.ground.has(key) or world.state.roofs.has(key) or world.resource(tile)!="":reason="先移開障礙"
			if reason.is_empty():candidates.append(tile)
			else:result.skipped[key]=reason
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
