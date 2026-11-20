extends SceneTree
## Save schema 21: optional sawmill/charcoal_kiln `processing` queue (T036).
## FIXTURES: built from a real fresh World (real construction history), then
## stations are inserted into the JSON state. Every queue is produced by the real
## CookingQueue helper against SaveSchema.processing_recipes(station) (i.e.
## Industry.PROCESS filtered to that station), or hand-mutated from such a queue.
## "Historical" records come from a labelled OLD recipe catalog (wood 3, yield 1,
## 9s) to prove saved snapshots stay authoritative. No production code is
## overridden and no stubs are used; World is exercised only via load_world/save.
## Run: godot --headless --path game --script res://tests/test_processing_queue_schema.gd
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const History=preload("res://scripts/construction_history.gd")
const A:="processing-schema-owner"
const B:="processing-schema-friend"
const FLOOR:=Vector2i(50,26)
const HOME_CELL:="50,25"      # sawmill, owner A
const LAN:="lanyang"
const LAN_CELL:="60,45"       # charcoal_kiln, owner B
const JIN:="jinguashi"
const JIN_CELL:="20,30"       # stove, owner A (cooking queue control / cross-queue ids)
const NOW:=925.0
var checks:=0
var failures:=0
var path:=""
## Labelled historical catalogs: older plank/charcoal prices than Industry.PROCESS.
var OLD_SAW:Dictionary={}
var OLD_KILN:Dictionary={}

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

func _write_and_path(candidate:Dictionary)->String:
	write_candidate(candidate)
	return path

## Loads a candidate through the real World file path; null when rejected.
func load_real(candidate:Dictionary):
	write_candidate(candidate)
	var w:=World.new()
	if not w.load_world(path):return null
	return w

func station(s:Dictionary,where:String)->Dictionary:
	match where:
		"home":return s.objects[HOME_CELL]
		"lanyang":return s.regions[LAN].objects[LAN_CELL]
	return s.regions[JIN].objects[JIN_CELL]

func station_type(where:String)->String:
	return "sawmill" if where=="home" else "charcoal_kiln"

func station_owner(where:String)->String:
	return A if where=="home" else B

func product(where:String)->String:
	return "plank" if where=="home" else "charcoal"

func other_product(where:String)->String:
	return "charcoal" if where=="home" else "plank"

func fixture()->Dictionary:
	var world:=World.new()
	world.add_player(A,"加工主人")
	world.add_player(B,"炭窯友")
	world.undo_clock_utc=func():return 1800000000.0
	world.undo_clock_ticks=func():return 1000
	world.state.time=NOW
	world.state.players[A].x=48.5
	world.state.players[A].y=26.5
	world.state.players[A].inventory.wood=100
	check(world.act(A,"fixture-floor","build",FLOOR,"floor").ok,"real construction creates live history")
	var s:=json(world.state)
	# Non-empty automatic buffer on the home sawmill proves input_wood/items survive.
	s.objects[HOME_CELL]={"type":"sawmill","owner":A,"items":{"plank":3},"input_wood":5,"auto_enabled":false}
	s.regions[LAN].objects[LAN_CELL]={"type":"charcoal_kiln","owner":B,"items":{},"input_wood":0,"auto_enabled":false}
	s.regions[JIN].objects[JIN_CELL]={"type":"stove","owner":A,"items":{}}
	s.players[A].inventory.wood=40
	s.players[A].inventory.stone=3
	s.players[B].inventory.wood=9
	s.unrelated_future_note={"keep":["me",1]}
	return json(s)

## active + 2 waiting (one historical) + 2 ready, all owned by the station owner.
func mixed_queue(where:String,base:int,owner:String="")->Dictionary:
	var who:=owner if owner!="" else station_owner(where)
	var catalog:=Schema.processing_recipes(station_type(where))
	var old:Dictionary=OLD_SAW if where=="home" else OLD_KILN
	var kind:=product(where)
	var t:float=float(catalog[kind].time)
	var start:=NOW-2.0*t-1.0
	var bag:Dictionary={"wood":100}
	var q:Dictionary=Queue.empty_state()
	for i in 3:
		var r:=Queue.enqueue(q,catalog,start,who,kind,hid(base+i),bag)
		check(r.ok,"fixture %s job %d queued"%[kind,i])
		q=r.state;bag=r.inventory
	var adv:=Queue.advance(q,catalog,NOW)
	check(adv.ok and adv.state.ready.size()==2 and not adv.state.active.is_empty(),"fixture advances two %s jobs to ready"%kind)
	q=adv.state
	var r:=Queue.enqueue(q,catalog,NOW,who,kind,hid(base+3),bag)
	check(r.ok,"fixture waiting %s queued"%kind);q=r.state;bag=r.inventory
	r=Queue.enqueue(q,old,NOW,who,kind,hid(base+4),bag)
	check(r.ok,"fixture historical %s queued"%kind);q=r.state
	return q

func full_queue(where:String,base:int,count:int,at:float)->Dictionary:
	var catalog:=Schema.processing_recipes(station_type(where))
	var bag:Dictionary={"wood":4*count}
	var q:Dictionary=Queue.empty_state()
	for i in count:
		var r:=Queue.enqueue(q,catalog,at,station_owner(where),product(where),hid(base+i),bag)
		check(r.ok,"full fixture job %d queued"%i)
		if not r.ok:break
		q=r.state;bag=r.inventory
	return q

func cooking_queue(owner:String,base:int)->Dictionary:
	var bag:Dictionary={"radish":20}
	var q:Dictionary=Queue.empty_state()
	for i in 3:
		var r:=Queue.enqueue(q,World.RECIPES,NOW-1.0,owner,"soup",hid(base+i),bag)
		check(r.ok,"fixture cooking soup %d queued"%i)
		q=r.state;bag=r.inventory
	return q

func with_processing(base:Dictionary,where:String,processing,version:int=21)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.version=version
	if int(s.version)<25:
		s.erase("flower_nursery")
		s.regions.erase("tianwei")
		s.erase("salt_pan")
		s.regions.erase("beimen")
	if version<23:s.erase("public_kitchen")
	station(s,where).processing=processing.duplicate(true) if (processing is Dictionary or processing is Array) else processing
	return s

func legacy_job(where:String,ready:float,auto:bool=false)->Dictionary:
	# Same shape World.process_industry / logistics write (current recipe only).
	var job:={"kind":product(where),"owner":station_owner(where),"ready":ready,"ingredients":{"wood":4},"yield":2}
	if auto:job["auto"]=true
	return job

func mutate(o:Dictionary,c:String,where:String)->void:
	var q=o.get("processing")
	match c:
		"type_array":o.processing=[]
		"type_string":o.processing="queue"
		"type_number":o.processing=5
		"type_null":o.processing=null
		"type_bool":o.processing=true
		"empty_object":o.processing={}
		"missing_ready":q.erase("ready")
		"extra_state_key":q.paused=false
		"active_array":q.active=[]
		"waiting_dict":q.waiting={}
		"with_manual_job":o.job=legacy_job(where,NOW+5.0)
		"with_auto_job":o.job=legacy_job(where,NOW+5.0,true)
		"auto_enabled":o.auto_enabled=true
		"auto_enabled_string":o.auto_enabled="false"
		"on_stove":o.type="stove"
		"on_chest":o.type="chest"
		"wrong_station_active":q.active.kind=other_product(where)
		"wrong_station_waiting":q.waiting[0].kind=other_product(where)
		"wrong_station_ready":q.ready[0].kind=other_product(where)
		"cooking_recipe":q.waiting[0].kind="soup"
		"kind_number":q.active.kind=3
		"owner_active_other":q.active.owner=B if where=="home" else A
		"owner_waiting_other":q.waiting[1].owner=B if where=="home" else A
		"owner_ready_other":q.ready[1].owner=B if where=="home" else A
		"owner_empty":q.waiting[0].owner=""
		"owner_65":q.waiting[0].owner="o".repeat(65)
		"owner_number":q.ready[0].owner=7
		"device_owner_changed":o.owner=B if where=="home" else A
		"started_nan":q.active.started=NAN
		"finish_inf":q.active.finish=INF
		"duration_nan":q.waiting[0].duration=NAN
		"completed_nan":q.ready[0].completed=NAN
		"duration_zero":q.waiting[0].duration=0.0
		"duration_negative":q.waiting[0].duration=-7.0
		"duration_string":q.waiting[0].duration="12"
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
		"dup_ready_active":q.ready[0].id=q.active.id
		"id_upper":q.waiting[0].id="A".repeat(32)
		"id_short":q.waiting[0].id="abc"
		"id_number":q.waiting[0].id=5
		"recipe_version_2":q.waiting[1].recipe_version=2
		"recipe_version_missing":q.active.erase("recipe_version")
		"yield_zero":q.waiting[1]["yield"]=0
		"yield_fraction":q.waiting[1]["yield"]=1.5
		"yield_string":q.active["yield"]="2"
		"yield_huge":q.active["yield"]=Queue.ITEM_CAP+1
		"ingredients_empty":q.waiting[1].ingredients={}
		"ingredients_zero":q.waiting[1].ingredients={"wood":0}
		"ingredients_fraction":q.waiting[1].ingredients={"wood":2.5}
		"ingredients_array":q.waiting[1].ingredients=["wood",3]
		"record_not_dict":q.waiting[0]="plank"
		"record_extra":q.waiting[0].note="x"
		"record_auto_flag":q.active.auto=true
		"record_missing_duration":q.waiting[0].erase("duration")
		"active_missing_finish":q.active.erase("finish")
		"waiting_has_finish":q.waiting[0].finish=NOW+20.0
		"ready_has_started":q.ready[0].started=900.0
		"eleven":
			for n in 6:
				var extra:Dictionary=q.waiting[0].duplicate(true)
				extra.id=hid(5000+n)
				q.waiting.append(extra)
		_:push_error("unknown mutation "+c)

const NONFINITE:=["started_nan","finish_inf","duration_nan","completed_nan"]
const CASES:=["type_array","type_string","type_number","type_null","type_bool","empty_object","missing_ready","extra_state_key","active_array","waiting_dict",
	"with_manual_job","with_auto_job","auto_enabled","auto_enabled_string","on_stove","on_chest",
	"wrong_station_active","wrong_station_waiting","wrong_station_ready","cooking_recipe","kind_number",
	"owner_active_other","owner_waiting_other","owner_ready_other","owner_empty","owner_65","owner_number","device_owner_changed",
	"started_nan","finish_inf","duration_nan","completed_nan","duration_zero","duration_negative","duration_string","duration_huge",
	"finish_mismatch","started_future","completed_future","ready_order","active_before_ready","orphan_waiting",
	"dup_waiting","dup_active","dup_ready_active","id_upper","id_short","id_number","recipe_version_2","recipe_version_missing",
	"yield_zero","yield_fraction","yield_string","yield_huge","ingredients_empty","ingredients_zero","ingredients_fraction","ingredients_array",
	"record_not_dict","record_extra","record_auto_flag","record_missing_duration","active_missing_finish","waiting_has_finish","ready_has_started","eleven"]

func _initialize()->void:run.call_deferred()

func run()->void:
	path="user://processing-queue-schema-%d.json"%Time.get_ticks_usec()
	OLD_SAW={"plank":{"ingredients":{"wood":3},"time":9.0,"yield":1}}
	OLD_KILN={"charcoal":{"ingredients":{"wood":3},"time":9.0,"yield":1}}

	# --- constants / literal cutoffs ---------------------------------------------
	check(Schema.VERSION==27,"save schema version is 21")
	check(Schema.PROCESSING_QUEUE_VERSION==21,"processing queue cutoff literal is 21")
	check(Schema.COOKING_QUEUE_VERSION==20,"cooking queue cutoff literal stays 20")
	check(Schema.BLUEPRINT_HISTORY_VERSION==19,"blueprint cutoff literal stays 19")
	var saw:=Schema.processing_recipes("sawmill")
	var kiln:=Schema.processing_recipes("charcoal_kiln")
	check(saw.keys()==["plank"] and kiln.keys()==["charcoal"],"recipes filtered to station: %s / %s"%[saw.keys(),kiln.keys()])
	check(same(saw.plank.ingredients,World.INDUSTRY.PROCESS.plank.ingredients) and float(saw.plank.time)==float(World.INDUSTRY.PROCESS.plank.time) and int(saw.plank["yield"])==int(World.INDUSTRY.PROCESS.plank["yield"]),"sawmill catalog mirrors Industry.PROCESS")
	check(Schema.processing_recipes("stove").is_empty(),"no processing recipes for other stations")

	# --- baseline ------------------------------------------------------------------
	var base:=fixture()
	check(int(base.version)==preload("res://scripts/save_schema.gd").VERSION,"fresh World writes version 21")
	var plain:Dictionary=base.duplicate(true)
	check(valid(plain) and int(plain.version)==preload("res://scripts/save_schema.gd").VERSION,"v21 stations without processing accepted")
	for where in ["home","lanyang"]:
		check(not station(plain,where).has("processing"),"%s: missing processing never invented on load"%where)
	var live=load_real(base)
	check(live!=null,"real World loads the baseline file")
	if live==null:
		print("PROCESSING_QUEUE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures]);quit(1);return

	# --- v21 queues accepted, preserved and round-tripped ------------------------
	var home_q:=mixed_queue("home",100)
	var lan_q:=mixed_queue("lanyang",200)
	var stove_q:=cooking_queue(A,300)
	var both:=with_processing(base,"home",home_q)
	station(both,"lanyang").processing=lan_q.duplicate(true)
	station(both,"jinguashi").cooking=stove_q.duplicate(true)
	var both_input:Dictionary=both.duplicate(true)
	check(valid(both) and int(both.version)==preload("res://scripts/save_schema.gd").VERSION,"home sawmill + regional kiln processing + cooking accepted at v21")
	check(same(station(both,"home").processing,home_q) and same(station(both,"lanyang").processing,lan_q),"validated processing queues unchanged")
	check(same(station(both,"jinguashi").cooking,stove_q),"cooking queue unchanged next to processing queues")
	check(int(station(both,"home").input_wood)==5 and same(station(both,"home").items,{"plank":3}) and station(both,"home").auto_enabled==false,"automatic buffer input_wood/items preserved beside manual queue")
	for where in ["home","lanyang"]:
		var hist:Dictionary=station(both,where).processing.waiting[1]
		check(hist.kind==product(where) and same(hist.ingredients,{"wood":3}) and int(hist["yield"])==1 and float(hist.duration)==9.0,"%s: historical ingredients/yield/duration retained"%where)
	var trip:=json(both_input)
	check(valid(trip),"JSON round-trip of processing queues accepted")
	check(trip.objects[HOME_CELL].processing.waiting[1]["yield"] is int and trip.objects[HOME_CELL].processing.waiting[1].ingredients.wood is int,"JSON whole floats normalised to int counts")
	check(same(trip.objects[HOME_CELL].processing,home_q) and same(trip.regions[LAN].objects[LAN_CELL].processing,lan_q),"JSON round-trip preserves queues exactly")
	check(valid(with_processing(base,"lanyang",Queue.empty_state())),"canonical empty processing queue accepted on regional kiln")
	check(valid(with_processing(base,"home",Queue.empty_state())),"canonical empty processing queue accepted on home sawmill")

	# Real disk load -> save -> reload.
	var real=load_real(both_input)
	check(real!=null,"real World loads v21 processing file")
	if real!=null:
		check(same(real.state.objects[HOME_CELL].processing,home_q) and same(real.state.regions[LAN].objects[LAN_CELL].processing,lan_q),"real World keeps both processing queues")
		check(same(real.state.regions[JIN].objects[JIN_CELL].cooking,stove_q),"real World keeps cooking queue")
		check(Queue.validate(real.state.objects[HOME_CELL].processing,saw,float(real.state.time)),"loaded queue still valid for helper")
		check(not real.state.objects[HOME_CELL].has("job"),"loading never adds a job beside processing")
		check(real.save(),"real World saves loaded processing queues")
		var again:=World.new()
		check(again.load_world(path),"saved processing file reloads")
		check(same(again.state.objects.get(HOME_CELL,{}).get("processing"),home_q) and same(again.state.regions[LAN].objects.get(LAN_CELL,{}).get("processing"),lan_q),"saved processing queues reload identically")
		check(int(again.state.version)==preload("res://scripts/save_schema.gd").VERSION,"reloaded save is version 21")

	# --- capacity -------------------------------------------------------------------
	for where in ["home","lanyang"]:
		var ten:=full_queue(where,400,10,NOW)
		check(ten.waiting.size()==9,"%s: ten fixture = active + 9 waiting"%where)
		check(valid(with_processing(base,where,ten)),"%s: ten jobs accepted"%where)
		var eleven:Dictionary=ten.duplicate(true)
		var extra:Dictionary=eleven.waiting[0].duplicate(true)
		extra.id=hid(499)
		eleven.waiting.append(extra)
		check(not valid(with_processing(base,where,eleven)),"%s: eleven jobs rejected"%where)
		var ready10:Dictionary=Queue.advance(full_queue(where,600,10,700.0),Schema.processing_recipes(station_type(where)),NOW).state
		check(ready10.ready.size()==10,"%s: ten jobs all completed"%where)
		check(valid(with_processing(base,where,ready10)),"%s: ten unclaimed ready jobs accepted"%where)

	# --- malformed / conflicting state rejected, never emptied, live World untouched
	for where in ["home","lanyang"]:
		var q:=mixed_queue(where,700)
		for c in CASES:
			var s:=with_processing(base,where,q)
			mutate(station(s,where),c,where)
			var bad_snapshot=station(s,where).get("processing")
			bad_snapshot=bad_snapshot.duplicate(true) if (bad_snapshot is Dictionary or bad_snapshot is Array) else bad_snapshot
			var dict_copy:Dictionary=s.duplicate(true)
			check(not valid(dict_copy),"%s: %s rejected"%[where,c])
			check(History.canonical(station(dict_copy,where).get("processing"))==History.canonical(bad_snapshot),"%s: %s rejected state kept as-is, never replaced/emptied"%[where,c])
			if c in NONFINITE:continue
			var before:String=History.canonical(live.state)
			check(not live.load_world(_write_and_path(s)),"%s: %s rejected by real World load"%[where,c])
			check(History.canonical(live.state)==before,"%s: %s rejection leaves live World untouched"%[where,c])
	# Empty processing still conflicts with auto mode / authoritative job.
	for where in ["home","lanyang"]:
		var e:=with_processing(base,where,Queue.empty_state())
		station(e,where).auto_enabled=true
		check(not valid(e),"%s: empty processing with auto_enabled=true rejected"%where)
		var j:=with_processing(base,where,Queue.empty_state())
		station(j,where).job=legacy_job(where,NOW+1.0)
		check(not valid(j),"%s: empty processing with manual job rejected"%where)
	# Processing on the wrong layer / station types.
	var on_floor:Dictionary=base.duplicate(true)
	on_floor.ground[World.key(FLOOR)].processing=Queue.empty_state()
	check(not valid(on_floor),"processing on floor rejected")
	var on_stove:Dictionary=base.duplicate(true)
	station(on_stove,"jinguashi").processing=Queue.empty_state()
	check(not valid(on_stove),"processing on stove rejected")
	var cooking_on_saw:Dictionary=base.duplicate(true)
	station(cooking_on_saw,"home").cooking=Queue.empty_state()
	check(not valid(cooking_on_saw),"cooking on sawmill rejected")

	# --- global unique ids: cross-queue and cross-region ---------------------------
	var cross_q:=with_processing(base,"home",mixed_queue("home",800))
	station(cross_q,"jinguashi").cooking=cooking_queue(A,804)   # 804 collides with home waiting[1]
	check(not valid(cross_q.duplicate(true)),"duplicate id across processing (home) and cooking (jinguashi) rejected")
	station(cross_q,"jinguashi").cooking=cooking_queue(A,805)
	check(valid(cross_q.duplicate(true)),"control: distinct ids across processing and cooking accepted")
	var cross_r:=with_processing(base,"home",mixed_queue("home",820))
	station(cross_r,"lanyang").processing=mixed_queue("lanyang",824)
	check(not valid(cross_r.duplicate(true)),"duplicate id across home sawmill and lanyang kiln rejected")
	station(cross_r,"lanyang").processing=mixed_queue("lanyang",825)
	check(valid(cross_r.duplicate(true)),"control: distinct ids home/region accepted")
	# Two processors in two different non-home regions.
	var two_regions:=with_processing(base,"lanyang",mixed_queue("lanyang",840))
	station(two_regions,"jinguashi").clear()
	station(two_regions,"jinguashi").merge({"type":"sawmill","owner":A,"items":{},"input_wood":0,"auto_enabled":false,"processing":mixed_queue("home",850)})
	check(valid(two_regions.duplicate(true)),"control: processing in two regions accepted")
	station(two_regions,"jinguashi").processing=mixed_queue("home",842)
	check(not valid(two_regions.duplicate(true)),"duplicate id across lanyang and jinguashi processors rejected")
	check(not live.load_world(_write_and_path(two_regions)),"real World rejects cross-region duplicate ids")
	# Old cooking-only helper kept its exact behaviour.
	var only_proc:=with_processing(base,"home",mixed_queue("home",860))
	station(only_proc,"lanyang").processing=mixed_queue("lanyang",860)
	check(Schema.cooking_ids_unique(only_proc) and not Schema.queue_ids_unique(only_proc),"cooking_ids_unique ignores processing; queue_ids_unique covers it")

	# --- old versions carrying processing: rejected, never erased ------------------
	for version in [20,19,18,17]:
		for where in ["home","lanyang"]:
			for processing in [Queue.empty_state(),mixed_queue(where,950)]:
				var s:=with_processing(base,where,processing,version)
				if version<18:s.erase("construction")
				var copy:Dictionary=s.duplicate(true)
				check(not valid(copy),"v%d %s processing rejected"%[version,where])
				check(int(copy.version)==version,"v%d rejection did not stamp version"%version)
				check(History.canonical(station(copy,where).processing)==History.canonical(station(s,where).processing),"v%d forward processing kept for inspection, not emptied"%version)
		var v_bad:=with_processing(base,"lanyang",mixed_queue("lanyang",960),version)
		if version<18:v_bad.erase("construction")
		check(not live.load_world(_write_and_path(v_bad)),"real World rejects v%d forward processing"%version)
	var future:Dictionary=base.duplicate(true)
	future.version=Schema.VERSION+1
	check(not valid(future),"future version rejected")

	# --- v20 (and older) migration unchanged: legacy jobs preserved, lazy -----------
	for version in [20,19,18]:
		var s:Dictionary=base.duplicate(true)
		s.version=version
		if int(s.version)<25:
			s.erase("flower_nursery")
			s.regions.erase("tianwei")
			s.erase("salt_pan")
			s.regions.erase("beimen")
		if version<23:s.erase("public_kitchen")
		station(s,"home").job=legacy_job("home",NOW+5.0)
		station(s,"lanyang").auto_enabled=true
		station(s,"lanyang").input_wood=8
		station(s,"lanyang").job=legacy_job("lanyang",NOW+3.0,true)
		if version==20:station(s,"jinguashi").cooking=cooking_queue(A,970)
		var players_before:Dictionary=s.players.duplicate(true)
		var keys_before:Array=s.players[A].inventory.keys();keys_before.sort()
		check(valid(s) and int(s.version)==preload("res://scripts/save_schema.gd").VERSION,"v%d legacy processing jobs accepted -> 21"%version)
		check(same(station(s,"home").job,legacy_job("home",NOW+5.0)),"v%d manual sawmill job preserved exactly"%version)
		check(same(station(s,"lanyang").job,legacy_job("lanyang",NOW+3.0,true)) and station(s,"lanyang").auto_enabled==true and int(station(s,"lanyang").input_wood)==8,"v%d automatic kiln job/mode/buffer preserved exactly"%version)
		check(not station(s,"home").has("processing") and not station(s,"lanyang").has("processing"),"v%d legacy jobs not converted at load"%version)
		var keys_after:Array=s.players[A].inventory.keys();keys_after.sort()
		check(same(s.players[A].inventory,players_before[A].inventory) and same(s.players[B].inventory,players_before[B].inventory) and keys_after==keys_before,"v%d inventories unchanged (no recharge/refund)"%version)
		check(same(s.unrelated_future_note,{"keep":["me",1]}),"v%d unrelated state kept"%version)
		if version==20:check(same(station(s,"jinguashi").cooking,cooking_queue(A,970)),"v20 cooking queue preserved through migration")
	# Legacy validation constraints unchanged (current-recipe snapshot required).
	var legacy_hist:Dictionary=base.duplicate(true)
	legacy_hist.version=20;legacy_hist.erase("public_kitchen")
	if int(legacy_hist.version)<25:
		legacy_hist.erase("flower_nursery")
		legacy_hist.regions.erase("tianwei")
		legacy_hist.erase("salt_pan")
		legacy_hist.regions.erase("beimen")
	var bad_job:=legacy_job("home",NOW+5.0)
	bad_job.ingredients={"wood":3}
	station(legacy_hist,"home").job=bad_job
	check(not valid(legacy_hist),"legacy job with non-current ingredients still rejected as before")
	var legacy_other:Dictionary=base.duplicate(true)
	var other_job:=legacy_job("home",NOW+5.0);other_job.owner=B
	station(legacy_other,"home").job=other_job
	check(not valid(legacy_other),"legacy job owned by someone else still rejected as before")
	# Legacy job on one station, queue on another: accepted.
	var mixed:=with_processing(base,"lanyang",mixed_queue("lanyang",980))
	station(mixed,"home").job=legacy_job("home",NOW+5.0)
	check(valid(mixed),"legacy job on one station and processing queue on another accepted")
	# Real World: v20 file with legacy jobs loads unchanged and saves as 21.
	var v20:Dictionary=base.duplicate(true)
	v20.version=20;v20.erase("public_kitchen")
	if int(v20.version)<25:
		v20.erase("flower_nursery")
		v20.regions.erase("tianwei")
		v20.erase("salt_pan")
		v20.regions.erase("beimen")
	station(v20,"home").job=legacy_job("home",NOW+5.0)
	var w20=load_real(v20)
	check(w20!=null and int(w20.state.version)==preload("res://scripts/save_schema.gd").VERSION,"real World loads v20 legacy job as 21")
	if w20!=null:
		check(same(w20.state.objects[HOME_CELL].job,legacy_job("home",NOW+5.0)) and not w20.state.objects[HOME_CELL].has("processing"),"real load keeps legacy job, no processing field")
		check(w20.save(),"migrated world saves")
		var re:=World.new()
		check(re.load_world(path) and same(re.state.objects[HOME_CELL].job,legacy_job("home",NOW+5.0)),"migrated legacy job round-trips through disk")

	# --- prior migrations keep their literal cutoffs -------------------------------
	var v19c:=base.duplicate(true)
	v19c.version=19;v19c.erase("public_kitchen")
	if int(v19c.version)<25:
		v19c.erase("flower_nursery")
		v19c.regions.erase("tianwei")
		v19c.erase("salt_pan")
		v19c.regions.erase("beimen")
	station(v19c,"jinguashi").cooking=cooking_queue(A,990)
	check(not valid(v19c),"cooking cutoff unchanged: v19 cooking rejected")
	var v20c:=base.duplicate(true)
	v20c.version=20;v20c.erase("public_kitchen")
	if int(v20c.version)<25:
		v20c.erase("flower_nursery")
		v20c.regions.erase("tianwei")
		v20c.erase("salt_pan")
		v20c.regions.erase("beimen")
	station(v20c,"jinguashi").cooking=cooking_queue(A,990)
	check(valid(v20c) and int(v20c.version)==preload("res://scripts/save_schema.gd").VERSION,"v20 cooking queue migrates to 21")
	var v18:Dictionary=base.duplicate(true)
	v18.version=18;v18.erase("public_kitchen")
	if int(v18.version)<25:
		v18.erase("flower_nursery")
		v18.regions.erase("tianwei")
		v18.erase("salt_pan")
		v18.regions.erase("beimen")
	var v18_history:Dictionary=v18.construction.duplicate(true)
	check(valid(v18) and int(v18.version)==preload("res://scripts/save_schema.gd").VERSION and same(v18.construction,v18_history),"v18 undo history preserved to 21")
	var v17:Dictionary=base.duplicate(true)
	v17.version=17;v17.erase("public_kitchen")
	if int(v17.version)<25:
		v17.erase("flower_nursery")
		v17.regions.erase("tianwei")
		v17.erase("salt_pan")
		v17.regions.erase("beimen")
	check(valid(v17) and v17.construction==History.fresh(),"pre-18 cutoff unchanged: history replaced with fresh")
	var bp:Dictionary=base.duplicate(true)
	bp.construction.last[A].action="blueprint"
	bp.construction.last[A].builds=26
	var bp19:Dictionary=bp.duplicate(true);bp19.version=19;bp19.erase("public_kitchen")
	if int(bp19.version)<25:
		bp19.erase("flower_nursery")
		bp19.regions.erase("tianwei")
		bp19.erase("salt_pan")
		bp19.regions.erase("beimen")
	check(valid(bp19) and bp19.construction.last[A].action=="blueprint","v19 blueprint history migrates intact")
	var bp18:Dictionary=bp.duplicate(true);bp18.version=18;bp18.erase("public_kitchen")
	if int(bp18.version)<25:
		bp18.erase("flower_nursery")
		bp18.regions.erase("tianwei")
		bp18.erase("salt_pan")
		bp18.regions.erase("beimen")
	check(not valid(bp18),"pre-19 cutoff unchanged: v18 blueprint history rejected")
	var roofed:Dictionary=base.duplicate(true)
	roofed.roofs[World.key(FLOOR)]={"type":"roof","owner":A,"items":{},"auto":true}
	var r17:Dictionary=roofed.duplicate(true);r17.version=17;r17.erase("public_kitchen");r17.erase("construction")
	if int(r17.version)<25:
		r17.erase("flower_nursery")
		r17.regions.erase("tianwei")
		r17.erase("salt_pan")
		r17.regions.erase("beimen")
	check(valid(r17),"v17 auto roof accepted")
	var r16:Dictionary=roofed.duplicate(true);r16.version=16;r16.erase("public_kitchen");r16.erase("construction")
	if int(r16.version)<25:
		r16.erase("flower_nursery")
		r16.regions.erase("tianwei")
		r16.erase("salt_pan")
		r16.regions.erase("beimen")
	check(not valid(r16),"pre-17 cutoff unchanged: v16 auto roof rejected")

	check(not live.state.objects.get(HOME_CELL,{}).has("processing"),"live World never adopted a rejected queue")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PROCESSING_QUEUE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
