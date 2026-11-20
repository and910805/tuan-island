extends "res://tests/test_mine_freight_journey.gd"

const POTATO_PLOT := Vector2i(41,35)
const HOME_STOVE := Vector2i(40,34)
const HOME_BENCH := GARDEN_JOURNEY_BENCH
const HOME_MILL := Vector2i(40,36)

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	act("harvest",POTATO_PLOT)
	act("cook",HOME_STOVE,"baked_potato")
	expect(world.step(World.RECIPES.baked_potato.time,true),"Real potatoes bake at the original stove")
	act("claim_cook",HOME_STOVE)
	gather("wood","tree","axe",4,3)
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	var sites := World.BOBO_WORKSHOP.sites(world.state)
	act("quest",sites.npc,"bobo:2")
	expect(int(person().stories.bobo)==3 and World.Village.unlocked(person(),"ore_display"),"Completed freight unlocks the display plan")
	checkpoint("bobo-blueprint")
	var display := find_display_cell(sites.npc)
	expect(display != Vector2i(-1,-1),"A reachable display site near Bobo exists")
	if failed:return
	act("build",display,"ore_display")
	expect(world.region_snapshot("jinguashi").objects[World.key(display)].owner==TOKEN,"Resident places their own display near Bobo")
	checkpoint("bobo-display")
	act("quest",sites.npc,"bobo:3")
	expect(int(person().stories.bobo)==4 and int(bag().get("baked_potato",0))==1,"Bobo shares one baked potato and completes the story")
	checkpoint("bobo-complete")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup and reopened.player_region(TOKEN)=="jinguashi" and int(reopened.state.players[TOKEN].stories.bobo)==4 and reopened.state.bobo_workshop.done.get(TOKEN,false) and reopened.state.regions.jinguashi.objects[World.key(display)].type=="ore_display","Workshop, four quest stages and display survive primary-save reload")
	print("BOBO_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f"%[actions,walking,world.state.time])

func checkpoint(stage: String) -> void:
	super.checkpoint(stage)
	if failed:return
	if stage=="mine-prepared":
		prepare_bobo_story()
	elif stage=="freight-crafted":
		sort_bobo_samples()

func prepare_bobo_story() -> void:
	gather("wood","tree","axe",16,3)
	mill_batch(HOME_MILL)
	act("craft",HOME_BENCH,"copper_joint")
	act("buy",World.Village.NPCS.xiaoli.cell,"potato")
	act("seed",POTATO_PLOT,"potato")
	act("water",POTATO_PLOT)
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	var sites := World.BOBO_WORKSHOP.sites(world.state)
	checkpoint("bobo-first-meeting")
	act("quest",sites.npc,"bobo:0")
	expect(int(person().stories.bobo)==1 and int(bag().plank)==6 and int(bag().copper_joint)==2,"Bobo accepts real boards and a copper joint without taking the mine repair reserve")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")

func sort_bobo_samples() -> void:
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	var sites := World.BOBO_WORKSHOP.sites(world.state)
	var ore := int(bag().get("gold_ore",0))
	var samples := int(bag().get("gold_sample",0))
	act("bobo_sort_start",sites.table)
	expect(int(bag().gold_ore)==ore-3,"Sorting reserves three naturally mined units")
	if failed:return
	actions += 1
	var wrong := world.act(TOKEN,"journey-%d"%actions,"bobo_sort_answer",sites.table,"0:small")
	print("%d bobo_sort_answer %s 0:small | %s" % [actions,sites.table,wrong.message])
	expect(not wrong.ok and int(world.state.bobo_workshop.jobs[TOKEN].step)==0 and int(bag().gold_ore)==ore-3,"Wrong bin retains material and lets the same round retry")
	act("bobo_sort_answer",sites.table,"0:large")
	checkpoint("bobo-sorting")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup and int(reopened.state.bobo_workshop.jobs[TOKEN].step)==1,"Leaving and reopening preserves the unfinished sort")
	if failed:return
	world=reopened
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	sites=World.BOBO_WORKSHOP.sites(world.state)
	act("bobo_sort_answer",sites.table,"1:medium")
	act("bobo_sort_answer",sites.table,"2:small")
	checkpoint("bobo-claim-ready")
	act("bobo_sort_claim",sites.table)
	expect(world.state.bobo_workshop.done.get(TOKEN,false) and int(bag().gold_sample)==samples+1,"Only finishing and claiming awards the collection sample")
	act("quest",sites.npc,"bobo:1")
	expect(int(person().stories.bobo)==2,"Bobo acknowledges claimed sample before freight dispatch")
	checkpoint("bobo-sorted")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")

func find_display_cell(npc: Vector2i) -> Vector2i:
	var local_world := World.new()
	local_world.state=world.region_snapshot("jinguashi")
	local_world._region="jinguashi"
	for distance in range(1,5):
		for y in range(npc.y-distance,npc.y+distance+1):
			for x in range(npc.x-distance,npc.x+distance+1):
				var cell := Vector2i(x,y)
				if maxi(absi(x-npc.x),absi(y-npc.y))!=distance:continue
				if local_world.protected(cell) or local_world.water(cell) or local_world.resource(cell)!="":continue
				if local_world.state.objects.has(World.key(cell)) or local_world.state.crops.has(World.key(cell)):continue
				if not route(cell).is_empty():return cell
	return Vector2i(-1,-1)
