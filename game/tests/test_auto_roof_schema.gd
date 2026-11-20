extends SceneTree
# Save schema v17: auto-roof marker validation and hand-built v16 migration.
# Note: the v16 cases below are hand-built candidates, not genuine historical
# fixtures; real old-save migration is verified separately.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Regions=preload("res://scripts/regions.gd")
var checks:=0
var failures:=0
var path:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func write_candidate(candidate:Dictionary) -> void:
	# Each deliberately invalid primary must be tested without a valid backup
	# from the previous case silently recovering instead.
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(candidate));f.close()

func valid(candidate:Dictionary) -> bool:
	return Schema.validate(candidate,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func region_tile(region:String,skip:int=0,allow_protected:bool=false) -> String:
	if region==Regions.HOME:return "%d,30"%(30+skip)
	# Jiaoxi only permits the story bench, even on its unprotected clearing.
	if region==Regions.Springs.REGION and not allow_protected:return ""
	var found:=0
	for y in range(World.SIZE.y):
		for x in range(World.SIZE.x):
			var t:=Vector2i(x,y)
			if Regions.land(t,region) and not Regions.water(t,region) and (allow_protected or not Regions.protected(t,region)):
				if found==skip:return "%d,%d"%[x,y]
				found+=1
	return ""

func layer(candidate:Dictionary,region:String) -> Dictionary:
	return candidate if region==Regions.HOME else candidate.regions[region]

func piece(kind:String,who:String) -> Dictionary:
	return {"type":kind,"owner":who,"items":{}}

func roof(who:String,flag=null) -> Dictionary:
	var r:=piece("roof",who)
	if flag!=null:r.auto=flag
	return r

func roofs_by_region(candidate:Dictionary) -> Dictionary:
	var out:={}
	for region in [Regions.HOME]+candidate.regions.keys():out[region]=layer(candidate,region).roofs.duplicate(true)
	# v25 introduces only an empty Tianwei layer; preserve exact roof equality.
	if int(candidate.version)<25 and not out.has("tianwei"):out.tianwei={}
	if int(candidate.version)<26 and not out.has("beimen"):out.beimen={}
	# T067 deep floors load as empty layers.
	for region in Regions.DEEP_MINES:
		if not out.has(region):out[region]={}
	return out

func expect_rejected(live,candidate:Dictionary,message:String) -> void:
	write_candidate(candidate)
	var original:=FileAccess.get_file_as_string(path)
	var previous:Dictionary=live.state.duplicate(true)
	expect(not live.load_world(path),message+" rejected")
	expect(live.state==previous,message+" leaves live state untouched")
	expect(FileAccess.get_file_as_string(path)==original,message+" leaves file untouched")

func _initialize() -> void:
	path="user://auto-roof-schema-%d.json"%Time.get_ticks_usec()
	var w:=World.new()
	w.add_player("alice","阿莉")
	w.add_player("bobby","阿博")
	var base:Dictionary=w.state.duplicate(true)
	base.version=17;base.erase("public_kitchen")
	base.erase("flower_nursery")
	base.regions.erase("tianwei")
	base.erase("salt_pan")
	base.regions.erase("beimen")
	# T067 deep floors (B6–B15) cannot carry pre-current buildings.
	for region in Regions.DEEP_MINES:base.regions.erase(region)
	var home:=Regions.HOME

	# Fresh v17: auto roof paid by a player other than the floor owner, plus manual roofs.
	var fresh:Dictionary=base.duplicate(true)
	fresh.ground["30,30"]=piece("floor","alice");fresh.roofs["30,30"]=roof("bobby",true)
	fresh.ground["31,30"]=piece("floor","alice");fresh.roofs["31,30"]=roof("alice")
	fresh.ground["32,30"]=piece("floor","alice");fresh.roofs["32,30"]=roof("alice",false)
	var expected_roofs:Dictionary=fresh.roofs.duplicate(true)
	write_candidate(fresh)
	var live:=World.new()
	expect(live.load_world(path),"v17 save with auto roof loads")
	expect(int(live.state.version)==Schema.VERSION,"loaded v17 migrates to the current format")
	expect(live.state.roofs==expected_roofs,"v17 roofs load unchanged")
	expect(live.save(),"v17 world saves")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(parsed is Dictionary and int(parsed.get("version",0))==Schema.VERSION,"save output uses current schema")
	var reopened:=World.new()
	expect(reopened.load_world(path),"v17 roundtrip reloads")
	var r30:Dictionary=reopened.state.roofs.get("30,30",{})
	expect(r30.get("auto") is bool and r30.auto==true and r30.owner=="bobby","auto flag and foreign payer survive roundtrip")
	expect(not reopened.state.roofs["31,30"].has("auto"),"manual roof gains no auto flag on roundtrip")
	expect(reopened.state.roofs["32,30"].get("auto") is bool and reopened.state.roofs["32,30"].auto==false,"auto=false preserved as manual")
	expect(reopened.state.roofs.size()==3,"no roofs created on reload")
	# T067: a pre-current save may carry a deep floor only as an untouched layer.
	var empty_deep:Dictionary=base.duplicate(true);empty_deep.regions["mine_7"]=Regions.fresh()
	expect(valid(empty_deep) and empty_deep.regions.has("mine_7") and empty_deep.regions.mine_7.roofs.is_empty(),"v17 with an empty deep floor loads it as empty")
	var built_deep:Dictionary=base.duplicate(true);built_deep.regions["mine_7"]=Regions.fresh()
	built_deep.regions.mine_7.roofs["20,18"]=roof("alice")
	expect(not valid(built_deep),"v17 cannot carry buildings on a deep floor")

	# Hand-built v16: manual roofs (including unknown owner, no floor) keep identity; an
	# enclosed floor room without a roof must not gain a roof on load.
	var legacy:Dictionary=base.duplicate(true)
	legacy.version=16;legacy.erase("public_kitchen")
	legacy.roofs["33,30"]=roof("ghost_owner")
	legacy.ground["34,30"]=piece("floor","bobby");legacy.roofs["34,30"]=roof("alice")
	for x in range(39,43):
		for y in range(39,43):
			if x in [40,41] and y in [40,41]:legacy.ground["%d,%d"%[x,y]]=piece("floor","alice")
			elif x==40 and y==42:
				var door:=piece("door","alice");door.open=false;legacy.objects["%d,%d"%[x,y]]=door
			else:legacy.objects["%d,%d"%[x,y]]=piece("wall","alice")
	for region in [Regions.HOME]+base.regions.keys():
		if region==home:continue
		var t:=region_tile(region)
		if t.is_empty():continue # Protected transit maps cannot contain persisted buildings.
		layer(legacy,region).roofs[t]=roof("ghost_owner")
	var legacy_roofs:=roofs_by_region(legacy)
	write_candidate(legacy)
	var migrated:=World.new()
	expect(migrated.load_world(path),"hand-built v16 with manual roofs loads")
	expect(int(migrated.state.version)==Schema.VERSION,"v16 migrates to the current format")
	expect(roofs_by_region(migrated.state)==legacy_roofs,"v16 manual roofs keep identity in every region")
	for region in Regions.ALL:
		for roof_record in layer(migrated.state,region).roofs.values():
			expect(not roof_record.has("auto"),"no auto flag invented in "+region)
	for k in ["40,40","41,40","40,41","41,41"]:
		expect(not migrated.state.roofs.has(k),"enclosed v16 room is not auto-roofed on load "+k)
	expect(migrated.save() and World.new().load_world(path),"migrated v16 resaves and reloads")
	parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(parsed is Dictionary and int(parsed.version)==Schema.VERSION and parsed.roofs.size()==legacy.roofs.size(),"resaved v16 uses the current format with the same roof count")

	var legacy_false:Dictionary=legacy.duplicate(true)
	legacy_false.roofs["34,30"].auto=false
	expect(valid(legacy_false) and legacy_false.roofs["34,30"].auto==false,"pre-17 auto=false is preserved as manual")

	# Rejections against a live world: state and file must not change.
	var bad:Dictionary
	bad=legacy.duplicate(true);bad.roofs["34,30"].auto=true
	expect_rejected(live,bad,"pre-17 auto=true at home")
	bad=fresh.duplicate(true);bad.roofs["30,30"].auto="true"
	expect_rejected(live,bad,"string auto")
	bad=fresh.duplicate(true);bad.roofs["30,30"].auto=1
	expect_rejected(live,bad,"numeric auto")
	bad=fresh.duplicate(true);bad.roofs["30,30"].auto=0
	expect_rejected(live,bad,"numeric zero auto")
	bad=fresh.duplicate(true);bad.roofs["30,30"].auto=null
	expect_rejected(live,bad,"null auto")
	bad=fresh.duplicate(true);bad.ground.erase("30,30")
	expect_rejected(live,bad,"auto roof missing floor")
	bad=fresh.duplicate(true);bad.ground["30,30"]=piece("path","alice")
	expect_rejected(live,bad,"auto roof over path")
	bad=fresh.duplicate(true);bad.roofs["30,30"].owner="ghost_owner"
	expect_rejected(live,bad,"auto roof unknown owner")
	var control:Dictionary=fresh.duplicate(true)
	control.objects["40,40"]=piece("wall","alice")
	control.ground["35,30"]=piece("path","alice")
	expect(valid(control.duplicate(true)),"control wall/path without auto flag is valid")
	bad=fresh.duplicate(true);bad.ground["31,30"].auto=false
	expect_rejected(live,bad,"auto flag on floor")
	bad=control.duplicate(true);bad.objects["40,40"].auto=true
	expect_rejected(live,bad,"auto flag on wall object")
	bad=control.duplicate(true);bad.ground["35,30"].auto=true
	expect_rejected(live,bad,"auto flag on path")
	expect(live.state.roofs==expected_roofs and int(live.state.version)==preload("res://scripts/save_schema.gd").VERSION,"live world still holds original roof contents")

	# Unrelated objects: manual v17 roof with unknown owner and no floor keeps old semantics.
	var manual_unknown:Dictionary=fresh.duplicate(true)
	manual_unknown.roofs["36,30"]=roof("ghost_owner")
	expect(valid(manual_unknown),"v17 manual roof with unknown owner and no floor stays valid")

	var clearing:=Regions.Springs.BENCH_CLEARING
	var bench_tile:=Vector2i(-1,-1)
	for y in range(clearing.position.y,clearing.end.y):
		for x in range(clearing.position.x,clearing.end.x):
			var candidate:=Vector2i(x,y)
			if Regions.land(candidate,Regions.Springs.REGION) and not Regions.protected(candidate,Regions.Springs.REGION):
				bench_tile=candidate
				break
		if bench_tile.x>=0:break
	expect(bench_tile.x>=0,"Jiaoxi has an unprotected story bench tile")
	if bench_tile.x>=0:
		var restricted:Dictionary=base.duplicate(true)
		layer(restricted,Regions.Springs.REGION).roofs[World.key(bench_tile)]=roof("alice")
		expect(not valid(restricted),"Jiaoxi still refuses a manual roof in the story bench clearing")

	# Every region layer: offline payer (persistent but elsewhere) accepted; global players used.
	# Use regions present in the v17 fixture; Tianwei is introduced in v25.
	for region in [Regions.HOME]+base.regions.keys():
		var t:=region_tile(region,1)
		if t.is_empty():
			var protected_tile:=region_tile(region,0,true)
			expect(not protected_tile.is_empty(),"protected region has land for rejection fixture")
			var protected_house:Dictionary=base.duplicate(true)
			layer(protected_house,region).ground[protected_tile]=piece("floor","alice")
			layer(protected_house,region).roofs[protected_tile]=roof("bobby",true)
			expect(not valid(protected_house),"protected transit map still rejects buildings: "+region)
			continue
		var c:Dictionary=base.duplicate(true)
		layer(c,region).ground[t]=piece("floor","alice")
		layer(c,region).roofs[t]=roof("bobby",true)
		expect(valid(c) and layer(c,region).roofs[t].auto==true,"auto roof with offline payer valid in "+region)
		var cross:Dictionary=base.duplicate(true)
		if region!=home:
			layer(cross,region).roofs[t]=roof("bobby",true)
			cross.ground[t]=piece("floor","alice")
		else:
			var lt:=region_tile(Regions.LANYANG,1)
			cross.roofs[lt]=roof("bobby",true)
			cross.regions[Regions.LANYANG].ground[lt]=piece("floor","alice")
		expect(not valid(cross),"floor in another layer does not satisfy "+region)
		var ghost:Dictionary=base.duplicate(true)
		layer(ghost,region).ground[t]=piece("floor","alice")
		layer(ghost,region).roofs[t]=roof("ghost_owner",true)
		expect(not valid(ghost),"unknown payer rejected in "+region)
		var old:Dictionary=base.duplicate(true);old.version=16;old.erase("public_kitchen")
		layer(old,region).ground[t]=piece("floor","alice")
		layer(old,region).roofs[t]=roof("bobby",true)
		expect(not valid(old),"pre-17 auto=true rejected in "+region)
		var strange:Dictionary=base.duplicate(true)
		layer(strange,region).ground[t]=piece("floor","alice")
		layer(strange,region).roofs[t]=roof("bobby","yes")
		expect(not valid(strange),"non-bool auto rejected in "+region)
		var manual:Dictionary=base.duplicate(true)
		layer(manual,region).roofs[t]=roof("ghost_owner")
		expect(valid(manual),"manual unknown-owner roof unchanged in "+region)

	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("AUTO_ROOF_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
