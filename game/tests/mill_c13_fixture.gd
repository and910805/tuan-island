extends RefCounted
## Shared fixture for the C13 麵粉磨坊 (3x3 mill) regression files (test_mill_c13*.gd). No scene, no UI.
##
## FIXTURE, NOT NORMAL PLAY (disclosed): the public kitchen is written in as already opened (the Q05 gate is
## tested through the real actions in test_bakery_world.gd), backpacks are written directly, players are
## teleported, and the island clearing x 38..50 / y 32..40 is opened through `World.state.removed`.
## Everything else (build, remove, move, undo, queue, belts, blueprints) goes through the real World actions.
##
## GEOMETRY. ANCHOR (40,33) covers x 40..42 / y 33..35. WEST (39.5,34.5) is outside every footprint, reaches the
## anchor (1.4 tiles) and stands ON the facing-1 front cell. DEST (40,37) covers x 40..42 / y 37..39 and is
## reachable from MOVER (43.5,36.5). SHIFT (40,34) overlaps the ANCHOR footprint by two rows.
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const PK=World.PUBLIC_KITCHEN
const A:="mill-a"
const B:="mill-b"
const ANCHOR:=Vector2i(40,33)
const DEST:=Vector2i(40,37)
const SHIFT:=Vector2i(40,34)
const WEST:=Vector2(39.5,34.5)
const MOVER:=Vector2(43.5,36.5)
const PARK:=Vector2(48.5,38.5)
## Cost of the new mill, written independently of World.BUILD so a drifting recipe fails by name.
const COST:={"wood":25,"stone":15,"woodwork_parts":4}

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

static func centre(tile:Vector2i) -> Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

static func stock() -> Dictionary:
	return {"wood":300,"stone":200,"woodwork_parts":20,"wheat":40,"sweet_corn":4,"fiber":10,"plank":10}

## A world with both players on the open clearing and the public kitchen opened.
static func world() -> World:
	var w:=World.new()
	w.add_player(A,"甲")
	w.add_player(B,"乙")
	w.state.time=720.0
	for x in range(38,51):
		for y in range(32,41):w.state.removed[World.key(Vector2i(x,y))]=true
	w.state.picnic=true
	w.state.community={"table":World.COMMUNITY.choose_table(w.state)}
	for part in [["37,33","stove"],["36,33","long_bench"],["36,34","long_bench"]]:
		w.state.objects[part[0]]={"type":part[1],"owner":A,"items":{}}
	w.state.public_kitchen={"stove":"37,33","seats":["36,33","36,34"],"meals":PK.REQUIREMENTS.duplicate(),"opened":true}
	for token:String in [A,B]:w.state.players[token].inventory=stock()
	var clock:=FakeClock.new()
	w.undo_clock_utc=Callable(clock,"now_utc")
	w.undo_clock_ticks=Callable(clock,"now_ticks")
	put(w,A,WEST)
	put(w,B,PARK)
	return w

static func put(w:World,token:String,at:Vector2) -> void:
	w.state.players[token].x=at.x
	w.state.players[token].y=at.y

static var serial:=0

static func act(w:World,token:String,verb:String,tile:Vector2i,extra:="") -> Dictionary:
	serial+=1
	return w.act(token,"mill-c13-%d"%serial,verb,tile,extra)

static func bag(w:World,item:String,token:=A) -> int:
	return int(w.state.players[token].inventory.get(item,0))

static func obj(w:World,tile:Vector2i) -> Dictionary:
	return w.state.objects.get(World.key(tile),{})

static func cells(anchor:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for offset:Vector2i in I.mill_cells():out.append(anchor+offset)
	return out

static func entrance(anchor:Vector2i,facing:int) -> Vector2i:
	return anchor+I.mill_entrance_offset(facing)

static func front(anchor:Vector2i,facing:int) -> Vector2i:
	return anchor+I.mill_front_offset(facing)

## Writes a complete new mill straight into the layer (no action, no charge): the shape the real build produces.
static func place(w:World,anchor:Vector2i,facing:int,owner:=A,anchor_extra:={}) -> void:
	var list:=cells(anchor)
	for part in list.size():
		var piece:Dictionary={"type":"mill","owner":owner,"items":{},I.MILL_PART:part,I.MILL_FACING:facing}
		if part==0:
			piece.merge({"input_wheat":0,"auto_enabled":false})
			piece.merge(anchor_extra,true)
		w.state.objects[World.key(list[part])]=piece

## True when every nine cells is this owner's part N with this facing and only the anchor holds machine state.
static func parts_ok(w:World,anchor:Vector2i,facing:int,owner:=A) -> bool:
	var list:=cells(anchor)
	for part in list.size():
		var piece:Dictionary=obj(w,list[part])
		if piece.get("type")!="mill" or piece.get("owner")!=owner or int(piece.get(I.MILL_PART,-1))!=part or int(piece.get(I.MILL_FACING,-1))!=facing:return false
		if part>0 and (piece.has("input_wheat") or piece.has("auto_enabled") or piece.has("job") or piece.has("processing") or not (piece.items as Dictionary).is_empty()):return false
	var head:Dictionary=obj(w,anchor)
	return head.has("input_wheat") and head.has("auto_enabled")

## The fixture's opened kitchen is written in directly, so it is not a schema-valid donated kitchen. Tests that
## validate or save replace it with the fresh (unregistered) kitchen and drop its three objects first; the mill
## cells themselves are never touched. Used on the live world only right before a save, otherwise on a copy.
static func quiet_kitchen(state:Dictionary) -> void:
	state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	state.picnic=false
	state.community={"table":""}
	for k in ["37,33","36,33","36,34"]:state.objects.erase(k)

static func valid(w:World) -> bool:
	var copy:Dictionary=w.state.duplicate(true)
	quiet_kitchen(copy)
	return bool(World.SAVE_SCHEMA.validate(copy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))
