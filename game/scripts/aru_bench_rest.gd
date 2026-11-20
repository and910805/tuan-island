extends RefCounted
## T066 N01-3 「留下新的刮痕」: pure helpers for the transient co-sitting scene beside 阿榆.
## The scene lives only on the World instance (World.aru_bench), never in world.state / SaveSchema:
## {} idle, or {"anchor":Vector2i,"site":Vector2i,"sitters":{token:slot}} (slot 0 primary, 1 visiting friend).
## The public snapshot field is {} or {"anchor":World.key(anchor),"sitters":{public_id:slot}}.

const SLOTS:=2
const PRIMARY:=0
const FRIEND:=1
const REACH:=3.2 # same reach as the old decorative popup, measured from Aru's dynamic cell centre
const SEAT_REACH:=3.0 # every seat must stay inside REACH so a sitter can always stand/leave in place
const SEARCH_X:=[-3,-2,-1,0,1,2,3]
const SEARCH_Y:=[-3,-2,-1,0,1,2,3]
const CLEARANCE:=0.7 # an idle player closer than this to a seat blocks that anchor
## Feet in tile units relative to the anchor (left edge of the 2x1 bench).
const NPC_FEET:=Vector2(0.40,0.72)
const SLOT_FEET:=[Vector2(1.00,0.72),Vector2(1.60,0.72)]
const SEAT_TOLERANCE:=0.08

static func feet(anchor:Vector2i,slot:int) -> Vector2:
	return Vector2(anchor)+SLOT_FEET[clampi(slot,0,SLOTS-1)]

static func npc_feet(anchor:Vector2i) -> Vector2:
	return Vector2(anchor)+NPC_FEET

static func site_center(site:Vector2i) -> Vector2:
	return Vector2(site)+Vector2(0.5,0.5)

## Candidate left-edge cells, nearest to Aru first; ties break by row then column so the choice is stable.
static func candidates(site:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for dy:int in SEARCH_Y:
		for dx:int in SEARCH_X:
			var anchor:=site+Vector2i(dx,dy)
			if feet(anchor,FRIEND).distance_to(site_center(site))<=SEAT_REACH and feet(anchor,PRIMARY).distance_to(site_center(site))<=SEAT_REACH:out.append(anchor)
	out.sort_custom(func(a:Vector2i,b:Vector2i) -> bool:
		var da:=feet(a,PRIMARY).distance_squared_to(site_center(site))
		var db:=feet(b,PRIMARY).distance_squared_to(site_center(site))
		if not is_equal_approx(da,db):return da<db
		return a.y<b.y or (a.y==b.y and a.x<b.x))
	return out

## Public projection. `public_id` maps a raw token to the id Session.public_state uses.
static func public_scene(scene:Dictionary,key_of:Callable,public_id:Callable) -> Dictionary:
	if scene.is_empty():return {}
	var sitters:={}
	for token:String in scene.sitters:sitters[str(public_id.call(token))]=int(scene.sitters[token])
	return {"anchor":str(key_of.call(scene.anchor)),"sitters":sitters}
