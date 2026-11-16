extends SceneTree
## Behavioural tests for auto_roof_preview.quote(): base build/remove + auto roof totals.
## Snapshots mirror the current-region layout (ground/objects/roofs keyed by World.key).
const World=preload("res://scripts/world.gd")
const Q=preload("res://scripts/auto_roof_preview.gd")
var checks:=0
var failures:=0
const O:=Vector2i(10,10)        # 2x2 interior origin: (10,10)..(11,11)
const DOOR:=Vector2i(10,9)
const GAP:=Vector2i(9,11)       # west wall slot left open
const SIDE:=Vector2i(9,10)      # west wall (no floor beneath)
const KEYS:=["ok","message","plan","base_cost","total_cost","base_refund","refunds","affected"]

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return World.key(p)

func snap() -> Dictionary:
	return {"ground":{},"objects":{},"roofs":{},"crops":{},"forest":{},"players":{}}

func piece(type:String,owner:String) -> Dictionary:
	var w:={"type":type,"owner":owner,"items":{}}
	if type=="door":w.open=false
	return w

func add_room(s:Dictionary,o:Vector2i,size:Vector2i,doors:Array,owner:="alice",wall_owner:="alice",floors:=true) -> Array:
	var cells:=[]
	for y in range(o.y-1,o.y+size.y+1):
		for x in range(o.x-1,o.x+size.x+1):
			var p:=Vector2i(x,y)
			if x>=o.x and x<o.x+size.x and y>=o.y and y<o.y+size.y:
				if floors:s.ground[k(p)]=piece("floor",owner)
				cells.append(p)
			elif not s.objects.has(k(p)):
				s.objects[k(p)]=piece("wall",wall_owner)
	for d in doors:s.objects[k(d)]=piece("door",wall_owner)
	return cells

func roof_cells(s:Dictionary,cells:Array,owner:String,auto:=true) -> void:
	for p in cells:
		var r:=piece("roof",owner)
		if auto:r.auto=true
		s.roofs[k(p)]=r

func keyset(cells:Array) -> Array:
	var out:=[]
	for p in cells:out.append(k(p))
	out.sort()
	return out

func sorted(values:Array) -> Array:
	var out:=values.duplicate()
	out.sort()
	return out

func shape_ok(r:Dictionary) -> bool:
	for f in KEYS:
		if not r.has(f):return false
	var p=r.plan
	return r.ok is bool and r.message is String and r.affected is bool and p is Dictionary and r.base_cost is Dictionary and r.total_cost is Dictionary and r.base_refund is Dictionary and r.refunds is Dictionary \
		and p.get("ok") is bool and p.get("message") is String and p.get("add") is Dictionary and p.get("remove") is Array and p.get("cost") is Dictionary and p.get("refunds") is Dictionary

func rejected(r:Dictionary) -> bool:
	return shape_ok(r) and not r.ok and not r.affected and r.base_cost.is_empty() and r.total_cost.is_empty() and r.base_refund.is_empty() and r.refunds.is_empty() and r.plan.add.is_empty() and r.plan.remove.is_empty()

func quote(s:Dictionary,actor:String,action:String,at:Vector2i,extra:="") -> Dictionary:
	var r:=Q.quote(s,actor,action,at,extra)
	expect(shape_ok(r),"result shape %s %s %s"%[action,extra,str(at)])
	return r

## Open room (west gap) with optional existing partial roofs.
func open_room(owner:="alice",wall_owner:="alice") -> Dictionary:
	var s:=snap()
	var cells:=add_room(s,O,Vector2i(2,2),[DOOR],owner,wall_owner)
	s.objects.erase(k(GAP))
	return {"s":s,"cells":cells}

func run() -> void:
	var B:Dictionary=World.BUILD
	expect(B.roof.wood==1 and B.roof.fiber==3,"test assumes roof = wood 1 + fiber 3")

	# --- exact base + auto totals before closure ---------------------------
	var c:=open_room()
	var s:Dictionary=c.s
	var r:=quote(s,"alice","build",GAP,"wall")
	expect(r.ok and r.affected,"closing wall is affected")
	expect(r.base_cost=={"wood":3},"wall base cost")
	expect(r.plan.cost=={"wood":4,"fiber":12},"4 auto roofs cost")
	expect(r.total_cost=={"wood":7,"fiber":12},"wall + 4 roofs total")
	expect(sorted(r.plan.add.keys())==keyset(c.cells),"adds exactly the interior")
	for key in r.plan.add:expect(r.plan.add[key]=={"type":"roof","owner":"alice","items":{},"auto":true},"auto roof owned by payer")
	expect(r.refunds.is_empty() and r.base_refund.is_empty(),"no refunds on closure")
	r=quote(s,"alice","build",GAP,"door")
	expect(r.ok and r.total_cost=={"wood":10,"fiber":14},"door closure total")
	r=quote(s,"alice","build",GAP,"window")
	expect(r.ok and r.total_cost=={"wood":10,"fiber":12,"stone":1},"window closure total")
	# Different actor closing someone else's room pays all roofs itself.
	r=quote(s,"bob","build",GAP,"wall")
	expect(r.ok and r.total_cost=={"wood":7,"fiber":12} and r.plan.add.values().all(func(v):return v.owner=="bob"),"closer pays and owns roofs")

	# Closure by the last floor tile.
	var f:=snap()
	var fcells:=add_room(f,O,Vector2i(2,2),[DOOR])
	f.ground.erase(k(Vector2i(11,11)))
	r=quote(f,"alice","build",Vector2i(11,11),"floor")
	expect(r.ok and r.affected and r.base_cost=={"wood":2} and r.total_cost=={"wood":6,"fiber":12},"last floor closes room")
	expect(sorted(r.plan.add.keys())==keyset(fcells),"floor closure roofs whole room")

	# --- missing roof materials: preview still shows the right cost ---------
	s.players={"alice":{"inventory":{}}}
	r=quote(s,"alice","build",GAP,"wall")
	expect(r.ok and r.total_cost=={"wood":7,"fiber":12},"empty inventory does not change the quote")
	s.erase("players")
	r=quote(s,"alice","build",GAP,"wall")
	expect(r.ok and r.total_cost=={"wood":7,"fiber":12},"players omitted from snapshot are irrelevant")

	# --- no structural change: normal quote, not affected -------------------
	r=quote(snap(),"alice","build",Vector2i(50,50),"floor")
	expect(r.ok and not r.affected and r.base_cost=={"wood":2} and r.total_cost=={"wood":2} and r.plan.ok,"lone floor normal quote")
	r=quote(snap(),"alice","build",Vector2i(50,50),"path")
	expect(r.ok and not r.affected and r.total_cost=={"stone":2},"path normal quote")

	# Legacy sealed, unroofed room: furniture/roof work never charges closure.
	var legacy:=snap()
	var lcells:=add_room(legacy,O,Vector2i(2,2),[DOOR])
	r=quote(legacy,"alice","build",lcells[0],"roof")
	expect(r.ok and not r.affected and r.total_cost=={"wood":1,"fiber":3},"manual roof in legacy room is just a roof")
	legacy.objects[k(lcells[1])]=piece("bed","alice")
	r=quote(legacy,"alice","remove",lcells[1])
	expect(r.ok and not r.affected and r.base_refund=={"wood":15,"fiber":10} and r.refunds=={"alice":{"wood":15,"fiber":10}},"remove bed in legacy room: no roof rebuild")

	# --- basic placement checks --------------------------------------------
	r=quote(s,"alice","build",SIDE,"wall")
	expect(rejected(r),"cannot build over existing object")
	r=quote(s,"alice","build",O,"floor")
	expect(rejected(r),"cannot re-floor")
	r=quote(s,"bob","build",O,"roof")
	expect(rejected(r),"roof only on own floor")
	s.crops[k(Vector2i(40,40))]={"kind":"","owner":"alice"}
	expect(rejected(quote(s,"alice","build",Vector2i(40,40),"floor")),"cannot floor over crops")
	s.crops.clear()
	roof_cells(s,[O],"alice",false)
	expect(rejected(quote(s,"alice","build",O,"roof")),"cannot stack roofs")
	s.roofs.clear()

	# --- mixed refunds on opening ------------------------------------------
	var m:=snap()
	var mcells:=add_room(m,O,Vector2i(2,2),[DOOR])
	roof_cells(m,mcells.slice(0,2),"bob")
	roof_cells(m,mcells.slice(2,4),"alice")
	r=quote(m,"alice","remove",SIDE)
	expect(r.ok and r.affected and sorted(r.plan.remove)==keyset(mcells),"opening removes all auto roofs")
	expect(r.base_refund=={"wood":3},"wall base refund")
	expect(r.refunds=={"bob":{"wood":2,"fiber":6},"alice":{"wood":5,"fiber":6}},"refunds per payer + base to actor")
	expect(r.total_cost.is_empty() and r.plan.cost.is_empty(),"opening costs nothing")
	expect(rejected(quote(m,"bob","remove",SIDE)),"cannot remove another player's wall")

	# --- manual roof mix ----------------------------------------------------
	c=open_room()
	s=c.s
	roof_cells(s,c.cells.slice(0,2),"alice",false)
	r=quote(s,"alice","build",GAP,"wall")
	expect(r.ok and sorted(r.plan.add.keys())==keyset(c.cells.slice(2,4)) and r.total_cost=={"wood":5,"fiber":6},"closure only roofs uncovered cells")
	roof_cells(s,c.cells.slice(2,4),"bob")
	s.objects[k(GAP)]=piece("wall","alice")
	r=quote(s,"alice","remove",SIDE)
	expect(r.ok and sorted(r.plan.remove)==keyset(c.cells.slice(2,4)),"opening keeps manual roofs")
	expect(r.refunds=={"bob":{"wood":2,"fiber":6},"alice":{"wood":3}},"manual roofs never refunded by reconcile")
	r=quote(s,"alice","remove",c.cells[0])
	expect(r.ok and not r.affected and r.base_refund=={"wood":1,"fiber":3} and r.plan.add.is_empty(),"remove targets manual roof first, no auto conversion")
	expect(rejected(quote(s,"bob","remove",c.cells[0])),"manual roof owner checked")

	# --- remove skips auto roof: bed / floor beneath ------------------------
	var a:=snap()
	var acells:=add_room(a,O,Vector2i(2,2),[DOOR])
	roof_cells(a,acells,"bob")
	a.objects[k(acells[0])]=piece("bed","alice")
	r=quote(a,"alice","remove",acells[0])
	expect(r.ok and not r.affected and r.base_refund=={"wood":15,"fiber":10} and r.refunds=={"alice":{"wood":15,"fiber":10}},"auto roof skipped, bed removed, roofs untouched")
	expect(rejected(quote(a,"bob","remove",acells[0])),"roof payer cannot remove someone else's bed")
	r=quote(a,"alice","remove",acells[3])
	expect(r.ok and r.affected and r.base_refund=={"wood":2},"auto roof skipped, floor removed")
	expect(sorted(r.plan.remove)==keyset(acells),"removing interior floor opens room")
	expect(r.refunds=={"bob":{"wood":4,"fiber":12},"alice":{"wood":2}},"roof refunds to payer, floor to actor")
	expect(rejected(quote(a,"bob","remove",acells[3])),"roof payer cannot remove floor under own auto roof")
	a.objects[k(acells[0])].items={"wood":3}
	expect(rejected(quote(a,"alice","remove",acells[0])),"non-empty container protected")
	var orphan:=snap()
	roof_cells(orphan,[Vector2i(3,3)],"alice")
	expect(rejected(quote(orphan,"alice","remove",Vector2i(3,3))),"lone auto roof is never a removal target")

	# --- merge with mixed ownership -----------------------------------------
	var g:=snap()
	var left:=add_room(g,O,Vector2i(2,2),[DOOR],"alice","alice")
	var right:=add_room(g,Vector2i(13,10),Vector2i(2,2),[Vector2i(13,9)],"bob","bob")
	roof_cells(g,left,"alice")
	roof_cells(g,right,"bob")
	var shared:=Vector2i(12,10)
	g.ground[k(shared)]=piece("floor","alice")
	r=quote(g,"alice","remove",shared)
	expect(r.ok and r.affected and r.plan.add.keys()==[k(shared)] and r.plan.remove.is_empty(),"merge keeps both rooms' roofs, roofs exposed floor")
	expect(r.total_cost=={"wood":1,"fiber":3} and r.refunds=={"alice":{"wood":3}},"merge charges actor one roof, refunds wall")
	g.ground.erase(k(shared))
	r=quote(g,"alice","remove",shared)
	expect(r.ok and sorted(r.plan.remove)==keyset(left+right),"merge through gap opens both rooms")
	expect(r.refunds=={"alice":{"wood":7,"fiber":12},"bob":{"wood":4,"fiber":12}},"mixed merge refunds each payer")

	# --- does not select unrelated room -------------------------------------
	c=open_room()
	s=c.s
	var other:=add_room(s,Vector2i(30,10),Vector2i(2,2),[Vector2i(30,9)])
	r=quote(s,"alice","build",GAP,"wall")
	expect(sorted(r.plan.add.keys())==keyset(c.cells) and r.total_cost=={"wood":7,"fiber":12},"unrelated sealed room not roofed")
	for p in other:expect(not r.plan.add.has(k(p)),"unrelated cell untouched")

	# --- batch --------------------------------------------------------------
	var e:=snap()
	var ecells:=add_room(e,O,Vector2i(2,2),[DOOR],"alice","alice",false)
	r=quote(e,"alice","build_area",O,"floor|11|11")
	expect(r.ok and r.base_cost=={"wood":8} and r.total_cost=={"wood":12,"fiber":12} and sorted(r.plan.add.keys())==keyset(ecells),"batch floor closes room")
	r=quote(e,"alice","build_area",Vector2i(11,11),"floor|10|10")
	expect(r.ok and r.total_cost=={"wood":12,"fiber":12},"batch corners in any order")
	r=quote(e,"alice","build_area",Vector2i(40,40),"path|44|44")
	expect(r.ok and not r.affected and r.total_cost=={"stone":50},"25-tile path batch")
	expect(rejected(quote(e,"alice","build_area",Vector2i(40,40),"path|45|44")),"26 tiles rejected")
	expect(rejected(quote(e,"alice","build_area",Vector2i(9,10),"floor|10|10")),"batch over wall rejected")
	r=quote(a,"alice","build_area",Vector2i(50,50),"roof|50|50")
	expect(rejected(r),"batch roof needs floor")
	var lr:=snap()
	var lrcells:=add_room(lr,O,Vector2i(2,2),[DOOR])
	lr.ground[k(lrcells[3])].owner="bob"
	expect(rejected(quote(lr,"alice","build_area",O,"roof|11|11")),"batch roof needs every floor owned")
	r=quote(lr,"alice","build_area",O,"roof|11|10")
	expect(r.ok and not r.affected and r.total_cost=={"wood":2,"fiber":6},"batch manual roof no auto charge")
	expect(rejected(quote(lr,"alice","build_area",O,"wall|11|10")),"batch wall unsupported")

	# --- 400 cell cap -------------------------------------------------------
	var big:=snap()
	for y in 20:
		for x in 21:big.ground[k(Vector2i(100+x,100+y))]=piece("floor","alice")
	r=quote(big,"alice","build",Vector2i(99,100),"floor")
	expect(rejected(r) and r.message.contains("400"),"oversized room rejected, not partial")

	# --- malformed / unsupported --------------------------------------------
	c=open_room()
	s=c.s
	for bad in [["","build",GAP,"wall"],[" alice","build",GAP,"wall"],["alice","dance",GAP,""],["alice","build",GAP,"bed"],["alice","build",GAP,""],
			["alice","build_area",O,"floor|x|1"],["alice","build_area",O,"floor|1"],["alice","build_area",O,"wall|10|10"],["alice","build_area",O,"floor|2000|10"],
			["alice","build",Vector2i(2000000,0),"floor"],["alice","remove",Vector2i(70,70),""]]:
		expect(rejected(Q.quote(s,bad[0],bad[1],bad[2],bad[3])),"rejected %s"%str(bad))
	expect(rejected(Q.quote({"ground":[],"objects":{},"roofs":{}},"alice","build",GAP,"wall")),"non-dictionary layer")
	expect(rejected(Q.quote({"ground":{},"objects":{},"roofs":{},"crops":5},"alice","build",GAP,"wall")),"non-dictionary crops")
	var mal:=s.duplicate(true)
	mal.objects[k(SIDE)]={"type":"wall","owner":7}
	expect(rejected(Q.quote(mal,"alice","remove",SIDE)),"malformed target")
	mal=m.duplicate(true)
	mal.roofs[k(O)]={"type":"roof","auto":true,"owner":null,"items":{}}
	expect(rejected(Q.quote(mal,"alice","remove",SIDE)),"malformed auto roof owner on opening")
	expect(rejected(Q.quote({},"alice","remove",O)),"empty snapshot remove")
	r=Q.quote({},"alice","build",O,"floor")
	expect(r.ok and r.total_cost=={"wood":2},"empty snapshot build still quotes")

	# --- no input mutation / fresh outputs -----------------------------------
	for snapshot in [m,a,g,s,e,lr]:
		var copy:Dictionary=snapshot.duplicate(true)
		for act in [["build",GAP,"wall"],["remove",SIDE,""],["remove",O,""],["build_area",O,"floor|11|11"],["remove",Vector2i(12,10),""]]:
			var out:=Q.quote(snapshot,"alice",act[0],act[1],act[2])
			for key in out.plan.add:out.plan.add[key].items["x"]=1
			for owner in out.refunds:out.refunds[owner]["wood"]=999
			out.base_cost["wood"]=999
			out.base_refund["wood"]=999
		expect(snapshot==copy,"quote never mutates snapshot")
	var build_copy:Dictionary=World.BUILD.duplicate(true)
	r=Q.quote(m,"alice","remove",SIDE)
	r.base_refund.wood=0
	r.refunds.alice.wood=0
	expect(World.BUILD==build_copy and World.BUILD.wall.wood==3,"World.BUILD untouched")
	expect(Q.quote(m,"alice","remove",SIDE).refunds.alice=={"wood":5,"fiber":6},"repeat quote unaffected by caller edits")

	# --- hashed public ids --------------------------------------------------
	var ha:="alice-token".sha256_text().left(16)
	var hb:="bob-token".sha256_text().left(16)
	c=open_room(ha,ha)
	s=c.s
	r=quote(s,ha,"build",GAP,"wall")
	expect(r.ok and r.plan.add.values().all(func(v):return v.owner==ha) and r.total_cost=={"wood":7,"fiber":12},"hashed actor closure")
	expect(not r.message.contains(ha),"message has no id")
	s.objects[k(GAP)]=piece("wall",ha)
	roof_cells(s,c.cells.slice(0,2),hb)
	roof_cells(s,c.cells.slice(2,4),ha)
	r=quote(s,ha,"remove",SIDE)
	expect(r.refunds=={hb:{"wood":2,"fiber":6},ha:{"wood":5,"fiber":6}},"hashed refunds keyed by public id")
	expect(not r.message.contains(ha) and not r.message.contains(hb),"refund message has no ids")
	expect(rejected(quote(s,hb,"remove",SIDE)),"hashed owner check")
	expect(rejected(quote(s,"alice-token","remove",SIDE)),"raw token does not match hashed owner")

	print("AUTO_ROOF_PREVIEW_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
