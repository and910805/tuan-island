extends SceneTree
## Save schema 20: optional stove `cooking` queue state (T036).
## Explicit fixtures from a real fresh World; queue state is built with the real
## CookingQueue helper (real ingredients/durations) or hand-mutated from it.
## Production World code is never overridden.
## Run: godot --headless --path game --script res://tests/test_cooking_queue_schema.gd
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const History=preload("res://scripts/construction_history.gd")
const A:="cooking-schema-owner"
const B:="cooking-schema-friend"
const FLOOR:=Vector2i(50,26)
const STOVE_CELL:=Vector2i(50,25)
const HOME_STOVE:="50,25"
const REGION:="lanyang"
const REGION_STOVE:="60,45"
const NOW:=925.0
var checks:=0
var failures:=0
var path:=""
var OLD:Dictionary={}

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+message)

func valid(s:Dictionary)->bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func same(a,b)->bool:
	return History.canonical(a)==History.canonical(b)

func hid(n:int)->String:
	return "%032x"%n

func json(s:Dictionary)->Dictionary:
	return JSON.parse_string(JSON.stringify(s))

func write_candidate(candidate:Dictionary)->void:
	# A stale .bak would let load_world recover instead of reporting rejection.
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(candidate));f.close()

## Loads a candidate through the real World file path; null when rejected.
func load_real(candidate:Dictionary):
	write_candidate(candidate)
	var w:=World.new()
	if not w.load_world(path):return null
	return w

func stove(s:Dictionary,where:String)->Dictionary:
	if where=="home":return s.objects[HOME_STOVE]
	return s.regions[REGION].objects[REGION_STOVE]

func legacy_job(ready:float)->Dictionary:
	# Same shape World.act("cook") writes, but with historical costs/yield.
	return {"kind":"bread","ready":ready,"owner":A,"ingredients":{"wheat":3},"yield":2,"recipe_version":1}

func fixture()->Dictionary:
	var world:=World.new()
	world.add_player(A,"排程主廚")
	world.add_player(B,"幫手")
	world.undo_clock_utc=func():return 1800000000.0
	world.undo_clock_ticks=func():return 1000
	world.state.time=NOW
	world.state.players[A].x=48.5
	world.state.players[A].y=26.5
	world.state.players[A].inventory.wood=100
	check(world.act(A,"fixture-floor","build",FLOOR,"floor").ok,"real construction creates live history")
	var s:=json(world.state)
	s.objects[HOME_STOVE]={"type":"stove","owner":A,"items":{}}
	s.regions[REGION].objects[REGION_STOVE]={"type":"stove","owner":B,"items":{}}
	s.players[A].inventory.radish=7
	# An ordinary material exercises preservation of unrelated inventory IDs.
	s.players[A].inventory.stone=3
	s.players[B].inventory.wheat=4
	s.unrelated_future_note={"keep":["me",1]}
	# Dot assignment of new keys can introduce StringName keys in GDScript.
	# SaveSchema consumes JSON dictionaries with String keys, as load_real does.
	return json(s)

## active soup + 2 waiting (one historical bread: wheat 3, yield 2, 7s) + 2 ready.
func mixed_queue(owner:String,base:int)->Dictionary:
	var bag:Dictionary={"radish":20,"wheat":10}
	var q:Dictionary=Queue.empty_state()
	for i in 3:
		var r:=Queue.enqueue(q,World.RECIPES,900.0,owner,"soup",hid(base+i),bag)
		check(r.ok,"fixture soup %d queued"%i)
		q=r.state;bag=r.inventory
	var adv:=Queue.advance(q,World.RECIPES,NOW)
	check(adv.ok and adv.state.ready.size()==2,"fixture advances two soups to ready")
	q=adv.state
	var r:=Queue.enqueue(q,World.RECIPES,NOW,owner,"soup",hid(base+3),bag)
	check(r.ok,"fixture waiting soup queued");q=r.state;bag=r.inventory
	r=Queue.enqueue(q,OLD,NOW,owner,"bread",hid(base+4),bag)
	check(r.ok,"fixture historical bread queued");q=r.state
	return q

func full_queue(owner:String,base:int,count:int,at:float)->Dictionary:
	var bag:Dictionary={"radish":2*count}
	var q:Dictionary=Queue.empty_state()
	for i in count:
		var r:=Queue.enqueue(q,World.RECIPES,at,owner,"soup",hid(base+i),bag)
		check(r.ok,"full fixture job %d queued"%i)
		if not r.ok:break
		q=r.state;bag=r.inventory
	return q

func with_cooking(base:Dictionary,where:String,cooking,version:int=20)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.version=version
	if int(s.version)<25:
		s.erase("flower_nursery")
		s.regions.erase("tianwei")
		s.erase("salt_pan")
		s.regions.erase("beimen")
	if version<23:s.erase("public_kitchen")
	stove(s,where).cooking=cooking.duplicate(true) if (cooking is Dictionary or cooking is Array) else cooking
	return s

func mutate(o:Dictionary,c:String)->void:
	var q=o.get("cooking")
	match c:
		"type_array":o.cooking=[]
		"type_string":o.cooking="queue"
		"type_number":o.cooking=5
		"type_null":o.cooking=null
		"type_bool":o.cooking=true
		"empty_object":o.cooking={}
		"missing_ready":q.erase("ready")
		"extra_state_key":q.paused=false
		"active_array":q.active=[]
		"waiting_dict":q.waiting={}
		"ready_null":q.ready=null
		"with_legacy_job":o.job=legacy_job(NOW+5.0)
		"on_table":o.type="table"
		"on_chest":o.type="chest"
		"started_nan":q.active.started=NAN
		"finish_inf":q.active.finish=INF
		"duration_nan":q.waiting[0].duration=NAN
		"duration_neg_inf":q.waiting[0].duration=-INF
		"completed_nan":q.ready[0].completed=NAN
		"duration_zero":q.waiting[0].duration=0.0
		"duration_negative":q.waiting[0].duration=-7.0
		"duration_string":q.waiting[0].duration="7"
		"duration_huge":q.waiting[0].duration=Queue.MAX_TIME*2.0
		"finish_mismatch":q.active.finish=float(q.active.finish)+1.0
		"started_future":
			q.active.started=NOW+1.0
			q.active.finish=NOW+1.0+float(q.active.duration)
		"completed_future":q.ready[1].completed=NOW+1.0
		"ready_order":q.ready.reverse()
		"active_before_ready":
			q.active.started=float(q.ready[1].completed)-1.0
			q.active.finish=float(q.active.started)+float(q.active.duration)
		"orphan_waiting":q.active={}
		"dup_waiting":q.waiting[1].id=q.waiting[0].id
		"dup_active":q.waiting[0].id=q.active.id
		"dup_ready":q.ready[0].id=q.ready[1].id
		"dup_ready_active":q.ready[0].id=q.active.id
		"id_upper":q.waiting[0].id="A".repeat(32)
		"id_short":q.waiting[0].id="abc"
		"id_long":q.waiting[0].id="a".repeat(33)
		"id_number":q.waiting[0].id=5
		"kind_unknown":q.waiting[0].kind="removed_recipe"
		"kind_number":q.active.kind=3
		"recipe_version_2":q.waiting[1].recipe_version=2
		"recipe_version_0":q.ready[0].recipe_version=0
		"recipe_version_missing":q.active.erase("recipe_version")
		"yield_zero":q.waiting[1]["yield"]=0
		"yield_fraction":q.waiting[1]["yield"]=1.5
		"yield_negative":q.ready[0]["yield"]=-2
		"yield_string":q.active["yield"]="2"
		"yield_huge":q.active["yield"]=Queue.ITEM_CAP+1
		"ingredients_empty":q.waiting[1].ingredients={}
		"ingredients_zero":q.waiting[1].ingredients={"wheat":0}
		"ingredients_negative":q.waiting[1].ingredients={"wheat":-3}
		"ingredients_fraction":q.waiting[1].ingredients={"wheat":2.5}
		"ingredients_array":q.waiting[1].ingredients=["wheat",3]
		"ingredients_long_key":q.waiting[1].ingredients={"w".repeat(65):3}
		"record_not_dict":q.waiting[0]="soup"
		"record_extra":q.waiting[0].note="x"
		"record_missing_duration":q.waiting[0].erase("duration")
		"active_missing_finish":q.active.erase("finish")
		"waiting_has_finish":q.waiting[0].finish=NOW+20.0
		"ready_has_started":q.ready[0].started=900.0
		"owner_empty":q.waiting[0].owner=""
		"owner_65":q.waiting[0].owner="o".repeat(65)
		"active_owner_65":q.active.owner="o".repeat(65)
		"ready_owner_65":q.ready[0].owner="o".repeat(65)
		"owner_number":q.ready[1].owner=7
		"owner_null":q.active.owner=null
		"eleven":
			for n in 6:
				var extra:Dictionary=q.waiting[0].duplicate(true)
				extra.id=hid(5000+n)
				q.waiting.append(extra)
		_:push_error("unknown mutation "+c)

const NONFINITE:=["started_nan","finish_inf","duration_nan","duration_neg_inf","completed_nan"]
const CASES:=["type_array","type_string","type_number","type_null","type_bool","empty_object","missing_ready","extra_state_key","active_array","waiting_dict","ready_null","with_legacy_job","on_table","on_chest","started_nan","finish_inf","duration_nan","duration_neg_inf","completed_nan","duration_zero","duration_negative","duration_string","duration_huge","finish_mismatch","started_future","completed_future","ready_order","active_before_ready","orphan_waiting","dup_waiting","dup_active","dup_ready","dup_ready_active","id_upper","id_short","id_long","id_number","kind_unknown","kind_number","recipe_version_2","recipe_version_0","recipe_version_missing","yield_zero","yield_fraction","yield_negative","yield_string","yield_huge","ingredients_empty","ingredients_zero","ingredients_negative","ingredients_fraction","ingredients_array","ingredients_long_key","record_not_dict","record_extra","record_missing_duration","active_missing_finish","waiting_has_finish","ready_has_started","owner_empty","owner_65","active_owner_65","ready_owner_65","owner_number","owner_null","eleven"]

func _initialize()->void:run.call_deferred()

func run()->void:
	path="user://cooking-queue-schema-%d.json"%Time.get_ticks_usec()
	OLD=World.RECIPES.duplicate(true)
	OLD.bread.ingredients={"wheat":3}
	OLD.bread["yield"]=2
	OLD.bread.time=7.0

	# --- constants / literal cutoffs ---------------------------------------------
	check(Schema.VERSION==27,"save schema version is 21")
	check(Schema.COOKING_QUEUE_VERSION==20,"cooking queue cutoff literal is 20")
	check(Schema.BLUEPRINT_HISTORY_VERSION==19,"blueprint cutoff literal stays 19")
	check(Queue.CAPACITY==10 and Queue.OWNER_MAX==64,"helper capacity 10 and owner bound 64")

	# --- baseline from a real fresh World -----------------------------------------
	var base:=fixture()
	check(int(base.version)==preload("res://scripts/save_schema.gd").VERSION,"fresh World writes version 20")
	check(not stove(base,"home").has("cooking") and not stove(base,"region").has("cooking"),"fixture stoves carry no queue")
	var plain:Dictionary=base.duplicate(true)
	check(valid(plain) and int(plain.version)==preload("res://scripts/save_schema.gd").VERSION,"v20 stoves without cooking accepted")
	check(not stove(plain,"home").has("cooking") and not stove(plain,"region").has("cooking"),"missing cooking is never invented on load")
	var live=load_real(base)
	check(live!=null,"real World loads the baseline file")
	if live==null:
		print("COOKING_QUEUE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures]);quit(1);return

	# --- v20 queues accepted, preserved and JSON round-tripped --------------------
	var home_q:=mixed_queue(A,100)
	var region_q:=mixed_queue(B,200)
	check(Queue.validate(home_q,World.RECIPES,NOW),"helper accepts historical snapshot against current recipes")
	var both:=with_cooking(base,"home",home_q)
	stove(both,"region").cooking=region_q.duplicate(true)
	var both_input:Dictionary=both.duplicate(true)
	check(valid(both) and int(both.version)==preload("res://scripts/save_schema.gd").VERSION,"home and regional queues accepted at v20")
	check(same(stove(both,"home").cooking,home_q) and same(stove(both,"region").cooking,region_q),"validated queues unchanged")
	var hist:Dictionary=stove(both,"home").cooking.waiting[1]
	check(hist.kind=="bread" and same(hist.ingredients,{"wheat":3}) and int(hist["yield"])==2 and float(hist.duration)==7.0,"historical ingredients/yield/duration retained independent of current recipe")
	var trip:=json(both_input)
	check(valid(trip),"JSON round-trip of queues accepted")
	check(trip.objects[HOME_STOVE].cooking.waiting[1]["yield"] is int and trip.objects[HOME_STOVE].cooking.waiting[1].ingredients.wheat is int,"JSON whole floats normalised to int counts")
	check(same(trip.objects[HOME_STOVE].cooking,home_q) and same(trip.regions[REGION].objects[REGION_STOVE].cooking,region_q),"JSON round-trip preserves queue exactly")
	var real=load_real(both_input)
	check(real!=null,"real World loads v20 queue file")
	if real!=null:
		check(same(real.state.objects[HOME_STOVE].cooking,home_q) and same(real.state.regions[REGION].objects[REGION_STOVE].cooking,region_q),"real World keeps both queues")
		check(Queue.validate(real.state.objects[HOME_STOVE].cooking,World.RECIPES,float(real.state.time)),"loaded queue still valid for helper")
		check(real.save(),"real World saves loaded queue")
		var again:=World.new()
		check(again.load_world(path) and same(again.state.objects[HOME_STOVE].cooking,home_q),"saved queue reloads identically")
	# Owner at the 64-character bound.
	var long_owner:=mixed_queue("o".repeat(64),300)
	check(valid(with_cooking(base,"home",long_owner)),"64-character nested owner accepted")
	check(valid(with_cooking(base,"region",Queue.empty_state())),"canonical empty queue accepted on regional stove")

	# --- capacity -----------------------------------------------------------------
	for where in ["home","region"]:
		var ten:=full_queue(A,400,10,NOW)
		check(ten.waiting.size()==9,"ten fixture = active + 9 waiting")
		var s10:=with_cooking(base,where,ten)
		check(valid(s10) and same(stove(s10,where).cooking,ten),"%s: ten queued jobs accepted"%where)
		var eleven:Dictionary=ten.duplicate(true)
		var extra:Dictionary=eleven.waiting[0].duplicate(true)
		extra.id=hid(499)
		eleven.waiting.append(extra)
		check(not valid(with_cooking(base,where,eleven)),"%s: eleven queued jobs rejected"%where)
		var ready10:Dictionary=Queue.advance(full_queue(A,600,10,800.0),World.RECIPES,NOW).state
		check(ready10.ready.size()==10,"ten jobs all completed")
		check(valid(with_cooking(base,where,ready10)),"%s: ten unclaimed ready jobs accepted"%where)
		var ready11:Dictionary=ready10.duplicate(true)
		var more:Dictionary=ready11.ready[9].duplicate(true)
		more.id=hid(699)
		ready11.ready.append(more)
		check(not valid(with_cooking(base,where,ready11)),"%s: eleven ready jobs rejected"%where)
		check(not valid(json(with_cooking(base,where,ready11))),"%s: eleven ready jobs rejected after JSON"%where)

	# --- malformed nested state rejected (home and regional), never emptied --------
	var control:Dictionary=base.duplicate(true)
	stove(control,"home").type="table"
	check(valid(control),"control: table without cooking is valid")
	for where in ["home","region"]:
		var q:=mixed_queue(A if where=="home" else B,700)
		for c in CASES:
			var s:=with_cooking(base,where,q)
			mutate(stove(s,where),c)
			var bad_snapshot=stove(s,where).get("cooking")
			bad_snapshot=bad_snapshot.duplicate(true) if (bad_snapshot is Dictionary or bad_snapshot is Array) else bad_snapshot
			var dict_copy:Dictionary=s.duplicate(true)
			check(not valid(dict_copy),"%s: %s rejected"%[where,c])
			var after=stove(dict_copy,where).get("cooking")
			check(History.canonical(after)==History.canonical(bad_snapshot),"%s: %s rejected state kept as-is, never replaced/emptied"%[where,c])
			if c in NONFINITE:continue
			var before:String=History.canonical(live.state)
			check(not live.load_world(_write_and_path(s)),"%s: %s rejected by real World load"%[where,c])
			check(History.canonical(live.state)==before,"%s: %s rejection leaves live World untouched"%[where,c])
	# Cooking on ground/roof layer objects (non-stove) rejected.
	var on_floor:Dictionary=base.duplicate(true)
	on_floor.ground[World.key(FLOOR)].cooking=Queue.empty_state()
	check(not valid(on_floor),"cooking on floor rejected")
	# Record ids must be unique across stoves.
	var cross:=with_cooking(base,"home",mixed_queue(A,800))
	stove(cross,"region").cooking=mixed_queue(B,804)
	check(not valid(cross.duplicate(true)),"duplicate job id across home and regional stoves rejected")
	stove(cross,"region").cooking=mixed_queue(B,805)
	check(valid(cross.duplicate(true)),"distinct ids across stoves accepted")
	var two_regions:=with_cooking(base,"region",mixed_queue(B,900))
	two_regions.regions["jinguashi"].objects["20,30"]={"type":"stove","owner":A,"items":{},"cooking":mixed_queue(A,910)}
	check(valid(two_regions.duplicate(true)),"control: queues on stoves in two regions accepted")
	two_regions.regions["jinguashi"].objects["20,30"].cooking=mixed_queue(A,900)
	check(not valid(two_regions.duplicate(true)),"duplicate job id across two regions rejected")

	# --- old versions carrying cooking = unknown forward state ---------------------
	for version in [19,18,17]:
		for where in ["home","region"]:
			for cooking in [Queue.empty_state(),mixed_queue(A,950)]:
				var s:=with_cooking(base,where,cooking,version)
				if version<18:s.erase("construction")
				var copy:Dictionary=s.duplicate(true)
				check(not valid(copy),"v%d %s stove with cooking rejected"%[version,where])
				check(int(copy.version)==version,"v%d rejection did not stamp version"%version)
				check(History.canonical(stove(copy,where).cooking)==History.canonical(stove(s,where).cooking),"v%d forward cooking kept for inspection, not emptied"%version)
		var v_bad:=with_cooking(base,"region",mixed_queue(A,960),version)
		check(not live.load_world(_write_and_path(v_bad)),"real World rejects v%d forward cooking"%version)
	var future:Dictionary=base.duplicate(true)
	future.version=Schema.VERSION+1
	check(not valid(future),"future version rejected")

	# --- legacy stove.job valid in old versions and 20, preserved exactly ----------
	for version in [20,19,18,17]:
		for where in ["home","region"]:
			var s:Dictionary=base.duplicate(true)
			s.version=version
			if int(s.version)<25:
				s.erase("flower_nursery")
				s.regions.erase("tianwei")
				s.erase("salt_pan")
				s.regions.erase("beimen")
			if version<23:s.erase("public_kitchen")
			if version<18:s.erase("construction")
			stove(s,where).job=legacy_job(NOW-1.0)
			var inventory_before:Dictionary=s.players.duplicate(true)
			var keys_before:Array=s.players[A].inventory.keys()
			keys_before.sort()
			check(valid(s) and int(s.version)==preload("res://scripts/save_schema.gd").VERSION,"v%d %s legacy job accepted -> 20"%[version,where])
			check(same(stove(s,where).job,legacy_job(NOW-1.0)),"v%d %s historical job (wheat 3, yield 2) preserved"%[version,where])
			check(not stove(s,where).has("cooking"),"v%d %s legacy job not converted at load"%[version,where])
			var keys_after:Array=s.players[A].inventory.keys()
			keys_after.sort()
			check(same(s.players[A].inventory,inventory_before[A].inventory) and same(s.players[B].inventory,inventory_before[B].inventory) and keys_after==keys_before,"v%d %s inventories and item ids unchanged"%[version,where])
			check(same(s.unrelated_future_note,{"keep":["me",1]}),"v%d %s unrelated state kept"%[version,where])
	var both_kinds:=with_cooking(base,"region",mixed_queue(B,970))
	stove(both_kinds,"home").job=legacy_job(NOW+5.0)
	check(valid(both_kinds),"legacy job on one stove and queue on another accepted")

	# Real World: v19 legacy job loads, is claimable with historical yield.
	var v19:Dictionary=base.duplicate(true)
	v19.version=19;v19.erase("public_kitchen")
	if int(v19.version)<25:
		v19.erase("flower_nursery")
		v19.regions.erase("tianwei")
		v19.erase("salt_pan")
		v19.regions.erase("beimen")
	stove(v19,"home").job=legacy_job(NOW-1.0)
	var w19=load_real(v19)
	check(w19!=null and int(w19.state.version)==preload("res://scripts/save_schema.gd").VERSION,"real World loads v19 legacy job as 20")
	if w19!=null:
		check(w19.state.objects[HOME_STOVE].has("job") and not w19.state.objects[HOME_STOVE].has("cooking"),"general load does not convert legacy job")
		var claimed:Dictionary=w19.act(A,"claim-legacy","claim_cook",STOVE_CELL)
		check(claimed.ok and int(w19.state.players[A].inventory.get("bread",0))==2,"legacy claim keeps historical yield 2")
		check(int(w19.state.players[A].inventory.radish)==7 and int(w19.state.players[A].inventory.stone)==3,"claim leaves unrelated inventory ids intact")
	# Real World: lazy conversion on first queue_cook preserves the old snapshot.
	var v19b:Dictionary=base.duplicate(true)
	v19b.version=19;v19b.erase("public_kitchen")
	if int(v19b.version)<25:
		v19b.erase("flower_nursery")
		v19b.regions.erase("tianwei")
		v19b.erase("salt_pan")
		v19b.regions.erase("beimen")
	stove(v19b,"home").job=legacy_job(NOW+5.0)
	var lazy=load_real(v19b)
	check(lazy!=null,"real World loads v19 unfinished legacy job")
	if lazy!=null:
		var queued:Dictionary=lazy.act(A,"queue-1","queue_cook",STOVE_CELL,"soup")
		check(queued.ok,"queue_cook on legacy stove succeeds")
		var st:Dictionary=lazy.state.objects[HOME_STOVE]
		check(not st.has("job") and st.has("cooking") and not st.cooking.active.is_empty(),"queue_cook converts the legacy job lazily")
		if st.has("cooking") and not st.cooking.active.is_empty():
			check(st.cooking.active.kind=="bread" and same(st.cooking.active.ingredients,{"wheat":3}) and int(st.cooking.active["yield"])==2 and float(st.cooking.active.finish)==NOW+5.0,"converted record keeps historical costs, yield and deadline")
			check(st.cooking.waiting.size()==1 and same(st.cooking.waiting[0].ingredients,World.RECIPES.soup.ingredients),"new enqueue copies current recipe")
		check(int(lazy.state.players[A].inventory.radish)==5,"only the new job's ingredients charged")
		check(lazy.save(),"converted world saves")
		var reloaded:=World.new()
		check(reloaded.load_world(path) and int(reloaded.state.version)==preload("res://scripts/save_schema.gd").VERSION,"converted v20 queue file reloads")
		check(same(reloaded.state.objects.get(HOME_STOVE,{}).get("cooking"),st.get("cooking")),"converted queue round-trips through World save")

	# --- prior migrations still behave with literal cutoffs ------------------------
	var v18:Dictionary=base.duplicate(true)
	v18.version=18;v18.erase("public_kitchen")
	if int(v18.version)<25:
		v18.erase("flower_nursery")
		v18.regions.erase("tianwei")
		v18.erase("salt_pan")
		v18.regions.erase("beimen")
	var v18_history:Dictionary=v18.construction.duplicate(true)
	var v18_ground:Dictionary=v18.ground.duplicate(true)
	check(valid(v18) and int(v18.version)==preload("res://scripts/save_schema.gd").VERSION,"v18 migrates to 20")
	check(same(v18.construction,v18_history) and v18.construction.last[A].status=="live","v18 live undo history preserved")
	check(same(v18.ground,v18_ground),"v18 construction layers preserved")
	var v17:Dictionary=base.duplicate(true)
	v17.version=17;v17.erase("public_kitchen")
	if int(v17.version)<25:
		v17.erase("flower_nursery")
		v17.regions.erase("tianwei")
		v17.erase("salt_pan")
		v17.regions.erase("beimen")
	check(valid(v17) and v17.construction==History.fresh(),"pre-18 cutoff unchanged: stray history replaced with fresh")
	var bp:Dictionary=base.duplicate(true)
	bp.construction.last[A].action="blueprint"
	bp.construction.last[A].builds=26
	var bp19:Dictionary=bp.duplicate(true);bp19.version=19;bp19.erase("public_kitchen")
	if int(bp19.version)<25:
		bp19.erase("flower_nursery")
		bp19.regions.erase("tianwei")
		bp19.erase("salt_pan")
		bp19.regions.erase("beimen")
	check(valid(bp19) and bp19.construction.last[A].action=="blueprint" and int(bp19.construction.last[A].builds)==26,"v19 blueprint history migrates to 20 intact")
	var bp18:Dictionary=bp.duplicate(true);bp18.version=18;bp18.erase("public_kitchen")
	if int(bp18.version)<25:
		bp18.erase("flower_nursery")
		bp18.regions.erase("tianwei")
		bp18.erase("salt_pan")
		bp18.regions.erase("beimen")
	check(not valid(bp18),"pre-19 cutoff unchanged: v18 blueprint history rejected")
	var roofed:Dictionary=base.duplicate(true)
	roofed.roofs[World.key(FLOOR)]={"type":"roof","owner":A,"items":{},"auto":true}
	for version in [20,19,18,17]:
		var r:Dictionary=roofed.duplicate(true);r.version=version
		if int(r.version)<25:
			r.erase("flower_nursery")
			r.regions.erase("tianwei")
			r.erase("salt_pan")
			r.regions.erase("beimen")
		if version<23:r.erase("public_kitchen")
		if version<18:r.erase("construction")
		check(valid(r) and r.roofs[World.key(FLOOR)].auto==true,"v%d auto roof accepted"%version)
	var r16:Dictionary=roofed.duplicate(true);r16.version=16;r16.erase("public_kitchen");r16.erase("construction")
	if int(r16.version)<25:
		r16.erase("flower_nursery")
		r16.regions.erase("tianwei")
		r16.erase("salt_pan")
		r16.regions.erase("beimen")
	check(not valid(r16),"pre-17 cutoff unchanged: v16 auto roof rejected")
	var m16:Dictionary=roofed.duplicate(true);m16.version=16;m16.erase("public_kitchen");m16.erase("construction")
	if int(m16.version)<25:
		m16.erase("flower_nursery")
		m16.regions.erase("tianwei")
		m16.erase("salt_pan")
		m16.regions.erase("beimen")
	m16.roofs[World.key(FLOOR)].auto=false
	check(valid(m16) and int(m16.version)==preload("res://scripts/save_schema.gd").VERSION,"v16 manual roof migrates to 20")

	check(History.canonical(live.state)!="" and not live.state.objects.get(HOME_STOVE,{}).has("cooking"),"live World never adopted a rejected queue")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COOKING_QUEUE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func _write_and_path(candidate:Dictionary)->String:
	write_candidate(candidate)
	return path
