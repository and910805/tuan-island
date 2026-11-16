extends SceneTree
## Headless unit test for the pure cooking queue helper (res://scripts/cooking_queue.gd).
## Isolated helper fixtures only: no World instance, no networking, no natural play.
## Expected costs, durations, yields and timestamps below are hand-transcribed numbers,
## not values recomputed with the helper's own logic.
## Run: godot --headless --path game --script res://tests/test_cooking_queue.gd

const World=preload("res://scripts/world.gd")
const Q=preload("res://scripts/cooking_queue.gd")
const INV_CAP:=1000000000
const BASE_KEYS:=["id","kind","owner","ingredients","yield","recipe_version","duration"]
const ACTIVE_KEYS:=["id","kind","owner","ingredients","yield","recipe_version","duration","started","finish"]
const READY_KEYS:=["id","kind","owner","ingredients","yield","recipe_version","duration","completed"]
const UPPER_ID:="0123456789ABCDEF0123456789ABCDEF"
# Independent expectations (World.RECIPES as shipped at T036 groundwork time).
const EXP:={
	"soup":{"ingredients":{"radish":2},"time":10.0,"yield":2},
	"bread":{"ingredients":{"wheat":2},"time":15.0,"yield":1},
	"feed":{"ingredients":{"wheat":1,"fiber":2},"time":5.0,"yield":4},
}

var checks:=0
var failures:=0
var R:Dictionary={}

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:
	call_deferred("run")

func run()->void:
	R=World.RECIPES
	test_recipe_expectations()
	test_sugar_recipe_transition()
	test_empty_state()
	test_fifo_deductions_and_boundaries()
	test_fractional_time_boundary()
	test_capacity_includes_ready()
	test_large_step_and_split_ticks()
	test_no_mutable_aliasing()
	test_cancel_ownership_and_restart()
	test_overdue_requires_advance()
	test_refund_and_claim_overflow()
	test_shared_single_claims()
	test_id_owner_kind_and_time_arguments()
	test_validate_matrix()
	test_recipe_inputs_fail_closed()
	test_json_roundtrip_continues()
	test_legacy_import()
	print("COOKING_QUEUE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func test_sugar_recipe_transition()->void:
	var old_catalog:=R.duplicate(true)
	old_catalog.sugar.ingredients={"sugar_beet":1}
	old_catalog.sugar.time=40.0
	var old_batch:=Q.enqueue(Q.empty_state(),old_catalog,0.0,"alice","sugar",hid(1),{"sugar_beet":1})
	var restored:Dictionary=JSON.parse_string(JSON.stringify(old_batch.state))
	expect(Q.validate(restored,R,0.0),"old sugar queue remains valid with new catalog")
	var old_ready:=Q.advance(restored,R,40.0)
	var old_claim:=Q.claim(old_ready.state,R,40.0,{})
	expect(old_claim.ok and int(old_claim.inventory.sugar)==2,"old paid batch still yields two sugar at 40 seconds")
	expect(not Q.enqueue(Q.empty_state(),R,0.0,"alice","sugar",hid(1),{"sugar_beet":1}).ok,"new sugar requires two beets")
	var new_batch:=Q.enqueue(Q.empty_state(),R,0.0,"alice","sugar",hid(1),{"sugar_beet":2})
	expect(new_batch.ok and int(new_batch.inventory.get("sugar_beet",0))==0 and float(new_batch.state.active.finish)==60.0,"new sugar uses two beets and finishes after one minute")

# ---------------------------------------------------------------- helpers

func hid(n:int)->String:
	return ("%x"%n).lpad(32,"0")

func snap(v:Variant)->String:
	return var_to_str(v)

## Order-insensitive, int/float-insensitive structural text used for semantic equality.
func canon(v:Variant)->String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d:Dictionary=v
			var entries:Array=[]
			for k in d:entries.append(str(k)+"="+canon(d[k]))
			entries.sort()
			var parts:PackedStringArray=PackedStringArray(entries)
			return "{"+",".join(parts)+"}"
		TYPE_ARRAY:
			var parts:PackedStringArray=PackedStringArray()
			for x in (v as Array):parts.append(canon(x))
			return "["+",".join(parts)+"]"
		TYPE_INT,TYPE_FLOAT:
			return "%.6f"%float(v)
		TYPE_STRING:
			return "\""+str(v)+"\""
	return var_to_str(v)

func is_ok(r:Variant)->bool:
	if not r is Dictionary:return false
	var flag:Variant=(r as Dictionary).get("ok",null)
	return typeof(flag)==TYPE_BOOL and bool(flag)

func msg(r:Variant)->String:
	if r is Dictionary:return str((r as Dictionary).get("message",""))
	return "<non-dictionary result>"

func sub_dict(d:Variant,key:String)->Dictionary:
	if d is Dictionary:
		var v:Variant=(d as Dictionary).get(key,null)
		if v is Dictionary:return v
	return {}

func sub_array(d:Variant,key:String)->Array:
	if d is Dictionary:
		var v:Variant=(d as Dictionary).get(key,null)
		if v is Array:return v
	return []

func sval(d:Variant,key:String)->String:
	if d is Dictionary:
		var v:Variant=(d as Dictionary).get(key,null)
		if v is String:return v
		return "<%s>"%type_string(typeof(v))
	return "<not-dictionary>"

func num(d:Variant,key:String)->float:
	if d is Dictionary:
		var v:Variant=(d as Dictionary).get(key,null)
		if typeof(v)==TYPE_INT or typeof(v)==TYPE_FLOAT:return float(v)
	return NAN

func ok_state(r:Variant,label:String)->Dictionary:
	expect(is_ok(r),label+" ("+msg(r)+")")
	return sub_dict(r,"state")

func ok_inv(r:Variant)->Dictionary:
	return sub_dict(r,"inventory")

func expect_reject(r:Variant,label:String)->void:
	var shaped:bool=r is Dictionary and (r as Dictionary).get("ok",null) is bool
	expect(shaped and not is_ok(r),label+" is rejected with ok=false")
	expect(r is Dictionary and (r as Dictionary).get("message",null) is String and msg(r)!="",label+" explains the failure")

func keys_are(d:Variant,keys:Array)->bool:
	if not d is Dictionary:return false
	var dd:Dictionary=d
	if dd.size()!=keys.size():return false
	for k in keys:
		if not dd.has(k):return false
	return true

func ids(list:Array)->Array:
	var out:Array=[]
	for x in list:out.append(sval(x,"id"))
	return out

func completions(list:Array)->Array:
	var out:Array=[]
	for x in list:out.append(num(x,"completed"))
	return out

func total_jobs(s:Dictionary)->int:
	return sub_array(s,"waiting").size()+sub_array(s,"ready").size()+(0 if sub_dict(s,"active").is_empty() else 1)

func rec(id:String,kind:String,owner:String)->Dictionary:
	var e:Dictionary=EXP[kind]
	return {"id":id,"kind":kind,"owner":owner,"ingredients":(e.ingredients as Dictionary).duplicate(true),"yield":int(e.yield),"recipe_version":1,"duration":float(e.time)}

func active_rec(id:String,kind:String,owner:String,started:float,finish:float)->Dictionary:
	var r:Dictionary=rec(id,kind,owner)
	r["started"]=started
	r["finish"]=finish
	return r

func ready_rec(id:String,kind:String,owner:String,completed:float)->Dictionary:
	var r:Dictionary=rec(id,kind,owner)
	r["completed"]=completed
	return r

func plenty()->Dictionary:
	return {"radish":100,"wheat":100,"fiber":100}

## soup, bread, feed, soup, bread, feed all queued at t=0; alice owns odd ids, bob even.
func six_at_zero()->Dictionary:
	var s:Dictionary=Q.empty_state()
	var inv:Dictionary=plenty()
	var kinds:Array[String]=["soup","bread","feed","soup","bread","feed"]
	for i in 6:
		var owner:String="alice" if i%2==0 else "bob"
		var r:Dictionary=Q.enqueue(s,R,0.0,owner,kinds[i],hid(i+1),inv)
		s=ok_state(r,"fixture enqueue %d"%(i+1))
		inv=ok_inv(r)
	expect(canon(inv)==canon({"radish":96,"wheat":94,"fiber":96}),"six-job fixture charged 2x soup, 2x bread, 2x feed exactly")
	return s

func advance_ok(s:Dictionary,now:float,label:String)->Dictionary:
	var r:Dictionary=Q.advance(s,R,now)
	return ok_state(r,label)

## Safe mutation of a helper-owned dictionary (a read-only alias would be a bug, not a crash).
func poke(d:Dictionary,key:Variant,value:Variant,label:String)->void:
	if d.is_read_only():
		expect(false,label+": helper output is a read-only alias")
		return
	d[key]=value

# ---------------------------------------------------------------- tests

func test_recipe_expectations()->void:
	for kind in EXP:
		var e:Dictionary=EXP[kind]
		var got:Variant=R.get(kind,null)
		expect(got is Dictionary,"World.RECIPES still defines "+str(kind))
		if not got is Dictionary:continue
		var g:Dictionary=got
		expect(canon(g.get("ingredients",{}))==canon(e.ingredients),str(kind)+" ingredients match independent expectation")
		expect(num(g,"time")==float(e.time),str(kind)+" duration matches independent expectation")
		expect(num(g,"yield")==float(e.yield),str(kind)+" yield matches independent expectation")

func test_empty_state()->void:
	var e:Dictionary=Q.empty_state()
	expect(keys_are(e,["active","waiting","ready"]),"empty state has exactly active/waiting/ready")
	expect(e.get("active") is Dictionary and sub_dict(e,"active").is_empty(),"empty active is an empty dictionary")
	expect(e.get("waiting") is Array and sub_array(e,"waiting").is_empty(),"empty waiting is an empty array")
	expect(e.get("ready") is Array and sub_array(e,"ready").is_empty(),"empty ready is an empty array")
	expect(Q.validate(e,R,0.0),"empty state validates at time zero")
	expect(Q.validate(e,R,12345.5),"empty state validates at a later fractional time")
	for bad_now in [NAN,INF,-INF,-1.0]:
		expect(not Q.validate(e,R,bad_now),"validate rejects now=%s"%str(bad_now))
	var ew:=sub_array(e,"waiting")
	expect(not ew.is_read_only() and not e.is_read_only(),"empty_state is caller-owned, not a read-only constant")
	if not ew.is_read_only():ew.append("junk")
	var again:Dictionary=Q.empty_state()
	expect(sub_array(again,"waiting").is_empty(),"empty_state returns a fresh value, no shared global")
	var adv:Dictionary=Q.advance(Q.empty_state(),R,5.0)
	expect(is_ok(adv) and adv.get("changed",null)==false,"advancing an empty kitchen reports changed=false")

func test_fifo_deductions_and_boundaries()->void:
	var alice:Dictionary={"radish":5,"wheat":3,"fiber":2,"gem":7}
	var bob:Dictionary={"wheat":4,"fiber":9}
	var s0:Dictionary=Q.empty_state()
	var s0_snap:=snap(s0)
	var alice_snap:=snap(alice)
	var r1:Dictionary=Q.enqueue(s0,R,100.0,"alice","soup",hid(1),alice)
	var s1:=ok_state(r1,"alice queues soup on an idle stove")
	var a1:=ok_inv(r1)
	expect(snap(s0)==s0_snap and snap(alice)==alice_snap,"successful enqueue does not mutate its arguments")
	expect(canon(a1)==canon({"radish":3,"wheat":3,"fiber":2,"gem":7}),"soup deducts exactly 2 radish and keeps unrelated gem")
	expect(typeof(a1.get("radish"))==TYPE_INT and typeof(a1.get("gem"))==TYPE_INT,"inventory counts stay integers")
	var act1:=sub_dict(s1,"active")
	expect(keys_are(act1,ACTIVE_KEYS),"active record has exactly the canonical active fields")
	expect(sval(act1,"id")==hid(1) and sval(act1,"kind")=="soup" and sval(act1,"owner")=="alice","active record identifies the job")
	expect(num(act1,"started")==100.0 and num(act1,"finish")==110.0,"idle stove starts at now=100 and finishes at 110")
	expect(canon(act1.get("ingredients"))==canon({"radish":2}) and num(act1,"yield")==2.0 and num(act1,"recipe_version")==1.0,"active record stores exact soup cost, yield and version")
	expect(sub_array(s1,"waiting").is_empty() and sub_array(s1,"ready").is_empty(),"nothing waiting or ready after first enqueue")
	expect(Q.validate(s1,R,100.0),"enqueue result validates")

	var r2:Dictionary=Q.enqueue(s1,R,101.0,"bob","bread",hid(2),bob)
	var s2:=ok_state(r2,"bob queues bread behind soup")
	expect(canon(ok_inv(r2))==canon({"wheat":2,"fiber":9}),"bread deducts exactly 2 wheat from bob")
	expect(canon(sub_dict(s2,"active"))==canon(act1),"queuing behind a busy stove leaves the active job alone")
	var w2:=sub_array(s2,"waiting")
	expect(w2.size()==1 and keys_are(w2[0] if w2.size()>0 else null,BASE_KEYS),"waiting record has exactly the canonical waiting fields")

	var r3:Dictionary=Q.enqueue(s2,R,102.0,"alice","feed",hid(3),a1)
	var s3:=ok_state(r3,"alice queues feed third")
	var a3:=ok_inv(r3)
	expect(int(a3.get("radish",-1))==3 and int(a3.get("wheat",-1))==2 and int(a3.get("fiber",0))==0 and int(a3.get("gem",-1))==7,"feed deducts exactly 1 wheat and 2 fiber")
	expect(canon(ids(sub_array(s3,"waiting")))==canon([hid(2),hid(3)]),"waiting order is FIFO bread then feed")

	var s3_snap:=snap(s3)
	var a3_snap:=snap(a3)
	expect_reject(Q.enqueue(s3,R,103.0,"alice","feed",hid(4),a3),"feed without enough fiber")
	expect(snap(s3)==s3_snap and snap(a3)==a3_snap,"insufficient-ingredient rejection mutates nothing")

	var adv_early:Dictionary=Q.advance(s3,R,109.75)
	expect(is_ok(adv_early) and adv_early.get("changed",null)==false,"advance just before finish reports no change")
	expect(canon(sub_dict(adv_early,"state"))==canon(s3),"advance just before finish keeps the state")
	var s4:=advance_ok(s3,110.0,"advance exactly at soup finish")
	var rd4:=sub_array(s4,"ready")
	expect(canon(ids(rd4))==canon([hid(1)]) and canon(completions(rd4))==canon([110.0]),"soup completes at the boundary now==finish with completed=110")
	expect(rd4.size()==1 and keys_are(rd4[0],READY_KEYS),"ready record has exactly the canonical ready fields")
	var act4:=sub_dict(s4,"active")
	expect(sval(act4,"id")==hid(2) and num(act4,"started")==110.0 and num(act4,"finish")==125.0,"bread promoted at soup finish 110 and ends 125")
	expect(canon(ids(sub_array(s4,"waiting")))==canon([hid(3)]),"feed still waiting")
	var again:Dictionary=Q.advance(s4,R,110.0)
	expect(is_ok(again) and again.get("changed",null)==false and canon(sub_dict(again,"state"))==canon(s4),"repeating advance at the same now is idempotent")
	var s5:=advance_ok(s4,125.0,"advance to bread finish")
	expect(canon(completions(sub_array(s5,"ready")))==canon([110.0,125.0]),"bread completed at 125")
	var act5:=sub_dict(s5,"active")
	expect(sval(act5,"id")==hid(3) and num(act5,"started")==125.0 and num(act5,"finish")==130.0,"feed promoted at 125 and ends 130")
	var s6:=advance_ok(s5,130.0,"advance to feed finish")
	expect(canon(ids(sub_array(s6,"ready")))==canon([hid(1),hid(2),hid(3)]) and canon(completions(sub_array(s6,"ready")))==canon([110.0,125.0,130.0]),"mixed FIFO completes soup, bread, feed in order")
	expect(sub_dict(s6,"active").is_empty() and sub_array(s6,"waiting").is_empty(),"kitchen idle after all three finish")
	expect(Q.validate(s6,R,130.0),"final state validates")

func test_fractional_time_boundary()->void:
	var r:Dictionary=Q.enqueue(Q.empty_state(),R,100.25,"alice","soup",hid(0x51),{"radish":2})
	var s:=ok_state(r,"enqueue at fractional time")
	expect(num(sub_dict(s,"active"),"finish")==110.25,"fractional start 100.25 finishes at 110.25")
	expect(is_ok(r) and int(ok_inv(r).get("radish",0))==0,"last two radish consumed")
	var early:Dictionary=Q.advance(s,R,110.2490234375)
	expect(is_ok(early) and early.get("changed",null)==false,"not complete a hair before 110.25")
	var done:=advance_ok(s,110.25,"advance at fractional boundary")
	expect(canon(completions(sub_array(done,"ready")))==canon([110.25]),"completes exactly at fractional finish")

func test_capacity_includes_ready()->void:
	var s:=six_at_zero()
	var inv:Dictionary=plenty()
	for i in range(7,11):
		s=ok_state(Q.enqueue(s,R,0.0,"carol","soup",hid(i),inv),"fill original ten-job capacity")
	expect(total_jobs(s)==10,"fixture holds ten jobs")
	var s_snap:=snap(s)
	var inv_snap:=snap(inv)
	expect_reject(Q.enqueue(s,R,1.0,"carol","soup",hid(11),inv),"eleventh job while ten queued")
	expect(snap(s)==s_snap and snap(inv)==inv_snap,"capacity rejection mutates nothing")
	var done:=advance_ok(s,1000.0,"finish all ten")
	expect(sub_array(done,"ready").size()==10,"ten ready records")
	expect_reject(Q.enqueue(done,R,1000.0,"carol","soup",hid(11),inv),"eleventh job while ten are ready and unclaimed")
	var c:Dictionary=Q.claim(done,R,1000.0,{})
	var after:=ok_state(c,"claim frees one slot")
	var e:Dictionary=Q.enqueue(after,R,1000.0,"carol","soup",hid(11),inv)
	var s7:=ok_state(e,"enqueue after claim fits under capacity")
	var act:=sub_dict(s7,"active")
	expect(sval(act,"id")==hid(11) and num(act,"started")==1000.0 and num(act,"finish")==1010.0,"idle stove with ready food starts new job immediately")
	expect(total_jobs(s7)==10,"total is ten again")
	expect_reject(Q.enqueue(s7,R,1000.0,"carol","feed",hid(12),inv),"another job beyond ten total")

func test_large_step_and_split_ticks()->void:
	var s:=six_at_zero()
	var expected_ids:Array=[hid(1),hid(2),hid(3),hid(4),hid(5),hid(6)]
	var expected_done:Array=[10.0,25.0,30.0,40.0,55.0,60.0]
	var big:Dictionary=Q.advance(s,R,1000.0)
	expect(is_ok(big) and big.get("changed",null)==true,"1000-second step reports a change")
	var bs:=sub_dict(big,"state")
	var rd:=sub_array(bs,"ready")
	expect(canon(ids(rd))==canon(expected_ids),"1000-second step completes all six in FIFO order")
	expect(canon(completions(rd))==canon(expected_done),"completion times are cumulative finishes 10,25,30,40,55,60 not 1000")
	var shapes_ok:=true
	for x in rd:
		if not keys_are(x,READY_KEYS):shapes_ok=false
	expect(shapes_ok,"every completed record is canonical ready shape")
	expect(sub_dict(bs,"active").is_empty() and sub_array(bs,"waiting").is_empty(),"nothing left active or waiting")
	expect(Q.validate(bs,R,1000.0),"large-step result validates")

	var mid:=advance_ok(s,31.0,"advance to 31")
	expect(canon(completions(sub_array(mid,"ready")))==canon([10.0,25.0,30.0]),"three complete by 31")
	var mact:=sub_dict(mid,"active")
	expect(sval(mact,"id")==hid(4) and num(mact,"started")==30.0 and num(mact,"finish")==40.0,"fourth job started at previous finish 30")
	expect(canon(ids(sub_array(mid,"waiting")))==canon([hid(5),hid(6)]),"two still waiting at 31")
	var at55:=advance_ok(s,55.0,"advance to 55")
	expect(sval(sub_dict(at55,"active"),"id")==hid(6) and num(sub_dict(at55,"active"),"started")==55.0,"sixth job starts exactly at 55 boundary")

	for seq in [[3.0,10.0,24.5,25.0,31.0,40.0,55.0,59.0,60.0,1000.0],[9.99,30.0,61.0,1000.0],[60.0,1000.0]]:
		var cur:Dictionary=s
		for t in seq:
			cur=advance_ok(cur,float(t),"split tick to %s"%str(t))
		expect(canon(cur)==canon(bs),"split ticks %s equal one large tick"%str(seq))

	var idem:Dictionary=Q.advance(bs,R,1000.0)
	expect(is_ok(idem) and idem.get("changed",null)==false and canon(sub_dict(idem,"state"))==canon(bs),"advance at same now after large step is a no-op")
	var later:Dictionary=Q.advance(bs,R,2000.0)
	expect(is_ok(later) and later.get("changed",null)==false and canon(completions(sub_array(sub_dict(later,"state"),"ready")))==canon(expected_done),"further time never rewrites completion timestamps")
	expect_reject(Q.advance(bs,R,59.0),"backward advance before last completion")
	expect(not Q.validate(bs,R,59.0) and Q.validate(bs,R,60.0),"validate enforces completed<=now")
	expect_reject(Q.advance(mid,R,29.0),"backward advance before active start")
	for bad in [NAN,INF,-1.0]:
		expect_reject(Q.advance(s,R,bad),"advance with now=%s"%str(bad))

func test_no_mutable_aliasing()->void:
	var rc:Dictionary=World.RECIPES.duplicate(true)
	var rc_snap:=snap(rc)
	var inv:Dictionary={"radish":10,"gem":1}
	var inv_snap:=snap(inv)
	var s:Dictionary=Q.empty_state()
	var s_snap:=snap(s)
	var r:Dictionary=Q.enqueue(s,rc,0.0,"alice","soup",hid(1),inv)
	var out:=ok_state(r,"enqueue with mutable recipe copy")
	var oinv:=ok_inv(r)
	var ing:=sub_dict(sub_dict(out,"active"),"ingredients")
	poke(ing,"radish",99,"output ingredients")
	var ow:=sub_array(out,"waiting")
	expect(not ow.is_read_only(),"output waiting array is caller-owned")
	if not ow.is_read_only():ow.append({"bogus":true})
	poke(oinv,"radish",-5,"output inventory")
	expect(snap(rc)==rc_snap,"mutating output ingredients does not reach the recipe table")
	expect(snap(s)==s_snap and snap(inv)==inv_snap,"mutating outputs does not reach inputs")

	var real:Dictionary=Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":2})
	var real_ing:Variant=sub_dict(sub_dict(real,"state"),"active").get("ingredients",null)
	expect(real_ing is Dictionary and not (real_ing as Dictionary).is_read_only(),"output ingredients are an owned copy, not the const World.RECIPES dictionary")
	expect(canon((World.RECIPES.soup as Dictionary).ingredients)==canon({"radish":2}),"World.RECIPES soup cost untouched")

	# Input mutated after the call must not alter outputs (including a no-op advance).
	var base:Dictionary=Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":4})
	var b1:=ok_state(base,"alias fixture soup")
	var b2:=ok_state(Q.enqueue(b1,R,0.0,"bob","feed",hid(2),{"wheat":1,"fiber":2}),"alias fixture feed")
	var noop:Dictionary=Q.advance(b2,R,5.0)
	var noop_state:=sub_dict(noop,"state")
	var noop_snap:=snap(noop_state)
	poke(sub_dict(sub_dict(b2,"active"),"ingredients"),"radish",50,"input active ingredients")
	var bw:=sub_array(b2,"waiting")
	if bw.size()>0 and bw[0] is Dictionary:poke(sub_dict(bw[0],"ingredients"),"fiber",77,"input waiting ingredients")
	expect(snap(noop_state)==noop_snap,"no-op advance output does not alias nested input records")

	var c1:=ok_state(Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":4}),"promotion fixture soup")
	var c2:=ok_state(Q.enqueue(c1,R,0.0,"bob","feed",hid(2),{"wheat":1,"fiber":2}),"promotion fixture feed")
	var promoted:=advance_ok(c2,10.0,"promote feed")
	var promoted_snap:=snap(promoted)
	var cw:=sub_array(c2,"waiting")
	if cw.size()>0 and cw[0] is Dictionary:poke(sub_dict(cw[0],"ingredients"),"wheat",9,"waiting input after promotion")
	poke(sub_dict(sub_dict(c2,"active"),"ingredients"),"radish",9,"active input after completion")
	expect(snap(promoted)==promoted_snap,"promoted/completed records are deep copies of input records")

	var ready_state:=advance_ok(c1,10.0,"ready fixture")
	var claim_inv:Dictionary={"soup":1}
	var claimed:Dictionary=Q.claim(ready_state,R,10.0,claim_inv)
	var claimed_snap:=snap(claimed)
	poke(claim_inv,"soup",400,"claim input inventory")
	var rr:=sub_array(ready_state,"ready")
	if rr.size()>0 and rr[0] is Dictionary:poke(rr[0] as Dictionary,"owner","mallory","claim input ready record")
	expect(snap(claimed)==claimed_snap,"claim result does not alias input inventory or ready record")

	var job:Dictionary={"kind":"soup","ready":10.0,"owner":"alice","ingredients":{"radish":2},"yield":2,"recipe_version":1}
	var imp:Dictionary=Q.import_legacy(job,R,5.0,hid(9))
	var imp_snap:=snap(imp)
	poke(job.ingredients as Dictionary,"radish",7,"legacy job input")
	expect(snap(imp)==imp_snap,"legacy import output does not alias job ingredients")

func test_cancel_ownership_and_restart()->void:
	var alice:Dictionary={"radish":4,"wheat":1,"fiber":2}
	var bob:Dictionary={"wheat":2}
	var r1:Dictionary=Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),alice)
	alice=ok_inv(r1)
	var r2:Dictionary=Q.enqueue(sub_dict(r1,"state"),R,1.0,"bob","bread",hid(2),bob)
	bob=ok_inv(r2)
	var r3:Dictionary=Q.enqueue(sub_dict(r2,"state"),R,2.0,"alice","feed",hid(3),alice)
	alice=ok_inv(r3)
	var s:=ok_state(r3,"three-job cancel fixture")
	expect(canon(alice)==canon({"radish":2,"wheat":0,"fiber":0}) or canon(alice)==canon({"radish":2}),"alice paid soup and feed")
	var s_snap:=snap(s)
	var bob_snap:=snap(bob)
	expect_reject(Q.cancel(s,R,4.0,"bob",hid(1),bob),"bob cancelling alice's active soup")
	expect_reject(Q.cancel(s,R,4.0,"bob",hid(3),bob),"bob cancelling alice's waiting feed")
	expect_reject(Q.cancel(s,R,4.0,"alice",hid(9),alice),"cancelling unknown id")
	expect_reject(Q.cancel(s,R,4.0,"",hid(1),alice),"cancelling with empty owner")
	expect(snap(s)==s_snap and snap(bob)==bob_snap,"rejected cancels mutate nothing")

	var ca:Dictionary=Q.cancel(s,R,4.0,"alice",hid(1),alice)
	var after_active:=ok_state(ca,"alice cancels her active soup")
	expect(int(ok_inv(ca).get("radish",-1))==4,"active cancel refunds exactly 2 radish")
	var act:=sub_dict(after_active,"active")
	expect(sval(act,"id")==hid(2) and num(act,"started")==4.0 and num(act,"finish")==19.0,"next job restarts at cancel time 4, not at 0 or 10")
	expect(canon(ids(sub_array(after_active,"waiting")))==canon([hid(3)]),"feed still waiting after active cancel")
	expect(sub_array(after_active,"ready").is_empty(),"cancelled job never becomes ready")

	var cw:Dictionary=Q.cancel(s,R,4.0,"alice",hid(3),alice)
	var after_waiting:=ok_state(cw,"alice cancels her waiting feed")
	var cwi:=ok_inv(cw)
	expect(int(cwi.get("wheat",-1))==1 and int(cwi.get("fiber",-1))==2 and int(cwi.get("radish",-1))==2,"waiting cancel refunds exactly 1 wheat + 2 fiber")
	expect(canon(sub_dict(after_waiting,"active"))==canon(sub_dict(s,"active")),"waiting cancel leaves active untouched")
	expect(canon(ids(sub_array(after_waiting,"waiting")))==canon([hid(2)]),"waiting cancel keeps remaining FIFO")

	var t1:=advance_ok(after_active,18.75,"before restarted bread finishes")
	expect(sub_array(t1,"ready").is_empty(),"restarted bread not done at 18.75")
	var t2:=advance_ok(after_active,19.0,"restarted bread finishes")
	expect(canon(ids(sub_array(t2,"ready")))==canon([hid(2)]) and canon(completions(sub_array(t2,"ready")))==canon([19.0]),"bread completes at 19")
	var t2a:=sub_dict(t2,"active")
	expect(sval(t2a,"id")==hid(3) and num(t2a,"started")==19.0 and num(t2a,"finish")==24.0,"feed starts at 19")
	expect_reject(Q.cancel(t2,R,19.0,"bob",hid(2),{}),"owner cancelling already completed bread")

	# FIFO with three waiting: cancel the middle one.
	var f:Dictionary=Q.empty_state()
	var inv:Dictionary=plenty()
	var order:Array[String]=["soup","bread","feed","soup"]
	for i in order.size():
		var fr:Dictionary=Q.enqueue(f,R,0.0,"alice",order[i],hid(0x40+i),inv)
		f=ok_state(fr,"FIFO cancel fixture %d"%i)
		inv=ok_inv(fr)
	var mid:Dictionary=Q.cancel(f,R,1.0,"alice",hid(0x42),inv)
	var ms:=ok_state(mid,"cancel middle waiting job")
	expect(canon(ids(sub_array(ms,"waiting")))==canon([hid(0x41),hid(0x43)]),"cancelling middle waiting job preserves FIFO of the rest")
	expect(sval(sub_dict(ms,"active"),"id")==hid(0x40) and num(sub_dict(ms,"active"),"started")==0.0,"active unchanged when a waiting job is cancelled")

func test_overdue_requires_advance()->void:
	var r1:Dictionary=Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":2})
	var s1:=ok_state(r1,"overdue fixture soup")
	var r2:Dictionary=Q.enqueue(s1,R,1.0,"bob","bread",hid(2),{"wheat":2})
	var s2:=ok_state(r2,"overdue fixture bread")
	expect(Q.validate(s2,R,12.0),"overdue active is a valid stored state")
	var snap2:=snap(s2)
	var inv:Dictionary={"radish":9}
	var inv_snap:=snap(inv)
	expect_reject(Q.cancel(s2,R,12.0,"alice",hid(1),inv),"cancelling overdue active soup without advancing")
	expect_reject(Q.enqueue(s2,R,12.0,"carol","soup",hid(3),inv),"enqueue while active is overdue")
	expect_reject(Q.claim(s2,R,12.0,inv),"claim with no ready food (claim does not auto-advance)")
	expect(snap(s2)==snap2 and snap(inv)==inv_snap,"overdue rejections mutate nothing")
	var adv:=advance_ok(s2,12.0,"explicit advance resolves overdue")
	expect(canon(ids(sub_array(adv,"ready")))==canon([hid(1)]) and canon(completions(sub_array(adv,"ready")))==canon([10.0]),"overdue soup completed at its finish 10")
	expect_reject(Q.cancel(adv,R,12.0,"alice",hid(1),inv),"cancelling soup once completed")
	var e:Dictionary=Q.enqueue(adv,R,12.0,"carol","soup",hid(3),inv)
	expect(is_ok(e),"enqueue accepted after advance ("+msg(e)+")")
	expect(int(ok_inv(e).get("radish",-1))==7,"post-advance enqueue charges exactly 2 radish")
	expect(canon(ids(sub_array(sub_dict(e,"state"),"waiting")))==canon([hid(3)]),"post-advance soup waits behind bread active 10..25")

	# Claim may take existing ready food while the active job is overdue, leaving active untouched.
	var a:=advance_ok(s2,10.0,"soup ready, bread active 10..25")
	var c:Dictionary=Q.claim(a,R,30.0,{})
	var cs:=ok_state(c,"claim ready soup while bread is overdue")
	expect(sval(c,"id")==hid(1),"claim took the ready soup")
	expect(canon(sub_dict(cs,"active"))==canon(sub_dict(a,"active")),"claim does not complete the overdue active job")
	expect(sub_array(cs,"ready").is_empty(),"claim only removed the ready soup")

func test_refund_and_claim_overflow()->void:
	var s:=ok_state(Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":2}),"overflow fixture")
	var s_snap:=snap(s)
	for bad_inv in [{"radish":INV_CAP-1,"gem":3},{"radish":INV_CAP}]:
		var b_snap:=snap(bad_inv)
		expect_reject(Q.cancel(s,R,1.0,"alice",hid(1),bad_inv),"refund overflowing past 1e9")
		expect(snap(bad_inv)==b_snap and snap(s)==s_snap,"refund overflow leaves inventory and state unchanged")
	var edge:Dictionary=Q.cancel(s,R,1.0,"alice",hid(1),{"radish":INV_CAP-2})
	expect(is_ok(edge),"refund landing exactly on 1e9 ("+msg(edge)+")")
	expect(int(ok_inv(edge).get("radish",-1))==INV_CAP,"refund reaches cap exactly")
	expect(sub_dict(sub_dict(edge,"state"),"active").is_empty(),"refunded soup removed from stove")

	var ready:=advance_ok(s,10.0,"soup ready for overflow claim")
	var ready_snap:=snap(ready)
	var full:Dictionary={"soup":INV_CAP-1}
	expect_reject(Q.claim(ready,R,10.0,full),"claim overflowing past 1e9")
	expect(snap(ready)==ready_snap and int(full.soup)==INV_CAP-1,"claim overflow leaves ready food and inventory untouched")
	var fit:Dictionary=Q.claim(ready,R,10.0,{"soup":INV_CAP-2})
	expect(is_ok(fit),"claim landing exactly on 1e9 ("+msg(fit)+")")
	expect(int(ok_inv(fit).get("soup",-1))==INV_CAP,"claim reaches cap exactly")

	for bad in [{"soup":-1},{"soup":1.5},{"soup":true},{"gem":INV_CAP+1},{"soup":"3"},{"soup":NAN},{"soup":null}]:
		expect_reject(Q.claim(ready,R,10.0,bad),"claim into malformed inventory %s"%str(bad))
	for bad in [{"radish":INV_CAP+1},{"radish":2.5},{"radish":true},{"radish":-2},{"radish":"9"},{"radish":INF}]:
		var bs:=snap(bad)
		expect_reject(Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(5),bad),"enqueue from malformed inventory %s"%str(bad))
		expect(snap(bad)==bs,"malformed inventory left untouched")
	expect_reject(Q.cancel(s,R,1.0,"alice",hid(1),{"radish":-1}),"refund into negative inventory")

func test_shared_single_claims()->void:
	var s:=ok_state(Q.enqueue(Q.empty_state(),R,0.0,"alice","soup",hid(1),{"radish":2}),"shared fixture soup")
	s=ok_state(Q.enqueue(s,R,0.0,"bob","bread",hid(2),{"wheat":2}),"shared fixture bread")
	var both:=advance_ok(s,25.0,"both ready")
	expect(canon(completions(sub_array(both,"ready")))==canon([10.0,25.0]),"soup at 10, bread at 25")
	var both_snap:=snap(both)
	var carol:Dictionary={"gem":1}
	var c1:Dictionary=Q.claim(both,R,25.0,carol)
	var s1:=ok_state(c1,"carol claims oldest ready even though alice cooked it")
	expect(canon(ok_inv(c1))==canon({"gem":1,"soup":2}),"claim adds exactly soup yield 2 and keeps gem")
	expect(sval(c1,"kind")=="soup" and sval(c1,"owner")=="alice" and sval(c1,"id")==hid(1),"claim reports kind/owner/id of the claimed job")
	expect(canon(ids(sub_array(s1,"ready")))==canon([hid(2)]),"only the oldest ready record removed")
	expect(snap(both)==both_snap,"claim does not mutate its input state")
	var c2:Dictionary=Q.claim(s1,R,25.0,{})
	var s2:=ok_state(c2,"second claim takes bread")
	expect(sval(c2,"id")==hid(2) and sval(c2,"owner")=="bob" and canon(ok_inv(c2))==canon({"bread":1}),"bread claim yields exactly 1")
	expect_reject(Q.claim(s2,R,25.0,{}),"claim with nothing ready")
	expect(not ids(sub_array(s2,"ready")).has(hid(1)),"a claimed record never reappears")

	var p:=ok_state(Q.enqueue(Q.empty_state(),R,0.0,"alice","feed",hid(0x31),{"wheat":1,"fiber":2}),"promote fixture feed")
	p=ok_state(Q.enqueue(p,R,0.0,"alice","soup",hid(0x32),{"radish":2}),"promote fixture soup")
	p=ok_state(Q.enqueue(p,R,0.0,"alice","bread",hid(0x33),{"wheat":2}),"promote fixture bread")
	var pa:=advance_ok(p,5.0,"feed ready, soup active")
	var pc:Dictionary=Q.claim(pa,R,6.0,{})
	var ps:=ok_state(pc,"claim feed")
	expect(int(ok_inv(pc).get("feed",-1))==4,"feed claim yields exactly 4")
	expect(canon(sub_dict(ps,"active"))==canon(sub_dict(pa,"active")) and canon(sub_array(ps,"waiting"))==canon(sub_array(pa,"waiting")),"claim never promotes or alters active/waiting")

func test_id_owner_kind_and_time_arguments()->void:
	var s:=ok_state(Q.enqueue(Q.empty_state(),R,0.0,"alice","feed",hid(0xa1),{"wheat":1,"fiber":2}),"id fixture feed")
	s=advance_ok(s,5.0,"id fixture feed ready")
	s=ok_state(Q.enqueue(s,R,5.0,"alice","soup",hid(0xb2),{"radish":2}),"id fixture soup active")
	s=ok_state(Q.enqueue(s,R,5.0,"alice","bread",hid(0xc3),{"wheat":2}),"id fixture bread waiting")
	var inv:Dictionary=plenty()
	var s_snap:=snap(s)
	expect_reject(Q.enqueue(s,R,5.0,"bob","soup",hid(0xa1),inv),"id duplicating a ready job")
	expect_reject(Q.enqueue(s,R,5.0,"bob","soup",hid(0xb2),inv),"id duplicating the active job")
	expect_reject(Q.enqueue(s,R,5.0,"bob","soup",hid(0xc3),inv),"id duplicating a waiting job")
	for bad_id in ["",UPPER_ID,hid(1).substr(1),"0"+hid(1),"g"+hid(1).substr(1)," "+hid(1).substr(1),"0x"+hid(1).substr(2),"-"+hid(1).substr(1)]:
		expect_reject(Q.enqueue(s,R,5.0,"bob","soup",bad_id,inv),"malformed id '%s'"%bad_id)
	expect_reject(Q.enqueue(s,R,5.0,"","soup",hid(0xd4),inv),"empty owner")
	expect_reject(Q.enqueue(s,R,5.0,"a".repeat(65),"soup",hid(0xd4),inv),"65-char owner")
	for bad_kind in ["cake","","Soup","name"]:
		expect_reject(Q.enqueue(s,R,5.0,"bob",bad_kind,hid(0xd4),inv),"unknown recipe '%s'"%bad_kind)
	for bad_now in [NAN,INF,-INF,-1.0]:
		expect_reject(Q.enqueue(Q.empty_state(),R,bad_now,"bob","soup",hid(0xd4),inv),"enqueue at now=%s"%str(bad_now))
		expect_reject(Q.claim(s,R,bad_now,inv),"claim at now=%s"%str(bad_now))
		expect_reject(Q.cancel(s,R,bad_now,"alice",hid(0xc3),inv),"cancel at now=%s"%str(bad_now))
	expect_reject(Q.enqueue(s,R,4.0,"bob","soup",hid(0xd4),inv),"enqueue at time before recorded completion")
	expect_reject(Q.claim(s,R,4.0,inv),"claim at time before recorded completion")
	expect(snap(s)==s_snap and snap(inv)==snap(plenty()),"argument rejections mutate nothing")
	var long_owner:String="a".repeat(64)
	var lo:Dictionary=Q.enqueue(Q.empty_state(),R,0.0,long_owner,"soup",hid(0xd4),{"radish":2})
	expect(sval(sub_dict(ok_state(lo,"64-char owner accepted"),"active"),"owner")==long_owner,"64-char owner stored verbatim")

func fixture_state()->Dictionary:
	return {
		"active":active_rec(hid(1),"soup","alice",100.0,110.0),
		"waiting":[rec(hid(2),"bread","bob")],
		"ready":[ready_rec(hid(3),"feed","carol",90.0)],
	}

func bad_state(name:String)->Variant:
	var s:Dictionary=fixture_state()
	var a:Dictionary=s.active
	var w:Dictionary=(s.waiting as Array)[0]
	var rd:Dictionary=(s.ready as Array)[0]
	match name:
		"state_null":return null
		"state_array":return [{},[],[]]
		"state_string":return "state"
		"state_int":return 6
		"state_bool":return true
		"extra_top":s["extra"]=1
		"missing_ready":s.erase("ready")
		"missing_active":s.erase("active")
		"active_array":s["active"]=[]
		"active_null":s["active"]=null
		"waiting_dict":s["waiting"]={}
		"ready_nondict":s["ready"]=[5]
		"waiting_string_entry":s["waiting"]=["x"]
		"record_extra":a["bonus"]=1
		"record_missing_owner":a.erase("owner")
		"record_missing_ingredients":w.erase("ingredients")
		"record_missing_id":rd.erase("id")
		"kind_unknown":w["kind"]="cake"
		"kind_int":w["kind"]=3
		"owner_empty":a["owner"]=""
		"owner_long":a["owner"]="a".repeat(65)
		"owner_int":a["owner"]=7
		"id_empty":w["id"]=""
		"id_upper":w["id"]=UPPER_ID
		"id_short":w["id"]=hid(2).substr(1)
		"id_long":w["id"]="0"+hid(2)
		"id_nonhex":w["id"]="g"+hid(2).substr(1)
		"id_int":w["id"]=2
		"id_dup_active":w["id"]=hid(1)
		"id_dup_ready":rd["id"]=hid(1)
		"id_dup_waiting_ready":rd["id"]=hid(2)
		"ing_empty":a["ingredients"]={}
		"ing_fraction":a["ingredients"]={"radish":2.5}
		"ing_bool":w["ingredients"]={"wheat":true}
		"ing_negative":rd["ingredients"]={"wheat":-1,"fiber":2}
		"ing_string":a["ingredients"]={"radish":"2"}
		"ing_array":a["ingredients"]=[2]
		"ing_nan":a["ingredients"]={"radish":NAN}
		"yield_zero":a["yield"]=0
		"duration_zero":a["duration"]=0.0
		"duration_negative":a["duration"]=-1.0
		"duration_nan":a["duration"]=NAN
		"duration_inf":a["duration"]=INF
		"duration_bool":a["duration"]=true
		"duration_missing":a.erase("duration")
		"yield_fraction":a["yield"]=2.5
		"yield_bool":w["yield"]=true
		"yield_string":rd["yield"]="4"
		"version_2":a["recipe_version"]=2
		"version_string":w["recipe_version"]="1"
		"version_bool":rd["recipe_version"]=true
		"version_missing":w.erase("recipe_version")
		"started_nan":
			a["started"]=NAN
			a["finish"]=NAN
		"started_inf":
			a["started"]=INF
			a["finish"]=INF
		"started_negative":
			a["started"]=-10.0
			a["finish"]=0.0
		"started_future":
			a["started"]=106.0
			a["finish"]=116.0
		"started_bool":a["started"]=true
		"started_string":a["started"]="100"
		"finish_mismatch":a["finish"]=111.0
		"finish_missing":a.erase("finish")
		"completed_future":rd["completed"]=106.0
		"completed_nan":rd["completed"]=NAN
		"completed_inf":rd["completed"]=INF
		"completed_negative":rd["completed"]=-1.0
		"completed_bool":rd["completed"]=true
		"ready_has_started":rd["started"]=80.0
		"waiting_has_started":w["started"]=100.0
		"active_has_completed":a["completed"]=100.0
		"waiting_without_active":s["active"]={}
		"over_capacity":
			for i in 8:(s.ready as Array).append(ready_rec(hid(0x20+i),"feed","dave",90.0))
		_:
			expect(false,"unknown bad_state case "+name)
	return s

func expect_all_ops_reject(s:Dictionary,label:String)->void:
	var before:=snap(s)
	var inv:Dictionary={"radish":50,"wheat":50,"fiber":50}
	var inv_before:=snap(inv)
	expect_reject(Q.advance(s,R,105.0),label+" advance")
	expect_reject(Q.enqueue(s,R,105.0,"erin","soup",hid(0xfe),inv),label+" enqueue")
	expect_reject(Q.cancel(s,R,105.0,"bob",hid(2),inv),label+" cancel")
	expect_reject(Q.claim(s,R,105.0,inv),label+" claim")
	expect(snap(s)==before and snap(inv)==inv_before,label+" leaves arguments untouched")

func test_validate_matrix()->void:
	var good:=fixture_state()
	expect(Q.validate(good,R,105.0),"hand-built fixture validates")
	expect(Q.validate(good,R,100.0),"started==now is valid")
	expect(Q.validate(good,R,200.0),"overdue active is valid storage")
	expect(not Q.validate(good,R,99.5),"started after now invalid")
	expect(not Q.validate(good,R,NAN) and not Q.validate(good,R,INF),"non-finite now invalid")
	# Sanity: the fixture is operable, so the negative matrix below is meaningful.
	var adv:Dictionary=Q.advance(good,R,105.0)
	expect(is_ok(adv) and adv.get("changed",null)==false,"fixture advances as a no-op at 105")
	var can:Dictionary=Q.cancel(good,R,105.0,"bob",hid(2),{})
	expect(is_ok(can) and int(ok_inv(can).get("wheat",-1))==2,"fixture waiting bread cancellable by bob for 2 wheat")
	var clm:Dictionary=Q.claim(good,R,105.0,{})
	expect(is_ok(clm) and int(ok_inv(clm).get("feed",-1))==4,"fixture ready feed claimable for 4")
	expect(snap(good)==snap(fixture_state()),"fixture untouched by successful ops")

	var floats:=fixture_state()
	var fa:Dictionary=floats.active
	fa["ingredients"]={"radish":2.0}
	fa["yield"]=2.0
	fa["recipe_version"]=1.0
	expect(Q.validate(floats,R,105.0),"JSON whole-number floats accepted")
	var fn:=advance_ok(floats,105.0,"advance normalizes float counts")
	var fna:=sub_dict(fn,"active")
	expect(typeof(sub_dict(fna,"ingredients").get("radish"))==TYPE_INT and typeof(fna.get("yield"))==TYPE_INT and typeof(fna.get("recipe_version"))==TYPE_INT,"successful output normalizes counts to int")

	var ready_only:Dictionary={"active":{},"waiting":[],"ready":[ready_rec(hid(3),"feed","carol",90.0)]}
	expect(Q.validate(ready_only,R,105.0),"ready-only state with empty active valid")
	var six:=fixture_state()
	for i in 3:(six.ready as Array).append(ready_rec(hid(0x20+i),"feed","dave",90.0))
	expect(Q.validate(six,R,105.0),"exactly six total jobs valid")

	var cases:Array[String]=["state_null","state_array","state_string","state_int","state_bool",
		"extra_top","missing_ready","missing_active","active_array","active_null","waiting_dict","ready_nondict","waiting_string_entry",
		"record_extra","record_missing_owner","record_missing_ingredients","record_missing_id",
		"kind_unknown","kind_int","owner_empty","owner_long","owner_int",
		"id_empty","id_upper","id_short","id_long","id_nonhex","id_int","id_dup_active","id_dup_ready","id_dup_waiting_ready",
		"ing_empty","ing_fraction","ing_bool","ing_negative","ing_string","ing_array","ing_nan",
		"yield_zero","yield_fraction","yield_bool","yield_string",
		"duration_zero","duration_negative","duration_nan","duration_inf","duration_bool","duration_missing",
		"version_2","version_string","version_bool","version_missing",
		"started_nan","started_inf","started_negative","started_future","started_bool","started_string","finish_mismatch","finish_missing",
		"completed_future","completed_nan","completed_inf","completed_negative","completed_bool",
		"ready_has_started","waiting_has_started","active_has_completed","waiting_without_active","over_capacity"]
	for name in cases:
		var v:Variant=bad_state(name)
		var before:=snap(v)
		expect(not Q.validate(v,R,105.0),"validate rejects "+name)
		expect(snap(v)==before,"validate does not repair/mutate "+name)
		if v is Dictionary:expect_all_ops_reject(v,name)

func bad_recipes(name:String)->Dictionary:
	var rc:Dictionary=World.RECIPES.duplicate(true)
	var soup:Dictionary=rc.soup
	if rc.is_read_only() or soup.is_read_only():
		expect(false,"duplicated recipe table should be writable")
		return {}
	match name:
		"time_zero":soup["time"]=0.0
		"time_negative":soup["time"]=-10.0
		"time_nan":soup["time"]=NAN
		"time_inf":soup["time"]=INF
		"time_string":soup["time"]="10"
		"time_bool":soup["time"]=true
		"time_missing":soup.erase("time")
		"count_zero":soup["ingredients"]={"radish":0}
		"count_negative":soup["ingredients"]={"radish":-2}
		"count_fraction":soup["ingredients"]={"radish":1.5}
		"count_bool":soup["ingredients"]={"radish":true}
		"ingredients_not_dict":soup["ingredients"]=["radish"]
		"yield_zero":soup["yield"]=0
		"yield_negative":soup["yield"]=-1
		"yield_fraction":soup["yield"]=1.5
		"yield_bool":soup["yield"]=true
		"yield_missing":soup.erase("yield")
		"recipe_not_dict":rc["soup"]=5
		_:expect(false,"unknown bad_recipes case "+name)
	return rc

func test_recipe_inputs_fail_closed()->void:
	for name in ["time_zero","time_negative","time_nan","time_inf","time_string","time_bool","time_missing",
			"count_zero","count_negative","count_fraction","count_bool","ingredients_not_dict",
			"yield_zero","yield_negative","yield_fraction","yield_bool","yield_missing","recipe_not_dict"]:
		var rc:=bad_recipes(name)
		var rc_snap:=snap(rc)
		expect(not Q.validate(fixture_state(),rc,105.0),"validate fails closed with bad recipe "+name)
		var inv:Dictionary={"radish":10}
		expect_reject(Q.enqueue(Q.empty_state(),rc,0.0,"alice","soup",hid(0x77),inv),"enqueue with bad recipe "+name)
		expect(snap(rc)==rc_snap and int(inv.radish)==10,"bad recipe "+name+" not mutated and nothing charged")
	expect_reject(Q.enqueue(Q.empty_state(),{},0.0,"alice","soup",hid(0x77),{"radish":10}),"enqueue against empty recipe table")

func test_json_roundtrip_continues()->void:
	var empty_parsed:Variant=JSON.parse_string(JSON.stringify(Q.empty_state()))
	expect(empty_parsed is Dictionary and Q.validate(empty_parsed,R,0.0),"empty state survives JSON")
	var s:=six_at_zero()
	var mid:=advance_ok(s,31.0,"roundtrip fixture to 31")
	var c1:Dictionary=Q.claim(mid,R,31.0,{})
	var after:=ok_state(c1,"claim first soup before save")
	var bob:=ok_inv(c1)
	expect(sval(c1,"id")==hid(1) and canon(bob)==canon({"soup":2}),"pre-save claim gave soup x2")
	var parsed:Variant=JSON.parse_string(JSON.stringify(after))
	expect(parsed is Dictionary,"saved queue parses back to a dictionary")
	var p:Dictionary=parsed if parsed is Dictionary else {}
	expect(Q.validate(p,R,31.0),"JSON-parsed state (float counts) validates")
	expect(not Q.validate(p,R,29.0),"JSON-parsed state still rejects backward time")
	var same:Dictionary=Q.advance(p,R,31.0)
	expect(is_ok(same) and same.get("changed",null)==false,"reloaded state at the same time is a no-op")
	var p_done:=advance_ok(p,1000.0,"reloaded state continues")
	var o_done:=advance_ok(after,1000.0,"original state continues")
	expect(canon(p_done)==canon(o_done),"reloaded and in-memory queues reach the same result")
	expect(canon(completions(sub_array(p_done,"ready")))==canon([25.0,30.0,40.0,55.0,60.0]),"reloaded queue keeps original timeline")
	var ints:=true
	for x in sub_array(p_done,"ready"):
		if not x is Dictionary:
			ints=false
			continue
		if typeof((x as Dictionary).get("yield"))!=TYPE_INT or typeof((x as Dictionary).get("recipe_version"))!=TYPE_INT:ints=false
		for v in sub_dict(x,"ingredients").values():
			if typeof(v)!=TYPE_INT:ints=false
	expect(ints,"advance output after JSON reload has integer counts")
	var got:Array=[]
	var cur:Dictionary=p_done
	for i in 10:
		var cr:Dictionary=Q.claim(cur,R,1000.0,bob)
		if not is_ok(cr):break
		got.append(sval(cr,"id"))
		cur=sub_dict(cr,"state")
		bob=ok_inv(cr)
	expect(canon(got)==canon([hid(2),hid(3),hid(4),hid(5),hid(6)]),"exactly the five unclaimed jobs are claimable after reload")
	expect(canon(bob)==canon({"soup":4,"bread":2,"feed":8}),"total rewards are exactly 2+2 soup, 1+1 bread, 4+4 feed, no duplicates")
	expect(typeof(bob.get("soup"))==TYPE_INT,"claimed inventory counts are integers")
	expect(total_jobs(cur)==0 and Q.validate(cur,R,1000.0),"kitchen empty and valid after all claims")

func test_legacy_import()->void:
	# Exact shape written by world.gd "cook": kind, ready, owner, ingredients, yield, recipe_version.
	var job:Dictionary={"kind":"soup","ready":110.0,"owner":"alice","ingredients":{"radish":2},"yield":2,"recipe_version":1}
	var job_snap:=snap(job)
	var r:Dictionary=Q.import_legacy(job,R,105.0,hid(1))
	var s:=ok_state(r,"import full World job shape")
	expect(snap(job)==job_snap,"import does not mutate the job")
	var a:=sub_dict(s,"active")
	expect(keys_are(a,ACTIVE_KEYS),"imported job is a canonical active record")
	expect(sval(a,"id")==hid(1) and sval(a,"owner")=="alice" and sval(a,"kind")=="soup","imported identity preserved")
	expect(num(a,"started")==100.0 and num(a,"finish")==110.0,"started derived as ready-10=100")
	expect(sub_array(s,"waiting").is_empty() and sub_array(s,"ready").is_empty(),"import creates exactly one job")
	expect(Q.validate(s,R,105.0),"imported state validates")
	expect(not r.has("inventory") or sub_dict(r,"inventory").is_empty(),"import neither charges nor refunds inventory")
	expect_reject(Q.enqueue(s,R,105.0,"bob","bread",hid(1),{"wheat":2}),"new job reusing imported id")
	var cont:Dictionary=Q.enqueue(s,R,105.0,"bob","bread",hid(2),{"wheat":2})
	expect(canon(ids(sub_array(ok_state(cont,"queue behind imported job"),"waiting")))==canon([hid(2)]),"new job waits behind imported job")

	var minimal:Dictionary={"kind":"bread","ready":30.0,"owner":"bob"}
	var m:=ok_state(Q.import_legacy(minimal,R,20.0,hid(2)),"import job without optional fields")
	var ma:=sub_dict(m,"active")
	expect(num(ma,"started")==15.0 and num(ma,"finish")==30.0,"bread started 15 finish 30")
	expect(canon(ma.get("ingredients"))==canon({"wheat":2}) and num(ma,"yield")==1.0 and num(ma,"recipe_version")==1.0,"missing optional fields filled from current recipe")

	var partial:Dictionary={"kind":"feed","ready":12.5,"owner":"carol","ingredients":{"wheat":1,"fiber":2}}
	var pa:=sub_dict(ok_state(Q.import_legacy(partial,R,10.0,hid(3)),"import with ingredients only"),"active")
	expect(num(pa,"started")==7.5 and num(pa,"yield")==4.0,"feed started 7.5, yield 4")

	var json_job:Dictionary={"kind":"soup","ready":110.0,"owner":"alice","ingredients":{"radish":2.0},"yield":2.0,"recipe_version":1.0}
	var ja:=sub_dict(ok_state(Q.import_legacy(json_job,R,105.0,hid(4)),"import JSON-float job"),"active")
	expect(typeof(sub_dict(ja,"ingredients").get("radish"))==TYPE_INT and typeof(ja.get("yield"))==TYPE_INT,"imported counts normalized to int")

	var past:Dictionary={"kind":"soup","ready":50.0,"owner":"alice"}
	var ps:=ok_state(Q.import_legacy(past,R,80.0,hid(5)),"import already-complete job")
	expect(Q.validate(ps,R,80.0),"already-complete import validates at now")
	var pd:=advance_ok(ps,80.0,"advance resolves imported completed job")
	expect(canon(ids(sub_array(pd,"ready")))==canon([hid(5)]) and canon(completions(sub_array(pd,"ready")))==canon([50.0]),"imported completed job ready with completed=50 not 80")
	expect(sub_dict(pd,"active").is_empty(),"no active left after resolving imported job")
	var zero:Dictionary={"kind":"soup","ready":10.0,"owner":"alice"}
	expect(sub_array(ok_state(Q.import_legacy(zero,R,10.0,hid(6)),"import job completing at boundary"),"ready").size()==1,"already complete at exact boundary")

	var empty:Dictionary=Q.import_legacy({},R,42.0,hid(7))
	expect(canon(ok_state(empty,"import empty job"))==canon(Q.empty_state()),"empty job imports as empty state")
	expect_reject(Q.import_legacy({},R,NAN,hid(7)),"empty job with NaN now")
	expect_reject(Q.import_legacy({},R,-1.0,hid(7)),"empty job with negative now")

	var bads:Array=[
		["empty cost",{"kind":"soup","ready":110.0,"owner":"alice","ingredients":{}},105.0,hid(8)],
		["fraction cost",{"kind":"soup","ready":110.0,"owner":"alice","ingredients":{"radish":2.5}},105.0,hid(8)],
		["bool cost",{"kind":"soup","ready":110.0,"owner":"alice","ingredients":{"radish":true}},105.0,hid(8)],
		["bool yield",{"kind":"soup","ready":110.0,"owner":"alice","yield":true},105.0,hid(8)],
		["version 2",{"kind":"soup","ready":110.0,"owner":"alice","recipe_version":2},105.0,hid(8)],
		["unknown field",{"kind":"soup","ready":110.0,"owner":"alice","bonus":1},105.0,hid(8)],
		["started field",{"kind":"soup","ready":110.0,"owner":"alice","started":100.0},105.0,hid(8)],
		["empty owner",{"kind":"soup","ready":110.0,"owner":""},105.0,hid(8)],
		["int owner",{"kind":"soup","ready":110.0,"owner":5},105.0,hid(8)],
		["long owner",{"kind":"soup","ready":110.0,"owner":"a".repeat(65)},105.0,hid(8)],
		["missing owner",{"kind":"soup","ready":110.0},105.0,hid(8)],
		["unknown kind",{"kind":"cake","ready":110.0,"owner":"alice"},105.0,hid(8)],
		["missing kind",{"ready":110.0,"owner":"alice"},105.0,hid(8)],
		["missing ready",{"kind":"soup","owner":"alice"},105.0,hid(8)],
		["negative deadline",{"kind":"soup","ready":-1.0,"owner":"alice"},105.0,hid(8)],
		["NaN ready",{"kind":"soup","ready":NAN,"owner":"alice"},105.0,hid(8)],
		["INF ready",{"kind":"soup","ready":INF,"owner":"alice"},105.0,hid(8)],
		["string ready",{"kind":"soup","ready":"110","owner":"alice"},105.0,hid(8)],
		["bool ready",{"kind":"soup","ready":true,"owner":"alice"},105.0,hid(8)],
		["bad id",{"kind":"soup","ready":110.0,"owner":"alice"},105.0,UPPER_ID],
		["empty id",{"kind":"soup","ready":110.0,"owner":"alice"},105.0,""],
		["NaN now",{"kind":"soup","ready":110.0,"owner":"alice"},NAN,hid(8)],
	]
	for b in bads:
		var row:Array=b
		var bj:Dictionary=row[1]
		var bj_snap:=snap(bj)
		expect_reject(Q.import_legacy(bj,R,float(row[2]),str(row[3])),"legacy import with "+str(row[0]))
		expect(snap(bj)==bj_snap,"legacy rejection leaves job untouched: "+str(row[0]))
