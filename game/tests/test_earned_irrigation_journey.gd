extends "res://tests/test_earned_pump_journey.gd"
## Default supplies -> gathered/processed/crafted irrigation -> actual dry crop.
## No inventory, flags, objects or position writes. World API, not manual play.
var irrigation_pump:=NONE
var irrigation_crop:=NONE
var irrigation_complete:=false

func finish(path:String)->void:
	expect(irrigation_complete,"Full earned irrigation stage reached its final checkpoint")
	super.finish(path)

func advance(seconds:float,label:String)->void:
	if failed:return
	expect(world.step(seconds,true),label)
	steps+=1
	sim_seconds+=seconds

func clear_resource(tile:Vector2i)->void:
	if failed:return
	var resource:=world.resource(tile)
	if resource.is_empty():return
	expect(resource in ["tree","rock","grass"],"Site has a normally gatherable resource")
	if failed:return
	for hit in (3 if resource=="tree" else (2 if resource=="rock" else 1)):
		must("pick" if resource=="rock" else "axe",tile,"","Clear real resource for irrigation")
		hits+=1
	if resource=="tree":trees+=1
	if resource=="rock":rocks+=1
	expect(world.resource(tile).is_empty(),"Irrigation site cleared through gathering")

func irrigation_site()->Vector2i:
	# Scan the real river bank near the workshop; never erase an existing structure.
	for y in [36,35,34,33,32,31,30,37,38,39,40,41,42]:
		var pump:=Vector2i(53,y)
		if not World.INDUSTRY.near_river(world,pump):continue
		var valid:=true
		for x in range(49,54):
			var tile:=Vector2i(x,y)
			if not world.is_land(tile) or world.water(tile) or world.protected(tile):valid=false;break
			for layer in LAYERS:
				if world.state[layer].has(World.key(tile)):valid=false;break
		if valid and not route(pump).is_empty():return pump
	return NONE

func reload_final()->void:
	super.reload_final()
	if failed:return
	var box_before:Dictionary=box_items().duplicate(true)
	# One plank batch, three joints, one basic sprinkler; use real recipe costs.
	var tank:Dictionary=World.CRAFT.tank_kit.ingredients
	var pipe:Dictionary=World.CRAFT.pipe_kit.ingredients
	var sprinkler:Dictionary=World.CRAFT.sprinkler_kit.ingredients
	var joint:Dictionary=World.CRAFT.copper_joint.ingredients
	var plank:Dictionary=World.INDUSTRY.PROCESS.plank
	var batches:=ceili(float(maxi(0,int(tank.plank)-held("plank")))/int(plank.yield))
	var joints:=int(pipe.copper_joint)+int(sprinkler.copper_joint)
	gather("wood",batches*int(plank.ingredients.wood)+joints*int(joint.wood)+int(sprinkler.wood),"tree")
	gather("stone",int(sprinkler.stone),"rock")
	if failed:return
	for batch in batches:must("queue_processing",sawmill,"plank","Queue earned tank boards")
	advance(float(plank.time)*batches+0.2,"Process earned tank boards")
	for batch in batches:must("claim_processing",sawmill,"","Claim earned tank boards")
	for batch in ceili(float(joints*int(joint.copper_ore))/2.0):
		var cooldown:=maxf(0.0,float(world.state.copper.ready)-float(world.state.time))
		if cooldown>0.0:advance(cooldown+0.01,"Wait for real transported ore replenishment")
		must("pick",World.COPPER_CELL,"","Mine real copper for irrigation")
	for index in joints:must("craft",bench,"copper_joint","Craft earned irrigation joint")
	for recipe in ["tank_kit","pipe_kit","sprinkler_kit"]:
		must("craft",bench,recipe,"Craft earned "+recipe)
	if failed:return
	expect(held("pump_kit")==1 and held("tank_kit")==1 and held("pipe_kit")==2 and held("sprinkler_kit")==1,"All irrigation kits come from actual recipe output")
	irrigation_pump=irrigation_site()
	expect(irrigation_pump!=NONE,"A real reachable river bank supports the full irrigation layout")
	if failed:return
	irrigation_crop=irrigation_pump+Vector2i(-4,0)
	for offset in 5:clear_resource(irrigation_pump+Vector2i(-offset,0))
	if failed:return
	for spec in [[0,"water_pump"],[-1,"water_pipe"],[-2,"water_tank"],[-3,"sprinkler"]]:
		must("build",irrigation_pump+Vector2i(spec[0],0),spec[1],"Place earned "+spec[1])
	if failed:return
	expect(held("pump_kit")==0 and held("tank_kit")==0 and held("pipe_kit")==1 and held("sprinkler_kit")==0,"Construction debits each kit exactly once")
	var seeds:=held("radish_seed")
	must("hoe",irrigation_crop,"","Hoe actual empty land beside sprinkler")
	must("seed",irrigation_crop,"radish","Sow original starting radish seed")
	expect(held("radish_seed")==seeds-1 and not world.state.crops[World.key(irrigation_crop)].wet,"Sowing consumes seed and leaves crop dry")
	var sprinkler_cell:=irrigation_pump+Vector2i(-3,0)
	var tank_cell:=irrigation_pump+Vector2i(-2,0)
	must("toggle_pump",irrigation_pump,"","Enable earned river pump")
	must("toggle_sprinkler",sprinkler_cell,"","Enable earned sprinkler")
	advance(8.1,"Actual river supply and automatic irrigation")
	if failed:return
	expect(world.state.crops[World.key(irrigation_crop)].wet,"Fully earned network automatically waters actual dry crop")
	expect(int(obj(sprinkler_cell).water)==7 and int(obj(tank_cell).water)==0,"First eight-unit pump round spends one unit on crop")
	advance(8.1,"Actual second pump round fills storage")
	expect(int(obj(sprinkler_cell).water)==12 and int(obj(tank_cell).water)==3,"Second round fills sprinkler and stores three units")
	var network:=World.INDUSTRY.network_info(world.state,World.key(irrigation_pump+Vector2i(-1,0)))
	expect(network.connected_tanks==1 and network.connected_pumps==1 and network.flow_visible,"Built devices form one functional water network")
	expect(same(box_before,box_items()),"Irrigation never silently consumes the workshop chest")
	var inventory:Dictionary=bag().duplicate(true)
	var devices:Dictionary=world.state.objects.duplicate(true)
	var crop:Dictionary=world.state.crops[World.key(irrigation_crop)].duplicate(true)
	var path:=world.save_path
	var loaded:=World.new()
	expect(loaded.load_world(path),"Earned irrigated save reloads from disk")
	loaded.add_player(TOKEN,"Island")
	world=loaded
	# JSON numbers reload as floats; compare normalized trees, including all keys.
	var same_devices:bool=JSON.parse_string(JSON.stringify(devices))==JSON.parse_string(JSON.stringify(world.state.objects))
	var same_crop:bool=JSON.parse_string(JSON.stringify(crop))==JSON.parse_string(JSON.stringify(world.state.crops[World.key(irrigation_crop)]))
	expect(same(inventory,bag()) and same_devices and same_crop,"Reload retains exact kits, water network and wet crop")
	advance(0.1,"Resume under an interval without extra water")
	expect(int(obj(sprinkler_cell).water)==12 and int(obj(tank_cell).water)==3,"Reload cannot bypass the pump interval")
	# Leave the real player near the installation for native save-copy inspection.
	walk_to(tank_cell,1.0)
	if failed:return
	expect(world.save(),"Persist real walking position for native preview")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-irrigation-output="):
			expect(DirAccess.copy_absolute(path,arg.trim_prefix("--qa-irrigation-output="))==OK,"Export actual earned irrigated save")
	irrigation_complete=not failed
	print("EARNED_IRRIGATION_JOURNEY passed=%s pump=%s crop=%s simulated_seconds=%.2f"%[not failed,irrigation_pump,irrigation_crop,sim_seconds])
