extends SceneTree
## T067 deep mine floors B6–B15 wired through real world.act() actions.
## PRESETS (fixture inputs, not earned in play): mine_depths starts at
## {"unlocked":5,"ready":{},"pumped":24,"hoist":false}; state.picnic=true; both players start in
## "jinguashi"; reinforced_pick 1; each commission's exact materials are written into the bag right
## before it; the Q07 hoist repair materials (Mines.HOIST_COST) are written into the bag at B9;
## mine_energy is set to energy_cost(d) for the exhaustion strike; mine_drill_kit 2 for the drill
## placement checks. Everything else is real actions.
const World=preload("res://scripts/world.gd")
const Mines=World.MINES
const Survey=World.MINE_SURVEY
const Drill=World.MINE_DRILL
const Regions=World.REGIONS
const Weather=World.WEATHER
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Actor="deep-miner"
const Beta="deep-surveyor"
const SURFACE_ARRIVAL:=Vector2(27.5,19.5)
const DRILL_CELL:=Vector2i(28,24)
var checks:=0
var failures:=0
var serial:=0

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func rid(tag:String)->String:
	serial+=1
	return "%s-%d"%[tag,serial]

func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func place(world:World,actor:String,p:Vector2i)->void:
	world.state.players[actor].x=p.x-0.5
	world.state.players[actor].y=p.y+0.5

func pos(world:World,actor:String)->Vector2:
	var person:Dictionary=world.state.players[actor]
	return Vector2(float(person.x),float(person.y))

func travel(world:World,actor:String,target:String,cell:Vector2i)->Dictionary:
	place(world,actor,cell)
	return world.act(actor,rid("go"),"mine_travel",cell,target)

func go(world:World,actor:String,target:String,cell:Vector2i)->bool:
	return travel(world,actor,target,cell).ok and world.player_region(actor)==target

func refused(world:World,actor:String,target:String,cell:Vector2i)->bool:
	var region:=world.player_region(actor)
	return not travel(world,actor,target,cell).ok and world.player_region(actor)==region

func standing_on_land(world:World,actor:String)->bool:
	var at:=pos(world,actor)
	var region:=world.player_region(actor)
	var tile:=Vector2i(floori(at.x),floori(at.y))
	return World.land(tile,region) and not Regions.water(tile,region)

func near(world:World,actor:String,target:Vector2,radius:float=3.2)->bool:
	return pos(world,actor).distance_to(target)<=radius

func observe(world:World,actor:String,depth:int)->Dictionary:
	var point:Vector2i=Survey.POINTS[depth]
	world.state.players[actor].x=point.x+0.5
	world.state.players[actor].y=point.y+0.5
	return world.act(actor,rid("observe-%d"%depth),"survey_observe",point)

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("deep-levels-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var legacy_path:=path.get_basename()+"-legacy.json"
	var broken:=path.path_join("missing").path_join("file")
	var world:=World.new()
	world.save_path=path
	world.add_player(Actor,"Miner")
	world.add_player(Beta,"Surveyor")

	# h) Static wiring: labels, indoor weather, region list, helper tables.
	expect(Mines.IDS.size()==15 and Mines.IDS[14]=="mine_15" and Mines.SHALLOW_DEPTH==5 and Mines.MAX_DEPTH==15,"Mines ships fifteen floors")
	expect(Regions.ALL.slice(Regions.ALL.size()-10)==Catalog.region_ids(),"Regions.ALL ends with mine_6..mine_15")
	expect(Regions.label("mine_12")=="合作礦場第 12 層","Deep floor label uses the shared mine wording")
	expect(Weather.is_indoor("mine_15") and str(Weather.at(2.0*Weather.DAY_SECONDS,"mine_15").id)=="indoor","Deepest floor is indoor and never rains")
	for depth in range(6,16):
		expect(Weather.is_indoor(Mines.IDS[depth-1]),"B%d is indoor"%depth)
		expect(world.state.regions.has(Mines.IDS[depth-1]),"Fresh world has region B%d"%depth)
		expect(Mines.energy_cost(depth)==roundi(10.0*Catalog.energy_multiplier(depth)),"B%d energy cost follows hazard multiplier"%depth)
		expect(Mines.finds(depth)==Catalog.DEPTHS[depth].finds,"B%d finds come from catalog"%depth)
	expect(Mines.energy_cost(1)==10 and Mines.energy_cost(5)==10,"B1–B5 energy cost unchanged")
	expect(Mines.finds(5)==["crystal_sand"] and Mines.finds(4)==["iron_ore"] and Mines.finds(1).is_empty(),"B4 has iron, and B5 retains crystal sand")
	expect(Mines.lift_targets(5).is_empty() and Mines.lift_targets(9)==[6] and Mines.lift_targets(15)==[6,10,15],"Lift landings never exceed unlocked depth")
	expect(Mines.surface_landings({"unlocked":15,"ready":{},"pumped":24,"hoist":false}).is_empty() and Mines.surface_landings({"unlocked":9,"ready":{},"pumped":24,"hoist":true})==[6],"Surface landings need the repaired hoist")
	expect("mine_6" not in Drill.REGIONS and Drill.REGIONS==Mines.IDS.slice(0,5),"Drill is limited to B1–B5")

	# PRESET: start with B1–B4 commissions done and B3 drained (equivalent to test_mine_depths' real path).
	world.state.mine_depths={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	world.state.picnic=true
	for actor in [Actor,Beta]:
		var person:Dictionary=world.state.players[actor]
		person.region="jinguashi"
		person.inventory.merge({"reinforced_pick":1},true)
	expect(valid(world.state.duplicate(true)),"Preset unlocked-5 state is schema-valid")

	# c) Surface hoist is closed before any deep floor opens.
	expect(refused(world,Actor,"mine_6",Mines.ENTRY),"Hoist to B6 refused while only B5 is open")
	# a) Descend B1–B5 with the ordinary stairs.
	expect(go(world,Actor,"mine_1",Mines.ENTRY),"Enter B1 from the surface")
	for depth in range(1,5):
		if depth==3:
			expect(refused(world,Actor,"jinguashi",Mines.LIFT),"LIFT on B3 is not a hoist station")
		expect(go(world,Actor,Mines.IDS[depth],Mines.DOWN),"Stairs B%d→B%d"%[depth,depth+1])
	expect(world.player_region(Actor)=="mine_5","Reached B5")
	# Legacy snapshot (d) taken at unlocked 5 while standing on B5.
	var legacy:Dictionary=world.state.duplicate(true)

	for depth in range(5,16):
		var region:String=Mines.IDS[depth-1]
		var person:Dictionary=world.state.players[Actor]
		var inv:Dictionary=person.inventory
		expect(world.player_region(Actor)==region and int(world.state.mine_depths.unlocked)==depth,"On B%d with B%d the deepest open floor"%[depth,depth])
		if depth>=6:
			# b) Arrival is safe ground.
			expect(standing_on_land(world,Actor),"B%d stair arrival stands on land"%depth)
			# f) Survey page on the reused side cave.
			var page:=observe(world,Actor,depth)
			expect(page.ok and Survey.own_record(world.state,Actor).seen.has(str(depth)),"Survey observation recorded on B%d"%depth)
			expect(str(page.get("message","")).contains(str(Survey.entry(depth).get("title","?"))) and Survey.entry(depth).title==Catalog.DEPTHS[depth].survey.title,"B%d survey page comes from catalog"%depth)
			# b) One normal strike.
			var ore:String=Mines.ORES[depth-1]
			var quantity:int=Mines.YIELDS[depth-1]
			expect(ore==Catalog.DEPTHS[depth].ore and quantity==int(Catalog.DEPTHS[depth].yield),"B%d ore table from catalog"%depth)
			var expected:={ore:quantity}
			for item in Mines.finds(depth):expected[item]=int(expected.get(item,0))+1
			var bag_before:Dictionary=inv.duplicate(true)
			var energy:=int(person.mine_energy)
			var cost:=Mines.energy_cost(depth)
			expect(energy==100,"B%d starts with full mining energy"%depth)
			var node:Vector2i=Mines.NODES[0]
			place(world,Actor,node)
			var strike:=world.act(Actor,rid("strike-%d"%depth),"mine_extract",node)
			var gained:=true
			for item in expected:gained=gained and int(inv.get(item,0))==int(bag_before.get(item,0))+int(expected[item])
			var others_same:=true
			for item in inv:
				if not expected.has(item):others_same=others_same and int(inv[item])==int(bag_before.get(item,0))
			expect(strike.ok and not strike.get("mine_exhausted",false),"Strike B%d node succeeds"%depth)
			expect(gained and others_same,"B%d strike gives %s×%d plus one of each find, nothing else"%[depth,ore,quantity])
			expect(int(person.mine_energy)==energy-cost,"B%d strike costs %d energy"%[depth,cost])
			expect(not world.act(Actor,rid("cooldown-%d"%depth),"mine_extract",node).ok,"B%d node cooldown blocks a second strike"%depth)
			# b) Exhaustion strike. PRESET: energy set to exactly the floor cost.
			person.mine_energy=cost
			var tired_node:Vector2i=Mines.NODES[1]
			place(world,Actor,tired_node)
			var ore_before:=int(inv.get(ore,0))
			var tired:=world.act(Actor,rid("tired-%d"%depth),"mine_extract",tired_node)
			expect(tired.ok and tired.get("mine_exhausted",false) and int(person.mine_energy)==100 and int(inv.get(ore,0))>=ore_before+quantity and int(inv.reinforced_pick)==1,"B%d exhaustion pays out, keeps tools and refills energy"%depth)
			expect(world.player_region(Actor)==region and near(world,Actor,Vector2(Mines.REST)+Vector2(0.5,0.5)),"B%d exhaustion returns to this floor's rest point"%depth)
		if depth==6:
			# g) Drill placement refused below B5. PRESET: two kits.
			inv["mine_drill_kit"]=2  # String key: dot-assign makes a StringName key the schema rejects.
			person.x=DRILL_CELL.x-0.5;person.y=DRILL_CELL.y-0.5
			expect(not world.act(Actor,rid("drill-b6"),"build",DRILL_CELL,"mine_drill").ok and int(world.state.players[Actor].inventory.get("mine_drill_kit",0))==2 and not world.state.regions.mine_6.objects.has(World.key(DRILL_CELL)),"Mine drill cannot be placed on B6")
		if depth==9:
			# c) Hoist round trip at unlocked 9.
			expect(refused(world,Actor,"mine_6",Mines.LIFT),"Deep lift only goes to the surface")
			var up:=travel(world,Actor,"jinguashi",Mines.LIFT)
			expect(up.ok and world.player_region(Actor)=="jinguashi" and near(world,Actor,SURFACE_ARRIVAL),"B9 lift returns to the Jinguashi entrance")
			expect(refused(world,Actor,"mine_10",Mines.ENTRY),"Hoist to B10 refused while unlocked is 9")
			expect(refused(world,Actor,"mine_7",Mines.ENTRY),"B7 is not a hoist landing")
			# Q07: the surface hoist is stuck until the shared repair.
			var stuck:=travel(world,Actor,"mine_6",Mines.ENTRY)
			expect(not stuck.ok and str(stuck.message)==World.HOIST_STUCK_MSG and world.player_region(Actor)=="jinguashi","Hoist to B6 is stuck before the Q07 repair")
			var bag:Dictionary=world.state.players[Actor].inventory
			for item in Mines.HOIST_COST:bag[item]=int(bag.get(item,0))+int(Mines.HOIST_COST[item])  # PRESET repair materials
			var repair:=world.act(Actor,rid("hoist"),World.HOIST_ACTION,Mines.ENTRY)
			expect(repair.ok and Mines.hoist_ready(world.state.mine_depths),"Hoist repaired at the entry sign")
			var down:=travel(world,Actor,"mine_6",Mines.ENTRY)
			expect(down.ok and world.player_region(Actor)=="mine_6" and near(world,Actor,Vector2(Mines.LIFT)+Vector2(0.5,0.5)) and standing_on_land(world,Actor),"Hoist lowers to B6 beside the lift")
			for back in range(6,9):expect(go(world,Actor,Mines.IDS[back],Mines.DOWN),"Stairs back down B%d→B%d"%[back,back+1])
		if depth==10:
			expect(go(world,Actor,"jinguashi",Mines.LIFT),"B10 lift to surface")
			expect(refused(world,Actor,"mine_15",Mines.ENTRY),"Hoist to B15 refused while unlocked is 10")
			var lowered:=travel(world,Actor,"mine_10",Mines.ENTRY)
			expect(lowered.ok and world.player_region(Actor)=="mine_10" and near(world,Actor,Vector2(Mines.LIFT)+Vector2(0.5,0.5)),"Hoist lowers to B10 once unlocked")
		if depth==12:
			# e) Failed save rolls back a deep strike.
			person.mine_energy=100
			var spare:Vector2i=Mines.NODES[2]
			place(world,Actor,spare)
			var before_strike:=world.state.duplicate(true)
			world.save_path=broken
			expect(not world.act(Actor,rid("broken-strike"),"mine_extract",spare).ok and world.state==before_strike,"Deep strike save failure rolls back")
			world.save_path=path
		if depth==15:break
		# a) Commission at the service station.
		var next:String=Mines.IDS[depth]
		expect(refused(world,Actor,next,Mines.DOWN),"B%d stairs blocked before its commission"%(depth+1))
		var cost_items:Dictionary=Mines.COSTS[depth-1]
		expect(cost_items==Catalog.COMMISSIONS[depth].cost,"B%d commission cost is the catalog cost"%depth)
		var first:String=cost_items.keys()[0]
		inv=world.state.players[Actor].inventory  # rollbacks replace world.state; never reuse stale refs
		for item in cost_items:inv[item]=int(cost_items[item])  # PRESET materials
		inv[first]=int(cost_items[first])-1
		place(world,Actor,Mines.SERVICE)
		var short:=world.state.duplicate(true)
		expect(not world.act(Actor,rid("short-%d"%depth),"mine_commission",Mines.SERVICE).ok and world.state==short,"B%d commission with one %s short fails without mutation"%[depth,first])
		inv=world.state.players[Actor].inventory
		inv[first]=int(cost_items[first])
		var before:=world.state.duplicate(true)
		var request:="commission-%d"%depth
		world.save_path=broken
		expect(not world.act(Actor,request,"mine_commission",Mines.SERVICE).ok and world.state==before,"B%d commission save failure rolls back"%depth)
		world.save_path=path
		var result:=world.act(Actor,request,"mine_commission",Mines.SERVICE)
		inv=world.state.players[Actor].inventory
		var spent:=true
		for item in cost_items:spent=spent and int(inv.get(item,0))==0
		expect(result.ok and int(world.state.mine_depths.unlocked)==depth+1 and spent,"B%d commission consumes the exact cost and opens B%d"%[depth,depth+1])
		expect(world.act(Actor,request,"mine_commission",Mines.SERVICE)==result and int(world.state.mine_depths.unlocked)==depth+1,"B%d commission replay settles once"%depth)
		expect(not world.act(Actor,rid("again-%d"%depth),"mine_commission",Mines.SERVICE).ok,"B%d commission cannot be repeated"%depth)
		if depth==12:
			place(world,Actor,Mines.DOWN)
			var before_down:=world.state.duplicate(true)
			world.save_path=broken
			expect(not world.act(Actor,rid("broken-down"),"mine_travel",Mines.DOWN,next).ok and world.state==before_down and world.player_region(Actor)==region,"Deep stair save failure rolls back")
			world.save_path=path
		expect(go(world,Actor,next,Mines.DOWN),"Stairs B%d→B%d"%[depth,depth+1])

	# a) Terminus. Position is captured after the last saved action; refused
	# actions below move the test actor without saving.
	var where:=pos(world,Actor)
	expect(int(world.state.mine_depths.unlocked)==15 and world.player_region(Actor)=="mine_15","All fifteen floors opened")
	expect(refused(world,Actor,"mine_16",Mines.DOWN) and refused(world,Actor,"mine_15",Mines.DOWN),"No stairs below B15")
	var inv15:Dictionary=world.state.players[Actor].inventory
	for item in Catalog.COMMISSIONS[14].cost:inv15[item]=99  # PRESET: plenty of materials, still refused
	place(world,Actor,Mines.SERVICE)
	var at_end:=world.state.duplicate(true)
	expect(not world.act(Actor,rid("commission-15"),"mine_commission",Mines.SERVICE).ok and world.state==at_end,"No commission on B15")
	var bad:=world.state.duplicate(true)
	bad.mine_depths.unlocked=16
	expect(not valid(bad),"Schema rejects unlocked 16")

	# d) Save/reload at B15.
	var reload:=World.new()
	expect(FileAccess.file_exists(path) and reload.load_world(path) and not reload.recovered_from_backup,"Deep save loads")
	var back:Dictionary=reload.state.players.get(Actor,{})
	expect(int(reload.state.version)==26 and int(reload.state.mine_depths.unlocked)==15 and int(reload.state.mine_depths.pumped)==24 and reload.state.mine_depths.get("hoist")==true,"Unlocked 15 and the repaired hoist persist without a version bump")
	var local_mine_bits:=3<<World.ISLAND_NOTES.PROJECTS.size()
	expect((reload.island_news_project_mask() & local_mine_bits)==local_mine_bits and (reload.island_project_mask() & local_mine_bits)==0,"Completed B15 and hoist appear in the news outside the festival checklist")
	expect(reload.act(Actor,rid("read-mine-news"),"news_read",Vector2i.ZERO,str(local_mine_bits)).ok and reload.save(),"Mining news can be marked read in a valid save")
	var read_again:=World.new()
	expect(read_again.load_world(path) and (int(read_again.state.players[Actor].news_seen) & local_mine_bits)==local_mine_bits,"The extended read mask survives reopening")
	expect(back.get("region","")=="mine_15" and is_equal_approx(float(back.get("x",0)),where.x) and is_equal_approx(float(back.get("y",0)),where.y),"Region and position persist")
	var ready_regions:Array=reload.state.mine_depths.ready.keys()
	expect("mine_6" in ready_regions and "mine_15" in ready_regions,"Deep node cooldowns persist")
	var survived:=true
	for region in Catalog.region_ids():survived=survived and reload.state.regions.has(region)
	expect(survived,"Reloaded save keeps every deep region")

	# c) B15 hoist, then f) claim gating with only deep pages.
	expect(go(world,Actor,"jinguashi",Mines.LIFT),"B15 lift to surface")
	var table:Vector2i=world.bobo_sites().table
	var me:Dictionary=world.state.players[Actor]
	me.x=table.x+1.5;me.y=table.y+0.5
	expect(Survey.own_record(world.state,Actor).seen.size()==10 and not world.act(Actor,rid("claim-deep-only"),"survey_claim",table).ok,"Deep pages alone cannot claim the five-page reward")
	var lowered15:=travel(world,Actor,"mine_15",Mines.ENTRY)
	expect(lowered15.ok and world.player_region(Actor)=="mine_15" and near(world,Actor,Vector2(Mines.LIFT)+Vector2(0.5,0.5)),"Hoist lowers to B15")

	# Generic UP stairs for all fifteen floors; record B1–B5 pages on the way up.
	for depth in range(15,0,-1):
		if depth<=5:
			expect(observe(world,Actor,depth).ok,"Survey observation recorded on B%d"%depth)
		if depth==5:
			# g) Control: same kit places fine on B5.
			me=world.state.players[Actor]
			me.x=DRILL_CELL.x-0.5;me.y=DRILL_CELL.y-0.5
			expect(world.act(Actor,rid("drill-b5"),"build",DRILL_CELL,"mine_drill").ok and int(me.inventory.mine_drill_kit)==1,"Control: drill places on B5")
		var above:String="jinguashi" if depth==1 else Mines.IDS[depth-2]
		expect(go(world,Actor,above,Mines.UP),"Stairs up from B%d"%depth)
	var record:=Survey.own_record(world.state,Actor)
	expect(record.seen.size()==15,"Seen keys 1..15 recorded")
	expect(valid(world.state.duplicate(true)),"Save with seen 1..15 validates")
	var malformed:=world.state.duplicate(true)
	malformed.mine_survey.players[Actor].seen["16"]=true
	expect(not valid(malformed),"Schema rejects survey page 16")
	me=world.state.players[Actor]
	me.x=table.x+1.5;me.y=table.y+0.5
	var samples:=int(me.inventory.get("gold_sample",0))
	var claim:=world.act(Actor,rid("claim-all"),"survey_claim",table)
	expect(claim.ok and int(world.state.players[Actor].inventory.get("gold_sample",0))==samples+1,"Fifteen pages still claim exactly one gold sample")

	# f) Beta: only B1–B5 pages, then claim.
	expect(go(world,Beta,"mine_1",Mines.ENTRY),"Beta enters B1")
	for depth in range(1,6):
		expect(observe(world,Beta,depth).ok,"Beta records B%d"%depth)
		if depth<5:expect(go(world,Beta,Mines.IDS[depth],Mines.DOWN),"Beta stairs B%d→B%d"%[depth,depth+1])
	for depth in range(5,0,-1):
		expect(go(world,Beta,"jinguashi" if depth==1 else Mines.IDS[depth-2],Mines.UP),"Beta stairs up from B%d"%depth)
	var beta:Dictionary=world.state.players[Beta]
	beta.x=table.x+1.5;beta.y=table.y+0.5
	var beta_claim:=world.act(Beta,rid("beta-claim"),"survey_claim",table)
	expect(beta_claim.ok and Survey.own_record(world.state,Beta).seen.size()==5 and int(world.state.players[Beta].inventory.get("gold_sample",0))==1,"B1–B5 pages alone claim exactly one gold sample")
	expect(not world.act(Beta,rid("beta-again"),"survey_claim",table).ok and int(world.state.players[Beta].inventory.get("gold_sample",0))==1,"No duplicate survey reward")

	# d) Legacy v26 save written before T067: unlocked 5, no mine_6..mine_15 regions.
	for region in Catalog.region_ids():legacy.regions.erase(region)
	legacy.mine_depths.erase("hoist")  # written before Q07: no hoist key
	var legacy_depths:Dictionary=legacy.mine_depths.duplicate(true)
	var file:=FileAccess.open(legacy_path,FileAccess.WRITE)
	expect(file!=null,"Write legacy fixture")
	if file!=null:
		file.store_string(JSON.stringify(legacy))
		file.close()
	var old:=World.new()
	expect(FileAccess.file_exists(legacy_path) and old.load_world(legacy_path) and old.state.players.has(Actor),"Pre-T067 v26 save loads")
	var added:=true
	for region in Catalog.region_ids():
		var layer=old.state.regions.get(region)
		added=added and layer is Dictionary and (layer.get("objects",{}) as Dictionary).is_empty() and (layer.get("crops",{}) as Dictionary).is_empty()
	expect(added and old.state.regions.size()==Regions.ALL.size()-1,"Loading adds empty mine_6..mine_15 regions")
	var loaded_depths:Dictionary=old.state.mine_depths
	expect(int(old.state.version)==26 and loaded_depths.size()==legacy_depths.size()+1 and loaded_depths.get("hoist")==false and int(loaded_depths.unlocked)==5 and int(loaded_depths.pumped)==24 and (loaded_depths.ready as Dictionary).size()==(legacy_depths.ready as Dictionary).size(),"Legacy mine_depths unchanged")
	expect(old.player_region(Actor)=="mine_5","Legacy player stays on B5")

	if failures==0:
		for file_path in [path,path+".bak",path+".tmp",legacy_path,legacy_path+".bak",legacy_path+".tmp"]:
			if FileAccess.file_exists(file_path):DirAccess.remove_absolute(file_path)
	print("MINE_DEEP_LEVELS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
