extends "res://tests/test_hand_water_journey.gd"

func craft_and_try_tiers()->void:
	if failed:return
	obtain_all({"wood":3,"fiber":2})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_sickle")
	grow_and_harvest(World.TILLER.ROW)
	deep_craft("iron_sickle")
	grow_and_harvest(World.TILLER.CROSS)
	deep_craft("precision_sickle")
	grow_and_harvest(World.TILLER.SQUARE)
	if failed:return
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and not loaded.recovered_from_backup,"Reload the precision sickle from the primary save"):return
	var restored:Dictionary=loaded.state.players[tok]
	expect(World.gathering_tool_upgrade("harvest",restored.inventory)=="precision_sickle","The last sickle survives reload")
	expect(int(restored.harvests)==int(person().harvests) and int(restored.inventory.radish)==int(bag().radish),"Harvest records and produce survive reload")

func grow_and_harvest(offsets:Array)->void:
	if failed:return
	var price:=int(World.CROPS.radish.seed_price)
	var cost:=maxi(0,offsets.size()-int(bag().get("radish_seed",0)))*price
	while int(person().coins)<cost and int(bag().get("radish",0))>0 and not failed:
		act("sell",World.Village.NPCS.xiaoli.cell,"radish")
	var center:=plant_pattern(offsets)
	if failed:return
	for offset:Vector2i in offsets:act("water",center+offset)
	wait(float(World.CROPS.radish.time)+0.1)
	walk_to(center,1.0)
	var before:=bag().duplicate(true)
	var harvests:=int(person().harvests)
	var quality:=int(bag().get("quality_radish",0))
	var guarantee:=World.has_crop_guarantee(person())
	act("harvest",center,"spread")
	if failed:return
	var expected:Dictionary={"radish":offsets.size()}
	if guarantee:expected.quality_radish=1
	expect_delta(before,expected,"The sickle grants the exact crop and quality yield without fuel")
	expect(int(person().harvests)==harvests+offsets.size(),"Each harvested plot increases the harvest count once")
	for offset:Vector2i in offsets:
		var plot:Dictionary=world.state.crops[World.key(center+offset)]
		expect(plot.kind.is_empty() and not plot.wet,"The harvested radish returns to dry soil")
	print("HAND_HARVEST_TIER id=%s cells=%d premium=%d"%[World.gathering_tool_upgrade("harvest",bag()),offsets.size(),int(bag().get("quality_radish",0))-quality])
