extends "res://tests/test_bakery_journey.gd"

func after_chapter()->void:
	super.after_chapter()
	if not failed:earn_copper_pick()
	if not failed:verify_copper_pick()
	print("COPPER_PICK_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])

func earn_copper_pick()->void:
	bk_probe("craft",bk_bench,"copper_pick","Upgrade before smelting any copper","材料不足")
	bk_gather("stone",53,["rock"])
	bk_gather("wood",16,["tree"])
	while held("copper_ore")<9 and not failed:
		bk_step(maxf(0.0,float(world.state.copper.ready)-float(world.state.time)),"restock transported copper ore")
		bk_run("mine_copper",World.COPPER_CELL)
	var stone_bench:=place_mining_station("stone_workbench",[Vector2i.ZERO,Vector2i.RIGHT])
	var smelter:=place_mining_station("small_smelter",World.INDUSTRY.SMELTER_CELLS)
	if failed:return
	expect(bk_obj(stone_bench).get("owner")==TOKEN,"Built the required stone workbench with earned materials")
	bk_craft("kiln_kit",1)
	var kiln:=place_mining_station("charcoal_kiln",[Vector2i.ZERO])
	bk_run("queue_processing",kiln,"charcoal")
	bk_step(float(World.INDUSTRY.PROCESS.charcoal.time),"make smelter fuel")
	bk_run("claim_processing",kiln)
	for _batch in range(2):bk_run("queue_processing",smelter,"copper_ingot")
	bk_step(float(World.INDUSTRY.PROCESS.copper_ingot.time)*2.0,"smelt the copper")
	for _batch in range(2):bk_run("claim_processing",smelter)
	if failed:return
	expect(held("copper_ingot")==4 and held("reinforced_pick")==1,"Smelted all metal before committing the upgrade")
	bk_craft("copper_pick",1)
	if failed:return
	expect(held("reinforced_pick")==0 and held("copper_ingot")==0,"Only the upgraded tool remains and the recipe consumed four ingots")

func place_mining_station(kind:String,footprint:Array)->Vector2i:
	if failed:return BK_NONE
	var occupied:=bk_reserved()
	var tile:=hoe_cell(occupied)
	while tile!=BK_NONE and not footprint.all(func(offset):return free_cell(tile+offset)):
		occupied[tile]=true
		tile=hoe_cell(occupied)
	expect(tile!=BK_NONE,"Found a free footprint for " + kind)
	if not failed:bk_build(tile,kind)
	return tile

func verify_copper_pick()->void:
	var rock:=find_resource("rock")
	expect(rock!=BK_NONE,"Found a natural rock to try the upgrade")
	if failed:return
	var stone_before:=held("stone")
	var result:=bk_run("pick",rock)
	expect(result.get("gather_dropped",false) and world.resource(rock)=="" and held("stone")==stone_before,"One swing broke the rock and dropped the stone on the ground")
	if failed:return
	collect_gathered(rock)
	expect(held("stone")==stone_before+5,"Walking over the drop collected the standard stone yield")
	bk_step(maxf(0.0,float(world.state.copper.ready)-float(world.state.time)),"restock the home copper point")
	bk_run("mine_copper",World.COPPER_CELL)
	if failed:return
	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Reload the earned copper pick from the primary save")
	if failed:return
	var miner:Dictionary=reopened.state.players[TOKEN]
	expect(World.active_mining_pick(miner.inventory)=="copper_pick" and miner.crafted_reinforced_pick,"The old crafting record and the upgraded pick both persist")
	# The existing deep-mine gate is tested with a separately staged B6 visit.
	var node:Vector2i=World.MINES.NODES[0]
	reopened.state.mine_depths.unlocked=6
	miner.region="mine_6"
	miner.x=node.x+0.5
	miner.y=node.y+0.5
	var strike_time:=float(reopened.state.time)
	expect(reopened.act(TOKEN,"deep-with-copper-pick","pick",node).ok,"The copper pick alone can mine in B6")
	var ready:Dictionary=reopened.state.mine_depths.ready.get("mine_6",{})
	expect(is_equal_approx(float(ready.get(World.key(node),0.0))-strike_time,9.0),"The copper pick reduced the twelve-second cooldown to nine seconds")
	expect(reopened.step(8.9,true) and not reopened.act(TOKEN,"deep-too-early","pick",node).ok,"At 8.9 seconds the node is still cooling down")
	expect(reopened.step(0.2,true) and reopened.act(TOKEN,"deep-ready","pick",node).ok,"At 9.1 seconds the node is ready again")
	expect(not World.trade_items().has("copper_pick"),"An upgraded personal pick is excluded from trade")
