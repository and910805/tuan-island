extends RefCounted

const INTERVAL:=12.0
const LIMIT:=2
const CAPACITY:=8
const OFFSETS:=[Vector2i(0,-2),Vector2i(2,0),Vector2i(0,2),Vector2i(-2,0)]
const OUTPUT:={"wood":6,"fiber":2,"resin":1}
const OUTPUT_CAPS:={"wood":48,"fiber":16,"resin":8}

static func fresh(now:float) -> Dictionary:
	return {"enabled":false,"fuel":0,"saplings":0,"cursor":0,"next_cycle":now,"last_cycle":-1.0}

static func can_move(station:Dictionary) -> bool:
	return not station.enabled and station.fuel==0 and station.saplings==0 and station.items.is_empty()

static func due(state:Dictionary,now:float) -> Array[String]:
	var stations:Array[String]=[]
	for key in state.objects:
		var station:Dictionary=state.objects[key]
		if station.type=="forester" and station.enabled and float(station.next_cycle)<=now:
			stations.append(key)
	return stations

static func plot_status(world,tile:Vector2i,owner:String) -> String:
	var state:Dictionary=world.state
	var target:String=world.key(tile)
	if not world.is_land(tile) or world.water(tile) or world.protected(tile):return "blocked"
	if state.crops.has(target) or state.objects.has(target) or state.ground.has(target) or state.roofs.has(target):return "blocked"
	var tree:Dictionary=state.forest.get(target,{})
	if tree.is_empty():return "empty" if world.resource(tile)=="" else "blocked"
	if tree.owner!=owner:return "blocked"
	return "mature" if tree.mature else "growing"

static func cycle(world,stations:Array[String]) -> bool:
	var changed:=false
	var state:Dictionary=world.state
	for key in stations:
		var station:Dictionary=state.objects[key]
		var tile:Vector2i=world.cell(key)+OFFSETS[int(station.cursor)]
		var target:String=world.key(tile)
		station.cursor=(int(station.cursor)+1)%OFFSETS.size()
		station.next_cycle=float(state.time)+INTERVAL
		var status:=plot_status(world,tile,station.owner)
		if status in ["blocked","growing"]:continue
		if status=="empty":
			if int(station.saplings)==0:continue
			var occupied:=false
			for token in world.active_tokens:
				var player:Dictionary=state.players[token]
				if Vector2(player.x,player.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))<0.8:
					occupied=true
					break
			if occupied:continue
			station.saplings=int(station.saplings)-1
		else:
			if int(station.fuel)==0:continue
			var fits:=true
			for item in OUTPUT:
				if int(station.items.get(item,0))+OUTPUT[item]>OUTPUT_CAPS[item]:
					fits=false
					break
			if not fits:continue
			station.fuel=int(station.fuel)-1
			for item in OUTPUT:station.items[item]=int(station.items.get(item,0))+OUTPUT[item]
			state.removed[target]=true
		state.forest[target]={"growth":0.0,"mature":false,"owner":station.owner}
		state.damage.erase(target)
		station.last_cycle=float(state.time)
		changed=true
	return changed
