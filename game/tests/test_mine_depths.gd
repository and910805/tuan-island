extends SceneTree
const World=preload("res://scripts/world.gd")
const Mines=World.MINES
const Actor="miner"
var checks:=0
var failures:=0

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func place(world:World,p:Vector2i)->void:
	world.state.players[Actor].x=p.x-0.5
	world.state.players[Actor].y=p.y+0.5

func go(world:World,target:String,cell:Vector2i)->bool:
	place(world,cell)
	return world.act(Actor,"go-"+str(checks),"mine_travel",cell,target).ok and world.player_region(Actor)==target

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("depths-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var world:=World.new()
	world.save_path=path
	world.add_player(Actor,"Miner")
	var p:Dictionary=world.state.players[Actor]
	p.region="jinguashi"
	p.inventory.merge({"reinforced_pick":1,"plank":6,"copper_joint":2,"stone":8},true)
	world.state.picnic=true
	expect(not world.act(Actor,"remote-entry","mine_travel",Mines.ENTRY,"mine_1").ok,"Cannot enter from distant spawn")
	expect(go(world,"mine_1",Mines.ENTRY),"Enter first actual mine region")
	expect(not go(world,"mine_3",Mines.DOWN) and world.player_region(Actor)=="mine_1","Cannot skip levels")
	expect(not go(world,"mine_2",Mines.DOWN),"Next level blocked before commission")
	for index in range(4):
		var region:String=Mines.IDS[index]
		place(world,Mines.SERVICE)
		if index==2:
			var objects:Dictionary=world.state.regions[region].objects
			objects["29,23"]={"type":"water_pump","owner":Actor,"items":{},"enabled":true}
			objects["30,23"]={"type":"water_pipe","owner":Actor,"items":{}}
			objects["31,23"]={"type":"water_tank","owner":Actor,"items":{},"water":48}
			expect(not world.act(Actor,"manual","mine_commission",Mines.SERVICE).ok and world.state.mine_depths.pumped==0,"Hand-filled tank does not qualify")
			expect(world.step(8,true) and world.state.mine_depths.pumped==0,"Full tank has no qualifying positive flow")
			objects["31,23"].water=0
			objects["29,23"].enabled=false
			expect(world.step(8,true) and world.state.mine_depths.pumped==0,"Disabled pump has no qualifying flow")
			objects["29,23"].enabled=true
			objects["30,23"].owner="other"
			expect(world.step(8,true) and world.state.mine_depths.pumped==0,"Another owner's pipe cannot connect the pump and tank")
			objects["30,23"].owner=Actor
			var dry:=world.state.duplicate(true)
			world.save_path=path.path_join("missing").path_join("file")
			expect(not world.step(8,true) and world.state==dry,"Failed pump tick rolls back the water and shared evidence")
			world.save_path=path
			expect(world.step(8,true) and world.step(8,true) and world.step(8,true) and world.state.mine_depths.pumped==24,"Actual pump and connected tank collect 24")
		var request:="commission-%d"%index
		var before:=world.state.duplicate(true)
		world.save_path=path.path_join("missing").path_join("file")
		expect(not world.act(Actor,request,"mine_commission",Mines.SERVICE).ok and world.state==before,"Commission save failure rolls back")
		world.save_path=path
		var result:=world.act(Actor,request,"mine_commission",Mines.SERVICE)
		expect(result.ok and world.state.mine_depths.unlocked==index+2 and world.act(Actor,request,"mine_commission",Mines.SERVICE)==result,"Project unlock and replay settle exactly once")
		expect(go(world,Mines.IDS[index+1],Mines.DOWN),"Walkable route enters next unlocked level")
	var node:Vector2i=Mines.NODES[0]
	place(world,node)
	p=world.state.players[Actor]
	p.mine_energy=10
	var mined:=world.act(Actor,"gold","mine_extract",node)
	expect(mined.ok and p.inventory.gold_ore==2 and p.inventory.reinforced_pick==1 and p.mine_energy==100 and Vector2(p.x,p.y)==Vector2(Mines.REST)+Vector2(0.5,0.5),"Exhaustion returns to local rest without losing tools or ore")
	place(world,node)
	expect(not world.act(Actor,"cooldown","pick",node).ok and world.act(Actor,"gold","mine_extract",node)==mined,"Shared cooldown and replay prevent extra payout")
	var reload:=World.new()
	expect(reload.load_world(path) and reload.state.version==26 and reload.state.mine_depths.unlocked==5 and reload.player_region(Actor)=="mine_5","Depth, energy and resources persist")
	expect((reload.island_project_mask() & 32)!=0,"Fifth-floor access appears in island news after reload")
	var schema=preload("res://scripts/save_schema.gd")
	var invalid:=reload.state.duplicate(true)
	invalid.mine_depths=[]
	expect(not schema.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Malformed depth record rejected without accessing its fields")
	expect(int(reload.state.players[Actor].inventory.get("crystal_sand",0))==1,"One crystal sand survives replay and restart")
	var second:Vector2i=Mines.NODES[1]
	place(reload,second)
	expect(reload.act(Actor,"second-ore","mine_extract",second).ok,"Mine a second deep deposit")
	expect(int(reload.state.players[Actor].inventory.get("crystal_sand",0))==2,"Second deposit yields the remaining sand for glass")
	var fungus_plot:=Vector2i(30,21)
	place(reload,fungus_plot)
	var miner:Dictionary=reload.state.players[Actor]
	miner.inventory["star_mushroom_seed"]=1
	expect(reload.act(Actor,"fungus-bed","hoe",fungus_plot).ok,"Prepare a fifth-layer mushroom bed")
	expect(reload.act(Actor,"fungus-seed","seed",fungus_plot,"star_mushroom").ok,"Plant mushroom spawn in the cave")
	expect(reload.act(Actor,"fungus-water","water",fungus_plot).ok,"Water the cave bed")
	expect(reload.step(float(World.CROPS.star_mushroom.time),true),"Grow the cave mushrooms")
	expect(reload.act(Actor,"fungus-harvest","harvest",fungus_plot).ok and miner.inventory.get("star_mushroom",0)==2,"Harvest two mushrooms from one spawn")
	for index in range(4,-1,-1):
		var destination: String = "jinguashi" if index==0 else Mines.IDS[index-1]
		expect(go(reload,destination,Mines.UP),"Free upward route at depth %d"%(index+1))
	expect(reload.state.players[Actor].inventory.gold_ore==4,"Return keeps personal inventory")
	var legacy:=reload.state.duplicate(true)
	legacy.version=5;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:legacy.regions.erase(region)
	for region in World.TRANSIT.TEA_STOPS:legacy.regions.erase(region)
	for region in World.TRANSIT.LOCAL:legacy.regions.erase(region)
	legacy.erase("mine_depths")
	for region in Mines.IDS:legacy.regions.erase(region)
	legacy.players[Actor].erase("mine_energy")
	expect(schema.validate(legacy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME) and legacy.version==26 and legacy.mine_depths==Mines.fresh() and legacy.players[Actor].inventory.gold_ore==4 and legacy.regions.size()==World.REGIONS.ALL.size()-1,"Version five migrates to all current regions and keeps existing inventory")
	for region in World.REGIONS.ALL:
		var layer:Dictionary=reload.state if region=="home" else reload.state.regions[region]
		layer.crops["13,20"]={"kind":"radish","wet":false,"growth":0.0,"remaining":1,"owner":Actor}
		layer.objects["13,21"]={"type":"sprinkler","owner":Actor,"items":{},"water":1,"enabled":true,"next_water":0.0,"last_water":-1.0}
	var before_tick:=reload.state.duplicate(true)
	reload.save_path=path.path_join("missing").path_join("file")
	expect(not reload.step(1,true) and reload.state==before_tick,"All eight region ticks and the clock roll back as one save")
	reload.save_path=path
	expect(reload.step(1,true) and reload.state.time==before_tick.time+1,"Clock advances exactly once across eight regions")
	var watered:=true
	for region in World.REGIONS.ALL:
		var layer:Dictionary=reload.state if region=="home" else reload.state.regions[region]
		watered=watered and layer.crops["13,20"].wet
	expect(watered,"Every region ran its real sprinkler step")
	for region in World.REGIONS.ALL:
		var layer:Dictionary=reload.state if region=="home" else reload.state.regions[region]
		layer.crops.erase("13,20")
		layer.objects.erase("13,21")
	var gate:=Vector2i(11,20)
	place(reload,gate)
	expect(reload.act(Actor,"return-home","transit",gate,"home").ok,"Return from Jinguashi with mined sand")
	var bench:=Vector2i(40,33)
	place(reload,bench)
	var supplies:Dictionary=reload.state.players[Actor].inventory
	# Only ordinary prerequisite materials are supplied by the fixture.
	supplies.merge({"wood":30,"stone":15,"charcoal":1,"copper_joint":1,"pumpkin_seed":1},true)
	expect(reload.act(Actor,"bench","build",bench,"bench").ok,"Build the home workbench")
	expect(not supplies.has("glass"),"No finished glass in the fixture")
	expect(reload.act(Actor,"glass","craft",bench,"glass").ok,"Craft two glass from mined sand and charcoal")
	expect(int(supplies.get("glass",0))==2 and int(supplies.get("crystal_sand",0))==0 and int(supplies.get("charcoal",0))==0,"Craft consumes exact materials")
	var field:=Vector2i(40,34)
	for work in [["hoe",""],["seed","pumpkin"],["water",""],["build","greenhouse_roof"]]:
		expect(reload.act(Actor,"field-"+work[0],work[0],field,work[1]).ok,"Prepare greenhouse plot: "+work[0])
	expect(int(supplies.get("glass",0))==0 and int(supplies.get("copper_joint",0))==0,"Greenhouse consumes both glass panes and the joint")
	expect(reload.step(float(World.CROPS.pumpkin.time),true),"Advance the watered greenhouse crop")
	expect(reload.act(Actor,"pumpkin","harvest",field).ok and int(supplies.get("pumpkin",0))==1,"Harvest autumn pumpkin in a spring greenhouse")
	var uncovered:=field+Vector2i.DOWN
	expect(reload.act(Actor,"open-field","hoe",uncovered).ok,"Prepare bare soil alongside the greenhouse")
	var rain := 2.0 * World.WEATHER.DAY_SECONDS
	expect(reload.step(rain-float(reload.state.time),true),"Advance to the first rainy morning")
	expect(not reload.state.crops[World.key(field)].wet and reload.state.crops[World.key(uncovered)].wet,"Rain wets bare soil, while glass keeps the covered plot dry")
	var garden:=World.LANYANG_LIFE.SERVICE
	expect(not reload.act(Actor,"report-home","greenhouse_report",garden).ok,"Reporting requires the actual gardener's region")
	reload.state.players[Actor].region="lanyang"
	place(reload,garden)
	var report:=reload.act(Actor,"report","greenhouse_report",garden)
	expect(report.ok and reload.act(Actor,"report","greenhouse_report",garden)==report,"Report once with an idempotent receipt")
	expect(not reload.act(Actor,"report-again","greenhouse_report",garden).ok,"A second report is refused")
	var finished := World.new()
	var read := finished.load_world(path)
	var journal: Dictionary = finished.state.players.get(Actor,{})
	expect(journal.get("greenhouse_reported",false) and journal.get("greenhouse_glass_crafted",false) and journal.get("greenhouse_cross_season_crop","")=="pumpkin","Winter letter progress survives restart")

	expect(read and not finished.recovered_from_backup and finished.state.roofs.get(World.key(field),{}).get("type")=="greenhouse_roof" and finished.state.players[Actor].inventory.get("pumpkin",0)==1,"Built roof and harvest persist together")
	if failures==0:
		for file in [path,path+".bak"]:DirAccess.remove_absolute(file)
	print("MINE_DEPTHS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
