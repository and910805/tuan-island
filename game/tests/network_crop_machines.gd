extends "res://tests/network_flower_seed_table.gd"

const MACHINES := {"alpha":Vector2i(40,36),"beta":Vector2i(44,36)}
const PLOTS := {"alpha":Vector2i(41,37),"beta":Vector2i(43,37)}
const PRODUCTS := {"alpha":"radish","beta":"lettuce"}
const WORK_STAND := Vector2(42.5,37.5)

func test_phase()->String:
	return "crop-machines"

func host_fixture(port:int)->void:
	var save_path:=handoff.path_join("world.json")
	var world:=World.new()
	world.save_path=save_path
	world.state.time=480.0
	for who in PRODUCTS:
		var token:String=tokens[who]
		var kind:String=PRODUCTS[who]
		world.add_player(token,who)
		var person:Dictionary=world.state.players[token]
		person.x=WORK_STAND.x
		person.y=WORK_STAND.y
		person.harvests=10
		person.inventory={kind:int(World.CROPS[kind].yield),"wood":15,"copper_ingot":4,"woodwork_parts":2,"charcoal":1,"tomato_seed":1,"glass":2,"copper_joint":1}
		for cell:Vector2i in [MACHINES[who],PLOTS[who]]:
			world.state.removed[World.key(cell)]=true
	if not check(world.can_stand(WORK_STAND) and world.save(),"isolated spring fixture with seeds, crops and building materials"):return
	var island:=Node.new()
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	var code:=session.host(port,"QA",save_path,OS.get_environment("FN_ROOM_KEY"),"127.0.0.1",true,"websocket")
	if not check(code==OK,"dedicated session loaded fixture (%d)"%code):return
	print("SEED_TABLE_SERVER_READY")
	var advance_path:=handoff.path_join("advance")
	if not await until(func():return FileAccess.file_exists(advance_path),20):
		finish(false,"clients did not reach clock barrier")
		return
	for who in PRODUCTS:
		var device:Dictionary=session.world.state.objects[k(MACHINES[who])]
		if not check(device.owner==tokens[who] and not device.processing.active.is_empty(),"independent active seed job for "+who):return
	if not check(session.world.step(float(World.CROPS.tomato.time)+1.0,true),"advanced spring crop and machine timers"):return
	print("SEED_TABLE_CLOCK_ADVANCED")
	var done_path:=handoff.path_join("done")
	if not await until(func():return FileAccess.file_exists(done_path),12):
		finish(false,"clients did not complete")
		return
	if not check(session.shutdown(),"server saved and shut down normally"):return
	session=null
	var loaded:=World.new()
	if not check(loaded.load_world(save_path) and not loaded.recovered_from_backup,"reopened final primary save"):return
	for who in PRODUCTS:
		var person:Dictionary=loaded.state.players[tokens[who]]
		var crop:Dictionary=loaded.state.crops[k(PLOTS[who])]
		var roof:Dictionary=loaded.state.roofs.get(k(PLOTS[who]),{})
		if not check(int(person.inventory.get(PRODUCTS[who]+"_seed",0))==1,"one seed packet persisted for "+who):return
		var sheltered:bool=who=="alpha"
		var dormant:=World.plot_dormant(crop,roof,"home",PLOTS[who],loaded.state.time)
		if not check(crop.owner==tokens[who] and dormant==(not sheltered),"correct spring dormancy persisted for "+who):return
		if sheltered and not check(person.get("greenhouse_cross_season_crop")=="tomato" and int(person.inventory.get("tomato",0))==2,"off-season harvest and quest evidence persisted"):return
	finish(true,"")

func exercise_table()->bool:
	var station:Vector2i=MACHINES[role]
	var tile:Vector2i=PLOTS[role]
	var other:="beta" if role=="alpha" else "alpha"
	var kind:String=PRODUCTS[role]
	var seed_id:=kind+"_seed"
	var craft:=await act_notice("build",station,"seed_maker")
	if not check(craft.get("ok")==true,"built personal seed maker: "+str(craft.get("message"))):return false
	for action in ["hoe","seed","water"]:
		var response:=await act_notice(action,tile,"tomato" if action=="seed" else "")
		if not check(response.get("ok")==true,"spring tomato "+action+": "+str(response.get("message"))):return false
	if role=="alpha":
		var built:=await act_notice("build",tile,"greenhouse_roof")
		if not check(built.get("ok")==true,"built greenhouse glass above own tomato: "+str(built.get("message"))):return false
	if not await barrier("start",true):return false
	var batch:=await act("queue_processing",station,seed_id)
	if not check(batch.get("ok")==true and int(inventory().get(kind,0))==0 and int(inventory().get("charcoal",0))==0,"enqueue paid the full crop and one charcoal"):return false
	var early:=await act("claim_processing",station)
	if not check(early.get("ok")==false and str(early.get("message")).begins_with("加工尚未完成"),"early claim refused"):return false
	if not await barrier("advance",true):return false
	var before:=ints(inventory())
	var denied:=await act("claim_processing",MACHINES[other])
	if not check(denied.get("ok")==false and denied.get("message")=="只能使用自己的加工設備" and ints(inventory())==before,"cannot claim another player's output"):return false
	var own_claim:=await act("claim_processing",station)
	if not check(own_claim.get("ok")==true and int(inventory().get(seed_id,0))==1,"own claim returns exactly one packet"):return false
	var duplicate:=await act("claim_processing",station)
	if not check(duplicate.get("ok")==false and int(inventory().get(seed_id,0))==1,"duplicate claim cannot create another packet"):return false
	var greenhouse:Dictionary=snap().crops[k(PLOTS.alpha)]
	var outside:Dictionary=snap().crops[k(PLOTS.beta)]
	if not check(float(greenhouse.growth)>=float(World.CROPS.tomato.time) and float(outside.growth)==0.0 and snap().roofs[k(PLOTS.alpha)].type=="greenhouse_roof","both clients see the covered plot mature and outdoor plot stay dormant"):return false
	if not await barrier("mature",true):return false
	var harvest:=await act_notice("harvest",tile)
	if role=="alpha":
		if not check(harvest.get("ok")==true and int(inventory().get("tomato",0))==2,"greenhouse owner harvested two tomatoes in spring"):return false
	else:
		if not check(harvest.get("ok")==false and str(harvest.get("message")).contains("休眠") and int(inventory().get("tomato",0))==0,"outdoor harvest is refused out of season"):return false
	return check(violation.is_empty(),"snapshot privacy held")
