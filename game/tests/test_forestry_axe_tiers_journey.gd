extends "res://tests/test_mining_pick_tiers_journey.gd"

func craft_and_try_tiers()->void:
	if failed:return
	cut_tree(find_resource("tree"),3,0)
	obtain_all({"wood":3,"fiber":2})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_axe")
	var planted:=grow_hardwood_tree()
	if failed:return
	cut_tree(planted,2,2)
	deep_craft("iron_axe")
	if failed:return
	expect(int(bag().get("copper_axe",0))==0,"The iron axe upgrade consumes the copper axe")
	cut_tree(find_resource("tree"),1,0)
	deep_craft("precision_axe")
	if failed:return
	expect(int(bag().get("iron_axe",0))==0,"The precision axe upgrade consumes the iron axe")
	cut_tree(find_resource("tree"),1,0)
	planted=grow_hardwood_tree()
	cut_tree(planted,1,3)
	if failed:return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"Reload the earned forestry upgrades from the main save"):return
	var restored:Dictionary=reloaded.state.players[tok].inventory
	expect(World.gathering_tool_upgrade("axe",restored)=="precision_axe" and int(restored.get("hardwood",0))==3,"The best axe and three harvested hardwood pieces persist")
	for id:String in World.FORESTRY_AXES:
		expect(not World.trade_items().has(id),"The personal axe is excluded from trade: " + id)

func grow_hardwood_tree()->Vector2i:
	var site:=open_square_site()
	if not expect(site.x>=0 and world.tree_planting_problem(tok,site).is_empty(),"Find a reachable site and an earned sapling"):return site
	act("plant_tree",site)
	wait(float(World.TREE_TIME)+0.1)
	expect(world.state.forest.get(World.key(site),{}).get("mature",false),"The planted tree grew to maturity")
	return site

func cut_tree(site:Vector2i,swings:int,hardwood:int)->void:
	if failed:return
	if not expect(site.x>=0 and world.resource(site)=="tree","Find a tree to try the axe"):return
	var initial:=bag().duplicate(true)
	for hit in swings:
		var result:=act("axe",site)
		if failed:return
		var final_swing:=hit==swings-1
		if not expect(bool(result.get("gather_dropped",false))==final_swing,"Wood drops on swing %d of %d"%[hit+1,swings]):return
		if not final_swing:expect_same(bag(),initial,"Partial damage earns no wood")
	var yield_items:Dictionary={"wood":6,"fiber":2,"sapling":1,"resin":1}
	if hardwood>0:yield_items.hardwood=hardwood
	expect_delta(initial,yield_items,"Axe harvest yields the public drop, picked up once")
	print("FORESTRY_AXE_TIER id=%s swings=%d hardwood=%d"%[World.gathering_tool_upgrade("axe",bag()),swings,hardwood])
