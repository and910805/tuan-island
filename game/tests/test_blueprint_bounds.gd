extends SceneTree
## Blueprint stage two: limits NOT covered by test_blueprint_world.gd, through
## the real World (quote_blueprint / apply_blueprint / blueprint_receipt /
## undo_summary / act undo_build). docs/blueprint-integration.md 第二段/第三段.
##
## FIXTURE DISCLOSURE (none of this is natural play):
##  * Inventories and device kits are written directly.
##  * Player regions and positions are written directly (incl. mine layers).
##  * state.mine_depths.unlocked is written directly.
##  * 16x16 and other sites are found algorithmically on land that is not water,
##    not protected, not occupied; base trees/rocks/grass inside a chosen site
##    are cleared by writing state.removed[tile]=true (the same marker that a
##    real axe/pick harvest leaves; no resources are granted). Every clearing is
##    printed as "FIXTURE ...".
##  * One explicit cap-boundary fixture sets state.construction.serial to
##    CONSTRUCTION_HISTORY.MAX_SERIAL (schema-valid value).
##  Pre-existing devices for cumulative limits are built by REAL apply_blueprint
##  calls, not injected. Undo clocks use a FakeClock. All saves go to one new
##  per-run user:// directory removed at the end. Missing API = counted failure.
##
## Not covered here: construction-watch overflow (MAX_WATCH 4096). The serial
## cap below is a separate untracked-history path, not equivalent coverage.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")
const SCHEMA=preload("res://scripts/save_schema.gd")
const HISTORY=preload("res://scripts/construction_history.gd")
const MINE_DRILL=preload("res://scripts/mine_drill.gd")
const INDUSTRY=preload("res://scripts/industry.gd")
const LOGISTICS=preload("res://scripts/logistics.gd")
const FORESTRY=preload("res://scripts/forestry.gd")

const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const PARK:=World.SPAWN

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=9000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks
	func advance(seconds:float) -> void:
		utc+=seconds
		ticks+=int(round(seconds*1000.0))

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var clock:FakeClock

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-blueprint-bounds-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		print("BLUEPRINT_BOUNDS_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	var probe=World.new()
	var ready:bool=probe.has_method("quote_blueprint") and probe.has_method("apply_blueprint") and probe.has_method("undo_summary")
	expect(ready,"World exposes quote_blueprint / apply_blueprint / undo_summary")
	var has_receipt:bool=probe.has_method("blueprint_receipt")
	expect(has_receipt,"World exposes blueprint_receipt(token,nonce)")
	expect(HISTORY.MAX_BLUEPRINT_BUILDS==768,"MAX_BLUEPRINT_BUILDS is 768")
	if ready:
		test_full_768()
		test_serial_cap_untracked()
		if has_receipt:test_receipts()
		test_mine_drill()
		test_pump_river_and_limit()
		test_cumulative_device_limits()
	cleanup()
	print("BLUEPRINT_BOUNDS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func cleanup() -> void:
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	expect(DirAccess.remove_absolute(dir)==OK,"isolated test directory removed")

# ---------------------------------------------------------------- fixtures --

func attach(w,c:FakeClock) -> void:
	w.set("undo_clock_utc",Callable(c,"now_utc"))
	w.set("undo_clock_ticks",Callable(c,"now_ticks"))

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300}
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	clock=FakeClock.new()
	attach(w,clock)
	return w

func reload(path:String):
	var loaded=World.new()
	expect(loaded.load_world(path),"saved world reloads: "+path)
	attach(loaded,clock)
	loaded.add_player(A,"Alice")
	loaded.add_player(B,"Bob")
	return loaded

func nonce() -> String:
	serial+=1
	return String.num_int64(serial+0x9000,16).lpad(32,"0")

func piece(kind:String,x:int,y:int) -> Dictionary:
	return {"kind":kind,"x":x,"y":y}

func bp(label:String,width:int,height:int,pieces:Array) -> Dictionary:
	return {"version":1,"name":label,"width":width,"height":height,"pieces":pieces}

func row(kind:String,count:int,label:String) -> Dictionary:
	var pieces:=[]
	for i in count:pieces.append(piece(kind,i,0))
	return bp(label,count,1,pieces)

func column(kind:String,count:int,label:String) -> Dictionary:
	var pieces:=[]
	for i in count:pieces.append(piece(kind,0,i))
	return bp(label,1,count,pieces)

func clear_cell(w,c:Vector2i) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	for f in ["objects","ground","roofs","crops","forest"]:
		if w.state[f].has(k):return false
	return true

## Home only. Rectangle `size` plus a standing column at x-1, >=3 cells from
## spawn and every Rect2i in `avoid`. Base trees/rocks/grass inside are cleared
## via state.removed (disclosed); anything else must already be clear.
func find_cleared_site(w,size:Vector2i,avoid:Array=[],xs:Array=[],ys:Array=[]) -> Vector2i:
	var park:=Vector2i(PARK)
	var columns:Array=xs if not xs.is_empty() else range(3,REGIONS.SIZE.x-size.x-2)
	for oy in (ys if not ys.is_empty() else range(2,REGIONS.SIZE.y-size.y-2)):
		for ox in columns:
			var o:=Vector2i(ox,oy)
			var zone:=Rect2i(o-Vector2i(3,3),size+Vector2i(6,6))
			if zone.has_point(park):continue
			var hit:=false
			for r in avoid:
				if zone.intersects(r):
					hit=true
					break
			if hit:continue
			var cells:Array[Vector2i]=[]
			for y in range(o.y,o.y+size.y):
				cells.append(Vector2i(o.x-1,y))
				for x in range(o.x,o.x+size.x):cells.append(Vector2i(x,y))
			var ok:=true
			var marks:Array[Vector2i]=[]
			for c in cells:
				if not w.is_land(c) or w.water(c) or w.protected(c):
					ok=false
					break
				var k:=World.key(c)
				for f in ["objects","ground","roofs","crops","forest"]:
					if w.state[f].has(k):ok=false
				var r:String=w.resource(c)
				if r in ["tree","rock","grass"]:marks.append(c)
				elif r!="":ok=false
				if not ok:break
			if not ok:continue
			for c in marks:w.state.removed[World.key(c)]=true
			var good:=true
			for c in cells:
				if not clear_cell(w,c):
					good=false
					break
			if good:
				print("FIXTURE cleared %d base resources (state.removed) for %s site at %s"%[marks.size(),size,o])
				return o
			for c in marks:w.state.removed.erase(World.key(c))
	expect(false,"found a clearable %s site"%size)
	return Vector2i(-1,-1)

func zone_of(o:Vector2i,size:Vector2i) -> Rect2i:
	return Rect2i(o-Vector2i(3,3),size+Vector2i(6,6))

func stand(o:Vector2i) -> Vector2:
	return Vector2(o.x-0.5,o.y+0.5)

func pose(w,token:String,at:Vector2) -> void:
	var person:Dictionary=w.state.players[token]
	person.x=at.x
	person.y=at.y
	for t in w.state.players:
		if t!=token and w.state.players[t].get("region",HOME)==person.get("region",HOME):
			var other:Dictionary=w.state.players[t]
			if Vector2(other.x,other.y).distance_to(at)<6.0:
				other.x=PARK.x
				other.y=PARK.y

func place(w,token:String,region:String,at:Vector2) -> void:
	w.state.players[token].region=region
	w.state.players[token].x=at.x
	w.state.players[token].y=at.y

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func full(w) -> String:
	return var_to_str(w.state)

func view(w) -> String:
	var copy:Dictionary=w.state.duplicate(true)
	copy.erase("construction")
	return var_to_str(copy)

func ints(d) -> Dictionary:
	if not d is Dictionary:return {"<invalid>":-1}
	var out:={}
	for k in d:
		var v=d[k]
		if not (v is int or v is float):return {"<invalid>":-1}
		if int(v)!=0:out[str(k)]=int(v)
	return out

func inv(w,token:String) -> Dictionary:
	return ints(w.state.players[token].inventory)

func plus(a:Dictionary,b:Dictionary,sign:int=1) -> Dictionary:
	var out:=ints(a)
	for k in b:
		if k=="name":continue
		out[k]=int(out.get(k,0))+sign*int(b[k])
		if int(out[k])==0:out.erase(k)
	return out

func times(recipe:Dictionary,n:int) -> Dictionary:
	var out:={}
	for k in recipe:
		if k!="name":out[k]=int(recipe[k])*n
	return out

func quote(w,token:String,raw,origin:Vector2i,turns=0) -> Dictionary:
	var region:String=w._region
	var q=w.call("quote_blueprint",token,raw,origin,turns)
	expect(q is Dictionary,"quote returns a Dictionary")
	expect(w._region==region,"quote keeps orientation")
	if not q is Dictionary:return {}
	leak_free(q,"quote")
	return q

func apply(w,token:String,n:String,raw,origin:Vector2i,turns,h:String) -> Dictionary:
	var r=w.call("apply_blueprint",token,n,raw,origin,turns,h)
	expect(r is Dictionary,"apply returns a Dictionary")
	expect(w._region==HOME,"apply leaves home orientation")
	if not r is Dictionary:return {}
	leak_free(r,"apply")
	return r

func quote_apply(w,token:String,raw,origin:Vector2i,label:String) -> Dictionary:
	var q:=quote(w,token,raw,origin)
	expect(q.get("ok")==true,label+": quote ok: "+str(q.get("message")))
	var r:=apply(w,token,nonce(),raw,origin,0,str(q.get("hash","")))
	expect(r.get("ok")==true,label+": applied: "+str(r.get("message")))
	return r

func refuse_apply(w,token:String,raw,origin:Vector2i,h:String,label:String) -> void:
	var snap:=full(w)
	var r:=apply(w,token,nonce(),raw,origin,0,h)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": apply rejected with a reason")
	expect(full(w)==snap,label+": entire state unchanged")

func has_problem(q:Dictionary,cell:Vector2i) -> bool:
	var list=q.get("problems",[])
	if not list is Array:return false
	for p in list:
		if p is Dictionary and Vector2i(int(p.get("x",-99999)),int(p.get("y",-99999)))==cell:return true
	return false

func summary(w,token:String) -> Dictionary:
	var s=w.call("undo_summary",token)
	expect(s is Dictionary,"undo_summary returns a Dictionary")
	return s if s is Dictionary else {}

func saved_valid(w,label:String) -> Dictionary:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	expect(parsed is Dictionary and int(parsed.get("version",0))==SCHEMA.VERSION,"saved document uses current schema")
	if not parsed is Dictionary:return {}
	expect(SCHEMA.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),label+": saved document passes save_schema.validate")
	return parsed

func owned(layer:Dictionary,kind:String,token:String) -> int:
	var n:=0
	for obj in layer.values():
		if obj is Dictionary and obj.get("type")==kind and obj.get("owner")==token:n+=1
	return n

func act_ok(w,token:String,rid:String,action:String,p:Vector2i,extra:String) -> bool:
	return w.act(token,rid,action,p,extra).get("ok",false)==true

# ------------------------------------------------- full 768-piece blueprint --

## 16x16 floors + 256 objects (tables on even x, walls on odd x) + 256 manual roofs.
func full_raw() -> Dictionary:
	var pieces:=[]
	for y in 16:
		for x in 16:
			pieces.append(piece("floor",x,y))
			pieces.append(piece("table" if x%2==0 else "wall",x,y))
			pieces.append(piece("roof",x,y))
	return bp("滿版",16,16,pieces)

func full_cost() -> Dictionary:
	var c:=times(World.BUILD.floor,256)
	c=plus(c,times(World.BUILD.table,128))
	c=plus(c,times(World.BUILD.wall,128))
	return plus(c,times(World.BUILD.roof,256))

func test_full_768() -> void:
	var w=new_world()
	var o:=find_cleared_site(w,Vector2i(16,16))
	if o.x<0:return
	var raw:=full_raw()
	expect(raw.pieces.size()==768,"fixture blueprint has exactly 768 pieces")
	var cost:=full_cost()
	w.state.players[A].inventory=cost.duplicate()  # exact stock (fixture)
	pose(w,A,stand(o))
	expect(w.save(),"768 baseline saved")
	var snap:=full(w)
	var q:=quote(w,A,raw,o)
	expect(q.get("ok")==true,"768-piece quote ok: "+str(q.get("message")))
	expect(int(q.get("pieces",-1))==768,"quote counts 768 pieces")
	expect(ints(q.get("cost"))==cost,"768 cost exact (floor+table+wall+manual roof): "+str(q.get("cost")))
	expect(int(q.get("roof_add",-1))==0 and int(q.get("roof_remove",-1))==0,"no auto roofs for doorless strips")
	expect(q.get("undoable")==true,"768 pieces stay within the undo bound")
	expect(full(w)==snap,"768 quote read-only")
	# One width over the cap (explicit size boundary fixture).
	var wide:=bp("過寬",17,1,[piece("floor",16,0)])
	var qw:=quote(w,A,wide,o)
	expect(qw.get("ok")==false and full(w)==snap,"width 17 rejected without mutation")
	var b0:=int(w.state.players[A].builds)
	var c0:=int(w.state.committed)
	var r:=apply(w,A,nonce(),raw,o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"768 applied: "+str(r.get("message")))
	if r.get("ok")!=true:return
	expect(inv(w,A)=={},"exact 768 stock fully consumed: "+str(inv(w,A)))
	expect(int(w.state.players[A].builds)==b0+768 and int(w.state.committed)==c0+1,"builds +768, one commit")
	var bad:=0
	for y in 16:
		for x in 16:
			var k:=World.key(o+Vector2i(x,y))
			var g=w.state.ground.get(k)
			var ob=w.state.objects.get(k)
			var rf=w.state.roofs.get(k)
			if not (g is Dictionary and g.get("type")=="floor" and g.get("owner")==A):bad+=1
			if not (ob is Dictionary and ob.get("type")==("table" if x%2==0 else "wall") and ob.get("owner")==A):bad+=1
			if not (rf is Dictionary and rf.get("owner")==A and not World.is_auto_roof(rf)):bad+=1
	expect(bad==0,"all 768 pieces on their layers with owner A and manual roofs (%d wrong)"%bad)
	var entry=w.state.construction.last.get(A,{})
	expect(entry.get("action")=="blueprint" and int(entry.get("builds",-1))==768 and entry.get("status")=="live","history: one live blueprint entry with 768 builds")
	saved_valid(w,"768 save")
	# Problem list cap: every piece now collides.
	var snap2:=full(w)
	var again:=quote(w,A,raw,o)
	expect(again.get("ok")==false and again.get("problems",[]).size()==World.BLUEPRINT_MAX_PROBLEMS,"768 collisions report exactly %d problems"%World.BLUEPRINT_MAX_PROBLEMS)
	expect(str(again.get("message","")).contains("768"),"message carries the full collision count: "+str(again.get("message")))
	expect(full(w)==snap2,"collision quote read-only")
	# Persist + reload carries all pieces.
	var loaded=reload(w.save_path)
	expect(loaded.state.ground.size()==w.state.ground.size() and loaded.state.objects.size()==w.state.objects.size() and loaded.state.roofs.size()==w.state.roofs.size(),"reloaded layer sizes match")
	# Whole undo with exact refund.
	clock.advance(3.0)
	var s:=summary(w,A)
	expect(s.get("available")==true,"768 blueprint undoable: "+str(s))
	pose(w,A,stand(o))
	var u:Dictionary=w.act(A,"undo-768","undo_build",o,str(s.get("id","")))
	expect(u.get("ok")==true,"undo 768: "+str(u.get("message")))
	var left:=0
	for y in 16:
		for x in 16:
			var k:=World.key(o+Vector2i(x,y))
			for f in ["ground","objects","roofs"]:
				if w.state[f].has(k):left+=1
	expect(left==0,"undo removed all 768 pieces (%d left)"%left)
	expect(inv(w,A)==cost and int(w.state.players[A].builds)==b0,"undo refunds exact 768 cost and builds")
	saved_valid(w,"768 undo save")

# ------------------------------------- untracked replacement (serial cap) --

func test_serial_cap_untracked() -> void:
	var w=new_world()
	var o:=find_cleared_site(w,Vector2i(3,1),[zone_of(Vector2i(39,33),Vector2i(1,1))])
	if o.x<0:return
	pose(w,A,stand(o))
	expect(act_ok(w,A,"cap-floor","build",o,"floor"),"A's ordinary build (becomes last)")
	var old:=summary(w,A)
	var old_id:=str(old.get("id",""))
	expect(old.get("available")==true and old_id!="","ordinary build undoable before the cap")
	# Explicit cap-boundary fixture: the next record id would exceed MAX_SERIAL.
	w.state.construction.serial=HISTORY.MAX_SERIAL
	print("FIXTURE construction.serial set to MAX_SERIAL=%d"%HISTORY.MAX_SERIAL)
	var raw:=bp("界",1,1,[piece("floor",0,0)])
	var target:=o+Vector2i(2,0)
	var q:=quote(w,A,raw,target)
	expect(q.get("ok")==true,"blueprint quote ok at serial cap")
	expect(q.get("undoable")==false,"quote discloses undoable=false when the record cannot be tracked (serial cap)")
	var r:=apply(w,A,nonce(),raw,target,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"blueprint applies at serial cap: "+str(r.get("message")))
	var s:=summary(w,A)
	expect(s.get("available")!=true and str(s.get("id",""))!=old_id,"old construction never resurfaces as last: "+str(s))
	var entry=w.state.construction.last.get(A)
	expect(entry==null or (entry is Dictionary and entry.get("status")!="live" and entry.get("id")!=old_id),"no live entry and old id gone")
	var before:=view(w)
	var u:Dictionary=w.act(A,"cap-undo-old","undo_build",o,old_id)
	expect(u.get("ok")==false,"undo with the old id refused")
	expect(view(w)==before,"refused old undo changes nothing")
	expect(w.state.ground.has(World.key(o)) and w.state.ground.has(World.key(target)),"both floors kept")
	saved_valid(w,"serial-cap save")
	var loaded=reload(w.save_path)
	expect(summary(loaded,A).get("available")!=true,"after reload the old construction is still not undoable")

# --------------------------------------------------------------- receipts --

func test_receipts() -> void:
	var w=new_world()
	var o:=find_cleared_site(w,Vector2i(3,1))
	if o.x<0:return
	var ob:=find_cleared_site(w,Vector2i(2,1),[zone_of(o,Vector2i(3,1))])
	if ob.x<0:return
	pose(w,A,stand(o))
	var raw:=bp("收據",2,1,[piece("floor",0,0),piece("floor",1,0)])
	var q:=quote(w,A,raw,o)
	var h1:=str(q.get("hash",""))
	var n1:=nonce()
	# Nonce of a rejected apply never yields a receipt.
	var n_fail:=nonce()
	apply(w,A,n_fail,raw,o,0,"f".repeat(64))
	expect(w.blueprint_receipt(A,n_fail)=={},"requoted nonce has no receipt")
	var r1:=apply(w,A,n1,raw,o,0,h1)
	expect(r1.get("ok")==true,"receipt blueprint applied: "+str(r1.get("message")))
	if r1.get("ok")!=true:return
	var got=w.blueprint_receipt(A,n1)
	expect(got is Dictionary and var_to_str(got)==var_to_str(r1),"blueprint_receipt returns the apply result")
	leak_free(got,"blueprint_receipt")
	# Deep copy: mutating the returned value (top level and nested) never reaches state.
	var stored_text:=var_to_str(w.state.players[A].receipts["blueprint:"+n1])
	if got is Dictionary:
		got.ok=false
		got.pieces=999
		if got.get("cost") is Dictionary:got.cost["wood"]=-1
	expect(var_to_str(w.state.players[A].receipts["blueprint:"+n1])==stored_text,"mutating returned receipt leaves stored receipt intact")
	expect(var_to_str(w.blueprint_receipt(A,n1))==var_to_str(r1),"fresh lookup unaffected by caller mutation")
	# Invalid inputs return {} and mutate nothing, including orientation.
	w.switch_region(LANYANG)
	var snap:=full(w)
	var bad_ok:=true
	for bad in ["","A"+n1.substr(1),n1.substr(1),n1+"0","blueprint:"+n1," "+n1.substr(1),"g"+n1.substr(1)]:
		bad_ok=bad_ok and w.blueprint_receipt(A,bad)=={}
	expect(bad_ok,"malformed nonces return {}")
	expect(w.blueprint_receipt("tok-nobody",n1)=={},"unknown token returns {}")
	expect(w.blueprint_receipt(B,n1)=={},"another player cannot read A's receipt")
	expect(w.blueprint_receipt(A,nonce())=={},"unused nonce returns {}")
	var mid=w.blueprint_receipt(A,n1)
	expect(w._region==LANYANG and full(w)==snap,"lookups keep LANYANG orientation and state unchanged")
	expect(mid is Dictionary and mid.get("ok")==true,"lookup works while oriented elsewhere")
	w.switch_region(HOME)
	# Owner separation: B uses the same nonce string for B's own blueprint.
	pose(w,B,stand(ob))
	var rawb:=bp("乙",2,1,[piece("floor",0,0),piece("floor",1,0)])
	var qb:=quote(w,B,rawb,ob)
	var rb:=apply(w,B,n1,rawb,ob,0,str(qb.get("hash","")))
	expect(rb.get("ok")==true and w.state.ground.get(World.key(ob),{}).get("owner")==B,"B's same nonce string builds B's own blueprint (receipts are per player)")
	expect(var_to_str(w.blueprint_receipt(B,n1))==var_to_str(rb) and var_to_str(w.blueprint_receipt(A,n1))==var_to_str(r1),"each player's receipt under the shared nonce is separate")
	# Reload keeps the receipt.
	var loaded=reload(w.save_path)
	var lr=loaded.blueprint_receipt(A,n1)
	expect(lr is Dictionary and HISTORY.canonical(lr)==HISTORY.canonical(r1),"receipt survives reload")
	# Undo the blueprint; the receipt is retained and the same nonce does not rebuild.
	clock.advance(2.0)
	pose(w,A,stand(o))
	var s:=summary(w,A)
	expect(s.get("available")==true,"receipt blueprint undoable: "+str(s))
	var u:Dictionary=w.act(A,"rcpt-undo","undo_build",o,str(s.get("id","")))
	expect(u.get("ok")==true,"receipt blueprint undone: "+str(u.get("message")))
	expect(not w.state.ground.has(World.key(o)),"floor removed by undo")
	var after_undo:=full(w)
	var replay:=apply(w,A,n1,raw,o,0,h1)
	expect(var_to_str(replay)==var_to_str(r1),"replay after undo returns stored receipt")
	expect(full(w)==after_undo and not w.state.ground.has(World.key(o)),"replay after undo rebuilds nothing, charges nothing")
	expect(var_to_str(w.blueprint_receipt(A,n1))==var_to_str(r1),"receipt retained after undo")
	# Ordinary act receipt with a hex request id is not a blueprint receipt
	# (done after the undo so it never replaces the blueprint as A's last build).
	var hex_rid:=nonce()
	pose(w,A,stand(o))
	expect(act_ok(w,A,hex_rid,"build",o+Vector2i(2,0),"floor"),"ordinary act with hex request id")
	expect(w.blueprint_receipt(A,hex_rid)=={},"plain act receipt is not returned as a blueprint receipt")
	expect(act_ok(w,A,"rcpt-rm0","remove",o+Vector2i(2,0),""),"ordinary floor removed again")
	# 128-receipt bound: n1 is the oldest; fill to exactly 128, then one more evicts it.
	var receipts:Dictionary=w.state.players[A].receipts
	expect(receipts.keys()[0]=="blueprint:"+n1,"blueprint receipt is A's oldest")
	var need:=128-receipts.size()
	var cell:=o+Vector2i(2,0)
	var acts_ok:=true
	for i in need:
		pose(w,A,stand(o))
		acts_ok=acts_ok and act_ok(w,A,"trim-%d"%i,"build" if i%2==0 else "remove",cell,"floor" if i%2==0 else "")
	expect(acts_ok and w.state.players[A].receipts.size()==128,"%d ordinary acts fill receipts to 128"%need)
	expect(w.blueprint_receipt(A,n1).get("ok")==true,"blueprint receipt retained at exactly 128")
	pose(w,A,stand(o))
	var tail_action:="build" if need%2==0 else "remove"
	expect(act_ok(w,A,"trim-last",tail_action,cell,"floor" if tail_action=="build" else ""),"129th receipt act")
	expect(w.state.players[A].receipts.size()==128 and w.blueprint_receipt(A,n1)=={},"129th receipt evicts the blueprint receipt")
	# Documented bound: an evicted nonce is NOT permanently deduplicated.
	pose(w,A,stand(o))
	var inv0:=inv(w,A)
	var evicted:=apply(w,A,n1,raw,o,0,h1)
	if evicted.get("requote")==true and evicted.get("quote") is Dictionary:
		evicted=apply(w,A,n1,raw,o,0,str(evicted.quote.get("hash","")))
	expect(evicted.get("ok")==true and w.state.ground.get(World.key(o),{}).get("owner")==A,"evicted nonce is processed as a fresh apply (128-receipt bound, not permanent dedup)")
	expect(inv(w,A)==plus(inv0,times(World.BUILD.floor,2),-1),"fresh apply charges again")
	saved_valid(w,"receipt save")

# -------------------------------------------------------------- mine drill --

func drill_cells(w,region:String) -> Array[Vector2i]:
	w.switch_region(region)
	var out:Array[Vector2i]=[]
	for d in MINE_DRILL.DIRECTIONS:
		var c:Vector2i=MINE_DRILL.NODE-d
		if w.is_land(c) and not w.water(c) and not w.protected(c) and not w.state.objects.has(World.key(c)) and MINE_DRILL.placement(c)>=0:out.append(c)
	w.switch_region(HOME)
	return out

func drill_raw() -> Dictionary:
	return bp("採掘",1,1,[piece("mine_drill",0,0)])

func mine_stand(c:Vector2i) -> Vector2:
	return Vector2(c.x-2.0,c.y+0.5)

func test_mine_drill() -> void:
	var w=new_world()
	for t in [A,B]:w.state.players[t].inventory["mine_drill_kit"]=5
	var cells:=drill_cells(w,"mine_1")
	expect(cells.size()>=2,"at least two designated drill cells in mine_1")
	if cells.size()<2:return
	var c:=cells[0]
	place(w,A,"mine_1",mine_stand(c))
	w.state.mine_depths.unlocked=4
	w.state.mine_depths.pumped=24 # explicit completed pumping prerequisite
	var q:=quote(w,A,drill_raw(),c)
	expect(q.get("ok")==false and has_problem(q,c),"drill locked before mine level 5")
	w.state.mine_depths.unlocked=5
	# Wrong region: same coordinates at home are not a drill site.
	var home:=find_cleared_site(w,Vector2i(1,1))
	if home.x>=0:
		place(w,A,HOME,stand(home))
		q=quote(w,A,drill_raw(),home)
		expect(q.get("ok")==false and has_problem(q,home),"drill rejected outside mine layers")
	# Non-designated mine cell.
	w.switch_region("mine_1")
	var off:=Vector2i(-1,-1)
	for d in [Vector2i(1,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(2,0),Vector2i(-2,0)]:
		var t:Vector2i=MINE_DRILL.NODE+d
		if w.is_land(t) and not w.water(t) and not w.protected(t) and not w.blocked(t):
			off=t
			break
	w.switch_region(HOME)
	expect(off.x>=0,"found an off-site mine cell")
	if off.x>=0:
		place(w,A,"mine_1",mine_stand(off))
		q=quote(w,A,drill_raw(),off)
		expect(q.get("ok")==false and has_problem(q,off),"drill rejected away from the designated node")
	# Two drills in one blueprint on one layer.
	var c2:=cells[1]
	var corner:=Vector2i(mini(c.x,c2.x),mini(c.y,c2.y))
	var pair:=bp("雙機",absi(c.x-c2.x)+1,absi(c.y-c2.y)+1,[piece("mine_drill",c.x-corner.x,c.y-corner.y),piece("mine_drill",c2.x-corner.x,c2.y-corner.y)])
	place(w,A,"mine_1",mine_stand(corner))
	q=quote(w,A,pair,corner)
	expect(q.get("ok")==false,"two drills on one layer in one blueprint rejected")
	# Valid drill in mine_1.
	place(w,A,"mine_1",mine_stand(c))
	quote_apply(w,A,drill_raw(),c,"drill mine_1")
	var drill=w.state.regions["mine_1"].objects.get(World.key(c))
	expect(drill is Dictionary and drill.get("owner")==A and int(drill.get("dir",-1))==MINE_DRILL.placement(c) and drill.get("enabled")==false,"drill stored in mine_1 with node-facing dir")
	expect(not w.state.objects.has(World.key(c)),"home layer untouched by mine drill")
	# One per layer: B cannot add a second drill on mine_1.
	place(w,B,"mine_1",mine_stand(c2))
	q=quote(w,B,drill_raw(),c2)
	expect(q.get("ok")==false and has_problem(q,c2),"second drill on the same layer rejected (other owner)")
	place(w,B,HOME,PARK)
	# Global per-person count.
	var c_m2:=drill_cells(w,"mine_2")
	var c_m3:=drill_cells(w,"mine_3")
	if c_m2.is_empty() or c_m3.is_empty():
		expect(false,"designated drill cells exist in mine_2 and mine_3")
		return
	place(w,A,"mine_2",mine_stand(c_m2[0]))
	quote_apply(w,A,drill_raw(),c_m2[0],"drill mine_2")
	expect(w.device_count(A,"mine_drill")==MINE_DRILL.LIMIT,"A owns the world-wide drill limit")
	place(w,A,"mine_3",mine_stand(c_m3[0]))
	q=quote(w,A,drill_raw(),c_m3[0])
	expect(q.get("ok")==false and has_problem(q,c_m3[0]),"third drill in a fresh layer rejected by the global count")
	place(w,B,"mine_3",mine_stand(c_m3[0]))
	expect(quote(w,B,drill_raw(),c_m3[0]).get("ok")==true,"control: B (no drills) may build on that layer")
	saved_valid(w,"drill save")

# ------------------------------------------------------------ pump / river --

func test_pump_river_and_limit() -> void:
	var w=new_world()
	w.state.players[A].inventory["pump_kit"]=10
	var col:=find_cleared_site(w,Vector2i(1,5),[],[53],range(15,23))
	if col.x<0:return
	var near_all:=true
	for i in 5:near_all=near_all and INDUSTRY.near_river(w,col+Vector2i(0,i))
	expect(near_all,"x=53 column is within two cells of the river")
	var far:=find_cleared_site(w,Vector2i(1,1),[Rect2i(44,0,20,60)])
	if far.x>=0:
		expect(not INDUSTRY.near_river(w,far),"far cell is away from water")
		pose(w,A,stand(far))
		var qf:=quote(w,A,column("water_pump",1,"遠泵"),far)
		expect(qf.get("ok")==false and has_problem(qf,far),"pump away from the river rejected")
	pose(w,A,stand(col))
	var limit:int=INDUSTRY.LIMITS.water_pump
	var q:=quote(w,A,column("water_pump",limit+1,"泵"),col)
	expect(q.get("ok")==false and has_problem(q,col+Vector2i(0,limit)),"%d pumps exceed the limit, problem on the extra one"%(limit+1))
	refuse_apply(w,A,column("water_pump",limit+1,"泵"),col,str(q.get("hash","")),"pump over limit")
	quote_apply(w,A,column("water_pump",limit,"泵"),col,"pumps at limit")
	expect(owned(w.state.objects,"water_pump",A)==limit,"A owns exactly %d pumps"%limit)

# ----------------------------------------------- cumulative device limits --

func test_cumulative_device_limits() -> void:
	var w=new_world()
	w.state.players[A].inventory.merge({"conveyor_kit":300,"pipe_kit":300,"tank_kit":20,"forester_kit":6},true)
	var s1:=find_cleared_site(w,Vector2i(16,16))
	if s1.x<0:return
	var belt_limit:int=LOGISTICS.BELT_LIMIT
	var pipe_limit:int=INDUSTRY.LIMITS.water_pipe
	expect(belt_limit-1<=128 and pipe_limit-1<=128,"prebuild fits 16x8 halves")
	var pieces:=[]
	for i in belt_limit-1:pieces.append(piece("conveyor",i%16,int(i/16.0)))
	for i in pipe_limit-1:pieces.append(piece("water_pipe",i%16,8+int(i/16.0)))
	pose(w,A,stand(s1))
	quote_apply(w,A,bp("預建",16,16,pieces),s1,"prebuild %d belts + %d pipes"%[belt_limit-1,pipe_limit-1])
	var avoid:=[zone_of(s1,Vector2i(16,16))]
	var tank_limit:int=INDUSTRY.LIMITS.water_tank
	var width:=tank_limit-1+FORESTRY.LIMIT-1
	var s2:=find_cleared_site(w,Vector2i(width,1),avoid)
	if s2.x<0:return
	avoid.append(zone_of(s2,Vector2i(width,1)))
	var p2:=[]
	for i in tank_limit-1:p2.append(piece("water_tank",i,0))
	for i in FORESTRY.LIMIT-1:p2.append(piece("forester",tank_limit-1+i,0))
	pose(w,A,stand(s2))
	quote_apply(w,A,bp("預建二",width,1,p2),s2,"prebuild tanks/forester")
	var counts:={"conveyor":belt_limit,"water_pipe":pipe_limit,"water_tank":tank_limit,"forester":FORESTRY.LIMIT}
	var ok_pre:=true
	for kind in counts:ok_pre=ok_pre and owned(w.state.objects,kind,A)==int(counts[kind])-1
	expect(ok_pre,"every kind is one below its limit")
	var s3:=find_cleared_site(w,Vector2i(2,1),avoid)
	if s3.x<0:return
	pose(w,A,stand(s3))
	var snap:=full(w)
	for kind in counts:
		var q:=quote(w,A,row(kind,2,"加"),s3)
		expect(q.get("ok")==false and has_problem(q,s3+Vector2i(1,0)) and not has_problem(q,s3),"%s: existing %d + 2 exceeds limit at the second piece"%[kind,int(counts[kind])-1])
		expect(quote(w,A,row(kind,1,"加"),s3).get("ok")==true,"%s: existing + 1 reaches the limit"%kind)
	expect(full(w)==snap,"limit quotes read-only")
	quote_apply(w,A,row("conveyor",1,"滿"),s3,"last allowed belt")
	expect(owned(w.state.objects,"conveyor",A)==belt_limit,"A owns exactly %d belts"%belt_limit)
	var q2:=quote(w,A,row("conveyor",1,"超"),s3+Vector2i(1,0))
	expect(q2.get("ok")==false,"belt after reaching the limit rejected")
	refuse_apply(w,A,row("conveyor",1,"超"),s3+Vector2i(1,0),str(q2.get("hash","")),"belt over cumulative limit")
	# Region-local limit control: another player is unaffected.
	w.state.players[B].inventory["conveyor_kit"]=2
	pose(w,B,stand(s3))
	expect(quote(w,B,row("conveyor",1,"乙"),s3+Vector2i(1,0)).get("ok")==true,"control: B's belt limit is independent of A's")
	saved_valid(w,"limits save")
