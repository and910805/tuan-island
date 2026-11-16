extends RefCounted

const REACH:=3.2
const COOLDOWN:=0.8

# Shared by the authoritative action and the cursor preview. No state is changed.
static func plan(world,token:String,center:Vector2i) -> Dictionary:
	var result:Dictionary={"cells":[],"skipped":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty():return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var tile:=Vector2i(x,y)
			var key:String=world.key(tile)
			var reason:=""
			if center_far or origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>REACH:reason="距離太遠"
			elif not world.is_land(tile) or world.water(tile):reason="水域"
			elif world.protected(tile):reason="公共通道"
			elif world.state.crops.has(key):reason="已有農田"
			elif world.state.objects.has(key) or world.state.ground.has(key) or world.state.roofs.has(key):reason="已有建物"
			elif world.resource(tile)!="":reason="先清除障礙"
			if reason.is_empty():result.cells.append(key)
			else:result.skipped[key]=reason
	return result
