extends "res://tests/test_material_source_journey.gd"
## Starts with normal supplies. Reuses earned gathering/BFS/processing/reload
## journey, then mines real copper and crafts a pump with no inventory writes.
func reload_final()->void:
	super.reload_final()
	if failed:return
	var before:Dictionary=bag().duplicate(true)
	var before_box:Dictionary=box_items().duplicate(true)
	var old_trees:=trees
	var old_rocks:=rocks
	var pick:Dictionary=World.CRAFT.reinforced_pick.ingredients
	var joint:Dictionary=World.CRAFT.copper_joint.ingredients
	var pump:Dictionary=World.CRAFT.pump_kit.ingredients
	gather("wood",int(pick.wood)+2*int(joint.wood),"tree")
	gather("stone",int(pick.stone),"rock")
	if failed:return
	must("craft",bench,"reinforced_pick","craft reinforced pick from earned resources")
	if failed:return
	expect(held("reinforced_pick")==1 and person().get("crafted_reinforced_pick",false),"Earned pick unlocks original copper action")
	var copper0:=held("copper_ore")
	must("pick",World.COPPER_CELL,"","mine actual transported practice ore at dock")
	expect(held("copper_ore")==copper0+2,"First real copper yield is two")
	var cooling:=doact("pick",World.COPPER_CELL)
	expect(not cooling.ok and held("copper_ore")==copper0+2,"Copper cooldown cannot be skipped")
	expect(world.step(12.0,true),"Advance actual copper replenishment")
	sim_seconds+=12.0
	must("pick",World.COPPER_CELL,"","mine second real copper batch")
	expect(held("copper_ore")==copper0+4,"All four copper units were earned at real source")
	for index in 2:must("craft",bench,"copper_joint","craft earned copper joint %d"%index)
	var old_pumps:=held("pump_kit")
	must("craft",bench,"pump_kit","craft pump from earned boards, charcoal and copper joints")
	if failed:return
	expect(held("pump_kit")==old_pumps+int(World.CRAFT.pump_kit.yield),"Earned workshop pipeline ends with original pump kit")
	expect(same(box_items(),before_box),"Extra stage never silently consumes adjacent chest")
	expect(int(before.get("wood",0))+6*(trees-old_trees)==held("wood")+int(pick.wood)+2*int(joint.wood),"Additional wood has a complete earned/spent ledger")
	expect(int(before.get("stone",0))+5*(rocks-old_rocks)==held("stone")+int(pick.stone),"Additional stone has a complete earned/spent ledger")
	expect(int(before.get("plank",0))==held("plank")+int(pump.plank) and int(before.get("charcoal",0))==held("charcoal")+int(pump.charcoal),"Pump consumes exactly its original processed ingredients")
	var path:=world.save_path
	var earned:Dictionary=bag().duplicate(true)
	var reloaded:=World.new()
	expect(reloaded.load_world(path),"Earned pump save reloads")
	reloaded.add_player(TOKEN,"Island")
	world=reloaded
	expect(same(bag(),earned),"Earned pump and remaining inventory persist")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="):
			var output:=arg.trim_prefix("--qa-output=")
			expect(DirAccess.copy_absolute(path,output)==OK,"Export earned save copy for native visual check")
	print("EARNED_PUMP_JOURNEY passed=%s actions=%d walk_tiles=%d trees=%d rocks=%d pump_kits=%d bench=%s"%[not failed,actions,walking,trees,rocks,held("pump_kit"),bench])
