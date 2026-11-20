extends RefCounted
## P05 迷路小雞 render helper. Pure view: reads snapshot.lost_chicks and draws a small wood sign, a
## low feeding pen and the lost chicks. Reuses the formal 糯米雞 sprite (life-art/animals.png, same
## body/foot split as chicken_cuddle.gd) at a smaller size plus a small yellow scarf so they read as
## chicks, not the ordinary 糯米雞. Adds no collision geometry and never changes rules.
## Every draw call takes screen pixels; sizes scale with view.TILE (48/64 px, 32 art px per tile).

const Rule=preload("res://scripts/lost_chicks.gd")
const ATLAS=preload("res://assets/life-art/animals.png")
const KEY:="lost_chicks"
const SIGN_POINT:="lost_chicks_sign"
const PEN_PHASES:=["run","results"]
const CHICK_SCALE:=0.74
const HOP_SECONDS:=1.6

const WOOD_DARK:=Color("6a3a1c")
const WOOD:=Color("a8642c")
const WOOD_LIGHT:=Color("d99a4a")
const HAY:=Color("e6c860")
const HAY_SHADE:=Color("b8973a")
const GRASS:=Color("7fae5a")
const SCARF:=Color("f6cf3c")
const SCARF_SHADE:=Color("d49a1e")
const SHADOW:=Color(0.18,0.12,0.08,0.28)
const GRAIN:=Color("f0dca0")

static func state(snapshot:Dictionary) -> Dictionary:
	var value=snapshot.get(KEY,{})
	return value if value is Dictionary else {}

static func phase(snapshot:Dictionary) -> String:
	return str(state(snapshot).get("phase","idle"))

## Picnic on the home village only (same gate as the other picnic activities).
static func available(snapshot:Dictionary) -> bool:
	return str(snapshot.get("region_id","home"))=="home" and bool(snapshot.get("picnic",false))

## Pen shows only while a round is running or in its results.
static func pen_shown(snapshot:Dictionary) -> bool:
	return available(snapshot) and phase(snapshot) in PEN_PHASES

## Focus points, tile-centre coordinates. Only the sign is interactable.
static func points(snapshot:Dictionary) -> Dictionary:
	if not available(snapshot):return {}
	return {SIGN_POINT:Vector2(Rule.SIGN)+Vector2(0.5,0.5)}

static func _unit(view) -> float:
	return float(view.TILE)/32.0

static func _rect(view,o:Vector2,u:float,x:float,y:float,w:float,h:float,color:Color) -> void:
	var p:=(o+Vector2(x,y)*u).round()
	view.draw_rect(Rect2(p,(Vector2(w,h)*u).round().max(Vector2.ONE)),color)

## `at` = top-left of the sign tile.
static func draw_sign(view,at:Vector2) -> void:
	var u:=_unit(view)
	var o:=at.floor()
	_rect(view,o,u,8,29,16,3,SHADOW)
	_rect(view,o,u,14,12,4,19,WOOD_DARK)
	_rect(view,o,u,15,12,2,19,WOOD)
	# board
	_rect(view,o,u,4,-1,24,16,WOOD_DARK)
	_rect(view,o,u,5,0,22,14,WOOD)
	_rect(view,o,u,5,0,22,2,WOOD_LIGHT)
	# little chick with a yellow scarf on the board
	_rect(view,o,u,10,4,8,7,Color("fff2c4"))
	_rect(view,o,u,9,6,1,3,Color("fff2c4"))
	_rect(view,o,u,8,7,2,1,Color("e8923a"))
	_rect(view,o,u,11,5,1,1,WOOD_DARK)
	_rect(view,o,u,11,9,7,2,SCARF)
	_rect(view,o,u,17,10,2,3,SCARF_SHADE)
	# paw prints to the right
	_rect(view,o,u,21,5,2,2,WOOD_DARK)
	_rect(view,o,u,23,8,2,2,WOOD_DARK)

## `at` = top-left of the pen tile. Low fence around a hay patch and a tiny trough.
static func draw_pen(view,at:Vector2) -> void:
	var u:=_unit(view)
	var o:=at.floor()
	_rect(view,o,u,1,28,30,3,SHADOW)
	_rect(view,o,u,2,12,28,17,GRASS)
	_rect(view,o,u,4,16,16,10,HAY)
	_rect(view,o,u,6,18,4,1,HAY_SHADE)
	_rect(view,o,u,12,22,5,1,HAY_SHADE)
	# trough
	_rect(view,o,u,21,19,8,6,WOOD_DARK)
	_rect(view,o,u,22,20,6,4,WOOD)
	_rect(view,o,u,23,19,4,1,GRAIN)
	# fence: back rail, posts, front rail
	_rect(view,o,u,0,10,32,3,WOOD_DARK)
	_rect(view,o,u,1,11,30,1,WOOD_LIGHT)
	for x in [0.0,14.0,29.0]:
		_rect(view,o,u,x,8,3,22,WOOD_DARK)
		_rect(view,o,u,x+1.0,8,1,21,WOOD)
	_rect(view,o,u,0,25,32,3,WOOD_DARK)
	_rect(view,o,u,1,26,30,1,WOOD)

## Chick pose offsets in art pixels, all whole pixels. static_motion => exact rest pose.
static func _hop(index:int,status:String,elapsed:float,static_motion:bool) -> int:
	if static_motion or status!="lost":return 0
	var t:=fposmod(maxf(elapsed,0.0)/HOP_SECONDS+float(index)*0.37,1.0)
	if t>=0.2:return 0
	return roundi(sin(t/0.2*PI)*3.0)

static func _kick(index:int,status:String,elapsed:float,static_motion:bool) -> int:
	if static_motion or status!="follow":return 0
	return 1 if int(floor(maxf(elapsed,0.0)*6.0))%2==(index%2) else -1

## `at` = top-left of one WorldView.TILE. The chick stands bottom-centre of that tile.
static func draw_chick(view,at:Vector2,index:int,status:String,elapsed:float,static_motion:bool) -> void:
	var tile:=float(view.TILE)
	var k:=tile/32.0*CHICK_SCALE
	var size:=32.0*k
	var hop:=_hop(index,status,elapsed,static_motion)
	var kick:=_kick(index,status,elapsed,static_motion)
	var origin:=(at+Vector2((tile-size)*0.5,tile-28.0*k-3.0)).round()
	var rise:=Vector2(0,-float(hop)*k).round()
	# shadow stays on the ground while the chick hops
	view.draw_rect(Rect2((origin+Vector2(8,27)*k).round(),(Vector2(14,2)*k).round().max(Vector2(2,1))),SHADOW)
	# body (rows 0-24) and the original feet (rows 25-27); feet swing when following
	view.draw_texture_rect_region(ATLAS,Rect2(origin+rise,Vector2(32,25)*k),Rect2(0,0,32,25))
	for leg in [[13,3,-kick],[17,4,kick]]:
		var foot_at:=origin+rise+Vector2(float(leg[0]),25.0+float(leg[2]))*k
		view.draw_texture_rect_region(ATLAS,Rect2(foot_at.round(),Vector2(float(leg[1]),3.0)*k),Rect2(leg[0],25,leg[1],3))
	if status=="follow":
		var gleam:=(origin+Vector2(24,5)*k).round()
		view.draw_rect(Rect2(gleam,Vector2(2,6)),Color("fff1a7"))
		view.draw_rect(Rect2(gleam+Vector2(-2,2),Vector2(6,2)),Color("fff1a7"))
	# yellow scarf at the neck (head faces left in the atlas) with a short tail
	var s:=origin+rise
	view.draw_rect(Rect2((s+Vector2(7,14)*k).round(),(Vector2(8,3)*k).round().max(Vector2(2,1))),SCARF)
	view.draw_rect(Rect2((s+Vector2(12,17)*k).round(),(Vector2(3,4)*k).round().max(Vector2(1,1))),SCARF_SHADE)

## `feet` = screen pixel bottom-centre of the bucket (HUD slot or beside the carrying player).
static func draw_bucket(view,feet:Vector2) -> void:
	var u:=_unit(view)
	var o:=(feet-Vector2(8,12)*u).round()
	_rect(view,o,u,0,11,16,2,SHADOW)
	_rect(view,o,u,1,3,14,9,WOOD_DARK)
	_rect(view,o,u,2,4,12,7,WOOD)
	_rect(view,o,u,2,4,12,1,WOOD_LIGHT)
	_rect(view,o,u,2,7,12,1,WOOD_DARK)
	_rect(view,o,u,3,2,10,2,GRAIN)
	_rect(view,o,u,5,1,2,1,GRAIN)
	_rect(view,o,u,2,0,1,3,WOOD_DARK)
	_rect(view,o,u,13,0,1,3,WOOD_DARK)
	_rect(view,o,u,2,0,12,1,WOOD_DARK)
