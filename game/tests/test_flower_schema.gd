extends SceneTree
## Save schema 25 (chapter 3 Tianwei flower nursery): migration of version-24
## saves, whole-file rejection of forward state in older saves, every v25
## FlowerNursery invariant, and a real World save/reload round trip.
## Contract: work/flowers/implementation-contract.json schema.* and
## tests_required.test_flower_schema.gd.
##
## SEEDED FIXTURES (disclosed): documents are built from real World saves of
## this run and then mutated in memory (version stamps, forward ids, records).
## Each forward-id rejection has a CONTROL: the same mutation with an existing
## id must be accepted, so a rejection is never caused by an unrelated defect.
## Saves go to a fresh random TEMP directory that is removed afterwards.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Regions=preload("res://scripts/regions.gd")
const Cooking=preload("res://scripts/cooking_queue.gd")

const A:="tok-schema-alice-SECRET"
const B:="tok-schema-bob-SECRET"
const HOME_CROP:="30,40"
const LANYANG_CELL:="20,20"

var checks:=0
var failures:=0
var dir:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("flower-schema-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	expect(Schema.VERSION==26 and Schema.FLOWER_VERSION==25 and Schema.BAKERY_VERSION==24 and Schema.PUBLIC_KITCHEN_VERSION==23,"schema VERSION 26, FLOWER_VERSION 25, older cut-offs unchanged")
	var legacy:=legacy_doc()
	test_migration(legacy)
	test_forward_rejection(legacy)
	var current:=current_doc()
	test_invariants(current)
	test_roundtrip(current)
	finish()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("FLOWER_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ------------------------------------------------------------------ helpers

func valid(doc:Dictionary) -> bool:
	return Schema.validate(doc,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func canon(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func doc_of(w) -> Dictionary:
	expect(w.save(),"fixture world saves")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	expect(parsed is Dictionary,"fixture save parses")
	return parsed if parsed is Dictionary else {}

func write_doc(name:String,doc:Dictionary) -> String:
	var path:=dir.path_join(name)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	return path

func unlock(w,token:String) -> void:
	var r:Dictionary=Tea.FRESH.duplicate(true) # FIXTURE finished chapter-2 comparison
	r.intro=true;r.potter=true;r.reused=true;r.reuse_count=1
	r.trials={"jar":true,"fiber":true};r.tea_discussed=true;r.comparison_complete=true
	w.state.tea_ceramics.players[token]=r

## A realistic version-24 document: written by a real World of this run, then
## the two version-25 additions are removed and the version stamped 24.
func legacy_doc() -> Dictionary:
	var w=World.new()
	w.save_path=dir.path_join("legacy-source.json")
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	unlock(w,A)
	w.state.crops[HOME_CROP]={"kind":"radish","growth":12.0,"wet":true,"owner":A,"remaining":1}
	w.state.objects["31,40"]={"type":"chest","owner":A,"items":{"wood":3}}
	w.state.regions.lanyang.objects[LANYANG_CELL]={"type":"chest","owner":B,"items":{"stone":2}}
	w.state.regions.lanyang.crops["21,20"]={"kind":"wheat","growth":0.0,"wet":false,"owner":B,"remaining":1}
	w.state.players[A].inventory.radish=4
	w.state.players[B].region="yingge"
	w.state.players[B].x=13.5
	w.state.players[B].y=25.5
	w.state.players[B].travel_book.visited.maokong=true
	w.state.players[B].travel_book.visited.yingge=true
	w.state.time=500.0
	var doc:=doc_of(w)
	# Start the byte-preservation comparison from a canonical saved document.
	# Existing loaders add community/player defaults independently of flowers.
	expect(valid(doc),"normalize existing save defaults before v24 fixture downgrade")
	doc.erase("flower_nursery")
	doc.regions.erase(Flower.REGION)
	doc.erase("salt_pan")
	doc.regions.erase("beimen")
	doc.version=24
	return doc

# ------------------------------------------------------------------ migration

func test_migration(legacy:Dictionary) -> void:
	var original:=legacy.duplicate(true)
	var migrated:=legacy.duplicate(true)
	expect(valid(migrated),"clean v24 save migrates")
	expect(int(migrated.get("version",0))==Schema.VERSION,"migrated save stamped SaveSchema.VERSION")
	expect(migrated.get("regions",{}).get(Flower.REGION)==Regions.fresh(),"fresh tianwei region added")
	expect(migrated.get("flower_nursery")==Flower.fresh(),"fresh flower_nursery added")
	expect(migrated.get("regions",{}).size()==Regions.ALL.size()-1,"region count matches Regions.ALL")
	# Every old field (and every old region) is unchanged after a JSON round trip.
	for field in original:
		if field=="version":continue
		if field=="regions":
			for region in original.regions:
				expect(canon(migrated.regions.get(region))==canon(original.regions[region]),"old region %s unchanged"%region)
			continue
		expect(canon(migrated.get(field))==canon(original[field]),"old field %s unchanged"%field)
	var extra:Array=migrated.keys().filter(func(k):return not original.has(k))
	expect(extra.size()==2 and extra.map(func(x):return str(x)).has("flower_nursery") and extra.map(func(x):return str(x)).has("salt_pan"),"only flower_nursery (+ the v26 salt_pan) added at the root: %s"%str(extra))
	# Through the real World loader, then save and reload.
	var path:=write_doc("legacy-24.json",legacy.duplicate(true))
	var w=World.new()
	expect(w.load_world(path) and not w.recovered_from_backup,"World loads the v24 file")
	expect(int(w.state.version)==Schema.VERSION and w.state.has("flower_nursery") and w.state.regions.has(Flower.REGION),"loaded v24 world gains tianwei + flower_nursery")
	expect(w.state.players[A].inventory.get("radish")==4 and w.state.crops.has(HOME_CROP) and w.state.regions.lanyang.objects.has(LANYANG_CELL),"inventory, home crop and regional chest kept")
	expect(w.save(),"migrated world saves")
	var again=World.new()
	expect(again.load_world(path),"migrated save reloads")
	expect(canon(again.state)==canon(w.state),"migrated save reload is identical")

# ------------------------------------------------------------------ forward state

## mutate(doc, id) writes `id` into one location. A control id must be accepted.
func forward_case(legacy:Dictionary,label:String,mutate:Callable,control:String,forward:Array) -> void:
	var ok_doc:=legacy.duplicate(true)
	mutate.call(ok_doc,control)
	expect(valid(ok_doc),"control %s=%s accepted in v24"%[label,control])
	for id in forward:
		var bad:=legacy.duplicate(true)
		mutate.call(bad,id)
		expect(not valid(bad),"v24 with %s=%s rejected"%[label,id])
		# The same content is fine in a version-25 save where it is legal.

func test_forward_rejection(legacy:Dictionary) -> void:
	var items:Array=Flower.FORWARD_IDS.filter(func(id):return id!=Flower.REGION)
	var crops:Array=Flower.FLOWERS
	forward_case(legacy,"inventory",func(d,id):d.players[A].inventory[id]=1,"wood",items)
	forward_case(legacy,"home chest items",func(d,id):d.objects["31,40"].items[id]=1,"fiber",items)
	forward_case(legacy,"regional chest items",func(d,id):d.regions.lanyang.objects[LANYANG_CELL].items[id]=1,"fiber",items)
	forward_case(legacy,"home crop kind",func(d,id):d.crops[HOME_CROP].kind=id;d.crops[HOME_CROP].growth=0.0,"lettuce",crops)
	forward_case(legacy,"regional crop kind",func(d,id):d.regions.lanyang.crops["21,20"].kind=id,"lettuce",crops)
	forward_case(legacy,"collection crops",func(d,id):d.players[A].collection.crops[id]=true,"radish",crops)
	forward_case(legacy,"collection meals",func(d,id):d.players[A].collection.meals[id]=true,"soup",["garden_cookie"])
	forward_case(legacy,"last_seed.kind",func(d,id):d.players[A].last_seed={"at":10.0,"x":30,"y":40,"cells":[HOME_CROP],"kind":id},"radish",crops)
	forward_case(legacy,"stove job kind",func(d,id):d.objects["32,40"]={"type":"stove","owner":A,"items":{},"job":{"kind":id,"ready":520.0,"owner":A}},"soup",["garden_cookie"])
	var queue:=func(d,id):
		# Real queues cannot have waiting jobs without an active job. Construct
		# both through the production API so forward rejection has a valid control.
		var first=Cooking.enqueue(Cooking.empty_state(),World.RECIPES,500.0,A,"soup","b".repeat(32),World.RECIPES.soup.ingredients.duplicate())
		expect(first.ok,"queue fixture starts a real soup job")
		var second=Cooking.enqueue(first.state,World.RECIPES,500.0,A,id,"a".repeat(32),World.RECIPES[id].ingredients.duplicate())
		expect(second.ok,"queue fixture appends a real %s job"%id)
		d.objects["32,40"]={"type":"stove","owner":A,"items":{},"cooking":second.state}
	forward_case(legacy,"cooking queue kind",queue,"soup",["garden_cookie"])
	forward_case(legacy,"chapter_one.harvests",func(d,id):d.chapter_one.harvests[A]={id:1},"radish",crops)
	forward_case(legacy,"travel_book.visited",func(d,id):d.players[B].travel_book.visited[id]=true,"maokong",[Flower.REGION])
	forward_case(legacy,"player.region",func(d,id):d.players[B].region=id,"yingge",[Flower.REGION])
	var root_key:=func(d,id):
		if id!="":d[id]=Flower.fresh()
	forward_case(legacy,"root key",root_key,"",["flower_nursery"])
	var region_key:=func(d,id):
		if id!="":d.regions[id]=Regions.fresh()
	forward_case(legacy,"regions key",region_key,"",[Flower.REGION])
	# A v25 document may legitimately carry the same ids.
	var modern:=legacy.duplicate(true)
	modern.version=25
	modern.regions[Flower.REGION]=Regions.fresh()
	modern.flower_nursery=Flower.fresh()
	modern.players[A].inventory.sugar=2
	modern.players[A].inventory.bluebell_seed=1
	modern.players[A].collection.meals.garden_cookie=true
	# Actual save files decode object keys as String, unlike dot assignment's
	# StringName keys; validate this positive control in its serialized form.
	expect(valid(JSON.parse_string(JSON.stringify(modern))),"the same forward ids are legal at version 25")
	var missing:=legacy.duplicate(true)
	missing.version=25
	missing.regions[Flower.REGION]=Regions.fresh()
	expect(not valid(missing),"a v25 save without flower_nursery is rejected")

# ------------------------------------------------------------------ v25 invariants

## Valid version-25 document with a finished player A, an in-progress player B,
## a completed garden and Tianwei beds.
func current_doc() -> Dictionary:
	var w=World.new()
	w.save_path=dir.path_join("current-source.json")
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	unlock(w,A)
	unlock(w,B)
	w.state.time=600.0
	for t in [A,B]:w.state.players[t].travel_book.visited[Flower.REGION]=true
	w.state.players[B].region=Flower.REGION
	w.state.players[B].x=13.5
	w.state.players[B].y=25.5
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for k in Flower.FLOWERS:
		a.planted[k]=true;a.harvested[k]=2;a.saved[k]=true
	a.sugar_day=0;a.sugar_bought=2
	var b:Dictionary=Flower.FRESH.duplicate(true)
	b.letter=true;b.intro=true
	b.planted.bluebell=true;b.harvested.bluebell=2
	b.saving={"kind":"bluebell","ready":640.0}
	b.dyeing={"ready":620.0}
	w.state.flower_nursery.players[A]=a
	w.state.flower_nursery.players[B]=b
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{A:7,B:3},"complete":true,"completed_at":550.0}
	for i in 3:
		var cell:=Flower.NURSERY_BEDS.position+Vector2i(i,0)
		w.state.regions[Flower.REGION].crops[World.key(cell)]={"kind":Flower.FLOWERS[i],"growth":10.0,"wet":true,"owner":A,"remaining":1}
	w.state.regions[Flower.REGION].crops[World.key(Flower.NURSERY_BEDS.position+Vector2i(0,2))]={"kind":"","growth":0.0,"wet":false,"owner":B,"remaining":0}
	return doc_of(w)

func reject(current:Dictionary,label:String,mutate:Callable) -> void:
	var bad:=current.duplicate(true)
	mutate.call(bad)
	expect(not valid(bad),"v25 rejects: "+label)

func test_invariants(current:Dictionary) -> void:
	var control:=current.duplicate(true)
	expect(valid(control),"valid v25 flower document accepted")
	expect(control.get("flower_nursery",{}).get("players",{}).get(A,{}).get("harvested",{}).get("bluebell") is int,"JSON floats normalised to int")
	reject(current,"extra root key",func(d):d.flower_nursery.extra={})
	reject(current,"missing garden",func(d):d.flower_nursery.erase("garden"))
	reject(current,"record extra key",func(d):d.flower_nursery.players[A].extra=true)
	reject(current,"record missing key",func(d):d.flower_nursery.players[A].erase("sugar_day"))
	reject(current,"record of unknown token",func(d):d.flower_nursery.players["ghost-token"]=d.flower_nursery.players[B].duplicate(true))
	reject(current,"letter false",func(d):d.flower_nursery.players[B].letter=false)
	reject(current,"letter without tea comparison",func(d):d.tea_ceramics.players[B].comparison_complete=false;d.tea_ceramics.players[B].tea_discussed=false)
	reject(current,"intro without visiting tianwei",func(d):d.players[A].travel_book.visited.erase(Flower.REGION))
	reject(current,"planted non-flower",func(d):d.flower_nursery.players[B].planted.radish=true)
	reject(current,"planted value not true",func(d):d.flower_nursery.players[B].planted.bluebell=1)
	reject(current,"harvested zero",func(d):d.flower_nursery.players[B].harvested.bluebell=0)
	reject(current,"harvested fractional",func(d):d.flower_nursery.players[B].harvested.bluebell=1.5)
	reject(current,"harvested above LIMIT",func(d):d.flower_nursery.players[B].harvested.bluebell=Flower.LIMIT+1)
	reject(current,"harvested without planted",func(d):d.flower_nursery.players[B].harvested.chime_herb=1)
	reject(current,"saved without harvested",func(d):d.flower_nursery.players[B].saved.chime_herb=true)
	reject(current,"progress without intro",func(d):d.flower_nursery.players[B].intro=false)
	reject(current,"saving non-flower",func(d):d.flower_nursery.players[B].saving.kind="radish")
	reject(current,"saving ready beyond time+60",func(d):d.flower_nursery.players[B].saving.ready=661.0)
	reject(current,"saving extra key",func(d):d.flower_nursery.players[B].saving.extra=1)
	reject(current,"dyeing ready beyond time+30",func(d):d.flower_nursery.players[B].dyeing.ready=631.0)
	reject(current,"shipped without all saved",func(d):d.flower_nursery.players[B].shipped=true)
	reject(current,"complete without shipped",func(d):d.flower_nursery.players[A].shipped=false)
	reject(current,"complete without garden complete",func(d):d.flower_nursery.garden.given.chime_herb=1;d.flower_nursery.garden.complete=false;d.flower_nursery.garden.completed_at=-1.0;d.flower_nursery.garden.contributors[B]=2)
	reject(current,"sugar_day in the future",func(d):d.flower_nursery.players[A].sugar_day=5)
	reject(current,"sugar_day below -1",func(d):d.flower_nursery.players[A].sugar_day=-2)
	reject(current,"sugar_bought above 2",func(d):d.flower_nursery.players[A].sugar_bought=3)
	reject(current,"sugar_bought without a day",func(d):d.flower_nursery.players[A].sugar_day=-1)
	reject(current,"garden given extra key",func(d):d.flower_nursery.garden.given.sugar=0)
	reject(current,"garden given above need",func(d):d.flower_nursery.garden.given.chime_herb=3;d.flower_nursery.garden.contributors[B]=4)
	reject(current,"garden complete flag mismatch",func(d):d.flower_nursery.garden.complete=false)
	reject(current,"contributor unknown token",func(d):d.flower_nursery.garden.contributors["ghost-token"]=1;d.flower_nursery.garden.contributors[A]=6)
	reject(current,"contributor count zero",func(d):d.flower_nursery.garden.contributors[B]=0;d.flower_nursery.garden.contributors[A]=10)
	reject(current,"contributors sum mismatch",func(d):d.flower_nursery.garden.contributors[A]=8)
	reject(current,"contributor without intro",func(d):d.flower_nursery.players[B]=Flower.FRESH.duplicate(true);d.flower_nursery.players[B].letter=true;d.players[B].region="home";d.players[B].x=39.5;d.players[B].y=33.5)
	reject(current,"completed_at -1 while complete",func(d):d.flower_nursery.garden.completed_at=-1.0)
	reject(current,"completed_at after time",func(d):d.flower_nursery.garden.completed_at=601.0)
	reject(current,"incomplete garden with completed_at",func(d):d.flower_nursery.players[A].complete=false;d.flower_nursery.garden.given.chime_herb=1;d.flower_nursery.garden.complete=false;d.flower_nursery.garden.contributors[B]=2)
	reject(current,"player in tianwei without a letter record",func(d):d.flower_nursery.players.erase(B);d.flower_nursery.garden.contributors.erase(B);d.flower_nursery.garden.contributors[A]=10)
	reject(current,"7 Tianwei plots for one owner",seven_plots)
	reject(current,"non-flower crop in Tianwei",func(d):d.regions[Flower.REGION].crops[World.key(Flower.NURSERY_BEDS.position)].kind="radish")
	reject(current,"Tianwei crop without owner",func(d):d.regions[Flower.REGION].crops[World.key(Flower.NURSERY_BEDS.position)].erase("owner"))
	reject(current,"Tianwei crop outside the nursery beds",func(d):d.regions[Flower.REGION].crops[World.key(Flower.SEED_TABLE+Vector2i(0,2))]={"kind":"","growth":0.0,"wet":false,"owner":B,"remaining":0})
	# Controls next to the boundaries stay valid.
	var six:=current.duplicate(true)
	for i in 3:six.regions[Flower.REGION].crops[World.key(Flower.NURSERY_BEDS.position+Vector2i(3+i,0))]={"kind":"","growth":0.0,"wet":false,"owner":A,"remaining":0}
	expect(valid(six),"exactly 6 Tianwei plots for one owner accepted")
	var edge:=current.duplicate(true)
	edge.flower_nursery.players[B].saving.ready=660.0
	edge.flower_nursery.players[B].dyeing.ready=630.0
	expect(valid(edge),"saving/dyeing ready exactly at the window edge accepted")

func seven_plots(d:Dictionary) -> void:
	for i in 4:d.regions[Flower.REGION].crops[World.key(Flower.NURSERY_BEDS.position+Vector2i(3+i,0))]={"kind":"","growth":0.0,"wet":false,"owner":A,"remaining":0}

# ------------------------------------------------------------------ round trip

func test_roundtrip(current:Dictionary) -> void:
	var path:=write_doc("current-25.json",current.duplicate(true))
	var w=World.new()
	expect(w.load_world(path),"World loads the v25 flower save")
	if not w.state.has("flower_nursery"):return
	var expected:=current.duplicate(true)
	valid(expected)
	expect(canon(w.state.flower_nursery)==canon(expected.flower_nursery),"loaded flower_nursery equals the document")
	expect(w.save(),"save after load")
	var again=World.new()
	expect(again.load_world(path),"reload after save")
	expect(canon(again.state)==canon(w.state),"save/reload round trip identical")
	expect(again.state.flower_nursery.players[A].harvested.bluebell is int,"reloaded counters are ints")
