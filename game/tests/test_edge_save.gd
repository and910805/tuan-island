extends SceneTree
## Save schema 27 (C02-C04 persistent edge layer): fresh world shape, legacy
## migration (v26 and v25 documents gain empty edge layers, every old tile object
## kept byte-identical, an older save carrying edge rows is rejected), strict key / row
## / owner / door-flag validation on the home layer and on every region, JSON
## round trip through SaveSchema and World save/load, and no partial apply when a
## corrupted file is rejected.
##
## SEEDED FIXTURES (disclosed): documents are written by real Worlds of this run
## and then mutated in memory (version stamps, removed layers, edge rows). Saves go
## to a fresh random TEMP directory that is removed afterwards.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Regions=preload("res://scripts/regions.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Session=preload("res://scripts/session.gd")

const A:="tok-edgesave-alice-SECRET"
const B:="tok-edgesave-bob-SECRET"
const HOME_CROP:="30,40"
const HOME_CHEST:="31,40"
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
	dir=base.path_join("edge-save-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	test_versions()
	var current:=current_doc()
	test_fresh_world(current)
	test_migration(legacy_doc(26),"v26")
	test_migration(legacy_doc(25),"v25")
	test_version_26_deep_mine()
	test_legacy_carrying_edges(legacy_doc(26))
	test_legacy_carrying_edges(legacy_doc(25))
	test_keys(current)
	test_rows(current)
	test_regions(current)
	test_roundtrip(current)
	test_no_partial_apply(current)
	test_live_projection_and_movement()
	finish()

func test_live_projection_and_movement() -> void:
	var world:=World.new()
	world.add_player(A,"阿青")
	world.add_player(B,"阿木")
	var start:=Vector2.ZERO
	for y in range(15,42):
		for x in range(12,64):
			var candidate:=Vector2(x+0.5,y+0.5)
			if world.can_stand(candidate) and world.can_stand(candidate+Vector2(2,0)):
				start=candidate
				break
		if start!=Vector2.ZERO:break
	expect(start!=Vector2.ZERO,"passable home movement fixture")
	if start==Vector2.ZERO:return
	var edge:=World.key(Vector2i(start)+Vector2i.RIGHT)+",W"
	world.state.edges[edge]={"type":"edge_door","owner":A,"open":false}
	world.state.regions.lanyang.edges["26,20,N"]={"type":"edge_window","owner":B}
	var player:Dictionary=world.state.players[A]
	player.x=start.x
	player.y=start.y
	world.move_player(A,Vector2.RIGHT,2.0/3.6)
	expect(is_equal_approx(float(player.x),start.x),"authoritative movement cannot cross a closed edge even in a large step")
	expect(not world.can_stand(start+Vector2(0.5,0)),"standing on the line overlaps the closed door")
	world.state.edges[edge].open=true
	world.move_player(A,Vector2.RIGHT,2.0/3.6)
	expect(is_equal_approx(float(player.x),start.x+2.0),"authoritative movement crosses an open door")
	var session:=Session.new()
	session.world=world
	var home:=session.public_state(Regions.HOME,A)
	var lanyang:=session.public_state(Regions.LANYANG,B)
	expect(home.edges.has(edge) and not home.edges.has("26,20,N"),"home gets only home edges")
	expect(lanyang.edges.has("26,20,N") and not lanyang.edges.has(edge),"Lanyang gets only its own edges")
	expect(home.edges[edge].owner==A.sha256_text().left(16) and lanyang.edges["26,20,N"].owner==B.sha256_text().left(16),"edge owner tokens are projected to public IDs")
	expect(world.state.edges[edge].owner==A and world.state.regions.lanyang.edges["26,20,N"].owner==B,"snapshot does not mutate persisted owners")
	session.free()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("EDGE_SAVE_TESTS checks=%d failures=%d"%[checks,failures])
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

func wall(token:String=A) -> Dictionary:
	return {"type":"edge_wall","owner":token}

func window(token:String=A) -> Dictionary:
	return {"type":"edge_window","owner":token}

func door(open:bool,token:String=A) -> Dictionary:
	return {"type":"edge_door","owner":token,"open":open}

func world_with_tiles():
	var w=World.new()
	w.save_path=dir.path_join("source-%d.json"%Time.get_ticks_usec())
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	w.state.crops[HOME_CROP]={"kind":"radish","growth":12.0,"wet":true,"owner":A,"remaining":1}
	w.state.objects[HOME_CHEST]={"type":"chest","owner":A,"items":{"wood":3}}
	w.state.regions.lanyang.objects[LANYANG_CELL]={"type":"chest","owner":B,"items":{"stone":2}}
	w.state.regions.lanyang.crops["21,20"]={"kind":"wheat","growth":0.0,"wet":false,"owner":B,"remaining":1}
	w.state.players[A].inventory.radish=4
	w.state.time=500.0
	return w

## Valid current-version document with edge rows on the home layer and Lanyang.
func current_doc() -> Dictionary:
	var doc:=doc_of(world_with_tiles())
	doc.edges={"30,40,N":wall(),"30,40,W":door(false),"31,40,W":window(B),"0,0,N":wall(),"0,60,N":wall(),"80,59,W":door(true,B)}
	doc.regions.lanyang.edges={"20,20,N":wall(B),"21,20,W":door(true)}
	return doc

func reject(current:Dictionary,label:String,mutate:Callable) -> void:
	var bad:=current.duplicate(true)
	mutate.call(bad)
	expect(not valid(wire(bad)),"v27 rejects: "+label)

## Same, on the in-memory document (non-JSON values such as int keys).
func reject_raw(current:Dictionary,label:String,mutate:Callable) -> void:
	var bad:=wire(current)
	mutate.call(bad)
	expect(not valid(bad),"v27 rejects (raw): "+label)

# ------------------------------------------------------------------ versions

func test_versions() -> void:
	expect(Schema.VERSION==27,"SaveSchema.VERSION is 27")
	expect(Schema.EDGE_VERSION==27,"EDGE_VERSION literal 27")
	expect(Schema.SALT_VERSION==26 and Schema.FLOWER_VERSION==25 and Schema.BAKERY_VERSION==24,"older cut-offs unchanged")
	expect(Schema.EDGE_TYPES==["edge_wall","edge_door","edge_window"],"three edge types")
	expect(Regions.LAYERS.has("edges"),"Regions.LAYERS carries edges")

# ------------------------------------------------------------------ fresh world

func test_fresh_world(current:Dictionary) -> void:
	var w=World.new()
	w.save_path=dir.path_join("fresh-27.json")
	w.add_player(A,"Alice")
	expect(int(w.state.version)==27,"fresh world version 27")
	expect(w.state.get("edges")=={},"fresh world has top-level edges {}")
	for region in Regions.ALL:
		if region==Regions.HOME:continue
		expect(w.state.regions[region].get("edges")=={},"fresh region %s has edges {}"%region)
		expect(w.state.regions[region]==Regions.fresh(),"fresh region %s equals Regions.fresh()"%region)
	var doc:=doc_of(w)
	expect(valid(doc.duplicate(true)),"fresh v27 save validates")
	var missing:=doc.duplicate(true)
	missing.erase("edges")
	expect(not valid(missing),"a v27 save without top-level edges is rejected")
	for region in doc.regions:
		var no_layer:=doc.duplicate(true)
		no_layer.regions[region].erase("edges")
		expect(not valid(no_layer),"a v27 save without edges in %s is rejected"%region)
		var not_dict:=doc.duplicate(true)
		not_dict.regions[region].edges=[]
		expect(not valid(not_dict),"a v27 save with non-dictionary edges in %s is rejected"%region)
	for bad in [[],"",null,0,true]:
		var broken:=doc.duplicate(true)
		broken.edges=bad
		expect(not valid(broken),"top-level edges %s rejected"%str(bad))
	expect(valid(wire(current)),"populated v27 document accepted")

# ------------------------------------------------------------------ legacy

## Real older document: edge layers removed everywhere; for v25 also the salt additions.
func legacy_doc(version:int) -> Dictionary:
	var doc:=doc_of(world_with_tiles())
	doc.erase("edges")
	for region in doc.regions:doc.regions[region].erase("edges")
	if version<26:
		doc.erase("salt_pan")
		doc.regions.erase(Salt.REGION)
	doc.version=version
	return doc

func test_migration(legacy:Dictionary,label:String) -> void:
	var original:=legacy.duplicate(true)
	var migrated:=legacy.duplicate(true)
	expect(valid(migrated),"clean %s save migrates"%label)
	expect(int(migrated.get("version",0))==27,"%s migrated save stamped 27"%label)
	expect(migrated.get("edges")=={},"%s: empty top-level edges added"%label)
	expect(migrated.regions.size()==Regions.ALL.size()-1,"%s: region count matches Regions.ALL"%label)
	for region in migrated.regions:
		expect(migrated.regions[region].get("edges")=={},"%s: region %s gained empty edges"%[label,region])
		expect(migrated.regions[region].size()==Regions.LAYERS.size(),"%s: region %s has exactly the layer fields"%[label,region])
	for field in original:
		if field in ["version","regions","salt_pan","players"]:continue
		expect(canon(migrated.get(field))==canon(original[field]),"%s: old field %s unchanged"%[label,field])
	var normalized:=wire(legacy)
	normalized.version=Schema.VERSION
	normalized.edges={}
	for region in normalized.regions:normalized.regions[region].edges={}
	if not normalized.regions.has(Regions.BEIMEN):normalized.regions[Regions.BEIMEN]=Regions.fresh()
	if not normalized.has("salt_pan"):normalized.salt_pan=Salt.fresh()
	expect(valid(normalized) and canon(migrated.players)==canon(normalized.players),"%s: legacy players match normal save normalization"%label)
	for region in original.regions:
		var kept:Dictionary=migrated.regions[region].duplicate(true)
		kept.erase("edges")
		expect(canon(kept)==canon(original.regions[region]),"%s: old region %s unchanged except edges"%[label,region])
	expect(canon(migrated.objects.get(HOME_CHEST))==canon(original.objects.get(HOME_CHEST)) and migrated.crops.has(HOME_CROP),"%s: old home tile objects kept"%label)
	expect(migrated.regions.lanyang.objects.has(LANYANG_CELL) and migrated.regions.lanyang.crops.has("21,20"),"%s: old lanyang tile objects kept"%label)
	var path:=write_doc("legacy-%s.json"%label,legacy.duplicate(true))
	var w=World.new()
	expect(w.load_world(path) and not w.recovered_from_backup,"World loads the %s file"%label)
	expect(int(w.state.version)==27 and w.state.edges=={} and w.state.regions.lanyang.edges=={},"%s world gains empty edge layers"%label)
	expect(w.state.players[A].inventory.get("radish")==4 and w.state.crops.has(HOME_CROP) and w.state.regions.lanyang.objects.has(LANYANG_CELL),"%s: inventory, crop and regional chest kept"%label)
	expect(w.save(),"%s migrated world saves"%label)
	var again=World.new()
	expect(again.load_world(path) and canon(again.state)==canon(w.state),"%s migrated save reload identical"%label)

func test_version_26_deep_mine() -> void:
	var old:=legacy_doc(26)
	var region:="mine_6"
	var mine_tile:=""
	for y in World.SIZE.y:
		for x in World.SIZE.x:
			var tile:=Vector2i(x,y)
			if not Regions.land(tile,region):continue
			mine_tile=World.key(tile)
			break
		if not mine_tile.is_empty():break
	if mine_tile.is_empty():
		expect(false,"fixture uses an actual floor on mine B6")
		return
	old.mine_depths.unlocked=6
	old.mine_depths.hoist=true
	old.mine_depths.pumped=24
	old.regions[region].removed[mine_tile]=true
	old.regions[region].next_network_check=1.0
	var found:=valid(old)
	expect(found and old.regions[region].removed.get(mine_tile,false) and old.regions[region].next_network_check==1.0,"v26 migration preserves existing deep mine terrain and ticking state")

func test_legacy_carrying_edges(legacy:Dictionary) -> void:
	var v:=int(legacy.version)
	var top:=legacy.duplicate(true)
	top.edges={}
	expect(valid(wire(top)),"v%d carrying an empty top-level placeholder still migrates"%v)
	var top_row:=legacy.duplicate(true)
	top_row.edges={"30,40,N":wall()}
	expect(not valid(wire(top_row)),"v%d carrying a top-level edge row is rejected"%v)
	for region in legacy.regions:
		var bad:=legacy.duplicate(true)
		bad.regions[region].edges={"30,40,N":wall()}
		var before:=canon(bad)
		expect(not valid(wire(bad)),"v%d carrying edges in region %s is rejected"%[v,region])
		expect(canon(bad)==before,"v%d region %s: judging never strips the document"%[v,region])
	var bad_layer:=legacy.duplicate(true)
	bad_layer.regions.lanyang=[]
	expect(not valid(wire(bad_layer)),"v%d non-dictionary region layer rejected"%v)

# ------------------------------------------------------------------ keys

func test_keys(current:Dictionary) -> void:
	var good:Array=["0,0,N","0,0,W","79,59,N","79,59,W","0,60,N","80,0,W","80,59,W","79,60,N","12,34,N"]
	for key in good:
		var doc:=current.duplicate(true)
		doc.edges={key:wall()}
		expect(valid(wire(doc)),"canonical key accepted: %s"%key)
	var bad:Array=["","0,0","0,0,S","0,0,E","0,0,n","0,0,w","1,2,N,","-1,0,N","0,-1,W","+1,0,N","01,2,N","1,02,N"," 1,2,N","1,2,N ","1, 2,N","1.0,2,N","a,b,N","1,2",
		"80,0,N","0,60,W","81,0,W","0,61,N","80,60,N","80,60,W","1000000,0,N","1,2,N\n","0,0,NW","30,40","30,40,N,N","30,40,,N"]
	for key in bad:
		reject(current,"home key %s"%key.c_escape(),func(d):d.edges={key:wall()})
		reject(current,"region key %s"%key.c_escape(),func(d):d.regions.lanyang.edges={key:wall()})
	reject_raw(current,"int key",func(d):d.edges={5:wall()})
	reject_raw(current,"Vector2i key",func(d):d.edges={Vector2i(1,2):wall()})
	reject_raw(current,"StringName key",func(d):d.edges={&"1,2,N":wall()})
	reject_raw(current,"bad key beside good ones",func(d):d.edges["9,9,S"]=wall())
	# Everything real stays accepted together: the whole rim plus a full row.
	var many:={}
	for x in World.SIZE.x:
		many["%d,0,N"%x]=wall()
		many["%d,%d,N"%[x,World.SIZE.y]]=window()
	for y in World.SIZE.y:
		many["0,%d,W"%y]=door(false)
		many["%d,%d,W"%[World.SIZE.x,y]]=door(true,B)
	var doc:=current.duplicate(true)
	doc.edges=many
	expect(valid(wire(doc)),"full rim of %d edges accepted"%many.size())
	expect(many.size()<=2*World.SIZE.x*World.SIZE.y+World.SIZE.x+World.SIZE.y,"fixture within the 2*area+width+height bound")

# ------------------------------------------------------------------ rows

func test_rows(current:Dictionary) -> void:
	var key:="30,41,N"
	var cases:={
		"row not a dictionary":func(d):d.edges[key]="edge_wall",
		"row null":func(d):d.edges[key]=null,
		"row array":func(d):d.edges[key]=["edge_wall",A],
		"empty row":func(d):d.edges[key]={},
		"missing type":func(d):d.edges[key]={"owner":A},
		"missing owner":func(d):d.edges[key]={"type":"edge_wall"},
		"unknown type":func(d):d.edges[key]={"type":"edge_fence","owner":A},
		"tile type wall":func(d):d.edges[key]={"type":"wall","owner":A},
		"tile type door":func(d):d.edges[key]={"type":"door","owner":A,"open":false},
		"type number":func(d):d.edges[key]={"type":1,"owner":A},
		"type null":func(d):d.edges[key]={"type":null,"owner":A},
		"type uppercase":func(d):d.edges[key]={"type":"EDGE_WALL","owner":A},
		"owner empty":func(d):d.edges[key]={"type":"edge_wall","owner":""},
		"owner unknown token":func(d):d.edges[key]={"type":"edge_wall","owner":"ghost-token"},
		"owner number":func(d):d.edges[key]={"type":"edge_wall","owner":7},
		"owner null":func(d):d.edges[key]={"type":"edge_wall","owner":null},
		"owner array":func(d):d.edges[key]={"type":"edge_wall","owner":[A]},
		"owner too long":func(d):d.edges[key]={"type":"edge_wall","owner":"x".repeat(65)},
		"owner padded":func(d):d.edges[key]={"type":"edge_wall","owner":A+" "},
		"owner wrong case":func(d):d.edges[key]={"type":"edge_wall","owner":A.to_upper()},
		"wall extra key":func(d):d.edges[key]={"type":"edge_wall","owner":A,"hp":3},
		"window extra key":func(d):d.edges[key]={"type":"edge_window","owner":A,"hp":3},
		"door extra key":func(d):d.edges[key]={"type":"edge_door","owner":A,"open":false,"hp":3},
		"wall with open true":func(d):d.edges[key]={"type":"edge_wall","owner":A,"open":true},
		"wall with open false":func(d):d.edges[key]={"type":"edge_wall","owner":A,"open":false},
		"window with open true":func(d):d.edges[key]={"type":"edge_window","owner":A,"open":true},
		"window with open false":func(d):d.edges[key]={"type":"edge_window","owner":A,"open":false},
		"door without open":func(d):d.edges[key]={"type":"edge_door","owner":A},
		"door open number":func(d):d.edges[key]={"type":"edge_door","owner":A,"open":1},
		"door open zero":func(d):d.edges[key]={"type":"edge_door","owner":A,"open":0},
		"door open text":func(d):d.edges[key]={"type":"edge_door","owner":A,"open":"true"},
		"door open null":func(d):d.edges[key]={"type":"edge_door","owner":A,"open":null},
	}
	for label in cases:
		reject(current,label,cases[label])
		reject(current,label+" (region)",func(d):
			d.regions.lanyang.edges[key]={}
			cases[label].call(d)
			d.regions.lanyang.edges[key]=d.edges[key]
			d.edges.erase(key))
	# Controls: each of the three shapes accepted, both door states.
	for row in [wall(),window(),door(true),door(false),wall(B),door(true,B)]:
		var doc:=current.duplicate(true)
		doc.edges[key]=row
		expect(valid(wire(doc)),"row accepted: %s"%JSON.stringify(row))
	# JSON normalisation keeps booleans boolean after validation.
	var normal:=wire(current)
	expect(valid(normal),"populated document validates")
	expect(normal.edges["30,40,W"].open is bool and normal.edges["80,59,W"].open==true and normal.regions.lanyang.edges["21,20,W"].open is bool,"door flags stay bool after validation")

# ------------------------------------------------------------------ regions

func test_regions(current:Dictionary) -> void:
	var every:Array=[]
	for region in Regions.ALL:
		if region!=Regions.HOME:every.append(region)
	expect(every.size()==Regions.ALL.size()-1 and every.size()==current.regions.size(),"every non-home region exercised (%d)"%every.size())
	for region in every:
		var doc:=current.duplicate(true)
		expect(doc.regions.has(region),"fixture has region %s"%region)
		doc.regions[region].edges={"5,5,N":wall(),"5,5,W":door(false,B)}
		if region==Regions.Cart.REGION:
			expect(valid(wire(current)) and not valid(wire(doc)),"The temporary cart gallery rejects even well-formed permanent walls")
		else:
			expect(valid(wire(doc)),"valid edges accepted in region %s"%region)
		reject(current,"bad key in region %s"%region,func(d):d.regions[region].edges={"5,5,S":wall()})
		reject(current,"bad owner in region %s"%region,func(d):d.regions[region].edges={"5,5,N":wall("ghost-token")})
		reject(current,"door without flag in region %s"%region,func(d):d.regions[region].edges={"5,5,N":{"type":"edge_door","owner":A}})
		reject(current,"wall with flag in region %s"%region,func(d):d.regions[region].edges={"5,5,N":{"type":"edge_wall","owner":A,"open":false}})
		reject(current,"missing layer in region %s"%region,func(d):d.regions[region].erase("edges"))
		reject(current,"non-dictionary layer in region %s"%region,func(d):d.regions[region].edges=[wall()])
	# Layers are independent: the same key may live in home and in a region.
	var twin:=current.duplicate(true)
	twin.edges["7,7,N"]=wall()
	twin.regions.lanyang.edges["7,7,N"]=door(true,B)
	expect(valid(wire(twin)),"same key in two layers accepted")
	# An unknown extra layer field is still refused by the existing exact layer size.
	reject(current,"extra region layer field",func(d):d.regions.lanyang.extra_edges={})

# ------------------------------------------------------------------ round trip

func test_roundtrip(current:Dictionary) -> void:
	var normal:=wire(current)
	expect(valid(normal),"round-trip fixture validates")
	var again:=wire(normal)
	expect(canon(again.edges)==canon(normal.edges) and canon(again.regions.lanyang.edges)==canon(normal.regions.lanyang.edges),"JSON stringify/parse keeps edge layers")
	expect(valid(again) and canon(again)==canon(normal),"validated document is a fixed point of validate")
	var path:=write_doc("current-27.json",current.duplicate(true))
	var w=World.new()
	expect(w.load_world(path) and not w.recovered_from_backup,"World loads the v27 edge save")
	if not w.state.has("edges"):return
	expect(canon(w.state.edges)==canon(normal.edges),"loaded home edges equal the document")
	expect(canon(w.state.regions.lanyang.edges)==canon(normal.regions.lanyang.edges),"loaded lanyang edges equal the document")
	expect(w.state.edges["30,40,W"].open==false and w.state.edges["80,59,W"].open==true,"door open flags survive the load")
	expect(w.state.edges["30,40,N"]==wall() and w.state.edges["31,40,W"]==window(B),"wall/window rows survive the load")
	expect(w.save(),"save after load")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	expect(saved is Dictionary and int(saved.get("version",0))==27 and canon(saved.get("edges"))==canon(normal.edges),"saved file carries the edge layer at version 27")
	var second=World.new()
	second.save_path=w.save_path
	expect(second.load_world(w.save_path) and not second.recovered_from_backup,"reload after save")
	expect(canon(second.state)==canon(w.state),"save/reload round trip identical (whole state)")
	expect(var_to_bytes(second.state.edges)==var_to_bytes(w.state.edges),"home edges bytes identical after reload")
	expect(var_to_bytes(second.state.regions.lanyang.edges)==var_to_bytes(w.state.regions.lanyang.edges),"lanyang edges bytes identical after reload")

# ------------------------------------------------------------------ no partial apply

func test_no_partial_apply(current:Dictionary) -> void:
	var good_path:=write_doc("live-good.json",current.duplicate(true))
	var live=World.new()
	expect(live.load_world(good_path),"live world loads the good v27 document")
	var live_before:=canon(live.state)
	var cases:={
		"bad key":func(d):d.edges["1,2,S"]=wall(),
		"bad type":func(d):d.edges["30,40,N"].type="edge_fence",
		"bad owner":func(d):d.edges["30,40,N"].owner="ghost-token",
		"door flag":func(d):d.edges["30,40,W"].erase("open"),
		"wall flag":func(d):d.edges["30,40,N"].open=false,
		"region key":func(d):d.regions.lanyang.edges["x,y,N"]=wall(),
		"region owner":func(d):d.regions.lanyang.edges["20,20,N"].owner="",
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
