extends SceneTree
const Settlement=preload("res://scripts/auto_roof_settlement.gd")
const Plan=preload("res://scripts/auto_roof_plan.gd")
const World=preload("res://scripts/world.gd")

# Token-like ids; the "SECRET" marker must never leak into any message.
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const C:="tok-carol-SECRET"
const D:="tok-dave-SECRET"
const LIMIT:=1000000000

var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

# w x h floor interior at o ringed by walls; door at `door` (or a gap if door_gap).
func room(o:Vector2i,w:int,h:int,door:Vector2i,door_gap:bool) -> Dictionary:
	var ground:={};var objects:={}
	for y in range(o.y-1,o.y+h+1):
		for x in range(o.x-1,o.x+w+1):
			var p:=Vector2i(x,y)
			if x==o.x-1 or x==o.x+w or y==o.y-1 or y==o.y+h:
				objects[k(p)]={"type":"wall","owner":A,"items":{}}
			else:
				ground[k(p)]={"type":"floor","owner":A,"items":{}}
	if door_gap:objects.erase(k(door))
	else:objects[k(door)]={"type":"door","owner":A,"items":{},"open":false}
	return {"ground":ground,"objects":objects,"roofs":{}}

func snap(v) -> String:
	return var_to_str(v)

func base_players() -> Dictionary:
	# Mirrors World's fresh-player shape; carol and dave are "offline" (only persisted).
	return {
		A:{"name":"A","coins":120,"inventory":{"wood":12,"stone":4,"fiber":10,"radish_seed":5,"sapling":2},"receipts":{},"builds":3},
		B:{"name":"B","coins":5,"inventory":{"wood":1,"fiber":0,"tea_leaf":7},"receipts":{}},
		C:{"name":"C","inventory":{"stone":9}},
		D:{"name":"D","inventory":{"wood":99,"fiber":99}},
	}

func plan_of(cost:Dictionary,refunds:Dictionary) -> Dictionary:
	var remove:Array[String]=[]
	return {"ok":true,"message":"x","add":{},"remove":remove,"cost":cost,"refunds":refunds}

func is_fail(r:Dictionary,label:String) -> void:
	expect(r.get("ok")==false,label+": should fail")
	expect(r.get("inventories") is Dictionary and r.inventories.is_empty(),label+": no staged inventories on failure")
	var m=r.get("message")
	expect(typeof(m)==TYPE_STRING and m!="" and m.contains("沒有施工"),label+": localized failure message")
	expect(typeof(m)==TYPE_STRING and not m.contains("SECRET") and not m.contains("tok-"),label+": no token in message")

func malform(q:Dictionary,i:int) -> void:
	match i:
		0:q.ok=false
		1:q.erase("ok")
		2:q.ok="true"
		3:q.ok=1
		4:q.cost=[]
		5:q.erase("cost")
		6:q.refunds=null
		7:q.erase("refunds")
		8:q.refunds={B:[1]}
		9:q.refunds={B:5}
		10:q.remove={}
		11:q.erase("remove")
		12:q.remove=[1]
		13:q.add=[]
		14:q.erase("add")
		15:q.message=3

func run() -> void:
	var recipe:Dictionary=World.BUILD.roof
	expect(int(recipe.wood)==1 and int(recipe.fiber)==3,"real roof recipe is wood 1 / fiber 3")

	# ---- Real planner: closing a 2x3 room by placing its door. ------------
	var o:=Vector2i(10,10);var door:=Vector2i(9,11)
	var touched:Array[Vector2i]=[door]
	var close:=Plan.reconcile(room(o,2,3,door,true),room(o,2,3,door,false),touched,A,recipe)
	expect(close.ok and close.add.size()==6,"planner adds 6 roofs")
	expect(close.cost=={"wood":6,"fiber":18} and close.refunds.is_empty(),"planner cost from real recipe")

	# Actor insufficient (starting fiber 10 < 18).
	var players:=base_players()
	var before:=snap(players);var plan_before:=snap(close)
	var r:=Settlement.prepare(players,A,close)
	is_fail(r,"actor insufficient")
	expect(r.message==Settlement.MSG_MISSING,"insufficient reports missing materials")
	expect(snap(players)==before and snap(close)==plan_before,"inputs unmodified on failure")

	# Actor sufficient: unrelated entries retained, other players untouched.
	players[A].inventory.fiber=18
	before=snap(players);plan_before=snap(close)
	r=Settlement.prepare(players,A,close)
	expect(r.ok,"actor pays real roof cost")
	expect(r.inventories.keys()==[A],"only actor staged")
	expect(r.inventories.get(A,{})=={"wood":6,"stone":4,"fiber":0,"radish_seed":5,"sapling":2},"cost applied, unrelated entries & zeroed key retained")
	expect(snap(players)==before and snap(close)==plan_before,"inputs unmodified on success")
	r.inventories[A].wood=777
	expect(int(players[A].inventory.wood)==12,"staged inventory is a copy")

	# ---- Real planner: opening a room refunds offline owners. -------------
	var opened_before:=room(o,2,3,door,false)
	var owners:=[B,C,B,C,B,C]
	var cells:=[Vector2i(10,10),Vector2i(11,10),Vector2i(10,11),Vector2i(11,11),Vector2i(10,12),Vector2i(11,12)]
	for i in cells.size():
		opened_before.roofs[k(cells[i])]={"type":"roof","owner":owners[i],"items":{},"auto":true}
	var opened_after:=opened_before.duplicate(true)
	opened_after.objects.erase(k(door))
	var open:=Plan.reconcile(opened_before,opened_after,touched,A,recipe)
	expect(open.ok and open.remove.size()==6 and open.cost.is_empty(),"planner removes 6 auto roofs")
	expect(open.refunds=={B:{"wood":3,"fiber":9},C:{"wood":3,"fiber":9}},"planner refunds per owner")
	players=base_players()
	before=snap(players)
	r=Settlement.prepare(players,A,open)
	expect(r.ok,"multi-owner offline refunds")
	var ks:Array=r.inventories.keys();ks.sort()
	var want:=[B,C];want.sort()
	expect(ks==want,"only refund owners staged; actor without cost not staged")
	expect(r.inventories.get(B,{})=={"wood":4,"fiber":9,"tea_leaf":7},"bob refunded, tea retained")
	expect(r.inventories.get(C,{})=={"stone":9,"wood":3,"fiber":9},"offline carol refunded")
	expect(snap(players)==before,"inputs unmodified multi-owner")

	# ---- Refund offsets actor cost (combined same owner). -----------------
	players=base_players()
	players[A].inventory.fiber=0
	var p:=plan_of({"wood":6,"fiber":18},{A:{"wood":6,"fiber":18},B:{"wood":3}})
	r=Settlement.prepare(players,A,p)
	expect(r.ok,"own refund offsets own cost")
	expect(r.inventories.get(A,{})==players[A].inventory,"net zero for actor")
	expect(r.inventories.get(B,{}).get("wood")==4,"other owner still refunded")
	p=plan_of({"wood":6,"fiber":18},{A:{"wood":1,"fiber":10}})
	r=Settlement.prepare(players,A,p)
	is_fail(r,"partial own refund still short")
	players[A].inventory.fiber=8
	r=Settlement.prepare(players,A,p)
	expect(r.ok and r.inventories[A].fiber==0 and r.inventories[A].wood==7,"combined cost+refund exact zero")

	# ---- Another owner's refund cannot subsidize the actor. ---------------
	players=base_players()
	players[A].inventory.fiber=0
	before=snap(players)
	r=Settlement.prepare(players,A,plan_of({"fiber":18},{B:{"fiber":18},D:{"fiber":100}}))
	is_fail(r,"other owner cannot subsidize")
	expect(r.message==Settlement.MSG_MISSING,"subsidy reported as missing materials")
	expect(snap(players)==before,"no partial refund to bob on failure")
	r=Settlement.prepare(players,B,plan_of({"wood":2},{A:{"wood":5}}))
	is_fail(r,"bob cannot spend alice refund")

	# ---- Refund cap exact boundary. ---------------------------------------
	players=base_players()
	players[B].inventory.wood=LIMIT-3
	r=Settlement.prepare(players,A,plan_of({},{B:{"wood":3}}))
	expect(r.ok and r.inventories[B].wood==LIMIT,"exactly 1e9 allowed")
	r=Settlement.prepare(players,A,plan_of({},{B:{"wood":4}}))
	is_fail(r,"1e9+1 rejected")
	expect(r.message==Settlement.MSG_CAP,"cap state message")
	players[B].inventory.wood=float(LIMIT)
	r=Settlement.prepare(players,A,plan_of({},{B:{"fiber":float(LIMIT)}}))
	expect(r.ok and typeof(r.inventories[B].wood)==TYPE_INT and r.inventories[B].fiber==LIMIT,"integer floats at 1e9 normalized")
	players[A].inventory.wood=LIMIT
	r=Settlement.prepare(players,A,plan_of({"wood":1},{A:{"wood":1}}))
	expect(r.ok and r.inventories[A].wood==LIMIT,"refund+cost netting at cap allowed")
	# One owner over cap blocks everyone (all-or-nothing).
	players=base_players()
	players[C].inventory.stone=LIMIT
	r=Settlement.prepare(players,A,plan_of({"wood":1},{B:{"wood":1},C:{"stone":1}}))
	is_fail(r,"any owner over cap rejects whole settlement")

	# ---- Integer-valued floats normalized. --------------------------------
	players=base_players()
	players[A].inventory.wood=12.0
	before=snap(players)
	r=Settlement.prepare(players,A,plan_of({"wood":2.0},{A:{"stone":1.0}}))
	expect(r.ok and typeof(r.inventories[A].wood)==TYPE_INT and r.inventories[A].wood==10 and r.inventories[A].stone==5,"integer floats accepted")
	expect(typeof(r.inventories[A].radish_seed)==TYPE_INT,"untouched entries normalized")
	expect(snap(players)==before,"normalization does not mutate input")
	players[A].inventory.radish=2
	before=snap(players)
	r=Settlement.prepare(players,A,plan_of({"wood":1},{}))
	expect(r.ok and r.inventories[A].get("radish")==2,"runtime dot-assigned inventory keys survive settlement")
	for resource_key in r.inventories.get(A,{}):expect(typeof(resource_key)==TYPE_STRING,"staged inventory keys normalized for persistence")
	expect(snap(players)==before,"runtime key normalization preserves original input")

	# ---- Bad values reject everywhere. ------------------------------------
	var bads:=[-1,-1.0,1.5,NAN,INF,-INF,true,false,"3",null,[1],{},LIMIT+1,float(LIMIT)+1.0,Vector2i(1,1)]
	for bad in bads:
		var label:=var_to_str(bad)
		players=base_players();before=snap(players)
		r=Settlement.prepare(players,A,plan_of({"wood":bad},{}))
		is_fail(r,"cost "+label)
		r=Settlement.prepare(players,A,plan_of({},{B:{"wood":bad}}))
		is_fail(r,"refund "+label)
		expect(snap(players)==before,"inputs unmodified after bad "+label)
		players[A].inventory.unrelated=bad
		r=Settlement.prepare(players,A,plan_of({"wood":1},{}))
		is_fail(r,"actor inventory entry "+label)
		players=base_players()
		players[B].inventory.unrelated=bad
		r=Settlement.prepare(players,A,plan_of({},{B:{"wood":1}}))
		is_fail(r,"owner inventory entry "+label)
	# Unaffected player's bad data does not block this transaction.
	players=base_players()
	players[D].inventory.wood=NAN
	r=Settlement.prepare(players,A,plan_of({"wood":1},{B:{"wood":1}}))
	expect(r.ok and not r.inventories.has(D),"unaffected player not validated or staged")
	# Bad keys.
	var sn:={};sn[&"pebble"]=1
	is_fail(Settlement.prepare(base_players(),A,plan_of(sn,{})),"StringName cost key")
	for key in [1,"","x".repeat(65)]:
		players=base_players()
		var c:={};c[key]=1
		is_fail(Settlement.prepare(players,A,plan_of(c,{})),"cost key "+var_to_str(key))
		is_fail(Settlement.prepare(players,A,plan_of({},{B:c})),"refund key "+var_to_str(key))
		players[A].inventory[key]=1
		is_fail(Settlement.prepare(players,A,plan_of({"wood":1},{})),"inventory key "+var_to_str(key))

	# ---- Malformed plan. --------------------------------------------------
	players=base_players();before=snap(players)
	var good:=plan_of({"wood":1},{B:{"wood":1}})
	expect(Settlement.prepare(players,A,good).ok,"baseline plan ok")
	for i in 16:
		var q:=good.duplicate(true)
		malform(q,i)
		var qs:=snap(q)
		is_fail(Settlement.prepare(players,A,q),"malformed plan #%d"%i)
		expect(snap(q)==qs,"malformed plan #%d unmodified"%i)
	var rejected:=close.duplicate(true);rejected.ok=false
	players[A].inventory.fiber=100
	is_fail(Settlement.prepare(players,A,rejected),"real plan with ok=false")
	players[A].inventory.fiber=10
	# Missing / malformed payer and owners.
	is_fail(Settlement.prepare(players,"",good),"empty actor")
	is_fail(Settlement.prepare(players," "+A,good),"padded actor")
	is_fail(Settlement.prepare(players,"tok-nobody-SECRET",good),"actor not persisted")
	is_fail(Settlement.prepare(players,"tok-nobody-SECRET",plan_of({},{})),"missing payer even for no-op")
	is_fail(Settlement.prepare(players,A,plan_of({},{"tok-ghost-SECRET":{"wood":1}})),"refund owner not persisted")
	is_fail(Settlement.prepare(players,A,plan_of({},{"":{"wood":1}})),"empty refund owner")
	is_fail(Settlement.prepare(players,A,plan_of({},{7:{"wood":1}})),"non-string refund owner")
	for broken in [null,[],"x",{"name":"no inventory"},{"inventory":[]},{"inventory":null}]:
		var ps:=base_players();ps[A]=broken
		is_fail(Settlement.prepare(ps,A,good),"broken actor record "+var_to_str(broken))
		ps=base_players();ps[B]=broken
		is_fail(Settlement.prepare(ps,A,good),"broken owner record "+var_to_str(broken))
	expect(snap(players)==before,"players unmodified across malformed cases")

	# ---- Empty cost/refunds no-op; zero-only entries do not invent keys. --
	r=Settlement.prepare(players,A,plan_of({},{}))
	expect(r.ok and r.inventories.is_empty() and r.message==Settlement.MSG_NOOP,"empty plan is no-op")
	r=Settlement.prepare(players,A,plan_of({},{B:{}}))
	expect(r.ok and r.inventories.is_empty(),"empty refund map is no-op")
	r=Settlement.prepare(players,A,plan_of({"gold":0},{B:{"gold":0}}))
	expect(r.ok and not r.inventories.get(A,{}).has("gold") and not r.inventories.get(B,{}).has("gold"),"zero counts add no keys")
	r=Settlement.prepare(players,A,plan_of({"gold":1},{}))
	is_fail(r,"cost of item not held")
	expect(r.message==Settlement.MSG_MISSING,"missing materials for absent item")
	expect(snap(players)==before,"players unmodified at end")

	print("AUTO_ROOF_SETTLEMENT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
