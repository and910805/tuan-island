extends "res://tests/test_earned_irrigation_journey.gd"
## Normal supplies -> irrigation -> forestry -> belt -> automatic planks.
## All materials earned. No inventory, position, forest or object fixture writes.
var forestry_complete:=false
var forester:=NONE
var timber_belt:=NONE

func finish(path:String)->void:
	expect(forestry_complete,"Earned forestry pipeline reached its final checkpoint")
	super.finish(path)

func tick_until(predicate:Callable,limit:int,label:String)->void:
	for tick in limit:
		if failed or predicate.call():break
		advance(2.0,label)
	expect(not failed and predicate.call(),label+" completed within bounded simulation")

func export_forestry(stage:String)->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-forestry-prefix="):
			expect(DirAccess.copy_absolute(world.save_path,arg.trim_prefix("--qa-forestry-prefix=")+"-"+stage+".json")==OK,"Export actual earned forestry "+stage)

func reload_final()->void:
	super.reload_final()
	if failed:return
	var box_before:Dictionary=box_items().duplicate(true)
	var kit:Dictionary=World.CRAFT.forester_kit.ingredients
	var belt:Dictionary=World.CRAFT.conveyor_kit.ingredients
	var joint:Dictionary=World.CRAFT.copper_joint.ingredients
	var boards:Dictionary=World.INDUSTRY.PROCESS.plank
	var coal:Dictionary=World.INDUSTRY.PROCESS.charcoal
	var plank_batches:=ceili(float(int(kit.plank)+int(belt.plank)-held("plank"))/int(boards.yield))
	var coal_batches:=ceili(float(int(kit.charcoal)+4-held("charcoal"))/int(coal.yield))
	var joints:=int(kit.copper_joint)+int(belt.copper_joint)
	gather("wood",plank_batches*int(boards.ingredients.wood)+coal_batches*int(coal.ingredients.wood)+joints*int(joint.wood),"tree")
	gather("stone",int(kit.stone),"rock")
	if failed:return
	for batch in plank_batches:must("queue_processing",sawmill,"plank","Queue earned forestry boards")
	for batch in coal_batches:must("queue_processing",kiln,"charcoal","Queue earned forestry charcoal")
	tick_until(func():return queue(sawmill).ready.size()==plank_batches and queue(kiln).ready.size()==coal_batches,80,"Process forestry construction materials")
	for batch in plank_batches:must("claim_processing",sawmill,"","Claim earned forestry boards")
	for batch in coal_batches:must("claim_processing",kiln,"","Claim earned forestry charcoal")
	for batch in ceili(float(joints*int(joint.copper_ore))/2.0):
		var cooldown:=maxf(0.0,float(world.state.copper.ready)-float(world.state.time))
		if cooldown>0:advance(cooldown+0.01,"Wait for earned forestry copper")
		must("pick",World.COPPER_CELL,"","Mine actual forestry copper")
	for index in joints:must("craft",bench,"copper_joint","Craft earned forestry joint")
	must("craft",bench,"forester_kit","Craft earned forestry station")
	must("craft",bench,"conveyor_kit","Craft earned conveyor pair")
	if failed:return
	# One straight belt reaches the existing sawmill. That machine occupies the
	# eastern forestry plot; three other plots remain a legitimate working grove.
	forester=sawmill+Vector2i(-2,0)
	timber_belt=sawmill+Vector2i.LEFT
	var planting_tiles:Array[Vector2i]=[]
	for offset:Vector2i in World.FORESTRY.OFFSETS:
		var tile:=forester+offset
		if tile!=sawmill:planting_tiles.append(tile)
	for tile in [forester,timber_belt]+planting_tiles:
		expect(world.is_land(tile) and not world.water(tile) and not world.protected(tile),"Earned forestry site is buildable land")
		for layer in LAYERS:expect(not world.state[layer].has(World.key(tile)),"Forestry site does not erase "+str(layer))
		if failed:return
		clear_resource(tile)
	must("build",forester,"forester","Place earned forestry station")
	must("build",timber_belt,"conveyor","Place earned timber belt")
	must("configure_conveyor",timber_belt,"dir:1","Aim belt from forestry to sawmill")
	must("configure_conveyor",timber_belt,"filter:wood","Filter actual forestry timber")
	must("toggle_conveyor",timber_belt,"","Enable timber delivery")
	must("toggle_auto_processing",sawmill,"","Enable original sawmill automatic mode")
	var seedlings:=held("sapling")
	must("load_forester",forester,"sapling","Load earned seedlings")
	must("load_forester",forester,"charcoal","Load earned fuel")
	expect(held("sapling")==seedlings-4 and obj(forester).saplings==4 and obj(forester).fuel==4,"Actual supply actions debit earned inventory")
	must("toggle_forester",forester,"","Enable earned forestry")
	walk_to(forester,1.0)
	tick_until(func():return planting_tiles.all(func(tile):return world.state.forest.has(World.key(tile))),35,"Automatically plant three usable forestry plots")
	if failed:return
	expect(obj(forester).saplings==1 and obj(forester).fuel==4,"Planting spends seedlings, no fuel")
	expect(World.FORESTRY.plot_status(world,sawmill,TOKEN)=="blocked","Sawmill occupies one forestry plot without blocking all three others")
	export_forestry("planted")
	var loaded:=World.new()
	expect(loaded.load_world(world.save_path),"Growing earned grove reloads")
	loaded.add_player(TOKEN,"Island")
	world=loaded
	var backpack_wood:=held("wood")
	tick_until(func():return int(obj(forester).fuel)==1,150,"Grow and harvest three real planted trees")
	if failed:return
	must("toggle_forester",forester,"","Pause after three actual harvests")
	expect(obj(forester).saplings==1,"Harvest replanting does not consume an extra seedling")
	for tile in planting_tiles:
		var tree:Dictionary=world.state.forest[World.key(tile)]
		expect(tree.owner==TOKEN and not tree.mature and float(tree.growth)<World.TREE_TIME,"Harvest really replants owned immature trees")
	tick_until(func():return int(obj(forester).items.get("wood",0))==0 and obj(timber_belt).items.is_empty() and not obj(sawmill).has("job"),60,"Drain harvested timber through automatic sawmill")
	if failed:return
	expect(held("wood")==backpack_wood,"Automatic line does not silently feed from backpack")
	expect(int(obj(sawmill).items.get("plank",0))==8 and int(obj(sawmill).input_wood)==2,"Eighteen harvested wood become eight boards plus two raw wood")
	expect(int(obj(forester).items.get("fiber",0))==6 and int(obj(forester).items.get("resin",0))==3,"All three harvests retain exact forestry byproducts")
	var prior_plank:=held("plank")
	must("collect_processing_output",sawmill,"","Collect real automatically processed boards")
	expect(held("plank")==prior_plank+8,"Original automatic collection grants eight earned boards")
	var prior_fiber:=held("fiber")
	var prior_resin:=held("resin")
	must("collect_forester",forester,"","Collect remaining real forestry byproducts")
	expect(held("fiber")==prior_fiber+6 and held("resin")==prior_resin+3,"Original forestry collection grants only actual byproducts")
	expect(same(box_before,box_items()),"Automated forestry never silently consumes the shared workshop chest")
	var inventory:Dictionary=bag().duplicate(true)
	var objects:Dictionary=JSON.parse_string(JSON.stringify(world.state.objects))
	var forest:Dictionary=JSON.parse_string(JSON.stringify(world.state.forest))
	loaded=World.new()
	expect(loaded.load_world(world.save_path),"Finished forestry pipeline reloads")
	loaded.add_player(TOKEN,"Island")
	world=loaded
	expect(same(inventory,bag()) and objects==JSON.parse_string(JSON.stringify(world.state.objects)) and forest==JSON.parse_string(JSON.stringify(world.state.forest)),"Reload retains exact collection, belt, remaining raw input and replanted grove")
	walk_to(forester,1.0)
	expect(world.save(),"Save earned forestry viewpoint")
	export_forestry("final")
	forestry_complete=not failed
	print("EARNED_FORESTRY_JOURNEY passed=%s station=%s belt=%s sawmill=%s boards=8 simulated_seconds=%.2f"%[not failed,forester,timber_belt,sawmill,sim_seconds])
