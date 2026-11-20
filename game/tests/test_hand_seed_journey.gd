extends "res://tests/test_hand_water_journey.gd"

func craft_and_try_tiers()->void:
	if failed:return
	obtain_all({"resin":1,"fiber":6})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_seed_pouch")
	sow_patch(World.TILLER.ROW)
	deep_craft("iron_seed_pouch")
	sow_patch(World.TILLER.CROSS)
	deep_craft("precision_seed_pouch")
	fund_final_field()
	sow_patch(World.TILLER.SQUARE)
	if failed:return
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and not loaded.recovered_from_backup,"Reload the seed pouch and planted fields from the primary save"):return
	var resident:Dictionary=loaded.state.players[tok]
	expect(World.gathering_tool_upgrade("seed",resident.inventory)=="precision_seed_pouch","The last seed pouch survives reload")
	expect(int(resident.inventory.get("radish_seed",0))==int(bag().get("radish_seed",0)),"Seed counts survive reload")
	var own_sowings:=0
	for soil:Dictionary in loaded.state.crops.values():
		if soil.get("owner")==tok and soil.get("kind")=="radish":own_sowings+=1
	expect(own_sowings>=9,"The newly planted precision patch survives reload")

func sow_patch(offsets:Array)->void:
	if failed:return
	var stall:Vector2i=World.Village.NPCS.xiaoli.cell
	while int(bag().get("radish_seed",0))<offsets.size() and not failed:act("buy",stall,"radish")
	var center:=available_field()
	if failed:return
	for offset:Vector2i in offsets:act("hoe",center+offset)
	walk_to(center,1.0)
	var inventory_before:=bag().duplicate(true)
	var crops_before:Dictionary=world.state.crops.duplicate(true)
	act("seed",center,"spread:radish")
	if failed:return
	var expected:Array=offsets.map(func(offset):return World.key(center+offset))
	var changed:Array=[]
	for tile:String in world.state.crops:
		if world.state.crops[tile].kind!=crops_before[tile].kind:changed.append(tile)
	changed.sort()
	expected.sort()
	expect_same(changed,expected,"Sowing changes only the intended %d cells"%offsets.size())
	expect_delta(inventory_before,{"radish_seed":-offsets.size()},"Every successful cell consumes one seed and no fuel")
	print("HAND_SEED_TIER id=%s cells=%d"%[World.gathering_tool_upgrade("seed",bag()),offsets.size()])
	for offset:Vector2i in offsets:act("water",center+offset)
