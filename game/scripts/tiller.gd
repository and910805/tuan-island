extends RefCounted

const REACH:=3.2
const COOLDOWN:=0.8
const ROW:=[Vector2i.LEFT,Vector2i.ZERO,Vector2i.RIGHT]
const CROSS:=[Vector2i.UP,Vector2i.LEFT,Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN]
const SQUARE:=[Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]
const HAND_PATTERNS:={
	"copper_hoe":ROW,
	"iron_hoe":CROSS,
	"precision_hoe":SQUARE,
	"copper_can":ROW,
	"iron_can":CROSS,
	"precision_can":SQUARE,
	"copper_seed_pouch":ROW,
	"iron_seed_pouch":CROSS,
	"precision_seed_pouch":SQUARE,
	"copper_sickle":ROW,
	"iron_sickle":CROSS,
	"precision_sickle":SQUARE,
}

# Shared by the authoritative action and the cursor preview. No state is changed.
static func plan(world,token:String,center:Vector2i,offsets:Array=SQUARE) -> Dictionary:
	var result:Dictionary={"cells":[],"skipped":{}}
	var person:Dictionary=world.state.players.get(token,{})
	if person.is_empty():return result
	var origin:=Vector2(person.x,person.y)
	var center_far:=origin.distance_to(Vector2(center)+Vector2(0.5,0.5))>REACH
	for offset:Vector2i in offsets:
		var tile:=center+offset
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

static func hand_plan(world,token:String,center:Vector2i,tool:String)->Dictionary:
	var offsets:Array=HAND_PATTERNS.get(tool,[])
	var preview:=plan(world,token,center,offsets)
	if not world.key(center) in preview.cells:preview.cells.clear()
	return preview
