extends RefCounted

const PLOT_PERMISSIONS = preload("res://scripts/plot_permissions.gd")

const REACH:=3.2
const COOLDOWN:=0.8

# Preview and server share the same per-plot maturity and ownership rules.
static func plan(world,token:String,center:Vector2i) -> Dictionary:
	var result:Dictionary={"cells":[],"skipped":{},"yields":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty():return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var tile:=Vector2i(x,y)
			var key:String=world.key(tile)
			var plot:Dictionary=world.state.crops.get(key,{})
			var kind:String=plot.get("kind","")
			var reason:=""
			if center_far or origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>REACH:reason="距離太遠"
			elif not world.is_land(tile) or world.water(tile) or world.protected(tile):reason="不可耕作的地面"
			elif plot.is_empty() or not world.CROPS.has(kind):reason="沒有作物"
			elif not PLOT_PERMISSIONS.can_harvest(world,token,plot,true).ok:reason=PLOT_PERMISSIONS.MSG_HARVEST_MACHINE
			elif float(plot.get("growth",0))<float(world.CROPS[kind].time):reason="還沒成熟"
			elif world.state.objects.has(key) or world.state.ground.has(key) or world.state.roofs.has(key) or world.resource(tile)!="":reason="先移開障礙"
			if reason.is_empty():
				result.cells.append(key)
				result.yields[kind]=int(result.yields.get(kind,0))+int(world.CROPS[kind].yield)
			else:result.skipped[key]=reason
	return result
