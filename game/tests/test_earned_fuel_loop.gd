extends "res://tests/test_earned_forestry_journey.gd"
## Fully earned fuel return + plank storage, including a stopped belt/reload.
var fuel_loop_complete:=false
var fuel_kiln:=NONE
var plank_box:=NONE
var loop_belts:Array[Vector2i]=[]

func finish(path:String)->void:
	expect(fuel_loop_complete,"Earned fuel loop reached the final checkpoint")
	super.finish(path)

func export_loop(stage:String)->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-loop-prefix="):
			expect(DirAccess.copy_absolute(world.save_path,arg.trim_prefix("--qa-loop-prefix=")+"-"+stage+".json")==OK,"Export earned fuel loop "+stage)

func reload_loop(label:String)->void:
	var before:Dictionary=JSON.parse_string(JSON.stringify(world.state.objects))
	var inv:Dictionary=bag().duplicate(true)
	var loaded:=World.new()
	expect(loaded.load_world(world.save_path),label+" loads")
	loaded.add_player(TOKEN,"Island")
	world=loaded
	expect(before==JSON.parse_string(JSON.stringify(world.state.objects)) and same(inv,bag()),label+" retains devices, cargo and inventory")

func reload_final()->void:
	super.reload_final()
	if failed:return
	var original_box:Dictionary=box_items().duplicate(true)
	# Six fuel-route belts plus the board outlet; one belt is already in the bag.
	var batches:=ceili(float(7-held("conveyor_kit"))/int(World.CRAFT.conveyor_kit.yield))
	var joints:=batches*int(World.CRAFT.conveyor_kit.ingredients.copper_joint)
	var wood_needed:=joints*int(World.CRAFT.copper_joint.ingredients.wood)+int(World.CRAFT.kiln_kit.ingredients.wood)+int(World.BUILD.private_chest.wood)+int(proc("charcoal").ingredients.wood)
	gather("wood",wood_needed,"tree")
	gather("stone",int(World.CRAFT.kiln_kit.ingredients.stone),"rock")
	must("queue_processing",kiln,"charcoal","Make earned startup fuel")
	advance(float(proc("charcoal").time)+0.1,"Process earned startup fuel")
	must("claim_processing",kiln,"","Claim earned startup fuel")
	for batch in joints:
		var wait:=maxf(0.0,float(world.state.copper.ready)-float(world.state.time))
		if wait>0:advance(wait+0.01,"Replenish actual loop copper")
		must("pick",World.COPPER_CELL,"","Mine actual loop copper")
	for index in joints:must("craft",bench,"copper_joint","Craft loop joint")
	for batch in batches:must("craft",bench,"conveyor_kit","Craft earned return-route belts")
	must("craft",bench,"kiln_kit","Craft dedicated fuel kiln")
	if failed:return
	fuel_kiln=forester+Vector2i(0,-2)
	plank_box=sawmill+Vector2i(0,2)
	# Reconfigure the north grove plot through real maturation and axe actions.
	tick_until(func():return world.state.forest[World.key(fuel_kiln)].mature,100,"Wait for own north tree before relocating that plot")
	clear_resource(fuel_kiln)
	var specs:=[
		[forester+Vector2i(0,-1),0,"wood"],
		[forester+Vector2i(-1,-2),3,"charcoal"],
		[forester+Vector2i(-2,-2),2,"charcoal"],
		[forester+Vector2i(-2,-1),1,"charcoal"],
		[forester+Vector2i(-1,-1),2,"charcoal"],
		[forester+Vector2i(-1,0),1,"charcoal"],
		[sawmill+Vector2i(0,1),2,"plank"]]
	var sites:Array[Vector2i]=[fuel_kiln,plank_box]
	for spec in specs:sites.append(spec[0])
	for tile in sites:
		expect(world.is_land(tile) and not world.water(tile) and not world.protected(tile),"Loop site %s is legal land"%tile)
		for layer in LAYERS:expect(not world.state[layer].has(World.key(tile)),"Loop does not erase "+str(layer))
		if failed:return
		clear_resource(tile)
	must("build",fuel_kiln,"charcoal_kiln","Place earned fuel-return kiln")
	must("build",plank_box,"private_chest","Place earned private board storage")
	var last_belt:Vector2i=forester+Vector2i(-1,0)
	var held_belt:Vector2i=forester+Vector2i(-1,-1)
	for spec in specs:
		var tile:Vector2i=spec[0]
		must("build",tile,"conveyor","Place earned loop belt")
		must("configure_conveyor",tile,"dir:%d"%spec[1],"Configure loop direction")
		must("configure_conveyor",tile,"filter:"+str(spec[2]),"Configure loop cargo")
		if tile!=last_belt:must("toggle_conveyor",tile,"","Enable loop segment")
		loop_belts.append(tile)
	must("toggle_auto_processing",fuel_kiln,"","Enable actual automatic charcoal production")
	var fuel_start:=int(obj(forester).fuel)+held("charcoal")
	must("load_forester",forester,"charcoal","Load only two earned startup charcoal")
	expect(fuel_start==3 and held("charcoal")==0 and int(obj(forester).fuel)==3,"Loop starts with exactly three fuel, no hidden refill")
	var raw_start:=int(obj(sawmill).input_wood)
	var backpack:Dictionary=bag().duplicate(true)
	must("toggle_forester",forester,"","Resume earned grove for a sustained loop")
	walk_to(forester,1.0)
	tick_until(func():return int(obj(held_belt).items.get("charcoal",0))==1,120,"Reach real backpressure at the intentionally stopped return belt")
	if failed:return
	var reason:=World.LOGISTICS.delivery_block(obj(held_belt),obj(last_belt),obj(last_belt))
	expect(reason=="前方輸送帶已停用","Actual retained charcoal identifies the stopped next segment")
	export_loop("blocked")
	reload_loop("Blocked fuel route")
	var fuel_before:=int(obj(forester).fuel)
	must("toggle_conveyor",last_belt,"","Restart actual blocked return segment")
	tick_until(func():return int(obj(forester).fuel)>fuel_before,30,"Deliver retained charcoal to forestry fuel slot")
	tick_until(func():return int(obj(forester).items.get("fiber",0))>=12,400,"Sustain six new harvests with automatic fuel return")
	if failed:return
	var harvests:=int(obj(forester).items.fiber)/int(World.FORESTRY.OUTPUT.fiber)
	expect(harvests>=6 and harvests>fuel_start,"Harvest count exceeds all startup fuel without manual refilling")
	must("toggle_forester",forester,"","Pause grove to audit earned loop conservation")
	tick_until(func():
		if int(obj(forester).items.get("wood",0))>0:return false
		for tile in loop_belts+[timber_belt]:
			if not obj(tile).items.is_empty():return false
		for tile in [sawmill,fuel_kiln]:
			if obj(tile).has("job") or int(obj(tile).input_wood)>=4:return false
		return true,100,"Finish in-flight processing and storage")
	if failed:return
	var raw:=int(obj(sawmill).input_wood)+int(obj(fuel_kiln).input_wood)
	var boards:=int(obj(plank_box).items.get("plank",0))+int(obj(sawmill).items.get("plank",0))
	var fuel:=int(obj(forester).fuel)+int(obj(fuel_kiln).items.get("charcoal",0))
	expect(6*harvests+raw_start==raw+2*boards+2*(fuel+harvests-fuel_start),"All harvested timber conserved as boards, raw wood, produced/consumed fuel")
	expect(int(obj(plank_box).items.get("plank",0))>=4,"Real automatically made boards reached private storage")
	expect(same(backpack,bag()) and same(original_box,box_items()),"Running loop never silently refills from backpack or shared chest")
	export_loop("stored")
	reload_loop("Sustained loop and private storage")
	var before:=held("plank")
	must("withdraw",plank_box,"plank","Withdraw actual stored board")
	expect(held("plank")==before+1,"Private storage retains original withdrawal behavior")
	walk_to(last_belt,1.0)
	expect(world.save(),"Save actual final loop viewpoint")
	export_loop("final")
	fuel_loop_complete=not failed
	print("EARNED_FUEL_LOOP passed=%s harvests=%d stored_boards=%d fuel=%d raw=%d simulated_seconds=%.2f"%[not failed,harvests,obj(plank_box).items.get("plank",0),fuel,raw,sim_seconds])
