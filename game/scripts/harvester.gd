extends RefCounted

const PLOT_PERMISSIONS = preload("res://scripts/plot_permissions.gd")
const Shapes=preload("res://scripts/tiller.gd")

const REACH:=3.2
const COOLDOWN:=0.8

# Preview and server share the same per-plot maturity and ownership rules.
static func plan(world,token:String,center:Vector2i,offsets:Array=Shapes.SQUARE,hand_tool:bool=false) -> Dictionary:
	var result:Dictionary={"cells":[],"skipped":{},"yields":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty():return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	for offset:Vector2i in offsets:
		var tile:=center+offset
		var key:String=world.key(tile)
		var plot:Dictionary=world.state.crops.get(key,{})
		var kind:String=plot.get("kind","")
		var reason:=""
		var blocked_by_roof:bool=world.state.roofs.has(key) and not (hand_tool and world.has_glass_roof(key))
		if center_far or origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>REACH:reason="距離太遠"
		elif not world.is_land(tile) or world.water(tile) or world.protected(tile):reason="不可耕作的地面"
		elif plot.is_empty() or not world.CROPS.has(kind):reason="沒有作物"
		elif not PLOT_PERMISSIONS.can_harvest(world,token,plot,true).ok:reason="無採收權限" if hand_tool else PLOT_PERMISSIONS.MSG_HARVEST_MACHINE
		elif float(plot.get("growth",0))<float(world.CROPS[kind].time):reason="還沒成熟"
		elif world.state.objects.has(key) or world.state.ground.has(key) or blocked_by_roof or world.resource(tile)!="":reason="先移開障礙"
		if reason.is_empty():
			result.cells.append(key)
			result.yields[kind]=int(result.yields.get(kind,0))+int(world.CROPS[kind].yield)
		else:result.skipped[key]=reason
	if hand_tool and not world.key(center) in result.cells:
		result.cells.clear()
		result.yields.clear()
	return result
