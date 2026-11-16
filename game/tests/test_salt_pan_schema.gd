extends SceneTree
## Save schema 26 (chapter 4 Beimen salt pans): fresh v26 round trip, migration
## of real older documents (v24 and v25) with every non-salt field unchanged,
## whole-file rejection of forward salt state in older saves (each with an
## accepted CONTROL), per-field corruption of salt_pan rejected without any
## partial apply to a live world, and older migration cut-offs unchanged.
##
## SEEDED FIXTURES (disclosed): documents are written by real Worlds of this run
## and then mutated in memory (version stamps, forward ids, records). The v26
## progress document seeds a finished chapter-3 flower record for A (as in
## test_flower_schema) and A's salt record / gates / lot 0 machines directly.
## Saves go to a fresh random TEMP directory that is removed afterwards.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Regions=preload("res://scripts/regions.gd")
const Cooking=preload("res://scripts/cooking_queue.gd")

const A:="tok-saltschema-alice-SECRET"
const B:="tok-saltschema-bob-SECRET"
const HOME_CROP:="30,40"
const HOME_CHEST:="31,40"
const LANYANG_CELL:="20,20"
const BOX_ID:="fedcba9876543210fedcba9876543210"

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
	dir=base.path_join("salt-schema-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	test_versions()
	test_fresh_roundtrip()
	var legacy25:=legacy_doc(25)
	var legacy24:=legacy_doc(24)
	test_migration(legacy25,"v25")
	test_migration(legacy24,"v24")
	test_forward_rejection(legacy25)
	test_forward_rejection(legacy24)
	var current:=current_doc()
	test_invariants(current)
	test_no_partial_apply(current)
	test_progress_roundtrip(current)
	test_escrow_waitlist(current)
	finish()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("SALT_PAN_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ------------------------------------------------------------------ helpers

func valid(doc:Dictionary) -> bool:
	return Schema.validate(doc,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func canon(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

## Serialized form (String keys, floats) exactly as a save file decodes.
func wire(doc:Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(doc))

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

func unlock_tea(w,token:String) -> void:
	var r:Dictionary=Tea.FRESH.duplicate(true) # FIXTURE finished chapter-2 comparison
	r.intro=true;r.potter=true;r.reused=true;r.reuse_count=1
	r.trials={"jar":true,"fiber":true};r.tea_discussed=true;r.comparison_complete=true
	w.state.tea_ceramics.players[token]=r

func salt_record(fields:Dictionary) -> Dictionary:
	var r:Dictionary={"letter":false,"intro":false,"raked":0,"wheel_raked":0,"auto_raked":0,"note":false,"order":false,"complete":false}
	r.merge(fields,true)
	return r

# ------------------------------------------------------------------ versions

func test_versions() -> void:
	expect(Schema.VERSION==26,"SaveSchema.VERSION is 26")
	expect(Schema.SALT_VERSION==26 and Salt.SAVE_VERSION==26,"SALT_VERSION literal 26 on both sides")
	expect(Schema.FLOWER_VERSION==25 and Schema.BAKERY_VERSION==24 and Schema.PUBLIC_KITCHEN_VERSION==23 and Schema.MATERIAL_SOURCE_VERSION==22,"older cut-offs unchanged")
	expect(Schema.PROCESSING_QUEUE_VERSION==21 and Schema.COOKING_QUEUE_VERSION==20 and Schema.BLUEPRINT_HISTORY_VERSION==19,"older queue/history cut-offs unchanged")
	expect(Regions.ALL.find(Salt.REGION)==Regions.ALL.find("tianwei")+1,"Beimen retains its region index after Tianwei")

# ------------------------------------------------------------------ fresh v26

func test_fresh_roundtrip() -> void:
	var w=World.new()
	w.save_path=dir.path_join("fresh-26.json")
	w.add_player(A,"Alice")
	expect(int(w.state.version)==26,"fresh world writes version 26")
	expect(w.state.get("salt_pan")==Salt.fresh(),"fresh world has SaltPan.fresh()")
	expect(w.state.regions.get(Salt.REGION)==Regions.fresh(),"fresh world has an empty beimen region")
	var doc:=doc_of(w)
	expect(int(doc.get("version",0))==26,"save file stamped 26")
	expect(valid(doc.duplicate(true)),"fresh v26 save validates")
	var again=World.new()
	expect(again.load_world(w.save_path) and not again.recovered_from_backup,"fresh v26 save loads")
	var normal:=doc.duplicate(true)
	valid(normal)
	expect(canon(again.state)==canon(normal),"fresh v26 load equals the validated document")
	expect(again.save(),"fresh v26 resaves")
	var third=World.new()
	expect(third.load_world(w.save_path) and canon(third.state)==canon(again.state),"fresh v26 save/load/save/load identical")
	var missing:=doc.duplicate(true)
	missing.erase("salt_pan")
	expect(not valid(missing),"a v26 save without salt_pan is rejected")
	var no_region:=doc.duplicate(true)
	no_region.regions.erase(Salt.REGION)
	expect(not valid(no_region),"a v26 save without the beimen region is rejected")

# ------------------------------------------------------------------ older fixtures

## A realistic older document written by a real World of this run; the salt
## additions (and for v24 also the flower additions) are removed and stamped.
func legacy_doc(version:int) -> Dictionary:
	var w=World.new()
	w.save_path=dir.path_join("legacy-source-%d.json"%version)
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	unlock_tea(w,A)
	w.state.crops[HOME_CROP]={"kind":"radish","growth":12.0,"wet":true,"owner":A,"remaining":1}
	w.state.objects[HOME_CHEST]={"type":"chest","owner":A,"items":{"wood":3}}
	w.state.regions.lanyang.objects[LANYANG_CELL]={"type":"chest","owner":B,"items":{"stone":2}}
	w.state.regions.lanyang.crops["21,20"]={"kind":"wheat","growth":0.0,"wet":false,"owner":B,"remaining":1}
	w.state.players[A].inventory.radish=4
	w.state.players[A].inventory.minnow=2
	w.state.players[B].region="yingge"
	w.state.players[B].x=13.5
	w.state.players[B].y=25.5
	w.state.players[B].travel_book.visited.maokong=true
	w.state.players[B].travel_book.visited.yingge=true
	w.state.time=500.0
	var doc:=doc_of(w)
	expect(valid(doc),"normalize existing save defaults before the v%d downgrade"%version)
	doc.erase("salt_pan")
	doc.regions.erase(Salt.REGION)
	if version<25:
		doc.erase("flower_nursery")
		doc.regions.erase(Flower.REGION)
	doc.version=version
	return doc

func test_migration(legacy:Dictionary,label:String) -> void:
	var original:=legacy.duplicate(true)
	var migrated:=legacy.duplicate(true)
	expect(valid(migrated),"clean %s save migrates"%label)
	expect(int(migrated.get("version",0))==26,"%s migrated save stamped 26"%label)
	expect(migrated.get("regions",{}).get(Salt.REGION)==Regions.fresh(),"%s: fresh beimen region added"%label)
	expect(migrated.get("salt_pan")==Salt.fresh(),"%s: fresh salt_pan added"%label)
	expect(migrated.get("regions",{}).size()==Regions.ALL.size()-1,"%s: region count matches Regions.ALL"%label)
	for field in original:
		if field=="version":continue
		if field=="regions":
			for region in original.regions:
				expect(canon(migrated.regions.get(region))==canon(original.regions[region]),"%s: old region %s unchanged"%[label,region])
			continue
		expect(canon(migrated.get(field))==canon(original[field]),"%s: old field %s unchanged"%[label,field])
	var extra:Array=migrated.keys().filter(func(k):return not original.has(k)).map(func(k):return str(k))
	extra.sort()
	var expected_extra:Array=["salt_pan"] if int(original.version)==25 else ["flower_nursery","salt_pan"]
	expect(extra==expected_extra,"%s: only %s added at the root: %s"%[label,str(expected_extra),str(extra)])
	var added_regions:Array=migrated.regions.keys().filter(func(k):return not original.regions.has(k)).map(func(k):return str(k))
	added_regions.sort()
	var expected_regions:Array=[Salt.REGION] if int(original.version)==25 else [Salt.REGION,Flower.REGION]
	expected_regions.sort()
	expect(added_regions==expected_regions,"%s: only %s regions added"%[label,str(expected_regions)])
	var path:=write_doc("legacy-%s.json"%label,legacy.duplicate(true))
	var w=World.new()
	expect(w.load_world(path) and not w.recovered_from_backup,"World loads the %s file"%label)
	expect(int(w.state.version)==26 and w.state.has("salt_pan") and w.state.regions.has(Salt.REGION),"%s world gains beimen + salt_pan"%label)
	expect(w.state.players[A].inventory.get("radish")==4 and w.state.players[A].inventory.get("minnow")==2 and w.state.crops.has(HOME_CROP) and w.state.regions.lanyang.objects.has(LANYANG_CELL),"%s: inventory, crop and regional chest kept"%label)
	expect(w.save(),"%s migrated world saves"%label)
	var again=World.new()
	expect(again.load_world(path) and canon(again.state)==canon(w.state),"%s migrated save reload identical"%label)

# ------------------------------------------------------------------ forward state

## mutate(doc, id) writes `id` into one location; the control id is accepted.
func forward_case(legacy:Dictionary,label:String,mutate:Callable,control:String,forward:Array) -> void:
	var v:=int(legacy.version)
	var ok_doc:=legacy.duplicate(true)
	mutate.call(ok_doc,control)
	expect(valid(wire(ok_doc)),"v%d control %s=%s accepted"%[v,label,control])
	for id in forward:
		var bad:=legacy.duplicate(true)
		mutate.call(bad,id)
		var before:=canon(bad)
		expect(not valid(wire(bad)),"v%d with %s=%s rejected"%[v,label,id])
		expect(canon(bad)==before,"v%d %s=%s: judging never strips the document"%[v,label,id])

func test_forward_rejection(legacy:Dictionary) -> void:
	var items:Array=Salt.ITEMS.keys()
	expect(items.size()==4 and items.has("sea_salt") and items.has("salt_grilled_fish") and items.has("salt_wheel_kit") and items.has("salt_rake_kit"),"four salt items")
	for id in items+[Salt.REGION,"salt_pan"]:
		expect(id in Salt.FORWARD_IDS,"FORWARD_IDS lists %s"%id)
	forward_case(legacy,"inventory",func(d,id):d.players[A].inventory[id]=1,"wood",items)
	forward_case(legacy,"home chest items",func(d,id):d.objects[HOME_CHEST].items[id]=1,"fiber",items)
	forward_case(legacy,"regional chest items",func(d,id):d.regions.lanyang.objects[LANYANG_CELL].items[id]=1,"fiber",items)
	forward_case(legacy,"stove job kind",func(d,id):d.objects["32,40"]={"type":"stove","owner":A,"items":{},"job":{"kind":id,"ready":520.0,"owner":A}},"soup",["salt_grilled_fish"])
	var queue:=func(d,id):
		var first=Cooking.enqueue(Cooking.empty_state(),World.RECIPES,500.0,A,"soup","b".repeat(32),World.RECIPES.soup.ingredients.duplicate())
		var second=Cooking.enqueue(first.state,World.RECIPES,500.0,A,id,"a".repeat(32),World.RECIPES[id].ingredients.duplicate())
		expect(first.ok and second.ok,"queue fixture built through CookingQueue (%s)"%id)
		d.objects["32,40"]={"type":"stove","owner":A,"items":{},"cooking":second.state}
	forward_case(legacy,"cooking queue kind",queue,"soup",["salt_grilled_fish"])
	forward_case(legacy,"collection meals",func(d,id):d.players[A].collection.meals[id]=true,"soup",["salt_grilled_fish"])
	forward_case(legacy,"chapter_one.harvests",func(d,id):d.chapter_one.harvests[A]={id:1},"radish",["sea_salt"])
	forward_case(legacy,"travel_book.visited",func(d,id):d.players[B].travel_book.visited[id]=true,"maokong",[Salt.REGION])
	forward_case(legacy,"player.region",func(d,id):d.players[B].region=id,"yingge",[Salt.REGION])
	var root_key:=func(d,id):
		if id!="":d[id]=Salt.fresh()
	forward_case(legacy,"root key",root_key,"",["salt_pan"])
	var region_key:=func(d,id):
		if id!="":d.regions[id]=Regions.fresh()
	forward_case(legacy,"regions key",region_key,"",[Salt.REGION])

# ------------------------------------------------------------------ v26 progress

func flower_done(w,token:String) -> void:
	# FIXTURE finished chapter-3 record and completed shared garden (as in
	# test_flower_schema.current_doc), so the salt letter is legal for `token`.
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for k in Flower.FLOWERS:
		a.planted[k]=true;a.harvested[k]=2;a.saved[k]=true
	w.state.flower_nursery.players[token]=a
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{token:10},"complete":true,"completed_at":550.0}
	w.state.players[token].travel_book.visited[Flower.REGION]=true

## Valid v26 document: A finished chapter 3, repaired all gates, raked by hand
## and with the wheel, holds lot 0 with wheel + rake + a configured own chest.
func current_doc() -> Dictionary:
	var w=World.new()
	w.save_path=dir.path_join("current-source.json")
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	unlock_tea(w,A)
	unlock_tea(w,B)
	w.state.time=2000.0
	flower_done(w,A)
	for t in [A]:w.state.players[t].travel_book.visited[Salt.REGION]=true
	var salt:Dictionary=w.state.salt_pan
	salt.players[A]=salt_record({"letter":true,"intro":true,"raked":3,"wheel_raked":1,"auto_raked":1})
	for g in 3:salt.gates[g]=Salt.GATE_NEEDS_EACH.duplicate(true)
	salt.givers[A]=true
	salt.repaired_at=600.0
	var chest:Vector2i=Salt.chest_sockets(0)[0]
	var chest_key:="%d,%d"%[chest.x,chest.y]
	w.state.regions[Salt.REGION].objects[chest_key]={"type":"private_chest","owner":A,"items":{"sea_salt":3},"box_id":BOX_ID}
	salt.lots[0]={"owner":A,"wheel":true,"rake":true,"chest":chest_key,"box":BOX_ID,"cap":60,"on":true}
	salt.pans[0]={"s":"brine","p":120.0,"t":1900.0,"f":"wheel"}
	salt.pans[1]={"s":"salt","p":float(Salt.NEED),"t":1950.0,"f":"wheel"}
	salt.pans[16]={"s":"brine","p":10.0,"t":1990.0,"f":"hand"}
	return doc_of(w)

func reject(current:Dictionary,label:String,mutate:Callable) -> void:
	var bad:=current.duplicate(true)
	mutate.call(bad)
	expect(not valid(wire(bad)),"v26 rejects: "+label)

func test_invariants(current:Dictionary) -> void:
	expect(valid(wire(current)),"valid v26 salt progress document accepted")
	var normal:=wire(current)
	valid(normal)
	expect(normal.salt_pan.players[A].raked is int and normal.salt_pan.lots[0].cap is int,"JSON floats normalised to int")
	reject(current,"extra root key",func(d):d.salt_pan.extra={})
	for key in ["players","gates","givers","repaired_at","pans","lots","apprentice","coop_box","kit_box","waitlist"]:
		reject(current,"missing root key "+key,func(d):d.salt_pan.erase(key))
	expect(Salt.ROOT_KEYS==["players","gates","givers","repaired_at","pans","lots","apprentice","coop_box","kit_box","waitlist"],"salt_pan root keys are exactly the 10 v26 keys")
	var root_keys:Array=current.salt_pan.keys().map(func(x):return str(x))
	root_keys.sort()
	var want_keys:Array=Salt.ROOT_KEYS.duplicate()
	want_keys.sort()
	expect(root_keys==want_keys,"v26 document salt_pan carries exactly the 10 root keys: %s"%str(root_keys))
	reject(current,"salt_pan not a dictionary",func(d):d.salt_pan=[])
	reject(current,"record extra key",func(d):d.salt_pan.players[A].extra=true)
	reject(current,"record missing key",func(d):d.salt_pan.players[A].erase("note"))
	reject(current,"record of unknown token",func(d):d.salt_pan.players["ghost-token"]=d.salt_pan.players[A].duplicate(true))
	reject(current,"letter without finished flower chapter",func(d):d.salt_pan.players[B]=salt_record({"letter":true}))
	reject(current,"intro without letter",func(d):d.salt_pan.players[A].letter=false)
	reject(current,"raked without intro",func(d):d.salt_pan.players[A].intro=false)
	reject(current,"wheel_raked above raked",func(d):d.salt_pan.players[A].wheel_raked=4)
	reject(current,"raked fractional",func(d):d.salt_pan.players[A].raked=2.5)
	reject(current,"raked negative",func(d):d.salt_pan.players[A].raked=-1)
	reject(current,"raked above LIMIT",func(d):d.salt_pan.players[A].raked=Salt.LIMIT+1)
	reject(current,"complete without order",func(d):d.salt_pan.players[A].complete=true)
	reject(current,"gates length 2",func(d):d.salt_pan.gates.pop_back())
	reject(current,"gate above need",func(d):d.salt_pan.gates[0].plank=int(Salt.GATE_NEEDS_EACH.plank)+1)
	reject(current,"gate extra material",func(d):d.salt_pan.gates[0].wood=0)
	reject(current,"repaired_at -1 with all gates full",func(d):d.salt_pan.repaired_at=-1.0)
	reject(current,"repaired_at after world time",func(d):d.salt_pan.repaired_at=2001.0)
	reject(current,"repaired while a gate is short",func(d):d.salt_pan.gates[2].stone=0)
	reject(current,"giver unknown token",func(d):d.salt_pan.givers["ghost-token"]=true)
	reject(current,"pans length 19",func(d):d.salt_pan.pans.pop_back())
	reject(current,"pan unknown state",func(d):d.salt_pan.pans[0].s="mud")
	reject(current,"brine progress above NEED",func(d):d.salt_pan.pans[0].p=float(Salt.NEED)+1.0)
	reject(current,"brine progress negative",func(d):d.salt_pan.pans[0].p=-1.0)
	reject(current,"salt below NEED",func(d):d.salt_pan.pans[1].p=10.0)
	reject(current,"empty pan with progress",func(d):d.salt_pan.pans[2]={"s":"empty","p":5.0,"t":0.0,"f":""})
	reject(current,"brine without a source",func(d):d.salt_pan.pans[0].f="")
	reject(current,"pan time after world time",func(d):d.salt_pan.pans[0].t=2001.0)
	reject(current,"pan extra key",func(d):d.salt_pan.pans[0].extra=1)
	reject(current,"lots length 9",func(d):d.salt_pan.lots.append(d.salt_pan.lots[1].duplicate(true)))
	reject(current,"lot owner unknown",func(d):d.salt_pan.lots[0].owner="ghost-token")
	reject(current,"one player owns two lots",func(d):d.salt_pan.lots[1]={"owner":A,"wheel":false,"rake":false,"chest":"","box":"","cap":60,"on":false})
	reject(current,"rake without wheel",func(d):d.salt_pan.lots[0].wheel=false)
	reject(current,"cap 1000",func(d):d.salt_pan.lots[0].cap=1000)
	reject(current,"cap below 3",func(d):d.salt_pan.lots[0].cap=2)
	reject(current,"on without chest",func(d):d.salt_pan.lots[0].chest="";d.salt_pan.lots[0].box="")
	reject(current,"chest outside the lot sockets",func(d):d.salt_pan.lots[0].chest="1,1")
	reject(current,"chest without box",func(d):d.salt_pan.lots[0].box="")
	reject(current,"box not 32 lower hex",func(d):d.salt_pan.lots[0].box="XYZ")
	reject(current,"free lot with leftover settings",func(d):d.salt_pan.lots[3].cap=61)
	reject(current,"apprentice extra key",func(d):d.salt_pan.apprentice.extra=1)
	reject(current,"apprentice tenant who also holds a private lot",func(d):d.salt_pan.apprentice.tenant=A;d.salt_pan.apprentice.since=100.0)
	reject(current,"apprentice since in the future",func(d):d.salt_pan.apprentice.tenant=A;d.salt_pan.lots[0]=Salt.fresh_lot();d.regions[Salt.REGION].objects.clear();d.salt_pan.apprentice.since=2001.0)
	var tenant_ok:=current.duplicate(true)
	tenant_ok.salt_pan.lots[0]=Salt.fresh_lot()
	tenant_ok.regions[Salt.REGION].objects.clear()
	tenant_ok.salt_pan.apprentice={"tenant":A,"since":1500.0,"wheel":true,"rake":false,"cap":60,"on":false}
	expect(valid(wire(tenant_ok)),"control: apprentice tenant without a private lot accepted")
	reject(current,"coop_box unknown token",func(d):d.salt_pan.coop_box["ghost-token"]=3)
	reject(current,"coop_box negative",func(d):d.salt_pan.coop_box[A]=-3)
	reject(current,"beimen object off a chest socket",func(d):d.regions[Salt.REGION].objects["20,20"]={"type":"chest","owner":A,"items":{}})
	reject(current,"beimen non-chest object on a socket",func(d):
		var other:Vector2i=Salt.chest_sockets(0)[1]
		d.regions[Salt.REGION].objects["%d,%d"%[other.x,other.y]]={"type":"bench","owner":A,"items":{}})
	reject(current,"beimen crop",func(d):d.regions[Salt.REGION].crops["20,20"]={"kind":"radish","growth":0.0,"wet":false,"owner":A,"remaining":1})
	reject(current,"beimen ground",func(d):d.regions[Salt.REGION].ground["20,20"]={"type":"path","owner":A,"items":{}})
	reject(current,"duplicate box_id across layers",func(d):d.objects[HOME_CHEST]={"type":"chest","owner":A,"items":{},"box_id":BOX_ID})
	# Controls right at the boundaries stay valid.
	var edge:=current.duplicate(true)
	edge.salt_pan.lots[0].cap=Salt.CAP_MIN
	expect(valid(wire(edge)),"cap exactly CAP_MIN accepted")
	edge=current.duplicate(true)
	edge.salt_pan.lots[0].cap=Salt.CAP_MAX
	expect(valid(wire(edge)),"cap exactly CAP_MAX accepted")
	edge=current.duplicate(true)
	edge.salt_pan.pans[0].t=2000.0
	expect(valid(wire(edge)),"pan time exactly world time accepted")

## Any corrupted salt field rejects the WHOLE file: the live world is untouched.
func test_no_partial_apply(current:Dictionary) -> void:
	var good_path:=write_doc("live-good.json",current.duplicate(true))
	var live=World.new()
	expect(live.load_world(good_path),"live world loads the good v26 document")
	var live_before:=canon(live.state)
	var cases:={
		"gate overfill":func(d):d.salt_pan.gates[1].stone=99,
		"lot cap 0":func(d):d.salt_pan.lots[0].cap=0,
		"pan state":func(d):d.salt_pan.pans[5].s="ice",
		"record key":func(d):d.salt_pan.players[A].bonus=1,
		"apprentice cap":func(d):d.salt_pan.apprentice.cap=-1,
	}
	for label in cases:
		var bad:=current.duplicate(true)
		cases[label].call(bad)
		var path:=write_doc("live-bad-%s.json"%label.replace(" ","-"),bad)
		var probe=World.new()
		expect(not probe.load_world(path),"corrupted file rejected: "+label)
		var loader=World.new()
		loader.load_world(good_path)
		var kept:=canon(loader.state)
		loader.load_world(path)
		expect(canon(loader.state)==kept,"no partial apply after rejection: "+label)
	expect(canon(live.state)==live_before,"live world never changed by rejected files")

func test_progress_roundtrip(current:Dictionary) -> void:
	var path:=write_doc("current-26.json",current.duplicate(true))
	var w=World.new()
	expect(w.load_world(path),"World loads the v26 salt save")
	if not w.state.has("salt_pan"):return
	var expected:=current.duplicate(true)
	valid(expected)
	expect(canon(w.state.salt_pan)==canon(expected.salt_pan),"loaded salt_pan equals the document")
	expect(w.save(),"save after load")
	var again=World.new()
	expect(again.load_world(path),"reload after save")
	expect(canon(again.state)==canon(w.state),"save/reload round trip identical")
	expect(var_to_bytes(again.state.salt_pan)==var_to_bytes(w.state.salt_pan),"salt_pan bytes identical after reload")

# ------------------------------------------------------------------ v26 escrow + waiting list

## SEEDED FIXTURE (disclosed): B gets a finished chapter-3 flower record (the
## shared garden is NOT touched), a beimen visit and one hand rake, so B is a
## legal waiting-list entry. Escrow compartments (kit_box) and the waiting list
## are written directly; their gameplay is covered by test_salt_pan_world.
func queue_doc(current:Dictionary) -> Dictionary:
	var d:Dictionary=wire(current)
	var fl:Dictionary=Flower.FRESH.duplicate(true)
	fl.letter=true;fl.intro=true;fl.shipped=true;fl.complete=true
	for k in Flower.FLOWERS:
		fl.planted[k]=true;fl.harvested[k]=2;fl.saved[k]=true
	d.flower_nursery.players[B]=fl
	d.players[B].travel_book.visited[Flower.REGION]=true
	d.players[B].travel_book.visited[Salt.REGION]=true
	d.salt_pan.players[B]=salt_record({"letter":true,"intro":true,"raked":1})
	# Station free, B heads the list (one window already missed), offered at 1990.
	d.salt_pan.kit_box={A:{"salt_wheel_kit":2,"salt_rake_kit":1},B:{"salt_wheel_kit":0,"salt_rake_kit":1}}
	d.salt_pan.waitlist={"order":[{"token":B,"missed":1}],"offer_at":1990.0}
	return wire(d)

## B holds the shift with the wheel installed; the escrow of B is at the edge
## (LIMIT-1 wheel kits) so the shift can still end.
func tenant_doc(queue:Dictionary) -> Dictionary:
	var d:Dictionary=wire(queue)
	d.salt_pan.waitlist={"order":[],"offer_at":0.0}
	d.salt_pan.apprentice={"tenant":B,"since":1500.0,"wheel":true,"rake":false,"cap":60,"on":false}
	d.salt_pan.kit_box[B]={"salt_wheel_kit":Salt.LIMIT-1,"salt_rake_kit":0}
	return wire(d)

## Non-finite numbers cannot travel through JSON; judge the in-memory document.
func reject_raw(base:Dictionary,label:String,mutate:Callable) -> void:
	var bad:Dictionary=wire(base)
	mutate.call(bad)
	expect(not valid(bad),"v26 rejects: "+label)

func test_escrow_waitlist(current:Dictionary) -> void:
	var queue:=queue_doc(current)
	var tenant:=tenant_doc(queue)
	expect(valid(wire(queue)),"control: populated escrow + waiting list (free station, head offered) accepted")
	expect(valid(wire(tenant)),"control: tenant with wheel installed and escrow at LIMIT-1 accepted")
	var edge:=wire(queue)
	edge.salt_pan.kit_box[A]={"salt_wheel_kit":Salt.LIMIT,"salt_rake_kit":Salt.LIMIT}
	expect(valid(edge),"control: escrow exactly LIMIT accepted for a non-tenant")
	edge=wire(tenant)
	edge.salt_pan.apprentice.wheel=false
	edge.salt_pan.kit_box[B].salt_wheel_kit=Salt.LIMIT
	expect(valid(edge),"control: tenant escrow at LIMIT accepted while nothing is installed")
	edge=wire(queue)
	edge.salt_pan.waitlist.offer_at=2000.0
	expect(valid(edge),"control: offer_at exactly world time accepted")
	edge=wire(queue)
	edge.salt_pan.waitlist.order[0].missed=0
	expect(valid(edge),"control: missed 0 accepted")
	edge=wire(tenant)
	edge.salt_pan.waitlist.order.append({"token":B,"missed":0})
	expect(not valid(edge),"v26 rejects: tenant also waiting in the list")
	# --- kit_box rejections
	reject(queue,"kit_box not a dictionary",func(d):d.salt_pan.kit_box=[])
	reject(queue,"kit_box unknown token",func(d):d.salt_pan.kit_box["ghost-token"]={"salt_wheel_kit":1,"salt_rake_kit":0})
	reject(current,"kit_box foreign token (player without a salt record)",func(d):d.salt_pan.kit_box[B]={"salt_wheel_kit":1,"salt_rake_kit":0})
	reject(queue,"kit_box compartment not a dictionary",func(d):d.salt_pan.kit_box[A]=3)
	reject(queue,"kit_box compartment missing a kit id",func(d):d.salt_pan.kit_box[A].erase("salt_rake_kit"))
	reject(queue,"kit_box compartment extra item",func(d):d.salt_pan.kit_box[A].sea_salt=1)
	reject(queue,"kit_box compartment foreign item instead of a kit",func(d):d.salt_pan.kit_box[A]={"salt_wheel_kit":1,"wood":1})
	reject(queue,"kit_box empty compartment",func(d):d.salt_pan.kit_box[A]={"salt_wheel_kit":0,"salt_rake_kit":0})
	reject(queue,"kit_box negative count",func(d):d.salt_pan.kit_box[A].salt_wheel_kit=-1)
	reject(queue,"kit_box fractional count",func(d):d.salt_pan.kit_box[A].salt_rake_kit=1.5)
	reject(queue,"kit_box count above LIMIT",func(d):d.salt_pan.kit_box[A].salt_wheel_kit=Salt.LIMIT+1)
	reject(queue,"kit_box count as text",func(d):d.salt_pan.kit_box[A].salt_wheel_kit="2")
	reject(queue,"kit_box count as bool",func(d):d.salt_pan.kit_box[B].salt_rake_kit=true)
	reject_raw(queue,"kit_box count NaN",func(d):d.salt_pan.kit_box[A].salt_wheel_kit=NAN)
	reject_raw(queue,"kit_box count INF",func(d):d.salt_pan.kit_box[A].salt_wheel_kit=INF)
	reject(tenant,"tenant escrow would overflow LIMIT (wheel installed, escrow LIMIT)",func(d):d.salt_pan.kit_box[B].salt_wheel_kit=Salt.LIMIT)
	reject(tenant,"tenant escrow would overflow LIMIT (rake installed, escrow LIMIT)",func(d):
		d.salt_pan.apprentice.rake=true
		d.salt_pan.kit_box[B]={"salt_wheel_kit":0,"salt_rake_kit":Salt.LIMIT})
	# --- waitlist rejections
	reject(queue,"waitlist not a dictionary",func(d):d.salt_pan.waitlist=[])
	reject(queue,"waitlist missing order",func(d):d.salt_pan.waitlist.erase("order"))
	reject(queue,"waitlist missing offer_at",func(d):d.salt_pan.waitlist.erase("offer_at"))
	reject(queue,"waitlist extra key",func(d):d.salt_pan.waitlist.extra=0)
	reject(queue,"waitlist order not an array",func(d):d.salt_pan.waitlist.order={B:0})
	reject(queue,"waitlist entry not a dictionary",func(d):d.salt_pan.waitlist.order[0]=B)
	reject(queue,"waitlist entry extra key",func(d):d.salt_pan.waitlist.order[0].since=1.0)
	reject(queue,"waitlist entry missing missed",func(d):d.salt_pan.waitlist.order[0].erase("missed"))
	reject(queue,"waitlist entry token not a string",func(d):d.salt_pan.waitlist.order[0].token=7)
	reject(queue,"waitlist entry empty token",func(d):d.salt_pan.waitlist.order[0].token="")
	reject(queue,"waitlist unknown token",func(d):d.salt_pan.waitlist.order[0].token="ghost-token")
	reject(current,"waitlist foreign token (player without a salt record)",func(d):d.salt_pan.waitlist={"order":[{"token":B,"missed":0}],"offer_at":1990.0})
	reject(queue,"waitlist duplicate token",func(d):d.salt_pan.waitlist.order.append({"token":B,"missed":0}))
	reject(queue,"waitlist lists a private lot holder",func(d):d.salt_pan.waitlist.order.append({"token":A,"missed":0}))
	reject(queue,"waitlist entry without a hand rake",func(d):d.salt_pan.players[B].raked=0)
	reject(queue,"waitlist entry that already automated",func(d):d.salt_pan.players[B].auto_raked=1)
	reject(queue,"waitlist missed 2",func(d):d.salt_pan.waitlist.order[0].missed=2)
	reject(queue,"waitlist missed negative",func(d):d.salt_pan.waitlist.order[0].missed=-1)
	reject(queue,"waitlist missed fractional",func(d):d.salt_pan.waitlist.order[0].missed=0.5)
	reject(queue,"waitlist missed bool",func(d):d.salt_pan.waitlist.order[0].missed=true)
	reject(queue,"waitlist missed text",func(d):d.salt_pan.waitlist.order[0].missed="0")
	reject(queue,"offer_at after world time",func(d):d.salt_pan.waitlist.offer_at=2001.0)
	reject(queue,"offer_at negative",func(d):d.salt_pan.waitlist.offer_at=-1.0)
	reject(queue,"offer_at as text",func(d):d.salt_pan.waitlist.offer_at="1990")
	reject_raw(queue,"offer_at NaN",func(d):d.salt_pan.waitlist.offer_at=NAN)
	reject_raw(queue,"offer_at INF",func(d):d.salt_pan.waitlist.offer_at=INF)
	reject_raw(queue,"offer_at -INF",func(d):d.salt_pan.waitlist.offer_at=-INF)
	reject(queue,"offer_at set with an empty list",func(d):d.salt_pan.waitlist.order.clear())
	reject(tenant,"offer_at set while the station is taken",func(d):d.salt_pan.waitlist.offer_at=1600.0)
	# --- whole-file rejection, no partial apply into a live world
	var good_path:=write_doc("queue-good.json",wire(queue))
	var live=World.new()
	expect(live.load_world(good_path),"live world loads the populated v26 document")
	var live_before:=canon(live.state)
	var bad_cases:={
		"kit_box ghost":func(d):d.salt_pan.kit_box["ghost-token"]={"salt_wheel_kit":1,"salt_rake_kit":0},
		"kit_box oversized":func(d):d.salt_pan.kit_box[A].salt_rake_kit=Salt.LIMIT+1,
		"waitlist duplicate":func(d):d.salt_pan.waitlist.order.append({"token":B,"missed":0}),
		"waitlist missed 2":func(d):d.salt_pan.waitlist.order[0].missed=2,
		"offer future":func(d):d.salt_pan.waitlist.offer_at=5000.0,
	}
	for label in bad_cases:
		var bad:=wire(queue)
		bad_cases[label].call(bad)
		var path:=write_doc("queue-bad-%s.json"%label.replace(" ","-"),bad)
		var loader=World.new()
		loader.load_world(good_path)
		var kept:=canon(loader.state)
		expect(not loader.load_world(path),"corrupted file rejected: "+label)
		expect(canon(loader.state)==kept,"no partial apply after rejection: "+label)
	expect(canon(live.state)==live_before,"live world never changed by rejected escrow/list files")
	# --- positive round trips through SaveSchema + World save/load
	for pair in [["queue",queue],["tenant",tenant]]:
		var label:String=pair[0]
		var doc:Dictionary=pair[1]
		var normal:=wire(doc)
		expect(valid(normal),"%s: populated document validates"%label)
		var box_a:Dictionary=normal.salt_pan.kit_box[A]
		expect(box_a.salt_wheel_kit is int and box_a.salt_rake_kit is int and normal.salt_pan.waitlist.offer_at is float,"%s: escrow counts -> int, offer_at -> float"%label)
		for entry in normal.salt_pan.waitlist.order:expect(entry.missed is int,"%s: missed -> int"%label)
		var path:=write_doc("roundtrip-%s.json"%label,wire(doc))
		var w=World.new()
		expect(w.load_world(path) and not w.recovered_from_backup,"%s: World loads the populated v26 save"%label)
		if not w.state.has("salt_pan"):continue
		expect(canon(w.state.salt_pan)==canon(normal.salt_pan),"%s: loaded salt_pan equals the validated document"%label)
		expect(w.state.salt_pan.kit_box.size()==2 and int(w.state.salt_pan.kit_box[A].salt_wheel_kit)==2,"%s: escrow survives the load"%label)
		expect(w.save(),"%s: save after load"%label)
		var again=World.new()
		expect(again.load_world(path) and not again.recovered_from_backup,"%s: reload after save"%label)
		expect(canon(again.state)==canon(w.state),"%s: save -> load identical (whole state)"%label)
		expect(var_to_bytes(again.state.salt_pan)==var_to_bytes(w.state.salt_pan),"%s: salt_pan bytes identical (types kept)"%label)
		var objects:Dictionary=again.state.regions[Salt.REGION].objects
		var own_b:Dictionary=Salt.own_view(again.state,B,objects,float(again.state.time))
		var own_a:Dictionary=Salt.own_view(again.state,A,objects,float(again.state.time))
		if label=="queue":
			expect(own_b.apprentice.kits=={"salt_wheel_kit":0,"salt_rake_kit":1} and int(own_b.apprentice.position)==1 and own_b.apprentice.queued==true and int(own_b.apprentice.waiting)==1,"queue: reloaded B sees own escrow and position 1")
			# Only lot 0 is taken here, so B may not take the shift (offer needs all 8 private lots taken).
			expect(own_b.apprentice.offer==false and int(own_b.free_lots)==7,"queue: no offer while private lots are free")
			expect(own_a.apprentice.kits=={"salt_wheel_kit":2,"salt_rake_kit":1} and int(own_a.apprentice.position)==0,"queue: reloaded A sees only own escrow")
		else:
			expect(own_b.apprentice.kits=={"salt_wheel_kit":Salt.LIMIT-1,"salt_rake_kit":0} and own_b.apprentice.mine==true,"tenant: reloaded B sees own escrow and the shift")
